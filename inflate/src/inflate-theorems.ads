--  Inflate.Theorems — end-to-end statements about the codec, proved once
--  for all inputs.
--
--  GZip_Round_Trip is the round-trip theorem of the stored-fragment
--  codec (milestone M6a of the compression plan): gzip-compressing any
--  input and decompressing the result restores the input exactly, with
--  Status = OK, under the theorem's side conditions — the input is under
--  the compressor's size cap and the buffers are large enough (the
--  compressed size is exactly GZip.Compressed_Size). The procedure is an
--  ordinary executable subprogram whose postcondition *is* the theorem;
--  its proof composes the compressor's contract (the emitted member
--  stands in the decode-model relation to the input) with the decoder's
--  (a member in the compressor's image decodes against the same model),
--  the functionality of the relation, and the content-invariance of the
--  CRC.
--
--  The theorem is spec-free: no DEFLATE specification is trusted, only
--  the agreement of two of this library's own subprograms through the
--  executable model. It says nothing about streams outside the
--  compressor's image; decoding those is covered by testing (and by
--  later milestones of the plan).
--
--  The procedure is executable at any input size, assertions on or off:
--  the ghost lemmas it invokes recurse as deep as the input is long (the
--  CRC fold model), so the body scopes them under an Ignore assertion
--  policy — GNATprove proves them all the same.

with Inflate.Raw;
with Inflate.GZip;

package Inflate.Theorems with SPARK_Mode => On is

   use type Interfaces.Unsigned_8;

   procedure GZip_Round_Trip
     (Input      : in     Byte_Array;
      Compressed : in out Byte_Array;
      Restored   : in out Byte_Array;
      C_Size     :    out Natural;
      R_Size     :    out Natural)
   with
     Global => null,
     Pre  =>
       Input'Length <= Raw.Max_Compress_Input
       and then Compressed'Length >= GZip.Compressed_Size (Input'Length)
       and then Restored'Length >= Input'Length,
     Post =>
       C_Size = GZip.Compressed_Size (Input'Length)
       and then R_Size = Input'Length
       and then (for all K in 0 .. Input'Length - 1 =>
                   Restored (Restored'First + K) = Input (Input'First + K));

end Inflate.Theorems;
