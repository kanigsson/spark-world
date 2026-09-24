package body BWT.Words
  with SPARK_Mode
is
   function Common (S : String; A, B, Len : Natural) return Natural is
   begin
      for K in 0 .. Len - 1 loop
         if S (A + K) /= S (B + K) then
            return K;
         end if;
         pragma Loop_Invariant
           (for all X in A .. A + K => S (X) = S (X - A + B));
      end loop;
      return Len;
   end Common;

   procedure Common_Same (S : String; A, B, C, D, Len : Natural) is
   begin
      null;
   end Common_Same;

   procedure Lex_Total (S : String; A, LA, B, LB : Natural) is
      M : constant Natural := Natural'Min (LA, LB);
   begin
      pragma Assert (Common (S, B, A, M) = Common (S, A, B, M));
   end Lex_Total;

   procedure Lex_Trans (S : String; A, LA, B, LB, C, LC : Natural) is
      M1 : constant Natural := Natural'Min (LA, LB);
      M2 : constant Natural := Natural'Min (LB, LC);
      M3 : constant Natural := Natural'Min (LA, LC);
      D1 : constant Natural := Common (S, A, B, M1);
      D2 : constant Natural := Common (S, B, C, M2);
      D3 : constant Natural := Common (S, A, C, M3);
   begin
      pragma Assert (Common (S, B, A, M1) = D1);
      pragma Assert (Common (S, C, B, M2) = D2);
      pragma Assert (Common (S, C, A, M3) = D3);
      if D1 < M1 and then D2 < M2 then
         pragma Assert (D3 = Natural'Min (D1, D2));
      elsif D1 < M1 then
         pragma Assert (LB <= LC);
         pragma Assert (D3 = D1);
      elsif D2 < M2 then
         if D2 < LA then
            pragma Assert (D3 = D2);
         else
            pragma Assert (LA < LC);
            pragma Assert (D3 = LA);
         end if;
      else
         pragma Assert (LA <= LB and then LB <= LC);
         pragma Assert (D3 = LA);
      end if;
   end Lex_Trans;

   procedure Lex_Prefix (S : String; A, LA, B, LB : Natural) is
   begin
      pragma Assert (Common (S, A, B, LA) = LA);
   end Lex_Prefix;

   procedure Lyndon_Same (S : String; A, B, L : Natural) is
   begin
      for O in 1 .. L - 1 loop
         pragma Assert (Below_Suffix (S, A, L, A + O));
         Common_Same (S, A, A + O, B, B + O, L - O);
         pragma Loop_Invariant
           (for all X in B + 1 .. B + O => Below_Suffix (S, B, L, X));
      end loop;
   end Lyndon_Same;

   procedure Shift_Back (S : String; I, J, P, X, T : Natural) is
   begin
      if T > 0 then
         pragma Assert (X >= I + P);
         pragma Assert (S (X) = S (X - P));
         pragma Assert (X - P >= I + (T - 1) * P);
         Shift_Back (S, I, J, P, X - P, T - 1);
         pragma Assert (X - P - (T - 1) * P = X - T * P);
      end if;
   end Shift_Back;

   --  One proper suffix of the extended word, starting O letters in.
   procedure Extend_Suffix (S : String; I, J, P, O : Positive)
   with
     Pre  =>
       Supported (S)
       and then J <= S'Length
       and then P < J
       and then I <= J - P
       and then O <= J - I
       and then Lyndon (S, I, P)
       and then Periodic (S, I, J, P)
       and then S (J - P) < S (J),
     Post => Below_Suffix (S, I, J - I + 1, I + O);

   procedure Extend_Suffix (S : String; I, J, P, O : Positive) is
      A : constant Natural := O / P;
      B : constant Natural := O mod P;
      R : constant Natural := J - I - O;
      U : constant Positive := J - I + 1;
   begin
      pragma Assert (O = A * P + B);
      if B /= 0 then
         pragma Assert (Below_Suffix (S, I, P, I + B));
         declare
            D : constant Natural := Common (S, I, I + B, P - B);
         begin
            pragma Assert (D < P - B);
            pragma Assert (S (I + D) < S (I + B + D));
            if D < R then
               for X in 0 .. D loop
                  Shift_Back (S, I, J, P, I + O + X, A);
                  pragma Assert (I + O + X - A * P = I + B + X);
                  pragma Loop_Invariant
                    (for all Z in I + O .. I + O + X => S (Z) = S (Z - O + B));
               end loop;
               pragma Assert (S (I + D) < S (I + O + D));
               pragma Assert (Common (S, I, I + O, U - O) = D);
            else
               for X in 0 .. R - 1 loop
                  Shift_Back (S, I, J, P, I + O + X, A);
                  pragma Assert (I + O + X - A * P = I + B + X);
                  pragma Loop_Invariant
                    (for all Z in I + O .. I + O + X => S (Z) = S (Z - O));
               end loop;
               pragma Assert (A >= 1 or else B + R = J - P - I);
               if A >= 1 then
                  Shift_Back (S, I, J, P, J - P, A - 1);
                  pragma Assert (J - P - (A - 1) * P = I + B + R);
               end if;
               pragma Assert (S (J - P) = S (I + B + R));
               pragma Assert (S (I + R) <= S (I + B + R));
               pragma Assert (S (I + R) < S (I + O + R));
               pragma Assert (Common (S, I, I + O, U - O) = R);
            end if;
         end;
      else
         pragma Assert (A >= 1);
         for X in 0 .. R - 1 loop
            Shift_Back (S, I, J, P, I + O + X, A);
            pragma Assert (I + O + X - A * P = I + X);
            pragma Loop_Invariant
              (for all Z in I + O .. I + O + X => S (Z) = S (Z - O));
         end loop;
         Shift_Back (S, I, J, P, J - P, A - 1);
         pragma Assert (J - P - (A - 1) * P = I + R);
         pragma Assert (S (I + R) < S (I + O + R));
         pragma Assert (Common (S, I, I + O, U - O) = R);
      end if;
   end Extend_Suffix;

   procedure Lyndon_Extend (S : String; I, J, P : Positive) is
   begin
      for O in 1 .. J - I loop
         Extend_Suffix (S, I, J, P, O);
         pragma Loop_Invariant
           (for all X in I + 1 .. I + O => Below_Suffix (S, I, J - I + 1, X));
      end loop;
   end Lyndon_Extend;
end BWT.Words;
