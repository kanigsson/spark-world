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
     Post =>
       Back'Result in F'Range
       and then Jump (S, F, Back'Result, D) = P
       and then Back'Result
                = F (P).First
                  + Reduce
                      (F (P).Offset
                       + (F (P).Length - Reduce (D, F (P).Length)),
                       F (P).Length);

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

   --  The classes of an ordered sequence of ranks, as runs: ranks never
   --  decrease along V, and each rank is the index just before its run, so
   --  the run of rank C starts at C + 1.
   function Runs (V : Keys) return Boolean
   is (V'First = 1
       and then V'Length <= Max_Length
       and then (for all P in V'Range =>
                   V (P) < P and then V (V (P) + 1) = V (P))
       and then (for all P in V'Range =>
                   (for all Q in P .. V'Last => V (P) <= V (Q))))
   with Ghost;

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
   procedure Scatter (Map, Items : Mapping; Result : in out Mapping)
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

   procedure Scatter (Map, Items : Mapping; Result : in out Mapping) is
      Inv : constant Mapping := Permutations.Inverse (Map)
      with Ghost;
   begin
      for K in Map'Range loop
         Result (Map (K)) := Items (K);
         pragma
           Loop_Invariant
             (for all J in 1 .. K => Result (Map (J)) = Items (J));
      end loop;
      pragma
        Assert (for all I in Result'Range => Result (I) = Items (Inv (I)));
   end Scatter;

   --  R (SA (P)) := V (P), for all P: ranks in the order of SA, spread back
   --  to positions.
   procedure Spread (SA : Mapping; V : Keys; R : in out Keys)
   with
     Pre  =>
       Permutation (SA)
       and then V'First = 1
       and then V'Length = SA'Length
       and then R'First = 1
       and then R'Length = SA'Length,
     Post => (for all P in SA'Range => R (SA (P)) = V (P));

   procedure Spread (SA : Mapping; V : Keys; R : in out Keys) is
   begin
      for I in SA'Range loop
         R (SA (I)) := V (I);
         pragma Loop_Invariant (for all P in 1 .. I => R (SA (P)) = V (P));
      end loop;
   end Spread;

   --  Result (I) := Items (Map (I)), for all I.
   procedure Gather (Items : Keys; Map : Mapping; Result : out Keys)
   with
     Relaxed_Initialization => Result,
     Pre                    =>
       Map'First = 1
       and then Result'First = 1
       and then Result'Length = Map'Length
       and then (for all X of Map => X in Items'Range),
     Post                   =>
       Result'Initialized
       and then (for all I in Map'Range => Result (I) = Items (Map (I)));

   procedure Gather (Items : Keys; Map : Mapping; Result : out Keys) is
   begin
      for I in Map'Range loop
         Result (I) := Items (Map (I));
         pragma
           Loop_Invariant
             (for all J in 1 .. I =>
                Result (J)'Initialized and then Result (J) = Items (Map (J)));
      end loop;
   end Gather;

   --  Rows that agree on H letters agree on H more when their ranks H
   --  letters on agree too.
   procedure Closed_Intro (S : String; F : Table; R : Keys; H : Positive)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then H <= 2 * Max_Length
       and then Ranked (S, F, R, H)
       and then (for all A in 1 .. S'Length =>
                   (for all B in 1 .. S'Length =>
                      (if R (A) = R (B)
                       then R (Jump (S, F, A, H)) = R (Jump (S, F, B, H))))),
     Post => Closed (S, F, H);

   procedure Closed_Intro (S : String; F : Table; R : Keys; H : Positive)
   is null;

   --  No map of Size + 1 places into Size places is one to one: its first
   --  Size places already take every value.
   procedure No_Injection (M : Mapping; Size : Natural)
   with
     Ghost,
     Pre  =>
       M'First = 1
       and then Size <= Max_Length
       and then M'Length = Size + 1
       and then (for all X of M => X <= Size)
       and then (for all I in M'Range =>
                   (for all J in M'Range => (if I /= J then M (I) /= M (J)))),
     Post => False;

   procedure No_Injection (M : Mapping; Size : Natural) is
   begin
      if Size = 0 then
         pragma Assert (M (1) <= 0);
         return;
      end if;
      declare
         Head : constant Mapping (1 .. Size) := M (1 .. Size);
         Inv  : constant Mapping := Permutations.Inverse (Head);
      begin
         pragma Assert (Head (Inv (M (Size + 1))) = M (Size + 1));
         pragma Assert (Inv (M (Size + 1)) /= Size + 1);
      end;
   end No_Injection;

   --  The next free place of a class is still inside its run. Otherwise the
   --  run is full, and its elements and the one to place are more elements
   --  of that class than the run has places.
   procedure Next_Free
     (SA, Inv    : Mapping;
      V          : Keys;
      T          : Mapping;
      First      : Keys;
      Cur, Owner : Keys;
      K          : Positive)
   with
     Ghost,
     Pre  =>
       Permutation (SA)
       and then Inv'First = 1
       and then Inv'Length = SA'Length
       and then (for all X of Inv => X in SA'Range)
       and then (for all P in SA'Range => SA (Inv (P)) = P)
       and then (for all P in SA'Range => Inv (SA (P)) = P)
       and then V'First = 1
       and then V'Length = SA'Length
       and then Runs (V)
       and then T'First = 1
       and then T'Length = SA'Length
       and then (for all X of T => X in SA'Range)
       and then (for all I in T'Range =>
                   (for all J in T'Range => (if I /= J then T (I) /= T (J))))
       and then First'First = 1
       and then First'Length = SA'Length
       and then (for all J in T'Range => First (J) = V (Inv (T (J))))
       and then Cur'First = 1
       and then Cur'Length = SA'Length
       and then Owner'First = 1
       and then Owner'Length = SA'Length
       and then K in T'Range
       and then (for all P in SA'Range =>
                   Owner (P) < K
                   and then (Owner (P) /= 0) = (P < Cur (V (P) + 1))
                   and then (if Owner (P) /= 0 then First (Owner (P)) = V (P)))
       and then (for all P in SA'Range =>
                   (for all Q in SA'Range =>
                      (if P /= Q and then Owner (P) /= 0
                       then Owner (P) /= Owner (Q))))
       and then (for all P in SA'Range =>
                   V (P) < Cur (V (P) + 1)
                   and then Cur (V (P) + 1) <= SA'Length + 1
                   and then (Cur (V (P) + 1) = V (P) + 1
                             or else V (Cur (V (P) + 1) - 1) = V (P))),
     Post =>
       Cur (First (K) + 1) <= SA'Length
       and then V (Cur (First (K) + 1)) = First (K);

   procedure Next_Free
     (SA, Inv    : Mapping;
      V          : Keys;
      T          : Mapping;
      First      : Keys;
      Cur, Owner : Keys;
      K          : Positive)
   is
      C  : constant Natural := First (K);
      P0 : constant Positive := Inv (T (K));
   begin
      pragma Assert (V (P0) = C);
      pragma Assert (V (C + 1) = C);
      if Cur (C + 1) <= SA'Length and then V (Cur (C + 1)) = C then
         return;
      end if;
      declare
         D    : constant Positive := Cur (C + 1);
         Size : constant Natural := D - 1 - C;
         M    : Mapping (1 .. Size + 1) := (others => 1);
      begin
         pragma Assert (D > C + 1 and then V (D - 1) = C);
         pragma Assert (Size <= SA'Length);
         pragma
           Assert
             (for all Q in SA'Range =>
                (if V (Q) = C then Q in C + 1 .. D - 1));
         pragma Assert (for all Q in C + 1 .. D - 1 => V (Q) = C);
         pragma Assert (for all Q in C + 1 .. D - 1 => Owner (Q) /= 0);
         for I in 1 .. Size loop
            pragma Assert (First (Owner (C + I)) = C);
            M (I) := Inv (T (Owner (C + I))) - C;
            pragma
              Loop_Invariant
                (for all J in 1 .. I =>
                   M (J) = Inv (T (Owner (C + J))) - C
                   and then M (J) in 1 .. Size);
         end loop;
         M (Size + 1) := P0 - C;
         pragma
           Assert
             (for all I in 1 .. Size =>
                (for all J in 1 .. Size =>
                   (if I /= J then Owner (C + I) /= Owner (C + J))));
         pragma Assert (for all I in 1 .. Size => Owner (C + I) /= K);
         No_Injection (M, Size);
      end;
   end Next_Free;

   --  Where each element of T goes when T is sorted stably by class: the
   --  next free place in its class's run. The run of class C starts at
   --  C + 1, so no counting pass is needed.
   procedure Slots
     (SA : Mapping; V : Keys; T : Mapping; First : Keys; Dest : out Mapping)
   with
     Relaxed_Initialization => Dest,
     Pre                    =>
       Permutation (SA)
       and then SA'Length >= 1
       and then V'First = 1
       and then V'Length = SA'Length
       and then Runs (V)
       and then T'First = 1
       and then T'Length = SA'Length
       and then (for all X of T => X in SA'Range)
       and then (for all I in T'Range =>
                   (for all J in T'Range => (if I /= J then T (I) /= T (J))))
       and then First'First = 1
       and then First'Length = SA'Length
       and then (for all J in T'Range =>
                   (for all P in SA'Range =>
                      (if SA (P) = T (J) then V (P) = First (J))))
       and then Dest'First = 1
       and then Dest'Length = SA'Length,
     Post                   =>
       Dest'Initialized
       and then Permutation (Dest)
       and then (for all K in Dest'Range => V (Dest (K)) = First (K))
       and then (for all J in Dest'Range =>
                   (for all K in Dest'Range =>
                      (if J < K and then First (J) = First (K)
                       then Dest (J) < Dest (K))));

   procedure Slots
     (SA : Mapping; V : Keys; T : Mapping; First : Keys; Dest : out Mapping)
   is
      N     : constant Positive := SA'Length;
      --  The next free place of each class, at the class plus one.
      Cur   : Keys (1 .. N)
      with Relaxed_Initialization;
      Place : Positive;
      --  Which element took each place, or 0.
      Owner : Keys (1 .. N) := (others => 0)
      with Ghost;
      Inv   : constant Mapping := Permutations.Inverse (SA)
      with Ghost;
   begin
      for P in 1 .. N loop
         Cur (P) := P;
         pragma
           Loop_Invariant
             (for all Q in 1 .. P => Cur (Q)'Initialized and then Cur (Q) = Q);
      end loop;
      pragma Assert (for all J in 1 .. N => First (J) = V (Inv (T (J))));
      for K in 1 .. N loop
         Next_Free (SA, Inv, V, T, First, Cur, Owner, K);
         Place := Cur (First (K) + 1);
         Dest (K) := Place;
         Cur (First (K) + 1) := Place + 1;
         Owner (Place) := K;
         pragma Loop_Invariant (Cur'Initialized);
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Dest (J)'Initialized
                and then Dest (J) in 1 .. N
                and then V (Dest (J)) = First (J)
                and then Owner (Dest (J)) = J
                and then Dest (J) < Cur (First (J) + 1));
         pragma
           Loop_Invariant
             (for all P in 1 .. N =>
                Owner (P) <= K
                and then (Owner (P) /= 0) = (P < Cur (V (P) + 1))
                and then (if Owner (P) /= 0 then First (Owner (P)) = V (P)));
         pragma
           Loop_Invariant
             (for all P in 1 .. N =>
                (for all Q in 1 .. N =>
                   (if P /= Q and then Owner (P) /= 0
                    then Owner (P) /= Owner (Q))));
         pragma
           Loop_Invariant
             (for all P in 1 .. N =>
                V (P) < Cur (V (P) + 1)
                and then Cur (V (P) + 1) <= N + 1
                and then (Cur (V (P) + 1) = V (P) + 1
                          or else V (Cur (V (P) + 1) - 1) = V (P)));
         pragma
           Loop_Invariant
             (for all I in 1 .. K =>
                (for all J in 1 .. K =>
                   (if I < J and then First (I) = First (J)
                    then Dest (I) < Dest (J))));
      end loop;
   end Slots;

   --  Numbers the classes of equal pairs along an order sorted by pairs, as
   --  runs, in place. Split tells whether some class of first keys has more
   --  than one second key.
   procedure Dense_Runs
     (V : in out Keys; K2 : Keys; Classes : out Positive; Split : out Boolean)
   with
     Pre  =>
       V'First = 1
       and then V'Length >= 1
       and then V'Length <= Max_Length
       and then K2'First = 1
       and then K2'Last = V'Last
       and then (for all P in V'Range =>
                   (for all Q in P .. V'Last => Pair_LE (V, K2, P, Q))),
     Post =>
       Runs (V)
       and then (for all P in V'Range =>
                   (for all Q in V'Range =>
                      (V (P) <= V (Q)) = Pair_LE (V'Old, K2, P, Q)))
       and then Classes <= V'Length
       and then (if Classes = V'Length
                 then (for all P in V'Range => V (P) = P - 1))
       and then (if not Split
                 then
                   (for all P in V'Range =>
                      (for all Q in V'Range =>
                         (if V'Old (P) = V'Old (Q) then K2 (P) = K2 (Q)))));

   procedure Dense_Runs
     (V : in out Keys; K2 : Keys; Classes : out Positive; Split : out Boolean)
   is
      Old  : constant Keys := V
      with Ghost;
      Next : Boolean
      with Ghost;
      --  The previous pair, and the run it belongs to.
      P1   : Natural := V (1);
      P2   : Natural := K2 (1);
      Head : Natural := 0;
   begin
      Classes := 1;
      Split := False;
      V (1) := 0;
      pragma
        Assert
          (for all P in V'Range =>
             (for all Q in P .. V'Last => Pair_LE (Old, K2, P, Q)));
      for I in 2 .. V'Last loop
         Next := V (I) /= P1 or else K2 (I) /= P2;
         if V (I) /= P1 or else K2 (I) /= P2 then
            if V (I) = P1 then
               Split := True;
            end if;
            Classes := Classes + 1;
            Head := I - 1;
         end if;
         P1 := V (I);
         P2 := K2 (I);
         V (I) := Head;
         pragma Assert (if Next then not Pair_LE (Old, K2, I, I - 1));
         pragma
           Assert
             (if Next
                then
                  (for all P in 1 .. I - 1 =>
                     V (P) < V (I) and then not Pair_LE (Old, K2, I, P)));
         pragma Assert (if not Next then V (I) = V (I - 1));
         pragma Assert (if Next and then not Split then Old (I - 1) < Old (I));
         pragma
           Assert
             (if not Split
                then
                  (for all P in 1 .. I - 1 =>
                     (if Old (P) = Old (I) then K2 (P) = K2 (I))));
         pragma
           Assert
             (if not Next
                then
                  (for all P in 1 .. I - 1 =>
                     Pair_LE (Old, K2, P, I) = Pair_LE (Old, K2, P, I - 1)
                     and then Pair_LE (Old, K2, I, P)
                              = Pair_LE (Old, K2, I - 1, P)));
         pragma Loop_Invariant (P1 = Old (I) and then P2 = K2 (I));
         pragma
           Loop_Invariant (for all Q in I + 1 .. V'Last => V (Q) = Old (Q));
         pragma Loop_Invariant (Head = V (I));
         pragma Loop_Invariant (Classes <= I);
         pragma
           Loop_Invariant
             (if Classes = I then (for all P in 1 .. I => V (P) = P - 1));
         pragma
           Loop_Invariant
             (for all P in 1 .. I => V (P) < P and then V (V (P) + 1) = V (P));
         pragma
           Loop_Invariant
             (for all P in 1 .. I => (for all Q in P .. I => V (P) <= V (Q)));
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                (for all Q in 1 .. I =>
                   (V (P) <= V (Q)) = Pair_LE (Old, K2, P, Q)));
         pragma
           Loop_Invariant
             (if not Split
                then
                  (for all P in 1 .. I =>
                     (for all Q in 1 .. I =>
                        (if Old (P) = Old (Q) then K2 (P) = K2 (Q)))));
      end loop;
   end Dense_Runs;

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
      V       : out Keys;
      Classes : out Positive)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then R'First = 1
       and then R'Length = S'Length
       and then SA'First = 1
       and then SA'Length = S'Length
       and then V'First = 1
       and then V'Length = S'Length,
     Post =>
       Ranked (S, F, R, 1)
       and then Permutation (SA)
       and then (for all P in SA'Range => V (P) = R (SA (P)))
       and then Runs (V)
       and then Classes <= S'Length
       and then (if Classes = S'Length then Distinct_Keys (R))
       and then (if Classes = S'Length
                 then (for all P in SA'Range => V (P) = P - 1));

   procedure Initial
     (S       : String;
      F       : Table;
      R       : out Keys;
      SA      : out Mapping;
      V       : out Keys;
      Classes : out Positive)
   is
      N     : constant Positive := S'Length;
      Code  : Keys (1 .. N) := (others => 0);
      Zero  : constant Keys (1 .. N) := (others => 0);
      Ident : Mapping (1 .. N) := (others => 1);
      Split : Boolean;
   begin
      R := (others => 0);
      SA := (others => 1);
      V := (others => 0);
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
      for I in 1 .. N loop
         V (I) := Code (SA (I));
         pragma Loop_Invariant (for all J in 1 .. I => V (J) = Code (SA (J)));
      end loop;
      pragma
        Assert
          (for all P in 1 .. N =>
             (for all Q in P .. N => Pair_LE (V, Zero, P, Q)));
      declare
         Codes : constant Keys (1 .. N) := V
         with Ghost;
         Inv   : constant Mapping := Permutations.Inverse (SA)
         with Ghost;
      begin
         Dense_Runs (V, Zero, Classes, Split);
         Spread (SA, V, R);
         pragma
           Assert
             (for all A in 1 .. N =>
                R (A) = V (Inv (A)) and then Codes (Inv (A)) = Code (A));
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (R (A) <= R (B)) = (Code (A) <= Code (B))));
         if Classes = N then
            pragma Assert (for all A in 1 .. N => R (A) = Inv (A) - 1);
         end if;
      end;
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

   --  Moving back without a division: in a single factor, or from a position
   --  at least D letters into its factor.
   procedure Back_Single (S : String; F : Table; P : Positive; D : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then P in F'Range
       and then D <= 4 * Max_Length
       and then F (P).First = 1
       and then F (P).Length = S'Length,
     Post =>
       Back (S, F, P, D)
       = (if P > Reduce (D, S'Length)
          then P - Reduce (D, S'Length)
          else P - Reduce (D, S'Length) + S'Length);

   procedure Back_Single (S : String; F : Table; P : Positive; D : Natural)
   is null;

   procedure Back_Inside (S : String; F : Table; P : Positive; D : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then P in F'Range
       and then D <= 4 * Max_Length
       and then P - F (P).First >= D,
     Post => Back (S, F, P, D) = P - D;

   procedure Back_Inside (S : String; F : Table; P : Positive; D : Natural)
   is null;

   --  One round: ranks by the first 2 * H letters, from ranks by H. When no
   --  class splits, the ranks are final (Closed). V holds the ranks in the
   --  order of SA, where they form runs; the run of a class tells where its
   --  elements go, so the round needs no counting pass. Each loop does one
   --  kind of random access, so that the processor can overlap its misses.
   procedure Double
     (S       : String;
      F       : Table;
      Start   : Mapping;
      Single  : Boolean;
      R       : in out Keys;
      SA      : in out Mapping;
      V       : in out Keys;
      H       : Positive;
      Classes : out Positive;
      Split   : out Boolean)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
       and then Start'First = 1
       and then Start'Length = S'Length
       and then (for all P in 1 .. S'Length => Start (P) = F (P).First)
       and then (if Single
                 then
                   (for all P in 1 .. S'Length =>
                      F (P).First = 1 and then F (P).Length = S'Length))
       and then Ranked (S, F, R, H)
       and then SA'First = 1
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then V'First = 1
       and then V'Length = S'Length
       and then (for all P in 1 .. S'Length => V (P) = R (SA (P)))
       and then Runs (V),
     Post =>
       Ranked (S, F, R, 2 * H)
       and then Permutation (SA)
       and then (for all P in 1 .. S'Length => V (P) = R (SA (P)))
       and then Runs (V)
       and then Classes <= S'Length
       and then (if Classes = S'Length then Distinct_Keys (R))
       and then (if Classes = S'Length
                 then (for all P in 1 .. S'Length => V (P) = P - 1))
       and then (if not Split then Closed (S, F, H));

   procedure Double
     (S       : String;
      F       : Table;
      Start   : Mapping;
      Single  : Boolean;
      R       : in out Keys;
      SA      : in out Mapping;
      V       : in out Keys;
      H       : Positive;
      Classes : out Positive;
      Split   : out Boolean)
   is
      N      : constant Positive := S'Length;
      --  The previous order, each position moved H letters back: sorted by
      --  the rank H letters on, which is the second key of a pair.
      T      : Mapping (1 .. N)
      with Relaxed_Initialization;
      --  The first key, in the order of T.
      First  : Keys (1 .. N)
      with Relaxed_Initialization;
      --  The second key, by position.
      Second : Keys (1 .. N)
      with Relaxed_Initialization;
      --  The second key, in the new order.
      Along  : Keys (1 .. N)
      with Relaxed_Initialization;
      --  Where each element of T goes.
      Dest   : Mapping (1 .. N)
      with Relaxed_Initialization;
      Old_R  : constant Keys := R
      with Ghost;
   begin
      pragma Assert (Ranked (S, F, Old_R, H));
      if Single then
         declare
            D : constant Natural := Reduce (H, N);
         begin
            for K in 1 .. N loop
               Back_Single (S, F, SA (K), H);
               T (K) := (if SA (K) > D then SA (K) - D else SA (K) - D + N);
               pragma
                 Loop_Invariant
                   (for all J in 1 .. K =>
                      T (J)'Initialized
                      and then T (J) = Back (S, F, SA (J), H));
            end loop;
         end;
      else
         for K in 1 .. N loop
            if SA (K) - Start (SA (K)) >= H then
               Back_Inside (S, F, SA (K), H);
               T (K) := SA (K) - H;
            else
               T (K) := Back (S, F, SA (K), H);
            end if;
            pragma
              Loop_Invariant
                (for all J in 1 .. K =>
                   T (J)'Initialized and then T (J) = Back (S, F, SA (J), H));
         end loop;
      end if;
      pragma Assert (T'Initialized);
      pragma Assert (for all K in 1 .. N => Jump (S, F, T (K), H) = SA (K));
      pragma
        Assert
          (for all I in 1 .. N =>
             (for all J in 1 .. N => (if I /= J then T (I) /= T (J))));
      Gather (R, T, First);
      for K in 1 .. N loop
         Second (K) := R (Jump (S, F, K, H));
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Second (J)'Initialized
                and then Second (J) = R (Jump (S, F, J, H)));
      end loop;
      pragma Assert (Second'Initialized);
      pragma Assert (for all K in 1 .. N => Second (T (K)) = V (K));
      Slots (SA, V, T, First, Dest);
      Scatter (Dest, T, SA);
      declare
         Inv_Dest : constant Mapping := Permutations.Inverse (Dest)
         with Ghost;
      begin
         pragma Assert (for all P in 1 .. N => SA (P) = T (Inv_Dest (P)));
         pragma Assert (for all P in 1 .. N => V (P) = R (SA (P)));
         pragma
           Assert (for all P in 1 .. N => Second (SA (P)) = V (Inv_Dest (P)));
         pragma
           Assert
             (for all P in 1 .. N =>
                (for all Q in P .. N =>
                   (if V (P) = V (Q) then Inv_Dest (P) <= Inv_Dest (Q))));
         pragma
           Assert
             (for all P in 1 .. N =>
                (for all Q in P .. N =>
                   V (P) <= V (Q)
                   and then (if V (P) = V (Q)
                             then V (Inv_Dest (P)) <= V (Inv_Dest (Q)))));
         pragma
           Assert
             (for all P in 1 .. N =>
                (for all Q in P .. N => Pair_LE (R, Second, SA (P), SA (Q))));
      end;
      Gather (Second, SA, Along);
      pragma
        Assert
          (for all P in 1 .. N =>
             (for all Q in P .. N => Pair_LE (V, Along, P, Q)));
      declare
         Mid : constant Keys := V
         with Ghost;
         Inv : constant Mapping := Permutations.Inverse (SA)
         with Ghost;
      begin
         Dense_Runs (V, Along, Classes, Split);
         Spread (SA, V, R);
         pragma
           Assert
             (for all A in 1 .. N =>
                R (A) = V (Inv (A))
                and then Mid (Inv (A)) = Old_R (A)
                and then Along (Inv (A)) = Second (A));
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (R (A) <= R (B)) = Pair_LE (Mid, Along, Inv (A), Inv (B))));
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   Pair_LE (Mid, Along, Inv (A), Inv (B))
                   = Pair_LE (Old_R, Second, A, B)));
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (R (A) <= R (B)) = Pair_LE (Old_R, Second, A, B)));
         if Classes = N then
            pragma Assert (for all A in 1 .. N => R (A) = Inv (A) - 1);
         end if;
         if not Split then
            pragma
              Assert
                (for all A in 1 .. N =>
                   (for all B in 1 .. N =>
                      (if Old_R (A) = Old_R (B)
                       then Second (A) = Second (B))));
         end if;
      end;
      Doubled (S, F, Old_R, Second, R, H);
      if not Split then
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (if Old_R (A) = Old_R (B)
                    then
                      Old_R (Jump (S, F, A, H)) = Old_R (Jump (S, F, B, H)))));
         Closed_Intro (S, F, Old_R, H);
      end if;
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

   --  When no two ranks are equal, SA lists the rows in order, whatever the
   --  tie order: the table is read off it.
   procedure Read_Off
     (S    : String;
      F    : Table;
      R    : Keys;
      SA   : Mapping;
      Ties : Tie_Order;
      Rows : out Table)
   with
     Relaxed_Initialization => Rows,
     Pre                    =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then Ranked (S, F, R, 2 * S'Length)
       and then SA'First = 1
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then (for all P in SA'Range => R (SA (P)) = P - 1)
       and then Rows'First = 1
       and then Rows'Length = S'Length,
     Post                   =>
       Rows'Initialized
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, F)
       and then Sorted (S, Rows, Ties);

   procedure Read_Off
     (S    : String;
      F    : Table;
      R    : Keys;
      SA   : Mapping;
      Ties : Tie_Order;
      Rows : out Table)
   is
      N   : constant Positive := S'Length;
      Inv : constant Mapping := Permutations.Inverse (SA)
      with Ghost;
   begin
      for I in 1 .. N loop
         Rows (I) := F (SA (I));
         pragma
           Loop_Invariant
             (for all J in 1 .. I =>
                Rows (J)'Initialized and then Rows (J) = F (SA (J)));
      end loop;
      pragma Assert (Rows'Initialized);
      pragma Assert (for all P in 1 .. N => F (P) = Rows (Inv (P)));
      pragma Assert (Same_Rows (Rows, F));
      pragma
        Assert
          (for all I in 1 .. N => Rows (I).First + Rows (I).Offset = SA (I));
      pragma Assert (Distinct (Rows));
      for I in 1 .. N loop
         for J in I .. N loop
            if I = J then
               Order_Laws (S, Rows (I), Rows (J), Rows (I), 2 * N);
            end if;
            pragma Assert (R (SA (I)) <= R (SA (J)));
            pragma
              Assert
                (if I /= J
                   then not Equal_Prefix (S, Rows (I), Rows (J), 2 * N));
            Key_Intro (S, Rows (I), Rows (J), Ties);
            pragma
              Loop_Invariant
                (for all L in I .. J => Key_LE (S, Rows (I), Rows (L), Ties));
         end loop;
         pragma
           Loop_Invariant
             (for all K in 1 .. I =>
                (for all L in K .. N => Key_LE (S, Rows (K), Rows (L), Ties)));
      end loop;
   end Read_Off;

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
         V       : Keys (1 .. N);
         --  Where the factor of each position starts.
         Start   : Mapping (1 .. N) := (others => 1);
         --  One factor, as in the classical table: positions move back
         --  without reading the factor table.
         Single  : constant Boolean := Factors (1).Length = N;
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
            Start (P) := Factors (P).First;
            pragma Loop_Invariant (Longest <= N);
            pragma
              Loop_Invariant
                (for all Q in 1 .. P =>
                   Factors (Q).Length <= Longest
                   and then Start (Q) = Factors (Q).First);
         end loop;
         pragma
           Assert
             (if Single
                then
                  (for all P in 1 .. N =>
                     Factors (P).First = 1 and then Factors (P).Length = N));
         Initial (S, Factors, R, SA, V, Classes);
         while H < 2 * Longest and then Classes < N and then Split loop
            pragma Loop_Invariant (H < 2 * Longest);
            pragma Loop_Invariant (Last_H <= H);
            pragma Loop_Invariant (Ranked (S, Factors, R, H));
            pragma Loop_Invariant (Permutation (SA));
            pragma Loop_Invariant (for all P in 1 .. N => V (P) = R (SA (P)));
            pragma Loop_Invariant (Runs (V));
            pragma Loop_Invariant (Classes <= N);
            pragma
              Loop_Invariant
                (if Classes = N then (for all P in 1 .. N => V (P) = P - 1));
            pragma Loop_Variant (Increases => H);
            Double (S, Factors, Start, Single, R, SA, V, H, Classes, Split);
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
         if Classes = N then
            Read_Off (S, Factors, R, SA, Ties, Rows);
         else
            Lay_Out (S, Factors, R, Ties, Rows);
         end if;
      end;
      return Rows;
   end Sorted_Rows;
end BWT.Doubling;
