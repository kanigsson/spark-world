--  Finite words as slices S (A .. A + Len - 1) of one string, under
--  lexicographic order, and the Lyndon words among them.

package BWT.Words
  with SPARK_Mode, Ghost
is
   function In_Word (S : String; A, Len : Natural) return Boolean
   is (Supported (S)
       and then A in 1 .. Max_Length + 1
       and then Len <= Max_Length
       and then A - 1 + Len <= S'Length);

   --  Length of the longest common prefix, bounded by Len.
   function Common (S : String; A, B, Len : Natural) return Natural
   with
     Pre  => In_Word (S, A, Len) and then In_Word (S, B, Len),
     Post =>
       Common'Result <= Len
       and then (for all X in A .. A + Common'Result - 1 =>
                   S (X) = S (X - A + B))
       and then (if Common'Result < Len
                 then S (A + Common'Result) /= S (B + Common'Result));

   function Lex_Less (S : String; A, LA, B, LB : Natural) return Boolean
   is (if Common (S, A, B, Natural'Min (LA, LB)) < Natural'Min (LA, LB)
       then
         S (A + Common (S, A, B, Natural'Min (LA, LB)))
         < S (B + Common (S, A, B, Natural'Min (LA, LB)))
       else LA < LB)
   with Pre => In_Word (S, A, LA) and then In_Word (S, B, LB);

   function Lex_LE (S : String; A, LA, B, LB : Natural) return Boolean
   is (not Lex_Less (S, B, LB, A, LA))
   with Pre => In_Word (S, A, LA) and then In_Word (S, B, LB);

   --  The word F .. F + L - 1 is smaller than its suffix from X.
   function Below_Suffix (S : String; F, L, X : Natural) return Boolean
   is (Lex_Less (S, F, L, X, F + L - X))
   with Pre => In_Word (S, F, L) and then X in F .. F + L;

   --  Strictly smaller than each of its proper suffixes.
   function Lyndon (S : String; F, L : Natural) return Boolean
   is (L >= 1
       and then (for all X in F + 1 .. F + L - 1 => Below_Suffix (S, F, L, X)))
   with Pre => In_Word (S, F, L);

   --  Contents agree on the first Len letters.
   function Same (S : String; A, B, Len : Natural) return Boolean
   is (for all X in A .. A + Len - 1 => S (X) = S (X - A + B))
   with Pre => In_Word (S, A, Len) and then In_Word (S, B, Len);

   procedure Common_Same (S : String; A, B, C, D, Len : Natural)
   with
     Pre  =>
       In_Word (S, A, Len)
       and then In_Word (S, B, Len)
       and then In_Word (S, C, Len)
       and then In_Word (S, D, Len)
       and then Same (S, A, C, Len)
       and then Same (S, B, D, Len),
     Post => Common (S, A, B, Len) = Common (S, C, D, Len);

   procedure Lex_Total (S : String; A, LA, B, LB : Natural)
   with
     Pre  => In_Word (S, A, LA) and then In_Word (S, B, LB),
     Post =>
       (Lex_Less (S, A, LA, B, LB)
        or else Lex_Less (S, B, LB, A, LA)
        or else (LA = LB and then Same (S, A, B, LA)))
       and then not (Lex_Less (S, A, LA, B, LB)
                     and then Lex_Less (S, B, LB, A, LA))
       and then (if LA = LB and then Same (S, A, B, LA)
                 then not Lex_Less (S, A, LA, B, LB));

   procedure Lex_Trans (S : String; A, LA, B, LB, C, LC : Natural)
   with
     Pre  =>
       In_Word (S, A, LA)
       and then In_Word (S, B, LB)
       and then In_Word (S, C, LC)
       and then Lex_LE (S, A, LA, B, LB)
       and then Lex_LE (S, B, LB, C, LC),
     Post =>
       Lex_LE (S, A, LA, C, LC)
       and then (if Lex_Less (S, A, LA, B, LB) or Lex_Less (S, B, LB, C, LC)
                 then Lex_Less (S, A, LA, C, LC));

   --  A proper prefix is smaller.
   procedure Lex_Prefix (S : String; A, LA, B, LB : Natural)
   with
     Pre  =>
       In_Word (S, A, LA)
       and then In_Word (S, B, LB)
       and then LA < LB
       and then Same (S, A, B, LA),
     Post => Lex_Less (S, A, LA, B, LB);

   --  Lyndon depends only on the letters.
   procedure Lyndon_Same (S : String; A, B, L : Natural)
   with
     Pre  =>
       In_Word (S, A, L)
       and then In_Word (S, B, L)
       and then Lyndon (S, A, L)
       and then Same (S, A, B, L),
     Post => Lyndon (S, B, L);

   --  Periodicity with period P on I .. J - 1, in the form Duval maintains.
   function Periodic (S : String; I, J, P : Positive) return Boolean
   is (for all X in I + P .. J - 1 => S (X) = S (X - P))
   with
     Pre =>
       Supported (S)
       and then J - 1 <= S'Length
       and then I <= J
       and then P <= S'Length;

   procedure Shift_Back (S : String; I, J, P, X, T : Natural)
   with
     Pre                =>
       Supported (S)
       and then J - 1 <= S'Length
       and then I in 1 .. J
       and then P in 1 .. S'Length
       and then Periodic (S, I, J, P)
       and then X <= J - 1
       and then T <= S'Length
       and then X >= I + T * P,
     Post               => S (X) = S (X - T * P),
     Subprogram_Variant => (Decreases => T);

   --  The step of Duval's algorithm that lengthens the current Lyndon word:
   --  a periodic repetition of a Lyndon word followed by a letter larger
   --  than the one the period predicts is itself a Lyndon word.
   procedure Lyndon_Extend (S : String; I, J, P : Positive)
   with
     Pre  =>
       Supported (S)
       and then J <= S'Length
       and then P < J
       and then I <= J - P
       and then Lyndon (S, I, P)
       and then Periodic (S, I, J, P)
       and then S (J - P) < S (J),
     Post => Lyndon (S, I, J - I + 1);
end BWT.Words;
