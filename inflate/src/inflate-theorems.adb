with Inflate.CRC32;
with Inflate.Bodies;

package body Inflate.Theorems with SPARK_Mode => On is

   --  The lemma invocations below recurse as deep as the data (the CRC
   --  fold model in particular); this policy keeps them out of
   --  assertion-enabled executables. GNATprove proves Ignore-policy
   --  assertions all the same, and the theorem's postcondition in the
   --  spec remains executable.
   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   ---------------------
   -- GZip_Round_Trip --
   ---------------------

   procedure GZip_Round_Trip
     (Input      : in     Byte_Array;
      Compressed : in out Byte_Array;
      Restored   : in out Byte_Array;
      C_Size     :    out Natural;
      R_Size     :    out Natural)
   is
      CF : constant Buffer_Index := Compressed'First;

      Consumed : Natural;
      Status   : Status_Type;
   begin
      GZip.Compress (Input, Compressed, C_Size);
      pragma Assert
        (GZip.Member
           (Compressed (CF .. CF + (C_Size - 1)), Restored'Length));

      GZip.Decompress
        (Compressed (CF .. CF + (C_Size - 1)), Restored,
         Consumed, R_Size, Status);

      --  Both Input and Restored decode from the same member under the
      --  model; the relation is functional in the decoded bytes, so they
      --  agree byte for byte — and with them the CRC the decoder checked
      --  against the trailer the compressor wrote.
      Bodies.Lemma_Encoding_Functional
        (Compressed (CF + 10 .. CF + (C_Size - 1)), C_Size - 18,
         Input,
         Restored (Restored'First .. Restored'First - 1 + R_Size));
      CRC32.Lemma_Update_Content
        (0, Input,
         Restored (Restored'First .. Restored'First - 1 + R_Size));

      pragma Assert (Consumed = C_Size);
      pragma Assert (R_Size = Input'Length);
      pragma Assert (Status = OK);
   end GZip_Round_Trip;

end Inflate.Theorems;
