--  Ore.Bit_Cursors — bit-addressed access to a plain byte array.
--
--  A bit-oriented format addresses bits by their position in a stream of
--  octets, not by their position in a word. This package is that addressing:
--  the bit at a position of a Byte_Array, the field of Count bits starting at
--  a position, and a position that a take or a put moves along. Ore.Bits is
--  the word layer underneath it — this package states everything in terms of
--  Bits.Bit, and its own operations are Bits.Insert applied to one byte of an
--  array at a time.
--
--  NO BUFFER OWNS THE BITS. A cursor here is a Natural position and a
--  Byte_Array the caller supplies, exactly as Load_16 and Store_16 are
--  defined on the array a caller already has. A bounded owning container
--  cannot wrap memory it did not allocate, and the ceiling that suits a
--  bounded container is not the ceiling of an input a caller mapped or read;
--  so the bit layer takes neither. Reading the bits of a Buffer means reading
--  the bits of a Slice of it.
--
--  POSITIONS. A bit position is 0-based and counts across the whole array
--  from its first byte, so position 8 is the first bit of the second byte
--  whatever that byte's index is. Byte positions stay 1-based, as everywhere
--  else in Ore, and the conversion between the two numberings happens in
--  Byte_Of and nowhere else.
--
--  NO PRODUCT OF LENGTH AND EIGHT. The number of bit positions an array has
--  is eight times its length, and for an array a caller owns that product can
--  leave Natural — Byte_Array admits nearly Positive'Last bytes, and the
--  Max_Capacity ceiling of the bounded buffers does not apply to an array
--  this package is handed. Every bound is therefore written as a division or
--  a subtraction: Fits divides the last position it would touch, and the
--  frame vocabulary takes a count rather than a one-past-the-end position,
--  because a position one past the last bit of a large array need not exist.
--
--  TWO ORDERS, AND THEY ARE INDEPENDENT. Which bit of a byte a stream starts
--  at is one question: Bit_Numbering answers it, and it is a property of the
--  format. How the bits taken from consecutive positions assemble into a
--  value is another: Field_Order answers that, and a format may answer it
--  differently for two fields of the same stream — DEFLATE packs its header
--  fields low bit first and its Huffman codes high bit first, both read out
--  of a stream numbered from the least significant bit of each byte. Neither
--  order is a setting made once; both are arguments of each operation.
--
--  WHAT THIS IS NOT. Every operation here costs one step per bit, and the
--  contracts are what that buys: a field is specified by which position each of
--  its bits came from, in either order, at any offset. A decoder whose
--  throughput is measured does not read that way — it keeps a word-sized
--  accumulator, refills it a byte at a time and takes a field with one shift and
--  one mask — and that reader is neither here nor buildable out of what is here,
--  because the accumulator's state is the bits already consumed from the array
--  and not yet from the stream, which a position in the array cannot represent.
--  Ore.Byte_Buffers.Load_32 and the shifts and masks of Ore.Bits are what such a
--  reader is built from, and the invariant tying its accumulator to a bit
--  position is its own. This is said here so that the next client reads it
--  rather than benchmarks it.
--
--  POSITIONS ARE NATURAL. A stream with more bit positions than a Natural holds
--  is out of the range of this layer, even where the array holding it is not:
--  the bounds below are divisions so that no length ceiling is needed, but the
--  position parameter is still a Natural. A client that counts bit positions in
--  a wider type keeps its own accessors — the division-and-subtraction style is
--  the part that generalises, the profile is the part that does not.
--
--  FRAMING. What a client cannot write for itself, and most wants to inherit,
--  is the step from "one byte of the array changed, and one bit within it" to
--  "one bit position of the array changed". Set_Bit states it as a
--  postcondition and Lemma_Bit_Frame states it as a lemma, for a client that
--  writes its bytes itself.
--
--  ASSERTION LEVEL. As in Ore.Bits, a statement about bits is a Static clause
--  and never executes: the frame conditions quantify over the bit positions of
--  a whole array, and the value clauses of a field are one term per bit. What
--  is left for a Runtime clause is the scalar part — a value fits under its
--  mask, a cursor advanced by the count it was asked for, a take that ran out
--  of bits moved nothing.
--
--  The two configuration pragmas below are repeated here rather than left to
--  the library's own configuration file, because a client compiling against
--  this spec applies its own configuration, not ours.

