package body BWT.Factorizations
  with SPARK_Mode
is
   procedure Empty_Prefix (S : String; Rows : Table) is null;

   procedure Extend_Prefix (S : String; Old, Rows : Table; I, Size : Positive)
   is
      E : constant Positive := I + Size;
   begin
      pragma Assert
        (for all P in 1 .. E - 1 =>
           Valid (Rows (P), S'Length)
           and then Rows (P).First + Rows (P).Offset = P
           and then Rows (P).First + Rows (P).Length <= E);
      pragma Assert
        (for all P in 1 .. I - 1 =>
           (for all Q in
              Rows (P).First .. Rows (P).First + Rows (P).Length - 1 =>
                Rows (Q) = Old (Q)));
      pragma Assert
        (for all P in 1 .. E - 1 =>
           (for all Q in
              Rows (P).First .. Rows (P).First + Rows (P).Length - 1 =>
                Rows (Q).First = Rows (P).First
                and then Rows (Q).Length = Rows (P).Length));
      pragma Assert
        (for all P in 1 .. E - 1 =>
           Lyndon (S, Rows (P).First, Rows (P).Length));
      --  The factor that ended at I - 1 is the one the new factor follows.
      pragma Assert
        (for all P in 1 .. I - 1 =>
           (if Old (P).First + Old (P).Length = I
            then
              Old (I - 1).First = Old (P).First
              and then Old (I - 1).Length = Old (P).Length));
      pragma Assert
        (for all P in 1 .. E - 1 =>
           (if Rows (P).First + Rows (P).Length < E
            then
              Rows (Rows (P).First + Rows (P).Length).Offset = 0
              and then Lex_LE
                         (S,
                          Rows (P).First + Rows (P).Length,
                          Rows (Rows (P).First + Rows (P).Length).Length,
                          Rows (P).First,
                          Rows (P).Length)));
   end Extend_Prefix;

   procedure Dominated_Less (S : String; I, F, L, D, Len : Natural) is
      M : constant Natural := Natural'Min (Len, L);
   begin
      if Len <= D then
         pragma Assert (Same (S, I, F, Len));
         pragma Assert (Common (S, I, F, M) = Len);
      else
         pragma Assert (I + D <= S'Length);
         pragma Assert (Common (S, I, F, M) = D);
      end if;
   end Dominated_Less;

   procedure Chain_LE (S : String; Rows : Table; B, C : Positive) is
      X : Positive := B;
   begin
      Lex_Total (S, B, Rows (B).Length, B, Rows (B).Length);
      while X < C loop
         pragma Loop_Invariant (X in B .. C);
         pragma Loop_Invariant (Rows (X).Offset = 0);
         pragma Loop_Invariant
           (Lex_LE (S, X, Rows (X).Length, B, Rows (B).Length));
         pragma Loop_Variant (Increases => X);
         declare
            Next : constant Positive := X + Rows (X).Length;
         begin
            pragma Assert (C >= Next);
            Lex_Trans
              (S,
               Next,
               Rows (Next).Length,
               X,
               Rows (X).Length,
               B,
               Rows (B).Length);
            X := Next;
         end;
      end loop;
   end Chain_LE;

   procedure No_Longer (S : String; A, B : Table; I : Positive) is
      LA : constant Positive := A (I).Length;
      LB : constant Positive := B (I).Length;
   begin
      if LA > LB then
         declare
            E1 : constant Positive := I + LA - 1;
            C  : constant Positive := B (E1).First;
            LC : constant Positive := B (C).Length;
            V  : constant Positive := E1 - C + 1;
         begin
            pragma Assert (B (C).First = C);
            pragma Assert (C >= I + LB);
            pragma Assert (V <= LC);
            --  The factor at I is below its suffix from C, which is a
            --  prefix of the factor at C, which is at most the factor at I
            --  in the other factorization, a proper prefix of the first.
            pragma Assert (Below_Suffix (S, I, LA, C));
            pragma Assert (Lex_Less (S, I, LA, C, V));
            if V < LC then
               Lex_Prefix (S, C, V, C, LC);
            else
               Lex_Total (S, C, V, C, LC);
            end if;
            Chain_LE (S, B, I, C);
            Lex_Prefix (S, I, LB, I, LA);
            Lex_Trans (S, I, LA, C, V, C, LC);
            Lex_Trans (S, I, LA, C, LC, I, LB);
            Lex_Trans (S, I, LA, I, LB, I, LA);
            Lex_Total (S, I, LA, I, LA);
         end;
      end if;
   end No_Longer;

   procedure Unique (S : String; A, B : Table) is
      I : Positive := 1;
   begin
      while I <= S'Length loop
         pragma Loop_Invariant (for all P in 1 .. I - 1 => A (P) = B (P));
         pragma Loop_Invariant (A (I).Offset = 0 and then B (I).Offset = 0);
         pragma Loop_Variant (Increases => I);
         No_Longer (S, A, B, I);
         No_Longer (S, B, A, I);
         declare
            L : constant Positive := A (I).Length;
         begin
            pragma Assert
              (for all P in I .. I + L - 1 =>
                 A (P) = (I, L, P - I) and then B (P) = (I, L, P - I));
            I := I + L;
         end;
      end loop;
   end Unique;
end BWT.Factorizations;
