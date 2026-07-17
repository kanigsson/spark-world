package body Inflate.Codebooks with SPARK_Mode => On is

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

end Inflate.Codebooks;
