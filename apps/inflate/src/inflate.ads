--  Inflate - shared types for the DEFLATE, zlib, gzip, and ZIP decoders.
--
--  This is the root of the crate: the byte/buffer types every child shares
--  and the single status enumeration that all layers report through. The
--  decoders live in the children:
--
--    Inflate.Raw     — DEFLATE itself (RFC 1951), the compression core
--    Inflate.LZ77    — proved back-reference match copying, including overlap
--    Inflate.Codebooks — fixed/canonical encoder codebook boundary
--    Inflate.Payload — shared Huffman token-payload serialization
--    Inflate.Dynamic — proved local dynamic-Huffman body construction
--    Inflate.Bodies  — common supported-body DEFLATE relation
--    Inflate.ZLib    — the zlib container (RFC 1950), Adler-32 checked
--    Inflate.GZip    — the gzip container (RFC 1952), CRC-32 checked
--    Inflate.CRC32   — CRC-32 (the gzip/zip polynomial)
--    Inflate.Adler32 — Adler-32 (the zlib checksum)
--
--  DESIGN: everything is one-shot over caller-provided buffers. No heap,
--  no access types, no recursion, no OS, and no tasking state. The library
--  is intended for bounded inputs where an upper bound on the decompressed
--  size is known by the caller. Malformed input is reported through
--  Status_Type instead of being handled by raising an exception.
--
--  The physical types are Ore's: an octet, the machine words, the
--  1-based byte index and the unconstrained byte array every buffer and
--  algorithm here is written against. Renaming them rather than declaring
--  our own is what lets the decoders pass their caller-provided arrays
--  straight to Ore.Byte_Buffers for checked endian field access. Only the
--  names are local, so `Inflate.Byte_Array` and `Ore.Byte_Array` are one
--  type and no conversion is ever needed at the boundary.

with Ore;
with Ore.Bit_Cursors;
with Ore.Bits;

package Inflate
  with Pure, SPARK_Mode => On
is

   --  Ore declares the operators of the word types below; a use clause in
   --  the visible part of this package makes them directly visible in the
   --  children as well, which is where the byte arithmetic lives. Nothing
   --  in this spec needs them, which is what the warning is about.
   pragma Warnings (Off, "use clause for package ""Ore"" has no effect");
   use Ore;
   pragma Warnings (On, "use clause for package ""Ore"" has no effect");

   subtype Byte is Ore.Byte;
   subtype Word16 is Ore.Word16;
   subtype Word32 is Ore.Word32;

   --  The index stops one short of Integer'Last so that a position one
   --  past the end of any buffer — the natural "everything consumed"
   --  cursor and empty-slice bound — is always computable without
   --  overflow. Buffers are thereby capped at Integer'Last - 1 bytes.
   subtype Buffer_Index is Ore.Index;

   subtype Byte_Array is Ore.Byte_Array;

   --  Ore.Bits under a short name, for the children that reach into it by
   --  qualified reference: the bit accessor the encoders' models are stated
   --  with, single-bit insertion, and explicit narrowing.
   package Bits renames Ore.Bits;

   --  Ore.Bit_Cursors likewise: DEFLATE addresses its fields by bit position
   --  in a stream of octets, which is what that package is, and the stream
   --  the encoders write into and the decoders read is a plain byte array a
   --  caller owns — the shape its operations are defined on. The bit accessor
   --  the encoders' stream model is stated with and the single-bit store the
   --  encoders write through both come from there, so that the step from the
   --  byte written to the bit position it moved is made once.
   package Bit_Cursors renames Ore.Bit_Cursors;

   --  DEFLATE is a bit-oriented format and the checksums are polynomial
   --  divisions, so shifts appear throughout. These are Ore's machine
   --  intrinsics rather than its checked shifts: the checked forms are
   --  specified bit by bit, whereas the bit reader and both checksums
   --  reason about the *value* a shift produces, which is what GNATprove
   --  gets from the intrinsic directly. The shifts are for the children, not
   --  for this spec, which is what the warning is about.
   pragma
     Warnings (Off, "use clause for package ""Intrinsics"" has no effect");
   use Ore.Bits.Intrinsics;
   pragma Warnings (On, "use clause for package ""Intrinsics"" has no effect");

   --  Every way a decode can end. OK means the stream was well-formed and
   --  the output (and, for the containers, its checksum) is complete;
   --  everything else identifies the first violation encountered.
   type Status_Type is
     (OK,

      --  RFC 1951 (raw DEFLATE) violations
      Truncated_Input,          --  input ended in the middle of the stream
      Output_Too_Small,         --  decompressed data exceeds Output'Length
      Invalid_Block_Type,       --  reserved block type 3
      Invalid_Stored_Length,    --  stored-block NLEN is not ~LEN
      Invalid_Header_Counts,    --  dynamic header HLIT > 286 or HDIST > 30
      Invalid_Code_Lengths,     --  code-length code over-subscribed/incomplete
      Invalid_Repeat,           --  length repeat before any length, or past end
      Invalid_Literal_Code,     --  literal/length code lengths inconsistent
      Invalid_Distance_Code,    --  distance code lengths inconsistent
      Invalid_Symbol,           --  bit sequence matches no code (incomplete code)
      Invalid_Length_Symbol,    --  reserved literal/length symbol 286/287
      Invalid_Distance_Symbol,  --  reserved distance symbol 30/31
      Distance_Too_Far,         --  match distance reaches before output start

      --  RFC 1950 (zlib container) violations
      ZLib_Bad_Header,          --  CMF/FLG check bits or method/window invalid
      ZLib_Dictionary_Needed,   --  FDICT set: preset dictionaries unsupported
      ZLib_Checksum_Mismatch,   --  Adler-32 of the output does not match

      --  RFC 1952 (gzip container) violations
      GZip_Bad_Magic,           --  not 1F 8B
      GZip_Bad_Method,          --  CM /= 8 (deflate)
      GZip_Reserved_Flags,      --  FLG reserved bits set
      GZip_Header_CRC_Mismatch, --  FHCRC present and wrong
      GZip_Checksum_Mismatch,   --  CRC-32 of the output does not match
      GZip_Length_Mismatch,     --  ISIZE /= output length mod 2**32

      --  ZIP container violations
      ZIP_No_End_Record,        --  end-of-central-directory record not found
      ZIP_Bad_Central_Entry,    --  central directory entry malformed
      ZIP_Bad_Local_Header,     --  local file header malformed or inconsistent
      ZIP_Unsupported,          --  feature outside scope (ZIP64, encryption, ...)
      ZIP_Checksum_Mismatch,    --  entry CRC-32 does not match
      ZIP_Length_Mismatch);     --  entry decompressed size does not match

end Inflate;
