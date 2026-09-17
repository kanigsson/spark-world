--  Inflate.ZLib — the zlib container (RFC 1950): a two-byte header, a
--  DEFLATE stream, and a big-endian Adler-32 of the decompressed data.
--
--  Preset dictionaries (FDICT) are out of scope and reported as
--  ZLib_Dictionary_Needed; they do not occur in the wild outside a few
--  specialised protocols that supply the dictionary out of band.

package Inflate.ZLib with SPARK_Mode => On is

   --  Decompress the zlib stream starting at Input'First. Status = OK
   --  means well-formed *and* the Adler-32 checksum matched. Consumed
   --  covers header, DEFLATE stream and trailer; trailing data after the
   --  stream is the caller's to interpret. On error, Consumed and Produced
   --  report progress for diagnostics; the output bytes are not valid data.
   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   => Consumed <= Input'Length and then Produced <= Output'Length;

end Inflate.ZLib;
