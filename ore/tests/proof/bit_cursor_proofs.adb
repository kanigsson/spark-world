package body Bit_Cursor_Proofs
  with SPARK_Mode => On
is

   pragma
     Assertion_Policy
       (Assert => Ignore, Loop_Invariant => Ignore, Ghost => Ignore);

   ---------------------------------------------------------------------------
   --  A header of two fields
   ---------------------------------------------------------------------------

   procedure Put_Header
     (Output   : in out Byte_Array;
      Position : in out Natural;
      Final    : Boolean;
      Kind     : Word32;
      Success  : out Boolean)
   is
      Start : constant Natural := Position;

      Flag_Written, Kind_Written : Boolean;

      Before : constant Byte_Array := Output
      with Ghost => Static;

      --  The array between the two puts: the flag is written and the kind is
      --  not, which is the state the frame of the second put is stated
      --  against.
      Middle : Byte_Array (Output'Range)
      with Ghost => Static;
   begin
      --  Both fields are checked once, so that a header is either written
      --  whole or not at all -- a put that failed halfway would leave the
      --  cursor and the array in a state this client has no contract for.
      if not Fits (Output, Start, Header_Width) then
         Success := False;
         return;
      end if;

      Put_Bits
        (Output,
         Position,
         Final_Width,
         Numbering,
         Low_Bit_First,
         (if Final then 1 else 0),
         Flag_Written);

      Middle := Output;

      Put_Bits
        (Output,
         Position,
         Kind_Width,
         Numbering,
         Low_Bit_First,
         Kind,
         Kind_Written);

      Success := Flag_Written and then Kind_Written;

      --  The flag survives the put of the kind: its bit position is outside
      --  the window that put wrote, which is arithmetic, and a field over
      --  unchanged bits is an unchanged field, which is the lemma.
      Lemma_Bits_At_Frame
        (Middle, Output, Start, Final_Width, Numbering, Low_Bit_First);
   end Put_Header;

   procedure Take_Header
     (Input    : Byte_Array;
      Position : in out Natural;
      Final    : out Boolean;
      Kind     : out Word32;
      Success  : out Boolean)
   is
      Start : constant Natural := Position;

      Flag : Word32;

      Flag_Read, Kind_Read : Boolean;
   begin
      if not Fits (Input, Start, Header_Width) then
         Final := False;
         Kind := 0;
         Success := False;
         return;
      end if;

      Take_Bits
        (Input,
         Position,
         Final_Width,
         Numbering,
         Low_Bit_First,
         Flag,
         Flag_Read);

      Take_Bits
        (Input,
         Position,
         Kind_Width,
         Numbering,
         Low_Bit_First,
         Kind,
         Kind_Read);

      --  A one-bit field is zero or one, which the client reads off the value
      --  of the mask its take is bounded by rather than off its bits.
      pragma Assert (Flag <= Low_Mask_32 (Final_Width));
      pragma Assert (Flag <= 1);

      Final := Flag = 1;
      Success := Flag_Read and then Kind_Read;
   end Take_Header;

   ---------------------------------------------------------------------------
   --  A code, and the arithmetic view of it
   ---------------------------------------------------------------------------

   procedure Lemma_Code_Sum (A : Byte_Array; Position : Natural) is
      Field : constant Word32 :=
        Bits_At (A, Position, Code_Width, Numbering, High_Bit_First);

      Sum : constant Word32 :=
        4 * Word32 (Bit_Value (A, Position, Numbering))
        + 2 * Word32 (Bit_Value (A, Position + 1, Numbering))
        + Word32 (Bit_Value (A, Position + 2, Numbering));
   begin
      --  The field is under its mask, so it is the weighted sum of three bits
      --  and the weights are constants. It is the variable exponent, not the
      --  sum, that a step from bits to a value founders on.
      pragma Assert (Field <= Low_Mask_32 (Code_Width));
      pragma Assert (Field <= 7);
      pragma
        Assert
          (Natural (Field)
           = 4 * (if Bit (Field, 2) then 1 else 0)
             + 2 * (if Bit (Field, 1) then 1 else 0)
             + (if Bit (Field, 0) then 1 else 0));

      pragma Assert (Static => Natural (Field) = Code_Sum (A, Position));
      pragma Assert (Static => Field = Sum);
   end Lemma_Code_Sum;

   ---------------------------------------------------------------------------
   --  A client that writes its own bytes
   ---------------------------------------------------------------------------

   procedure Put_Bit_By_Hand
     (Output : in out Byte_Array; Position : Natural; Value : Boolean)
   is
      Target : constant Index := Byte_Of (Output, Position);
      Within : constant Bit_Index_8 := Bit_In_Byte (Position, Numbering);
      Mask   : constant Byte := Field_Mask_8 (Within, 1);

      Before : constant Byte_Array := Output
      with Ghost => Static;
   begin
      if Value then
         Output (Target) := Output (Target) or Mask;
      else
         Output (Target) := Output (Target) and not Mask;
      end if;

      --  What the store did to the byte, bit by bit: the mask has the one bit
      --  the position names, so every other bit of the byte is either or-ed
      --  with zero or and-ed with one.
      Lemma_Or_Bits (Before (Target), Mask);
      Lemma_Not_Bits (Mask);
      Lemma_And_Bits (Before (Target), not Mask);

      --  One byte changed, one bit within it: the array-level frame follows,
      --  and this client does not prove it.
      Lemma_Bit_Frame (Before, Output, Position, Numbering);
   end Put_Bit_By_Hand;

end Bit_Cursor_Proofs;
