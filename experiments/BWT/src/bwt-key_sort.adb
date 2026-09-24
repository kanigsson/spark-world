package body BWT.Key_Sort
  with SPARK_Mode
is
   --  How many elements of K (1 .. Through) are ordered before or at Row.
   function Rank (K : Keys; Row : Positive; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else
         Rank (K, Row, Through - 1)
         + (if Ordered (K, Through, Row) then 1 else 0))
   with
     Ghost,
     Pre                =>
       K'First = 1
       and then K'Length <= Max_Length
       and then Row in K'Range
       and then Through <= K'Length,
     Post               =>
       Rank'Result <= Through
       and then (if Through >= Row then Rank'Result >= 1),
     Subprogram_Variant => (Decreases => Through);

   procedure Strict_Ranks (K : Keys; A, B : Positive)
   with
     Ghost,
     Pre  =>
       K'First = 1
       and then K'Length <= Max_Length
       and then A in K'Range
       and then B in K'Range
       and then A /= B
       and then Ordered (K, A, B),
     Post => Rank (K, A, K'Length) < Rank (K, B, K'Length);

   procedure Strict_Ranks (K : Keys; A, B : Positive) is
   begin
      for I in 0 .. K'Length loop
         pragma Loop_Invariant (Rank (K, A, I) <= Rank (K, B, I));
         pragma
           Loop_Invariant (if I >= B then Rank (K, A, I) < Rank (K, B, I));
      end loop;
   end Strict_Ranks;

   --  Occurrences of C, and of keys below C, among K (1 .. Through).

   function Occ (K : Keys; C : Natural; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else Occ (K, C, Through - 1) + (if K (Through) = C then 1 else 0))
   with
     Ghost,
     Pre                =>
       K'First = 1
       and then K'Length <= Max_Length
       and then Through <= K'Length,
     Post               => Occ'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   function Below (K : Keys; C : Natural; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else Below (K, C, Through - 1) + (if K (Through) < C then 1 else 0))
   with
     Ghost,
     Pre                =>
       K'First = 1
       and then K'Length <= Max_Length
       and then Through <= K'Length,
     Post               => Below'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   procedure Below_First (K : Keys)
   with
     Ghost,
     Pre  => K'First = 1 and then K'Length <= Max_Length,
     Post => Below (K, 0, K'Length) = 0;

   procedure Below_First (K : Keys) is
   begin
      for T in 0 .. K'Length loop
         pragma Loop_Invariant (Below (K, 0, T) = 0);
      end loop;
   end Below_First;

   procedure Below_Next (K : Keys; C : Natural)
   with
     Ghost,
     Pre  =>
       K'First = 1 and then K'Length <= Max_Length and then C < Max_Length,
     Post =>
       Below (K, C + 1, K'Length)
       = Below (K, C, K'Length) + Occ (K, C, K'Length);

   procedure Below_Next (K : Keys; C : Natural) is
   begin
      for T in 0 .. K'Length loop
         pragma
           Loop_Invariant
             (Below (K, C + 1, T) = Below (K, C, T) + Occ (K, C, T));
      end loop;
   end Below_Next;

   --  A row's rank counts the smaller keys, then the equal ones up to it.
   procedure Rank_Split (K : Keys; Row : Positive)
   with
     Ghost,
     Pre  =>
       K'First = 1 and then K'Length <= Max_Length and then Row in K'Range,
     Post =>
       Rank (K, Row, K'Length)
       = Below (K, K (Row), K'Length) + Occ (K, K (Row), Row);

   procedure Rank_Split (K : Keys; Row : Positive) is
   begin
      for T in 0 .. K'Length loop
         pragma
           Loop_Invariant
             (Rank (K, Row, T)
                = Below (K, K (Row), T)
                  + Occ (K, K (Row), Natural'Min (T, Row)));
      end loop;
   end Rank_Split;

   --  Ranks order elements as Ordered does, and so form a permutation.
   procedure Rank_Order (K : Keys; Map : Mapping)
   with
     Ghost,
     Pre  =>
       K'First = 1
       and then K'Length <= Max_Length
       and then Map'First = 1
       and then Map'Length = K'Length
       and then (for all I in K'Range => Map (I) = Rank (K, I, K'Length)),
     Post =>
       Permutation (Map)
       and then (for all I in K'Range =>
                   (for all J in K'Range =>
                      (Ordered (K, I, J) = (Map (I) <= Map (J)))));

   procedure Rank_Order (K : Keys; Map : Mapping) is
   begin
      for I in K'Range loop
         for J in K'Range loop
            if I /= J then
               if Ordered (K, I, J) then
                  Strict_Ranks (K, I, J);
               else
                  Strict_Ranks (K, J, I);
               end if;
            end if;
            pragma
              Loop_Invariant
                (for all L in 1 .. J =>
                   (Ordered (K, I, L) = (Map (I) <= Map (L)))
                   and then (if I /= L then Map (I) /= Map (L)));
         end loop;
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                (for all Q in K'Range =>
                   (Ordered (K, P, Q) = (Map (P) <= Map (Q)))
                   and then (if P /= Q then Map (P) /= Map (Q))));
      end loop;
   end Rank_Order;

   --  One pass counts each key. Prefix sums, in place, turn the counts into
   --  where each key's elements start, and a second pass numbers equal keys
   --  in order of position.
   function Place (K : Keys; Buckets : Positive) return Mapping is
      type Counts is array (Natural range <>) of Natural;
      Map   : Mapping (1 .. K'Length) := (others => 1);
      Count : Counts (0 .. Buckets - 1) := (others => 0);
      Sum   : Natural := 0;
      Size  : Natural;
   begin
      for I in K'Range loop
         Count (K (I)) := Count (K (I)) + 1;
         pragma
           Loop_Invariant
             (for all C in Count'Range => Count (C) = Occ (K, C, I));
      end loop;
      Below_First (K);
      for C in Count'Range loop
         pragma
           Loop_Invariant
             (for all D in 0 .. C - 1 => Count (D) = Below (K, D, K'Length));
         pragma
           Loop_Invariant
             (for all D in C .. Count'Last =>
                Count (D) = Occ (K, D, K'Length));
         pragma Loop_Invariant (Sum = Below (K, C, K'Length));
         Below_Next (K, C);
         Size := Count (C);
         Count (C) := Sum;
         Sum := Sum + Size;
      end loop;
      for I in K'Range loop
         Rank_Split (K, I);
         Count (K (I)) := Count (K (I)) + 1;
         Map (I) := Count (K (I));
         pragma
           Loop_Invariant
             (for all C in Count'Range =>
                Count (C) = Below (K, C, K'Length) + Occ (K, C, I));
         pragma
           Loop_Invariant
             (for all P in 1 .. I => Map (P) = Rank (K, P, K'Length));
      end loop;
      Rank_Order (K, Map);
      return Map;
   end Place;
end BWT.Key_Sort;
