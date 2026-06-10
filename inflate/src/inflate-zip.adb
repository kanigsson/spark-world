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
      C      := (Offset => 0, Remaining => 0);
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
      --  EOCD record.
      if CD_Offset > Word32 (Pos)
        or else CD_Size > Word32 (Pos) - CD_Offset
      then
         Status := ZIP_Bad_Central_Entry;
         return;
      end if;

      C      := (Offset => Natural (CD_Offset), Remaining => Count);
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
      E := (Name_First   => 1,
            Name_Last    => 0,
            Method       => 0,
            Flags        => 0,
            CRC          => 0,
            Comp_Size    => 0,
            Uncomp_Size  => 0,
            Local_Offset => 0);

      if Archive'Length - C.Offset < Central_Entry_Size
        or else not Has_Signature (Archive, C.Offset, 16#01#, 16#02#)
      then
         Status := ZIP_Bad_Central_Entry;
         C.Remaining := 0;
         return;
      end if;

      E.Flags        := RD16 (Archive, C.Offset + 8);
      E.Method       := RD16 (Archive, C.Offset + 10);
      E.CRC          := RD32 (Archive, C.Offset + 16);
      E.Comp_Size    := RD32 (Archive, C.Offset + 20);
      E.Uncomp_Size  := RD32 (Archive, C.Offset + 24);
      Name_Len       := RD16 (Archive, C.Offset + 28);
      Extra_Len      := RD16 (Archive, C.Offset + 30);
      Comment_Len    := RD16 (Archive, C.Offset + 32);
      E.Local_Offset := RD32 (Archive, C.Offset + 42);

      if RD16 (Archive, C.Offset + 34) /= 0 then  --  disk number start
         Status := ZIP_Unsupported;
         C.Remaining := 0;
         return;
      end if;
      if E.Comp_Size = 16#FFFF_FFFF#
        or else E.Uncomp_Size = 16#FFFF_FFFF#
        or else E.Local_Offset = 16#FFFF_FFFF#
      then
         Status := ZIP_Unsupported;
         C.Remaining := 0;
         return;
      end if;

      if Name_Len + Extra_Len + Comment_Len >
        Archive'Length - C.Offset - Central_Entry_Size
      then
         Status := ZIP_Bad_Central_Entry;
         C.Remaining := 0;
         return;
      end if;

      E.Name_First := Archive'First + C.Offset + Central_Entry_Size;
      E.Name_Last  := E.Name_First - 1 + Name_Len;

      C.Offset    := C.Offset + Central_Entry_Size
                       + Name_Len + Extra_Len + Comment_Len;
      C.Remaining := C.Remaining - 1;
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

      if E.Flags mod 2 /= 0 then  --  bit 0: encrypted
         Status := ZIP_Unsupported;
         return;
      end if;

      --  Validate the local header the offset points at
      if E.Local_Offset > Word32 (Archive'Length)
        or else Archive'Length - Natural (E.Local_Offset) < Local_Header_Size
      then
         Status := ZIP_Bad_Local_Header;
         return;
      end if;
      LO := Natural (E.Local_Offset);
      if not Has_Signature (Archive, LO, 16#03#, 16#04#) then
         Status := ZIP_Bad_Local_Header;
         return;
      end if;

      --  The local name and extra field may legitimately differ from the
      --  central ones (data-descriptor writers leave sizes zero here), so
      --  only their lengths matter: they place the data.
      declare
         L_Name  : constant Natural := RD16 (Archive, LO + 26);
         L_Extra : constant Natural := RD16 (Archive, LO + 28);
      begin
         if L_Name + L_Extra >
           Archive'Length - LO - Local_Header_Size
         then
            Status := ZIP_Bad_Local_Header;
            return;
         end if;
         Data_Start := LO + Local_Header_Size + L_Name + L_Extra;
      end;

      if E.Comp_Size > Word32 (Archive'Length - Data_Start) then
         Status := ZIP_Bad_Local_Header;
         return;
      end if;
      CSize := Natural (E.Comp_Size);

      case E.Method is
         when 0 =>
            --  Stored: the two sizes must agree and the bytes are literal
            if E.Comp_Size /= E.Uncomp_Size then
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
              or else Word32 (Produced) /= E.Uncomp_Size
            then
               Status := ZIP_Length_Mismatch;
               return;
            end if;

         when others =>
            Status := ZIP_Unsupported;
            return;
      end case;

      if CRC32.Compute (Output (Output'First .. Output'First - 1 + Produced))
        /= E.CRC
      then
         Status := ZIP_Checksum_Mismatch;
         return;
      end if;

      Status := OK;
   end Extract;

end Inflate.ZIP;
