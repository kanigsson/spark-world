package body BWT.Sorting with SPARK_Mode is
   function Prefix_Sorted (S : String; Rows : Table; Through : Natural)
     return Boolean is
     (for all P in 1 .. Through => (for all Q in P .. Rows'Last =>
       Key_LE (S, Rows (P), Rows (Q))))
   with Ghost, Pre => Well_Formed (S, Rows) and then Through <= Rows'Length;

   procedure Extend_Sorted (S : String; Before, After : Table; Pos, Best : Positive)
   with Ghost, Pre => Well_Formed (S, Before) and then Well_Formed (S, After)
     and then Pos in Before'Range and then Best in Pos .. Before'Last
     and then Prefix_Sorted (S, Before, Pos - 1)
     and then (for all Q in Pos .. Before'Last => Key_LE (S, Before (Best), Before (Q)))
     and then (for all Q in Before'Range => After (Q) =
       (if Q = Pos then Before (Best) elsif Q = Best then Before (Pos) else Before (Q))),
     Post => Prefix_Sorted (S, After, Pos);

   procedure Extend_Sorted (S : String; Before, After : Table; Pos, Best : Positive) is
   begin
      for I in 1 .. Pos loop
         for J in I .. After'Last loop
            pragma Assert (Key_LE (S, After (I), After (J)));
            pragma Loop_Invariant
              (for all Q in I .. J => Key_LE (S, After (I), After (Q)));
         end loop;
         pragma Loop_Invariant (Prefix_Sorted (S, After, I));
      end loop;
   end Extend_Sorted;

   function Find (Rows : Table; R : Rotation) return Positive
   with Ghost, Pre => (for some Q of Rows => Q = R),
     Post => Find'Result in Rows'Range and then Rows (Find'Result) = R;

   function Find (Rows : Table; R : Rotation) return Positive is
   begin
      for I in Rows'Range loop
         if Rows (I) = R then
            return I;
         end if;
         pragma Loop_Invariant (for all J in Rows'First .. I => Rows (J) /= R);
      end loop;
      return Rows'First;
   end Find;

   procedure Compose (A, B, C : Table)
   with Ghost, Pre => Same_Rows (A, B) and then Same_Rows (B, C),
     Post => Same_Rows (A, C);

   procedure Compose (A, B, C : Table) is
   begin
      for I in A'Range loop
         declare
            J : constant Positive := Find (B, A (I));
            K : constant Positive := Find (C, B (J));
            L : constant Positive := Find (B, C (I));
            M : constant Positive := Find (A, B (L));
         begin
            pragma Assert (A (I) = C (K));
            pragma Assert (C (I) = A (M));
         end;
         pragma Loop_Invariant
           (for all P in A'First .. I => (for some Q in C'Range => A (P) = C (Q)));
         pragma Loop_Invariant
           (for all P in C'First .. I => (for some Q in A'Range => C (P) = A (Q)));
      end loop;
      pragma Assert (A'First = C'First and then A'Last = C'Last);
      pragma Assert
        (for all I in A'Range => (for some J in C'Range => A (I) = C (J)));
      pragma Assert
        (for all I in C'Range => (for some J in A'Range => C (I) = A (J)));
      pragma Assert (Same_Rows (A, C));
   end Compose;

   procedure Swap (Rows : in out Table; A, B : Positive)
   with Pre => A in Rows'Range and then B in Rows'Range,
     Post => Same_Rows (Rows, Rows'Old)
       and then Distinct (Rows) = Distinct (Rows'Old)
       and then (for all I in Rows'Range =>
         Rows (I) = (if I = A then Rows'Old (B)
                     elsif I = B then Rows'Old (A) else Rows'Old (I)));

   procedure Swap (Rows : in out Table; A, B : Positive) is
      Old_Rows : constant Table := Rows with Ghost;
      Temp : constant Rotation := Rows (A);
   begin
      Rows (A) := Rows (B);
      Rows (B) := Temp;
      for I in Rows'Range loop
         declare
            J : constant Positive := (if I = A then B elsif I = B then A else I);
         begin
            pragma Assert (Rows (I) = Old_Rows (J));
            pragma Assert (Old_Rows (I) = Rows (J));
         end;
         pragma Loop_Invariant
           (for all K in Rows'First .. I =>
             (for some Q of Rows => Q = Old_Rows (K)));
         pragma Loop_Invariant
           (for all K in Rows'First .. I =>
             (for some Q of Old_Rows => Q = Rows (K)));
      end loop;
   end Swap;

   procedure Sort (S : String; Rows : in out Table) is
      pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Distinct);
      Original : constant Table := Rows with Ghost;
      Before : Table := Rows with Ghost;
   begin
      --  Selection by (periodic word, original position) has the same stable
      --  order as insertion sort, with simpler minimum and permutation proofs.
      for I in Rows'Range loop
         declare
            Best : Positive := I;
         begin
            Key_Order (S, Rows (I), Rows (I), Rows (I));
            for J in I + 1 .. Rows'Last loop
               if Key_Less (S, Rows (J), Rows (Best)) then
                  for K in I .. J - 1 loop
                     Key_Order (S, Rows (J), Rows (Best), Rows (K));
                     pragma Loop_Invariant
                       (for all P in I .. K => Key_LE (S, Rows (J), Rows (P)));
                  end loop;
                  Best := J;
               end if;
               Key_Order (S, Rows (Best), Rows (J), Rows (Best));
               pragma Loop_Invariant (Best in I .. J);
               pragma Loop_Invariant
                 (for all K in I .. J => Key_LE (S, Rows (Best), Rows (K)));
            end loop;
            Before := Rows;
            Swap (Rows, I, Best);
            Extend_Sorted (S, Before, Rows, I, Best);
            Compose (Original, Before, Rows);
         end;
         pragma Loop_Invariant (Well_Formed (S, Rows));
         pragma Loop_Invariant (Distinct (Rows));
         pragma Loop_Invariant (Same_Rows (Rows, Original));
         pragma Loop_Invariant (Prefix_Sorted (S, Rows, I));
      end loop;
      pragma Assert (Same_Rows (Rows, Original));
      pragma Assert (Sorted (S, Rows));
   end Sort;
end BWT.Sorting;
