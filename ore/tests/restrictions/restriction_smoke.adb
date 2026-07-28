with Ore;
with Ore.Byte_Buffers;

procedure Restriction_Smoke is
   use type Ore.Byte;

   B : Ore.Byte_Buffers.Buffer (1);
begin
   Ore.Byte_Buffers.Append (B, 0);
   pragma
     Assert
       (Ore.Byte_Buffers.Length (B) = 1
        and then Ore.Byte_Buffers.Element (B, 1) = 0);
end Restriction_Smoke;
