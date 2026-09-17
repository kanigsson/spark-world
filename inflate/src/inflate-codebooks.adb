package body Inflate.Codebooks with SPARK_Mode => On is

   ----------------------
   -- Lemma_Pow2_Power --
   ----------------------

   procedure Lemma_Pow2_Power (Length : Natural) is
   begin
      --  One branch per width, because what each branch supplies is a concrete
      --  exponent: the table entry and the power are then both literals. A
      --  disjunction of widths in one branch would leave the exponent
      --  variable, which is the case the provers do not take.
      case Length is
         when 0 => null;
         when 1 => null;
         when 2 => null;
         when 3 => null;
         when 4 => null;
         when 5 => null;
         when 6 => null;
         when 7 => null;
         when 8 => null;
         when 9 => null;
         when 10 => null;
         when 11 => null;
         when 12 => null;
         when 13 => null;
         when 14 => null;
         when 15 => null;
         when others => null;   --  excluded by the precondition
      end case;
   end Lemma_Pow2_Power;

   procedure Lemma_Count_Step
     (Lengths : Code_Length_Array;
      Length  : Code_Length_Pos;
      Position, Last : Symbol_Count)
   with
     Ghost,
     Pre  => Position < Last
               and then Last <= Max_Symbols
               and then Lengths (Symbol_Index (Position)) = Length,
     Post => Count_Length (Lengths, Length, Last) >
               Count_Length (Lengths, Length, Position),
     Subprogram_Variant => (Decreases => Last - Position);

   procedure Lemma_Count_Step
     (Lengths : Code_Length_Array;
      Length  : Code_Length_Pos;
      Position, Last : Symbol_Count)
   is
   begin
      if Last > Position + 1 then
         Lemma_Count_Step (Lengths, Length, Position, Last - 1);
      end if;
   end Lemma_Count_Step;

   function Rank_Of
     (Book : Codebook; Symbol : Symbol_Index) return Symbol_Count
   is
   begin
      Lemma_Count_Step
        (Book.Lengths, Book.Lengths (Symbol), Symbol, Max_Symbols);
      return Count_Length
        (Book.Lengths, Book.Lengths (Symbol), Symbol);
   end Rank_Of;

   procedure Build
     (Lengths : in     Code_Length_Array;
      Book    :    out Codebook;
      Success :    out Boolean)
   is
   begin
      Book.Lengths := Lengths;
      Book.Counts := (others => 0);

      for Symbol in Symbol_Index loop
         pragma Loop_Invariant
           (for all Length in Code_Length_Pos =>
              Book.Counts (Length) =
                Count_Length (Lengths, Length, Symbol));
         if Lengths (Symbol) /= 0 then
            Book.Counts (Lengths (Symbol)) :=
              Book.Counts (Lengths (Symbol)) + 1;
         end if;
      end loop;

      pragma Assert (Exact_Counts (Book));
      Success := Ready (Book);
   end Build;

   procedure Lemma_Exact_Books_Equal (Left, Right : Codebook)
   is
      procedure Lemma_Count_Length_Equal
        (Left_Lengths, Right_Lengths : Code_Length_Array;
         Length : Code_Length_Pos;
         Count  : Symbol_Count)
      with
        Ghost,
        Pre  => Left_Lengths = Right_Lengths,
        Post => Count_Length (Left_Lengths, Length, Count) =
                  Count_Length (Right_Lengths, Length, Count),
        Subprogram_Variant => (Decreases => Count);

      procedure Lemma_Count_Length_Equal
        (Left_Lengths, Right_Lengths : Code_Length_Array;
         Length : Code_Length_Pos;
         Count  : Symbol_Count)
      is
      begin
         if Count > 0 then
            Lemma_Count_Length_Equal
              (Left_Lengths, Right_Lengths, Length, Count - 1);
         end if;
      end Lemma_Count_Length_Equal;
   begin
      for Length in Code_Length_Pos loop
         pragma Loop_Invariant
           (for all L in Code_Length_Pos'First .. Length - 1 =>
              Left.Counts (L) = Right.Counts (L));
         Lemma_Count_Length_Equal
           (Left.Lengths, Right.Lengths, Length, Max_Symbols);
         pragma Assert (Left.Counts (Length) = Right.Counts (Length));
      end loop;
      pragma Assert (Left.Counts = Right.Counts);
   end Lemma_Exact_Books_Equal;

   procedure Lemma_Length_Arrays_Equal
     (Left, Right : Code_Length_Array) is null;

   procedure Lemma_Canonical_Lengths_Equal (Left, Right : Codebook)
   is
   begin
      pragma Assert
        (for all I in Symbol_Index => Left.Lengths (I) = Right.Lengths (I));
      Lemma_Length_Arrays_Equal (Left.Lengths, Right.Lengths);
   end Lemma_Canonical_Lengths_Equal;

   procedure Lemma_Count_Lengths_Equal
     (Left, Right : Code_Length_Array;
      Length      : Code_Length_Pos;
      Count       : Symbol_Count)
   with
     Ghost,
     Pre  => Left = Right,
     Post => Count_Length (Left, Length, Count) =
               Count_Length (Right, Length, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Count_Lengths_Equal
     (Left, Right : Code_Length_Array;
      Length      : Code_Length_Pos;
      Count       : Symbol_Count)
   is
   begin
      if Count > 0 then
         Lemma_Count_Lengths_Equal (Left, Right, Length, Count - 1);
      end if;
   end Lemma_Count_Lengths_Equal;

   procedure Lemma_First_Codes_Equal
     (Left, Right : Length_Count_Array;
      Length      : Code_Length_Pos)
   with
     Ghost,
     Pre  => Left = Right,
     Post => First_Code (Left, Length) = First_Code (Right, Length),
     Subprogram_Variant => (Decreases => Length);

   procedure Lemma_First_Codes_Equal
     (Left, Right : Length_Count_Array;
      Length      : Code_Length_Pos)
   is
   begin
      if Length > 1 then
         Lemma_First_Codes_Equal (Left, Right, Length - 1);
      end if;
   end Lemma_First_Codes_Equal;

   procedure Lemma_Kraft_Values_Equal
     (Left, Right : Length_Count_Array;
      Length      : Code_Length)
   with
     Ghost,
     Pre  => Left = Right,
     Post => Kraft_Value (Left, Length) = Kraft_Value (Right, Length),
     Subprogram_Variant => (Decreases => Length);

   procedure Lemma_Kraft_Values_Equal
     (Left, Right : Length_Count_Array;
      Length      : Code_Length)
   is
   begin
      if Length > 0 then
         Lemma_Kraft_Values_Equal (Left, Right, Length - 1);
      end if;
   end Lemma_Kraft_Values_Equal;

   procedure Lemma_Ready_From_Fields (Left, Right : Codebook)
   is
   begin
      pragma Assert (Exact_Counts (Left));
      pragma Assert (Canonical_Valid (Left));
      pragma Assert (Complete (Left));
      for Length in Code_Length_Pos loop
         pragma Loop_Invariant
           (for all L in Code_Length_Pos'First .. Length - 1 =>
              Right.Counts (L) =
                Count_Length (Right.Lengths, L, Max_Symbols));
         pragma Loop_Invariant
           (for all L in Code_Length_Pos'First .. Length - 1 =>
              First_Code (Right.Counts, L) + Right.Counts (L) <=
                Pow2 (L));
         Lemma_Count_Lengths_Equal
           (Left.Lengths, Right.Lengths, Length, Max_Symbols);
         Lemma_First_Codes_Equal (Left.Counts, Right.Counts, Length);
         pragma Assert
           (Right.Counts (Length) =
              Count_Length (Right.Lengths, Length, Max_Symbols));
         pragma Assert
           (First_Code (Right.Counts, Length) + Right.Counts (Length) <=
              Pow2 (Length));
      end loop;
      pragma Assert (Exact_Counts (Right));
      pragma Assert (Canonical_Valid (Right));
      Lemma_Kraft_Values_Equal (Left.Counts, Right.Counts, 15);
      pragma Assert (Complete (Right));
   end Lemma_Ready_From_Fields;

   procedure Lemma_Lengths_At_Most_From_Fields
     (Left, Right : Codebook;
      Maximum     : Code_Length)
   is
   begin
      for Symbol in Symbol_Index loop
         pragma Loop_Invariant
           (for all I in Symbol_Index'First .. Symbol - 1 =>
              Length_Of (Right, I) <= Maximum);
         pragma Assert (Left.Lengths (Symbol) = Right.Lengths (Symbol));
         pragma Assert (Length_Of (Left, Symbol) <= Maximum);
         pragma Assert (Length_Of (Right, Symbol) <= Maximum);
      end loop;
   end Lemma_Lengths_At_Most_From_Fields;

   procedure Lemma_Length_Of_From_Fields (Left, Right : Codebook)
   is
   begin
      for Symbol in Symbol_Index loop
         pragma Loop_Invariant
           (for all I in Symbol_Index'First .. Symbol - 1 =>
              Length_Of (Left, I) = Length_Of (Right, I));
         pragma Assert (Left.Lengths (Symbol) = Right.Lengths (Symbol));
         pragma Assert
           (Length_Of (Left, Symbol) = Length_Of (Right, Symbol));
      end loop;
   end Lemma_Length_Of_From_Fields;

   procedure Lemma_Code_Of_From_Fields
     (Left, Right : Codebook;
      Symbol      : Symbol_Index)
   is
      Length : constant Code_Length_Pos := Left.Lengths (Symbol);
   begin
      pragma Assert (Right.Lengths (Symbol) = Length);
      Lemma_Count_Lengths_Equal
        (Left.Lengths, Right.Lengths, Length, Symbol);
      pragma Assert
        (Rank_Of (Left, Symbol) =
           Count_Length (Left.Lengths, Length, Symbol));
      pragma Assert
        (Rank_Of (Right, Symbol) =
           Count_Length (Right.Lengths, Length, Symbol));
      pragma Assert (Rank_Of (Left, Symbol) = Rank_Of (Right, Symbol));
      Lemma_First_Codes_Equal (Left.Counts, Right.Counts, Length);
   end Lemma_Code_Of_From_Fields;

end Inflate.Codebooks;
