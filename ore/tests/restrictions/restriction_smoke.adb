with Ore;
with Ore.Bits;
with Ore.Byte_Buffers;

procedure Restriction_Smoke is
   use type Ore.Byte;
   use type Ore.Word16;

   B : Ore.Byte_Buffers.Buffer (1);
begin
   Ore.Byte_Buffers.Append (B, 0);
   pragma
     Assert
       (Ore.Byte_Buffers.Length (B) = 1
        and then Ore.Byte_Buffers.Element (B, 1) = 0);

   --  Both children have to be in the partition for the binder to check them
   --  against the restrictions, not just compiled.
   pragma
     Assert
       (Ore.Bits.Population_Count (Ore.Bits.Low_Mask_8 (3)) = 3
        and then Ore.Bits.Byte_Swap (Ore.Word16'(16#00FF#)) = 16#FF00#);
end Restriction_Smoke;
