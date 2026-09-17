package body Kraft with SPARK_Mode => On is

   ---------------------------------------------------------------------
   --  Induction lemmas: each recurses on the summed prefix; the prover
   --  closes each step from one unfolding of the summation function plus
   --  the recursive call's postcondition.
   ---------------------------------------------------------------------

   procedure Lemma_Sum_Update
     (C     : Length_Count_Array;
      L     : Code_Length_Pos;
      V     : Symbol_Count;
      Up_To : Code_Length)
   is
   begin
      if Up_To > 0 then
         Lemma_Sum_Update (C, L, V, Up_To - 1);
      end if;
   end Lemma_Sum_Update;

   procedure Lemma_Sum_Monotone
     (C  : Length_Count_Array;
      L1 : Code_Length;
      L2 : Code_Length)
   is
   begin
      if L1 < L2 then
         Lemma_Sum_Monotone (C, L1, L2 - 1);
      end if;
   end Lemma_Sum_Monotone;

   procedure Lemma_Count_Len_Step
     (Lengths : Code_Length_Array;
      L       : Code_Length_Pos;
      Hi1     : Natural;
      Hi2     : Natural)
   is
   begin
      if Hi2 > Hi1 + 1 then
         Lemma_Count_Len_Step (Lengths, L, Hi1, Hi2 - 1);
      end if;
   end Lemma_Count_Len_Step;

   procedure Lemma_Kraft_Blowup
     (C  : Length_Count_Array;
      L1 : Code_Length;
      L2 : Code_Length)
   is
   begin
      if L1 < L2 then
         pragma Assert (Kraft_Sum (C, L1 + 1) > Pow2 (L1 + 1));
         Lemma_Kraft_Blowup (C, L1 + 1, L2);
      end if;
   end Lemma_Kraft_Blowup;

   ---------------------------------------------------------------------
   --  Construct
   ---------------------------------------------------------------------

   procedure Construct
     (Lengths  : in     Code_Length_Array;
      Counts   :    out Length_Count_Array;
      Symbols  :    out Symbol_Map;
      Complete :    out Boolean;
      Valid    :    out Boolean)
   is
      Offs : Length_Count_Array := (others => 0);
      Left : Integer range -Max_Symbols .. 2 ** 15;
   begin
      Counts   := (others => 0);
      Symbols  := (others => 0);
      Complete := False;
      Valid    := False;

      --  Histogram of the code lengths. The invariant keeps the histogram
      --  exact per length, which is what makes every later bound a fact
      --  about prefix sums rather than a defensive check.
      for I in Lengths'Range loop
         pragma Loop_Invariant
           (for all L in Code_Length_Pos =>
              Counts (L) = Count_Len (Lengths, L, I));
         pragma Loop_Invariant
           (Sum_Counts (Counts, 15) <= I - Lengths'First);
         if Lengths (I) /= 0 then
            Lemma_Sum_Update
              (Counts, Lengths (I), Counts (Lengths (I)) + 1, 15);
            Counts (Lengths (I)) := Counts (Lengths (I)) + 1;
         end if;
      end loop;

      pragma Assert
        (for all L in Code_Length_Pos =>
           Counts (L) = Count_Len (Lengths, L, Lengths'Last + 1));
      pragma Assert (Sum_Counts (Counts, 15) <= Lengths'Length);

      --  The Kraft loop: Left is the scaled remaining code space. The
      --  invariant ties it exactly to the ghost Kraft sum, so the sign
      --  of Left decides the Kraft inequality — and once negative, the
      --  blow-up lemma shows no longer length can repair it.
      Left := 1;
      for Len in Code_Length_Pos loop
         pragma Loop_Invariant (Left in 0 .. Pow2 (Len - 1));
         pragma Loop_Invariant
           (Left = Pow2 (Len - 1) - Kraft_Sum (Counts, Len - 1));
         Left := Left * 2 - Counts (Len);
         if Left < 0 then
            Lemma_Kraft_Blowup (Counts, Len, 15);
            return;
         end if;
      end loop;
      Complete := Left = 0;

      pragma Assert (Kraft_Sum (Counts, 15) <= Pow2 (15));

      --  Symbol offsets: prefix sums of the histogram. The library's
      --  defensive bound check is gone; the range check on the addition
      --  is discharged from monotonicity of prefix sums.
      for Len in 2 .. 15 loop
         pragma Loop_Invariant
           (for all L in 1 .. Len - 1 =>
              Offs (L) = Sum_Counts (Counts, L - 1));
         Lemma_Sum_Monotone (Counts, Len - 1, 15);
         Offs (Len) := Offs (Len - 1) + Counts (Len - 1);
      end loop;

      pragma Assert
        (for all L in Code_Length_Pos =>
           Offs (L) = Sum_Counts (Counts, L - 1));

      --  Sorted symbol fill. Offs (L) walks from the prefix sum below L
      --  up to the prefix sum including L; strict inequality at each
      --  write comes from the occurrence at I itself still being ahead.
      for I in Lengths'Range loop
         pragma Loop_Invariant
           (for all L in Code_Length_Pos =>
              Offs (L) = Sum_Counts (Counts, L - 1)
                         + Count_Len (Lengths, L, I));
         if Lengths (I) /= 0 then
            Lemma_Count_Len_Step
              (Lengths, Lengths (I), I, Lengths'Last + 1);
            Lemma_Sum_Monotone (Counts, Lengths (I), 15);
            Symbols (Offs (Lengths (I))) := I - Lengths'First;
            Offs (Lengths (I)) := Offs (Lengths (I)) + 1;
         end if;
      end loop;

      Valid := True;
   end Construct;

   ---------------------------------------------------------------------
   --  Decode_Sim
   ---------------------------------------------------------------------

   procedure Decode_Sim
     (Bits    : in     Bit_Array;
      Counts  : in     Length_Count_Array;
      Symbols : in     Symbol_Map;
      Symbol  :    out Symbol_Value;
      Found   :    out Boolean)
   is
      Code  : Natural := 0;
      First : Natural := 0;
      Index : Natural := 0;
      Count : Symbol_Count;
   begin
      Symbol := 0;
      Found  := False;
      for Len in Code_Length_Pos loop
         pragma Loop_Invariant (Code mod 2 = 0 and then Code < Pow2 (Len));
         pragma Loop_Invariant (First <= Code);
         pragma Loop_Invariant (Index = Sum_Counts (Counts, Len - 1));
         Code  := Code + Bits (Bits'First + (Len - 1));
         Count := Counts (Len);
         if Code - First < Count then
            --  The slot bound, proved instead of checked: the slot is
            --  below the prefix sum through Len, itself at most the full
            --  sum, at most the map size.
            Lemma_Sum_Monotone (Counts, Len, 15);
            Symbol := Symbols (Index + (Code - First));
            Found  := True;
            return;
         end if;
         Index := Index + Count;
         First := (First + Count) * 2;
         Code  := Code * 2;
      end loop;
   end Decode_Sim;

end Kraft;
