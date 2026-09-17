--  Ore.Bits — bit-level operations on the machine words.
--
--  Everything here is word-level and total: no state, no storage, nothing
--  that can be full or empty, and no operation that can fail. These are the
--  primitives a wire format, a checksum or a compressed stream needs before
--  any buffer is involved — shifts and rotates, masks, bit fields, bit
--  counts, byte order within a word, and explicit narrowing and widening.
--
--  POSITIONS. A bit position is 0-based and counts from the least
--  significant bit, which is how a bit-numbering table in a format
--  specification reads. Byte positions in an array stay 1-based, as
--  everywhere else in Ore; the two numberings never meet in one expression.
--
--  VOCABULARY. Bit is to a word what Element is to a buffer. Contracts state
--  which bits a result has rather than an arithmetic formula for its value,
--  so a client asking "is bit 5 set after this insert?" gets an answer
--  without unfolding a sum of powers of two. Bit is an expression function
--  over the machine shift, so its definition stays visible to proof and a
--  client can move between the bit view and the value view. Lemma_Bits_Equal
--  is the step in the other direction, from agreement on every bit back to
--  equality of the values.
--
--  ARRAYS. Loading and storing a 16-, 32- or 64-bit field of a Byte_Array in
--  either byte order is not here: it is defined on plain arrays alongside
--  the buffers, in Ore.Byte_Buffers, and needs no buffer to be used. This
--  package covers the word side of the same subject — which byte of a word
--  sits where, and how to reverse that order.
--
--  RANGES. A bit-level postcondition is written as one quantifier per range
--  of positions rather than as one quantifier with a conditional inside it.
--  Each range then says plainly where its bits come from — these are cleared,
--  those are the bits of the argument moved down — which is both how a
--  specification is read and, because the range bound is the case
--  distinction, the form a prover disposes of without searching for it.
--
--  ASSERTION LEVEL. A postcondition quantified over the bits of a word is
--  constant-cost, unlike one quantified over a buffer, but it is still tens
--  of operations to describe what is usually a single machine instruction.
--  Bit-level postconditions are therefore Static clauses and never execute.
--  Where an operation has a cheap scalar fact to report — a count is at most
--  the width, an extracted field fits under its mask — that fact is a
--  Runtime clause.
--
--  The configuration pragma below is repeated here rather than left to the
--  library's own configuration file, because a client compiling against this
--  spec applies its own configuration, not ours.

--  Static assertions contain proof-only models and are always ignored by the
--  compiler. Executable contracts and assertions remain enabled by -gnata.
pragma Assertion_Policy (Ghost => Ignore);

