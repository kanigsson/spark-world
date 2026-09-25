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

   --  X mod L, without a division while X < 2 * L. Rounds call it for every
   --  position, and that is nearly always the case.
   function Reduce (X : Natural; L : Positive) return Natural
   is (if X < L then X elsif X - L < L then X - L else X mod L)
   with Post => Reduce'Result = X mod L;

   --  The position D letters on from P, within P's factor, and the one D
   --  letters back.
   function Jump
     (S : String; F : Table; P : Positive; D : Natural) return Positive
   is (F (P).First + Reduce (F (P).Offset + D, F (P).Length))
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then P in F'Range
       and then D <= 4 * Max_Length,
     Post => Jump'Result in F'Range and then F (Jump'Result) = Skip (F (P), D);

   function Back
     (S : String; F : Table; P : Positive; D : Natural) return Positive
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then P in F'Range
       and then D <= 4 * Max_Length,
     Post => Back'Result in F'Range and then Jump (S, F, Back'Result, D) = P;

   function Back
     (S : String; F : Table; P : Positive; D : Natural) return Positive is
   begin
      Skip_Unskip (F (P), D);
      return
        F (P).First
        + Reduce
            (F (P).Offset + (F (P).Length - Reduce (D, F (P).Length)),
             F (P).Length);
   end Back;

   --  Ranks order positions as the first H letters of their rows do.
   function Ranked
     (S : String; F : Table; R : Keys; H : Natural) return Boolean
   is (R'First = 1
       and then R'Length = S'Length
       and then (for all X of R => X < S'Length)
       and then (for all A in R'Range =>
                   (for all B in R'Range =>
                      (R (A) <= R (B)) = LE (S, F (A), F (B), H)
                      and then (R (A) = R (B))
                               = Equal_Prefix (S, F (A), F (B), H))))
   with
     Ghost,
     Pre => Supported (S) and then Cycles (S, F) and then H <= 4 * Max_Length;

   --  Rows that agree on H letters still agree on H letters after H more.
   --  Agreement on H letters then extends to every horizon.
   function Closed (S : String; F : Table; H : Natural) return Boolean
   is (for all A in F'Range =>
         (for all B in F'Range =>
            (if Equal_Prefix (S, F (A), F (B), H)
             then
               Equal_Prefix
                 (S, F (Jump (S, F, A, H)), F (Jump (S, F, B, H)), H))))
   with
     Ghost,
     Pre => Supported (S) and then Cycles (S, F) and then H <= 4 * Max_Length;

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

   --  Numbers the classes of equal pairs along SA, from 0. Split tells
   --  whether some class of first keys has more than one second key.
   procedure Dense_Ranks
     (SA      : Mapping;
      K1, K2  : Keys;
      R       : out Keys;
      Classes : out Positive;
      Split   : out Boolean)
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
       and then Sorted_By (R, SA)
       and then (if not Split
                 then
                   (for all A in K1'Range =>
                      (for all B in K1'Range =>
                         (if K1 (A) = K1 (B) then K2 (A) = K2 (B)))));

   procedure Dense_Ranks
     (SA      : Mapping;
      K1, K2  : Keys;
      R       : out Keys;
      Classes : out Positive;
      Split   : out Boolean)
   is
      Inv : constant Mapping := Permutations.Inverse (SA)
      with Ghost;
   begin
      R := (others => 0);
      Classes := 1;
      Split := False;
      for I in 2 .. SA'Last loop
         if K1 (SA (I)) /= K1 (SA (I - 1))
           or else K2 (SA (I)) /= K2 (SA (I - 1))
         then
            if K1 (SA (I)) = K1 (SA (I - 1)) then
               Split := True;
            end if;
            Classes := Classes + 1;
         end if;
         R (SA (I)) := Classes - 1;
         pragma
           Loop_Invariant
             (if not Split
                then
                  (for all P in 1 .. I =>
                     (for all Q in 1 .. I =>
                        (if K1 (SA (P)) = K1 (SA (Q))
                         then K2 (SA (P)) = K2 (SA (Q))))));
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
      if not Split then
         pragma
           Assert
             (for all A in K1'Range =>
                (for all B in K1'Range =>
                   (if K1 (SA (Inv (A))) = K1 (SA (Inv (B)))
                    then K2 (SA (Inv (A))) = K2 (SA (Inv (B))))));
         for A in K1'Range loop
            for B in K1'Range loop
               pragma Assert (SA (Inv (A)) = A and then SA (Inv (B)) = B);
               pragma
                 Loop_Invariant
                   (for all C in K1'First .. B =>
                      (if K1 (A) = K1 (C) then K2 (A) = K2 (C)));
            end loop;
            pragma
              Loop_Invariant
                (for all D in K1'First .. A =>
                   (for all C in K1'Range =>
                      (if K1 (D) = K1 (C) then K2 (D) = K2 (C))));
         end loop;
      end if;
   end Dense_Ranks;

   --  One letter decides the first round.
   procedure Initial_Pair (S : String; F : Table; A, B : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then A in 1 .. S'Length
       and then B in 1 .. S'Length,
     Post =>
       LE (S, F (A), F (B), 1) = (S (A) <= S (B))
       and then Equal_Prefix (S, F (A), F (B), 1) = (S (A) = S (B));

   procedure Initial_Pair (S : String; F : Table; A, B : Positive) is
   begin
      Letter_Direct (S, F (A), 0);
      Letter_Direct (S, F (B), 0);
   end Initial_Pair;

   procedure Initial
     (S       : String;
      F       : Table;
      R       : out Keys;
      SA      : out Mapping;
      Classes : out Positive)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then R'First = 1
       and then R'Length = S'Length
       and then SA'First = 1
       and then SA'Length = S'Length,
     Post =>
       Ranked (S, F, R, 1)
       and then Permutation (SA)
       and then Sorted_By (R, SA)
       and then Classes <= S'Length
       and then (if Classes = S'Length then Distinct_Keys (R));

   procedure Initial
     (S       : String;
      F       : Table;
      R       : out Keys;
      SA      : out Mapping;
      Classes : out Positive)
   is
      N     : constant Positive := S'Length;
      Code  : Keys (1 .. N) := (others => 0);
      Zero  : constant Keys (1 .. N) := (others => 0);
      Ident : Mapping (1 .. N) := (others => 1);
      Split : Boolean;
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
      Dense_Ranks (SA, Code, Zero, R, Classes, Split);
      pragma Unreferenced (Split);
      for A in 1 .. N loop
         for B in 1 .. N loop
            Initial_Pair (S, F, A, B);
            pragma
              Loop_Invariant
                (for all C in 1 .. B =>
                   (R (A) <= R (C)) = LE (S, F (A), F (C), 1)
                   and then (R (A) = R (C))
                            = Equal_Prefix (S, F (A), F (C), 1));
         end loop;
         pragma
           Loop_Invariant
             (for all C in 1 .. A =>
                (for all D in 1 .. N =>
                   (R (C) <= R (D)) = LE (S, F (C), F (D), 1)
                   and then (R (C) = R (D))
                            = Equal_Prefix (S, F (C), F (D), 1)));
      end loop;
   end Initial;

   --  Comparing 2 * H letters compares H, then H more from H letters on.
   procedure Double_Pair
     (S : String; F : Table; R : Keys; H : Positive; A, B : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then H <= 2 * Max_Length
       and then Ranked (S, F, R, H)
       and then A in 1 .. S'Length
       and then B in 1 .. S'Length,
     Post =>
       (R (A) < R (B)
        or else (R (A) = R (B)
                 and then R (Jump (S, F, A, H)) <= R (Jump (S, F, B, H))))
       = LE (S, F (A), F (B), 2 * H)
       and then (R (A) = R (B)
                 and then R (Jump (S, F, A, H)) = R (Jump (S, F, B, H)))
                = Equal_Prefix (S, F (A), F (B), 2 * H);

   procedure Double_Pair
     (S : String; F : Table; R : Keys; H : Positive; A, B : Positive) is
   begin
      Skip_Split (S, F (A), F (B), H, H);
      Order_Laws (S, F (A), F (B), F (A), H);
   end Double_Pair;

   procedure Doubled (S : String; F : Table; R, K2, New_R : Keys; H : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
       and then Ranked (S, F, R, H)
       and then K2'First = 1
       and then K2'Length = S'Length
       and then (for all A in 1 .. S'Length => K2 (A) = R (Jump (S, F, A, H)))
       and then New_R'First = 1
       and then New_R'Length = S'Length
       and then (for all X of New_R => X < S'Length)
       and then (for all A in New_R'Range =>
                   (for all B in New_R'Range =>
                      (New_R (A) <= New_R (B)) = Pair_LE (R, K2, A, B))),
     Post => Ranked (S, F, New_R, 2 * H);

   procedure Doubled (S : String; F : Table; R, K2, New_R : Keys; H : Positive)
   is
      N : constant Positive := S'Length;
   begin
      for A in 1 .. N loop
         for B in 1 .. N loop
            Double_Pair (S, F, R, H, A, B);
            pragma Assert ((New_R (A) <= New_R (B)) = Pair_LE (R, K2, A, B));
            pragma Assert ((New_R (B) <= New_R (A)) = Pair_LE (R, K2, B, A));
            pragma
              Loop_Invariant
                (for all C in 1 .. B =>
                   (New_R (A) <= New_R (C)) = LE (S, F (A), F (C), 2 * H)
                   and then (New_R (A) = New_R (C))
                            = Equal_Prefix (S, F (A), F (C), 2 * H));
         end loop;
         pragma
           Loop_Invariant
             (for all C in 1 .. A =>
                (for all D in 1 .. N =>
                   (New_R (C) <= New_R (D)) = LE (S, F (C), F (D), 2 * H)
                   and then (New_R (C) = New_R (D))
                            = Equal_Prefix (S, F (C), F (D), 2 * H)));
      end loop;
   end Doubled;

   --  One round: ranks by the first 2 * H letters, from ranks by H. When no
   --  class splits, the ranks are final (Closed).
   procedure Double
     (S       : String;
      F       : Table;
      R       : in out Keys;
      SA      : in out Mapping;
      H       : Positive;
      Classes : out Positive;
      Split   : out Boolean)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
       and then Ranked (S, F, R, H)
       and then SA'First = 1
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then Sorted_By (R, SA),
     Post =>
       Ranked (S, F, R, 2 * H)
       and then Permutation (SA)
       and then Sorted_By (R, SA)
       and then Classes <= S'Length
       and then (if Classes = S'Length then Distinct_Keys (R))
       and then (if not Split then Closed (S, F, H));

   procedure Double
     (S       : String;
      F       : Table;
      R       : in out Keys;
      SA      : in out Mapping;
      H       : Positive;
      Classes : out Positive;
      Split   : out Boolean)
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
         T (K) := Back (S, F, SA (K), H);
         First (K) := R (T (K));
         Second (K) := R (Jump (S, F, K, H));
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                T (J) = Back (S, F, SA (J), H)
                and then First (J) = R (T (J))
                and then Second (J) = R (Jump (S, F, J, H)));
      end loop;
      pragma Assert (for all K in 1 .. N => Jump (S, F, T (K), H) = SA (K));
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
      Dense_Ranks (SA, R, Second, New_R, Classes, Split);
      Doubled (S, F, R, Second, New_R, H);
      if not Split then
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (if R (A) = R (B)
                    then R (Jump (S, F, A, H)) = R (Jump (S, F, B, H)))));
         pragma Assert (Closed (S, F, H));
      end if;
      R := New_R;
   end Double;

   --  Under Closed, rows that agree on H letters agree on any number.
   procedure Closed_Extend
     (S : String; F : Table; H : Positive; A, B : Positive; Size : Natural)
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Cycles (S, F)
       and then H <= 4 * Max_Length
       and then Size <= 4 * Max_Length
       and then Closed (S, F, H)
       and then A in F'Range
       and then B in F'Range
       and then Equal_Prefix (S, F (A), F (B), H),
     Post               => Equal_Prefix (S, F (A), F (B), Size),
     Subprogram_Variant => (Decreases => Size);

   procedure Closed_Extend
     (S : String; F : Table; H : Positive; A, B : Positive; Size : Natural) is
   begin
      if Size <= H then
         Equal_Prefix_Shorter (S, F (A), F (B), H, Size);
      else
         Closed_Extend
           (S, F, H, Jump (S, F, A, H), Jump (S, F, B, H), Size - H);
         Skip_Split (S, F (A), F (B), H, Size - H);
      end if;
   end Closed_Extend;

   --  Once H covers two periods, or no two ranks are equal, or the ranks
   --  stopped splitting at G letters, H letters decide the order of the full
   --  horizon.
   procedure Settle (S : String; F : Table; R : Keys; G, H, Longest : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then Longest <= Max_Length
       and then H <= 4 * Max_Length
       and then (for all P in F'Range => F (P).Length <= Longest)
       and then Ranked (S, F, R, H)
       and then G <= H
       and then (H >= 2 * Longest
                 or else Distinct_Keys (R)
                 or else Closed (S, F, G)),
     Post => Ranked (S, F, R, 2 * S'Length);

   procedure Settle (S : String; F : Table; R : Keys; G, H, Longest : Positive)
   is
      N : constant Positive := S'Length;
   begin
      for A in 1 .. N loop
         for B in 1 .. N loop
            if A = B then
               Equal_Same (S, F (A), F (B), 2 * N);
               Order_Laws (S, F (A), F (B), F (A), 2 * N);
            elsif H >= 2 * Longest
              or else not Equal_Prefix (S, F (A), F (B), H)
            then
               Settled (S, F (A), F (B), H, 2 * N);
            else
               Equal_Prefix_Shorter (S, F (A), F (B), H, G);
               Closed_Extend (S, F, G, A, B, 2 * N);
               Order_Laws (S, F (A), F (B), F (A), 2 * N);
            end if;
            pragma
              Loop_Invariant
                (for all C in 1 .. B =>
                   (R (A) <= R (C)) = LE (S, F (A), F (C), 2 * N)
                   and then (R (A) = R (C))
                            = Equal_Prefix (S, F (A), F (C), 2 * N));
         end loop;
         pragma
           Loop_Invariant
             (for all C in 1 .. A =>
                (for all D in 1 .. N =>
                   (R (C) <= R (D)) = LE (S, F (C), F (D), 2 * N)
                   and then (R (C) = R (D))
                            = Equal_Prefix (S, F (C), F (D), 2 * N)));
      end loop;
   end Settle;

   --  Where position K goes in the final pass: equal ranks keep position
   --  order, or reverse it.
   function Tie_Position (N, K : Positive; Ties : Tie_Order) return Positive
   is (case Ties is
         when Earlier_First => K,
         when Later_First   => N + 1 - K)
   with
     Pre  => K <= N and then N <= Max_Length,
     Post => Tie_Position'Result <= N;

   --  The table read off final ranks, equal ranks in tie order.
   procedure Lay_Out
     (S : String; F : Table; R : Keys; Ties : Tie_Order; Rows : out Table)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then Ranked (S, F, R, 2 * S'Length)
       and then Rows'First = 1
       and then Rows'Length = S'Length,
     Post =>
       Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, F)
       and then Sorted (S, Rows, Ties);

   procedure Lay_Out
     (S : String; F : Table; R : Keys; Ties : Tie_Order; Rows : out Table)
   is
      N   : constant Positive := S'Length;
      Key : Keys (1 .. N) := (others => 0);
   begin
      for K in 1 .. N loop
         Key (K) := R (Tie_Position (N, K, Ties));
         pragma
           Loop_Invariant
             (for all J in 1 .. K => Key (J) = R (Tie_Position (N, J, Ties)));
      end loop;
      declare
         Map : constant Mapping := Place (Key, N);
         Inv : constant Mapping := Permutations.Inverse (Map)
         with Ghost;
      begin
         Rows := (others => (1, 1, 0));
         for K in 1 .. N loop
            Rows (Map (K)) := F (Tie_Position (N, K, Ties));
            pragma
              Loop_Invariant
                (for all J in 1 .. K =>
                   Rows (Map (J)) = F (Tie_Position (N, J, Ties)));
         end loop;
         pragma
           Assert
             (for all I in 1 .. N =>
                Rows (I) = F (Tie_Position (N, Inv (I), Ties)));
         pragma
           Assert
             (for all P in 1 .. N =>
                F (P) = Rows (Map (Tie_Position (N, P, Ties))));
         pragma Assert (Same_Rows (Rows, F));
         pragma
           Assert
             (for all I in 1 .. N =>
                Rows (I).First + Rows (I).Offset
                = Tie_Position (N, Inv (I), Ties));
         pragma Assert (Distinct (Rows));
         for I in 1 .. N loop
            for J in I .. N loop
               pragma Assert (Ordered (Key, Inv (I), Inv (J)));
               Key_Intro (S, Rows (I), Rows (J), Ties);
               pragma
                 Loop_Invariant
                   (for all L in I .. J =>
                      Key_LE (S, Rows (I), Rows (L), Ties));
            end loop;
            pragma
              Loop_Invariant
                (for all K in 1 .. I =>
                   (for all L in K .. N =>
                      Key_LE (S, Rows (K), Rows (L), Ties)));
         end loop;
      end;
   end Lay_Out;

   function Sorted_Rows
     (S : String; Factors : Table; Ties : Tie_Order) return Table
   is
      N    : constant Natural := S'Length;
      Rows : Table (1 .. N);
   begin
      if N = 0 then
         return Factors;
      end if;
      declare
         R       : Keys (1 .. N);
         SA      : Mapping (1 .. N);
         Classes : Positive;
         H       : Positive := 1;
         Longest : Positive := 1;
         Split   : Boolean := True;
         --  The horizon of the last round, at which Closed holds once a
         --  round splits nothing.
         Last_H  : Positive := 1
         with Ghost;
      begin
         for P in 1 .. N loop
            Longest := Positive'Max (Longest, Factors (P).Length);
            pragma Loop_Invariant (Longest <= N);
            pragma
              Loop_Invariant
                (for all Q in 1 .. P => Factors (Q).Length <= Longest);
         end loop;
         Initial (S, Factors, R, SA, Classes);
         while H < 2 * Longest and then Classes < N and then Split loop
            pragma Loop_Invariant (H < 2 * Longest);
            pragma Loop_Invariant (Last_H <= H);
            pragma Loop_Invariant (Ranked (S, Factors, R, H));
            pragma Loop_Invariant (Permutation (SA));
            pragma Loop_Invariant (Sorted_By (R, SA));
            pragma Loop_Invariant (Classes <= N);
            pragma Loop_Variant (Increases => H);
            Double (S, Factors, R, SA, H, Classes, Split);
            Last_H := H;
            H := 2 * H;
         end loop;
         pragma Assert (H < 4 * Longest);
         pragma
           Assert
             (H >= 2 * Longest
                or else Distinct_Keys (R)
                or else Closed (S, Factors, Last_H));
         Settle (S, Factors, R, Last_H, H, Longest);
         Lay_Out (S, Factors, R, Ties, Rows);
      end;
      return Rows;
   end Sorted_Rows;
end BWT.Doubling;
