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

package Inflate.GZip with SPARK_Mode => On is

   --  Decompress the gzip member starting at Input'First. Status = OK
   --  means well-formed *and* CRC-32 and length matched. On error,
   --  Consumed and Produced report progress for diagnostics; the output
   --  bytes are not valid data.
   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   => Consumed <= Input'Length
               and then Produced <= Output'Length
               and then (if Status = OK then Consumed > 0);

   --  Decompress consecutive gzip members until the input is exhausted,
   --  concatenating their output — the semantics of `gzip -d` on the whole
   --  file. Trailing data that is not a gzip member is an error
   --  (GZip_Bad_Magic), as it is for `gzip`.
   procedure Decompress_All
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   => Produced <= Output'Length;

end Inflate.GZip;
