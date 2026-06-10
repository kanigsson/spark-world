package body Inflate.CRC32 with SPARK_Mode => On is

   use Interfaces;

   type Table_Type is array (Byte) of Word32;

   function Build_Table return Table_Type with Global => null;

   function Build_Table return Table_Type is
      T : Table_Type;
      C : Word32;
   begin
      for I in Byte loop
         C := Word32 (I);
         for K in 1 .. 8 loop
            C := (if (C and 1) /= 0
                  then 16#EDB8_8320# xor Shift_Right (C, 1)
                  else Shift_Right (C, 1));
         end loop;
         T (I) := C;
      end loop;
      return T;
   end Build_Table;

   Table : constant Table_Type := Build_Table;

   function Update (CRC : Word32; Data : Byte_Array) return Word32 is
      C : Word32 := CRC xor 16#FFFF_FFFF#;
   begin
      for I in Data'Range loop
         C := Table (Byte (C and 16#FF#) xor Data (I)) xor Shift_Right (C, 8);
      end loop;
      return C xor 16#FFFF_FFFF#;
   end Update;

end Inflate.CRC32;
