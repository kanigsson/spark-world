package body BWT.FM_Index
  with SPARK_Mode
is
   use BWT.Search;

   procedure Below_First (Last : String)
   with
     Ghost,
     Pre  => Supported (Last),
     Post => Below_Count (Last, Character'First, Last'Length) = 0;

   procedure Below_First (Last : String) is
   begin
      for T in 0 .. Last'Length loop
         pragma Loop_Invariant (Below_Count (Last, Character'First, T) = 0);
      end loop;
   end Below_First;

   procedure Below_Next (Last : String; C : Character)
   with
     Ghost,
     Pre  => Supported (Last) and then C < Character'Last,
     Post =>
       Below_Count (Last, Character'Succ (C), Last'Length)
       = Below_Count (Last, C, Last'Length) + Occ (Last, C, Last'Length);

   procedure Below_Next (Last : String; C : Character) is
   begin
      for T in 0 .. Last'Length loop
         pragma
           Loop_Invariant
             (Below_Count (Last, Character'Succ (C), T)
                = Below_Count (Last, C, T) + Occ (Last, C, T));
      end loop;
   end Below_Next;

   --  A backward step counts the rows ending below C, then those ending in C
   --  up to T.
   procedure Step_Split (Last : String; C : Character; T : Natural)
   with
     Ghost,
     Pre  => Supported (Last) and then T <= Last'Length,
     Post =>
       Hits (Step_Flags (Last, C, T), Last'Length)
       = Below_Count (Last, C, Last'Length) + Occ (Last, C, T);

   procedure Step_Split (Last : String; C : Character; T : Natural) is
   begin
      for X in 0 .. Last'Length loop
         pragma
           Loop_Invariant
             (Hits (Step_Flags (Last, C, T), X)
                = Below_Count (Last, C, X)
                  + Occ (Last, C, Natural'Min (X, T)));
      end loop;
   end Step_Split;

   function Build (Last : String) return Index is
      N       : constant Natural := Last'Length;
      Result  : Index (N, N / Block) :=
        (Length => N,
         Blocks => N / Block,
         Last   => Last,
         Below  => (others => 0),
         Marks  => (others => (others => 0)));
      Running : Counts := (others => 0);
      Sum     : Natural := 0;
   begin
      for I in Last'Range loop
         Running (Last (I)) := Running (Last (I)) + 1;
         if I mod Block = 0 then
            Result.Marks (I / Block) := Running;
         end if;
         pragma
           Loop_Invariant
             (for all C in Character => Running (C) = Occ (Last, C, I));
         pragma
           Loop_Invariant
             (for all K in 0 .. I / Block =>
                (for all C in Character =>
                   Result.Marks (K) (C) = Occ (Last, C, K * Block)));
         pragma Loop_Invariant (Result.Last = Last);
      end loop;
      Below_First (Last);
      for C in Character loop
         Result.Below (C) := Sum;
         pragma
           Loop_Invariant
             (for all D in Character'First .. C =>
                Result.Below (D) = Below_Count (Last, D, N));
         pragma Loop_Invariant (Sum = Below_Count (Last, C, N));
         exit when C = Character'Last;
         Below_Next (Last, C);
         Sum := Sum + Running (C);
      end loop;
      return Result;
   end Build;

   function Rank (Idx : Index; C : Character; T : Natural) return Natural is
      K : constant Natural := T / Block;
      R : Natural := Idx.Marks (K) (C);
   begin
      for I in K * Block + 1 .. T loop
         if Idx.Last (I) = C then
            R := R + 1;
         end if;
         pragma Loop_Invariant (R = Occ (Idx.Last, C, I));
      end loop;
      return R;
   end Rank;

   function Count (Idx : Index; P : String) return Natural is
      Lo : Natural := 0;
      Hi : Natural := Idx.Length;
   begin
      for J in reverse P'Range loop
         pragma Loop_Invariant (Lo = Bound (Idx.Last, P, J + 1, True));
         pragma Loop_Invariant (Hi = Bound (Idx.Last, P, J + 1, False));
         Step_Split (Idx.Last, P (J), Lo);
         Step_Split (Idx.Last, P (J), Hi);
         Lo := Idx.Below (P (J)) + Rank (Idx, P (J), Lo);
         Hi := Idx.Below (P (J)) + Rank (Idx, P (J), Hi);
      end loop;
      pragma Assert (Search.Count (Idx.Last, P) = Hi - Lo);
      return Hi - Lo;
   end Count;
end BWT.FM_Index;
