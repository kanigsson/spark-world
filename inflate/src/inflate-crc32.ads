--  Inflate.CRC32 — the CRC-32 used by gzip and ZIP (polynomial 0xEDB88320,
--  reflected, init and final XOR 0xFFFFFFFF; ISO 3309 / ITU-T V.42).
--
--  Table-driven, one byte per step; the table is computed at elaboration
--  from the polynomial rather than transcribed, so there is nothing to
--  mistype. All arithmetic is modular — proof of absence of run-time
--  errors is direct.

package Inflate.CRC32 with SPARK_Mode => On is

   --  Continue a CRC over more data. Start from 0 (Compute does), feed
   --  consecutive slices, and the result equals the CRC of the whole.
   function Update (CRC : Word32; Data : Byte_Array) return Word32
   with Global => null;

   --  CRC-32 of Data, as gzip and ZIP store it.
   function Compute (Data : Byte_Array) return Word32 is (Update (0, Data))
   with Global => null;

end Inflate.CRC32;
