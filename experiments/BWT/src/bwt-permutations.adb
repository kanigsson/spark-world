with BWT.Counting;

package body BWT.Permutations with SPARK_Mode is
   function Inverse (Map : Mapping) return Mapping is
      Result : Mapping (1 .. Map'Length) := (others => 1);
      Seen : Counting.Flags (1 .. Map'Length) := (others => False);
   begin
      Counting.All_Clear (Seen);
      for I in Map'Range loop
         pragma Loop_Invariant
           (Counting.Unseen (Seen, Seen'Length) = Map'Length - I + 1);
         pragma Loop_Invariant
           (for all J in Map'Range =>
             (Seen (J) = (for some K in 1 .. I - 1 => Map (K) = J)));
         pragma Loop_Invariant
           (for all J in 1 .. I - 1 => Result (Map (J)) = J);
         pragma Loop_Invariant
           (for all J in Map'Range =>
             Result (J) in Map'Range
               and then (if Seen (J) then Map (Result (J)) = J));
         declare
            Before : constant Counting.Flags := Seen;
         begin
            Result (Map (I)) := I;
            Seen (Map (I)) := True;
            Counting.Marked (Before, Seen, Map (I));
         end;
      end loop;
      pragma Assert (Counting.Unseen (Seen, Seen'Length) = 0);
      return Result;
   end Inverse;

   procedure Swap (Map : in out Mapping; A, B : Positive) is
      Temp : constant Positive := Map (A);
   begin
      Map (A) := Map (B);
      Map (B) := Temp;
   end Swap;
end BWT.Permutations;
