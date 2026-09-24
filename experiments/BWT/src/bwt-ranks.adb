package body BWT.Ranks
  with SPARK_Mode
is
   function Rank
     (Last : String; Row : Positive; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else
         Rank (Last, Row, Through - 1)
         + (if Ordered (Last, Through, Row) then 1 else 0));

   procedure Strict_Ranks (Last : String; A, B : Positive) is
   begin
      for I in 0 .. Last'Length loop
         pragma Loop_Invariant (Rank (Last, A, I) <= Rank (Last, B, I));
         pragma
           Loop_Invariant
             (if I >= B then Rank (Last, A, I) < Rank (Last, B, I));
      end loop;
   end Strict_Ranks;

   --  Occurrences of C, and of letters below C, among Last (1 .. Through).

   function Occ
     (Last : String; C : Character; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else Occ (Last, C, Through - 1) + (if Last (Through) = C then 1 else 0))
   with
     Ghost,
     Pre                => Supported (Last) and then Through <= Last'Length,
     Post               => Occ'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   function Below
     (Last : String; C : Character; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else
         Below (Last, C, Through - 1) + (if Last (Through) < C then 1 else 0))
   with
     Ghost,
     Pre                => Supported (Last) and then Through <= Last'Length,
     Post               => Below'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   procedure Below_First (Last : String)
   with
     Ghost,
     Pre  => Supported (Last),
     Post => Below (Last, Character'First, Last'Length) = 0;

   procedure Below_First (Last : String) is
   begin
      for T in 0 .. Last'Length loop
         pragma Loop_Invariant (Below (Last, Character'First, T) = 0);
      end loop;
   end Below_First;

   procedure Below_Next (Last : String; C : Character)
   with
     Ghost,
     Pre  => Supported (Last) and then C < Character'Last,
     Post =>
       Below (Last, Character'Succ (C), Last'Length)
       = Below (Last, C, Last'Length) + Occ (Last, C, Last'Length);

   procedure Below_Next (Last : String; C : Character) is
   begin
      for T in 0 .. Last'Length loop
         pragma
           Loop_Invariant
             (Below (Last, Character'Succ (C), T)
                = Below (Last, C, T) + Occ (Last, C, T));
      end loop;
   end Below_Next;

   --  A row's rank counts the smaller letters, then the equal ones up to it.
   procedure Rank_Split (Last : String; Row : Positive)
   with
     Ghost,
     Pre  => Supported (Last) and then Row in Last'Range,
     Post =>
       Rank (Last, Row, Last'Length)
       = Below (Last, Last (Row), Last'Length) + Occ (Last, Last (Row), Row);

   procedure Rank_Split (Last : String; Row : Positive) is
   begin
      for T in 0 .. Last'Length loop
         pragma
           Loop_Invariant
             (Rank (Last, Row, T)
                = Below (Last, Last (Row), T)
                  + Occ (Last, Last (Row), Natural'Min (T, Row)));
      end loop;
   end Rank_Split;

   --  Ranks order rows as Ordered does, and so form a permutation.
   procedure Rank_Order (Last : String; Map : Mapping)
   with
     Ghost,
     Pre  =>
       Supported (Last)
       and then Map'First = 1
       and then Map'Length = Last'Length
       and then (for all I in Last'Range =>
                   Map (I) = Rank (Last, I, Last'Length)),
     Post =>
       Permutation (Map)
       and then (for all I in Last'Range =>
                   (for all J in Last'Range =>
                      (Ordered (Last, I, J) = (Map (I) <= Map (J)))));

   procedure Rank_Order (Last : String; Map : Mapping) is
   begin
      for I in Last'Range loop
         for J in Last'Range loop
            if I /= J then
               if Ordered (Last, I, J) then
                  Strict_Ranks (Last, I, J);
               else
                  Strict_Ranks (Last, J, I);
               end if;
            end if;
            pragma
              Loop_Invariant
                (for all K in 1 .. J =>
                   (Ordered (Last, I, K) = (Map (I) <= Map (K)))
                   and then (if I /= K then Map (I) /= Map (K)));
         end loop;
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                (for all Q in Last'Range =>
                   (Ordered (Last, P, Q) = (Map (P) <= Map (Q)))
                   and then (if P /= Q then Map (P) /= Map (Q))));
      end loop;
   end Rank_Order;

   --  A counting sort: one pass counts each letter, prefix sums give where
   --  each letter's rows start, and a second pass numbers equal letters in
   --  order of position.
   function LF (Last : String) return Mapping is
      type Counts is array (Character) of Natural;
      Map   : Mapping (1 .. Last'Length) := (others => 1);
      Count : Counts := (others => 0);
      Start : Counts := (others => 0);
   begin
      for I in Last'Range loop
         Count (Last (I)) := Count (Last (I)) + 1;
         pragma
           Loop_Invariant
             (for all C in Character => Count (C) = Occ (Last, C, I));
      end loop;
      Below_First (Last);
      for C in Character loop
         pragma
           Loop_Invariant
             (for all D in Character'First .. C =>
                Start (D) = Below (Last, D, Last'Length));
         exit when C = Character'Last;
         Below_Next (Last, C);
         Start (Character'Succ (C)) := Start (C) + Count (C);
      end loop;
      Count := (others => 0);
      for I in Last'Range loop
         Rank_Split (Last, I);
         Count (Last (I)) := Count (Last (I)) + 1;
         Map (I) := Start (Last (I)) + Count (Last (I));
         pragma
           Loop_Invariant
             (for all C in Character => Count (C) = Occ (Last, C, I));
         pragma
           Loop_Invariant
             (for all P in 1 .. I => Map (P) = Rank (Last, P, Last'Length));
      end loop;
      Rank_Order (Last, Map);
      return Map;
   end LF;

   procedure Walk_Step (Last : String; Primary : Positive; Steps : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Walk);
   begin
      null;
   end Walk_Step;
end BWT.Ranks;