--  Postconditions are written as conjunctions of independent clauses, so most
--  'Old prefixes sit under a short-circuit operator and are formally
--  "potentially unevaluated". The prefixes here are scalar cursors or ghost
--  array copies, both harmless to evaluate on entry.
pragma Unevaluated_Use_Of_Old (Allow);

--  Static assertions contain proof-only models and are always ignored by the
--  compiler. Executable contracts and assertions remain enabled by -gnata.
pragma Assertion_Policy (Ghost => Ignore);

with Ore.Bits;
with Ore.Byte_Buffers;

package Ore.Bit_Cursors
  with Pure, SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Orders
   ---------------------------------------------------------------------------

   --  Which bit of a byte the stream's first bit is. Lsb_First numbers the
   --  bits of each byte from its least significant end, which is how a
   --  bit-packed format that also stores its multi-byte fields little-endian
   --  reads; Msb_First numbers them from the most significant end, which is
   --  how a format that draws its bits as a picture of a byte reads.
   type Bit_Numbering is (Lsb_First, Msb_First);

   --  Where the first bit taken lands in the value. Low_Bit_First makes the
   --  first bit of the field the least significant bit of the value, so a
   --  wider field is the same number with more bits above it; High_Bit_First
   --  makes it the most significant bit of the field, which is how a
   --  variable-length code is read, one bit at a time, deeper into a tree.
   type Field_Order is (Low_Bit_First, High_Bit_First);

   ---------------------------------------------------------------------------
   --  Positions
   ---------------------------------------------------------------------------

   --  Does the array hold Count bit positions from Position on? This is the
   --  bounds check of every operation here, and it is written so that nothing
   --  it evaluates can overflow: the end position is formed only once it is
   --  known to exist, and the byte it falls in is a division. An empty field
   --  fits anywhere, including at a position the array does not have — there
   --  is no bit to read there and none to write.
   function Fits
     (A : Byte_Array; Position : Natural; Count : Natural) return Boolean
   is (Count = 0
       or else
         (Position <= Natural'Last - Count
          and then (Position + Count - 1) / 8 < A'Length))
   with Global => null;

   --  The byte a bit position falls in, as an index of the array.
   function Byte_Of (A : Byte_Array; Position : Natural) return Index
   is (A'First + Position / 8)
   with Global => null, Pre => Fits (A, Position, 1);

   --  Which bit of that byte it is, as a bit position of the byte. This is
   --  where the two numberings meet, and the only place they do.
   function Bit_In_Byte
     (Position : Natural; Numbering : Bit_Numbering) return Bits.Bit_Index_8
   is (if Numbering = Lsb_First then Position mod 8 else 7 - Position mod 8)
   with Global => null;

   --  Is a position at a byte boundary, and the first boundary at or after a
   --  position. A format that pads to a byte before its next field asks the
   --  first; the second is where that field begins. Skipping to the boundary
   --  reads no bits and writes none, so neither takes an array.
   function Is_Byte_Aligned (Position : Natural) return Boolean
   is (Position mod 8 = 0)
   with Global => null;

   function Align_To_Byte (Position : Natural) return Natural
   is (if Position mod 8 = 0 then Position else Position - Position mod 8 + 8)
   with
     Global => null,
     Pre    => Position <= Natural'Last - 7,
     Post   =>
       Is_Byte_Aligned (Align_To_Byte'Result)
       and then Align_To_Byte'Result >= Position
       and then Align_To_Byte'Result - Position <= 7;

   ---------------------------------------------------------------------------
   --  Bits of an array
   ---------------------------------------------------------------------------

   --  Is the bit at Position set? Everything in this package is specified with
   --  this function, and it is an expression function for the same reason
   --  Bits.Bit is one: a client restating its own bit accessor in terms of it
   --  keeps the definition, not just the name, in front of its provers.
   function Bit
     (A : Byte_Array; Position : Natural; Numbering : Bit_Numbering)
      return Boolean
   is (Bits.Bit (A (Byte_Of (A, Position)), Bit_In_Byte (Position, Numbering)))
   with Global => null, Pre => Fits (A, Position, 1);

   --  The same bit as a number. A model that sums the bits of a code into its
   --  value needs the arithmetic view, and writing the conversion at each of
   --  the sixty places such a model mentions a bit is not a style choice.
   function Bit_Value
     (A : Byte_Array; Position : Natural; Numbering : Bit_Numbering)
      return Natural
   is (if Bit (A, Position, Numbering) then 1 else 0)
   with
     Global => null,
     Pre    => Fits (A, Position, 1),
     Post   => Bit_Value'Result <= 1;

   ---------------------------------------------------------------------------
   --  Proof vocabulary
   ---------------------------------------------------------------------------

   --  After is Before at every bit position outside the Count positions from
   --  First: the frame condition of every operation here that writes. The
   --  window is a count rather than a one-past-the-end position, because the
   --  position past the last bit of a long array need not be a Natural, and
   --  the quantifier runs over the positions the array has rather than over a
   --  product of its length and eight. Both arrays must have the same bounds.
   function Bits_Unchanged_Outside
     (Before, After : Byte_Array;
      First         : Natural;
      Count         : Natural;
      Numbering     : Bit_Numbering) return Boolean
   is (Before'First = After'First
       and then Before'Last = After'Last
       and then
         (for all P in Natural =>
            (if Fits (Before, P, 1)
               and then (P < First or else P - First >= Count)
             then Bit (After, P, Numbering) = Bit (Before, P, Numbering))))
   with Ghost => Static;

   --  One byte of the array changed, and within that byte only the bit the
   --  position names: then only that bit position of the array changed. This
   --  is Bits.Lemma_Insert_Frame lifted from a word to an array, and it is
   --  the reasoning a client writing its own masked byte store cannot avoid.
   --  A client that uses Set_Bit gets the conclusion from its postcondition
   --  and needs nothing from here.
   procedure Lemma_Bit_Frame
     (Before, After : Byte_Array;
      Position      : Natural;
      Numbering     : Bit_Numbering)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Fits (Before, Position, 1)
       and then
         Byte_Buffers.Unchanged_Outside
           (Before,
            After,
            Byte_Of (Before, Position),
            Byte_Of (Before, Position) + 1)
       and then
         (for all I in Bits.Bit_Index_8 =>
            (if I /= Bit_In_Byte (Position, Numbering)
             then
               Bits.Bit (After (Byte_Of (Before, Position)), I)
               = Bits.Bit (Before (Byte_Of (Before, Position)), I))),
     Post   => Bits_Unchanged_Outside (Before, After, Position, 1, Numbering);

   ---------------------------------------------------------------------------
   --  Fields
   ---------------------------------------------------------------------------

   --  The Count bits from Position, assembled into a value. The bits above
   --  the field are clear whichever order assembled it, since both orders use
   --  the same Count bits of the result and differ only in which of them the
   --  first bit taken is. This is the read that moves nothing — Take_Bits is
   --  the same value with the cursor advanced.
   --
   --  Thirty-two bits is the width: it holds every field a bit-packed format
   --  defines, a code no format makes longer, and a client that wants more
   --  takes twice.
   function Bits_At
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order) return Word32
   with
     Global => null,
     Pre    => Fits (A, Position, Count),
     Post   =>
       (Runtime => Bits_At'Result <= Bits.Low_Mask_32 (Count),
        Static  =>
          (for all K in 0 .. Count - 1 =>
             Bits.Bit
               (Bits_At'Result,
                (if Order = Low_Bit_First then K else Count - 1 - K))
             = Bit (A, Position + K, Numbering))
          and then
            (for all I in Count .. 31 => not Bits.Bit (Bits_At'Result, I)));

   --  Bits that did not change give a field that did not change: the frame
   --  lemma of a read, and the step from the bit-wise statement a write makes
   --  to an equality of values. A client proving that one write left another
   --  field alone shows the positions of that field are outside the window it
   --  wrote, which is arithmetic, and then calls this.
   --
   --  The two arrays must have the same bounds, and that is not a strictness
   --  that could be dropped: a field is a function of the array, so its frame
   --  cannot be weaker than its subject. A client whose own frame is stated over
   --  bit positions holds between arrays of equal length whatever their bounds,
   --  because a position is counted from 'First; adopting this one then means
   --  threading equal-bounds hypotheses up through the callers that have no
   --  reason to carry them, and a client for which that costs more than its own
   --  induction is right to keep the induction.
   procedure Lemma_Bits_At_Frame
     (Before, After : Byte_Array;
      Position      : Natural;
      Count         : Bits.Bit_Count_32;
      Numbering     : Bit_Numbering;
      Order         : Field_Order)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Before'First = After'First
       and then Before'Last = After'Last
       and then Fits (Before, Position, Count)
       and then
         (for all K in 0 .. Count - 1 =>
            Bit (After, Position + K, Numbering)
            = Bit (Before, Position + K, Numbering)),
     Post   =>
       Bits_At (After, Position, Count, Numbering, Order)
       = Bits_At (Before, Position, Count, Numbering, Order);

   ---------------------------------------------------------------------------
   --  A field as a number
   ---------------------------------------------------------------------------

   --  A field is read because it is a number: a code indexes a table, a length
   --  becomes a length, a distance becomes an offset. Bits_At states which bit
   --  of the result each position became, which is what a write has to
   --  establish and a frame has to preserve, but a client whose own
   --  specifications are arithmetic cannot get from that statement to a number
   --  without a bridge. These two operations are the bridge, and without them a
   --  client that computes with the fields it reads has to keep its own reader.
   --
   --  ADOPTING THE VALUE VIEW MEANS PROVING YOUR READER EQUAL TO IT, not
   --  replacing it. A client's reader usually cannot be defined as Field_Value:
   --  its postcondition names the recurrence its consumers are proved through,
   --  and inside its own body the shorter field is not available from its own
   --  contract, so the recursive clause stops being provable the moment the body
   --  stops recursing. What the equality buys is everything downstream of it —
   --  in the client this was written for, the whole write side — while the reader
   --  stays. That shape is what tests/proof demonstrates.
   --
   --  What the value view does not give is the direction back: from a field's
   --  value to which bits of the array its digits are. A contract that has to
   --  establish individual bit equations, because the format defines those bits
   --  and its decoder reads them as bits, is Set_Bit's and stays so.
   --
   --  One bit at a time is how a client's model of a field is written, because
   --  that is how a format defines one, so the recurrence is what is stated: a
   --  field is twice the field without its least significant bit, plus that
   --  bit. Which bit that is is the whole content of the two orders — the last
   --  one taken under High_Bit_First, the first one under Low_Bit_First — so
   --  the two cases drop a bit at opposite ends and are otherwise the same
   --  equation.
   procedure Lemma_Bits_At_Recursion
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Count >= 1 and then Fits (A, Position, Count),
     Post   =>
       (case Order is
          when High_Bit_First =>
            Bits_At (A, Position, Count, Numbering, Order)
            = 2
              * Bits_At (A, Position, Count - 1, Numbering, Order)
              + Word32 (Bit_Value (A, Position + Count - 1, Numbering)),
          when Low_Bit_First  =>
            Bits_At (A, Position, Count, Numbering, Order)
            = 2
              * Bits_At (A, Position + 1, Count - 1, Numbering, Order)
              + Word32 (Bit_Value (A, Position, Numbering)));

   --  A field's width stops short of a Word32's where the number is a Natural.
   --  Two bits go: one because a 32-bit field can exceed Natural'Last, and one
   --  because the recurrence doubles a field, and a contract that overflows
   --  where its subject does not is a contract a client cannot use. Every field
   --  a bit-packed format defines is inside this; what is not is a whole word,
   --  which is what Bits_At and the endian loads are for.
   subtype Value_Count is Natural range 0 .. 30;

   --  The field as a number. A client whose codes, lengths and symbols are all
   --  Natural would otherwise write a conversion at every use, and each one
   --  carries a range check that needs the bound of the mask — provable, but it
   --  is noise at the boundary of a package whose job is that boundary.
   --
   --  The bound is stated twice, and the second form is the one a client's own
   --  contracts are written in: a code of Count bits is below 2 ** Count, in
   --  Natural, because that is what a code length means. The mask form is the
   --  same fact in the arithmetic of the word the field came out of, where the
   --  power is a modular one — a client that has the mask form and needs the
   --  other crosses between them with Bits.Lemma_Low_Mask_32_Natural, and a
   --  client that only reads fields needs neither, because the bound it wants is
   --  here.
   --
   --  The last clause is what the recurrence rests on: a field of this width
   --  can be doubled without leaving Natural, so an induction over the width
   --  never has to bound the arithmetic of the step it is proving.
   function Field_Value
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Value_Count;
      Numbering : Bit_Numbering;
      Order     : Field_Order) return Natural
   with
     Global => null,
     Pre    => Fits (A, Position, Count),
     Post   =>
       Field_Value'Result
       = Natural (Bits_At (A, Position, Count, Numbering, Order))
       and then Field_Value'Result <= Natural (Bits.Low_Mask_32 (Count))
       and then Field_Value'Result < 2 ** Count
       and then Field_Value'Result <= Natural'Last / 2;

   --  The same recurrence in the arithmetic a client's model is written in.
   procedure Lemma_Field_Value_Recursion
     (A         : Byte_Array;
      Position  : Natural;
      Count     : Value_Count;
      Numbering : Bit_Numbering;
      Order     : Field_Order)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Count >= 1 and then Fits (A, Position, Count),
     Post   =>
       (case Order is
          when High_Bit_First =>
            Field_Value (A, Position, Count, Numbering, Order)
            = 2
              * Field_Value (A, Position, Count - 1, Numbering, Order)
              + Bit_Value (A, Position + Count - 1, Numbering),
          when Low_Bit_First  =>
            Field_Value (A, Position, Count, Numbering, Order)
            = 2
              * Field_Value (A, Position + 1, Count - 1, Numbering, Order)
              + Bit_Value (A, Position, Numbering));

   ---------------------------------------------------------------------------
   --  Writing
   ---------------------------------------------------------------------------

   --  Set or clear one bit. The postcondition is the bit that changed and the
   --  two frames — no other bit position of the array, and no other byte of
   --  it — because a client reasons about the array in whichever of the two
   --  numberings its own contracts use.
   procedure Set_Bit
     (A         : in out Byte_Array;
      Position  : Natural;
      Value     : Boolean;
      Numbering : Bit_Numbering)
   with
     Global => null,
     Pre    => Fits (A, Position, 1),
     Post   =>
       (Runtime => Bit (A, Position, Numbering) = Value,
        Static  =>
          Bits_Unchanged_Outside (A'Old, A, Position, 1, Numbering)
          and then
            Byte_Buffers.Unchanged_Outside
              (A'Old, A, Byte_Of (A, Position), Byte_Of (A, Position) + 1));

   ---------------------------------------------------------------------------
   --  Cursors
   ---------------------------------------------------------------------------

   --  Take Count bits from Position and advance it, or report that the array
   --  does not hold them and move nothing. Running out of bits is an answer
   --  rather than an error: a decoder asks for the next field of a stream it
   --  does not control the end of, and has to be able to ask.
   --
   --  A take costs a step per bit, as everything here does. Where that is the
   --  wrong trade the reader wanted is the accumulator one, which this package
   --  does not provide; see the head of this spec.
   --
   --  Unchanged on failure is the guarantee that makes a refill loop
   --  writable — the caller retries the same take once more bytes have
   --  arrived, at the position it still holds.
   procedure Take_Bits
     (A         : Byte_Array;
      Position  : in out Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order;
      Value     : out Word32;
      Success   : out Boolean)
   with
     Global => null,
     Post   =>
       (Runtime =>
          Success = Fits (A, Position'Old, Count)
          and then
            (if Success
             then
               Position = Position'Old + Count
               and then
                 Value = Bits_At (A, Position'Old, Count, Numbering, Order)
             else Position = Position'Old and then Value = 0));

   --  Put Count bits of Value at Position and advance it, or report that the
   --  array does not hold them and change neither the array nor the cursor.
   --  Value must already fit in Count bits, as it must for Bits.Insert: a
   --  value that does not is a caller's error rather than something to
   --  truncate silently.
   --
   --  The postcondition is the field read back, the two frames, and — on
   --  failure — the array unchanged as a whole, which is what lets an encoder
   --  that ran out of room report a size rather than a corrupted output.
   procedure Put_Bits
     (A         : in out Byte_Array;
      Position  : in out Natural;
      Count     : Bits.Bit_Count_32;
      Numbering : Bit_Numbering;
      Order     : Field_Order;
      Value     : Word32;
      Success   : out Boolean)
   with
     Global => null,
     Pre    => Value <= Bits.Low_Mask_32 (Count),
     Post   =>
       (Runtime =>
          Success = Fits (A, Position'Old, Count)
          and then
            (if Success
             then
               Position = Position'Old + Count
               and then
                 Bits_At (A, Position'Old, Count, Numbering, Order) = Value
             else Position = Position'Old),
        Static  =>
          (if Success
           then
             Bits_Unchanged_Outside (A'Old, A, Position'Old, Count, Numbering)
             and then
               (if Count > 0
                then
                  Byte_Buffers.Unchanged_Outside
                    (A'Old,
                     A,
                     Byte_Of (A, Position'Old),
                     Byte_Of (A, Position'Old + Count - 1) + 1))
           else A = A'Old));

end Ore.Bit_Cursors;
