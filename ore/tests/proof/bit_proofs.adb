package body Bit_Proofs
  with SPARK_Mode => On
is

   pragma
     Assertion_Policy
       (Assert => Ignore, Loop_Invariant => Ignore, Ghost => Ignore);

   function Pack (Version : Word32; Kind : Word32; Flag : Word32) return Word32
   is
      Empty        : constant Word32 := 0;
      With_Version : constant Word32 :=
        Insert (Empty, Version, Version_Offset, Version_Width);
      With_Kind    : constant Word32 :=
        Insert (With_Version, Kind, Kind_Offset, Kind_Width);
      Result       : constant Word32 :=
        Insert (With_Kind, Flag, Flag_Offset, Flag_Width);

      Rest_Offset : constant := Flag_Offset + Flag_Width;
      Rest_Width  : constant := 32 - Rest_Offset;
   begin
      --  Each field reads back through the round trip in Insert's own
      --  postcondition. What the frame lemma adds is that the inserts which
      --  came after a field left it alone — including the bits above every
      --  field, which no insert touched and which the initial value left
      --  clear.
      Lemma_Insert_Frame
        (With_Version,
         Kind,
         Kind_Offset,
         Kind_Width,
         Version_Offset,
         Version_Width);
      Lemma_Insert_Frame
        (With_Kind,
         Flag,
         Flag_Offset,
         Flag_Width,
         Version_Offset,
         Version_Width);
      Lemma_Insert_Frame
        (With_Kind, Flag, Flag_Offset, Flag_Width, Kind_Offset, Kind_Width);

      Lemma_Insert_Frame
        (Empty,
         Version,
         Version_Offset,
         Version_Width,
         Rest_Offset,
         Rest_Width);
      Lemma_Insert_Frame
        (With_Version, Kind, Kind_Offset, Kind_Width, Rest_Offset, Rest_Width);
      Lemma_Insert_Frame
        (With_Kind, Flag, Flag_Offset, Flag_Width, Rest_Offset, Rest_Width);

      --  Those three carry the top of the word back to the value the packing
      --  started from, where every bit of the extracted field is clear.
      pragma
        Assert
          (for all I in Bit_Index_32 =>
             Bit (Extract (Empty, Rest_Offset, Rest_Width), I)
             = Bit (Word32'(0), I));
      Lemma_Bits_Equal (Extract (Empty, Rest_Offset, Rest_Width), 0);

      return Result;
   end Pack;

   function Significant_Bits (Value : Word32) return Natural is
      Width   : constant Natural := 32 - Leading_Zeroes (Value);
      Shifted : constant Word32 := Shift_Right (Value, Width);
   begin
      --  Every bit of the shifted word comes from a position at or above
      --  Width, and Leading_Zeroes says those are all clear; a word whose
      --  bits are all clear is the word zero.
      pragma
        Assert
          (Static =>
             (for all I in Bit_Index_32 =>
                Bit (Shifted, I) = Bit (Word32'(0), I)));
      Lemma_Bits_Equal (Shifted, 0);

      return Width;
   end Significant_Bits;

end Bit_Proofs;
