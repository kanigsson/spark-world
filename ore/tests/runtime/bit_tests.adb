--  Runtime tests for Ore.Bits. The bit-level postconditions are Static and so
--  never execute, which is exactly why these tests exist: what a contract says
--  about which bits a result has, the assertions below say as a value a reader
--  can check against a specification by eye. The Runtime-level clauses — the
--  counts and the fits-under-its-mask fact — are checked by -gnata as the test
--  calls each operation.

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Ore;         use Ore;
with Ore.Bits;    use Ore.Bits;

procedure Bit_Tests is

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if not Condition then
         Failures := Failures + 1;
         Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   ---------------------------------------------------------------------------

   procedure Test_Bit is
   begin
      Check (Bit (Byte'(16#A5#), 0), "bit 0 of A5");
      Check (not Bit (Byte'(16#A5#), 1), "bit 1 of A5");
      Check (Bit (Byte'(16#A5#), 7), "bit 7 of A5");
      Check (not Bit (Word64'(1), 63), "top bit of one");
      Check (Bit (Word64'(2 ** 63), 63), "top bit of the top power");
   end Test_Bit;

   procedure Test_Shifts is
   begin
      Check (Shift_Left (Byte'(1), 7) = 16#80#, "shift a byte to the top");
      Check (Shift_Left (Byte'(1), 8) = 0, "shift a byte out entirely");
      Check (Shift_Right (Byte'(16#80#), 7) = 1, "shift a byte back down");
      Check (Shift_Right (Word32'(16#1234_5678#), 16) = 16#1234#, "shift 32");
      Check
        (Shift_Left (Word32'(16#1234_5678#), 16) = 16#5678_0000#,
         "shift 32 the other way");
      Check
        (Shift_Right (Word64'(Word64'Last), 64) = 0, "shift 64 out entirely");
      Check
        (Shift_Left (Word16'(16#00FF#), 4) = 16#0FF0#, "shift within a word");
   end Test_Shifts;

   procedure Test_Rotates is
   begin
      Check (Rotate_Left (Byte'(16#81#), 1) = 16#03#, "rotate a byte left");
      Check (Rotate_Right (Byte'(16#81#), 1) = 16#C0#, "rotate a byte right");
      Check (Rotate_Left (Byte'(16#A5#), 8) = 16#A5#, "rotate by the width");
      Check (Rotate_Left (Byte'(16#A5#), 0) = 16#A5#, "rotate by nothing");
      Check
        (Rotate_Left (Word32'(16#1234_5678#), 8) = 16#3456_7812#,
         "rotate 32 by a byte");
      Check
        (Rotate_Right (Word32'(16#1234_5678#), 8) = 16#7812_3456#,
         "rotate 32 back");
      Check
        (Rotate_Left (Word64'(1), 63) = 2 ** 63, "rotate 64 to the top bit");
   end Test_Rotates;

   procedure Test_Masks is
   begin
      Check (Low_Mask_8 (0) = 0, "an empty mask");
      Check (Low_Mask_8 (3) = 2#0000_0111#, "three low bits");
      Check (Low_Mask_8 (8) = 16#FF#, "the full-width byte mask");
      Check (Low_Mask_16 (16) = 16#FFFF#, "the full-width 16-bit mask");
      Check (Low_Mask_32 (32) = 16#FFFF_FFFF#, "the full-width 32-bit mask");
      Check (Low_Mask_64 (64) = Word64'Last, "the full-width 64-bit mask");

      Check (Field_Mask_8 (0, 0) = 0, "an empty field mask");
      Check (Field_Mask_8 (5, 3) = 2#1110_0000#, "the top three bits");
      Check (Field_Mask_32 (8, 8) = 16#0000_FF00#, "the second byte");
      Check (Field_Mask_32 (32, 0) = 0, "an empty field at the end");

      --  The value clauses are Runtime clauses, so -gnata has checked them at
      --  each call above; what these add is the value written the way a client
      --  writes a bound, against the mask it would otherwise tabulate.
      for Count in Bit_Count_32 range 0 .. 31 loop
         Check
           (Low_Mask_32 (Count) = 2 ** Count - 1,
            "the low 32-bit mask is two to the count less one");
      end loop;
      Check
        (Low_Mask_32 (32) = Word32'Last, "the full-width mask is every bit");
      Check
        (Field_Mask_32 (8, 8) = Low_Mask_32 (8) * 2 ** 8,
         "a field mask is its low mask moved up");
   end Test_Masks;

   procedure Test_Fields is
      Packed : Word32;
   begin
      Check
        (Extract (Word32'(16#1234_5678#), 8, 8) = 16#56#,
         "extract the second byte");
      Check
        (Extract (Word32'(16#1234_5678#), 0, 32) = 16#1234_5678#,
         "extract everything");
      Check (Extract (Word32'(16#1234_5678#), 4, 0) = 0, "extract nothing");

      Check
        (Insert (Word32'(16#1234_5678#), 16#AB#, 8, 8) = 16#1234_AB78#,
         "insert into the second byte");
      Check
        (Insert (Word32'(16#FFFF_FFFF#), 0, 0, 32) = 0, "insert everything");
      Check
        (Insert (Word32'(16#1234_5678#), 0, 4, 0) = 16#1234_5678#,
         "insert nothing");

      --  What a header field does: three fields packed and read back.
      Packed := 0;
      Packed := Insert (Packed, 5, 0, 4);
      Packed := Insert (Packed, 16#2A#, 4, 6);
      Packed := Insert (Packed, 1, 10, 1);
      Check (Extract (Packed, 0, 4) = 5, "first packed field");
      Check (Extract (Packed, 4, 6) = 16#2A#, "second packed field");
      Check (Extract (Packed, 10, 1) = 1, "third packed field");
      Check (Extract (Packed, 11, 21) = 0, "nothing above the fields");
   end Test_Fields;

   procedure Test_Counting is
   begin
      Check (Population_Count (Byte'(0)) = 0, "no bits set");
      Check (Population_Count (Byte'(16#FF#)) = 8, "every bit of a byte");
      Check (Population_Count (Word16'(16#F0F0#)) = 8, "half the bits");
      Check (Population_Count (Word64'Last) = 64, "every bit of a word");

      Check (Leading_Zeroes (Byte'(0)) = 8, "leading zeroes of nothing");
      Check (Leading_Zeroes (Byte'(1)) = 7, "leading zeroes of one");
      Check (Leading_Zeroes (Byte'(16#80#)) = 0, "leading zeroes of the top");
      Check
        (Leading_Zeroes (Word32'(16#0001_0000#)) = 15, "leading zeroes 32");
      Check (Leading_Zeroes (Word64'(1)) = 63, "leading zeroes 64");

      Check (Trailing_Zeroes (Byte'(0)) = 8, "trailing zeroes of nothing");
      Check (Trailing_Zeroes (Byte'(1)) = 0, "trailing zeroes of one");
      Check
        (Trailing_Zeroes (Byte'(16#80#)) = 7, "trailing zeroes of the top");
      Check
        (Trailing_Zeroes (Word32'(16#0001_0000#)) = 16, "trailing zeroes 32");
      Check (Trailing_Zeroes (Word64'(2 ** 63)) = 63, "trailing zeroes 64");
   end Test_Counting;

   procedure Test_Bytes is
   begin
      Check
        (Byte_At (Word32'(16#1234_5678#), 0, Little_Endian) = 16#78#,
         "the least significant byte");
      Check
        (Byte_At (Word32'(16#1234_5678#), 0, Big_Endian) = 16#12#,
         "the most significant byte");
      Check
        (Byte_At (Word16'(16#ABCD#), 1, Little_Endian) = 16#AB#,
         "the high byte of a 16-bit word");
      Check
        (Byte_At (Word64'(16#0102_0304_0506_0708#), 3, Big_Endian) = 16#04#,
         "a byte in the middle of a 64-bit word");

      Check (Byte_Swap (Word16'(16#ABCD#)) = 16#CDAB#, "swap two bytes");
      Check
        (Byte_Swap (Word32'(16#1234_5678#)) = 16#7856_3412#,
         "swap four bytes");
      Check
        (Byte_Swap (Word64'(16#0102_0304_0506_0708#))
         = 16#0807_0605_0403_0201#,
         "swap eight bytes");
      Check
        (Byte_Swap (Byte_Swap (Word32'(16#1234_5678#))) = 16#1234_5678#,
         "swapping twice is the identity");
   end Test_Bytes;

   procedure Test_Widths is
   begin
      Check
        (Truncate_To_Byte (Word32'(16#1234_5678#)) = 16#78#, "truncate to 8");
      Check
        (Truncate_To_Word16 (Word64'(16#0102_0304_0506_0708#)) = 16#0708#,
         "truncate to 16");
      Check
        (Truncate_To_Word32 (Word64'Last) = 16#FFFF_FFFF#, "truncate to 32");

      Check (Extend_To_Word16 (Byte'(16#FF#)) = 16#00FF#, "extend to 16");
      Check
        (Extend_To_Word64 (Word32'(16#FFFF_FFFF#)) = 16#FFFF_FFFF#,
         "extend to 64");
      Check
        (Truncate_To_Byte (Extend_To_Word32 (Byte'(16#A5#))) = 16#A5#,
         "extend then truncate");
   end Test_Widths;

begin
   Test_Bit;
   Test_Shifts;
   Test_Rotates;
   Test_Masks;
   Test_Fields;
   Test_Counting;
   Test_Bytes;
   Test_Widths;

   if Failures = 0 then
      Put_Line ("bit_tests: all checks passed");
   else
      Put_Line ("bit_tests:" & Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Bit_Tests;
