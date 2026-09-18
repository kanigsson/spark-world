--  Runtime tests for Ore.Bit_Cursors. The frame conditions and the field
--  contracts are Static and so never execute, which is why these tests exist:
--  what a contract says about which bit positions a value came from, the
--  assertions below say as a number a reader can check against a bit-numbering
--  table by eye. The Runtime clauses — the cursor advanced by what it was
--  asked for, the value under its mask, nothing moved when the bits ran out —
--  are checked by -gnata as the test calls each operation.

with Ada.Text_IO;     use Ada.Text_IO;
with Test_Checks;     use Test_Checks;
with Ore;             use Ore;
with Ore.Bits;        use Ore.Bits;
with Ore.Bit_Cursors; use Ore.Bit_Cursors;

procedure Bit_Cursor_Tests is

   ---------------------------------------------------------------------------

   --  Two bytes whose bits are worth writing out. Numbered from the least
   --  significant bit of each byte, the positions 0 .. 15 hold
   --
   --     0 0 1 1 0 1 0 1   1 0 0 0 1 1 0 0
   --
   --  and numbered from the most significant bit they hold the reverse of each
   --  group of eight.
   Sample : constant Byte_Array (1 .. 2) := (2#1010_1100#, 2#0011_0001#);

   Empty : constant Byte_Array (1 .. 0) := (others => 0);

   ---------------------------------------------------------------------------

   procedure Test_Positions is
   begin
      Check (Fits (Sample, 0, 0), "an empty field fits at the start");
      Check (Fits (Sample, 0, 16), "every bit of the array fits");
      Check (not Fits (Sample, 0, 17), "one bit too many does not fit");
      Check (Fits (Sample, 15, 1), "the last bit fits");
      Check (not Fits (Sample, 16, 1), "one past the last bit does not");
      Check (Fits (Empty, 0, 0), "an empty field fits in an empty array");
      Check (not Fits (Empty, 0, 1), "an empty array has no bits");
      Check
        (Fits (Sample, Natural'Last, 0),
         "an empty field fits at a position the array does not have");

      Check (Byte_Of (Sample, 0) = 1, "the first bit is in the first byte");
      Check (Byte_Of (Sample, 7) = 1, "the eighth bit is still in it");
      Check (Byte_Of (Sample, 8) = 2, "the ninth bit is in the second");

      Check (Bit_In_Byte (9, Lsb_First) = 1, "numbered from the low end");
      Check (Bit_In_Byte (9, Msb_First) = 6, "numbered from the high end");

      Check (Is_Byte_Aligned (0), "the start is aligned");
      Check (not Is_Byte_Aligned (7), "the eighth bit is not");
      Check (Is_Byte_Aligned (16), "the third byte is");

      Check (Align_To_Byte (0) = 0, "an aligned position does not move");
      Check (Align_To_Byte (1) = 8, "the next boundary after the first bit");
      Check (Align_To_Byte (8) = 8, "a boundary is its own boundary");
      Check (Align_To_Byte (15) = 16, "the next boundary after the last bit");
   end Test_Positions;

   ---------------------------------------------------------------------------

   procedure Test_Bits is
   begin
      Check (not Bit (Sample, 0, Lsb_First), "position 0, low end first");
      Check (Bit (Sample, 2, Lsb_First), "position 2, low end first");
      Check (Bit (Sample, 7, Lsb_First), "position 7, low end first");
      Check (Bit (Sample, 8, Lsb_First), "the first bit of the next byte");
      Check (not Bit (Sample, 15, Lsb_First), "the last bit");

      Check (Bit (Sample, 0, Msb_First), "position 0, high end first");
      Check (not Bit (Sample, 1, Msb_First), "position 1, high end first");
      Check (not Bit (Sample, 8, Msb_First), "the next byte, high end first");

      Check (Bit_Value (Sample, 0, Lsb_First) = 0, "the bit as a number");
      Check (Bit_Value (Sample, 2, Lsb_First) = 1, "a set bit as a number");
   end Test_Bits;

   ---------------------------------------------------------------------------

   --  What the sixteen bits of Sample are, taken low bit first: the first byte
   --  is the low half, because position 0 is its least significant bit.
   Sample_As_Field : constant Word32 := 16#31AC#;

   procedure Test_Fields is
   begin
      --  The low four bits of the first byte, taken low bit first: the number
      --  is the field in place.
      Check
        (Bits_At (Sample, 0, 4, Lsb_First, Low_Bit_First) = 2#1100#,
         "four bits, low bit first");

      --  The same four bits taken high bit first: the first bit read is the
      --  most significant one, so the field is reversed.
      Check
        (Bits_At (Sample, 0, 4, Lsb_First, High_Bit_First) = 2#0011#,
         "four bits, high bit first");

      --  Across the byte boundary, which is the case a shift-and-mask
      --  implementation would have to distinguish: positions 6, 7, 8, 9 hold
      --  0, 1, 1, 0.
      Check
        (Bits_At (Sample, 6, 4, Lsb_First, Low_Bit_First) = 2#0110#,
         "four bits across the boundary, low bit first");
      Check
        (Bits_At (Sample, 6, 4, Lsb_First, High_Bit_First) = 2#0110#,
         "four bits across the boundary, high bit first");

      --  The other numbering reads the same byte from its other end.
      Check
        (Bits_At (Sample, 0, 4, Msb_First, Low_Bit_First) = 2#0101#,
         "four bits of the high end, low bit first");

      Check
        (Bits_At (Sample, 0, 0, Lsb_First, Low_Bit_First) = 0,
         "an empty field is zero");
      Check
        (Bits_At (Sample, 0, 16, Lsb_First, Low_Bit_First) = Sample_As_Field,
         "the whole array as one field");
   end Test_Fields;

   ---------------------------------------------------------------------------

   procedure Test_Values is
   begin
      --  The same fields as numbers rather than as words: what a client that
      --  computes with what it reads gets without writing a conversion.
      Check
        (Field_Value (Sample, 0, 4, Lsb_First, Low_Bit_First) = 12,
         "four bits as a number, low bit first");
      Check
        (Field_Value (Sample, 0, 4, Lsb_First, High_Bit_First) = 3,
         "four bits as a number, high bit first");
      Check
        (Field_Value (Sample, 0, 0, Lsb_First, Low_Bit_First) = 0,
         "an empty field is zero");

      --  The recurrence the lemmas state, as arithmetic on values: a field is
      --  twice the field without its least significant bit, plus that bit. That
      --  bit is the last one taken under one order and the first under the
      --  other, which is the only difference between them.
      for Count in 1 .. 12 loop
         Check
           (Field_Value (Sample, 0, Count, Lsb_First, High_Bit_First)
            = 2
              * Field_Value (Sample, 0, Count - 1, Lsb_First, High_Bit_First)
              + Bit_Value (Sample, Count - 1, Lsb_First),
            "the recurrence, high bit first");
         Check
           (Field_Value (Sample, 0, Count, Lsb_First, Low_Bit_First)
            = 2
              * Field_Value (Sample, 1, Count - 1, Lsb_First, Low_Bit_First)
              + Bit_Value (Sample, 0, Lsb_First),
            "the recurrence, low bit first");
      end loop;
   end Test_Values;

   ---------------------------------------------------------------------------

   procedure Test_Take is
      Position : Natural;
      Value    : Word32;
      Success  : Boolean;
   begin
      --  Two takes on one cursor, in the two orders a bit-packed format
      --  alternates between.
      Position := 0;
      Take_Bits
        (Sample, Position, 3, Lsb_First, Low_Bit_First, Value, Success);
      Check (Success, "the first take succeeds");
      Check (Position = 3, "the cursor advanced by three");
      Check (Value = 2#100#, "three bits, low bit first");

      Take_Bits
        (Sample, Position, 5, Lsb_First, High_Bit_First, Value, Success);
      Check (Success, "the second take succeeds");
      Check (Position = 8, "the cursor advanced to the byte boundary");
      --  Positions 3 .. 7 hold 1, 0, 1, 0, 1, and the first of them is the
      --  most significant bit of the code.
      Check (Value = 2#10101#, "five bits, high bit first");

      --  Running out of bits moves nothing, which is what lets the caller
      --  retry the same take once more bytes have arrived.
      Position := 14;
      Take_Bits
        (Sample, Position, 4, Lsb_First, Low_Bit_First, Value, Success);
      Check (not Success, "a take past the end fails");
      Check (Position = 14, "a failed take does not move the cursor");
      Check (Value = 0, "a failed take reports no value");

      --  An empty take is legal anywhere the cursor happens to be.
      Position := 16;
      Take_Bits
        (Sample, Position, 0, Lsb_First, Low_Bit_First, Value, Success);
      Check (Success, "an empty take at the end succeeds");
      Check (Position = 16 and then Value = 0, "and reads nothing");
   end Test_Take;

   ---------------------------------------------------------------------------

   procedure Test_Put is
      Output   : Byte_Array (1 .. 3);
      Position : Natural;
      Value    : Word32;
      Success  : Boolean;
   begin
      --  A header low bit first and a code high bit first, on one cursor, then
      --  read back the same way: the round trip a format's writer and reader
      --  form.
      Output := (others => 0);
      Position := 0;
      Put_Bits
        (Output, Position, 3, Lsb_First, Low_Bit_First, 2#101#, Success);
      Check (Success, "the header is written");
      Put_Bits
        (Output,
         Position,
         9,
         Lsb_First,
         High_Bit_First,
         2#1_1000_0011#,
         Success);
      Check (Success, "the code is written");
      Check (Position = 12, "the cursor advanced by both fields");

      Check (Output (3) = 0, "the byte the put did not reach is untouched");

      Position := 0;
      Take_Bits
        (Output, Position, 3, Lsb_First, Low_Bit_First, Value, Success);
      Check
        (Success and then Value = 2#101#, "the header reads back as it went");
      Take_Bits
        (Output, Position, 9, Lsb_First, High_Bit_First, Value, Success);
      Check
        (Success and then Value = 2#1_1000_0011#,
         "the code reads back as it went");

      --  A put that does not fit changes neither the array nor the cursor.
      declare
         Before : constant Byte_Array := Output;
      begin
         Position := 22;
         Put_Bits
           (Output, Position, 4, Lsb_First, Low_Bit_First, 2#1111#, Success);
         Check (not Success, "a put past the end fails");
         Check (Position = 22, "a failed put does not move the cursor");
         Check (Output = Before, "a failed put changes nothing");
      end;

      --  Set_Bit and its two frames, as a value: one bit of one byte.
      Output := (others => 0);
      Set_Bit (Output, 9, True, Lsb_First);
      Check
        (Output = Byte_Array'(0, 2#0000_0010#, 0),
         "one bit set, low end first");
      Set_Bit (Output, 9, False, Lsb_First);
      Check (Output = Byte_Array'(0, 0, 0), "and cleared again");

      Set_Bit (Output, 9, True, Msb_First);
      Check
        (Output = Byte_Array'(0, 2#0100_0000#, 0),
         "one bit set, high end first");
   end Test_Put;

begin
   Start ("bit_cursor_tests");
   Test_Positions;
   Test_Bits;
   Test_Fields;
   Test_Values;
   Test_Take;
   Test_Put;

   Report;
end Bit_Cursor_Tests;
