package body Ore.Bits
  with SPARK_Mode => On
is

   --  Count_Bits is recursive and the loop invariants below are written
   --  against it, so evaluating them would cost far more than the counting
   --  loop they describe. They are proof-only; GNATprove verifies
   --  Ignore-policy assertions normally.
   pragma
     Assertion_Policy
       (Assert => Ignore, Loop_Invariant => Ignore, Ghost => Ignore);

   ---------------------------------------------------------------------------
   --  Bits of a word
   ---------------------------------------------------------------------------

   --  Agreement on every bit is a quantified hypothesis, and the equality of
   --  the two values is a bit-vector goal; a prover closes the goal once it
   --  has the hypothesis at each position, but will not choose those
   --  instances itself. Naming them is the whole proof.
   procedure Lemma_Bits_Equal (Left, Right : Byte) is
   begin
      pragma Assert (Bit (Left, 0) = Bit (Right, 0));
      pragma Assert (Bit (Left, 1) = Bit (Right, 1));
      pragma Assert (Bit (Left, 2) = Bit (Right, 2));
      pragma Assert (Bit (Left, 3) = Bit (Right, 3));
      pragma Assert (Bit (Left, 4) = Bit (Right, 4));
      pragma Assert (Bit (Left, 5) = Bit (Right, 5));
      pragma Assert (Bit (Left, 6) = Bit (Right, 6));
      pragma Assert (Bit (Left, 7) = Bit (Right, 7));
   end Lemma_Bits_Equal;

   procedure Lemma_Bits_Equal (Left, Right : Word16) is
   begin
      pragma Assert (Bit (Left, 0) = Bit (Right, 0));
      pragma Assert (Bit (Left, 1) = Bit (Right, 1));
      pragma Assert (Bit (Left, 2) = Bit (Right, 2));
      pragma Assert (Bit (Left, 3) = Bit (Right, 3));
      pragma Assert (Bit (Left, 4) = Bit (Right, 4));
      pragma Assert (Bit (Left, 5) = Bit (Right, 5));
      pragma Assert (Bit (Left, 6) = Bit (Right, 6));
      pragma Assert (Bit (Left, 7) = Bit (Right, 7));
      pragma Assert (Bit (Left, 8) = Bit (Right, 8));
      pragma Assert (Bit (Left, 9) = Bit (Right, 9));
      pragma Assert (Bit (Left, 10) = Bit (Right, 10));
      pragma Assert (Bit (Left, 11) = Bit (Right, 11));
      pragma Assert (Bit (Left, 12) = Bit (Right, 12));
      pragma Assert (Bit (Left, 13) = Bit (Right, 13));
      pragma Assert (Bit (Left, 14) = Bit (Right, 14));
      pragma Assert (Bit (Left, 15) = Bit (Right, 15));
   end Lemma_Bits_Equal;

   procedure Lemma_Bits_Equal (Left, Right : Word32) is
   begin
      pragma Assert (Bit (Left, 0) = Bit (Right, 0));
      pragma Assert (Bit (Left, 1) = Bit (Right, 1));
      pragma Assert (Bit (Left, 2) = Bit (Right, 2));
      pragma Assert (Bit (Left, 3) = Bit (Right, 3));
      pragma Assert (Bit (Left, 4) = Bit (Right, 4));
      pragma Assert (Bit (Left, 5) = Bit (Right, 5));
      pragma Assert (Bit (Left, 6) = Bit (Right, 6));
      pragma Assert (Bit (Left, 7) = Bit (Right, 7));
      pragma Assert (Bit (Left, 8) = Bit (Right, 8));
      pragma Assert (Bit (Left, 9) = Bit (Right, 9));
      pragma Assert (Bit (Left, 10) = Bit (Right, 10));
      pragma Assert (Bit (Left, 11) = Bit (Right, 11));
      pragma Assert (Bit (Left, 12) = Bit (Right, 12));
      pragma Assert (Bit (Left, 13) = Bit (Right, 13));
      pragma Assert (Bit (Left, 14) = Bit (Right, 14));
      pragma Assert (Bit (Left, 15) = Bit (Right, 15));
      pragma Assert (Bit (Left, 16) = Bit (Right, 16));
      pragma Assert (Bit (Left, 17) = Bit (Right, 17));
      pragma Assert (Bit (Left, 18) = Bit (Right, 18));
      pragma Assert (Bit (Left, 19) = Bit (Right, 19));
      pragma Assert (Bit (Left, 20) = Bit (Right, 20));
      pragma Assert (Bit (Left, 21) = Bit (Right, 21));
      pragma Assert (Bit (Left, 22) = Bit (Right, 22));
      pragma Assert (Bit (Left, 23) = Bit (Right, 23));
      pragma Assert (Bit (Left, 24) = Bit (Right, 24));
      pragma Assert (Bit (Left, 25) = Bit (Right, 25));
      pragma Assert (Bit (Left, 26) = Bit (Right, 26));
      pragma Assert (Bit (Left, 27) = Bit (Right, 27));
      pragma Assert (Bit (Left, 28) = Bit (Right, 28));
      pragma Assert (Bit (Left, 29) = Bit (Right, 29));
      pragma Assert (Bit (Left, 30) = Bit (Right, 30));
      pragma Assert (Bit (Left, 31) = Bit (Right, 31));
   end Lemma_Bits_Equal;

   procedure Lemma_Bits_Equal (Left, Right : Word64) is
   begin
      pragma Assert (Bit (Left, 0) = Bit (Right, 0));
      pragma Assert (Bit (Left, 1) = Bit (Right, 1));
      pragma Assert (Bit (Left, 2) = Bit (Right, 2));
      pragma Assert (Bit (Left, 3) = Bit (Right, 3));
      pragma Assert (Bit (Left, 4) = Bit (Right, 4));
      pragma Assert (Bit (Left, 5) = Bit (Right, 5));
      pragma Assert (Bit (Left, 6) = Bit (Right, 6));
      pragma Assert (Bit (Left, 7) = Bit (Right, 7));
      pragma Assert (Bit (Left, 8) = Bit (Right, 8));
      pragma Assert (Bit (Left, 9) = Bit (Right, 9));
      pragma Assert (Bit (Left, 10) = Bit (Right, 10));
      pragma Assert (Bit (Left, 11) = Bit (Right, 11));
      pragma Assert (Bit (Left, 12) = Bit (Right, 12));
      pragma Assert (Bit (Left, 13) = Bit (Right, 13));
      pragma Assert (Bit (Left, 14) = Bit (Right, 14));
      pragma Assert (Bit (Left, 15) = Bit (Right, 15));
      pragma Assert (Bit (Left, 16) = Bit (Right, 16));
      pragma Assert (Bit (Left, 17) = Bit (Right, 17));
      pragma Assert (Bit (Left, 18) = Bit (Right, 18));
      pragma Assert (Bit (Left, 19) = Bit (Right, 19));
      pragma Assert (Bit (Left, 20) = Bit (Right, 20));
      pragma Assert (Bit (Left, 21) = Bit (Right, 21));
      pragma Assert (Bit (Left, 22) = Bit (Right, 22));
      pragma Assert (Bit (Left, 23) = Bit (Right, 23));
      pragma Assert (Bit (Left, 24) = Bit (Right, 24));
      pragma Assert (Bit (Left, 25) = Bit (Right, 25));
      pragma Assert (Bit (Left, 26) = Bit (Right, 26));
      pragma Assert (Bit (Left, 27) = Bit (Right, 27));
      pragma Assert (Bit (Left, 28) = Bit (Right, 28));
      pragma Assert (Bit (Left, 29) = Bit (Right, 29));
      pragma Assert (Bit (Left, 30) = Bit (Right, 30));
      pragma Assert (Bit (Left, 31) = Bit (Right, 31));
      pragma Assert (Bit (Left, 32) = Bit (Right, 32));
      pragma Assert (Bit (Left, 33) = Bit (Right, 33));
      pragma Assert (Bit (Left, 34) = Bit (Right, 34));
      pragma Assert (Bit (Left, 35) = Bit (Right, 35));
      pragma Assert (Bit (Left, 36) = Bit (Right, 36));
      pragma Assert (Bit (Left, 37) = Bit (Right, 37));
      pragma Assert (Bit (Left, 38) = Bit (Right, 38));
      pragma Assert (Bit (Left, 39) = Bit (Right, 39));
      pragma Assert (Bit (Left, 40) = Bit (Right, 40));
      pragma Assert (Bit (Left, 41) = Bit (Right, 41));
      pragma Assert (Bit (Left, 42) = Bit (Right, 42));
      pragma Assert (Bit (Left, 43) = Bit (Right, 43));
      pragma Assert (Bit (Left, 44) = Bit (Right, 44));
      pragma Assert (Bit (Left, 45) = Bit (Right, 45));
      pragma Assert (Bit (Left, 46) = Bit (Right, 46));
      pragma Assert (Bit (Left, 47) = Bit (Right, 47));
      pragma Assert (Bit (Left, 48) = Bit (Right, 48));
      pragma Assert (Bit (Left, 49) = Bit (Right, 49));
      pragma Assert (Bit (Left, 50) = Bit (Right, 50));
      pragma Assert (Bit (Left, 51) = Bit (Right, 51));
      pragma Assert (Bit (Left, 52) = Bit (Right, 52));
      pragma Assert (Bit (Left, 53) = Bit (Right, 53));
      pragma Assert (Bit (Left, 54) = Bit (Right, 54));
      pragma Assert (Bit (Left, 55) = Bit (Right, 55));
      pragma Assert (Bit (Left, 56) = Bit (Right, 56));
      pragma Assert (Bit (Left, 57) = Bit (Right, 57));
      pragma Assert (Bit (Left, 58) = Bit (Right, 58));
      pragma Assert (Bit (Left, 59) = Bit (Right, 59));
      pragma Assert (Bit (Left, 60) = Bit (Right, 60));
      pragma Assert (Bit (Left, 61) = Bit (Right, 61));
      pragma Assert (Bit (Left, 62) = Bit (Right, 62));
      pragma Assert (Bit (Left, 63) = Bit (Right, 63));
   end Lemma_Bits_Equal;

   --  One operator at one position is a bit-vector fact a prover finds on its
   --  own; these lemmas exist so that it is asked for it once, where the
   --  positions are otherwise buried under a composition.
   procedure Lemma_And_Bits (Left, Right : Byte) is null;
   procedure Lemma_And_Bits (Left, Right : Word16) is null;
   procedure Lemma_And_Bits (Left, Right : Word32) is null;
   procedure Lemma_And_Bits (Left, Right : Word64) is null;

   procedure Lemma_Or_Bits (Left, Right : Byte) is null;
   procedure Lemma_Or_Bits (Left, Right : Word16) is null;
   procedure Lemma_Or_Bits (Left, Right : Word32) is null;
   procedure Lemma_Or_Bits (Left, Right : Word64) is null;

   procedure Lemma_Xor_Bits (Left, Right : Byte) is null;
   procedure Lemma_Xor_Bits (Left, Right : Word16) is null;
   procedure Lemma_Xor_Bits (Left, Right : Word32) is null;
   procedure Lemma_Xor_Bits (Left, Right : Word64) is null;

   procedure Lemma_Not_Bits (Value : Byte) is null;
   procedure Lemma_Not_Bits (Value : Word16) is null;
   procedure Lemma_Not_Bits (Value : Word32) is null;
   procedure Lemma_Not_Bits (Value : Word64) is null;

   ---------------------------------------------------------------------------
   --  Shifts and rotates
   ---------------------------------------------------------------------------

   function Shift_Left (Value : Byte; Amount : Bit_Count_8) return Byte
   is (Intrinsics.Shift_Left (Value, Amount));

   function Shift_Left (Value : Word16; Amount : Bit_Count_16) return Word16
   is (Intrinsics.Shift_Left (Value, Amount));

   function Shift_Left (Value : Word32; Amount : Bit_Count_32) return Word32
   is (Intrinsics.Shift_Left (Value, Amount));

   function Shift_Left (Value : Word64; Amount : Bit_Count_64) return Word64
   is (Intrinsics.Shift_Left (Value, Amount));

   function Shift_Right (Value : Byte; Amount : Bit_Count_8) return Byte
   is (Intrinsics.Shift_Right (Value, Amount));

   function Shift_Right (Value : Word16; Amount : Bit_Count_16) return Word16
   is (Intrinsics.Shift_Right (Value, Amount));

   function Shift_Right (Value : Word32; Amount : Bit_Count_32) return Word32
   is (Intrinsics.Shift_Right (Value, Amount));

   function Shift_Right (Value : Word64; Amount : Bit_Count_64) return Word64
   is (Intrinsics.Shift_Right (Value, Amount));

   function Rotate_Left (Value : Byte; Amount : Bit_Count_8) return Byte
   is (Intrinsics.Rotate_Left (Value, Amount));

   function Rotate_Left (Value : Word16; Amount : Bit_Count_16) return Word16
   is (Intrinsics.Rotate_Left (Value, Amount));

   function Rotate_Left (Value : Word32; Amount : Bit_Count_32) return Word32
   is (Intrinsics.Rotate_Left (Value, Amount));

   function Rotate_Left (Value : Word64; Amount : Bit_Count_64) return Word64
   is (Intrinsics.Rotate_Left (Value, Amount));

   function Rotate_Right (Value : Byte; Amount : Bit_Count_8) return Byte
   is (Intrinsics.Rotate_Right (Value, Amount));

   function Rotate_Right (Value : Word16; Amount : Bit_Count_16) return Word16
   is (Intrinsics.Rotate_Right (Value, Amount));

   function Rotate_Right (Value : Word32; Amount : Bit_Count_32) return Word32
   is (Intrinsics.Rotate_Right (Value, Amount));

   function Rotate_Right (Value : Word64; Amount : Bit_Count_64) return Word64
   is (Intrinsics.Rotate_Right (Value, Amount));

   ---------------------------------------------------------------------------
   --  Masks
   ---------------------------------------------------------------------------

   --  All ones shifted up by Count, complemented: the one formulation that
   --  needs no special case at either end of the range.
   function Low_Mask_8 (Count : Bit_Count_8) return Byte
   is (not Intrinsics.Shift_Left (Byte'Last, Count));

   function Low_Mask_16 (Count : Bit_Count_16) return Word16
   is (not Intrinsics.Shift_Left (Word16'Last, Count));

   function Low_Mask_32 (Count : Bit_Count_32) return Word32
   is (not Intrinsics.Shift_Left (Word32'Last, Count));

   function Low_Mask_64 (Count : Bit_Count_64) return Word64
   is (not Intrinsics.Shift_Left (Word64'Last, Count));

   procedure Lemma_Bound_Bits (Value : Byte; Count : Bit_Count_8) is null;
   procedure Lemma_Bound_Bits (Value : Word16; Count : Bit_Count_16) is null;
   procedure Lemma_Bound_Bits (Value : Word32; Count : Bit_Count_32) is null;
   procedure Lemma_Bound_Bits (Value : Word64; Count : Bit_Count_64) is null;

   procedure Lemma_Low_Mask_8_Monotonic (Left, Right : Bit_Count_8) is null;
   procedure Lemma_Low_Mask_16_Monotonic (Left, Right : Bit_Count_16) is null;
   procedure Lemma_Low_Mask_32_Monotonic (Left, Right : Bit_Count_32) is null;
   procedure Lemma_Low_Mask_64_Monotonic (Left, Right : Bit_Count_64) is null;

   procedure Lemma_Low_Mask_8_Natural (Count : Bit_Count_8) is null;
   procedure Lemma_Low_Mask_16_Natural (Count : Bit_Count_16) is null;
   procedure Lemma_Low_Mask_32_Natural (Count : Bit_Count_32) is null;
   procedure Lemma_Low_Mask_64_Natural (Count : Bit_Count_64) is null;

   function Field_Mask_8
     (Offset : Bit_Count_8; Count : Bit_Count_8) return Byte
   is (Shift_Left (Low_Mask_8 (Count), Offset));

   function Field_Mask_16
     (Offset : Bit_Count_16; Count : Bit_Count_16) return Word16
   is (Shift_Left (Low_Mask_16 (Count), Offset));

   function Field_Mask_32
     (Offset : Bit_Count_32; Count : Bit_Count_32) return Word32
   is (Shift_Left (Low_Mask_32 (Count), Offset));

   function Field_Mask_64
     (Offset : Bit_Count_64; Count : Bit_Count_64) return Word64
   is (Shift_Left (Low_Mask_64 (Count), Offset));

   ---------------------------------------------------------------------------
   --  Powers of two
   ---------------------------------------------------------------------------

   --  One shifted up, rather than the mask plus one: this way the bit-wise
   --  half of the contract is the shift's own, and the value follows from it.
   function Power_Of_Two_8 (Exponent : Bit_Index_8) return Byte
   is (Intrinsics.Shift_Left (1, Exponent));

   function Power_Of_Two_16 (Exponent : Bit_Index_16) return Word16
   is (Intrinsics.Shift_Left (1, Exponent));

   function Power_Of_Two_32 (Exponent : Bit_Index_32) return Word32
   is (Intrinsics.Shift_Left (1, Exponent));

   function Power_Of_Two_64 (Exponent : Bit_Index_64) return Word64
   is (Intrinsics.Shift_Left (1, Exponent));

   --  A weight is a mask plus one, and that is the step: the crossing is already
   --  proved for the mask, so the power's own crossing is an addition on either
   --  side of it rather than a second exponent for a prover to reason about. The
   --  narrower widths are written the same way, although they close without it.
   procedure Lemma_Power_Of_Two_8_Natural (Exponent : Bit_Index_8) is
   begin
      Lemma_Low_Mask_8_Natural (Exponent);
      pragma Assert (Power_Of_Two_8 (Exponent) = Low_Mask_8 (Exponent) + 1);
   end Lemma_Power_Of_Two_8_Natural;

   procedure Lemma_Power_Of_Two_16_Natural (Exponent : Bit_Index_16) is
   begin
      Lemma_Low_Mask_16_Natural (Exponent);
      pragma Assert (Power_Of_Two_16 (Exponent) = Low_Mask_16 (Exponent) + 1);
   end Lemma_Power_Of_Two_16_Natural;

   procedure Lemma_Power_Of_Two_32_Natural (Exponent : Bit_Index_32) is
   begin
      Lemma_Low_Mask_32_Natural (Exponent);
      pragma Assert (Power_Of_Two_32 (Exponent) = Low_Mask_32 (Exponent) + 1);
   end Lemma_Power_Of_Two_32_Natural;

   procedure Lemma_Power_Of_Two_64_Natural (Exponent : Bit_Index_64) is
   begin
      Lemma_Low_Mask_64_Natural (Exponent);
      pragma Assert (Power_Of_Two_64 (Exponent) = Low_Mask_64 (Exponent) + 1);
   end Lemma_Power_Of_Two_64_Natural;

   ---------------------------------------------------------------------------
   --  Bit fields
   ---------------------------------------------------------------------------

   function Extract
     (Value : Byte; Offset : Bit_Count_8; Count : Bit_Count_8) return Byte
   is (Shift_Right (Value, Offset) and Low_Mask_8 (Count));

   function Extract
     (Value : Word16; Offset : Bit_Count_16; Count : Bit_Count_16)
      return Word16
   is (Shift_Right (Value, Offset) and Low_Mask_16 (Count));

   function Extract
     (Value : Word32; Offset : Bit_Count_32; Count : Bit_Count_32)
      return Word32
   is (Shift_Right (Value, Offset) and Low_Mask_32 (Count));

   function Extract
     (Value : Word64; Offset : Bit_Count_64; Count : Bit_Count_64)
      return Word64
   is (Shift_Right (Value, Offset) and Low_Mask_64 (Count));

   function Insert
     (Value : Byte; Field : Byte; Offset : Bit_Count_8; Count : Bit_Count_8)
      return Byte
   is
      Mask    : constant Byte := Field_Mask_8 (Offset, Count);
      Cleared : constant Byte := Value and not Mask;
      Placed  : constant Byte := Shift_Left (Field, Offset);
   begin
      --  Which bits each half contributes, one range at a time: the field is
      --  a hole in Cleared and everything else is a hole in Placed, so the
      --  two never claim the same position.
      Lemma_Not_Bits (Mask);
      Lemma_And_Bits (Value, not Mask);

      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 => not Bit (Cleared, I));
      pragma
        Assert
          (for all I in 0 .. Offset - 1 => Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset + Count .. 7 =>
             Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Placed, I) = Bit (Field, I - Offset));
      pragma Assert (for all I in 0 .. Offset - 1 => not Bit (Placed, I));
      pragma Assert (for all I in Offset + Count .. 7 => not Bit (Placed, I));

      --  And the round trip the Runtime clause states: the field extracted
      --  from the result agrees with Field at every position, so it is the
      --  same value. Above the field both are clear — Field because it fits
      --  under its mask, the extraction because that is what it discards.
      Lemma_Or_Bits (Cleared, Placed);
      pragma Assert (for all I in Count .. 7 => not Bit (Field, I));
      pragma
        Assert
          (for all I in Bit_Index_8 =>
             Bit (Extract (Cleared or Placed, Offset, Count), I)
             = Bit (Field, I));
      Lemma_Bits_Equal (Extract (Cleared or Placed, Offset, Count), Field);

      return Cleared or Placed;
   end Insert;

   function Insert
     (Value  : Word16;
      Field  : Word16;
      Offset : Bit_Count_16;
      Count  : Bit_Count_16) return Word16
   is
      Mask    : constant Word16 := Field_Mask_16 (Offset, Count);
      Cleared : constant Word16 := Value and not Mask;
      Placed  : constant Word16 := Shift_Left (Field, Offset);
   begin
      --  Which bits each half contributes, one range at a time: the field is
      --  a hole in Cleared and everything else is a hole in Placed, so the
      --  two never claim the same position.
      Lemma_Not_Bits (Mask);
      Lemma_And_Bits (Value, not Mask);

      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 => not Bit (Cleared, I));
      pragma
        Assert
          (for all I in 0 .. Offset - 1 => Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset + Count .. 15 =>
             Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Placed, I) = Bit (Field, I - Offset));
      pragma Assert (for all I in 0 .. Offset - 1 => not Bit (Placed, I));
      pragma Assert (for all I in Offset + Count .. 15 => not Bit (Placed, I));

      --  And the round trip the Runtime clause states: the field extracted
      --  from the result agrees with Field at every position, so it is the
      --  same value. Above the field both are clear — Field because it fits
      --  under its mask, the extraction because that is what it discards.
      Lemma_Or_Bits (Cleared, Placed);
      pragma Assert (for all I in Count .. 15 => not Bit (Field, I));
      pragma
        Assert
          (for all I in Bit_Index_16 =>
             Bit (Extract (Cleared or Placed, Offset, Count), I)
             = Bit (Field, I));
      Lemma_Bits_Equal (Extract (Cleared or Placed, Offset, Count), Field);

      return Cleared or Placed;
   end Insert;

   function Insert
     (Value  : Word32;
      Field  : Word32;
      Offset : Bit_Count_32;
      Count  : Bit_Count_32) return Word32
   is
      Mask    : constant Word32 := Field_Mask_32 (Offset, Count);
      Cleared : constant Word32 := Value and not Mask;
      Placed  : constant Word32 := Shift_Left (Field, Offset);
   begin
      --  Which bits each half contributes, one range at a time: the field is
      --  a hole in Cleared and everything else is a hole in Placed, so the
      --  two never claim the same position.
      Lemma_Not_Bits (Mask);
      Lemma_And_Bits (Value, not Mask);

      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 => not Bit (Cleared, I));
      pragma
        Assert
          (for all I in 0 .. Offset - 1 => Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset + Count .. 31 =>
             Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Placed, I) = Bit (Field, I - Offset));
      pragma Assert (for all I in 0 .. Offset - 1 => not Bit (Placed, I));
      pragma Assert (for all I in Offset + Count .. 31 => not Bit (Placed, I));

      --  And the round trip the Runtime clause states: the field extracted
      --  from the result agrees with Field at every position, so it is the
      --  same value. Above the field both are clear — Field because it fits
      --  under its mask, the extraction because that is what it discards.
      Lemma_Or_Bits (Cleared, Placed);
      pragma Assert (for all I in Count .. 31 => not Bit (Field, I));
      pragma
        Assert
          (for all I in Bit_Index_32 =>
             Bit (Extract (Cleared or Placed, Offset, Count), I)
             = Bit (Field, I));
      Lemma_Bits_Equal (Extract (Cleared or Placed, Offset, Count), Field);

      return Cleared or Placed;
   end Insert;

   function Insert
     (Value  : Word64;
      Field  : Word64;
      Offset : Bit_Count_64;
      Count  : Bit_Count_64) return Word64
   is
      Mask    : constant Word64 := Field_Mask_64 (Offset, Count);
      Cleared : constant Word64 := Value and not Mask;
      Placed  : constant Word64 := Shift_Left (Field, Offset);
   begin
      --  Which bits each half contributes, one range at a time: the field is
      --  a hole in Cleared and everything else is a hole in Placed, so the
      --  two never claim the same position.
      Lemma_Not_Bits (Mask);
      Lemma_And_Bits (Value, not Mask);

      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 => not Bit (Cleared, I));
      pragma
        Assert
          (for all I in 0 .. Offset - 1 => Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset + Count .. 63 =>
             Bit (Cleared, I) = Bit (Value, I));
      pragma
        Assert
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Placed, I) = Bit (Field, I - Offset));
      pragma Assert (for all I in 0 .. Offset - 1 => not Bit (Placed, I));
      pragma Assert (for all I in Offset + Count .. 63 => not Bit (Placed, I));

      --  And the round trip the Runtime clause states: the field extracted
      --  from the result agrees with Field at every position, so it is the
      --  same value. Above the field both are clear — Field because it fits
      --  under its mask, the extraction because that is what it discards.
      Lemma_Or_Bits (Cleared, Placed);
      pragma Assert (for all I in Count .. 63 => not Bit (Field, I));
      pragma
        Assert
          (for all I in Bit_Index_64 =>
             Bit (Extract (Cleared or Placed, Offset, Count), I)
             = Bit (Field, I));
      Lemma_Bits_Equal (Extract (Cleared or Placed, Offset, Count), Field);

      return Cleared or Placed;
   end Insert;

   procedure Lemma_Insert_Frame
     (Value        : Byte;
      Field        : Byte;
      Offset       : Bit_Count_8;
      Count        : Bit_Count_8;
      Other_Offset : Bit_Count_8;
      Other_Count  : Bit_Count_8)
   is
      Written : constant Byte := Insert (Value, Field, Offset, Count);
      After   : constant Byte := Extract (Written, Other_Offset, Other_Count);
      Before  : constant Byte := Extract (Value, Other_Offset, Other_Count);
   begin
      --  Disjointness puts every position the other field reads outside the
      --  one just written, where Insert changed nothing; above the other
      --  field both extractions are clear.
      pragma
        Assert (for all I in Bit_Index_8 => Bit (After, I) = Bit (Before, I));
      Lemma_Bits_Equal (After, Before);
   end Lemma_Insert_Frame;

   procedure Lemma_Insert_Frame
     (Value        : Word16;
      Field        : Word16;
      Offset       : Bit_Count_16;
      Count        : Bit_Count_16;
      Other_Offset : Bit_Count_16;
      Other_Count  : Bit_Count_16)
   is
      Written : constant Word16 := Insert (Value, Field, Offset, Count);
      After   : constant Word16 :=
        Extract (Written, Other_Offset, Other_Count);
      Before  : constant Word16 := Extract (Value, Other_Offset, Other_Count);
   begin
      --  Disjointness puts every position the other field reads outside the
      --  one just written, where Insert changed nothing; above the other
      --  field both extractions are clear.
      pragma
        Assert (for all I in Bit_Index_16 => Bit (After, I) = Bit (Before, I));
      Lemma_Bits_Equal (After, Before);
   end Lemma_Insert_Frame;

   procedure Lemma_Insert_Frame
     (Value        : Word32;
      Field        : Word32;
      Offset       : Bit_Count_32;
      Count        : Bit_Count_32;
      Other_Offset : Bit_Count_32;
      Other_Count  : Bit_Count_32)
   is
      Written : constant Word32 := Insert (Value, Field, Offset, Count);
      After   : constant Word32 :=
        Extract (Written, Other_Offset, Other_Count);
      Before  : constant Word32 := Extract (Value, Other_Offset, Other_Count);
   begin
      --  Disjointness puts every position the other field reads outside the
      --  one just written, where Insert changed nothing; above the other
      --  field both extractions are clear.
      pragma
        Assert (for all I in Bit_Index_32 => Bit (After, I) = Bit (Before, I));
      Lemma_Bits_Equal (After, Before);
   end Lemma_Insert_Frame;

   procedure Lemma_Insert_Frame
     (Value        : Word64;
      Field        : Word64;
      Offset       : Bit_Count_64;
      Count        : Bit_Count_64;
      Other_Offset : Bit_Count_64;
      Other_Count  : Bit_Count_64)
   is
      Written : constant Word64 := Insert (Value, Field, Offset, Count);
      After   : constant Word64 :=
        Extract (Written, Other_Offset, Other_Count);
      Before  : constant Word64 := Extract (Value, Other_Offset, Other_Count);
   begin
      --  Disjointness puts every position the other field reads outside the
      --  one just written, where Insert changed nothing; above the other
      --  field both extractions are clear.
      pragma
        Assert (for all I in Bit_Index_64 => Bit (After, I) = Bit (Before, I));
      Lemma_Bits_Equal (After, Before);
   end Lemma_Insert_Frame;

   ---------------------------------------------------------------------------
   --  Bits and values
   ---------------------------------------------------------------------------

   --  The shifts need no proof here: inside this package a shift is the
   --  intrinsic, so its arithmetic is visible and the provers close it unaided.
   --  From outside it is not — a checked shift states only which bits it
   --  moves — which is the whole reason these lemmas exist rather than being
   --  left to a client.
   procedure Lemma_Shift_Left_Value (Value : Byte; Amount : Bit_Count_8)
   is null;

   procedure Lemma_Shift_Left_Value (Value : Word16; Amount : Bit_Count_16)
   is null;

   procedure Lemma_Shift_Left_Value (Value : Word32; Amount : Bit_Count_32)
   is null;

   procedure Lemma_Shift_Left_Value (Value : Word64; Amount : Bit_Count_64)
   is null;

   procedure Lemma_Shift_Right_Value (Value : Byte; Amount : Bit_Count_8)
   is null;

   procedure Lemma_Shift_Right_Value (Value : Word16; Amount : Bit_Count_16)
   is null;

   procedure Lemma_Shift_Right_Value (Value : Word32; Amount : Bit_Count_32)
   is null;

   procedure Lemma_Shift_Right_Value (Value : Word64; Amount : Bit_Count_64)
   is null;

   --  A field is a shift and then a mask, and the two steps are named
   --  separately here: the 64-bit goal is not closed with them left implicit,
   --  and the narrower widths are written the same way rather than differently
   --  for no reason a reader could see.
   procedure Lemma_Extract_Value
     (Value : Byte; Offset : Bit_Count_8; Count : Bit_Count_8) is
   begin
      Lemma_Shift_Right_Value (Value, Offset);
      pragma
        Assert
          ((Shift_Right (Value, Offset) and Low_Mask_8 (Count))
           = Shift_Right (Value, Offset) mod 2 ** Count);
   end Lemma_Extract_Value;

   procedure Lemma_Extract_Value
     (Value : Word16; Offset : Bit_Count_16; Count : Bit_Count_16) is
   begin
      Lemma_Shift_Right_Value (Value, Offset);
      pragma
        Assert
          ((Shift_Right (Value, Offset) and Low_Mask_16 (Count))
           = Shift_Right (Value, Offset) mod 2 ** Count);
   end Lemma_Extract_Value;

   procedure Lemma_Extract_Value
     (Value : Word32; Offset : Bit_Count_32; Count : Bit_Count_32) is
   begin
      Lemma_Shift_Right_Value (Value, Offset);
      pragma
        Assert
          ((Shift_Right (Value, Offset) and Low_Mask_32 (Count))
           = Shift_Right (Value, Offset) mod 2 ** Count);
   end Lemma_Extract_Value;

   procedure Lemma_Extract_Value
     (Value : Word64; Offset : Bit_Count_64; Count : Bit_Count_64) is
   begin
      Lemma_Shift_Right_Value (Value, Offset);
      pragma
        Assert
          ((Shift_Right (Value, Offset) and Low_Mask_64 (Count))
           = Shift_Right (Value, Offset) mod 2 ** Count);
   end Lemma_Extract_Value;

   --  The recurrence against the operation, by induction on the count: one more
   --  bit of the field is the field one bit shorter plus that bit's weight,
   --  which is the step stated as an assertion below because it is the only
   --  place the two views meet.
   procedure Lemma_Bits_Value (Value : Byte; Count : Bit_Count_8) is
   begin
      if Count = 0 then
         return;
      end if;

      Lemma_Bits_Value (Value, Count - 1);

      pragma
        Assert
          (Extract (Value, 0, Count)
           = Extract (Value, 0, Count - 1)
             + (if Bit (Value, Count - 1) then 2 ** (Count - 1) else 0));
   end Lemma_Bits_Value;

   procedure Lemma_Bits_Value (Value : Word16; Count : Bit_Count_16) is
   begin
      if Count = 0 then
         return;
      end if;

      Lemma_Bits_Value (Value, Count - 1);

      pragma
        Assert
          (Extract (Value, 0, Count)
           = Extract (Value, 0, Count - 1)
             + (if Bit (Value, Count - 1) then 2 ** (Count - 1) else 0));
   end Lemma_Bits_Value;

   procedure Lemma_Bits_Value (Value : Word32; Count : Bit_Count_32) is
   begin
      if Count = 0 then
         return;
      end if;

      Lemma_Bits_Value (Value, Count - 1);

      pragma
        Assert
          (Extract (Value, 0, Count)
           = Extract (Value, 0, Count - 1)
             + (if Bit (Value, Count - 1) then 2 ** (Count - 1) else 0));
   end Lemma_Bits_Value;

   procedure Lemma_Bits_Value (Value : Word64; Count : Bit_Count_64) is
   begin
      if Count = 0 then
         return;
      end if;

      Lemma_Bits_Value (Value, Count - 1);

      pragma
        Assert
          (Extract (Value, 0, Count)
           = Extract (Value, 0, Count - 1)
             + (if Bit (Value, Count - 1) then 2 ** (Count - 1) else 0));
   end Lemma_Bits_Value;

   ---------------------------------------------------------------------------
   --  Counting bits
   ---------------------------------------------------------------------------

   --  A bit at a time, in step with the recurrence the postcondition names.
   --  A word-parallel count would be faster and would need its own proof;
   --  the loop is what a reader can check against the specification.
   function Population_Count (Value : Byte) return Natural is
      Total : Natural := 0;
   begin
      for I in Bit_Index_8 loop
         if Bit (Value, I) then
            Total := Total + 1;
         end if;

         pragma Loop_Invariant (Total = Count_Bits (Value, I + 1));
         pragma
           Loop_Invariant
             ((Total = 0) = (for all J in 0 .. I => not Bit (Value, J)));
      end loop;

      --  A count of zero means no bit is set, which is the word zero.
      if Total = 0 then
         Lemma_Bits_Equal (Value, 0);
      end if;

      return Total;
   end Population_Count;

   function Population_Count (Value : Word16) return Natural is
      Total : Natural := 0;
   begin
      for I in Bit_Index_16 loop
         if Bit (Value, I) then
            Total := Total + 1;
         end if;

         pragma Loop_Invariant (Total = Count_Bits (Value, I + 1));
         pragma
           Loop_Invariant
             ((Total = 0) = (for all J in 0 .. I => not Bit (Value, J)));
      end loop;

      --  A count of zero means no bit is set, which is the word zero.
      if Total = 0 then
         Lemma_Bits_Equal (Value, 0);
      end if;

      return Total;
   end Population_Count;

   function Population_Count (Value : Word32) return Natural is
      Total : Natural := 0;
   begin
      for I in Bit_Index_32 loop
         if Bit (Value, I) then
            Total := Total + 1;
         end if;

         pragma Loop_Invariant (Total = Count_Bits (Value, I + 1));
         pragma
           Loop_Invariant
             ((Total = 0) = (for all J in 0 .. I => not Bit (Value, J)));
      end loop;

      --  A count of zero means no bit is set, which is the word zero.
      if Total = 0 then
         Lemma_Bits_Equal (Value, 0);
      end if;

      return Total;
   end Population_Count;

   function Population_Count (Value : Word64) return Natural is
      Total : Natural := 0;
   begin
      for I in Bit_Index_64 loop
         if Bit (Value, I) then
            Total := Total + 1;
         end if;

         pragma Loop_Invariant (Total = Count_Bits (Value, I + 1));
         pragma
           Loop_Invariant
             ((Total = 0) = (for all J in 0 .. I => not Bit (Value, J)));
      end loop;

      --  A count of zero means no bit is set, which is the word zero.
      if Total = 0 then
         Lemma_Bits_Equal (Value, 0);
      end if;

      return Total;
   end Population_Count;

   --  Scanning from the top: the first bit found is the most significant one
   --  set, and reaching the bottom without finding one leaves a word whose
   --  every bit is clear.
   function Leading_Zeroes (Value : Byte) return Natural is
   begin
      for I in reverse Bit_Index_8 loop
         if Bit (Value, I) then
            return 7 - I;
         end if;

         pragma Loop_Invariant (for all J in I .. 7 => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 8;
   end Leading_Zeroes;

   function Leading_Zeroes (Value : Word16) return Natural is
   begin
      for I in reverse Bit_Index_16 loop
         if Bit (Value, I) then
            return 15 - I;
         end if;

         pragma Loop_Invariant (for all J in I .. 15 => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 16;
   end Leading_Zeroes;

   function Leading_Zeroes (Value : Word32) return Natural is
   begin
      for I in reverse Bit_Index_32 loop
         if Bit (Value, I) then
            return 31 - I;
         end if;

         pragma Loop_Invariant (for all J in I .. 31 => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 32;
   end Leading_Zeroes;

   function Leading_Zeroes (Value : Word64) return Natural is
   begin
      for I in reverse Bit_Index_64 loop
         if Bit (Value, I) then
            return 63 - I;
         end if;

         pragma Loop_Invariant (for all J in I .. 63 => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 64;
   end Leading_Zeroes;

   function Trailing_Zeroes (Value : Byte) return Natural is
   begin
      for I in Bit_Index_8 loop
         if Bit (Value, I) then
            return I;
         end if;

         pragma Loop_Invariant (for all J in 0 .. I => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 8;
   end Trailing_Zeroes;

   function Trailing_Zeroes (Value : Word16) return Natural is
   begin
      for I in Bit_Index_16 loop
         if Bit (Value, I) then
            return I;
         end if;

         pragma Loop_Invariant (for all J in 0 .. I => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 16;
   end Trailing_Zeroes;

   function Trailing_Zeroes (Value : Word32) return Natural is
   begin
      for I in Bit_Index_32 loop
         if Bit (Value, I) then
            return I;
         end if;

         pragma Loop_Invariant (for all J in 0 .. I => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 32;
   end Trailing_Zeroes;

   function Trailing_Zeroes (Value : Word64) return Natural is
   begin
      for I in Bit_Index_64 loop
         if Bit (Value, I) then
            return I;
         end if;

         pragma Loop_Invariant (for all J in 0 .. I => not Bit (Value, J));
      end loop;

      Lemma_Bits_Equal (Value, 0);
      return 64;
   end Trailing_Zeroes;

   ---------------------------------------------------------------------------
   --  Bytes within a word
   ---------------------------------------------------------------------------

   --  Each byte moved to the position mirroring its own. Written out rather
   --  than looped: the byte count is fixed, and the masks say which byte goes
   --  where more directly than an index computation would.
   function Byte_Swap (Value : Word16) return Word16
   is (Intrinsics.Shift_Left (Value and 16#00FF#, 8)
       or Intrinsics.Shift_Right (Value and 16#FF00#, 8));

   function Byte_Swap (Value : Word32) return Word32
   is (Intrinsics.Shift_Left (Value and 16#0000_00FF#, 24)
       or Intrinsics.Shift_Left (Value and 16#0000_FF00#, 8)
       or Intrinsics.Shift_Right (Value and 16#00FF_0000#, 8)
       or Intrinsics.Shift_Right (Value and 16#FF00_0000#, 24));

   function Byte_Swap (Value : Word64) return Word64
   is (Intrinsics.Shift_Left (Value and 16#0000_0000_0000_00FF#, 56)
       or Intrinsics.Shift_Left (Value and 16#0000_0000_0000_FF00#, 40)
       or Intrinsics.Shift_Left (Value and 16#0000_0000_00FF_0000#, 24)
       or Intrinsics.Shift_Left (Value and 16#0000_0000_FF00_0000#, 8)
       or Intrinsics.Shift_Right (Value and 16#0000_00FF_0000_0000#, 8)
       or Intrinsics.Shift_Right (Value and 16#0000_FF00_0000_0000#, 24)
       or Intrinsics.Shift_Right (Value and 16#00FF_0000_0000_0000#, 40)
       or Intrinsics.Shift_Right (Value and 16#FF00_0000_0000_0000#, 56));

   procedure Lemma_Byte_Swap_Involutive (Value : Word16) is null;
   procedure Lemma_Byte_Swap_Involutive (Value : Word32) is null;
   procedure Lemma_Byte_Swap_Involutive (Value : Word64) is null;

   procedure Lemma_Bytes_Equal (Left, Right : Word16) is
   begin
      --  The hypothesis at each byte in turn: a prover closes the equality of
      --  the two words once it has the bytes named, but will not choose those
      --  instances itself.
      pragma
        Assert
          (Byte_At (Left, 0, Little_Endian)
           = Byte_At (Right, 0, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 1, Little_Endian)
           = Byte_At (Right, 1, Little_Endian));
   end Lemma_Bytes_Equal;

   procedure Lemma_Bytes_Equal (Left, Right : Word32) is
   begin
      --  The hypothesis at each byte in turn: a prover closes the equality of
      --  the two words once it has the bytes named, but will not choose those
      --  instances itself.
      pragma
        Assert
          (Byte_At (Left, 0, Little_Endian)
           = Byte_At (Right, 0, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 1, Little_Endian)
           = Byte_At (Right, 1, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 2, Little_Endian)
           = Byte_At (Right, 2, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 3, Little_Endian)
           = Byte_At (Right, 3, Little_Endian));
   end Lemma_Bytes_Equal;

   procedure Lemma_Bytes_Equal (Left, Right : Word64) is
   begin
      --  The hypothesis at each byte in turn: a prover closes the equality of
      --  the two words once it has the bytes named, but will not choose those
      --  instances itself.
      pragma
        Assert
          (Byte_At (Left, 0, Little_Endian)
           = Byte_At (Right, 0, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 1, Little_Endian)
           = Byte_At (Right, 1, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 2, Little_Endian)
           = Byte_At (Right, 2, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 3, Little_Endian)
           = Byte_At (Right, 3, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 4, Little_Endian)
           = Byte_At (Right, 4, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 5, Little_Endian)
           = Byte_At (Right, 5, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 6, Little_Endian)
           = Byte_At (Right, 6, Little_Endian));
      pragma
        Assert
          (Byte_At (Left, 7, Little_Endian)
           = Byte_At (Right, 7, Little_Endian));
   end Lemma_Bytes_Equal;

end Ore.Bits;
