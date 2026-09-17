with Ada.Text_IO;  use Ada.Text_IO;
with Inflate;      use Inflate;
with Inflate.LZ77;
with Inflate.Model;

procedure LZ77_Test is
   Data     : Byte_Array (1 .. 32) := (others => 0);
   Before   : Byte_Array (Data'Range);
   Produced : Natural;
begin
   --  Distance one: replicate the immediately preceding byte.
   Data (1 .. 4) := (1, 2, 3, 9);
   Before := Data;
   Produced := 4;
   Inflate.LZ77.Copy_Match (Data, Produced, 6, 1);
   pragma Assert (Produced = 10);
   pragma Assert (Data (1 .. 10) = (1, 2, 3, 9, 9, 9, 9, 9, 9, 9));
   pragma Assert (Inflate.Model.Copies_Match (Before, Data, 4, 6, 1));
   Put_Line ("distance-one run passed");

   --  Distance at least length: source and destination do not overlap.
   Data := (others => 0);
   Data (1 .. 8) := (1, 2, 3, 4, 10, 11, 12, 13);
   Before := Data;
   Produced := 8;
   Inflate.LZ77.Copy_Match (Data, Produced, 4, 4);
   pragma Assert (Produced = 12);
   pragma Assert (Data (9 .. 12) = (10, 11, 12, 13));
   pragma Assert (Inflate.Model.Copies_Match (Before, Data, 8, 4, 4));
   Put_Line ("non-overlapping match passed");

   --  General overlap: the three-byte source repeats through eight bytes.
   Data := (others => 0);
   Data (1 .. 6) := (1, 2, 3, 7, 8, 9);
   Before := Data;
   Produced := 6;
   Inflate.LZ77.Copy_Match (Data, Produced, 8, 3);
   pragma Assert (Produced = 14);
   pragma Assert (Data (7 .. 14) = (7, 8, 9, 7, 8, 9, 7, 8));
   pragma Assert (Inflate.Model.Copies_Match (Before, Data, 6, 8, 3));
   Put_Line ("overlapping match passed");
end LZ77_Test;
