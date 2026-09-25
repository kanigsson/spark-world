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
      Code  : Keys (1 .. N) := (others => 0)
      with Ghost;
      Split : Boolean;
   begin
      --  R stays zero until the ranks are spread, so it serves as the
      --  constant second key of the first round.
      R := (others => 0);
      SA := (others => 1);
      V := (others => 0);
      for I in 1 .. N loop
         Code (I) := Character'Pos (S (I));
         pragma
           Loop_Invariant
             (for all J in 1 .. I => Code (J) = Character'Pos (S (J)));
      end loop;
      declare
         --  The stable order of the letters, as the decoders use it.
         Map : constant Mapping := LF (S);
         Inv : constant Mapping := Permutations.Inverse (Map)
         with Ghost;
      begin
         for I in 1 .. N loop
            SA (Map (I)) := I;
            pragma Loop_Invariant (for all J in 1 .. I => SA (Map (J)) = J);
         end loop;
         pragma Assert (for all P in 1 .. N => SA (P) = Inv (P));
         pragma Assert (Permutation (SA));
         pragma
           Assert
             (for all P in 1 .. N =>
                (for all Q in P .. N => Ordered (S, Inv (P), Inv (Q))));
      end;
      for I in 1 .. N loop
         V (I) := Character'Pos (S (SA (I)));
         pragma Loop_Invariant (for all J in 1 .. I => V (J) = Code (SA (J)));
      end loop;
      pragma
        Assert
          (for all P in 1 .. N =>
             (for all Q in P .. N => Pair_LE (V, R, P, Q)));
      declare
         Codes : constant Keys (1 .. N) := V
         with Ghost;
         Inv   : constant Mapping := Permutations.Inverse (SA)
         with Ghost;
      begin
         Dense_Runs (V, R, Classes, Split);
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

   --  Moving on without a division, in a single factor.
   procedure Jump_Single (S : String; F : Table; P : Positive; D : Natural)
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
       Jump (S, F, P, D)
       = (if P + Reduce (D, S'Length) <= S'Length
          then P + Reduce (D, S'Length)
          else P + Reduce (D, S'Length) - S'Length);

   procedure Jump_Single (S : String; F : Table; P : Positive; D : Natural) is
      N : constant Positive := S'Length;
      Q : constant Natural := D / N;
      M : constant Natural := D mod N;
   begin
      pragma Assert (F (P).Offset = P - 1);
      pragma Assert (D = Q * N + M);
      pragma Assert (Reduce (D, N) = M);
      --  The remainder, from a quotient and a remainder in 0 .. N - 1.
      if P + M <= N then
         pragma Assert (P - 1 + D = (P - 1 + M) + Q * N);
         pragma Assert ((P - 1 + D) mod N = P - 1 + M);
      else
         pragma Assert (P - 1 + D = (P - 1 + M - N) + (Q + 1) * N);
         pragma Assert ((P - 1 + D) mod N = P - 1 + M - N);
      end if;
   end Jump_Single;

   --  Second (K) := R (Jump (K, H)), for all K. A single factor needs no
   --  table: the ranks H letters on are the ranks rotated, two block copies.
   procedure Second_Keys
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      H      : Positive;
      Second : out Keys)
   with
     Relaxed_Initialization => Second,
     Pre                    =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
       and then (if Single
                 then
                   (for all P in 1 .. S'Length =>
                      F (P).First = 1 and then F (P).Length = S'Length))
       and then R'First = 1
       and then R'Length = S'Length
       and then Second'First = 1
       and then Second'Length = S'Length,
     Post                   =>
       Second'Initialized
       and then (for all K in 1 .. S'Length =>
                   Second (K) = R (Jump (S, F, K, H)));

   procedure Second_Keys
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      H      : Positive;
      Second : out Keys)
   is
      N : constant Positive := S'Length;
   begin
      if Single then
         declare
            D : constant Natural := Reduce (H, N);
         begin
            for K in 1 .. N - D loop
               Jump_Single (S, F, K, H);
               Second (K) := R (K + D);
               pragma
                 Loop_Invariant
                   (for all J in 1 .. K =>
                      Second (J)'Initialized
                      and then Second (J) = R (Jump (S, F, J, H)));
            end loop;
            for K in N - D + 1 .. N loop
               Jump_Single (S, F, K, H);
               Second (K) := R (K + D - N);
               pragma
                 Loop_Invariant
                   (for all J in 1 .. K =>
                      Second (J)'Initialized
                      and then Second (J) = R (Jump (S, F, J, H)));
            end loop;
         end;
      else
         for K in 1 .. N loop
            Second (K) := R (Jump (S, F, K, H));
            pragma
              Loop_Invariant
                (for all J in 1 .. K =>
                   Second (J)'Initialized
                   and then Second (J) = R (Jump (S, F, J, H)));
         end loop;
      end if;
   end Second_Keys;

   --  Ranks spread from SA compare as the ranks along SA do.
   procedure Spread_Order (R, V, Mid, Along : Keys; Inv : Mapping)
   with
     Ghost,
     Pre  =>
       V'First = 1
       and then Mid'First = 1
       and then Mid'Last = V'Last
       and then Along'First = 1
       and then Along'Last = V'Last
       and then R'First = 1
       and then R'Last = V'Last
       and then Inv'First = 1
       and then Inv'Last = V'Last
       and then (for all X of Inv => X in V'Range)
       and then (for all A in R'Range => R (A) = V (Inv (A)))
       and then (for all P in V'Range =>
                   (for all Q in V'Range =>
                      (V (P) <= V (Q)) = Pair_LE (Mid, Along, P, Q))),
     Post =>
       (for all A in R'Range =>
          (for all B in R'Range =>
             (R (A) <= R (B)) = Pair_LE (Mid, Along, Inv (A), Inv (B))));

   procedure Spread_Order (R, V, Mid, Along : Keys; Inv : Mapping) is null;

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
      Second_Keys (S, F, Single, R, H, Second);
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
         Spread_Order (R, V, Mid, Along, Inv);
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

   --  Skipping settled classes (Larsson and Sadakane). Once most classes
   --  hold a single row, a round sorts only the classes that still hold
   --  several, each by its second key and in place. All second keys are read
   --  before any rank changes, so the round still goes from H letters to
   --  exactly 2 * H.

   --  What a group sort needs of its inputs, and keeps: each element of the
   --  range carries its second key, and belongs to class C.
   function Sort_Frame
     (S : String; F : Table; H : Natural; R : Keys; SA : Mapping; K : Keys)
      return Boolean
   is (Supported (S)
       and then Cycles (S, F)
       and then H <= 4 * Max_Length
       and then R'First = 1
       and then R'Length = S'Length
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then K'First = 1
       and then K'Last = SA'Last)
   with Ghost;

   function Paired
     (S      : String;
      F      : Table;
      H      : Natural;
      R      : Keys;
      SA     : Mapping;
      K      : Keys;
      C      : Natural;
      Lo, Hi : Positive) return Boolean
   is (for all I in Lo .. Hi =>
         K (I) = R (Jump (S, F, SA (I), H)) and then R (SA (I)) = C)
   with Ghost, Pre => Sort_Frame (S, F, H, R, SA, K) and then Hi <= SA'Last;

   function Bounded_By
     (K : Keys; Lo, Hi : Positive; Min, Max : Integer) return Boolean
   is (for all I in Lo .. Hi => K (I) >= Min and then K (I) <= Max)
   with Ghost, Pre => Hi <= K'Last and then K'First = 1;

   function Sorted_Between (K : Keys; Lo, Hi : Natural) return Boolean
   is (for all P in Lo .. Hi => (for all Q in P .. Hi => K (P) <= K (Q)))
   with Ghost, Pre => (if Lo <= Hi then Lo >= K'First and then Hi <= K'Last);

   --  Exchanges two elements, with their keys.
   procedure Swap_Pair (SA : in out Mapping; K : in out Keys; A, B : Positive)
   with
     Pre  =>
       Permutation (SA)
       and then K'First = 1
       and then K'Last = SA'Last
       and then A in SA'Range
       and then B in SA'Range,
     Post =>
       Permutation (SA)
       and then SA (A) = SA'Old (B)
       and then SA (B) = SA'Old (A)
       and then K (A) = K'Old (B)
       and then K (B) = K'Old (A)
       and then (for all I in SA'Range =>
                   (if I /= A and then I /= B
                    then SA (I) = SA'Old (I) and then K (I) = K'Old (I)));

   procedure Swap_Pair (SA : in out Mapping; K : in out Keys; A, B : Positive)
   is
      Elem : constant Positive := SA (A);
      Key  : constant Natural := K (A);
   begin
      SA (A) := SA (B);
      SA (B) := Elem;
      K (A) := K (B);
      K (B) := Key;
   end Swap_Pair;

   procedure Insertion_Sort
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer)
   with
     Pre  =>
       Sort_Frame (S, F, H, R, SA, K)
       and then Lo <= Hi
       and then Hi <= SA'Last
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max),
     Post =>
       Permutation (SA)
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max)
       and then Sorted_Between (K, Lo, Hi)
       and then (for all I in SA'Range =>
                   (if I not in Lo .. Hi
                    then SA (I) = SA'Old (I) and then K (I) = K'Old (I)));

   procedure Insertion_Sort
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer)
   is
      J : Positive;
   begin
      for I in Lo + 1 .. Hi loop
         J := I;
         loop
            pragma Loop_Invariant (J in Lo .. I);
            pragma Loop_Invariant (Permutation (SA));
            pragma Loop_Invariant (Paired (S, F, H, R, SA, K, C, Lo, Hi));
            pragma Loop_Invariant (Bounded_By (K, Lo, Hi, Min, Max));
            pragma
              Loop_Invariant
                (for all P in Lo .. I =>
                   (for all Q in P .. I =>
                      (if P /= J and then Q /= J then K (P) <= K (Q))));
            pragma Loop_Invariant (for all Q in J + 1 .. I => K (J) <= K (Q));
            pragma
              Loop_Invariant
                (for all X in SA'Range =>
                   (if X not in Lo .. Hi
                    then
                      SA (X) = SA'Loop_Entry (X)
                      and then K (X) = K'Loop_Entry (X)));
            pragma
              Loop_Invariant
                (for all X in I + 1 .. Hi => K (X) = K'Loop_Entry (X));
            pragma Loop_Variant (Decreases => J);
            exit when J = Lo or else K (J - 1) <= K (J);
            Swap_Pair (SA, K, J - 1, J);
            J := J - 1;
         end loop;
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (Paired (S, F, H, R, SA, K, C, Lo, Hi));
         pragma Loop_Invariant (Bounded_By (K, Lo, Hi, Min, Max));
         pragma Loop_Invariant (Sorted_Between (K, Lo, I));
         pragma
           Loop_Invariant
             (for all X in SA'Range =>
                (if X not in Lo .. Hi
                 then
                   SA (X) = SA'Loop_Entry (X)
                   and then K (X) = K'Loop_Entry (X)));
      end loop;
   end Insertion_Sort;

   --  Splits a range around the key of its first element: smaller keys,
   --  then equal ones, then larger ones.
   procedure Partition
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer;
      Pivot    : out Natural;
      Lt, Gt   : out Positive)
   with
     Pre  =>
       Sort_Frame (S, F, H, R, SA, K)
       and then Lo < Hi
       and then Hi <= SA'Last
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max),
     Post =>
       Permutation (SA)
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max)
       and then Pivot = K'Old (Lo)
       and then Lo <= Lt
       and then Lt < Gt
       and then Gt <= Hi + 1
       and then (for all I in Lo .. Lt - 1 => K (I) < Pivot)
       and then (for all I in Lt .. Gt - 1 => K (I) = Pivot)
       and then (for all I in Gt .. Hi => K (I) > Pivot)
       and then (for all I in SA'Range =>
                   (if I not in Lo .. Hi
                    then SA (I) = SA'Old (I) and then K (I) = K'Old (I)));

   procedure Partition
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer;
      Pivot    : out Natural;
      Lt, Gt   : out Positive)
   is
      I : Positive := Lo + 1;
   begin
      Pivot := K (Lo);
      Lt := Lo;
      Gt := Hi + 1;
      while I < Gt loop
         pragma
           Loop_Invariant (Lo <= Lt and then Lt < I and then Gt <= Hi + 1);
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (Paired (S, F, H, R, SA, K, C, Lo, Hi));
         pragma Loop_Invariant (Bounded_By (K, Lo, Hi, Min, Max));
         pragma Loop_Invariant (for all X in Lo .. Lt - 1 => K (X) < Pivot);
         pragma Loop_Invariant (for all X in Lt .. I - 1 => K (X) = Pivot);
         pragma Loop_Invariant (for all X in Gt .. Hi => K (X) > Pivot);
         pragma
           Loop_Invariant
             (for all X in SA'Range =>
                (if X not in Lo .. Hi
                 then
                   SA (X) = SA'Loop_Entry (X)
                   and then K (X) = K'Loop_Entry (X)));
         pragma Loop_Variant (Decreases => Gt - I);
         if K (I) < Pivot then
            Swap_Pair (SA, K, Lt, I);
            Lt := Lt + 1;
            I := I + 1;
         elsif K (I) > Pivot then
            Gt := Gt - 1;
            Swap_Pair (SA, K, I, Gt);
         else
            I := I + 1;
         end if;
      end loop;
   end Partition;

   --  Heapsort, the fallback that bounds a group sort to O(g log g) when
   --  quicksort's pivots keep splitting badly. The heap is laid out from Lo:
   --  the parent of J is Lo + (J - Lo - 1) / 2.
   function Parent (Lo, J : Positive) return Positive
   is (Lo + (J - Lo - 1) / 2)
   with Pre => Lo < J, Post => Parent'Result in Lo .. J - 1;

   --  Every parent from Top on is at least as large as its children.
   function Heap_From (K : Keys; Lo, Top, E : Positive) return Boolean
   is (for all J in Lo + 1 .. E =>
         (if Parent (Lo, J) >= Top then K (Parent (Lo, J)) >= K (J)))
   with
     Ghost,
     Pre =>
       K'First = 1
       and then E <= K'Last
       and then K'Last <= Max_Length
       and then Lo <= Max_Length;

   --  The root of a heap is its largest element.
   procedure Heap_Max (K : Keys; Lo, E : Positive)
   with
     Ghost,
     Pre  =>
       K'First = 1
       and then Lo <= E
       and then E <= K'Last
       and then K'Last <= Max_Length
       and then Heap_From (K, Lo, Lo, E),
     Post => (for all X in Lo .. E => K (X) <= K (Lo));

   procedure Heap_Max (K : Keys; Lo, E : Positive) is
   begin
      for X in Lo .. E loop
         pragma Loop_Invariant (for all Y in Lo .. X => K (Y) <= K (Lo));
      end loop;
   end Heap_Max;

   --  Moves the element at X0 down its subtree until the heap holds from X0.
   procedure Sift_Down
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      X0, E    : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer;
      --  Bounds on the keys of X0 .. E, which stay there.
      Low, Top : Integer)
   with
     Pre  =>
       Sort_Frame (S, F, H, R, SA, K)
       and then Lo <= X0
       and then X0 <= E
       and then E <= Hi
       and then Hi <= SA'Last
       and then Hi <= Max_Length
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max)
       and then Bounded_By (K, X0, E, Low, Top)
       and then Heap_From (K, Lo, X0 + 1, E),
     Post =>
       Permutation (SA)
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max)
       and then Bounded_By (K, X0, E, Low, Top)
       and then Heap_From (K, Lo, X0, E)
       and then (for all I in SA'Range =>
                   (if I not in X0 .. E
                    then SA (I) = SA'Old (I) and then K (I) = K'Old (I)));

   procedure Sift_Down
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      X0, E    : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer;
      --  Bounds on the keys of X0 .. E, which stay there.
      Low, Top : Integer)
   is
      X     : Positive := X0;
      Child : Positive;
   begin
      loop
         pragma Loop_Invariant (X in X0 .. E);
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (Paired (S, F, H, R, SA, K, C, Lo, Hi));
         pragma Loop_Invariant (Bounded_By (K, Lo, Hi, Min, Max));
         pragma Loop_Invariant (Bounded_By (K, X0, E, Low, Top));
         pragma
           Loop_Invariant
             (for all J in Lo + 1 .. E =>
                (if Parent (Lo, J) >= X0 and then Parent (Lo, J) /= X
                 then K (Parent (Lo, J)) >= K (J)));
         pragma
           Loop_Invariant
             (if X /= X0
                then
                  (for all J in Lo + 1 .. E =>
                     (if Parent (Lo, J) = X
                      then K (Parent (Lo, X)) >= K (J))));
         pragma
           Loop_Invariant
             (for all I in SA'Range =>
                (if I not in X0 .. E
                 then
                   SA (I) = SA'Loop_Entry (I)
                   and then K (I) = K'Loop_Entry (I)));
         pragma Loop_Variant (Increases => X);
         exit when 2 * (X - Lo) + 1 > E - Lo;
         Child := Lo + 2 * (X - Lo) + 1;
         if Child < E and then K (Child + 1) > K (Child) then
            Child := Child + 1;
         end if;
         exit when K (X) >= K (Child);
         Swap_Pair (SA, K, X, Child);
         X := Child;
      end loop;
   end Sift_Down;

   procedure Heap_Sort
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer)
   with
     Pre  =>
       Sort_Frame (S, F, H, R, SA, K)
       and then Lo <= Hi
       and then Hi <= SA'Last
       and then Hi <= Max_Length
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max),
     Post =>
       Permutation (SA)
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max)
       and then Sorted_Between (K, Lo, Hi)
       and then (for all I in SA'Range =>
                   (if I not in Lo .. Hi
                    then SA (I) = SA'Old (I) and then K (I) = K'Old (I)));

   procedure Heap_Sort
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer) is
   begin
      for I in reverse Lo .. Hi loop
         Sift_Down (SA, K, Lo, Hi, I, Hi, S, F, H, R, C, Min, Max, Min, Max);
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (Paired (S, F, H, R, SA, K, C, Lo, Hi));
         pragma Loop_Invariant (Bounded_By (K, Lo, Hi, Min, Max));
         pragma Loop_Invariant (Heap_From (K, Lo, I, Hi));
         pragma
           Loop_Invariant
             (for all X in SA'Range =>
                (if X not in Lo .. Hi
                 then
                   SA (X) = SA'Loop_Entry (X)
                   and then K (X) = K'Loop_Entry (X)));
      end loop;
      for E in reverse Lo + 1 .. Hi loop
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (Paired (S, F, H, R, SA, K, C, Lo, Hi));
         pragma Loop_Invariant (Bounded_By (K, Lo, Hi, Min, Max));
         pragma Loop_Invariant (Heap_From (K, Lo, Lo, E));
         pragma Loop_Invariant (Sorted_Between (K, E + 1, Hi));
         pragma
           Loop_Invariant
             (for all X in Lo .. E =>
                (for all Y in E + 1 .. Hi => K (X) <= K (Y)));
         pragma
           Loop_Invariant
             (for all X in SA'Range =>
                (if X not in Lo .. Hi
                 then
                   SA (X) = SA'Loop_Entry (X)
                   and then K (X) = K'Loop_Entry (X)));
         Heap_Max (K, Lo, E);
         Swap_Pair (SA, K, Lo, E);
         --  The largest key is now at E, and bounds the rest of the heap.
         Sift_Down
           (SA, K, Lo, Hi, Lo, E - 1, S, F, H, R, C, Min, Max, Min, K (E));
         pragma
           Assert
             (for all X in Lo .. E - 1 =>
                (for all Y in E .. Hi => K (X) <= K (Y)));
      end loop;
   end Heap_Sort;

   --  Quicksort, recursing on the smaller part so that the stack stays
   --  logarithmic, and sorting short ranges by insertion.
   procedure Quick_Sort
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer;
      Depth    : Natural)
   with
     Pre                =>
       Sort_Frame (S, F, H, R, SA, K)
       and then Lo <= Hi
       and then Hi <= SA'Last
       and then Hi <= Max_Length
       and then Min >= -1
       and then Max <= Max_Length + 1
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max),
     Post               =>
       Permutation (SA)
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, Min, Max)
       and then Sorted_Between (K, Lo, Hi)
       and then (for all I in SA'Range =>
                   (if I not in Lo .. Hi
                    then SA (I) = SA'Old (I) and then K (I) = K'Old (I))),
     Subprogram_Variant => (Decreases => Hi - Lo);

   procedure Quick_Sort
     (SA       : in out Mapping;
      K        : in out Keys;
      Lo, Hi   : Positive;
      S        : String;
      F        : Table;
      H        : Natural;
      R        : Keys;
      C        : Natural;
      Min, Max : Integer;
      Depth    : Natural)
   is
      --  Partitions left before falling back to heapsort.
      Budget : Natural := Depth;
      --  The part still to sort, and bounds on its keys.
      L      : Positive := Lo;
      U      : Natural := Hi;
      Low    : Integer := Min;
      High   : Integer := Max;
      Mid, M : Positive;
      Pivot  : Natural;
      Lt, Gt : Positive;
   begin
      loop
         pragma Loop_Invariant (Lo <= L and then U <= Hi and then L <= U + 1);
         pragma Loop_Invariant (Low >= Min and then High <= Max);
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (Paired (S, F, H, R, SA, K, C, Lo, Hi));
         pragma Loop_Invariant (Bounded_By (K, Lo, Hi, Min, Max));
         pragma Loop_Invariant (Bounded_By (K, L, U, Low, High));
         pragma Loop_Invariant (for all X in Lo .. L - 1 => K (X) < Low);
         pragma Loop_Invariant (for all X in U + 1 .. Hi => K (X) > High);
         pragma Loop_Invariant (Sorted_Between (K, Lo, L - 1));
         pragma Loop_Invariant (Sorted_Between (K, U + 1, Hi));
         pragma
           Loop_Invariant
             (for all X in Lo .. L - 1 =>
                (for all Y in U + 1 .. Hi => K (X) <= K (Y)));
         pragma
           Loop_Invariant
             (for all X in SA'Range =>
                (if X not in Lo .. Hi
                 then
                   SA (X) = SA'Loop_Entry (X)
                   and then K (X) = K'Loop_Entry (X)));
         pragma Loop_Variant (Decreases => U - L);
         exit when U < L + 16 or else Budget = 0;
         Budget := Budget - 1;
         --  The median of the first, middle and last keys as the pivot.
         Mid := L + (U - L) / 2;
         M :=
           (if K (L) < K (Mid)
            then
              (if K (Mid) < K (U) then Mid elsif K (L) < K (U) then U else L)
            else
              (if K (L) < K (U) then L elsif K (Mid) < K (U) then U else Mid));
         Swap_Pair (SA, K, L, M);
         Partition (SA, K, L, U, S, F, H, R, C, Low, High, Pivot, Lt, Gt);
         if Lt - L <= U + 1 - Gt then
            if Lt > L + 1 then
               Quick_Sort
                 (SA, K, L, Lt - 1, S, F, H, R, C, Low, Pivot - 1, Budget);
            end if;
            L := Gt;
            Low := Pivot + 1;
         else
            if U > Gt then
               Quick_Sort
                 (SA, K, Gt, U, S, F, H, R, C, Pivot + 1, High, Budget);
            end if;
            U := Lt - 1;
            High := Pivot - 1;
         end if;
      end loop;
      if U >= L + 16 then
         Heap_Sort (SA, K, L, U, S, F, H, R, C, Low, High);
      elsif L < U then
         Insertion_Sort (SA, K, L, U, S, F, H, R, C, Low, High);
      end if;
      pragma Assert (Sorted_Between (K, L, U));
      pragma
        Assert
          (for all X in Lo .. L - 1 =>
             (for all Y in L .. U => K (X) <= K (Y)));
      pragma
        Assert
          (for all X in L .. U =>
             (for all Y in U + 1 .. Hi => K (X) <= K (Y)));
   end Quick_Sort;

   --  Sorts a group by its keys: introsort, with a partition budget of
   --  twice the depth of a balanced split.
   procedure Sort_Group
     (SA     : in out Mapping;
      K      : in out Keys;
      Lo, Hi : Positive;
      S      : String;
      F      : Table;
      H      : Natural;
      R      : Keys;
      C      : Natural)
   with
     Pre  =>
       Sort_Frame (S, F, H, R, SA, K)
       and then Lo <= Hi
       and then Hi <= SA'Last
       and then Hi <= Max_Length
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Bounded_By (K, Lo, Hi, 0, Max_Length),
     Post =>
       Permutation (SA)
       and then Paired (S, F, H, R, SA, K, C, Lo, Hi)
       and then Sorted_Between (K, Lo, Hi)
       and then (for all I in SA'Range =>
                   (if I not in Lo .. Hi
                    then SA (I) = SA'Old (I) and then K (I) = K'Old (I)));

   procedure Sort_Group
     (SA     : in out Mapping;
      K      : in out Keys;
      Lo, Hi : Positive;
      S      : String;
      F      : Table;
      H      : Natural;
      R      : Keys;
      C      : Natural)
   is
      Size  : Natural := Hi - Lo + 1;
      Depth : Natural := 0;
   begin
      for Step in 1 .. 25 loop
         exit when Size <= 1;
         Size := Size / 2;
         Depth := Depth + 2;
         pragma Loop_Invariant (Depth = 2 * Step);
      end loop;
      Quick_Sort (SA, K, Lo, Hi, S, F, H, R, C, 0, Max_Length, Depth);
   end Sort_Group;

   --  The class of V (P) has another element.
   function In_Group (V : Keys; P : Positive) return Boolean
   is ((P > 1 and then V (P - 1) = V (P))
       or else (P < V'Last and then V (P + 1) = V (P)))
   with Ghost, Pre => V'First = 1 and then P in V'Range;

   --  P is alone in its class.
   function Alone (V : Keys; P : Positive) return Boolean
   is (V (P) = P - 1 and then (P = V'Last or else V (P + 1) = P))
   with Ghost, Pre => V'First = 1 and then P in V'Range;

   --  From an element alone in its class, Skip leads to the end of a stretch
   --  of such elements. A scan jumps over the stretch, and since an element
   --  alone in its class stays so, the stretch stays valid in later rounds.
   function Skips (V : Keys; Skip : Mapping) return Boolean
   is (Skip'First = 1
       and then Skip'Last = V'Last
       and then (for all P in V'Range =>
                   (if Alone (V, P)
                    then
                      Skip (P) in P .. V'Last
                      and then (for all X in P .. Skip (P) => Alone (V, X)))))
   with Ghost, Pre => V'First = 1;

   --  Skipping only itself is always valid.
   procedure Skips_Identity (V : Keys; Skip : Mapping)
   with
     Ghost,
     Pre  =>
       V'First = 1
       and then Skip'First = 1
       and then Skip'Last = V'Last
       and then (for all P in Skip'Range => Skip (P) = P),
     Post => Skips (V, Skip);

   procedure Skips_Identity (V : Keys; Skip : Mapping) is null;

   --  A run starts where its class does.
   procedure Run_Head (V : Keys; P : Positive)
   with
     Ghost,
     Pre  =>
       Runs (V)
       and then P in V'Range
       and then (P = 1 or else V (P - 1) /= V (P)),
     Post => V (P) = P - 1;

   procedure Run_Head (V : Keys; P : Positive) is
   begin
      if V (P) + 1 < P then
         pragma Assert (V (V (P) + 1) <= V (P - 1));
      end if;
   end Run_Head;

   --  Numbers the classes of equal second keys in a sorted group, as runs
   --  from the group's head. Split records that the group split, and
   --  Distinct is cleared when a new class has several elements.
   procedure Renumber_Group
     (V               : in out Keys;
      K               : Keys;
      Lo, Hi          : Positive;
      Split, Distinct : in out Boolean)
   with
     Pre  =>
       V'First = 1
       and then K'First = 1
       and then K'Last = V'Last
       and then Lo < Hi
       and then Hi <= V'Last
       and then (for all P in Lo .. Hi => V (P) = Lo - 1)
       and then Sorted_Between (K, Lo, Hi),
     Post =>
       (for all P in V'Range => (if P not in Lo .. Hi then V (P) = V'Old (P)))
       and then (for all P in Lo .. Hi =>
                   V (P) >= Lo - 1
                   and then V (P) < P
                   and then V (V (P) + 1) = V (P))
       and then (for all P in Lo .. Hi =>
                   (for all Q in Lo .. Hi =>
                      (V (P) <= V (Q)) = (K (P) <= K (Q))))
       and then (if Split'Old then Split)
       and then (if not Split then (for all P in Lo .. Hi => K (P) = K (Lo)))
       and then (if Distinct
                 then
                   Distinct'Old
                   and then (for all P in Lo .. Hi => V (P) = P - 1));

   procedure Renumber_Group
     (V               : in out Keys;
      K               : Keys;
      Lo, Hi          : Positive;
      Split, Distinct : in out Boolean)
   is
      Head : Natural := Lo - 1;
   begin
      for I in Lo + 1 .. Hi loop
         if K (I) /= K (I - 1) then
            Head := I - 1;
            Split := True;
         else
            Distinct := False;
         end if;
         V (I) := Head;
         pragma Loop_Invariant (Head = V (I));
         pragma
           Loop_Invariant
             (for all P in V'Range =>
                (if P not in Lo .. I then V (P) = V'Loop_Entry (P)));
         pragma
           Loop_Invariant
             (for all P in Lo .. I =>
                V (P) >= Lo - 1
                and then V (P) < P
                and then V (V (P) + 1) = V (P));
         pragma
           Loop_Invariant
             (for all P in Lo .. I =>
                (for all Q in Lo .. I => (V (P) <= V (Q)) = (K (P) <= K (Q))));
         pragma Loop_Invariant (if Split'Loop_Entry then Split);
         pragma
           Loop_Invariant
             (if not Split then (for all P in Lo .. I => K (P) = K (Lo)));
         pragma
           Loop_Invariant
             (if Distinct
                then
                  Distinct'Loop_Entry
                  and then (for all P in Lo .. I => V (P) = P - 1));
      end loop;
   end Renumber_Group;

   --  Two elements of one class are both in a group.
   procedure Group_Members (V : Keys)
   with
     Ghost,
     Pre  => Runs (V),
     Post =>
       (for all P in V'Range =>
          (for all Q in V'Range =>
             (if P /= Q and then V (P) = V (Q) then In_Group (V, P))));

   procedure Group_Members (V : Keys) is
   begin
      for P in V'Range loop
         for Q in V'Range loop
            if P < Q and then V (P) = V (Q) then
               pragma Assert (V (P) <= V (P + 1) and then V (P + 1) <= V (Q));
            elsif Q < P and then V (P) = V (Q) then
               pragma Assert (V (Q) <= V (P - 1) and then V (P - 1) <= V (P));
            end if;
            pragma
              Loop_Invariant
                (for all B in V'First .. Q =>
                   (if P /= B and then V (P) = V (B) then In_Group (V, P)));
         end loop;
         pragma
           Loop_Invariant
             (for all A in V'First .. P =>
                (for all B in V'Range =>
                   (if A /= B and then V (A) = V (B) then In_Group (V, A))));
      end loop;
   end Group_Members;

   --  The second keys of I .. J, in the order of SA.
   procedure Read_Keys
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : Mapping;
      Along  : in out Keys;
      I, J   : Positive;
      H      : Positive)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
       and then (if Single
                 then
                   (for all P in 1 .. S'Length =>
                      F (P).First = 1 and then F (P).Length = S'Length))
       and then R'First = 1
       and then R'Length = S'Length
       and then SA'First = 1
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then Along'First = 1
       and then Along'Length = S'Length
       and then I <= J
       and then J <= S'Length,
     Post =>
       (for all Q in I .. J => Along (Q) = R (Jump (S, F, SA (Q), H)))
       and then (for all Q in 1 .. S'Length =>
                   (if Q not in I .. J then Along (Q) = Along'Old (Q)));

   procedure Read_Keys
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : Mapping;
      Along  : in out Keys;
      I, J   : Positive;
      H      : Positive)
   is
      N : constant Positive := S'Length;
      D : constant Natural := Reduce (H, N);
   begin
      for P in I .. J loop
         if Single then
            Jump_Single (S, F, SA (P), H);
            Along (P) :=
              R (if SA (P) + D <= N then SA (P) + D else SA (P) + D - N);
         else
            Along (P) := R (Jump (S, F, SA (P), H));
         end if;
         pragma
           Loop_Invariant
             (for all Q in I .. P => Along (Q) = R (Jump (S, F, SA (Q), H)));
         pragma
           Loop_Invariant
             (for all Q in 1 .. N =>
                (if Q not in I .. P then Along (Q) = Along'Loop_Entry (Q)));
      end loop;
   end Read_Keys;

   --  Reads the second keys of the group I .. J of class I - 1, and sorts
   --  the group by them.
   procedure Sort_Run
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : in out Mapping;
      Along  : in out Keys;
      I, J   : Positive;
      H      : Positive)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
       and then (if Single
                 then
                   (for all P in 1 .. S'Length =>
                      F (P).First = 1 and then F (P).Length = S'Length))
       and then R'First = 1
       and then R'Length = S'Length
       and then (for all X of R => X < S'Length)
       and then SA'First = 1
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then Along'First = 1
       and then Along'Length = S'Length
       and then I < J
       and then J <= S'Length
       and then (for all P in I .. J => R (SA (P)) = I - 1),
     Post =>
       Permutation (SA)
       and then (for all P in I .. J =>
                   Along (P) = R (Jump (S, F, SA (P), H))
                   and then R (SA (P)) = I - 1)
       and then Sorted_Between (Along, I, J)
       and then (for all P in 1 .. S'Length =>
                   (if P not in I .. J
                    then
                      SA (P) = SA'Old (P) and then Along (P) = Along'Old (P)));

   procedure Sort_Run
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : in out Mapping;
      Along  : in out Keys;
      I, J   : Positive;
      H      : Positive) is
   begin
      Read_Keys (S, F, Single, R, SA, Along, I, J, H);
      Sort_Group (SA, Along, I, J, S, F, H, R, I - 1);
   end Sort_Run;

   --  The first scan of a sparse round: reads the second key of every
   --  element of a group, and sorts each group by it.
   procedure Sort_Groups
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : in out Mapping;
      V      : Keys;
      Skip   : Mapping;
      Along  : in out Keys;
      H      : Positive)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
       and then (if Single
                 then
                   (for all P in 1 .. S'Length =>
                      F (P).First = 1 and then F (P).Length = S'Length))
       and then R'First = 1
       and then R'Length = S'Length
       and then (for all X of R => X < S'Length)
       and then SA'First = 1
       and then SA'Length = S'Length
       and then Permutation (SA)
       and then V'First = 1
       and then V'Length = S'Length
       and then (for all P in 1 .. S'Length => V (P) = R (SA (P)))
       and then Runs (V)
       and then Skips (V, Skip)
       and then Along'First = 1
       and then Along'Length = S'Length,
     Post =>
       Permutation (SA)
       and then (for all P in 1 .. S'Length => V (P) = R (SA (P)))
       and then (for all P in 1 .. S'Length =>
                   (if In_Group (V, P)
                    then Along (P) = R (Jump (S, F, SA (P), H))))
       and then (for all P in 1 .. S'Length =>
                   (for all Q in P .. S'Length =>
                      (if V (P) = V (Q) then Along (P) <= Along (Q))));

   procedure Sort_Groups
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : in out Mapping;
      V      : Keys;
      Skip   : Mapping;
      Along  : in out Keys;
      H      : Positive)
   is
      N    : constant Positive := S'Length;
      I, J : Positive;
   begin
      I := 1;
      while I <= N loop
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (for all P in 1 .. N => V (P) = R (SA (P)));
         pragma Loop_Invariant (I = 1 or else V (I - 1) /= V (I));
         pragma
           Loop_Invariant
             (for all P in 1 .. I - 1 =>
                (if In_Group (V, P)
                 then Along (P) = R (Jump (S, F, SA (P), H))));
         pragma
           Loop_Invariant
             (for all P in 1 .. I - 1 =>
                (for all Q in P .. I - 1 =>
                   (if V (P) = V (Q) then Along (P) <= Along (Q))));
         pragma
           Loop_Invariant (for all P in I .. N => SA (P) = SA'Loop_Entry (P));
         pragma Loop_Variant (Increases => I);
         Run_Head (V, I);
         pragma Assert (for all P in 1 .. I - 1 => V (P) < I - 1);
         if I < N and then V (I + 1) = V (I) then
            J := I + 1;
            loop
               pragma Loop_Invariant (J in I + 1 .. N);
               pragma Loop_Invariant (for all P in I .. J => V (P) = V (I));
               pragma Loop_Variant (Increases => J);
               exit when J = N or else V (J + 1) /= V (I);
               J := J + 1;
            end loop;
            pragma Assert (for all P in I .. J => V (P) = I - 1);
            pragma Assert (if J < N then V (J + 1) > I - 1);
            declare
               A0 : constant Keys := Along
               with Ghost;
            begin
               Sort_Run (S, F, Single, R, SA, Along, I, J, H);
               pragma Assert (for all P in 1 .. I - 1 => Along (P) = A0 (P));
            end;
            pragma Assert (Sorted_Between (Along, I, J));
         else
            if I < N then
               Run_Head (V, I + 1);
            end if;
            pragma Assert (Alone (V, I));
            J := Skip (I);
            pragma Assert (for all X in I .. J => Alone (V, X));
            pragma Assert (for all X in I .. J => V (X) = X - 1);
            pragma Assert (for all X in I .. J => not In_Group (V, X));
            pragma Assert (if J < N then V (J + 1) = J);
            pragma
              Assert
                (for all P in I .. J =>
                   (for all Q in P .. J => (if V (P) = V (Q) then P = Q)));
         end if;
         pragma
           Assert
             (for all P in I .. J =>
                (for all Q in P .. J =>
                   (if V (P) = V (Q) then Along (P) <= Along (Q))));
         pragma
           Assert
             (for all P in 1 .. I - 1 =>
                (for all Q in I .. J => V (P) /= V (Q)));
         pragma
           Assert
             (for all P in 1 .. I - 1 =>
                (for all Q in P .. I - 1 =>
                   (if V (P) = V (Q) then Along (P) <= Along (Q))));
         pragma
           Assert
             (for all P in 1 .. J =>
                (for all Q in P .. J =>
                   (if V (P) = V (Q) then Along (P) <= Along (Q))));
         I := J + 1;
      end loop;
   end Sort_Groups;

   --  Numbers one sorted group, spreads its ranks, and restarts the skips of
   --  its elements.
   procedure Number_Group
     (SA    : Mapping;
      V     : in out Keys;
      Skip  : in out Mapping;
      Along : Keys;
      R     : in out Keys;
      I, J  : Positive;
      Split : in out Boolean;
      Apart : out Boolean)
   with
     Pre  =>
       Permutation (SA)
       and then V'First = 1
       and then V'Length = SA'Length
       and then Skip'First = 1
       and then Skip'Length = SA'Length
       and then Along'First = 1
       and then Along'Length = SA'Length
       and then R'First = 1
       and then R'Length = SA'Length
       and then I < J
       and then J <= SA'Length
       and then (for all P in I .. J => V (P) = I - 1)
       and then Sorted_Between (Along, I, J),
     Post =>
       (for all P in SA'Range =>
          (if P not in I .. J
           then
             V (P) = V'Old (P)
             and then Skip (P) = Skip'Old (P)
             and then R (SA (P)) = R'Old (SA (P))))
       and then (for all P in I .. J =>
                   V (P) >= I - 1
                   and then V (P) < P
                   and then V (V (P) + 1) = V (P)
                   and then R (SA (P)) = V (P)
                   and then Skip (P) = P)
       and then (for all P in I .. J =>
                   (for all Q in I .. J =>
                      (V (P) <= V (Q)) = (Along (P) <= Along (Q))))
       and then (if Split'Old then Split)
       and then (if not Split
                 then (for all P in I .. J => Along (P) = Along (I)))
       and then (if Apart then (for all P in I .. J => V (P) = P - 1));

   procedure Number_Group
     (SA    : Mapping;
      V     : in out Keys;
      Skip  : in out Mapping;
      Along : Keys;
      R     : in out Keys;
      I, J  : Positive;
      Split : in out Boolean;
      Apart : out Boolean) is
   begin
      Apart := True;
      Renumber_Group (V, Along, I, J, Split, Apart);
      for P in I .. J loop
         R (SA (P)) := V (P);
         Skip (P) := P;
         pragma Loop_Invariant (for all Q in I .. P => R (SA (Q)) = V (Q));
         pragma
           Loop_Invariant
             (for all Q in SA'Range =>
                (if Q not in I .. P then R (SA (Q)) = R'Loop_Entry (SA (Q))));
         pragma Loop_Invariant (for all Q in I .. P => Skip (Q) = Q);
         pragma
           Loop_Invariant
             (for all Q in SA'Range =>
                (if Q not in I .. P then Skip (Q) = Skip'Loop_Entry (Q)));
      end loop;
   end Number_Group;

   --  After a group is numbered, Skip still leads over stretches of
   --  elements alone in their class: those before the group end before it,
   --  and each element of the group now skips only itself.
   procedure Skips_Kept
     (V0, V1 : Keys; Skip0, Skip1 : Mapping; I, J : Positive)
   with
     Ghost,
     Pre  =>
       V0'First = 1
       and then V0'Last <= Max_Length
       and then V1'First = 1
       and then V1'Last = V0'Last
       and then Skips (V0, Skip0)
       and then Skip1'First = 1
       and then Skip1'Last = V0'Last
       and then I < J
       and then J <= V0'Last
       and then V0 (I) = I - 1
       and then V0 (I + 1) = I - 1
       and then V1 (I) = I - 1
       and then (for all P in V0'Range =>
                   (if P not in I .. J
                    then V1 (P) = V0 (P) and then Skip1 (P) = Skip0 (P)))
       and then (for all P in I .. J => Skip1 (P) = P),
     Post => Skips (V1, Skip1);

   procedure Skips_Kept
     (V0, V1 : Keys; Skip0, Skip1 : Mapping; I, J : Positive) is
   begin
      pragma Assert (for all P in I .. J => Skip1 (P) = P);
      pragma Assert (not Alone (V0, I));
      pragma
        Assert
          (for all P in 1 .. I - 1 => (if Alone (V0, P) then Skip0 (P) < I));
      pragma Assert (for all P in 1 .. I - 1 => Alone (V1, P) = Alone (V0, P));
      pragma
        Assert
          (for all P in J + 1 .. V0'Last => Alone (V1, P) = Alone (V0, P));
   end Skips_Kept;

   --  Ranks that compare as pairs on 1 .. I - 1 and on I .. J, and are
   --  ordered between the two, compare as pairs on 1 .. J.
   procedure Order_Extend (V, Old, Along : Keys; I, J : Positive)
   with
     Ghost,
     Pre  =>
       V'First = 1
       and then Old'First = 1
       and then Old'Last = V'Last
       and then Along'First = 1
       and then Along'Last = V'Last
       and then I <= J
       and then J <= V'Last
       and then (for all P in 1 .. I - 1 =>
                   (for all Q in 1 .. I - 1 =>
                      (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)))
       and then (for all P in I .. J =>
                   (for all Q in I .. J =>
                      (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)))
       and then (for all P in 1 .. I - 1 =>
                   (for all Q in I .. J =>
                      V (P) < V (Q)
                      and then Pair_LE (Old, Along, P, Q)
                      and then not Pair_LE (Old, Along, Q, P))),
     Post =>
       (for all P in 1 .. J =>
          (for all Q in 1 .. J =>
             (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));

   procedure Order_Extend (V, Old, Along : Keys; I, J : Positive) is null;

   --  A numbered group compares as pairs: its first keys are all equal.
   procedure Group_Order (V, Old, Along : Keys; I, J : Positive)
   with
     Ghost,
     Pre  =>
       V'First = 1
       and then Old'First = 1
       and then Old'Last = V'Last
       and then Along'First = 1
       and then Along'Last = V'Last
       and then I <= J
       and then J <= V'Last
       and then (for all P in I .. J => Old (P) = I - 1)
       and then (for all P in I .. J =>
                   (for all Q in I .. J =>
                      (V (P) <= V (Q)) = (Along (P) <= Along (Q)))),
     Post =>
       (for all P in I .. J =>
          (for all Q in I .. J =>
             (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));

   procedure Group_Order (V, Old, Along : Keys; I, J : Positive) is null;

   --  A stretch of elements alone in their classes keeps its ranks, which
   --  compare as pairs.
   procedure Stretch_Order (V, Old, Along : Keys; I, J : Positive)
   with
     Ghost,
     Pre  =>
       V'First = 1
       and then Old'First = 1
       and then Old'Last = V'Last
       and then Along'First = 1
       and then Along'Last = V'Last
       and then I <= J
       and then J <= V'Last
       and then (for all P in I .. J =>
                   V (P) = P - 1 and then Old (P) = P - 1),
     Post =>
       (for all P in I .. J =>
          V (P) >= Old (P) and then V (P) < P and then V (V (P) + 1) = V (P))
       and then (for all P in I .. J =>
                   (for all Q in I .. J =>
                      (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));

   procedure Stretch_Order (V, Old, Along : Keys; I, J : Positive) is null;

   --  Classes that met a single second key on 1 .. I - 1 and on I .. J, and
   --  none on both, met a single one on 1 .. J.
   procedure Unsplit_Extend (Old, Along : Keys; I, J : Positive)
   with
     Ghost,
     Pre  =>
       Old'First = 1
       and then Along'First = 1
       and then Along'Last = Old'Last
       and then I <= J
       and then J <= Old'Last
       and then (for all P in 1 .. I - 1 =>
                   (for all Q in 1 .. I - 1 =>
                      (if Old (P) = Old (Q) then Along (P) = Along (Q))))
       and then (for all P in I .. J =>
                   (for all Q in I .. J =>
                      (if Old (P) = Old (Q) then Along (P) = Along (Q))))
       and then (for all P in 1 .. I - 1 =>
                   (for all Q in I .. J => Old (P) /= Old (Q))),
     Post =>
       (for all P in 1 .. J =>
          (for all Q in 1 .. J =>
             (if Old (P) = Old (Q) then Along (P) = Along (Q))));

   procedure Unsplit_Extend (Old, Along : Keys; I, J : Positive) is null;

   --  A stretch of elements alone in their class can be skipped from its
   --  start.
   procedure Skips_Close
     (V : Keys; Skip0, Skip1 : Mapping; First, Last : Positive)
   with
     Ghost,
     Pre  =>
       V'First = 1
       and then Skips (V, Skip0)
       and then Skip1'First = 1
       and then Skip1'Last = V'Last
       and then First <= Last
       and then Last <= V'Last
       and then (for all X in First .. Last => Alone (V, X))
       and then Skip1 (First) = Last
       and then (for all P in V'Range =>
                   (if P /= First then Skip1 (P) = Skip0 (P))),
     Post => Skips (V, Skip1);

   procedure Skips_Close
     (V : Keys; Skip0, Skip1 : Mapping; First, Last : Positive)
   is null;

   --  A group numbered into classes of one leaves each element alone.
   procedure Apart_Alone (V : Keys; I, J : Positive)
   with
     Ghost,
     Pre  =>
       V'First = 1
       and then I <= J
       and then J <= V'Last
       and then (for all P in I .. J => V (P) = P - 1)
       and then (J = V'Last or else V (J + 1) = J),
     Post => (for all X in I .. J => Alone (V, X));

   procedure Apart_Alone (V : Keys; I, J : Positive) is null;

   --  The second scan of a sparse round: numbers the classes of each sorted
   --  group as runs, and spreads its ranks. Its contract is Dense_Runs's,
   --  with the ranks spread: the second keys of elements alone in their
   --  class are never read.
   procedure Renumber_Groups
     (SA              : Mapping;
      V               : in out Keys;
      Skip            : in out Mapping;
      Along           : Keys;
      R               : in out Keys;
      Split, Distinct : out Boolean)
   with
     Pre  =>
       Permutation (SA)
       and then V'First = 1
       and then V'Length = SA'Length
       and then Runs (V)
       and then Skips (V, Skip)
       and then Along'First = 1
       and then Along'Length = SA'Length
       and then R'First = 1
       and then R'Length = SA'Length
       and then (for all P in SA'Range => V (P) = R (SA (P)))
       and then (for all P in SA'Range =>
                   (for all Q in P .. SA'Last =>
                      (if V (P) = V (Q) then Along (P) <= Along (Q)))),
     Post =>
       Runs (V)
       and then Skips (V, Skip)
       and then (for all P in SA'Range => R (SA (P)) = V (P))
       and then (for all P in SA'Range =>
                   (for all Q in SA'Range =>
                      (V (P) <= V (Q)) = Pair_LE (V'Old, Along, P, Q)))
       and then (if Distinct then (for all P in SA'Range => V (P) = P - 1))
       and then (if not Split
                 then
                   (for all P in SA'Range =>
                      (for all Q in SA'Range =>
                         (if V'Old (P) = V'Old (Q)
                          then Along (P) = Along (Q)))));

   procedure Renumber_Groups
     (SA              : Mapping;
      V               : in out Keys;
      Skip            : in out Mapping;
      Along           : Keys;
      R               : in out Keys;
      Split, Distinct : out Boolean)
   is
      N       : constant Natural := SA'Length;
      Old     : constant Keys := V
      with Ghost;
      I, J    : Positive;
      --  Where the current stretch of elements alone in their class starts,
      --  or 0.
      Stretch : Natural := 0;
      --  The group being numbered split into elements alone in their class.
      Apart   : Boolean;
   begin
      Distinct := True;
      Split := False;
      I := 1;
      while I <= N loop
         pragma Loop_Invariant (Skips (V, Skip));
         pragma
           Loop_Invariant
             (if Stretch /= 0
                then
                  Stretch < I
                  and then (for all X in Stretch .. I - 1 => Alone (V, X)));
         pragma Loop_Invariant (I = 1 or else Old (I - 1) /= Old (I));
         pragma Loop_Invariant (for all P in I .. N => V (P) = Old (P));
         pragma Loop_Invariant (for all P in I .. N => R (SA (P)) = Old (P));
         pragma Loop_Invariant (for all P in 1 .. I - 1 => R (SA (P)) = V (P));
         pragma
           Loop_Invariant
             (for all P in 1 .. I - 1 =>
                V (P) >= Old (P)
                and then V (P) < P
                and then V (V (P) + 1) = V (P));
         pragma
           Loop_Invariant
             (for all P in 1 .. I - 1 =>
                (for all Q in P .. I - 1 => V (P) <= V (Q)));
         pragma
           Loop_Invariant
             (for all P in 1 .. I - 1 =>
                (for all Q in 1 .. I - 1 =>
                   (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));
         pragma
           Loop_Invariant
             (if not Split
                then
                  (for all P in 1 .. I - 1 =>
                     (for all Q in 1 .. I - 1 =>
                        (if Old (P) = Old (Q) then Along (P) = Along (Q)))));
         pragma
           Loop_Invariant
             (if Distinct then (for all P in 1 .. I - 1 => V (P) = P - 1));
         pragma Loop_Variant (Increases => I);
         declare
            --  The ranks as this iteration starts.
            Before : constant Keys := V
            with Ghost;
         begin
            Run_Head (Old, I);
            pragma Assert (for all P in 1 .. I - 1 => Old (P) < I - 1);
            pragma
              Assert
                (for all P in 1 .. I - 1 =>
                   (for all Q in P .. I - 1 => V (P) <= V (Q)));
            if I < N and then V (I + 1) = V (I) then
               J := I + 1;
               loop
                  pragma Loop_Invariant (J in I + 1 .. N);
                  pragma
                    Loop_Invariant (for all P in I .. J => Old (P) = Old (I));
                  pragma
                    Loop_Invariant
                      (for all P in J + 1 .. N => V (P) = Old (P));
                  pragma Loop_Variant (Increases => J);
                  exit when J = N or else V (J + 1) /= V (I);
                  J := J + 1;
               end loop;
               pragma Assert (for all P in I .. J => Old (P) = I - 1);
               pragma Assert (if J < N then Old (J + 1) > I - 1);
               pragma Assert (Sorted_Between (Along, I, J));
               if J < N then
                  Run_Head (Old, J + 1);
               end if;
               declare
                  V0    : constant Keys := V
                  with Ghost;
                  Skip0 : constant Mapping := Skip
                  with Ghost;
               begin
                  Number_Group (SA, V, Skip, Along, R, I, J, Split, Apart);
                  Skips_Kept (V0, V, Skip0, Skip, I, J);
                  Group_Order (V, Old, Along, I, J);
                  pragma Assert (for all P in 1 .. I - 1 => V (P) = V0 (P));
                  pragma
                    Assert
                      (for all P in 1 .. I - 1 =>
                         (for all Q in 1 .. I - 1 =>
                            (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));
                  pragma
                    Assert
                      (for all X in 1 .. I - 1 =>
                         Alone (V, X) = Alone (V0, X));
               end;
               Distinct := Distinct and then Apart;
               pragma Assert (if J < N then V (J + 1) = J);
               pragma
                 Assert
                   (if Stretch /= 0
                      then (for all X in Stretch .. I - 1 => Alone (V, X)));
               if Apart then
                  Apart_Alone (V, I, J);
                  if Stretch = 0 then
                     Stretch := I;
                  end if;
               elsif Stretch /= 0 then
                  declare
                     Skip0 : constant Mapping := Skip
                     with Ghost;
                  begin
                     Skip (Stretch) := I - 1;
                     Skips_Close (V, Skip0, Skip, Stretch, I - 1);
                  end;
                  Stretch := 0;
               end if;
               pragma Assert (Skips (V, Skip));
               pragma
                 Assert
                   (if Stretch /= 0
                      then
                        Stretch <= J
                        and then (for all X in Stretch .. J => Alone (V, X)));
            else
               if I < N then
                  Run_Head (Old, I + 1);
               end if;
               pragma Assert (Alone (V, I));
               J := Skip (I);
               pragma Assert (for all X in I .. J => Alone (V, X));
               pragma Assert (for all X in I .. J => V (X) = X - 1);
               pragma Assert (for all X in I .. J => Old (X) = X - 1);
               pragma Assert (if J < N then Old (J + 1) = J);
               Stretch_Order (V, Old, Along, I, J);
               pragma
                 Assert
                   (for all P in 1 .. I - 1 =>
                      (for all Q in 1 .. I - 1 =>
                         (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));
               if Stretch = 0 then
                  Stretch := I;
               end if;
               pragma
                 Assert
                   (Stretch <= J
                      and then (for all X in Stretch .. J => Alone (V, X)));
            end if;
            pragma
              Assert
                (for all P in I .. J =>
                   V (P) >= I - 1
                   and then V (P) < P
                   and then V (V (P) + 1) = V (P));
            pragma Assert (for all P in 1 .. I - 1 => V (P) < I - 1);
            pragma
              Assert
                (for all P in I .. J =>
                   (for all Q in P .. J => Pair_LE (Old, Along, P, Q)));
            pragma
              Assert
                (for all P in 1 .. I - 1 =>
                   (for all Q in I .. J =>
                      V (P) < V (Q)
                      and then Pair_LE (Old, Along, P, Q)
                      and then not Pair_LE (Old, Along, Q, P)));
            pragma
              Assert
                (for all P in I .. J =>
                   (for all Q in I .. J =>
                      (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));
            pragma Assert (for all P in 1 .. I - 1 => V (P) = Before (P));
            pragma
              Assert
                (for all P in 1 .. I - 1 =>
                   (for all Q in 1 .. I - 1 =>
                      (V (P) <= V (Q)) = Pair_LE (Old, Along, P, Q)));
            Order_Extend (V, Old, Along, I, J);
            pragma
              Assert
                (for all P in 1 .. I - 1 =>
                   (for all Q in I .. J => Old (P) /= Old (Q)));
            if not Split then
               pragma
                 Assert
                   (for all P in I .. J =>
                      (for all Q in I .. J =>
                         (if Old (P) = Old (Q) then Along (P) = Along (Q))));
               Unsplit_Extend (Old, Along, I, J);
            end if;
            pragma
              Assert
                (for all P in 1 .. J =>
                   (for all Q in P .. J => V (P) <= V (Q)));
            pragma
              Assert
                (for all P in 1 .. J =>
                   V (P) < P and then V (V (P) + 1) = V (P));
            pragma Assert (Skips (V, Skip));
            pragma
              Assert
                (if Stretch /= 0
                   then
                     Stretch <= J
                     and then (for all X in Stretch .. J => Alone (V, X)));
         end;
         I := J + 1;
      end loop;
      if Stretch /= 0 then
         Skip (Stretch) := N;
      end if;
   end Renumber_Groups;

   --  Pairs read in the order of SA compare as the same pairs by position:
   --  the second keys that differ from Second are never compared.
   procedure Pair_Translate (Mid, Along, Old_R, Second : Keys; Inv : Mapping)
   with
     Ghost,
     Pre  =>
       Old_R'First = 1
       and then Second'First = 1
       and then Second'Last = Old_R'Last
       and then Mid'First = 1
       and then Mid'Last = Old_R'Last
       and then Along'First = 1
       and then Along'Last = Old_R'Last
       and then Inv'First = 1
       and then Inv'Last = Old_R'Last
       and then (for all X of Inv => X in Old_R'Range)
       and then (for all A in Old_R'Range => Mid (Inv (A)) = Old_R (A))
       and then (for all A in Old_R'Range =>
                   (for all B in Old_R'Range =>
                      (if A /= B and then Old_R (A) = Old_R (B)
                       then Along (Inv (A)) = Second (A)))),
     Post =>
       (for all A in Old_R'Range =>
          (for all B in Old_R'Range =>
             Pair_LE (Mid, Along, Inv (A), Inv (B))
             = Pair_LE (Old_R, Second, A, B)));

   procedure Pair_Translate (Mid, Along, Old_R, Second : Keys; Inv : Mapping)
   is null;

   --  One round that sorts only the classes with several elements, each by
   --  its second key, in place in SA. It keeps Double's contract. The first
   --  scan reads the second keys and sorts every group. Ranks change only in
   --  the second, so every key is read at H letters.
   procedure Sparse_Double
     (S        : String;
      F        : Table;
      Single   : Boolean;
      R        : in out Keys;
      SA       : in out Mapping;
      V        : in out Keys;
      Skip     : in out Mapping;
      Along    : in out Keys;
      H        : Positive;
      Distinct : out Boolean;
      Split    : out Boolean)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then H <= 2 * Max_Length
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
       and then Runs (V)
       and then Skips (V, Skip)
       and then Along'First = 1
       and then Along'Length = S'Length,
     Post =>
       Ranked (S, F, R, 2 * H)
       and then Permutation (SA)
       and then (for all P in 1 .. S'Length => V (P) = R (SA (P)))
       and then Runs (V)
       and then Skips (V, Skip)
       and then (if Distinct then Distinct_Keys (R))
       and then (if Distinct
                 then (for all P in 1 .. S'Length => V (P) = P - 1))
       and then (if not Split then Closed (S, F, H));

   procedure Sparse_Double
     (S        : String;
      F        : Table;
      Single   : Boolean;
      R        : in out Keys;
      SA       : in out Mapping;
      V        : in out Keys;
      Skip     : in out Mapping;
      Along    : in out Keys;
      H        : Positive;
      Distinct : out Boolean;
      Split    : out Boolean)
   is
      N      : constant Positive := S'Length;
      Old_R  : constant Keys := R
      with Ghost;
      Mid    : constant Keys := V
      with Ghost;
      Second : Keys (1 .. N) := (others => 0)
      with Ghost;
   begin
      pragma Assert (Ranked (S, F, Old_R, H));
      Sort_Groups (S, F, Single, R, SA, V, Skip, Along, H);
      for A in 1 .. N loop
         Second (A) := R (Jump (S, F, A, H));
         pragma
           Loop_Invariant
             (for all B in 1 .. A => Second (B) = R (Jump (S, F, B, H)));
      end loop;
      Group_Members (Mid);
      pragma Assert (for all P in 1 .. N => Mid (P) = Old_R (SA (P)));
      pragma
        Assert
          (for all P in 1 .. N =>
             (if In_Group (Mid, P) then Along (P) = Second (SA (P))));
      Renumber_Groups (SA, V, Skip, Along, R, Split, Distinct);
      declare
         Inv : constant Mapping := Permutations.Inverse (SA)
         with Ghost;
      begin
         pragma Assert (for all A in 1 .. N => R (A) = V (Inv (A)));
         pragma Assert (for all A in 1 .. N => R (A) < N);
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (if A /= B and then Old_R (A) = Old_R (B)
                    then
                      Inv (A) /= Inv (B)
                      and then Mid (Inv (A)) = Mid (Inv (B)))));
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (if A /= B and then Old_R (A) = Old_R (B)
                    then In_Group (Mid, Inv (A)))));
         pragma
           Assert
             (for all A in 1 .. N =>
                (if In_Group (Mid, Inv (A))
                 then Along (Inv (A)) = Second (A)));
         Pair_Translate (Mid, Along, Old_R, Second, Inv);
         Spread_Order (R, V, Mid, Along, Inv);
         pragma
           Assert
             (for all A in 1 .. N =>
                (for all B in 1 .. N =>
                   (R (A) <= R (B)) = Pair_LE (Old_R, Second, A, B)));
         if Distinct then
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
         Closed_Intro (S, F, Old_R, H);
      end if;
   end Sparse_Double;

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
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : Mapping;
      Ties   : Tie_Order;
      Rows   : out Table)
   with
     Relaxed_Initialization => Rows,
     Pre                    =>
       Supported (S)
       and then Cycles (S, F)
       and then S'Length > 0
       and then (if Single
                 then
                   (for all P in 1 .. S'Length =>
                      F (P).First = 1 and then F (P).Length = S'Length))
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
     (S      : String;
      F      : Table;
      Single : Boolean;
      R      : Keys;
      SA     : Mapping;
      Ties   : Tie_Order;
      Rows   : out Table)
   is
      N   : constant Positive := S'Length;
      Inv : constant Mapping := Permutations.Inverse (SA)
      with Ghost;
   begin
      --  A single factor's rows are known without reading its table.
      for I in 1 .. N loop
         if Single then
            pragma Assert (F (SA (I)).Offset = SA (I) - 1);
            Rows (I) := (1, N, SA (I) - 1);
         else
            Rows (I) := F (SA (I));
         end if;
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

   --  Ranks the rows by prefix doubling, up to the full horizon. Rounds
   --  switch to sorting only the classes with several rows once at most a
   --  quarter of the rows are unsettled.
   procedure Rank_All
     (S       : String;
      Factors : Table;
      Start   : Mapping;
      Single  : Boolean;
      Longest : Positive;
      R       : out Keys;
      SA      : out Mapping;
      Settled : out Boolean)
   with
     Pre  =>
       Supported (S)
       and then Cycles (S, Factors)
       and then S'Length > 0
       and then Longest <= S'Length
       and then (for all P in 1 .. S'Length => Factors (P).Length <= Longest)
       and then Start'First = 1
       and then Start'Length = S'Length
       and then (for all P in 1 .. S'Length => Start (P) = Factors (P).First)
       and then (if Single
                 then
                   (for all P in 1 .. S'Length =>
                      Factors (P).First = 1
                      and then Factors (P).Length = S'Length))
       and then R'First = 1
       and then R'Length = S'Length
       and then SA'First = 1
       and then SA'Length = S'Length,
     Post =>
       Ranked (S, Factors, R, 2 * S'Length)
       and then Permutation (SA)
       and then (if Settled
                 then (for all P in 1 .. S'Length => R (SA (P)) = P - 1));

   procedure Rank_All
     (S       : String;
      Factors : Table;
      Start   : Mapping;
      Single  : Boolean;
      Longest : Positive;
      R       : out Keys;
      SA      : out Mapping;
      Settled : out Boolean)
   is
      N       : constant Positive := S'Length;
      --  The ranks in the order of SA.
      V       : Keys (1 .. N);
      Classes : Positive;
      --  The second keys of the groups, in sparse rounds.
      Along   : Keys (1 .. N) := (others => 0);
      --  Stretches of rows alone in their class, in sparse rounds.
      Skip    : Mapping (1 .. N) := (others => 1);
      --  Few enough rows are unsettled to sort only their classes.
      Sparse  : Boolean;
      H       : Positive := 1;
      Split   : Boolean := True;
      --  The horizon of the last round, at which Closed holds once a round
      --  splits nothing.
      Last_H  : Positive := 1
      with Ghost;
   begin
      Initial (S, Factors, R, SA, V, Classes);
      Settled := Classes = N;
      Sparse := N - Classes <= N / 4;
      if Sparse then
         for P in 1 .. N loop
            Skip (P) := P;
            pragma Loop_Invariant (for all Q in 1 .. P => Skip (Q) = Q);
         end loop;
         Skips_Identity (V, Skip);
      end if;
      while H < 2 * Longest and then not Settled and then Split loop
         pragma Loop_Invariant (H < 2 * Longest);
         pragma Loop_Invariant (Last_H <= H);
         pragma Loop_Invariant (Ranked (S, Factors, R, H));
         pragma Loop_Invariant (Permutation (SA));
         pragma Loop_Invariant (for all P in 1 .. N => V (P) = R (SA (P)));
         pragma Loop_Invariant (Runs (V));
         pragma
           Loop_Invariant
             (if Settled then (for all P in 1 .. N => V (P) = P - 1));
         pragma Loop_Invariant (if Settled then Distinct_Keys (R));
         pragma Loop_Invariant (if Sparse then Skips (V, Skip));
         pragma Loop_Variant (Increases => H);
         --  Fewer than N - Classes classes hold several rows, and those
         --  hold fewer than twice as many rows, so at most half of them.
         if Sparse then
            Sparse_Double
              (S, Factors, Single, R, SA, V, Skip, Along, H, Settled, Split);
         else
            Double (S, Factors, Start, Single, R, SA, V, H, Classes, Split);
            Settled := Classes = N;
            Sparse := N - Classes <= N / 4;
            if Sparse then
               for P in 1 .. N loop
                  Skip (P) := P;
                  pragma Loop_Invariant (for all Q in 1 .. P => Skip (Q) = Q);
               end loop;
               Skips_Identity (V, Skip);
            end if;
         end if;
         pragma Assert (if Settled then Distinct_Keys (R));
         pragma
           Assert (if Settled then (for all P in 1 .. N => V (P) = P - 1));
         pragma Assert (if Sparse then Skips (V, Skip));
         pragma Assert (if not Split then Closed (S, Factors, H));
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
   end Rank_All;

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
         --  Where the factor of each position starts.
         Start   : Mapping (1 .. N) := (others => 1);
         --  One factor, as in the classical table: positions move back
         --  without reading the factor table.
         Single  : constant Boolean := Factors (1).Length = N;
         --  All ranks differ.
         Settled : Boolean;
         Longest : Positive := 1;
      begin
         if Single then
            pragma
              Assert
                (for all P in 1 .. N =>
                   Factors (P).First = 1 and then Factors (P).Length = N);
            Longest := N;
         else
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
         end if;
         pragma Assert (for all P in 1 .. N => Factors (P).Length <= Longest);
         pragma Assert (for all P in 1 .. N => Start (P) = Factors (P).First);
         Rank_All (S, Factors, Start, Single, Longest, R, SA, Settled);
         if Settled then
            Read_Off (S, Factors, Single, R, SA, Ties, Rows);
         else
            Lay_Out (S, Factors, R, Ties, Rows);
         end if;
      end;
      return Rows;
   end Sorted_Rows;
end BWT.Doubling;
