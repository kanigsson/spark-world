with BWT.Bijective;
with BWT.Bijective_Proofs;
with BWT.Doubling;
with BWT.Onto_Proofs;
with BWT.Ranks;
with BWT.Rotations;
with BWT.Sorting;
with BWT.Matrices;

package body BWT
  with SPARK_Mode
is
   subtype Rotation_Table is BWT.Table;
   subtype Indices is Ranks.Mapping;

   procedure Sort
     (S    : String;
      Rows : in out Rotation_Table;
      Ties : Tie_Order := Earlier_First)
   renames Sorting.Sort;

   function LF (Last : String) return Indices renames Ranks.LF;

   function Walk
     (Last : String; Primary : Positive; Steps : Natural) return Positive
   is (Ranks.Walk (Last, Primary, Steps));

   --  Sorting only permutes rows, so the shape shared by all classical
   --  rotations survives it, and so does the unshifted one.
   procedure Classical_Shape (Rows, Original : Rotation_Table; N : Positive)
   with
     Ghost,
     Global => null,
     Pre    =>
       Same_Rows (Rows, Original)
       and then Original'First = 1
       and then Original'Length = N
       and then (for all R of Original => R.First = 1 and then R.Length = N)
       and then Original (1).Offset = 0,
     Post   =>
       (for all R of Rows => R.First = 1 and then R.Length = N)
       and then (for some J in Rows'Range => Rows (J).Offset = 0);

   procedure Classical_Shape (Rows, Original : Rotation_Table; N : Positive)
   is null;

   function Initial_Rows (S : String) return Rotation_Table
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Initial_Rows'Result'First = 1
       and then Initial_Rows'Result'Last = S'Length
       and then (for all I in Initial_Rows'Result'Range =>
                   Initial_Rows'Result (I) = (1, S'Length, I - 1));

   function Initial_Rows (S : String) return Rotation_Table is
      Rows : Rotation_Table (1 .. S'Length);
   begin
      for I in Rows'Range loop
         Rows (I) := (First => 1, Length => S'Length, Offset => I - 1);
         pragma
           Loop_Invariant
             (for all J in 1 .. I => Rows (J) = (1, S'Length, J - 1));
      end loop;
      return Rows;
   end Initial_Rows;

   function Rotations_Of (S : String) return Table
   is (Initial_Rows (S));

   --  The classical table as specified, by selection sort. The encoder builds
   --  the same table by prefix doubling instead.
   function Classical_Table (S : String) return Rotation_Table
   with
     Ghost,
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Well_Formed (S, Classical_Table'Result)
       and then Distinct (Classical_Table'Result)
       and then Same_Rows (Classical_Table'Result, Rotations_Of (S))
       and then Sorted (S, Classical_Table'Result, Earlier_First)
       and then (for all R of Classical_Table'Result =>
                   R.First = 1 and then R.Length = S'Length)
       and then (if S'Length > 0
                 then
                   (for some J in Classical_Table'Result'Range =>
                      Classical_Table'Result (J).Offset = 0));

   function Classical_Table (S : String) return Rotation_Table is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Sorted);
      Rows : Rotation_Table := Initial_Rows (S);
   begin
      pragma Assert (for all R of Rows => Valid (R, S'Length));
      declare
         Original : constant Rotation_Table := Rows
         with Ghost;
      begin
         Sort (S, Rows);
         if S'Length > 0 then
            Classical_Shape (Rows, Original, S'Length);
         end if;
      end;
      return Rows;
   end Classical_Table;

   function Classical_Rows (S : String) return Table
   is (Classical_Table (S));

   function Lyndon_Factors (S : String) return Table
   is (Bijective.Factor_Rotations (S));

   function Bijective_Rows (S : String) return Table
   is (Bijective.Table_Of (S));

   function Classical_Encode (S : String) return Classical_Result is
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Matrices.Closed);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Sorted);
      Rotations : constant Rotation_Table := Initial_Rows (S);
      pragma Assert (Doubling.Cycles (S, Rotations));
      Rows      : constant Rotation_Table :=
        Doubling.Sorted_Rows (S, Rotations, Earlier_First);
      Result    : Classical_Result (S'Length) :=
        (Length  => S'Length,
         Last    => (others => Character'First),
         Primary => 0);
   begin
      Classical_Rows_Unique (S, Rows);
      if S'Length = 0 then
         return Result;
      end if;
      Classical_Shape (Rows, Rotations, S'Length);
      Matrices.Classical_Closed (S, Rows);
      for I in Rows'Range loop
         Result.Last (I) := Letter (S, Rows (I), Rows (I).Length - 1);
         if Rows (I).Offset = 0 then
            Result.Primary := I;
         end if;
         pragma Loop_Invariant (Result.Primary <= I);
         pragma
           Loop_Invariant
             (if Result.Primary > 0 then Rows (Result.Primary).Offset = 0);
         pragma
           Loop_Invariant
             (for all J in 1 .. I =>
                Result.Last (J) = Letter (S, Rows (J), S'Length - 1));
         pragma
           Loop_Invariant
             ((Result.Primary > 0)
                = (for some J in 1 .. I => Rows (J).Offset = 0));
      end loop;
      Matrices.Classical_Thread (S, Rows, Result.Last, Result.Primary);
      return Result;
   end Classical_Encode;

   function Classical_Decode (Last : String; Primary : Natural) return String
   is
      Map    : constant Indices := LF (Last);
      Result : String (1 .. Last'Length) := (others => Character'First);
      Row    : Natural := Primary;
   begin
      if Last'Length > 0 then
         Ranks.Walk_Step (Last, Primary, 0);
      end if;
      for I in reverse Result'Range loop
         pragma Loop_Invariant (Row in Map'Range);
         pragma Loop_Invariant (Row = Walk (Last, Primary, Last'Length - I));
         pragma
           Loop_Invariant
             (for all K in I + 1 .. Last'Length =>
                Result (K) = Last (Walk (Last, Primary, Last'Length - K)));
         if I > 1 then
            Ranks.Walk_Step (Last, Primary, Last'Length - I);
         end if;
         Result (I) := Last (Row);
         Row := Map (Row);
      end loop;
      return Result;
   end Classical_Decode;

   function Bijective_Encode (S : String) return String
   is (Bijective.Encode (S));

   function Bijective_Decode (Last : String) return String
   is (Bijective.Decode (Last));

   procedure Prove_Bijective_Round_Trip (S : String) is
   begin
      Bijective_Proofs.Round_Trip (S);
   end Prove_Bijective_Round_Trip;

   procedure Prove_Bijective_Onto (Last : String) is
   begin
      Onto_Proofs.Onto (Last);
   end Prove_Bijective_Onto;

   procedure Bijective_LF_Exact (S : String) is
   begin
      Bijective_Proofs.LF_Exact (S);
      for K in 1 .. S'Length loop
         Ranks.Walk_Step (Bijective_Encode (S), K, 0);
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Walk (Bijective_Encode (S), J, 1)
                = LF (Bijective_Encode (S)) (J));
      end loop;
   end Bijective_LF_Exact;

   procedure Classical_LF_Exact (S : String) is
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Matrices.Closed);
      N    : constant Natural := S'Length;
      Rows : constant Rotation_Table := Classical_Table (S);
      Last : constant String := Classical_Encode (S).Last;
   begin
      if N = 0 then
         return;
      end if;
      Classical_Shape (Rows, Initial_Rows (S), N);
      Matrices.Classical_Closed (S, Rows);
      declare
         Map : constant Indices := LF (Last);
      begin
         Matrices.LF_Shifts (S, Rows, Last, Map);
         for K in 1 .. N loop
            Ranks.Walk_Step (Last, K, 0);
            Rotations.Equal_Prefix_Shorter
              (S, Rows (Map (K)), Previous (Rows (K)), 2 * N, N);
            pragma
              Assert
                (Rows (Map (K)) = (1, N, Rows (Map (K)).Offset)
                   and then Previous (Rows (K))
                            = (1, N, Previous (Rows (K)).Offset));
            pragma Assert (Rows (Map (K)) = Previous (Rows (K)));
            pragma
              Loop_Invariant
                (for all J in 1 .. K =>
                   Walk (Last, J, 1) = Map (J)
                   and then Rows (Map (J)) = Previous (Rows (J)));
         end loop;
      end;
   end Classical_LF_Exact;

   procedure Classical_Rows_Unique (S : String; Rows : Table) is
      Canonical : constant Rotation_Table := Classical_Table (S);
   begin
      pragma
        Assert
          (for all I in Rows'Range =>
             (for some J in Canonical'Range => Rows (I) = Canonical (J)));
      pragma
        Assert
          (for all I in Canonical'Range =>
             (for some J in Rows'Range => Canonical (I) = Rows (J)));
      Sorting.Sorted_Unique (S, Canonical, Rows, Earlier_First);
   end Classical_Rows_Unique;

   procedure Bijective_Rows_Unique (S : String; Rows : Table) is
      Canonical : constant Rotation_Table := Bijective.Table_Of (S);
   begin
      Sorting.Same_Rows_Trans (Canonical, Lyndon_Factors (S), Rows);
      Sorting.Sorted_Unique (S, Canonical, Rows, Later_First);
   end Bijective_Rows_Unique;
end BWT;
