with BWT.Key_Sort;
with BWT.Permutations;
with BWT.Ranks;
with BWT.Rotations;

package body BWT.Doubling
  with SPARK_Mode
is
   use BWT.Key_Sort;
   use BWT.Ranks;
   use BWT.Rotations;

   --  Positions 1 .. N stand for the rotations of S starting there.
   function Rot (N, P : Positive) return Rotation
   is (1, N, P - 1)
   with Pre => P <= N, Post => Valid (Rot'Result, N);

   --  The position H letters on, and the one H letters back.
   function Next (N, P, H : Positive) return Positive
   is (if P + H <= N then P + H else P + H - N)
   with
     Pre  => N <= Max_Length and then P <= N and then H < N,
     Post => Next'Result <= N;

   function Back (N, P, H : Positive) return Positive
   is (if P > H then P - H else P - H + N)
   with
     Pre  => N <= Max_Length and then P <= N and then H < N,
     Post => Back'Result <= N and then Next (N, Back'Result, H) = P;

   --  Ranks order positions as the first H letters of their rotations do.
   function Ranked (S : String; R : Keys; H : Natural) return Boolean
   is (R'First = 1
       and then R'Length = S'Length
       and then (for all X of R => X < S'Length)
       and then (for all A in R'Range =>
                   (for all B in R'Range =>
                      (R (A) <= R (B))
                      = LE (S, Rot (S'Length, A), Rot (S'Length, B), H)
                      and then (R (A) = R (B))
                               = Equal_Prefix
                                   (S,
                                    Rot (S'Length, A),
                                    Rot (S'Length, B),
                                    H))))
   with Ghost, Pre => Supported (S) and then H <= 4 * Max_Length;

   function Distinct_Keys (R : Keys) return Boolean
   is (for all A in R'Range =>
         (for all B in R'Range => (if A /= B then R (A) /= R (B))))
   with Ghost;

   --  Positions listed in SA have nondecreasing ranks.
   function Sorted_By (R : Keys; SA : Mapping) return Boolean
   is (for all P in SA'Range =>
         (for all Q in P .. SA'Last => R (SA (P)) <= R (SA (Q))))
   with Ghost, Pre => (for all X of SA => X in R'Range);

   --  The lexicographic order of rank pairs.
   function Pair_LE (K1, K2 : Keys; A, B : Positive) return Boolean
   is (K1 (A) < K1 (B) or else (K1 (A) = K1 (B) and then K2 (A) <= K2 (B)))
   with
     Ghost,
     Pre =>
       K2'First = K1'First
       and then K2'Last = K1'Last
       and then A in K1'Range
       and then B in K1'Range;

   --  Result (Map (K)) := Items (K), for all K.
   procedure Scatter (Map, Items : Mapping; Result : out Mapping)
   with
     Pre  =>
       Permutation (Map)
       and then Items'First = 1
       and then Items'Length = Map'Length
       and then Result'First = 1
       and then Result'Length = Map'Length
       and then (for all X of Items => X in 1 .. Map'Length)
       and then (for all I in Items'Range =>
                   (for all J in Items'Range =>
                      (if I /= J then Items (I) /= Items (J)))),
     Post =>
       Permutation (Result)
       and then (for all K in Map'Range => Result (Map (K)) = Items (K));

   procedure Scatter (Map, Items : Mapping; Result : out Mapping) is
      Inv : constant Mapping := Permutations.Inverse (Map)
      with Ghost;
   begin
      Result := (others => 1);
      for K in Map'Range loop
         Result (Map (K)) := Items (K);
         pragma
           Loop_Invariant
             (for all J in 1 .. K => Result (Map (J)) = Items (J));
      end loop;
      pragma
        Assert (for all I in Result'Range => Result (I) = Items (Inv (I)));
   end Scatter;

   --  Numbers the classes of equal pairs along SA, from 0.
   procedure Dense_Ranks
     (SA : Mapping; K1, K2 : Keys; R : out Keys; Classes : out Positive)
   with
     Pre  =>
       Permutation (SA)
       and then SA'Length >= 1
       and then K1'First = 1
       and then K1'Length = SA'Length
       and then K2'First = 1
       and then K2'Length = SA'Length
       and then R'First = 1
       and then R'Length = SA'Length
       and then (for all P in SA'Range =>
                   (for all Q in P .. SA'Last =>
                      Pair_LE (K1, K2, SA (P), SA (Q)))),
     Post =>
       (for all X of R => X < R'Length)
       and then (for all A in R'Range =>
                   (for all B in R'Range =>
                      (R (A) <= R (B)) = Pair_LE (K1, K2, A, B)))
       and then Classes <= R'Length
       and then (if Classes = R'Length then Distinct_Keys (R))
       and then Sorted_By (R, SA);

   procedure Dense_Ranks
     (SA : Mapping; K1, K2 : Keys; R : out Keys; Classes : out Positive)
   is
      Inv : constant Mapping := Permutations.Inverse (SA)
      with Ghost;
   begin
      R := (others => 0);
      Classes := 1;
      for I in 2 .. SA'Last loop
         if K1 (SA (I)) /= K1 (SA (I - 1))
           or else K2 (SA (I)) /= K2 (SA (I - 1))
         then
            Classes := Classes + 1;
         end if;
         R (SA (I)) := Classes - 1;
         pragma Loop_Invariant (Classes <= I);
         pragma Loop_Invariant (R (SA (I)) = Classes - 1);
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                R (SA (P)) <= P - 1 and then R (SA (I)) - R (SA (P)) <= I - P);
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                (for all Q in 1 .. I =>
                   (R (SA (P)) <= R (SA (Q)))
                   = Pair_LE (K1, K2, SA (P), SA (Q))));
      end loop;
      pragma Assert (R (SA (SA'Last)) = Classes - 1);
      pragma
        Assert
          (for all P in SA'Range =>
             (for all Q in SA'Range =>
                (R (SA (P)) <= R (SA (Q)))
                = Pair_LE (K1, K2, SA (P), SA (Q))));
      pragma Assert (for all A in R'Range => SA (Inv (A)) = A);
      pragma
        Assert
          (for all A in R'Range =>
             (for all B in R'Range =>
                (R (SA (Inv (A))) <= R (SA (Inv (B))))
                = Pair_LE (K1, K2, SA (Inv (A)), SA (Inv (B)))));
      if Classes = R'Length then
         pragma Assert (for all P in SA'Range => R (SA (P)) = P - 1);
         pragma Assert (for all A in R'Range => R (A) = Inv (A) - 1);
      end if;
   end Dense_Ranks;

   --  One letter decides the first round.
   procedure Initial_Pair (S : String; A, B : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S) and then A in 1 .. S'Length and then B in 1 .. S'Length,
     Post =>
       LE (S, Rot (S'Length, A), Rot (S'Length, B), 1) = (S (A) <= S (B))
       and then Equal_Prefix (S, Rot (S'Length, A), Rot (S'Length, B), 1)
                = (S (A) = S (B));

   procedure Initial_Pair (S : String; A, B : Positive) is
   begin
      Letter_Direct (S, Rot (S'Length, A), 0);
      Letter_Direct (S, Rot (S'Length, B), 0);
   end Initial_Pair;

   procedure Initial
     (S : String; R : out Keys; SA : out Mapping; Classes : out Positive)
   with
     Pre  =>
       Supported (S)
       and then S'Length > 0
       and then R'First = 1
       and then R'Length = S'Length
       and then SA'First = 1
       and then SA'Length = S'Length,
     Post =>
       Ranked (S, R, 1)
       and then Permutation (SA)
       and then Sorted_By (R, SA)
       and then Classes <= S'Length
       and then (if Classes = S'Length then Distinct_Keys (R));

   procedure Initial
     (S : String; R : out Keys; SA : out Mapping; Classes : out Positive)
   is
      N     : constant Positive := S'Length;
      Code  : Keys (1 .. N) := (others => 0);
      Zero  : constant Keys (1 .. N) := (others => 0);
      Ident : Mapping (1 .. N) := (others => 1);
   begin
      for I in 1 .. N loop
         Code (I) := Character'Pos (S (I));
         Ident (I) := I;
         pragma
           Loop_Invariant
             (for all J in 1 .. I =>
                Code (J) = Character'Pos (S (J)) and then Ident (J) = J);
      end loop;
      declare
         Map : constant Mapping := Place (Code, 256);
         Inv : constant Mapping := Permutations.Inverse (Map)
         with Ghost;
      begin
         Scatter (Map, Ident, SA);
         pragma Assert (for all P in 1 .. N => SA (P) = Inv (P));
         pragma
           Assert
             (for all P in 1 .. N =>
                (for all Q in P .. N => Ordered (Code, Inv (P), Inv (Q))));
      end;
      Dense_Ranks (SA, Code, Zero, R, Classes);
      for A in 1 .. N loop
         for B in 1 .. N loop
            Initial_Pair (S, A, B);
            pragma
              Loop_Invariant
                (for all C in 1 .. B =>
                   (R (A) <= R (C)) = LE (S, Rot (N, A), Rot (N, C), 1)
                   and then (R (A) = R (C))
                            = Equal_Prefix (S, Rot (N, A), Rot (N, C), 1));
         end loop;
         pragma
           Loop_Invariant
             (for all C in 1 .. A =>
                (for all D in 1 .. N =>
                   (R (C) <= R (D)) = LE (S, Rot (N, C), Rot (N, D), 1)
                   and then (R (C) = R (D))
                            = Equal_Prefix (S, Rot (N, C), Rot (N, D), 1)));
      end loop;
   end Initial;

   --  Comparing 2 * H letters compares H, then H more from H letters on.
   procedure Double_Pair (S : String; R : Keys; H : Positive; A, B : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then H < S'Length
       and then Ranked (S, R, H)
       and then A in 1 .. S'Length
       and then B in 1 .. S'Length,
     Post =>
       (R (A) < R (B)
        or else (R (A) = R (B)
                 and then R (Next (S'Length, A, H))
                          <= R (Next (S'Length, B, H))))
       = LE (S, Rot (S'Length, A), Rot (S'Length, B), 2 * H)
       and then (R (A) = R (B)
                 and then R (Next (S'Length, A, H))
                          = R (Next (S'Length, B, H)))
                = Equal_Prefix
                    (S, Rot (S'Length, A), Rot (S'Length, B), 2 * H);

   procedure Double_Pair (S : String; R : Keys; H : Positive; A, B : Positive)
   is
      N  : constant Positive := S'Length;
      RA : constant Rotation := Rot (N, A);
      RB : constant Rotation := Rot (N, B);
   begin
      Order_Split (S, RA, RB, H, H);
      pragma Assert (Advance (RA, H) = Rot (N, Next (N, A, H)));
      pragma Assert (Advance (RB, H) = Rot (N, Next (N, B, H)));
      Order_Laws (S, RA, RB, RA, H);
   end Double_Pair;

   procedure Doubled (S : String; R, K2, New_R : Keys; H : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then H < S'Length
       and then Ranked (S, R, H)
       and then K2'First = 1
       and then K2'Length = S'Length
       and then (for all A in 1 .. S'Length =>
                   K2 (A) = R (Next (S'Length, A, H)))
       and then New_R'First = 1
       and then New_R'Length = S'Length
       and then (for all X of New_R => X < S'Length)
       and then (for all A in New_R'Range =>
                   (for all B in New_R'Range =>
                      (New_R (A) <= New_R (B)) = Pair_LE (R, K2, A, B))),
     Post => Ranked (S, New_R, 2 * H);

   procedure Doubled (S : String; R, K2, New_R : Keys; H : Positive) is
      N : constant Positive := S'Length;
   begin
      for A in 1 .. N loop
         for B in 1 .. N loop
            Double_Pair (S, R, H, A, B);
            pragma Assert ((New_R (A) <= New_R (B)) = Pair_LE (R, K2, A, B));
            pragma Assert ((New_R (B) <= New_R (A)) = Pair_LE (R, K2, B, A));
            pragma
              Loop_Invariant
                (for all C in 1 .. B =>
                   (New_R (A) <= New_R (C))
                   = LE (S, Rot (N, A), Rot (N, C), 2 * H)
                   and then (New_R (A) = New_R (C))
                            = Equal_Prefix (S, Rot (N, A), Rot (N, C), 2 * H));
         end loop;
         pragma
           Loop_Invariant
             (for all C in 1 .. A =>
                (for all D in 1 .. N =>
                   (New_R (C) <= New_R (D))
                   = LE (S, Rot (N, C), Rot (N, D), 2 * H)
                   and then (New_R (C) = New_R (D))
                            = Equal_Prefix
                                (S, Rot (N, C), Rot (N, D), 2 * H)));
      end loop;
   end Doubled;

   --  One round: ranks by the first 2 * H letters, from ranks by H.
   procedure Double
     (S       : String;
      R       : in out Keys;
      SA      : in out Mapping;
      H       : Positive;
      Classes : out Positive)
   with
     Pre  =>
       Supported (S)
       and then H < S'Length
       and then Ranked (S, R, H)
       and then SA'First = 1
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then Sorted_By (R, SA),
     Post =>
       Ranked (S, R, 2 * H)
       and then Permutation (SA)
       and then Sorted_By (R, SA)
       and then Classes <= S'Length
       and then (if Classes = S'Length then Distinct_Keys (R));

   procedure Double
     (S       : String;
      R       : in out Keys;
      SA      : in out Mapping;
      H       : Positive;
      Classes : out Positive)
   is
      N      : constant Positive := S'Length;
      --  The previous order, each position moved H letters back: sorted by
      --  the rank H letters on, which is the second key of a pair.
      T      : Mapping (1 .. N) := (others => 1);
      --  The first key, in the order of T.
      First  : Keys (1 .. N) := (others => 0);
      --  The second key, by position.
      Second : Keys (1 .. N) := (others => 0);
      New_R  : Keys (1 .. N);
   begin
      for K in 1 .. N loop
         T (K) := Back (N, SA (K), H);
         First (K) := R (T (K));
         Second (K) := R (Next (N, K, H));
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                T (J) = Back (N, SA (J), H)
                and then First (J) = R (T (J))
                and then Second (J) = R (Next (N, J, H)));
      end loop;
      pragma Assert (for all K in 1 .. N => Next (N, T (K), H) = SA (K));
      pragma
        Assert
          (for all I in 1 .. N =>
             (for all J in 1 .. N => (if I /= J then T (I) /= T (J))));
      pragma Assert (for all K in 1 .. N => Second (T (K)) = R (SA (K)));
      declare
         Map : constant Mapping := Place (First, N);
         Inv : constant Mapping := Permutations.Inverse (Map)
         with Ghost;
      begin
         --  Equal first keys keep the order of T, and so of second keys.
         pragma
           Assert
             (for all K in 1 .. N =>
                (for all L in 1 .. N =>
                   (if Map (K) <= Map (L)
                    then Pair_LE (R, Second, T (K), T (L)))));
         Scatter (Map, T, SA);
         pragma Assert (for all P in 1 .. N => SA (P) = T (Inv (P)));
         pragma
           Assert
             (for all P in 1 .. N =>
                (for all Q in P .. N => Map (Inv (P)) <= Map (Inv (Q))));
         pragma
           Assert
             (for all P in 1 .. N =>
                (for all Q in P .. N => Pair_LE (R, Second, SA (P), SA (Q))));
      end;
      Dense_Ranks (SA, R, Second, New_R, Classes);
      Doubled (S, R, Second, New_R, H);
      R := New_R;
   end Double;

   --  Once H covers a period, or no two ranks are equal, H letters decide
   --  the order of every horizon up to 2 * N.
   procedure Settle (S : String; R : Keys; H : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then H <= 2 * S'Length
       and then Ranked (S, R, H)
       and then (H >= S'Length or else Distinct_Keys (R)),
     Post => Ranked (S, R, 2 * S'Length);

   procedure Settle (S : String; R : Keys; H : Positive) is
      N : constant Positive := S'Length;
   begin
      for A in 1 .. N loop
         for B in 1 .. N loop
            if A = B then
               Equal_Same (S, Rot (N, A), Rot (N, B), 2 * N);
               Order_Laws (S, Rot (N, A), Rot (N, B), Rot (N, A), 2 * N);
            else
               Settled (S, Rot (N, A), Rot (N, B), H, 2 * N);
            end if;
            pragma
              Loop_Invariant
                (for all C in 1 .. B =>
                   (R (A) <= R (C)) = LE (S, Rot (N, A), Rot (N, C), 2 * N)
                   and then (R (A) = R (C))
                            = Equal_Prefix (S, Rot (N, A), Rot (N, C), 2 * N));
         end loop;
         pragma
           Loop_Invariant
             (for all C in 1 .. A =>
                (for all D in 1 .. N =>
                   (R (C) <= R (D)) = LE (S, Rot (N, C), Rot (N, D), 2 * N)
                   and then (R (C) = R (D))
                            = Equal_Prefix
                                (S, Rot (N, C), Rot (N, D), 2 * N)));
      end loop;
   end Settle;

   --  The table read off final ranks: rows by rank, equal ranks by position.
   procedure Lay_Out (S : String; R : Keys; Rows : out Table)
   with
     Pre  =>
       Supported (S)
       and then S'Length > 0
       and then Ranked (S, R, 2 * S'Length)
       and then Rows'First = 1
       and then Rows'Length = S'Length,
     Post =>
       Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, Rotations_Of (S))
       and then Sorted (S, Rows, Earlier_First)
       and then (for all Row of Rows =>
                   Row.First = 1 and then Row.Length = S'Length)
       and then (for some J in Rows'Range => Rows (J).Offset = 0);

   procedure Lay_Out (S : String; R : Keys; Rows : out Table) is
      N    : constant Positive := S'Length;
      Map  : constant Mapping := Place (R, N);
      Inv  : constant Mapping := Permutations.Inverse (Map)
      with Ghost;
      Rots : constant Table := Rotations_Of (S)
      with Ghost;
   begin
      Rows := (others => (1, 1, 0));
      for A in 1 .. N loop
         Rows (Map (A)) := Rot (N, A);
         pragma
           Loop_Invariant (for all J in 1 .. A => Rows (Map (J)) = Rot (N, J));
      end loop;
      pragma Assert (for all I in 1 .. N => Rows (I) = Rot (N, Inv (I)));
      pragma Assert (for all I in 1 .. N => Rots (I) = Rot (N, I));
      pragma Assert (for all I in 1 .. N => Rows (I) = Rots (Inv (I)));
      pragma Assert (for all I in 1 .. N => Rots (I) = Rows (Map (I)));
      pragma Assert (Same_Rows (Rows, Rots));
      pragma Assert (Distinct (Rows));
      pragma Assert (Rows (Map (1)).Offset = 0);
      for I in 1 .. N loop
         for J in I .. N loop
            pragma Assert (Ordered (R, Inv (I), Inv (J)));
            Key_Intro (S, Rows (I), Rows (J), Earlier_First);
            pragma
              Loop_Invariant
                (for all L in I .. J =>
                   Key_LE (S, Rows (I), Rows (L), Earlier_First));
         end loop;
         pragma
           Loop_Invariant
             (for all K in 1 .. I =>
                (for all L in K .. N =>
                   Key_LE (S, Rows (K), Rows (L), Earlier_First)));
      end loop;
   end Lay_Out;

   function Classical_Table (S : String) return Table is
      N    : constant Natural := S'Length;
      Rows : Table (1 .. N) := (others => (1, 1, 0));
   begin
      if N = 0 then
         return Rows;
      end if;
      declare
         R       : Keys (1 .. N);
         SA      : Mapping (1 .. N);
         Classes : Positive;
         H       : Positive := 1;
      begin
         Initial (S, R, SA, Classes);
         while H < N and then Classes < N loop
            pragma Loop_Invariant (H < 2 * N);
            pragma Loop_Invariant (Ranked (S, R, H));
            pragma Loop_Invariant (Permutation (SA));
            pragma Loop_Invariant (Sorted_By (R, SA));
            pragma Loop_Invariant (Classes <= N);
            pragma Loop_Invariant (if Classes = N then Distinct_Keys (R));
            pragma Loop_Variant (Increases => H);
            Double (S, R, SA, H, Classes);
            H := 2 * H;
         end loop;
         pragma Assert (H >= N or else Distinct_Keys (R));
         Settle (S, R, H);
         Lay_Out (S, R, Rows);
      end;
      return Rows;
   end Classical_Table;
end BWT.Doubling;
