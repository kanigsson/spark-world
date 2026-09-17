--  M2 pressure test: prove, in isolation, the whole-table properties of the
--  canonical Huffman construction that the shipping AoRTE proof handles
--  with defensive runtime checks.
--
--  The algorithm below is a faithful copy of the library's table
--  construction (histogram of code lengths, the Kraft "Left" loop, the
--  per-length symbol offsets, the sorted symbol fill) with the defensive
--  early returns REMOVED: every array index and range check must instead
--  be discharged from ghost summation facts. The decoder's slot-bound
--  check is exercised by a decode simulation over a bit array.
--
--  Proved facts (see the postconditions):
--    * the histogram is exact per length: Counts (L) is the number of
--      entries of Lengths equal to L, and their sum is at most
--      Lengths'Length (so at most 288);
--    * the offsets Offs (L) are the prefix sums of the histogram, hence
--      never exceed the symbol-map size — the defensive checks are dead;
--    * the "Left" loop decides exactly the scaled Kraft inequality:
--      Valid = (Kraft_Sum <= 2**15), Complete = (Kraft_Sum = 2**15);
--    * the decoder's slot index Index + (Code - First) stays within the
--      symbol map for any table whose counts sum to at most 288.

package Kraft with SPARK_Mode => On is

   Max_Symbols : constant := 288;

   subtype Code_Length     is Natural range 0 .. 15;
   subtype Code_Length_Pos is Code_Length range 1 .. 15;
   subtype Symbol_Count    is Natural range 0 .. Max_Symbols;
   subtype Symbol_Value    is Natural range 0 .. Max_Symbols - 1;

   type Length_Count_Array is array (Code_Length_Pos) of Symbol_Count;
   type Symbol_Map         is array (Symbol_Value) of Symbol_Value;

   subtype Length_Index is Natural range 0 .. 319;
   type Code_Length_Array is array (Length_Index range <>) of Code_Length;

   --  Concrete powers of two: the provers enumerate the aggregate's cases
   --  where a symbolic 2**N would need power lemmas they do not find.
   Pow2 : constant array (Natural range 0 .. 16) of Natural :=
     (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192,
      16384, 32768, 65536);

   ---------------------------------------------------------------------
   --  Ghost summation machinery
   ---------------------------------------------------------------------

   --  Sum of Counts (1 .. L)
   function Sum_Counts
     (C : Length_Count_Array;
      L : Code_Length) return Natural
   is
     (if L = 0 then 0 else Sum_Counts (C, L - 1) + C (L))
   with
     Ghost,
     Subprogram_Variant => (Decreases => L),
     Post => Sum_Counts'Result <= L * Max_Symbols;

   --  Number of J in Lengths'First .. Hi - 1 with Lengths (J) = L
   function Count_Len
     (Lengths : Code_Length_Array;
      L       : Code_Length_Pos;
      Hi      : Natural) return Natural
   is
     (if Hi <= Lengths'First then 0
      else Count_Len (Lengths, L, Hi - 1)
           + (if Lengths (Hi - 1) = L then 1 else 0))
   with
     Ghost,
     Pre  => Hi <= Lengths'Last + 1,
     Subprogram_Variant => (Decreases => Hi),
     Post => Count_Len'Result <=
               (if Hi <= Lengths'First then 0 else Hi - Lengths'First);

   --  The Kraft sum scaled by 2**L: sum over lengths 1 .. L of
   --  Counts (Len) * 2**(L - Len). A prefix code with these counts exists
   --  iff Kraft_Sum (C, 15) <= 2**15, and is complete iff equal.
   function Kraft_Sum
     (C : Length_Count_Array;
      L : Code_Length) return Natural
   is
     (if L = 0 then 0 else 2 * Kraft_Sum (C, L - 1) + C (L))
   with
     Ghost,
     Subprogram_Variant => (Decreases => L),
     Post => Kraft_Sum'Result <= Max_Symbols * (Pow2 (L) - 1);

   ---------------------------------------------------------------------
   --  Induction lemmas
   ---------------------------------------------------------------------

   --  Updating one cell shifts the sum by the difference, when the cell
   --  is within the summed prefix.
   procedure Lemma_Sum_Update
     (C     : Length_Count_Array;
      L     : Code_Length_Pos;
      V     : Symbol_Count;
      Up_To : Code_Length)
   with
     Ghost,
     Subprogram_Variant => (Decreases => Up_To),
     Post =>
       (if L <= Up_To
        then Sum_Counts ((C with delta L => V), Up_To) =
               Sum_Counts (C, Up_To) + V - C (L)
        else Sum_Counts ((C with delta L => V), Up_To) =
               Sum_Counts (C, Up_To));

   --  Prefix sums of a nonnegative sequence are monotone.
   procedure Lemma_Sum_Monotone
     (C  : Length_Count_Array;
      L1 : Code_Length;
      L2 : Code_Length)
   with
     Ghost,
     Pre  => L1 <= L2,
     Subprogram_Variant => (Decreases => L2),
     Post => Sum_Counts (C, L1) <= Sum_Counts (C, L2);

   --  An occurrence at position Hi1 makes the count over any longer
   --  prefix strictly larger.
   procedure Lemma_Count_Len_Step
     (Lengths : Code_Length_Array;
      L       : Code_Length_Pos;
      Hi1     : Natural;
      Hi2     : Natural)
   with
     Ghost,
     Pre  => Hi1 in Lengths'First .. Lengths'Last
             and then Hi2 in Hi1 + 1 .. Lengths'Last + 1
             and then Lengths (Hi1) = L,
     Subprogram_Variant => (Decreases => Hi2),
     Post => Count_Len (Lengths, L, Hi2) >= Count_Len (Lengths, L, Hi1) + 1;

   --  Once the Kraft sum over-subscribes a prefix of the lengths, adding
   --  longer lengths cannot repair it (each step doubles the deficit).
   procedure Lemma_Kraft_Blowup
     (C  : Length_Count_Array;
      L1 : Code_Length;
      L2 : Code_Length)
   with
     Ghost,
     Pre  => L1 <= L2 and then Kraft_Sum (C, L1) > Pow2 (L1),
     Subprogram_Variant => (Decreases => L2 - L1),
     Post => Kraft_Sum (C, L2) > Pow2 (L2);

   ---------------------------------------------------------------------
   --  The construction, defensive checks removed
   ---------------------------------------------------------------------

   procedure Construct
     (Lengths  : in     Code_Length_Array;
      Counts   :    out Length_Count_Array;
      Symbols  :    out Symbol_Map;
      Complete :    out Boolean;
      Valid    :    out Boolean)
   with
     Global => null,
     Pre    => Lengths'Length in 1 .. Max_Symbols,
     Post   =>
       (for all L in Code_Length_Pos =>
          Counts (L) = Count_Len (Lengths, L, Lengths'Last + 1))
       and then Sum_Counts (Counts, 15) <= Lengths'Length
       and then Valid = (Kraft_Sum (Counts, 15) <= Pow2 (15))
       and then Complete = (Kraft_Sum (Counts, 15) = Pow2 (15));

   ---------------------------------------------------------------------
   --  The decoder's slot bound
   ---------------------------------------------------------------------

   subtype Bit is Natural range 0 .. 1;
   type Bit_Array is array (Positive range <>) of Bit;

   --  The library decoder's per-length walk, over an explicit bit array,
   --  with the defensive slot check removed: the symbol-map access is
   --  proved in range from Sum_Counts (Counts, 15) <= Max_Symbols alone,
   --  which Construct establishes for every table it accepts.
   procedure Decode_Sim
     (Bits    : in     Bit_Array;
      Counts  : in     Length_Count_Array;
      Symbols : in     Symbol_Map;
      Symbol  :    out Symbol_Value;
      Found   :    out Boolean)
   with
     Global => null,
     Pre    => Bits'Length >= 15
               and then Sum_Counts (Counts, 15) <= Max_Symbols;

end Kraft;