package Ore.Bits
  with Pure, SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Bit positions
   ---------------------------------------------------------------------------

   --  A position names one bit of a word; a count names how many bits an
   --  operation moves, masks or skips, and so reaches the width itself. A
   --  shift by the width leaves nothing behind, an empty field is a field of
   --  count zero, and a mask of the full width is all ones — none of which
   --  are edge cases a caller should have to avoid.
   subtype Bit_Index_8 is Natural range 0 .. 7;
   subtype Bit_Count_8 is Natural range 0 .. 8;

   subtype Bit_Index_16 is Natural range 0 .. 15;
   subtype Bit_Count_16 is Natural range 0 .. 16;

   subtype Bit_Index_32 is Natural range 0 .. 31;
   subtype Bit_Count_32 is Natural range 0 .. 32;

   subtype Bit_Index_64 is Natural range 0 .. 63;
   subtype Bit_Count_64 is Natural range 0 .. 64;

   ---------------------------------------------------------------------------
   --  The machine instructions
   ---------------------------------------------------------------------------

   --  Shift and rotate as GNAT's intrinsics. They sit in a nested package
   --  because GNAT recognizes an intrinsic only under these exact names and
   --  profiles, and the names are wanted at the outer level for the checked
   --  forms below. The amount here is any Natural: shifting by the width or
   --  more yields zero, and a rotate is taken modulo the width. GNATprove
   --  knows all four operations natively and translates them to bit-vector
   --  operations, so nothing about them is assumed the way the contract of an
   --  imported subprogram would be.
   package Intrinsics is
      function Shift_Left (Value : Byte; Amount : Natural) return Byte
      with Import, Convention => Intrinsic, Global => null;

      function Shift_Right (Value : Byte; Amount : Natural) return Byte
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Left (Value : Byte; Amount : Natural) return Byte
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Right (Value : Byte; Amount : Natural) return Byte
      with Import, Convention => Intrinsic, Global => null;

      function Shift_Left (Value : Word16; Amount : Natural) return Word16
      with Import, Convention => Intrinsic, Global => null;

      function Shift_Right (Value : Word16; Amount : Natural) return Word16
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Left (Value : Word16; Amount : Natural) return Word16
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Right (Value : Word16; Amount : Natural) return Word16
      with Import, Convention => Intrinsic, Global => null;

      function Shift_Left (Value : Word32; Amount : Natural) return Word32
      with Import, Convention => Intrinsic, Global => null;

      function Shift_Right (Value : Word32; Amount : Natural) return Word32
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Left (Value : Word32; Amount : Natural) return Word32
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Right (Value : Word32; Amount : Natural) return Word32
      with Import, Convention => Intrinsic, Global => null;

      function Shift_Left (Value : Word64; Amount : Natural) return Word64
      with Import, Convention => Intrinsic, Global => null;

      function Shift_Right (Value : Word64; Amount : Natural) return Word64
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Left (Value : Word64; Amount : Natural) return Word64
      with Import, Convention => Intrinsic, Global => null;

      function Rotate_Right (Value : Word64; Amount : Natural) return Word64
      with Import, Convention => Intrinsic, Global => null;
   end Intrinsics;

   ---------------------------------------------------------------------------
   --  Bits of a word
   ---------------------------------------------------------------------------

   --  Is the bit at Position set? Every contract in this package is written
   --  with this function, and it is an expression function so that its
   --  definition, not just its name, is what a client's prover sees.
   function Bit (Value : Byte; Position : Bit_Index_8) return Boolean
   is ((Intrinsics.Shift_Right (Value, Position) and 1) = 1)
   with Global => null;

   function Bit (Value : Word16; Position : Bit_Index_16) return Boolean
   is ((Intrinsics.Shift_Right (Value, Position) and 1) = 1)
   with Global => null;

   function Bit (Value : Word32; Position : Bit_Index_32) return Boolean
   is ((Intrinsics.Shift_Right (Value, Position) and 1) = 1)
   with Global => null;

   function Bit (Value : Word64; Position : Bit_Index_64) return Boolean
   is ((Intrinsics.Shift_Right (Value, Position) and 1) = 1)
   with Global => null;

   --  Two words that agree on every bit are the same word. This is the step
   --  from a bit-wise statement back to an equality of values — the analogue
   --  for words of what Lemma_Contents_Equal is for buffers, and what a
   --  client needs to close a proof that constructed a value bit by bit.
   procedure Lemma_Bits_Equal (Left, Right : Byte)
   with
     Ghost  => Static,
     Global => null,
     Pre    => (for all I in Bit_Index_8 => Bit (Left, I) = Bit (Right, I)),
     Post   => Left = Right;

   procedure Lemma_Bits_Equal (Left, Right : Word16)
   with
     Ghost  => Static,
     Global => null,
     Pre    => (for all I in Bit_Index_16 => Bit (Left, I) = Bit (Right, I)),
     Post   => Left = Right;

   procedure Lemma_Bits_Equal (Left, Right : Word32)
   with
     Ghost  => Static,
     Global => null,
     Pre    => (for all I in Bit_Index_32 => Bit (Left, I) = Bit (Right, I)),
     Post   => Left = Right;

   procedure Lemma_Bits_Equal (Left, Right : Word64)
   with
     Ghost  => Static,
     Global => null,
     Pre    => (for all I in Bit_Index_64 => Bit (Left, I) = Bit (Right, I)),
     Post   => Left = Right;

   --  What the bitwise operators do, bit by bit. A prover works these out
   --  unaided for one operator applied to one position, but not for a
   --  composition of three, and a client combining masks needs them at the
   --  same points the bodies here do.
   procedure Lemma_And_Bits (Left, Right : Byte)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_8 =>
          Bit (Left and Right, I) = (Bit (Left, I) and then Bit (Right, I)));

   procedure Lemma_And_Bits (Left, Right : Word16)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_16 =>
          Bit (Left and Right, I) = (Bit (Left, I) and then Bit (Right, I)));

   procedure Lemma_And_Bits (Left, Right : Word32)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_32 =>
          Bit (Left and Right, I) = (Bit (Left, I) and then Bit (Right, I)));

   procedure Lemma_And_Bits (Left, Right : Word64)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_64 =>
          Bit (Left and Right, I) = (Bit (Left, I) and then Bit (Right, I)));

   procedure Lemma_Or_Bits (Left, Right : Byte)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_8 =>
          Bit (Left or Right, I) = (Bit (Left, I) or else Bit (Right, I)));

   procedure Lemma_Or_Bits (Left, Right : Word16)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_16 =>
          Bit (Left or Right, I) = (Bit (Left, I) or else Bit (Right, I)));

   procedure Lemma_Or_Bits (Left, Right : Word32)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_32 =>
          Bit (Left or Right, I) = (Bit (Left, I) or else Bit (Right, I)));

   procedure Lemma_Or_Bits (Left, Right : Word64)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_64 =>
          Bit (Left or Right, I) = (Bit (Left, I) or else Bit (Right, I)));

   procedure Lemma_Xor_Bits (Left, Right : Byte)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_8 =>
          Bit (Left xor Right, I) = (Bit (Left, I) /= Bit (Right, I)));

   procedure Lemma_Xor_Bits (Left, Right : Word16)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_16 =>
          Bit (Left xor Right, I) = (Bit (Left, I) /= Bit (Right, I)));

   procedure Lemma_Xor_Bits (Left, Right : Word32)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_32 =>
          Bit (Left xor Right, I) = (Bit (Left, I) /= Bit (Right, I)));

   procedure Lemma_Xor_Bits (Left, Right : Word64)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_64 =>
          Bit (Left xor Right, I) = (Bit (Left, I) /= Bit (Right, I)));

   procedure Lemma_Not_Bits (Value : Byte)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_8 => Bit (not Value, I) = not Bit (Value, I));

   procedure Lemma_Not_Bits (Value : Word16)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_16 => Bit (not Value, I) = not Bit (Value, I));

   procedure Lemma_Not_Bits (Value : Word32)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_32 => Bit (not Value, I) = not Bit (Value, I));

   procedure Lemma_Not_Bits (Value : Word64)
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       (for all I in Bit_Index_64 => Bit (not Value, I) = not Bit (Value, I));

   ---------------------------------------------------------------------------
   --  Shifts and rotates
   ---------------------------------------------------------------------------

   --  Shift towards the more significant end, filling with zeroes. The amount
   --  is checked against the width by its subtype, which is the difference
   --  from the intrinsic above: a shift by more than the width is a mistake
   --  worth catching rather than a value worth defining.
   function Shift_Left (Value : Byte; Amount : Bit_Count_8) return Byte
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. Amount - 1 => not Bit (Shift_Left'Result, I))
          and then
            (for all I in Amount .. 7 =>
               Bit (Shift_Left'Result, I) = Bit (Value, I - Amount)));

   function Shift_Left (Value : Word16; Amount : Bit_Count_16) return Word16
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. Amount - 1 => not Bit (Shift_Left'Result, I))
          and then
            (for all I in Amount .. 15 =>
               Bit (Shift_Left'Result, I) = Bit (Value, I - Amount)));

   function Shift_Left (Value : Word32; Amount : Bit_Count_32) return Word32
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. Amount - 1 => not Bit (Shift_Left'Result, I))
          and then
            (for all I in Amount .. 31 =>
               Bit (Shift_Left'Result, I) = Bit (Value, I - Amount)));

   function Shift_Left (Value : Word64; Amount : Bit_Count_64) return Word64
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. Amount - 1 => not Bit (Shift_Left'Result, I))
          and then
            (for all I in Amount .. 63 =>
               Bit (Shift_Left'Result, I) = Bit (Value, I - Amount)));

   --  Shift towards the less significant end, filling with zeroes. This is a
   --  logical shift: nothing here treats a word as signed.
   function Shift_Right (Value : Byte; Amount : Bit_Count_8) return Byte
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 7 - Amount =>
             Bit (Shift_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 8 - Amount .. 7 => not Bit (Shift_Right'Result, I)));

   function Shift_Right (Value : Word16; Amount : Bit_Count_16) return Word16
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 15 - Amount =>
             Bit (Shift_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 16 - Amount .. 15 =>
               not Bit (Shift_Right'Result, I)));

   function Shift_Right (Value : Word32; Amount : Bit_Count_32) return Word32
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 31 - Amount =>
             Bit (Shift_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 32 - Amount .. 31 =>
               not Bit (Shift_Right'Result, I)));

   function Shift_Right (Value : Word64; Amount : Bit_Count_64) return Word64
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 63 - Amount =>
             Bit (Shift_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 64 - Amount .. 63 =>
               not Bit (Shift_Right'Result, I)));

   --  Rotate: the bits leaving one end re-enter at the other. The
   --  postcondition takes the source position modulo the width, so a rotation
   --  by the width is the identity rather than an excluded case.
   function Rotate_Left (Value : Byte; Amount : Bit_Count_8) return Byte
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in Amount .. 7 =>
             Bit (Rotate_Left'Result, I) = Bit (Value, I - Amount))
          and then
            (for all I in 0 .. Amount - 1 =>
               Bit (Rotate_Left'Result, I) = Bit (Value, I + 8 - Amount)));

   function Rotate_Left (Value : Word16; Amount : Bit_Count_16) return Word16
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in Amount .. 15 =>
             Bit (Rotate_Left'Result, I) = Bit (Value, I - Amount))
          and then
            (for all I in 0 .. Amount - 1 =>
               Bit (Rotate_Left'Result, I) = Bit (Value, I + 16 - Amount)));

   function Rotate_Left (Value : Word32; Amount : Bit_Count_32) return Word32
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in Amount .. 31 =>
             Bit (Rotate_Left'Result, I) = Bit (Value, I - Amount))
          and then
            (for all I in 0 .. Amount - 1 =>
               Bit (Rotate_Left'Result, I) = Bit (Value, I + 32 - Amount)));

   function Rotate_Left (Value : Word64; Amount : Bit_Count_64) return Word64
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in Amount .. 63 =>
             Bit (Rotate_Left'Result, I) = Bit (Value, I - Amount))
          and then
            (for all I in 0 .. Amount - 1 =>
               Bit (Rotate_Left'Result, I) = Bit (Value, I + 64 - Amount)));

   function Rotate_Right (Value : Byte; Amount : Bit_Count_8) return Byte
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 7 - Amount =>
             Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 8 - Amount .. 7 =>
               Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount - 8)));

   function Rotate_Right (Value : Word16; Amount : Bit_Count_16) return Word16
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 15 - Amount =>
             Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 16 - Amount .. 15 =>
               Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount - 16)));

   function Rotate_Right (Value : Word32; Amount : Bit_Count_32) return Word32
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 31 - Amount =>
             Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 32 - Amount .. 31 =>
               Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount - 32)));

   function Rotate_Right (Value : Word64; Amount : Bit_Count_64) return Word64
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in 0 .. 63 - Amount =>
             Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount))
          and then
            (for all I in 64 - Amount .. 63 =>
               Bit (Rotate_Right'Result, I) = Bit (Value, I + Amount - 64)));

   ---------------------------------------------------------------------------
   --  Masks
   ---------------------------------------------------------------------------

   --  The low Count bits set and nothing else. Named per width rather than
   --  overloaded because only the result type distinguishes them. Building a
   --  mask this way is what makes it safe: the count is checked against the
   --  width by its subtype, and the full-width mask — the one an expression
   --  like 2 ** Count - 1 cannot form without overflowing — is just the
   --  largest legal count.
   --
   --  A mask is used two ways in the same contract: to mask, and as an
   --  arithmetic bound on a value that fits under it. The Static clause serves
   --  the first, and a client that needs the second cannot get there from
   --  "these bits are set". So the value is stated as well, in a Runtime
   --  clause. The case distinction on the full width is the same awkwardness
   --  that makes the operation worth having; it is stated here once so that no
   --  client has to write it, or keep a table of masks to avoid writing it.
   function Low_Mask_8 (Count : Bit_Count_8) return Byte
   with
     Global => null,
     Post   =>
       (Runtime =>
          (if Count < 8
           then Low_Mask_8'Result = 2 ** Count - 1
           else Low_Mask_8'Result = Byte'Last),
        Static  =>
          (for all I in 0 .. Count - 1 => Bit (Low_Mask_8'Result, I))
          and then
            (for all I in Count .. 7 => not Bit (Low_Mask_8'Result, I)));

   function Low_Mask_16 (Count : Bit_Count_16) return Word16
   with
     Global => null,
     Post   =>
       (Runtime =>
          (if Count < 16
           then Low_Mask_16'Result = 2 ** Count - 1
           else Low_Mask_16'Result = Word16'Last),
        Static  =>
          (for all I in 0 .. Count - 1 => Bit (Low_Mask_16'Result, I))
          and then
            (for all I in Count .. 15 => not Bit (Low_Mask_16'Result, I)));

   function Low_Mask_32 (Count : Bit_Count_32) return Word32
   with
     Global => null,
     Post   =>
       (Runtime =>
          (if Count < 32
           then Low_Mask_32'Result = 2 ** Count - 1
           else Low_Mask_32'Result = Word32'Last),
        Static  =>
          (for all I in 0 .. Count - 1 => Bit (Low_Mask_32'Result, I))
          and then
            (for all I in Count .. 31 => not Bit (Low_Mask_32'Result, I)));

   function Low_Mask_64 (Count : Bit_Count_64) return Word64
   with
     Global => null,
     Post   =>
       (Runtime =>
          (if Count < 64
           then Low_Mask_64'Result = 2 ** Count - 1
           else Low_Mask_64'Result = Word64'Last),
        Static  =>
          (for all I in 0 .. Count - 1 => Bit (Low_Mask_64'Result, I))
          and then
            (for all I in Count .. 63 => not Bit (Low_Mask_64'Result, I)));

   --  A value that fits under a low mask has no bits above the mask. This is
   --  the step from the arithmetic bound a client carries — the form a bound
   --  is usually written and checked in — to the bit-wise fact the contracts
   --  here are stated in, and it is the direction Extract does not give: that
   --  one produces the bound from the bits, this one the bits from the bound.
   procedure Lemma_Bound_Bits (Value : Byte; Count : Bit_Count_8)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Value <= Low_Mask_8 (Count),
     Post   => (for all I in Count .. 7 => not Bit (Value, I));

   procedure Lemma_Bound_Bits (Value : Word16; Count : Bit_Count_16)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Value <= Low_Mask_16 (Count),
     Post   => (for all I in Count .. 15 => not Bit (Value, I));

   procedure Lemma_Bound_Bits (Value : Word32; Count : Bit_Count_32)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Value <= Low_Mask_32 (Count),
     Post   => (for all I in Count .. 31 => not Bit (Value, I));

   procedure Lemma_Bound_Bits (Value : Word64; Count : Bit_Count_64)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Value <= Low_Mask_64 (Count),
     Post   => (for all I in Count .. 63 => not Bit (Value, I));

   --  A wider mask is a bigger number. Masks come out of a count a client
   --  computed, and a bound written against one of them has to be usable
   --  against another: this is the step from "the count is no larger" to "the
   --  mask is no larger", which the value clause gives only once the two
   --  powers are compared, and comparing two powers of a variable exponent is
   --  what a prover does not do on its own. The name carries the width, as the
   --  masks themselves do: the parameters are counts, so the four would
   --  otherwise be one profile.
   procedure Lemma_Low_Mask_8_Monotonic (Left, Right : Bit_Count_8)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Left <= Right,
     Post   => Low_Mask_8 (Left) <= Low_Mask_8 (Right);

   procedure Lemma_Low_Mask_16_Monotonic (Left, Right : Bit_Count_16)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Left <= Right,
     Post   => Low_Mask_16 (Left) <= Low_Mask_16 (Right);

   procedure Lemma_Low_Mask_32_Monotonic (Left, Right : Bit_Count_32)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Left <= Right,
     Post   => Low_Mask_32 (Left) <= Low_Mask_32 (Right);

   procedure Lemma_Low_Mask_64_Monotonic (Left, Right : Bit_Count_64)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Left <= Right,
     Post   => Low_Mask_64 (Left) <= Low_Mask_64 (Right);

   --  The mask as a number of the arithmetic a client's own contracts are
   --  written in. The value clause above is an equality in the word type, so the
   --  power in it is a modular one; a client bounds a code by 2 ** N in Natural,
   --  because that is what a code length means, and with the exponent computed
   --  at run time nothing crosses between the two. So the crossing is stated
   --  here, once per width, rather than enumerated per width in a client — which
   --  is what a client does write when it needs it, since a concrete exponent is
   --  the only thing that makes the equality trivial.
   --
   --  The wider two stop at thirty bits: the mask itself is a Natural up to
   --  thirty-one, but the power on the right is not, and a contract that
   --  overflows where its subject does not is a contract that cannot be used.
   --  Above that width the value is a word and stays one.
   procedure Lemma_Low_Mask_8_Natural (Count : Bit_Count_8)
   with
     Ghost  => Static,
     Global => null,
     Post   => Natural (Low_Mask_8 (Count)) = 2 ** Count - 1;

   procedure Lemma_Low_Mask_16_Natural (Count : Bit_Count_16)
   with
     Ghost  => Static,
     Global => null,
     Post   => Natural (Low_Mask_16 (Count)) = 2 ** Count - 1;

   procedure Lemma_Low_Mask_32_Natural (Count : Bit_Count_32)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Count <= 30,
     Post   => Natural (Low_Mask_32 (Count)) = 2 ** Count - 1;

   procedure Lemma_Low_Mask_64_Natural (Count : Bit_Count_64)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Count <= 30,
     Post   => Natural (Low_Mask_64 (Count)) = 2 ** Count - 1;

   --  Count bits set, starting at Offset: the mask of one field. The bound is
   --  in subtraction form, so the sum Offset + Count is never formed where it
   --  could leave the width.
   --
   --  The value clause is the low mask moved up, which is what a client
   --  comparing against a field in place needs. The multiplication is the one
   --  the field itself fits in — Count bits at Offset stay inside the width —
   --  except in the empty case Offset = width, where 2 ** Offset wraps to zero
   --  and multiplies a mask that is zero anyway.
   function Field_Mask_8
     (Offset : Bit_Count_8; Count : Bit_Count_8) return Byte
   with
     Global => null,
     Pre    => Count <= 8 - Offset,
     Post   =>
       (Runtime => Field_Mask_8'Result = Low_Mask_8 (Count) * 2 ** Offset,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Field_Mask_8'Result, I))
          and then
            (for all I in 0 .. Offset - 1 => not Bit (Field_Mask_8'Result, I))
          and then
            (for all I in Offset + Count .. 7 =>
               not Bit (Field_Mask_8'Result, I)));

   function Field_Mask_16
     (Offset : Bit_Count_16; Count : Bit_Count_16) return Word16
   with
     Global => null,
     Pre    => Count <= 16 - Offset,
     Post   =>
       (Runtime => Field_Mask_16'Result = Low_Mask_16 (Count) * 2 ** Offset,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Field_Mask_16'Result, I))
          and then
            (for all I in 0 .. Offset - 1 => not Bit (Field_Mask_16'Result, I))
          and then
            (for all I in Offset + Count .. 15 =>
               not Bit (Field_Mask_16'Result, I)));

   function Field_Mask_32
     (Offset : Bit_Count_32; Count : Bit_Count_32) return Word32
   with
     Global => null,
     Pre    => Count <= 32 - Offset,
     Post   =>
       (Runtime => Field_Mask_32'Result = Low_Mask_32 (Count) * 2 ** Offset,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Field_Mask_32'Result, I))
          and then
            (for all I in 0 .. Offset - 1 => not Bit (Field_Mask_32'Result, I))
          and then
            (for all I in Offset + Count .. 31 =>
               not Bit (Field_Mask_32'Result, I)));

   function Field_Mask_64
     (Offset : Bit_Count_64; Count : Bit_Count_64) return Word64
   with
     Global => null,
     Pre    => Count <= 64 - Offset,
     Post   =>
       (Runtime => Field_Mask_64'Result = Low_Mask_64 (Count) * 2 ** Offset,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Field_Mask_64'Result, I))
          and then
            (for all I in 0 .. Offset - 1 => not Bit (Field_Mask_64'Result, I))
          and then
            (for all I in Offset + Count .. 63 =>
               not Bit (Field_Mask_64'Result, I)));

   ---------------------------------------------------------------------------
   --  Powers of two
   ---------------------------------------------------------------------------

   --  One bit set, at Exponent: the weight of that bit position. A mask plus
   --  one is the same number, but a client that needs the weight is not
   --  masking anything — it is weighing a code length, summing a series, or
   --  sizing a table — and writing it as a mask says the wrong thing about
   --  what the value is for. The exponent stops one short of the width, which
   --  is where the value stops being representable rather than a restriction
   --  of its own.
   --
   --  Naming the operation is what keeps a client from tabulating it. A
   --  concrete array of powers is what a client writes when a symbolic
   --  exponent is proof risk; here the exponent is symbolic, the value is a
   --  postcondition, and the bit is one too, so neither view has to be
   --  recovered from the other.
   function Power_Of_Two_8 (Exponent : Bit_Index_8) return Byte
   with
     Global => null,
     Post   =>
       (Runtime => Power_Of_Two_8'Result = 2 ** Exponent,
        Static  =>
          (for all I in Bit_Index_8 =>
             Bit (Power_Of_Two_8'Result, I) = (I = Exponent)));

   function Power_Of_Two_16 (Exponent : Bit_Index_16) return Word16
   with
     Global => null,
     Post   =>
       (Runtime => Power_Of_Two_16'Result = 2 ** Exponent,
        Static  =>
          (for all I in Bit_Index_16 =>
             Bit (Power_Of_Two_16'Result, I) = (I = Exponent)));

   function Power_Of_Two_32 (Exponent : Bit_Index_32) return Word32
   with
     Global => null,
     Post   =>
       (Runtime => Power_Of_Two_32'Result = 2 ** Exponent,
        Static  =>
          (for all I in Bit_Index_32 =>
             Bit (Power_Of_Two_32'Result, I) = (I = Exponent)));

   function Power_Of_Two_64 (Exponent : Bit_Index_64) return Word64
   with
     Global => null,
     Post   =>
       (Runtime => Power_Of_Two_64'Result = 2 ** Exponent,
        Static  =>
          (for all I in Bit_Index_64 =>
             Bit (Power_Of_Two_64'Result, I) = (I = Exponent)));

   --  The weight as a number of the arithmetic that weighs with it, for the
   --  reason the masks have the same lemma: a Kraft sum over code lengths, or a
   --  table size, is a Natural, and the value clause above is an equality in the
   --  word type. A client whose powers are Naturals throughout needs no
   --  operation from here — 2 ** N is that value — but one that has a word from
   --  a shift or a mask and a bound to meet in Natural needs the step between,
   --  and it is the step a symbolic exponent denies it.
   procedure Lemma_Power_Of_Two_8_Natural (Exponent : Bit_Index_8)
   with
     Ghost  => Static,
     Global => null,
     Post   => Natural (Power_Of_Two_8 (Exponent)) = 2 ** Exponent;

   procedure Lemma_Power_Of_Two_16_Natural (Exponent : Bit_Index_16)
   with
     Ghost  => Static,
     Global => null,
     Post   => Natural (Power_Of_Two_16 (Exponent)) = 2 ** Exponent;

   procedure Lemma_Power_Of_Two_32_Natural (Exponent : Bit_Index_32)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Exponent <= 30,
     Post   => Natural (Power_Of_Two_32 (Exponent)) = 2 ** Exponent;

   procedure Lemma_Power_Of_Two_64_Natural (Exponent : Bit_Index_64)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Exponent <= 30,
     Post   => Natural (Power_Of_Two_64 (Exponent)) = 2 ** Exponent;

   ---------------------------------------------------------------------------
   --  Bit fields
   ---------------------------------------------------------------------------

   --  The Count bits at Offset, moved down to bit zero. The Runtime clause is
   --  the fact the next operation usually needs — the result fits in Count
   --  bits — and it is exactly the precondition of Insert. Its right-hand side
   --  is a mask, whose own contract gives the number that mask is, so the
   --  bound is available as an arithmetic bound and not only as a mask.
   function Extract
     (Value : Byte; Offset : Bit_Count_8; Count : Bit_Count_8) return Byte
   with
     Global => null,
     Pre    => Count <= 8 - Offset,
     Post   =>
       (Runtime => Extract'Result <= Low_Mask_8 (Count),
        Static  =>
          (for all I in 0 .. Count - 1 =>
             Bit (Extract'Result, I) = Bit (Value, Offset + I))
          and then (for all I in Count .. 7 => not Bit (Extract'Result, I)));

   function Extract
     (Value : Word16; Offset : Bit_Count_16; Count : Bit_Count_16)
      return Word16
   with
     Global => null,
     Pre    => Count <= 16 - Offset,
     Post   =>
       (Runtime => Extract'Result <= Low_Mask_16 (Count),
        Static  =>
          (for all I in 0 .. Count - 1 =>
             Bit (Extract'Result, I) = Bit (Value, Offset + I))
          and then (for all I in Count .. 15 => not Bit (Extract'Result, I)));

   function Extract
     (Value : Word32; Offset : Bit_Count_32; Count : Bit_Count_32)
      return Word32
   with
     Global => null,
     Pre    => Count <= 32 - Offset,
     Post   =>
       (Runtime => Extract'Result <= Low_Mask_32 (Count),
        Static  =>
          (for all I in 0 .. Count - 1 =>
             Bit (Extract'Result, I) = Bit (Value, Offset + I))
          and then (for all I in Count .. 31 => not Bit (Extract'Result, I)));

   function Extract
     (Value : Word64; Offset : Bit_Count_64; Count : Bit_Count_64)
      return Word64
   with
     Global => null,
     Pre    => Count <= 64 - Offset,
     Post   =>
       (Runtime => Extract'Result <= Low_Mask_64 (Count),
        Static  =>
          (for all I in 0 .. Count - 1 =>
             Bit (Extract'Result, I) = Bit (Value, Offset + I))
          and then (for all I in Count .. 63 => not Bit (Extract'Result, I)));

   --  Value with its Count bits at Offset replaced by Field. Field must
   --  already fit in Count bits; a value that does not is a caller's error
   --  rather than something to truncate silently. The second half of the
   --  postcondition is the frame condition: no bit outside the field moved.
   function Insert
     (Value : Byte; Field : Byte; Offset : Bit_Count_8; Count : Bit_Count_8)
      return Byte
   with
     Global => null,
     Pre    => Count <= 8 - Offset and then Field <= Low_Mask_8 (Count),
     Post   =>
       (Runtime => Extract (Insert'Result, Offset, Count) = Field,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Insert'Result, I) = Bit (Field, I - Offset))
          and then
            (for all I in 0 .. Offset - 1 =>
               Bit (Insert'Result, I) = Bit (Value, I))
          and then
            (for all I in Offset + Count .. 7 =>
               Bit (Insert'Result, I) = Bit (Value, I)));

   function Insert
     (Value  : Word16;
      Field  : Word16;
      Offset : Bit_Count_16;
      Count  : Bit_Count_16) return Word16
   with
     Global => null,
     Pre    => Count <= 16 - Offset and then Field <= Low_Mask_16 (Count),
     Post   =>
       (Runtime => Extract (Insert'Result, Offset, Count) = Field,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Insert'Result, I) = Bit (Field, I - Offset))
          and then
            (for all I in 0 .. Offset - 1 =>
               Bit (Insert'Result, I) = Bit (Value, I))
          and then
            (for all I in Offset + Count .. 15 =>
               Bit (Insert'Result, I) = Bit (Value, I)));

   function Insert
     (Value  : Word32;
      Field  : Word32;
      Offset : Bit_Count_32;
      Count  : Bit_Count_32) return Word32
   with
     Global => null,
     Pre    => Count <= 32 - Offset and then Field <= Low_Mask_32 (Count),
     Post   =>
       (Runtime => Extract (Insert'Result, Offset, Count) = Field,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Insert'Result, I) = Bit (Field, I - Offset))
          and then
            (for all I in 0 .. Offset - 1 =>
               Bit (Insert'Result, I) = Bit (Value, I))
          and then
            (for all I in Offset + Count .. 31 =>
               Bit (Insert'Result, I) = Bit (Value, I)));

   function Insert
     (Value  : Word64;
      Field  : Word64;
      Offset : Bit_Count_64;
      Count  : Bit_Count_64) return Word64
   with
     Global => null,
     Pre    => Count <= 64 - Offset and then Field <= Low_Mask_64 (Count),
     Post   =>
       (Runtime => Extract (Insert'Result, Offset, Count) = Field,
        Static  =>
          (for all I in Offset .. Offset + Count - 1 =>
             Bit (Insert'Result, I) = Bit (Field, I - Offset))
          and then
            (for all I in 0 .. Offset - 1 =>
               Bit (Insert'Result, I) = Bit (Value, I))
          and then
            (for all I in Offset + Count .. 63 =>
               Bit (Insert'Result, I) = Bit (Value, I)));

   --  Inserting one field leaves another one alone, provided the two do not
   --  overlap. With the round trip in Insert's own postcondition, this is what
   --  packing several fields into one word needs: each field reads back as it
   --  went in, whatever was written after it.
   procedure Lemma_Insert_Frame
     (Value        : Byte;
      Field        : Byte;
      Offset       : Bit_Count_8;
      Count        : Bit_Count_8;
      Other_Offset : Bit_Count_8;
      Other_Count  : Bit_Count_8)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Count <= 8 - Offset
       and then Field <= Low_Mask_8 (Count)
       and then Other_Count <= 8 - Other_Offset
       and then
         (Other_Offset + Other_Count <= Offset
          or else Offset + Count <= Other_Offset),
     Post   =>
       Extract
         (Insert (Value, Field, Offset, Count), Other_Offset, Other_Count)
       = Extract (Value, Other_Offset, Other_Count);

   procedure Lemma_Insert_Frame
     (Value        : Word16;
      Field        : Word16;
      Offset       : Bit_Count_16;
      Count        : Bit_Count_16;
      Other_Offset : Bit_Count_16;
      Other_Count  : Bit_Count_16)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Count <= 16 - Offset
       and then Field <= Low_Mask_16 (Count)
       and then Other_Count <= 16 - Other_Offset
       and then
         (Other_Offset + Other_Count <= Offset
          or else Offset + Count <= Other_Offset),
     Post   =>
       Extract
         (Insert (Value, Field, Offset, Count), Other_Offset, Other_Count)
       = Extract (Value, Other_Offset, Other_Count);

   procedure Lemma_Insert_Frame
     (Value        : Word32;
      Field        : Word32;
      Offset       : Bit_Count_32;
      Count        : Bit_Count_32;
      Other_Offset : Bit_Count_32;
      Other_Count  : Bit_Count_32)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Count <= 32 - Offset
       and then Field <= Low_Mask_32 (Count)
       and then Other_Count <= 32 - Other_Offset
       and then
         (Other_Offset + Other_Count <= Offset
          or else Offset + Count <= Other_Offset),
     Post   =>
       Extract
         (Insert (Value, Field, Offset, Count), Other_Offset, Other_Count)
       = Extract (Value, Other_Offset, Other_Count);

   procedure Lemma_Insert_Frame
     (Value        : Word64;
      Field        : Word64;
      Offset       : Bit_Count_64;
      Count        : Bit_Count_64;
      Other_Offset : Bit_Count_64;
      Other_Count  : Bit_Count_64)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Count <= 64 - Offset
       and then Field <= Low_Mask_64 (Count)
       and then Other_Count <= 64 - Other_Offset
       and then
         (Other_Offset + Other_Count <= Offset
          or else Offset + Count <= Other_Offset),
     Post   =>
       Extract
         (Insert (Value, Field, Offset, Count), Other_Offset, Other_Count)
       = Extract (Value, Other_Offset, Other_Count);

   ---------------------------------------------------------------------------
   --  Bits and values
   ---------------------------------------------------------------------------

   --  Everything above states which bits a result has. A client reads a
   --  bit-packed field because the field is a number — a code indexes a table,
   --  a length becomes a length — so its own specifications are arithmetic,
   --  and it needs the step between the two views. Lemma_Bound_Bits goes from a
   --  bound to bits; these go the other way, and they are the direction the
   --  contracts here cannot supply as postconditions, because an arithmetic
   --  postcondition on a shift would be the thing this layer exists not to
   --  make a client write.
   --
   --  A shift is a multiplication or a division by a power of two, and a field
   --  at the bottom of a word is a remainder. Those three are the whole bridge:
   --  every arithmetic fact about a bit operation of this package follows from
   --  them and ordinary integer reasoning, which is what a prover is good at.
   --  A shift left needs no restriction, because a shift that leaves the word
   --  and a multiplication that wraps agree; a shift right and a field do,
   --  because the divisor or the modulus has to be a number the type holds.
   procedure Lemma_Shift_Left_Value (Value : Byte; Amount : Bit_Count_8)
   with
     Ghost  => Static,
     Global => null,
     Post   => Shift_Left (Value, Amount) = Value * 2 ** Amount;

   procedure Lemma_Shift_Left_Value (Value : Word16; Amount : Bit_Count_16)
   with
     Ghost  => Static,
     Global => null,
     Post   => Shift_Left (Value, Amount) = Value * 2 ** Amount;

   procedure Lemma_Shift_Left_Value (Value : Word32; Amount : Bit_Count_32)
   with
     Ghost  => Static,
     Global => null,
     Post   => Shift_Left (Value, Amount) = Value * 2 ** Amount;

   procedure Lemma_Shift_Left_Value (Value : Word64; Amount : Bit_Count_64)
   with
     Ghost  => Static,
     Global => null,
     Post   => Shift_Left (Value, Amount) = Value * 2 ** Amount;

   procedure Lemma_Shift_Right_Value (Value : Byte; Amount : Bit_Count_8)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Amount < 8,
     Post   => Shift_Right (Value, Amount) = Value / 2 ** Amount;

   procedure Lemma_Shift_Right_Value (Value : Word16; Amount : Bit_Count_16)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Amount < 16,
     Post   => Shift_Right (Value, Amount) = Value / 2 ** Amount;

   procedure Lemma_Shift_Right_Value (Value : Word32; Amount : Bit_Count_32)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Amount < 32,
     Post   => Shift_Right (Value, Amount) = Value / 2 ** Amount;

   procedure Lemma_Shift_Right_Value (Value : Word64; Amount : Bit_Count_64)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Amount < 64,
     Post   => Shift_Right (Value, Amount) = Value / 2 ** Amount;

   procedure Lemma_Extract_Value
     (Value : Byte; Offset : Bit_Count_8; Count : Bit_Count_8)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Offset < 8 and then Count < 8 and then Count <= 8 - Offset,
     Post   =>
       Extract (Value, Offset, Count) = (Value / 2 ** Offset) mod 2 ** Count;

   procedure Lemma_Extract_Value
     (Value : Word16; Offset : Bit_Count_16; Count : Bit_Count_16)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Offset < 16 and then Count < 16 and then Count <= 16 - Offset,
     Post   =>
       Extract (Value, Offset, Count) = (Value / 2 ** Offset) mod 2 ** Count;

   procedure Lemma_Extract_Value
     (Value : Word32; Offset : Bit_Count_32; Count : Bit_Count_32)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Offset < 32 and then Count < 32 and then Count <= 32 - Offset,
     Post   =>
       Extract (Value, Offset, Count) = (Value / 2 ** Offset) mod 2 ** Count;

   procedure Lemma_Extract_Value
     (Value : Word64; Offset : Bit_Count_64; Count : Bit_Count_64)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Offset < 64 and then Count < 64 and then Count <= 64 - Offset,
     Post   =>
       Extract (Value, Offset, Count) = (Value / 2 ** Offset) mod 2 ** Count;

   --  What the low Upto bits are worth, as a recurrence: each bit adds its own
   --  weight. This is to a value what Count_Bits is to a count — the form a
   --  client's own induction is written against, and the shape a model of a
   --  code arrives at when it reads a field one bit at a time.
   function Bits_Value (Value : Byte; Upto : Bit_Count_8) return Byte
   is (if Upto = 0
       then 0
       else
         Bits_Value (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 2 ** (Upto - 1) else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Bits_Value'Result <= Low_Mask_8 (Upto),
     Subprogram_Variant => (Decreases => Upto);

   function Bits_Value (Value : Word16; Upto : Bit_Count_16) return Word16
   is (if Upto = 0
       then 0
       else
         Bits_Value (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 2 ** (Upto - 1) else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Bits_Value'Result <= Low_Mask_16 (Upto),
     Subprogram_Variant => (Decreases => Upto);

   function Bits_Value (Value : Word32; Upto : Bit_Count_32) return Word32
   is (if Upto = 0
       then 0
       else
         Bits_Value (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 2 ** (Upto - 1) else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Bits_Value'Result <= Low_Mask_32 (Upto),
     Subprogram_Variant => (Decreases => Upto);

   function Bits_Value (Value : Word64; Upto : Bit_Count_64) return Word64
   is (if Upto = 0
       then 0
       else
         Bits_Value (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 2 ** (Upto - 1) else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Bits_Value'Result <= Low_Mask_64 (Upto),
     Subprogram_Variant => (Decreases => Upto);

   --  The bits of a field are worth the field: the recurrence and the operation
   --  agree, so a client that specified its reader as a recurrence can use
   --  either and needs no induction of its own.
   procedure Lemma_Bits_Value (Value : Byte; Count : Bit_Count_8)
   with
     Ghost              => Static,
     Global             => null,
     Post               =>
       Bits_Value (Value, Count) = Extract (Value, 0, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Bits_Value (Value : Word16; Count : Bit_Count_16)
   with
     Ghost              => Static,
     Global             => null,
     Post               =>
       Bits_Value (Value, Count) = Extract (Value, 0, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Bits_Value (Value : Word32; Count : Bit_Count_32)
   with
     Ghost              => Static,
     Global             => null,
     Post               =>
       Bits_Value (Value, Count) = Extract (Value, 0, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Bits_Value (Value : Word64; Count : Bit_Count_64)
   with
     Ghost              => Static,
     Global             => null,
     Post               =>
       Bits_Value (Value, Count) = Extract (Value, 0, Count),
     Subprogram_Variant => (Decreases => Count);

   ---------------------------------------------------------------------------
   --  Counting bits
   ---------------------------------------------------------------------------

   --  How many of the low Upto bits are set. This is the specification of
   --  Population_Count, stated as the recurrence rather than as a loop,
   --  because a recurrence is what a client's own induction can be written
   --  against; the counting loop is an implementation of it.
   function Count_Bits (Value : Byte; Upto : Bit_Count_8) return Natural
   is (if Upto = 0
       then 0
       else
         Count_Bits (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 1 else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Count_Bits'Result <= Upto,
     Subprogram_Variant => (Decreases => Upto);

   function Count_Bits (Value : Word16; Upto : Bit_Count_16) return Natural
   is (if Upto = 0
       then 0
       else
         Count_Bits (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 1 else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Count_Bits'Result <= Upto,
     Subprogram_Variant => (Decreases => Upto);

   function Count_Bits (Value : Word32; Upto : Bit_Count_32) return Natural
   is (if Upto = 0
       then 0
       else
         Count_Bits (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 1 else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Count_Bits'Result <= Upto,
     Subprogram_Variant => (Decreases => Upto);

   function Count_Bits (Value : Word64; Upto : Bit_Count_64) return Natural
   is (if Upto = 0
       then 0
       else
         Count_Bits (Value, Upto - 1)
         + (if Bit (Value, Upto - 1) then 1 else 0))
   with
     Ghost              => Static,
     Global             => null,
     Post               => Count_Bits'Result <= Upto,
     Subprogram_Variant => (Decreases => Upto);

   --  How many bits are set.
   function Population_Count (Value : Byte) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Population_Count'Result <= 8
          and then (Population_Count'Result = 0) = (Value = 0),
        Static  => Population_Count'Result = Count_Bits (Value, 8));

   function Population_Count (Value : Word16) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Population_Count'Result <= 16
          and then (Population_Count'Result = 0) = (Value = 0),
        Static  => Population_Count'Result = Count_Bits (Value, 16));

   function Population_Count (Value : Word32) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Population_Count'Result <= 32
          and then (Population_Count'Result = 0) = (Value = 0),
        Static  => Population_Count'Result = Count_Bits (Value, 32));

   function Population_Count (Value : Word64) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Population_Count'Result <= 64
          and then (Population_Count'Result = 0) = (Value = 0),
        Static  => Population_Count'Result = Count_Bits (Value, 64));

   --  How many zero bits sit above the most significant bit that is set —
   --  the width for a zero word. Together with the position of that bit,
   --  which the postcondition also gives, this is how a client sizes a value:
   --  the number of bits needed to hold it is the width less the count.
   function Leading_Zeroes (Value : Byte) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Leading_Zeroes'Result <= 8
          and then (Leading_Zeroes'Result = 8) = (Value = 0),
        Static  =>
          (for all I in 8 - Leading_Zeroes'Result .. 7 => not Bit (Value, I))
          and then
            (if Leading_Zeroes'Result < 8
             then Bit (Value, 7 - Leading_Zeroes'Result)));

   function Leading_Zeroes (Value : Word16) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Leading_Zeroes'Result <= 16
          and then (Leading_Zeroes'Result = 16) = (Value = 0),
        Static  =>
          (for all I in 16 - Leading_Zeroes'Result .. 15 => not Bit (Value, I))
          and then
            (if Leading_Zeroes'Result < 16
             then Bit (Value, 15 - Leading_Zeroes'Result)));

   function Leading_Zeroes (Value : Word32) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Leading_Zeroes'Result <= 32
          and then (Leading_Zeroes'Result = 32) = (Value = 0),
        Static  =>
          (for all I in 32 - Leading_Zeroes'Result .. 31 => not Bit (Value, I))
          and then
            (if Leading_Zeroes'Result < 32
             then Bit (Value, 31 - Leading_Zeroes'Result)));

   function Leading_Zeroes (Value : Word64) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Leading_Zeroes'Result <= 64
          and then (Leading_Zeroes'Result = 64) = (Value = 0),
        Static  =>
          (for all I in 64 - Leading_Zeroes'Result .. 63 => not Bit (Value, I))
          and then
            (if Leading_Zeroes'Result < 64
             then Bit (Value, 63 - Leading_Zeroes'Result)));

   --  How many zero bits sit below the least significant bit that is set —
   --  the width for a zero word. This is the alignment of a value: the
   --  largest power of two that divides it.
   function Trailing_Zeroes (Value : Byte) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Trailing_Zeroes'Result <= 8
          and then (Trailing_Zeroes'Result = 8) = (Value = 0),
        Static  =>
          (for all I in 0 .. Trailing_Zeroes'Result - 1 => not Bit (Value, I))
          and then
            (if Trailing_Zeroes'Result < 8
             then Bit (Value, Trailing_Zeroes'Result)));

   function Trailing_Zeroes (Value : Word16) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Trailing_Zeroes'Result <= 16
          and then (Trailing_Zeroes'Result = 16) = (Value = 0),
        Static  =>
          (for all I in 0 .. Trailing_Zeroes'Result - 1 => not Bit (Value, I))
          and then
            (if Trailing_Zeroes'Result < 16
             then Bit (Value, Trailing_Zeroes'Result)));

   function Trailing_Zeroes (Value : Word32) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Trailing_Zeroes'Result <= 32
          and then (Trailing_Zeroes'Result = 32) = (Value = 0),
        Static  =>
          (for all I in 0 .. Trailing_Zeroes'Result - 1 => not Bit (Value, I))
          and then
            (if Trailing_Zeroes'Result < 32
             then Bit (Value, Trailing_Zeroes'Result)));

   function Trailing_Zeroes (Value : Word64) return Natural
   with
     Global => null,
     Post   =>
       (Runtime =>
          Trailing_Zeroes'Result <= 64
          and then (Trailing_Zeroes'Result = 64) = (Value = 0),
        Static  =>
          (for all I in 0 .. Trailing_Zeroes'Result - 1 => not Bit (Value, I))
          and then
            (if Trailing_Zeroes'Result < 64
             then Bit (Value, Trailing_Zeroes'Result)));

   ---------------------------------------------------------------------------
   --  Truncation and extension
   ---------------------------------------------------------------------------

   --  Narrowing keeps the low bits of the value and drops the rest. It is a
   --  separate operation rather than a type conversion because a conversion
   --  that cannot represent its argument raises, and a protocol field that is
   --  meant to be truncated should not have to pass a range check first.
   --  These are expression functions: the arithmetic is the specification.
   function Truncate_To_Byte (Value : Word16) return Byte
   is (Byte (Value mod 2 ** 8))
   with Global => null;

   function Truncate_To_Byte (Value : Word32) return Byte
   is (Byte (Value mod 2 ** 8))
   with Global => null;

   function Truncate_To_Byte (Value : Word64) return Byte
   is (Byte (Value mod 2 ** 8))
   with Global => null;

   function Truncate_To_Word16 (Value : Word32) return Word16
   is (Word16 (Value mod 2 ** 16))
   with Global => null;

   function Truncate_To_Word16 (Value : Word64) return Word16
   is (Word16 (Value mod 2 ** 16))
   with Global => null;

   function Truncate_To_Word32 (Value : Word64) return Word32
   is (Word32 (Value mod 2 ** 32))
   with Global => null;

   --  Widening keeps the value and clears the bits above it. A plain type
   --  conversion would do the same; naming the operation says that the width
   --  change is deliberate, and keeps a widening and a narrowing from looking
   --  alike at the point of use.
   function Extend_To_Word16 (Value : Byte) return Word16
   is (Word16 (Value))
   with Global => null;

   function Extend_To_Word32 (Value : Byte) return Word32
   is (Word32 (Value))
   with Global => null;

   function Extend_To_Word32 (Value : Word16) return Word32
   is (Word32 (Value))
   with Global => null;

   function Extend_To_Word64 (Value : Byte) return Word64
   is (Word64 (Value))
   with Global => null;

   function Extend_To_Word64 (Value : Word16) return Word64
   is (Word64 (Value))
   with Global => null;

   function Extend_To_Word64 (Value : Word32) return Word64
   is (Word64 (Value))
   with Global => null;

   ---------------------------------------------------------------------------
   --  Bytes within a word
   ---------------------------------------------------------------------------

   --  Which byte of a word an index names depends on the byte order, exactly
   --  as it does in an array: in Little_Endian order byte zero is the least
   --  significant one, in Big_Endian order it is the most significant. The
   --  index is 0-based like a bit position, because it counts bytes from one
   --  end of a word rather than positions in an array.
   subtype Byte_Offset_16 is Natural range 0 .. 1;
   subtype Byte_Offset_32 is Natural range 0 .. 3;
   subtype Byte_Offset_64 is Natural range 0 .. 7;

   function Byte_At
     (Value : Word16; Index : Byte_Offset_16; Order : Byte_Order) return Byte
   is (Truncate_To_Byte
         (Intrinsics.Shift_Right
            (Value, 8 * (if Order = Little_Endian then Index else 1 - Index))))
   with Global => null;

   function Byte_At
     (Value : Word32; Index : Byte_Offset_32; Order : Byte_Order) return Byte
   is (Truncate_To_Byte
         (Intrinsics.Shift_Right
            (Value, 8 * (if Order = Little_Endian then Index else 3 - Index))))
   with Global => null;

   function Byte_At
     (Value : Word64; Index : Byte_Offset_64; Order : Byte_Order) return Byte
   is (Truncate_To_Byte
         (Intrinsics.Shift_Right
            (Value, 8 * (if Order = Little_Endian then Index else 7 - Index))))
   with Global => null;

   --  Reverse the byte order of a word: the value read back in one order is
   --  the value that went in read in the other. This is the conversion
   --  between a value in memory order and a value in register order, for a
   --  client that has the whole word already rather than the array it came
   --  from.
   function Byte_Swap (Value : Word16) return Word16
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in Byte_Offset_16 =>
             Byte_At (Byte_Swap'Result, I, Little_Endian)
             = Byte_At (Value, I, Big_Endian)));

   function Byte_Swap (Value : Word32) return Word32
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in Byte_Offset_32 =>
             Byte_At (Byte_Swap'Result, I, Little_Endian)
             = Byte_At (Value, I, Big_Endian)));

   function Byte_Swap (Value : Word64) return Word64
   with
     Global => null,
     Post   =>
       (Static =>
          (for all I in Byte_Offset_64 =>
             Byte_At (Byte_Swap'Result, I, Little_Endian)
             = Byte_At (Value, I, Big_Endian)));

   --  Reversing the byte order twice returns the word: a client that swaps on
   --  the way in and on the way out needs no further reasoning to get its
   --  value back.
   procedure Lemma_Byte_Swap_Involutive (Value : Word16)
   with
     Ghost  => Static,
     Global => null,
     Post   => Byte_Swap (Byte_Swap (Value)) = Value;

   procedure Lemma_Byte_Swap_Involutive (Value : Word32)
   with
     Ghost  => Static,
     Global => null,
     Post   => Byte_Swap (Byte_Swap (Value)) = Value;

   procedure Lemma_Byte_Swap_Involutive (Value : Word64)
   with
     Ghost  => Static,
     Global => null,
     Post   => Byte_Swap (Byte_Swap (Value)) = Value;

   --  Two words that agree byte by byte are the same word: the step from the
   --  byte-level statement Byte_Swap makes back to an equality of values.
   procedure Lemma_Bytes_Equal (Left, Right : Word16)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       (for all I in Byte_Offset_16 =>
          Byte_At (Left, I, Little_Endian)
          = Byte_At (Right, I, Little_Endian)),
     Post   => Left = Right;

   procedure Lemma_Bytes_Equal (Left, Right : Word32)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       (for all I in Byte_Offset_32 =>
          Byte_At (Left, I, Little_Endian)
          = Byte_At (Right, I, Little_Endian)),
     Post   => Left = Right;

   procedure Lemma_Bytes_Equal (Left, Right : Word64)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       (for all I in Byte_Offset_64 =>
          Byte_At (Left, I, Little_Endian)
          = Byte_At (Right, I, Little_Endian)),
     Post   => Left = Right;

end Ore.Bits;
