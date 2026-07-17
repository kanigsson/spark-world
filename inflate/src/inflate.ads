--  Inflate - shared types for the DEFLATE, zlib, gzip, and ZIP decoders.
--
--  This is the root of the crate: the byte/buffer types every child shares
--  and the single status enumeration that all layers report through. The
--  decoders live in the children:
--
--    Inflate.Raw     — DEFLATE itself (RFC 1951), the compression core
--    Inflate.LZ77    — proved back-reference match copying, including overlap
--    Inflate.Dynamic — proved bounded dynamic-Huffman length construction
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

with Interfaces;

package Inflate with Pure, SPARK_Mode => On is

   subtype Byte   is Interfaces.Unsigned_8;
   subtype Word32 is Interfaces.Unsigned_32;

   --  The index stops one short of Integer'Last so that a position one
   --  past the end of any buffer — the natural "everything consumed"
   --  cursor and empty-slice bound — is always computable without
   --  overflow. Buffers are thereby capped at Integer'Last - 1 bytes.
   subtype Buffer_Index is Positive range 1 .. Positive'Last - 1;

   type Byte_Array is array (Buffer_Index range <>) of Byte;

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
