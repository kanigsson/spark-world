with BWT.Rotations;

package body BWT.Sorting
  with SPARK_Mode
is
   use BWT.Rotations;

   function Prefix_Sorted
     (S : String; Rows : Table; Through : Natural; Ties : Tie_Order)
      return Boolean
   is (for all P in 1 .. Through =>
         (for all Q in P .. Rows'Last => Key_LE (S, Rows (P), Rows (Q), Ties)))
   with Ghost, Pre => Well_Formed (S, Rows) and then Through <= Rows'Length;

   procedure Extend_Sorted
     (S             : String;
      Before, After : Table;
      Pos, Best     : Positive;
      Ties          : Tie_Order)
   with
     Ghost,
     Pre  =>
       Well_Formed (S, Before)
       and then Well_Formed (S, After)
       and then Pos in Before'Range
       and then Best in Pos .. Before'Last
       and then Prefix_Sorted (S, Before, Pos - 1, Ties)
       and then (for all Q in Pos .. Before'Last =>
                   Key_LE (S, Before (Best), Before (Q), Ties))
       and then (for all Q in Before'Range =>
                   After (Q)
                   = (if Q = Pos
                      then Before (Best)
                      elsif Q = Best
                      then Before (Pos)
                      else Before (Q))),
     Post => Prefix_Sorted (S, After, Pos, Ties);

   procedure Extend_Sorted
     (S             : String;
      Before, After : Table;
      Pos, Best     : Positive;
      Ties          : Tie_Order) is
   begin
      for I in 1 .. Pos loop
         for J in I .. After'Last loop
            pragma Assert (Key_LE (S, After (I), After (J), Ties));
            pragma
              Loop_Invariant
                (for all Q in I .. J =>
                   Key_LE (S, After (I), After (Q), Ties));
         end loop;
         pragma Loop_Invariant (Prefix_Sorted (S, After, I, Ties));
      end loop;
   end Extend_Sorted;

   function Find (Rows : Table; R : Rotation) return Positive
   with
     Ghost,
     Pre  => (for some Q of Rows => Q = R),
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
   with
     Ghost,
     Pre  => Same_Rows (A, B) and then Same_Rows (B, C),
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
            pragma Assert (for some J in C'Range => A (I) = C (J));
            pragma Assert (C (I) = A (M));
         end;
         pragma
           Loop_Invariant
             (for all P in A'First .. I =>
                (for some Q in C'Range => A (P) = C (Q)));
         pragma
           Loop_Invariant
             (for all P in C'First .. I =>
                (for some Q in A'Range => C (P) = A (Q)));
      end loop;
      pragma Assert (A'First = C'First and then A'Last = C'Last);
      pragma
        Assert
          (for all I in A'Range => (for some J in C'Range => A (I) = C (J)));
      pragma
        Assert
          (for all I in C'Range => (for some J in A'Range => C (I) = A (J)));
      pragma Assert (Same_Rows (A, C));
   end Compose;

   procedure Same_Refl (A : Table)
   with Ghost, Post => Same_Rows (A, A);

   procedure Same_Refl (A : Table) is
   begin
      for I in A'Range loop
         pragma
           Loop_Invariant
             (for all K in A'First .. I =>
                (for some J in A'Range => A (K) = A (J)));
      end loop;
   end Same_Refl;

   procedure Same_Symm (A, B : Table)
   with Ghost, Pre => Same_Rows (A, B), Post => Same_Rows (B, A);

   procedure Same_Symm (A, B : Table) is null;

   procedure Swap (Rows : in out Table; A, B : Positive)
   with
     Pre  => A in Rows'Range and then B in Rows'Range,
     Post =>
       Same_Rows (Rows, Rows'Old)
       and then Same_Rows (Rows'Old, Rows)
       and then Distinct (Rows) = Distinct (Rows'Old)
       and then (for all I in Rows'Range =>
                   Rows (I)
                   = (if I = A
                      then Rows'Old (B)
                      elsif I = B
                      then Rows'Old (A)
                      else Rows'Old (I)));

   procedure Swap (Rows : in out Table; A, B : Positive) is
      Old_Rows : constant Table := Rows
      with Ghost;
      Temp     : constant Rotation := Rows (A);
   begin
      Rows (A) := Rows (B);
      Rows (B) := Temp;
      for I in Rows'Range loop
         declare
            J : constant Positive :=
              (if I = A then B elsif I = B then A else I);
         begin
            pragma Assert (Rows (I) = Old_Rows (J));
            pragma Assert (Old_Rows (I) = Rows (J));
         end;
         pragma
           Loop_Invariant
             (for all K in Rows'First .. I =>
                (for some Q of Rows => Q = Old_Rows (K)));
         pragma
           Loop_Invariant
             (for all K in Rows'First .. I =>
                (for some Q of Old_Rows => Q = Rows (K)));
      end loop;
   end Swap;

   procedure Sort
     (S : String; Rows : in out Table; Ties : Tie_Order := Earlier_First)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Distinct);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Same_Rows);
      Original : constant Table := Rows
      with Ghost;
      Before   : Table := Rows
      with Ghost;
   begin
      Same_Refl (Original);
      --  Selection by (periodic word, original position) has the same stable
      --  order as insertion sort, with simpler minimum and permutation proofs.
      for I in Rows'Range loop
         declare
            Best : Positive := I;
         begin
            Key_Order (S, Rows (I), Rows (I), Rows (I), Ties);
            for J in I + 1 .. Rows'Last loop
               if Key_Less (S, Rows (J), Rows (Best), Ties) then
                  for K in I .. J - 1 loop
                     Key_Order (S, Rows (J), Rows (Best), Rows (K), Ties);
                     pragma
                       Loop_Invariant
                         (for all P in I .. K =>
                            Key_LE (S, Rows (J), Rows (P), Ties));
                  end loop;
                  Best := J;
               end if;
               Key_Order (S, Rows (Best), Rows (J), Rows (Best), Ties);
               pragma Loop_Invariant (Best in I .. J);
               pragma
                 Loop_Invariant
                   (for all K in I .. J =>
                      Key_LE (S, Rows (Best), Rows (K), Ties));
            end loop;
            Before := Rows;
            Swap (Rows, I, Best);
            Compose (Original, Before, Rows);
            Extend_Sorted (S, Before, Rows, I, Best, Ties);
         end;
         pragma Loop_Invariant (Well_Formed (S, Rows));
         pragma Loop_Invariant (Distinct (Rows));
         pragma Loop_Invariant (Same_Rows (Original, Rows));
         pragma Loop_Invariant (Prefix_Sorted (S, Rows, I, Ties));
      end loop;
      Same_Symm (Original, Rows);
      pragma Assert (Sorted (S, Rows, Ties));
   end Sort;

   --  Every row of A is a row of C, when it is one of B and B's are C's.
   procedure Contained (A, B, C : Table)
   with
     Ghost,
     Pre  =>
       (for all I in A'Range => (for some J in B'Range => A (I) = B (J)))
       and then (for all I in B'Range =>
                   (for some J in C'Range => B (I) = C (J))),
     Post =>
       (for all I in A'Range => (for some J in C'Range => A (I) = C (J)));

   procedure Contained (A, B, C : Table) is
   begin
      for I in A'Range loop
         declare
            J : constant Positive := Find (B, A (I));
            K : constant Positive := Find (C, B (J));
         begin
            pragma Assert (A (I) = C (K));
         end;
         pragma
           Loop_Invariant
             (for all P in A'First .. I =>
                (for some J in C'Range => A (P) = C (J)));
      end loop;
   end Contained;

   procedure Same_Rows_Trans (A, B, C : Table) is
   begin
      Contained (A, B, C);
      Contained (C, B, A);
   end Same_Rows_Trans;

   procedure Sorted_Unique (S : String; A, B : Table; Ties : Tie_Order) is
   begin
      for I in A'Range loop
         pragma
           Loop_Invariant (for all P in A'First .. I - 1 => A (P) = B (P));
         declare
            J : constant Positive := Find (B, A (I));
            K : constant Positive := Find (A, B (I));
         begin
            pragma Assert (J >= I);
            pragma Assert (K >= I);
            pragma Assert (Key_LE (S, A (I), A (K), Ties));
            pragma Assert (Key_LE (S, B (I), B (J), Ties));
            Key_Antisym (S, A (I), A (K), Ties);
            pragma Assert (A (I) = A (K));
         end;
      end loop;
   end Sorted_Unique;
end BWT.Sorting;
