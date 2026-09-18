with Ore;
with Ore.Bit_Cursors;
with Ore.Bits;
with Ore.Byte_Buffers;

procedure Restriction_Smoke is
   use type Ore.Byte;
   use type Ore.Word16;
   use type Ore.Word32;

   B : Ore.Byte_Buffers.Buffer (1);

   Bits_Out : Ore.Byte_Array (1 .. 1) := (1 => 0);
   Position : Natural := 0;
   Written  : Boolean;
begin
   Ore.Byte_Buffers.Append (B, 0);
   pragma
     Assert
       (Ore.Byte_Buffers.Length (B) = 1
          and then Ore.Byte_Buffers.Element (B, 1) = 0);

   --  Every child has to be in the partition for the binder to check it
   --  against the restrictions, not just compiled.
   pragma
     Assert
       (Ore.Bits.Population_Count (Ore.Bits.Low_Mask_8 (3)) = 3
          and then Ore.Bits.Byte_Swap (Ore.Word16'(16#00FF#)) = 16#FF00#);

   Ore.Bit_Cursors.Put_Bits
     (Bits_Out,
      Position,
      3,
      Ore.Bit_Cursors.Lsb_First,
      Ore.Bit_Cursors.Low_Bit_First,
      2#101#,
      Written);
   pragma
     Assert
       (Written
          and then Position = 3
          and then Ore.Bit_Cursors.Bits_At
                     (Bits_Out,
                      0,
                      3,
                      Ore.Bit_Cursors.Lsb_First,
                      Ore.Bit_Cursors.Low_Bit_First)
                   = 2#101#
          and then Ore.Bit_Cursors.Field_Value
                     (Bits_Out,
                      0,
                      3,
                      Ore.Bit_Cursors.Lsb_First,
                      Ore.Bit_Cursors.Low_Bit_First)
                   = 5
          and then Ore.Bits.Power_Of_Two_32 (4) = 16);
end Restriction_Smoke;
