--  Inflate.Raw — the DEFLATE compressed data format itself (RFC 1951).
--
--  One-shot: the whole compressed stream is in Input, and the whole result
--  must fit in Output. This is for bounded inputs where an upper bound on
--  the decompressed size is known; it is not a streaming zlib replacement.
--
--  The decoder is stateless and reentrant: fixed-code tables are built on
--  demand rather than cached in package state, so concurrent calls share
--  nothing.

with Inflate.Model;
with Inflate.Fixed;

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
   --
   --  The second postcondition is the decode half of the round-trip
   --  theorem, on the stored fragment the compressor emits: whenever a
   --  well-formed stored-block stream starts at Input'First (trailing
   --  bytes after it, such as a container's checksum, are fine) and its
   --  decoded size fits the buffer, decoding succeeds, consumes exactly
   --  the stream, and the produced bytes stand in the decode-model
   --  relation to it. Since the relation is functional in the decoded
   --  bytes, this pins the output completely.
   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   =>
       (Consumed <= Input'Length and then Produced <= Output'Length)
       and then (if Status = OK
                 then Model.Is_Decoding
                        (Input, Output, Consumed, Produced))
       and then
       (if Input'Length <= Fixed.Max_Stream_Bytes
           and then Fixed.Analyze (Input).Valid
           and then Fixed.Analyze (Input).Decoded_Length <= Output'Length
        then Status = OK
             and then Consumed = (Fixed.Analyze (Input).End_Bit + 7) / 8
             and then Produced = Fixed.Analyze (Input).Decoded_Length
             and then Fixed.Is_Encoding
                        (Input, Consumed,
                         Output
                           (Output'First .. Output'First - 1 + Produced)))
       and then
       (if Input'Length >= 5
           and then Model.Stored_Stream_End
                      (Input, Input'First, Input'Last) > 0
           and then Model.Stored_Decoded_Length
                      (Input, Input'First, Input'Last) <= Output'Length
        then
          Status = OK
          and then Input'First + (Consumed - 1) =
                     Model.Stored_Stream_End (Input, Input'First, Input'Last)
          and then Produced =
                     Model.Stored_Decoded_Length
                       (Input, Input'First, Input'Last)
          and then Model.Encodes_Stored
                     (Input, Input'First, Input'First + (Consumed - 1),
                      Output,
                      (if Output'Length > 0 then Output'First else 1),
                      (if Output'Length > 0
                       then Output'First + (Produced - 1)
                       else 0)));

   ---------------------------------------------------------------------
   --  Compression
   ---------------------------------------------------------------------

   --  The compressor emits stored blocks only (RFC 1951 §3.2.4): every
   --  standard DEFLATE decoder consumes its output, the compression ratio
   --  is just slightly below 1. Its functional contract is the round-trip
   --  property: the emitted bytes are related to the input by the same
   --  decode model (Inflate.Model) that the decoder is verified against,
   --  so decompressing the output provably yields the input back.

   Max_Stored_Block : constant := 16#FFFF#;  --  LEN is a 16-bit field

   --  Input size cap: leaves room below the buffer-length ceiling for the
   --  5 bytes of framing per block that compression can add.
   Max_Compress_Input : constant := Buffer_Index'Last - 2**18;

   --  Blocks needed for N bytes of input: ceiling division, and one
   --  (empty, final) block when there is no input at all.
   function Stored_Block_Count (N : Natural) return Positive is
     (if N = 0 then 1 else 1 + (N - 1) / Max_Stored_Block)
   with Post => Stored_Block_Count'Result <= 32769;

   --  The exact compressed size for N input bytes: 5 bytes of block
   --  header per block. This is the proved size bound the caller can
   --  allocate from.
   function Stored_Size (N : Natural) return Positive is
     (N + 5 * Stored_Block_Count (N))
   with Pre => N <= Max_Compress_Input;

   --  Compress Input into a sequence of stored blocks. Total: under the
   --  precondition every input compresses successfully — there is no
   --  failure path — and the output size is exactly Stored_Size.
   --
   --  The postcondition is the compress half of the round-trip theorem:
   --  the produced bytes stand in the decode-model relation to exactly
   --  the input bytes.
   procedure Compress_Stored
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural)
   with
     Global => null,
     Pre    => Input'Length <= Max_Compress_Input
               and then Output'Length >= Stored_Size (Input'Length),
     Post   =>
       Produced = Stored_Size (Input'Length)
       and then Model.Encodes_Stored
                  (Output, Output'First, Output'First + (Produced - 1),
                   Input,
                   (if Input'Length > 0 then Input'First else 1),
                   (if Input'Length > 0 then Input'Last else 0));

end Inflate.Raw;
