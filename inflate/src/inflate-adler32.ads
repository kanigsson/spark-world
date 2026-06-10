--  Inflate.Adler32 — the zlib checksum (RFC 1950 §8.2): two mod-65521 sums,
--  the low one over the bytes, the high one over the running low sums.

package Inflate.Adler32 with SPARK_Mode => On is

   --  Continue a checksum over more data. Start from 1 (Compute does), feed
   --  consecutive slices, and the result equals the checksum of the whole.
   function Update (Adler : Word32; Data : Byte_Array) return Word32
   with Global => null;

   --  Adler-32 of Data, as the zlib container stores it.
   function Compute (Data : Byte_Array) return Word32 is (Update (1, Data))
   with Global => null;

end Inflate.Adler32;
