--  Inflate.GZip — the gzip container (RFC 1952): a header with optional
--  fields, a DEFLATE stream, and a little-endian CRC-32 plus length
--  (mod 2**32) of the decompressed data.
--
--  All header features are handled: EXTRA, NAME and COMMENT fields are
--  skipped with bounds checks, a header CRC (FHCRC) is verified when
--  present, reserved flag bits are rejected.
--
--  A gzip file may concatenate several members (`gzip` and `pigz` produce
--  such files; all decode as one stream). This decodes one member and
--  reports where it ended in Consumed; Decompress_All loops members for
--  the common "whole file" case.

with Ore.Byte_Buffers;

with Inflate.Raw;
with Inflate.CRC32;
with Inflate.Fixed;
with Inflate.Dynamic;
with Inflate.Bodies;

package Inflate.GZip with SPARK_Mode => On is

   --  The trailer is two little-endian 32-bit fields. Load_32 is the checked
   --  read of such a field, and the contracts below say what it must yield;
   --  its precondition, which is the bounds check, is what the enclosing
   --  Member and Compressed_Size conditions discharge.
   use Ore.Byte_Buffers;

   --  The shape of members Compress emits, characterized without exposing
   --  whether the body used stored blocks or the bounded fixed-Huffman image.
   --  The common body must end exactly eight bytes before the member's end
   --  and its decoded size must fit Out_Len.  Trailer contents remain a
   --  separate checksum/length condition below.
   function Member
     (Input : Byte_Array; Out_Len : Natural) return Boolean
   is
     (Input'Length >= 20
      and then Input (Input'First) = 16#1F#
      and then Input (Input'First + 1) = 16#8B#
      and then Input (Input'First + 2) = 8
      and then Input (Input'First + 3) = 0
      and then Bodies.Recognized
                 (Input (Input'First + 10 .. Input'Last), Out_Len)
      and then Bodies.Encoded_Size
                 (Input (Input'First + 10 .. Input'Last)) =
                   Input'Length - 18);

   --  Decompress the gzip member starting at Input'First. Status = OK
   --  means well-formed *and* CRC-32 and length matched. On error,
   --  Consumed and Produced report progress for diagnostics; the output
   --  bytes are not valid data.
   --
   --  The second postcondition is the decode half of the round-trip
   --  theorem lifted to the container: on a member in the compressor's
   --  image, the whole member is consumed, the body decodes against the
   --  model into the output, and the member is accepted when its
   --  trailer holds the CRC-32 the decoder recomputes over that output
   --  plus the output's length. A compressor that provably stored those
   --  values (Compress does) therefore gets Status = OK.
   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   =>
       (Consumed <= Input'Length
        and then Produced <= Output'Length
        and then (if Status = OK then Consumed > 0))
       and then
       (if Member (Input, Output'Length)
        then
          Consumed = Input'Length
          and then Produced = Bodies.Decoded_Size
                     (Input (Input'First + 10 .. Input'Last))
          and then Bodies.Body_Encodes
                     (Input (Input'First + 10 .. Input'Last),
                      Input'Length - 18,
                      Output (Output'First .. Output'First - 1 + Produced))
          and then (if Load_32 (Input, Input'Last - 7, Little_Endian) =
                         CRC32.Compute
                           (Output (Output'First ..
                                    Output'First - 1 + Produced))
                       and then Load_32
                                  (Input, Input'Last - 3, Little_Endian) =
                                    Word32 (Produced)
                    then Status = OK));

   --  Decompress consecutive gzip members until the input is exhausted,
   --  concatenating their output — the semantics of `gzip -d` on the whole
   --  file. Trailing data that is not a gzip member is an error
   --  (GZip_Bad_Magic), as it is for `gzip`.
   --
   --  A file that is one member in the compressor's image (the whole-file
   --  case of the round-trip theorem) carries the member contract through.
   procedure Decompress_All
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   =>
       Produced <= Output'Length
       and then
       (if Member (Input, Output'Length)
        then
          Produced = Bodies.Decoded_Size
                       (Input (Input'First + 10 .. Input'Last))
          and then Bodies.Body_Encodes
                     (Input (Input'First + 10 .. Input'Last),
                      Input'Length - 18,
                      Output (Output'First .. Output'First - 1 + Produced))
          and then (if Load_32 (Input, Input'Last - 7, Little_Endian) =
                         CRC32.Compute
                           (Output (Output'First ..
                                    Output'First - 1 + Produced))
                       and then Load_32
                                  (Input, Input'Last - 3, Little_Endian) =
                                    Word32 (Produced)
                    then Status = OK));

   ---------------------------------------------------------------------
   --  Compression
   ---------------------------------------------------------------------

   --  Allocation bound for Compress's output: header, the selected dynamic,
   --  fixed, or stored body, and trailer. Above the first dynamic-selection
   --  threshold the bound reserves its deliberately large direct-length
   --  header even when the data ultimately stays on the fixed path.
   function Compressed_Size (N : Natural) return Positive is
     ((if N < Dynamic.Dynamic_Run_Min_Input
       then Fixed.Max_Size (N)
       elsif N <= Dynamic.Max_Input then Dynamic.Max_Size (N)
       elsif N <= Fixed.Max_Input then Fixed.Max_Size (N)
       else Raw.Stored_Size (N)) + 18)
   with Pre => N <= Raw.Max_Compress_Input;

   --  Produce a complete gzip member holding Input. Long constant-byte runs
   --  first try a sparse dynamic-Huffman body and retain it only when it is
   --  smaller than the exact fixed alternative. Other inputs within the fixed
   --  arithmetic domain use fixed-Huffman literals and selected verified
   --  matches; larger inputs use stored blocks. All are consumable by any gzip
   --  decoder and total under the precondition; Compressed_Size is the caller's
   --  capacity bound.
   --
   --  The postcondition pins down the whole member: the fixed header (no
   --  optional fields, so the DEFLATE body starts 10 bytes in), the body
   --  standing in the decode-model relation to exactly Input, and the
   --  trailer holding the same CRC-32 the decoder recomputes, plus the
   --  input length. This is the compress half of the gzip round-trip
   --  theorem; the decode half relates Decompress to the same model.
   procedure Compress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural)
   with
     Global => null,
     Pre    => Input'Length <= Raw.Max_Compress_Input
               and then Output'Length >= Compressed_Size (Input'Length),
     Post   =>
       (if Dynamic.Selects_Byte_Run (Input)
        then Produced <= Fixed.Encoded_Size (Input) + 18
        elsif Input'Length <= Fixed.Max_Input
        then Produced = Fixed.Encoded_Size (Input) + 18
        else Produced = Raw.Stored_Size (Input'Length) + 18)
       and then Produced <= Compressed_Size (Input'Length)
       and then Output (Output'First) = 16#1F#
       and then Output (Output'First + 1) = 16#8B#
       and then Output (Output'First + 2) = 8
       and then Output (Output'First + 3) = 0
       and then Bodies.Body_Encodes
                  (Output
                     (Output'First + 10 ..
                      Output'First + (Produced - 1)),
                   Produced - 18, Input)
       and then Bodies.Recognized
                  (Output
                     (Output'First + 10 ..
                      Output'First + (Produced - 1)),
                   Input'Length)
       and then Bodies.Encoded_Size
                  (Output
                     (Output'First + 10 ..
                      Output'First + (Produced - 1))) = Produced - 18
       and then Bodies.Decoded_Size
                  (Output
                     (Output'First + 10 ..
                      Output'First + (Produced - 1))) = Input'Length
       and then Load_32
                  (Output, Output'First + (Produced - 8), Little_Endian) =
                    CRC32.Compute (Input)
       and then Load_32
                  (Output, Output'First + (Produced - 4), Little_Endian) =
                    Word32 (Input'Length);

end Inflate.GZip;
