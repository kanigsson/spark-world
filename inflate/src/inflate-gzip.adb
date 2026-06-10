with Inflate.Raw;
with Inflate.CRC32;

package body Inflate.GZip with SPARK_Mode => On is

   use Interfaces;

   function LE32 (B0, B1, B2, B3 : Byte) return Word32 is
     (Word32 (B0)
      or Shift_Left (Word32 (B1), 8)
      or Shift_Left (Word32 (B2), 16)
      or Shift_Left (Word32 (B3), 24));

   --  Header flag bits (RFC 1952 §2.3.1)
   FHCRC    : constant Byte := 16#02#;
   FEXTRA   : constant Byte := 16#04#;
   FNAME    : constant Byte := 16#08#;
   FCOMMENT : constant Byte := 16#10#;

   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   is
      P   : Natural;  --  current offset from Input'First
      FLG : Byte;
      Raw_Consumed, Raw_Produced : Natural;
      Stored_CRC, Stored_Size    : Word32;
   begin
      Consumed := 0;
      Produced := 0;

      if Input'Length < 2 then
         Status := Truncated_Input;
         return;
      end if;
      if Input (Input'First) /= 16#1F#
        or else Input (Input'First + 1) /= 16#8B#
      then
         Status := GZip_Bad_Magic;
         return;
      end if;
      if Input'Length < 10 then
         Status := Truncated_Input;
         return;
      end if;
      if Input (Input'First + 2) /= 8 then
         Status := GZip_Bad_Method;
         return;
      end if;
      FLG := Input (Input'First + 3);
      if (FLG and 16#E0#) /= 0 then
         Status := GZip_Reserved_Flags;
         return;
      end if;
      --  MTIME, XFL and OS carry no constraints; skip to the optional fields
      P := 10;

      if (FLG and FEXTRA) /= 0 then
         if Input'Length - P < 2 then
            Status := Truncated_Input;
            return;
         end if;
         declare
            XLen : constant Natural :=
              Natural (Input (Input'First + P))
              + 256 * Natural (Input (Input'First + P + 1));
         begin
            P := P + 2;
            if XLen > Input'Length - P then
               Status := Truncated_Input;
               return;
            end if;
            P := P + XLen;
         end;
      end if;

      --  NAME then COMMENT, when present: zero-terminated byte strings
      for Field in 1 .. 2 loop
         pragma Loop_Invariant (P <= Input'Length);
         if (FLG and (if Field = 1 then FNAME else FCOMMENT)) /= 0 then
            loop
               pragma Loop_Invariant (P <= Input'Length);
               pragma Loop_Variant (Increases => P);
               if P >= Input'Length then
                  Status := Truncated_Input;
                  return;
               end if;
               P := P + 1;
               exit when Input (Input'First + P - 1) = 0;
            end loop;
         end if;
      end loop;

      if (FLG and FHCRC) /= 0 then
         if Input'Length - P < 2 then
            Status := Truncated_Input;
            return;
         end if;
         declare
            --  The stored value is the low 16 bits of the CRC-32 of the
            --  header bytes up to (not including) this field.
            Header_CRC : constant Word32 :=
              CRC32.Compute (Input (Input'First .. Input'First - 1 + P));
            Stored : constant Natural :=
              Natural (Input (Input'First + P))
              + 256 * Natural (Input (Input'First + P + 1));
         begin
            P := P + 2;
            if Natural (Header_CRC and 16#FFFF#) /= Stored then
               Status := GZip_Header_CRC_Mismatch;
               return;
            end if;
         end;
      end if;

      if Input'Length - P < 1 then
         Status := Truncated_Input;
         return;
      end if;
      Raw.Decompress
        (Input (Input'First + P .. Input'Last), Output,
         Raw_Consumed, Raw_Produced, Status);
      Consumed := P + Raw_Consumed;
      Produced := Raw_Produced;
      if Status /= OK then
         return;
      end if;

      --  Trailer: CRC-32 then length mod 2**32, both little-endian
      if Input'Length - Consumed < 8 then
         Status := Truncated_Input;
         return;
      end if;
      Stored_CRC := LE32
        (Input (Input'First + Consumed),
         Input (Input'First + Consumed + 1),
         Input (Input'First + Consumed + 2),
         Input (Input'First + Consumed + 3));
      Stored_Size := LE32
        (Input (Input'First + Consumed + 4),
         Input (Input'First + Consumed + 5),
         Input (Input'First + Consumed + 6),
         Input (Input'First + Consumed + 7));
      Consumed := Consumed + 8;

      if Stored_CRC /=
        CRC32.Compute (Output (Output'First .. Output'First - 1 + Produced))
      then
         Status := GZip_Checksum_Mismatch;
      elsif Stored_Size /= Word32 (Produced) then
         Status := GZip_Length_Mismatch;
      end if;
   end Decompress;

   procedure Decompress_All
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural;
      Status   :    out Status_Type)
   is
      In_Pos  : Natural := 0;
      Out_Pos : Natural := 0;
      C, Pr   : Natural;
   begin
      Produced := 0;
      if Input'Length = 0 then
         Status := Truncated_Input;
         return;
      end if;
      loop
         pragma Loop_Invariant (In_Pos < Input'Length);
         pragma Loop_Invariant (Out_Pos <= Output'Length);
         pragma Loop_Variant (Increases => In_Pos);
         Decompress
           (Input (Input'First + In_Pos .. Input'Last),
            Output (Output'First + Out_Pos .. Output'Last),
            C, Pr, Status);
         In_Pos  := In_Pos + C;
         Out_Pos := Out_Pos + Pr;
         Produced := Out_Pos;
         exit when Status /= OK or else In_Pos >= Input'Length;
      end loop;
   end Decompress_All;

end Inflate.GZip;
