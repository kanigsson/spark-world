with Ada.Text_IO;          use Ada.Text_IO;
with Huffman_Round_Trip;   use Huffman_Round_Trip;

procedure Huffman_Round_Trip_Test is
   Lengths : Full_Length_Array := (others => 0);
   Book    : Codebook;
   Success : Boolean;
   Input   : Message_Buffer := (others => 0);
   Bits    : Bit_Buffer;
   Output  : Message_Buffer;
   Used    : Bit_Count;
   Count   : Message_Count;
begin
   --  A small complete canonical code: 0, 10, 110, 111.
   Lengths (0 .. 3) := (1, 2, 3, 3);
   Build (Lengths, Book, Success);
   pragma Assert (Success);

   Input (0 .. 7) := (0, 1, 2, 3, 3, 2, 1, 0);
   Round_Trip (Book, Input, 8, Bits, Used, Output, Count);
   pragma Assert (Count = 8);
   pragma Assert (Output (0 .. 7) = Input (0 .. 7));
   Put_Line
     ("8 symbols ->" & Used'Image & " bits ->" & Count'Image & " symbols");

   --  The RFC 1951 fixed literal/length assignment exercises the full
   --  288-symbol alphabet and its 7-, 8-, and 9-bit code lengths.
   for I in Lengths'Range loop
      Lengths (I) :=
        (if I <= 143 then 8 elsif I <= 255 then 9
         elsif I <= 279 then 7 else 8);
   end loop;
   Build (Lengths, Book, Success);
   pragma Assert (Success);
   Input (0 .. 7) := (0, 143, 144, 255, 256, 279, 280, 287);
   Round_Trip (Book, Input, 8, Bits, Used, Output, Count);
   pragma Assert (Count = 8);
   pragma Assert (Output (0 .. 7) = Input (0 .. 7));
   Put_Line ("RFC fixed code round-trip passed");

   --  Empty sequences are part of the theorem as well.
   Round_Trip (Book, Input, 0, Bits, Used, Output, Count);
   pragma Assert (Used = 0 and Count = 0);
   Put_Line ("empty sequence round-trip passed");
end Huffman_Round_Trip_Test;
