with BWT.Bijective;
with BWT.Bijective_Proofs;
with BWT.Ranks;
with BWT.Rotations;
with BWT.Sorting;
with BWT.Matrices;

package body BWT
  with SPARK_Mode
is
   use BWT.Rotations;
   subtype Rotation_Table is BWT.Rotations.Table;
   subtype Indices is Ranks.Mapping;

   procedure Sort
     (S : String; Rows : in out Rotation_Table;
      Ties : Tie_Order := Earlier_First)
     renames Sorting.Sort;

   function LF (Last : String) return Indices renames Ranks.LF;

   function Walk (Last : String; Primary : Positive; Steps : Natural)
     return Positive is (Ranks.Walk (Last, Primary, Steps));

   --  Sorting only permutes rows, so the shape shared by all classical
   --  rotations survives it, and so does the unshifted one.
   procedure Classical_Shape (Rows, Original : Rotation_Table; N : Positive)
   with Ghost, Global => null,
     Pre => Sorting.Same_Rows (Rows, Original)
       and then Original'First = 1 and then Original'Length = N
       and then (for all R of Original => R.First = 1 and then R.Length = N)
       and then Original (1).Offset = 0,
     Post => (for all R of Rows => R.First = 1 and then R.Length = N)
       and then (for some J in Rows'Range => Rows (J).Offset = 0);

   procedure Classical_Shape (Rows, Original : Rotation_Table; N : Positive)
   is null;

   function Classical_Encode (S : String) return Classical_Result is
      pragma Annotate
        (GNATprove, Hide_Info, "Expression_Function_Body", Matrices.Closed);
      pragma Annotate
        (GNATprove, Hide_Info, "Expression_Function_Body", Sorting.Sorted);
      Rows   : Rotation_Table (1 .. S'Length);
      Result : Classical_Result (S'Length) :=
        (Length  => S'Length,
         Last    => (others => Character'First),
         Primary => 0);
   begin
      if S'Length = 0 then
         return Result;
      end if;
      for I in Rows'Range loop
         Rows (I) := (First => 1, Length => S'Length, Offset => I - 1);
         pragma Loop_Invariant (Rows (1).Offset = 0);
         pragma Loop_Invariant
           (for all J in 1 .. I => Rows (J).First + Rows (J).Offset = J);
         pragma Loop_Invariant
           (for all J in 1 .. I => Rows (J).First = 1 and then Rows (J).Length = S'Length);
         pragma
           Loop_Invariant (for all J in 1 .. I => Valid (Rows (J), S'Length));
      end loop;
      declare
         Original : constant Rotation_Table := Rows with Ghost;
      begin
         Sort (S, Rows);
         Classical_Shape (Rows, Original, S'Length);
      end;
      Matrices.Classical_Closed (S, Rows);
      for I in Rows'Range loop
         Result.Last (I) := Letter (S, Rows (I), Rows (I).Length - 1);
         if Rows (I).Offset = 0 then
            Result.Primary := I;
         end if;
         pragma Loop_Invariant (Result.Primary <= I);
         pragma Loop_Invariant
           (if Result.Primary > 0 then Rows (Result.Primary).Offset = 0);
         pragma Loop_Invariant
           (for all J in 1 .. I => Result.Last (J) = Letter (S, Rows (J), S'Length - 1));
         pragma Loop_Invariant
           ((Result.Primary > 0) =
              (for some J in 1 .. I => Rows (J).Offset = 0));
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
         pragma Loop_Invariant
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
end BWT;
