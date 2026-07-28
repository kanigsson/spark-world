--  The implementation is one bit at a time, in both directions. A field of
--  Count bits crosses a byte boundary in general, so a shift-and-mask
--  implementation is a case distinction on how the field straddles the bytes
--  it touches, with a different one for each order; the loop below is the same
--  code for every case and every order, and its cost is the cost of the
--  format — a decoder that walks a Huffman tree reads its bits one at a time
--  in any case.
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
