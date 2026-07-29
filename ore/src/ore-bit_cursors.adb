--  The implementation is one bit at a time, in both directions. A field of
--  Count bits crosses a byte boundary in general, so a shift-and-mask
--  implementation is a case distinction on how the field straddles the bytes it
--  touches, with a different one for each order; the loop below is the same code
--  for every case and every order, and what it costs is a step per bit.
--
--  That is a real cost and not only a proof convenience. A tree walk reads its
--  bits one at a time anyway, but the loop around a tree walk does not, and a
--  reader whose throughput is measured wants an accumulator instead — which the
--  spec says is out of scope rather than slow here.
--
--  Each step is a single-bit Bits.Insert, whose frame condition says that the
--  bits already placed did not move. That is what the loop invariants are
--  written against: one range for the bits placed so far and one for the bits
--  still clear, in the order the range bounds make the case distinction the
--  provers need.

pragma Assertion_Policy (Ghost => Ignore);

package body Ore.Bit_Cursors
  with SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Fields
   ---------------------------------------------------------------------------

   function Bits_At
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order) return Word32
   is
      Result : Word32 := 0;
   begin
      case Order is
         when Low_Bit_First  =>
            --  The first bit taken is the least significant one, so the bits
            --  placed so far are the low ones and the rest are still clear.
            for K in 0 .. Count - 1 loop
               Result :=
                 Bits.Insert
                   (Result,
                    (if Bit (A, Position + K, Numbering) then 1 else 0),
                    K,
                    1);

               pragma
                 Loop_Invariant
                   (Static =>
                      (for all J in 0 .. K =>
                         Bits.Bit (Result, J)
                         = Bit (A, Position + J, Numbering)));
               pragma
                 Loop_Invariant
                   (Static =>
                      (for all I in K + 1 .. 31 => not Bits.Bit (Result, I)));
            end loop;

         when High_Bit_First =>
            --  The first bit taken is the most significant one of the field,
            --  so the bits placed so far are those at the top of the field,
            --  and the ones below them are still clear.
            for K in 0 .. Count - 1 loop
               Result :=
                 Bits.Insert
                   (Result,
                    (if Bit (A, Position + K, Numbering) then 1 else 0),
                    Count - 1 - K,
                    1);

               pragma
                 Loop_Invariant
                   (Static =>
                      (for all J in 0 .. K =>
                         Bits.Bit (Result, Count - 1 - J)
                         = Bit (A, Position + J, Numbering)));
               pragma
                 Loop_Invariant
                   (Static =>
                      (for all I in 0 .. Count - 2 - K =>
                         not Bits.Bit (Result, I)));
               pragma
                 Loop_Invariant
                   (Static =>
                      (for all I in Count .. 31 => not Bits.Bit (Result, I)));
            end loop;
      end case;

      --  The Runtime clause of the postcondition is an arithmetic bound, and
      --  what the loop established is that no bit above the field is set.
      --  Extracting the field is the value again, and an extracted field is
      --  bounded by its mask.
      pragma
        Assert
          (Static =>
             (for all I in Bits.Bit_Index_32 =>
                Bits.Bit (Bits.Extract (Result, 0, Count), I)
                = Bits.Bit (Result, I)));
      Bits.Lemma_Bits_Equal (Bits.Extract (Result, 0, Count), Result);

      return Result;
   end Bits_At;

   procedure Lemma_Bits_At_Frame
     (Before, After : Byte_Array;
      Position      : Natural;
      Count         : Bits.Bit_Count_32;
      Numbering     : Bit_Numbering;
      Order         : Field_Order)
   is
      --  Every bit of the two fields comes from a bit position the hypothesis
      --  equates, above the field both are clear, and two words that agree bit
      --  by bit are the same word.
      Left  : constant Word32 :=
        Bits_At (After, Position, Count, Numbering, Order);
      Right : constant Word32 :=
        Bits_At (Before, Position, Count, Numbering, Order);
   begin
      --  The contract of Bits_At quantifies over the bits taken from the
      --  array; the goal quantifies over the bits of the value. Under one
      --  order those are the same numbering and under the other they run
      --  opposite, so the position each bit of the value was taken from is
      --  named here rather than left to be found.
      for I in 0 .. Count - 1 loop
         declare
            Taken : constant Natural :=
              (if Order = Low_Bit_First then I else Count - 1 - I);
            Slot  : constant Natural :=
              (if Order = Low_Bit_First then Taken else Count - 1 - Taken);
         begin
            pragma Assert (Static => Slot = I);
            pragma
              Assert
                (Static =>
                   Bits.Bit (Left, Slot)
                   = Bit (After, Position + Taken, Numbering));
            pragma
              Assert
                (Static =>
                   Bits.Bit (Right, Slot)
                   = Bit (Before, Position + Taken, Numbering));
            pragma Assert (Static => Bits.Bit (Left, I) = Bits.Bit (Right, I));
         end;

         pragma
           Loop_Invariant
             (Static =>
                (for all J in 0 .. I =>
                   Bits.Bit (Left, J) = Bits.Bit (Right, J)));
      end loop;

      pragma
        Assert
          (Static =>
             (for all I in Count .. 31 =>
                Bits.Bit (Left, I) = Bits.Bit (Right, I)));
      Bits.Lemma_Bits_Equal (Left, Right);
   end Lemma_Bits_At_Frame;

   ---------------------------------------------------------------------------
   --  A field as a number
   ---------------------------------------------------------------------------

   procedure Lemma_Bits_At_Recursion
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order)
   is
      Whole : constant Word32 :=
        Bits_At (A, Position, Count, Numbering, Order);

      --  Where the field one bit shorter starts, and where the bit it does not
      --  have is: at the end under High_Bit_First, at the beginning under
      --  Low_Bit_First, which under either order is the least significant bit
      --  of the value.
      Shorter_Position : constant Natural :=
        (if Order = High_Bit_First then Position else Position + 1);
      Lowest_Position  : constant Natural :=
        (if Order = High_Bit_First then Position + Count - 1 else Position);

      Shorter : constant Word32 :=
        Bits_At (A, Shorter_Position, Count - 1, Numbering, Order);

      Lowest : constant Boolean := Bit (A, Lowest_Position, Numbering);
   begin
      --  The shorter field is the whole one shifted down by a bit. Proving it
      --  means naming, for each bit, the position both fields took it from: the
      --  contracts quantify over the bits taken and this quantifies over the
      --  bits of a value, and under High_Bit_First the two run opposite.
      for I in Bits.Bit_Index_32 loop
         if I <= Count - 2 then
            declare
               Whole_Taken : constant Natural :=
                 (if Order = High_Bit_First then Count - 2 - I else I + 1);
               Short_Taken : constant Natural :=
                 (if Order = High_Bit_First then Count - 2 - I else I);

               Whole_Slot : constant Natural :=
                 (if Order = Low_Bit_First
                  then Whole_Taken
                  else Count - 1 - Whole_Taken);
               Short_Slot : constant Natural :=
                 (if Order = Low_Bit_First
                  then Short_Taken
                  else Count - 2 - Short_Taken);
            begin
               pragma Assert (Static => Whole_Slot = I + 1);
               pragma Assert (Static => Short_Slot = I);
               pragma
                 Assert
                   (Static =>
                      Position + Whole_Taken = Shorter_Position + Short_Taken);
               pragma
                 Assert
                   (Static =>
                      Bits.Bit (Whole, Whole_Slot)
                      = Bit (A, Position + Whole_Taken, Numbering));
               pragma
                 Assert
                   (Static =>
                      Bits.Bit (Shorter, Short_Slot)
                      = Bit (A, Shorter_Position + Short_Taken, Numbering));
            end;
         end if;

         pragma
           Loop_Invariant
             (Static =>
                (for all J in 0 .. I =>
                   Bits.Bit (Bits.Shift_Right (Whole, 1), J)
                   = Bits.Bit (Shorter, J)));
      end loop;

      Bits.Lemma_Bits_Equal (Bits.Shift_Right (Whole, 1), Shorter);

      --  A shift is a division, so the shorter field is half the whole one.
      Bits.Lemma_Shift_Right_Value (Whole, 1);

      --  And the bit it dropped is the remainder: the one-bit field at the
      --  bottom of the word, which the recurrence of Bits_Value states as a
      --  number and the value of a field states as a remainder.
      declare
         Lowest_Taken : constant Natural :=
           (if Order = High_Bit_First then Count - 1 else 0);
         Lowest_Slot  : constant Natural :=
           (if Order = Low_Bit_First
            then Lowest_Taken
            else Count - 1 - Lowest_Taken);
      begin
         pragma Assert (Static => Lowest_Slot = 0);
         pragma Assert (Static => Position + Lowest_Taken = Lowest_Position);
         pragma
           Assert
             (Static =>
                Bits.Bit (Whole, Lowest_Slot)
                = Bit (A, Position + Lowest_Taken, Numbering));
      end;

      Bits.Lemma_Bits_Value (Whole, 1);
      Bits.Lemma_Extract_Value (Whole, 0, 1);

      pragma
        Assert
          (Static => Bits.Bits_Value (Whole, 1) = (if Lowest then 1 else 0));
      pragma Assert (Whole mod 2 = (if Lowest then 1 else 0));
      pragma Assert (Whole = 2 * (Whole / 2) + Whole mod 2);
   end Lemma_Bits_At_Recursion;

   function Field_Value
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Value_Count;
      Numbering : Bit_Numbering;
      Order     : Field_Order) return Natural
   is
      Field : constant Word32 :=
        Bits_At (A, Position, Count, Numbering, Order);
   begin
      --  The conversion is the whole operation, and what it needs is the bound
      --  of the field as a number. The mask is one less than the power it stops
      --  at; a count no wider than this one puts that power inside a Natural
      --  with a bit to spare. Both steps are what a client would otherwise take
      --  at each of its own conversions.
      Bits.Lemma_Low_Mask_32_Monotonic (Count, 30);

      pragma Assert (Field <= Bits.Low_Mask_32 (Count));
      pragma Assert (Field <= Bits.Low_Mask_32 (30));
      pragma Assert (Bits.Low_Mask_32 (30) = 2 ** 30 - 1);
      pragma Assert (Bits.Low_Mask_32 (Count) = 2 ** Count - 1);

      return Natural (Field);
   end Field_Value;

   procedure Lemma_Field_Value_Recursion
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Value_Count;
      Numbering : Bit_Numbering;
      Order     : Field_Order)
   is
      Shorter_Position : constant Natural :=
        (if Order = High_Bit_First then Position else Position + 1);
      Lowest_Position  : constant Natural :=
        (if Order = High_Bit_First then Position + Count - 1 else Position);

      Whole   : constant Word32 :=
        Bits_At (A, Position, Count, Numbering, Order);
      Shorter : constant Word32 :=
        Bits_At (A, Shorter_Position, Count - 1, Numbering, Order);

      Lowest : constant Natural := Bit_Value (A, Lowest_Position, Numbering);
   begin
      --  The same equation, moved out of the word type. Both fields are under a
      --  mask this width keeps inside a Natural, so the conversion is faithful
      --  and the doubling is the same doubling.
      Lemma_Bits_At_Recursion (A, Position, Count, Numbering, Order);

      Bits.Lemma_Low_Mask_32_Monotonic (Count, 30);
      Bits.Lemma_Low_Mask_32_Monotonic (Count - 1, 30);

      pragma Assert (Whole <= Bits.Low_Mask_32 (30));
      pragma Assert (Shorter <= Bits.Low_Mask_32 (30));
      pragma Assert (Bits.Low_Mask_32 (30) = 2 ** 30 - 1);
      pragma Assert (Whole = 2 * Shorter + Word32 (Lowest));
      pragma Assert (Natural (Whole) = 2 * Natural (Shorter) + Lowest);
   end Lemma_Field_Value_Recursion;

   ---------------------------------------------------------------------------
   --  Writing
   ---------------------------------------------------------------------------

   procedure Lemma_Bit_Frame
     (Before, After : Byte_Array;
      Position      : Natural;
      Numbering     : Bit_Numbering)
   is null;

   procedure Set_Bit
     (A         : in out Byte_Array;
      Position  : Natural;
      Value     : Boolean;
      Numbering : Bit_Numbering)
   is
      Target : constant Index := Byte_Of (A, Position);
      Within : constant Bits.Bit_Index_8 := Bit_In_Byte (Position, Numbering);

      Before : constant Byte_Array := A
      with Ghost => Static;
   begin
      A (Target) :=
        Bits.Insert (A (Target), (if Value then 1 else 0), Within, 1);

      --  One byte changed and, within it, one bit: the array-level frame is
      --  that step, which is exactly what the lemma states.
      Lemma_Bit_Frame (Before, A, Position, Numbering);
   end Set_Bit;

   ---------------------------------------------------------------------------
   --  Cursors
   ---------------------------------------------------------------------------

   procedure Take_Bits
     (A         : Byte_Array;
      Position  : in out Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order;
      Value     : out Word32;
      Success   : out Boolean) is
   begin
      if Fits (A, Position, Count) then
         Value := Bits_At (A, Position, Count, Numbering, Order);
         Position := Position + Count;
         Success := True;
      else
         Value := 0;
         Success := False;
      end if;
   end Take_Bits;

   procedure Put_Bits
     (A         : in out Byte_Array;
      Position  : in out Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order;
      Value     : Word32;
      Success   : out Boolean)
   is
      Start : constant Natural := Position;

      Before : constant Byte_Array := A
      with Ghost => Static;
   begin
      if not Fits (A, Start, Count) then
         Success := False;
         return;
      end if;

      Success := True;

      --  Value has no bits above the field, which is the fact the round trip
      --  in the postcondition needs and which the precondition states as a
      --  bound.
      Bits.Lemma_Bound_Bits (Value, Count);

      for K in 0 .. Count - 1 loop
         Set_Bit
           (A,
            Start + K,
            Bits.Bit
              (Value, (if Order = Low_Bit_First then K else Count - 1 - K)),
            Numbering);

         --  The bits written so far, the bit positions the whole put has not
         --  reached, and the bytes it has not reached: the last two are the
         --  two frames of the postcondition, accumulated one Set_Bit at a
         --  time.
         pragma
           Loop_Invariant
             (Static =>
                (for all J in 0 .. K =>
                   Bit (A, Start + J, Numbering)
                   = Bits.Bit
                       (Value,
                        (if Order = Low_Bit_First
                         then J
                         else Count - 1 - J))));
         pragma
           Loop_Invariant
             (Static =>
                Bits_Unchanged_Outside (Before, A, Start, K + 1, Numbering));
         pragma
           Loop_Invariant
             (Static =>
                Byte_Buffers.Unchanged_Outside
                  (Before, A, Byte_Of (A, Start), Byte_Of (A, Start + K) + 1));
      end loop;

      --  The round trip: the field reads back bit for bit as the value that
      --  went in, and two words that agree bit by bit are the same word.
      pragma
        Assert
          (Static =>
             (for all I in Bits.Bit_Index_32 =>
                Bits.Bit (Bits_At (A, Start, Count, Numbering, Order), I)
                = Bits.Bit (Value, I)));
      Bits.Lemma_Bits_Equal
        (Bits_At (A, Start, Count, Numbering, Order), Value);

      Position := Start + Count;
   end Put_Bits;

end Ore.Bit_Cursors;
