--  Inflate.Raw — the DEFLATE compressed data format itself (RFC 1951).
--
--  One-shot: the whole compressed stream is in Input, and the whole result
--  must fit in Output. This is for bounded inputs where an upper bound on
--  the decompressed size is known; it is not a streaming zlib replacement.
--
--  The decoder is stateless and reentrant: fixed-code tables are built on
--  demand rather than cached in package state, so concurrent calls share
--  nothing.

package Inflate.Raw with SPARK_Mode => On is

   --  Decompress the DEFLATE stream starting at Input'First.
   --
   --  On return, Output (Output'First .. Output'First + Produced - 1) holds
   --  the decompressed bytes and Consumed is the number of input bytes the
   --  stream occupied, including the final partially-used byte if the last
   --  block ended mid-byte. Input beyond Consumed is not looked at — a
   --  caller with trailing data (a checksum, the next archive member)
   --  resumes reading there.
   --
   --  Status /= OK means the stream violated the format; Produced then
   --  reports how much output had been emitted when the violation was
   --  detected (useful for diagnostics, not valid data). Output is a scratch
   --  buffer: bytes beyond Produced may have been written. It is `in out`
   --  rather than `out` so that callers need not prove initialization of a
   --  buffer that is data-flow-wise write-before-read; pass it uninitialized
   --  from full-Ada code, or zeroed from SPARK code.
   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   => Consumed <= Input'Length and then Produced <= Output'Length;

end Inflate.Raw;
