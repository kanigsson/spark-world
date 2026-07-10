with Inflate.Raw;
with Inflate.CRC32;

package body Inflate.ZIP with SPARK_Mode => On is

   use Interfaces;

   --  Little-endian reads at an offset from A'First. The preconditions
   --  are what every call site has just bounds-checked.

   function RD16 (A : Byte_Array; Off : Natural) return Natural is
     (Natural (A (A'First + Off))
      + 256 * Natural (A (A'First + Off + 1)))
   with
     Global => null,
     Pre    => A'Length >= 2 and then Off <= A'Length - 2,
     Post   => RD16'Result <= 16#FFFF#;

   function RD32 (A : Byte_Array; Off : Natural) return Word32 is
     (Word32 (A (A'First + Off))
      or Shift_Left (Word32 (A (A'First + Off + 1)), 8)
      or Shift_Left (Word32 (A (A'First + Off + 2)), 16)
      or Shift_Left (Word32 (A (A'First + Off + 3)), 24))
   with
     Global => null,
     Pre    => A'Length >= 4 and then Off <= A'Length - 4;

   --  Record signatures ("PK" plus a type pair)
   function Has_Signature
     (A : Byte_Array; Off : Natural; S3, S4 : Byte) return Boolean
   is
     (A (A'First + Off) = 16#50#
      and then A (A'First + Off + 1) = 16#4B#
      and then A (A'First + Off + 2) = S3
      and then A (A'First + Off + 3) = S4)
   with
     Global => null,
     Pre    => A'Length >= 4 and then Off <= A'Length - 4;

   End_Record_Size    : constant := 22;  --  EOCD without the comment
   Central_Entry_Size : constant := 46;  --  fixed part of a central entry
   Local_Header_Size  : constant := 30;  --  fixed part of a local header

   ----------
   -- Open --
   ----------

   procedure Open
     (Archive : in     Byte_Array;
      C       :    out Cursor;
      Count   :    out Natural;
      Status  :    out Status_Type)
   is
      Pos       : Natural;  --  candidate EOCD offset from Archive'First
      Found     : Boolean := False;
      CD_Offset : Word32;
      CD_Size   : Word32;
   begin
      C      := (others => 0);
      Count  := 0;

      if Archive'Length < End_Record_Size then
         Status := ZIP_No_End_Record;
         return;
      end if;

      --  The EOCD sits at the very end, except for a comment of up to
      --  65535 bytes whose length it declares — scan backward and accept
      --  the first candidate whose declared comment length closes the
      --  archive exactly.
      Pos := Archive'Length - End_Record_Size;
      loop
         pragma Loop_Invariant (Pos <= Archive'Length - End_Record_Size);
         pragma Loop_Variant (Decreases => Pos);
         if Has_Signature (Archive, Pos, 16#05#, 16#06#)
           and then RD16 (Archive, Pos + 20) = Archive'Length - End_Record_Size - Pos
         then
            Found := True;
            exit;
         end if;
         exit when Pos = 0
           or else Archive'Length - End_Record_Size - Pos >= 16#FFFF#;
         Pos := Pos - 1;
      end loop;
      if not Found then
         Status := ZIP_No_End_Record;
         return;
      end if;

      --  Multi-disk archives died with floppies; the ZIP64 marker values
      --  flag sizes this 32-bit walker must not reinterpret.
      if RD16 (Archive, Pos + 4) /= 0          --  this disk
        or else RD16 (Archive, Pos + 6) /= 0   --  central directory disk
        or else RD16 (Archive, Pos + 8) /= RD16 (Archive, Pos + 10)
      then
         Status := ZIP_Unsupported;
         return;
      end if;
      Count     := RD16 (Archive, Pos + 10);
      CD_Size   := RD32 (Archive, Pos + 12);
      CD_Offset := RD32 (Archive, Pos + 16);
      if Count = 16#FFFF#
        or else CD_Size = 16#FFFF_FFFF#
        or else CD_Offset = 16#FFFF_FFFF#
      then
         Status := ZIP_Unsupported;
         return;
      end if;

      --  The central directory must lie between the archive start and the
      --  EOCD record, and its declared size must be large enough for the
      --  declared number of fixed-size entry headers.
      if CD_Offset > Word32 (Pos)
        or else CD_Size > Word32 (Pos) - CD_Offset
        or else (Count = 0 and then CD_Size /= 0)
        or else Count > Natural (CD_Size) / Central_Entry_Size
      then
         Status := ZIP_Bad_Central_Entry;
         return;
      end if;

      C      := (Offset            => Natural (CD_Offset),
                 Limit             => Natural (CD_Offset + CD_Size),
                 First             => Natural (CD_Offset),
                 End_Record_Offset => Pos,
                 Remaining         => Count);
      Status := OK;
   end Open;

   ----------
   -- Next --
   ----------

   procedure Next
     (Archive : in     Byte_Array;
      C       : in out Cursor;
      E       :    out Entry_Info;
      Status  :    out Status_Type)
   is
      Name_Len, Extra_Len, Comment_Len : Natural;
   begin
      E := (Name_First_Value  => 1,
            Name_Last_Value   => 0,
            Method_Value      => 0,
            Flags_Value       => 0,
            CRC_Value         => 0,
            Comp_Size_Value   => 0,
            Uncomp_Size_Value => 0,
            Local_Offset      => 0,
            Central_Offset    => 0,
            Central_First     => 0,
            Central_Limit     => 0,
            End_Record_Offset => 0);

      if C.Offset > C.Limit
        or else C.Limit > Archive'Length
        or else C.Limit - C.Offset < Central_Entry_Size
        or else not Has_Signature (Archive, C.Offset, 16#01#, 16#02#)
      then
         Status := ZIP_Bad_Central_Entry;
         C.Remaining := 0;
         return;
      end if;

      E.Flags_Value       := RD16 (Archive, C.Offset + 8);
      E.Method_Value      := RD16 (Archive, C.Offset + 10);
      E.CRC_Value         := RD32 (Archive, C.Offset + 16);
      E.Comp_Size_Value   := RD32 (Archive, C.Offset + 20);
      E.Uncomp_Size_Value := RD32 (Archive, C.Offset + 24);
      Name_Len       := RD16 (Archive, C.Offset + 28);
      Extra_Len      := RD16 (Archive, C.Offset + 30);
      Comment_Len    := RD16 (Archive, C.Offset + 32);
      E.Local_Offset := RD32 (Archive, C.Offset + 42);

      if RD16 (Archive, C.Offset + 34) /= 0 then  --  disk number start
         Status := ZIP_Unsupported;
         C.Remaining := 0;
         return;
      end if;
      if E.Comp_Size_Value = 16#FFFF_FFFF#
        or else E.Uncomp_Size_Value = 16#FFFF_FFFF#
        or else E.Local_Offset = 16#FFFF_FFFF#
      then
         Status := ZIP_Unsupported;
         C.Remaining := 0;
         return;
      end if;

      if Name_Len + Extra_Len + Comment_Len >
        C.Limit - C.Offset - Central_Entry_Size
      then
         Status := ZIP_Bad_Central_Entry;
         C.Remaining := 0;
         return;
      end if;

      E.Name_First_Value  := Archive'First + C.Offset + Central_Entry_Size;
      E.Name_Last_Value   := E.Name_First_Value - 1 + Name_Len;
      E.Central_Offset    := C.Offset;
      E.Central_First     := C.First;
      E.Central_Limit     := C.Limit;
      E.End_Record_Offset := C.End_Record_Offset;

      C.Offset    := C.Offset + Central_Entry_Size
                       + Name_Len + Extra_Len + Comment_Len;
      C.Remaining := C.Remaining - 1;
      if (C.Remaining = 0 and then C.Offset /= C.Limit)
        or else (C.Remaining > 0
                 and then C.Remaining >
                   (C.Limit - C.Offset) / Central_Entry_Size)
      then
         Status := ZIP_Bad_Central_Entry;
         C.Remaining := 0;
         return;
      end if;
      Status      := OK;
   end Next;

   -------------
   -- Extract --
   -------------

   procedure Extract
     (Archive  : in     Byte_Array;
      E        : in     Entry_Info;
      Output   : in out Byte_Array;
      Produced :    out Natural;
      Status   :    out Status_Type)
   is
      LO         : Natural;
      Data_Start : Natural;
      CSize      : Natural;
      Consumed   : Natural;
   begin
      Produced := 0;

      --  Re-read the EOCD and central entry identified by this opaque
      --  descriptor. This both binds E to Archive and ensures that none of
      --  the metadata used below is merely trusted caller state.
      if E.End_Record_Offset > Archive'Length
        or else Archive'Length - E.End_Record_Offset < End_Record_Size
        or else not Has_Signature
          (Archive, E.End_Record_Offset, 16#05#, 16#06#)
        or else RD16 (Archive, E.End_Record_Offset + 20) /=
          Archive'Length - End_Record_Size - E.End_Record_Offset
        or else RD16 (Archive, E.End_Record_Offset + 4) /= 0
        or else RD16 (Archive, E.End_Record_Offset + 6) /= 0
        or else RD16 (Archive, E.End_Record_Offset + 8) /=
          RD16 (Archive, E.End_Record_Offset + 10)
        or else E.Central_First > E.Central_Limit
        or else E.Central_Limit > E.End_Record_Offset
        or else RD32 (Archive, E.End_Record_Offset + 16) /=
          Word32 (E.Central_First)
        or else RD32 (Archive, E.End_Record_Offset + 12) /=
          Word32 (E.Central_Limit - E.Central_First)
      then
         Status := ZIP_Bad_Central_Entry;
         return;
      end if;

      if E.Central_Offset < E.Central_First
        or else E.Central_Offset > E.Central_Limit
        or else E.Central_Limit - E.Central_Offset < Central_Entry_Size
        or else not Has_Signature
          (Archive, E.Central_Offset, 16#01#, 16#02#)
        or else RD16 (Archive, E.Central_Offset + 34) /= 0
        or else RD16 (Archive, E.Central_Offset + 28)
                    + RD16 (Archive, E.Central_Offset + 30)
                    + RD16 (Archive, E.Central_Offset + 32) >
          E.Central_Limit - E.Central_Offset - Central_Entry_Size
      then
         Status := ZIP_Bad_Central_Entry;
         return;
      end if;

      if E.Name_First_Value /=
           Archive'First + E.Central_Offset + Central_Entry_Size
        or else E.Name_Last_Value /= E.Name_First_Value - 1
          + RD16 (Archive, E.Central_Offset + 28)
        or else E.Flags_Value /= RD16 (Archive, E.Central_Offset + 8)
        or else E.Method_Value /= RD16 (Archive, E.Central_Offset + 10)
        or else E.CRC_Value /= RD32 (Archive, E.Central_Offset + 16)
        or else E.Comp_Size_Value /= RD32 (Archive, E.Central_Offset + 20)
        or else E.Uncomp_Size_Value /= RD32 (Archive, E.Central_Offset + 24)
        or else E.Local_Offset /= RD32 (Archive, E.Central_Offset + 42)
      then
         Status := ZIP_Bad_Central_Entry;
         return;
      end if;

      if E.Flags_Value mod 2 /= 0 then  --  bit 0: encrypted
         Status := ZIP_Unsupported;
         return;
      end if;

      --  Validate the local header the offset points at
      if E.Local_Offset > Word32 (E.Central_First)
        or else E.Central_First - Natural (E.Local_Offset) < Local_Header_Size
      then
         Status := ZIP_Bad_Local_Header;
         return;
      end if;
      LO := Natural (E.Local_Offset);
      if not Has_Signature (Archive, LO, 16#03#, 16#04#) then
         Status := ZIP_Bad_Local_Header;
         return;
      end if;

      --  The local name must match the central name. The extra field may
      --  differ, but its length still determines where the data starts.
      declare
         L_Name  : constant Natural := RD16 (Archive, LO + 26);
         L_Extra : constant Natural := RD16 (Archive, LO + 28);
         C_Name  : constant Natural :=
           E.Name_Last_Value - (E.Name_First_Value - 1);
      begin
         if L_Name + L_Extra >
           E.Central_First - LO - Local_Header_Size
           or else L_Name /= C_Name
           or else RD16 (Archive, LO + 6) /= E.Flags_Value
           or else RD16 (Archive, LO + 8) /= E.Method_Value
         then
            Status := ZIP_Bad_Local_Header;
            return;
         end if;
         Data_Start := LO + Local_Header_Size + L_Name + L_Extra;

         if L_Name > 0
           and then Archive
             (Archive'First + LO + Local_Header_Size ..
              Archive'First + LO + Local_Header_Size + L_Name - 1) /=
             Archive (E.Name_First_Value .. E.Name_Last_Value)
         then
            Status := ZIP_Bad_Local_Header;
            return;
         end if;
      end;

      --  Without a data descriptor, CRC and sizes belong in both headers.
      --  A 0xFFFFFFFF local size is also accepted for the small-file
      --  force-ZIP64 form whose central record still has classic sizes.
      if (E.Flags_Value / 8) mod 2 = 0
        and then
          (RD32 (Archive, LO + 14) /= E.CRC_Value
           or else (RD32 (Archive, LO + 18) /= E.Comp_Size_Value
                    and then RD32 (Archive, LO + 18) /= 16#FFFF_FFFF#)
           or else (RD32 (Archive, LO + 22) /= E.Uncomp_Size_Value
                    and then RD32 (Archive, LO + 22) /= 16#FFFF_FFFF#))
      then
         Status := ZIP_Bad_Local_Header;
         return;
      end if;

      if E.Comp_Size_Value > Word32 (E.Central_First - Data_Start) then
         Status := ZIP_Bad_Local_Header;
         return;
      end if;
      CSize := Natural (E.Comp_Size_Value);

      case E.Method_Value is
         when 0 =>
            --  Stored: the two sizes must agree and the bytes are literal
            if E.Comp_Size_Value /= E.Uncomp_Size_Value then
               Status := ZIP_Bad_Central_Entry;
               return;
            end if;
            if CSize > Output'Length then
               Status := Output_Too_Small;
               return;
            end if;
            if CSize > 0 then
               Output (Output'First .. Output'First - 1 + CSize) :=
                 Archive (Archive'First + Data_Start ..
                          Archive'First - 1 + Data_Start + CSize);
            end if;
            Produced := CSize;

         when 8 =>
            Raw.Decompress
              (Archive (Archive'First + Data_Start ..
                        Archive'First - 1 + Data_Start + CSize),
               Output, Consumed, Produced, Status);
            if Status /= OK then
               return;
            end if;
            --  The deflate stream must fill the declared sizes exactly
            if Consumed /= CSize
              or else Word32 (Produced) /= E.Uncomp_Size_Value
            then
               Status := ZIP_Length_Mismatch;
               return;
            end if;

         when others =>
            Status := ZIP_Unsupported;
            return;
      end case;

      if CRC32.Compute (Output (Output'First .. Output'First - 1 + Produced))
        /= E.CRC_Value
      then
         Status := ZIP_Checksum_Mismatch;
         return;
      end if;

      Status := OK;
   end Extract;

end Inflate.ZIP;
