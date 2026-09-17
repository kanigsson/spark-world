with Ore.Byte_Buffers;

with Inflate.Raw;
with Inflate.Adler32;

package body Inflate.ZLib with SPARK_Mode => On is

   use Ore.Byte_Buffers;

   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   is
      CMF, FLG : Byte;
      Raw_Consumed, Raw_Produced : Natural;
      Stored_Sum : Word32;
   begin
      Consumed := 0;
      Produced := 0;

      --  Header: compression method/info byte and flags byte, tied by a
      --  mod-31 check over the pair.
      if Input'Length < 3 then
         Status := Truncated_Input;
         return;
      end if;
      CMF := Input (Input'First);
      FLG := Input (Input'First + 1);
      if (Natural (CMF) * 256 + Natural (FLG)) mod 31 /= 0
        or else (CMF and 16#0F#) /= 8       --  method: deflate
        or else Shift_Right (CMF, 4) > 7    --  window size: at most 32K
      then
         Status := ZLib_Bad_Header;
         return;
      end if;
      if (FLG and 16#20#) /= 0 then
         Status := ZLib_Dictionary_Needed;
         return;
      end if;

      Raw.Decompress
        (Input (Input'First + 2 .. Input'Last), Output,
         Raw_Consumed, Raw_Produced, Status);
      Consumed := 2 + Raw_Consumed;
      Produced := Raw_Produced;
      if Status /= OK then
         return;
      end if;

      --  Trailer: Adler-32 of the decompressed data, big-endian.
      if Input'Length - Consumed < 4 then
         Status := Truncated_Input;
         return;
      end if;
      Stored_Sum := Load_32 (Input, Input'First + Consumed, Big_Endian);
      Consumed := Consumed + 4;

      if Stored_Sum /=
        Adler32.Compute (Output (Output'First .. Output'First - 1 + Produced))
      then
         Status := ZLib_Checksum_Mismatch;
      end if;
   end Decompress;

end Inflate.ZLib;
