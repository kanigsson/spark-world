package body BWT.Locate
  with SPARK_Mode
is
   function Slot (L : Locator; Row : Positive) return Natural is
      K : constant Natural := Row / FM_Index.Block;
      R : Natural := L.Before (K);
   begin
      for I in K * FM_Index.Block + 1 .. Row loop
         if L.Sampled (I) then
            R := R + 1;
         end if;
         pragma Loop_Invariant (R = Search.Hits (L.Sampled, I));
      end loop;
      return R;
   end Slot;

   function Locate (L : Locator; P : String) return Places is
      Lo, Hi : Natural;
   begin
      FM_Index.Interval (L.Idx, P, Lo, Hi);
      declare
         Size   : constant Natural := Hi - Lo;
         Result : Places (1 .. Size) := (others => 0);
      begin
         for K in Result'Range loop
            Result (K) := Resolve (L, Lo + K, Rate - 1);
            pragma
              Loop_Invariant
                (for all J in 1 .. K =>
                   Result (J) = Resolve (L, Lo + J, Rate - 1));
         end loop;
         return Result;
      end;
   end Locate;

   function Build (S : String; Rows : Table) return Locator is
      N       : constant Natural := S'Length;
      Last    : String (1 .. N) := (others => Character'First);
      Sampled : Flags (1 .. N) := (others => False);
      Count   : Natural := 0;
   begin
      for I in 1 .. N loop
         Last (I) := Letter (S, Rows (I), Rows (I).Length - 1);
         Sampled (I) := Rows (I).Offset mod Rate = 0;
         pragma
           Loop_Invariant
             (for all J in 1 .. I =>
                Last (J) = Letter (S, Rows (J), Rows (J).Length - 1)
                and then Sampled (J) = (Rows (J).Offset mod Rate = 0));
      end loop;
      for I in 1 .. N loop
         if Sampled (I) then
            Count := Count + 1;
         end if;
         pragma Loop_Invariant (Count = Search.Hits (Sampled, I));
         pragma
           Loop_Invariant
             (for all J in 1 .. I => Search.Hits (Sampled, J) <= Count);
      end loop;
      declare
         Total   : constant Natural := Count;
         Result  : Locator (N, N / FM_Index.Block, Total) :=
           (Length  => N,
            Blocks  => N / FM_Index.Block,
            Samples => Total,
            Idx     => FM_Index.Build (Last),
            Sampled => Sampled,
            Before  => (others => 0),
            Value   => (others => 0));
         Running : Natural := 0;
      begin
         for I in 1 .. N loop
            if Sampled (I) then
               Running := Running + 1;
               Result.Value (Running) := Rows (I).First + Rows (I).Offset;
            end if;
            if I mod FM_Index.Block = 0 then
               Result.Before (I / FM_Index.Block) := Running;
            end if;
            pragma Loop_Invariant (Running = Search.Hits (Sampled, I));
            pragma
              Loop_Invariant
                (for all J in 1 .. I => Search.Hits (Sampled, J) <= Running);
            pragma
              Loop_Invariant
                (for all K in 0 .. I / FM_Index.Block =>
                   Result.Before (K)
                   = Search.Hits (Sampled, K * FM_Index.Block));
            pragma
              Loop_Invariant
                (for all J in 1 .. I =>
                   (if Sampled (J)
                    then
                      Result.Value (Search.Hits (Sampled, J))
                      = Rows (J).First + Rows (J).Offset));
            pragma Loop_Invariant (for all V of Result.Value => V <= N);
            pragma Loop_Invariant (Result.Sampled = Sampled);
            pragma
              Loop_Invariant
                (FM_Index.Valid (Result.Idx) and then Result.Idx.Last = Last);
         end loop;
         pragma
           Assert
             (for all I in 1 .. N =>
                (if Sampled (I) then Search.Hits (Sampled, I) >= 1));
         return Result;
      end;
   end Build;

   --  A walk from a row within Fuel steps of a sample ends at its position.
   procedure Resolve_Exact
     (S : String; Rows : Table; L : Locator; Row : Positive; Fuel : Natural)
   with
     Ghost,
     Pre                =>
       Well_Formed (S, Rows)
       and then Valid (L)
       and then Describes (S, Rows, L)
       and then (for all K in 1 .. S'Length =>
                   Rows (Walk (L.Idx.Last, K, 1)) = Previous (Rows (K)))
       and then Row in 1 .. S'Length
       and then Fuel <= Rate
       and then Rows (Row).Offset mod Rate <= Fuel,
     Post               =>
       Resolve (L, Row, Fuel) = Rows (Row).First + Rows (Row).Offset,
     Subprogram_Variant => (Decreases => Fuel);

   procedure Resolve_Exact
     (S : String; Rows : Table; L : Locator; Row : Positive; Fuel : Natural) is
   begin
      if not L.Sampled (Row) then
         declare
            Next : constant Positive := FM_Index.LF (L.Idx, Row);
         begin
            pragma Assert (Rows (Next) = Previous (Rows (Row)));
            pragma Assert (Rows (Row).Offset > 0);
            pragma Assert (Rows (Next).Offset = Rows (Row).Offset - 1);
            pragma
              Assert
                (Rows (Next).Offset mod Rate = Rows (Row).Offset mod Rate - 1);
            Resolve_Exact (S, Rows, L, Next, Fuel - 1);
         end;
      end if;
   end Resolve_Exact;

   procedure Locate_Rows
     (S : String; F, Rows : Table; Ties : Tie_Order; L : Locator; P : String)
   is
      Found : constant Places := Locate (L, P);
      Lo    : constant Natural := Search.Bound (L.Idx.Last, P, 1, True);
   begin
      Search.Matching_Rows (S, F, Rows, Ties, L.Idx.Last, P);
      Search.Count_Rows (S, F, Rows, Ties, L.Idx.Last, P);
      pragma Assert (Found'Length = Search.Count (L.Idx.Last, P));
      for K in Found'Range loop
         Resolve_Exact (S, Rows, L, Lo + K, Rate - 1);
         pragma
           Assert (Found (K) = Rows (Lo + K).First + Rows (Lo + K).Offset);
         pragma Assert (Found (K) in 1 .. S'Length);
         pragma Assert (for some Q in F'Range => Rows (Lo + K) = F (Q));
         pragma Assert (F (Found (K)) = Rows (Lo + K));
         pragma Assert (Search.Occurs (S, Rows (Lo + K), P));
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Found (J) in 1 .. S'Length
                and then F (Found (J)) = Rows (Lo + J)
                and then Search.Occurs (S, F (Found (J)), P));
      end loop;
   end Locate_Rows;

   --  Equal columns take equal LF steps.
   procedure Same_Walk (A, B : String; Row : Positive)
   with
     Ghost,
     Pre  =>
       Supported (A)
       and then Supported (B)
       and then A'Length = B'Length
       and then Row in A'Range
       and then (for all I in A'Range => A (I) = B (I)),
     Post => Walk (A, Row, 1) = Walk (B, Row, 1);

   procedure Same_Walk (A, B : String; Row : Positive) is
   begin
      Walk_Once (A, Row);
      Walk_Once (B, Row);
      for T in 0 .. A'Length loop
         pragma
           Loop_Invariant (Stable_Rank (A, Row, T) = Stable_Rank (B, Row, T));
      end loop;
   end Same_Walk;

   procedure Classical_Locate (S, P : String) is
      Rows : constant Table := Classical_Sorted (S);
      Rots : constant Table := Rotations_Of (S);
      L    : constant Locator := Build (S, Rows);
      E    : constant Classical_Result := Classical_Encode (S);
   begin
      pragma Assert (Doubling.Cycles (S, Rots));
      if S'Length = 0 then
         return;
      end if;
      for I in Rows'Range loop
         pragma Assert (for some Q in Rots'Range => Rows (I) = Rots (Q));
         pragma
           Loop_Invariant (for all J in 1 .. I => Rows (J).Length = S'Length);
      end loop;
      Classical_LF_Exact (S);
      for K in 1 .. S'Length loop
         Same_Walk (L.Idx.Last, E.Last, K);
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Rows (Walk (L.Idx.Last, J, 1)) = Previous (Rows (J)));
      end loop;
      Locate_Rows (S, Rots, Rows, Earlier_First, L, P);
   end Classical_Locate;

   procedure Bijective_Locate (S, P : String) is
      Rows : constant Table := Bijective_Sorted (S);
      L    : constant Locator := Build (S, Rows);
      E    : constant String := Bijective_Encode (S);
   begin
      if S'Length = 0 then
         return;
      end if;
      Bijective_LF_Exact (S);
      for K in 1 .. S'Length loop
         Same_Walk (L.Idx.Last, E, K);
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Rows (Walk (L.Idx.Last, J, 1)) = Previous (Rows (J)));
      end loop;
      Locate_Rows (S, Lyndon_Factors (S), Rows, Later_First, L, P);
   end Bijective_Locate;
end BWT.Locate;
