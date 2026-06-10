package body Inflate.Adler32 with SPARK_Mode => On is

   use Interfaces;

   Base : constant := 65521;

   --  Largest run length for which the sums cannot wrap a 32-bit word:
   --  with A < Base and B < Base on entry to a run of N bytes of 255,
   --  B grows to at most (Base-1)(N+1) + 255·N(N+1)/2, which stays below
   --  2**32 for N = 5552 (the bound zlib uses). The reductions after each
   --  run make the sums exact even though the type is modular.
   Run_Max : constant := 5552;

   function Update (Adler : Word32; Data : Byte_Array) return Word32 is
      A : Word32 := (Adler and 16#FFFF#) mod Base;
      B : Word32 := Shift_Right (Adler, 16) mod Base;
      Run : Natural range 0 .. Run_Max - 1 := 0;
   begin
      for I in Data'Range loop
         A := A + Word32 (Data (I));
         B := B + A;
         if Run = Run_Max - 1 then
            A := A mod Base;
            B := B mod Base;
            Run := 0;
         else
            Run := Run + 1;
         end if;
      end loop;
      A := A mod Base;
      B := B mod Base;
      return Shift_Left (B, 16) or A;
   end Update;

end Inflate.Adler32;
