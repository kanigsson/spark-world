with BWT.Words;

package body BWT.Bijective
  with SPARK_Mode
is
   use BWT.Factorizations;
   use BWT.Words;

   function Factor_Rotations (S : String) return Table is
      pragma
        Annotate
          (GNATprove,
           Hide_Info,
           "Expression_Function_Body",
           Prefix_Factorization);

      Rows : Table (1 .. S'Length) := (others => (1, 1, 0));
      I    : Positive := 1;
      J, K : Positive;
      Size : Positive;
      --  The text from I agrees with the previous factor for Dom letters and
      --  then falls below it, so no later factor can exceed that one.
      Dom  : Natural := 0
      with Ghost;

      procedure Emit (Rows : in out Table; I, Size : Positive)
      with
        Pre  =>
          Rows'Last <= Max_Length
          and then I in Rows'Range
          and then Size <= Rows'Last - I + 1,
        Post =>
          (for all P in Rows'Range =>
             (if P in I .. I + Size - 1
              then Rows (P) = (I, Size, P - I)
              else Rows (P) = Rows'Old (P)));

      procedure Emit (Rows : in out Table; I, Size : Positive) is
      begin
         for Offset in 0 .. Size - 1 loop
            Rows (I + Offset) := (I, Size, Offset);
            pragma Loop_Invariant
              (for all P in Rows'Range =>
                 (if P in I .. I + Offset
                  then Rows (P) = (I, Size, P - I)
                  else Rows (P) = Rows'Loop_Entry (P)));
         end loop;
      end Emit;
   begin
      Empty_Prefix (S, Rows);
      while I <= S'Length loop
         pragma Loop_Invariant (I <= S'Length + 1);
         pragma Loop_Invariant (Prefix_Factorization (S, Rows, I));
         pragma Loop_Invariant
           (if I > 1
            then Dominated (S, I, Rows (I - 1).First, Rows (I - 1).Length, Dom));
         pragma Loop_Variant (Increases => I);
         J := I + 1;
         K := I;
         --  S (I .. J - 1) repeats the Lyndon word S (I .. I + J - K - 1).
         while J <= S'Length and then S (K) <= S (J) loop
            pragma Loop_Invariant (I <= K and then K < J);
            pragma Loop_Invariant (J in I + 1 .. S'Length + 1);
            pragma Loop_Invariant (Lyndon (S, I, J - K));
            pragma Loop_Invariant (Periodic (S, I, J, J - K));
            pragma Loop_Variant (Increases => J);
            if S (K) < S (J) then
               Lyndon_Extend (S, I, J, J - K);
               K := I;
            else
               K := K + 1;
            end if;
            J := J + 1;
         end loop;
         Size := J - K;
         pragma Assert (J > S'Length or else S (J - Size) > S (J));
         declare
            Run_Start : constant Positive := I
            with Ghost;
         begin
            if I > 1 then
               Dominated_Less
                 (S, I, Rows (I - 1).First, Rows (I - 1).Length, Dom, Size);
            end if;
            while I <= K loop
               pragma Loop_Invariant (I in Run_Start .. K + Size);
               pragma Loop_Invariant (I <= S'Length + 1);
               pragma Loop_Invariant (Prefix_Factorization (S, Rows, I));
               pragma Loop_Invariant (Lyndon (S, I, Size));
               pragma Loop_Invariant
                 (if I > 1
                  then
                    Lex_LE
                      (S, I, Size, Rows (I - 1).First, Rows (I - 1).Length));
               pragma Loop_Invariant
                 (if I > Run_Start
                  then
                    Rows (I - 1).First = I - Size
                    and then Rows (I - 1).Length = Size);
               pragma Loop_Variant (Increases => I);
               declare
                  Old : constant Table := Rows
                  with Ghost;
               begin
                  Emit (Rows, I, Size);
                  Extend_Prefix (S, Old, Rows, I, Size);
               end;
               I := I + Size;
               if I <= K then
                  pragma Assert (Same (S, I - Size, I, Size));
                  Lyndon_Same (S, I - Size, I, Size);
                  Lex_Total (S, I, Size, I - Size, Size);
               end if;
            end loop;
            pragma Assert (I > Run_Start);
            Dom := J - I;
            pragma Assert (Same (S, I, I - Size, Dom));
         end;
      end loop;
      return Rows;
   end Factor_Rotations;
end BWT.Bijective;
