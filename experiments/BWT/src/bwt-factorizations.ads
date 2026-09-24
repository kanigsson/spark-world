with BWT.Rotations;
with BWT.Words;

--  A rotation table that records a Lyndon factorization: row P describes the
--  factor containing position P, rotated to start at P.

package BWT.Factorizations
  with SPARK_Mode, Ghost
is
   use BWT.Rotations;
   use BWT.Words;

   --  Positions 1 .. I - 1 are covered by complete, nonincreasing Lyndon
   --  factors.
   function Prefix_Factorization
     (S : String; Rows : Table; I : Positive) return Boolean
   is (Supported (S)
       and then Rows'First = 1
       and then Rows'Length = S'Length
       and then I <= S'Length + 1
       and then (for all P in 1 .. I - 1 =>
                   Valid (Rows (P), S'Length)
                   and then Rows (P).First + Rows (P).Offset = P
                   and then Rows (P).First + Rows (P).Length <= I)
       and then (for all P in 1 .. I - 1 =>
                   (for all Q in
                      Rows (P).First .. Rows (P).First + Rows (P).Length - 1 =>
                      Rows (Q).First = Rows (P).First
                      and then Rows (Q).Length = Rows (P).Length))
       and then (for all P in 1 .. I - 1 =>
                   Lyndon (S, Rows (P).First, Rows (P).Length))
       and then (for all P in 1 .. I - 1 =>
                   (if Rows (P).First + Rows (P).Length < I
                    then
                      Rows (Rows (P).First + Rows (P).Length).Offset = 0
                      and then Lex_LE
                                 (S,
                                  Rows (P).First + Rows (P).Length,
                                  Rows (Rows (P).First + Rows (P).Length)
                                    .Length,
                                  Rows (P).First,
                                  Rows (P).Length))));

   function Factorization (S : String; Rows : Table) return Boolean
   is (Supported (S) and then Prefix_Factorization (S, Rows, S'Length + 1));

   procedure Empty_Prefix (S : String; Rows : Table)
   with
     Pre  =>
       Supported (S) and then Rows'First = 1 and then Rows'Length = S'Length,
     Post => Prefix_Factorization (S, Rows, 1);

   --  Rows gains the factor I .. I + Size - 1 and keeps everything before.
   procedure Extend_Prefix (S : String; Old, Rows : Table; I, Size : Positive)
   with
     Pre  =>
       Prefix_Factorization (S, Old, I)
       and then Rows'First = 1
       and then Rows'Length = S'Length
       and then Size <= S'Length
       and then I - 1 + Size <= S'Length
       and then (for all P in 1 .. I - 1 => Rows (P) = Old (P))
       and then (for all P in I .. I + Size - 1 => Rows (P) = (I, Size, P - I))
       and then Lyndon (S, I, Size)
       and then (if I > 1
                 then
                   Lex_LE (S, I, Size, Old (I - 1).First, Old (I - 1).Length)),
     Post => Prefix_Factorization (S, Rows, I + Size);

   --  Every word starting at I is smaller than the factor F .. F + L - 1:
   --  the text from I agrees with it for D letters, then falls below it or
   --  ends.
   function Dominated (S : String; I, F, L, D : Natural) return Boolean
   is (In_Word (S, F, L)
       and then I in 1 .. S'Length + 1
       and then D < L
       and then I - 1 + D <= S'Length
       and then Same (S, I, F, D)
       and then (if I + D <= S'Length then S (I + D) < S (F + D)))
   with Pre => Supported (S);

   procedure Dominated_Less (S : String; I, F, L, D, Len : Natural)
   with
     Pre  =>
       Supported (S)
       and then Dominated (S, I, F, L, D)
       and then In_Word (S, I, Len)
       and then Len >= 1,
     Post => Lex_Less (S, I, Len, F, L);

   procedure Bounds (S : String; Rows : Table)
   with
     Pre  => Factorization (S, Rows),
     Post => Rows'First = 1 and then Rows'Length = S'Length;

   procedure Intro (S : String; Rows : Table)
   with
     Pre  =>
       Supported (S)
       and then Rows'First = 1
       and then Rows'Length = S'Length
       and then (for all P in 1 .. S'Length =>
                   Valid (Rows (P), S'Length)
                   and then Rows (P).First + Rows (P).Offset = P
                   and then Rows (P).First + Rows (P).Length <= S'Length + 1)
       and then (for all P in 1 .. S'Length =>
                   (for all Q in
                      Rows (P).First .. Rows (P).First + Rows (P).Length - 1 =>
                      Rows (Q).First = Rows (P).First
                      and then Rows (Q).Length = Rows (P).Length))
       and then (for all P in 1 .. S'Length =>
                   Lyndon (S, Rows (P).First, Rows (P).Length))
       and then (for all P in 1 .. S'Length =>
                   (if Rows (P).First + Rows (P).Length < S'Length + 1
                    then
                      Rows (Rows (P).First + Rows (P).Length).Offset = 0
                      and then Lex_LE
                                 (S,
                                  Rows (P).First + Rows (P).Length,
                                  Rows (Rows (P).First + Rows (P).Length)
                                    .Length,
                                  Rows (P).First,
                                  Rows (P).Length))),
     Post => Factorization (S, Rows);

   --  Factors never increase along the string.
   procedure Chain_LE (S : String; Rows : Table; B, C : Positive)
   with
     Pre  =>
       Factorization (S, Rows)
       and then B <= C
       and then C <= S'Length
       and then Rows (B).Offset = 0
       and then Rows (C).Offset = 0,
     Post => Lex_LE (S, C, Rows (C).Length, B, Rows (B).Length);

   --  Two nonincreasing Lyndon factorizations agree on the factor at I.
   procedure No_Longer (S : String; A, B : Table; I : Positive)
   with
     Pre  =>
       Factorization (S, A)
       and then Factorization (S, B)
       and then I <= S'Length
       and then A (I).Offset = 0
       and then B (I).Offset = 0,
     Post => A (I).Length <= B (I).Length;

   --  The nonincreasing Lyndon factorization is unique.
   procedure Unique (S : String; A, B : Table)
   with
     Pre  => Factorization (S, A) and then Factorization (S, B),
     Post => (for all P in A'Range => A (P) = B (P));
end BWT.Factorizations;
