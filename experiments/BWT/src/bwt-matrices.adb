with BWT.Permutations;

package body BWT.Matrices with SPARK_Mode is
   pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", LE);
   procedure Same_Image (S : String; Rows : Table; A, B : Mapping)
   with Pre => Sorting.Well_Formed (S, Rows)
     and then Permutation (A) and then Permutation (B)
     and then A'Length = Rows'Length and then B'Length = Rows'Length
     and then (for all I in Rows'Range =>
       Equal_Prefix (S, Rows (A (I)), Rows (B (I)), 2 * S'Length)),
     Post => Ordered_Image (S, Rows, A) = Ordered_Image (S, Rows, B);

   procedure Same_Image (S : String; Rows : Table; A, B : Mapping) is
   begin
      for I in Rows'Range loop
         for J in I .. Rows'Last loop
            Equivalent_Order (S, Rows (A (I)), Rows (B (I)), Rows (A (J)));
            Equivalent_Order (S, Rows (A (J)), Rows (B (J)), Rows (B (I)));
            pragma Loop_Invariant
              (for all K in I .. J =>
                (LE (S, Rows (A (I)), Rows (A (K)), 2 * S'Length) =
                 LE (S, Rows (B (I)), Rows (B (K)), 2 * S'Length)));
         end loop;
         pragma Loop_Invariant
           (for all P in 1 .. I => (for all Q in P .. Rows'Last =>
             (LE (S, Rows (A (P)), Rows (A (Q)), 2 * S'Length) =
              LE (S, Rows (B (P)), Rows (B (Q)), 2 * S'Length))));
      end loop;
   end Same_Image;

   procedure Sorted_Permutation (S : String; Rows : Table; Map : Mapping) is
      P : Mapping := Map;
   begin
      for I in Rows'Range loop
         pragma Loop_Invariant (Permutation (P));
         pragma Loop_Invariant (Ordered_Image (S, Rows, P));
         pragma Loop_Invariant (for all K in 1 .. I - 1 => P (K) = K);
         pragma Loop_Invariant
           (for all K in Rows'Range =>
             Equal_Prefix (S, Rows (P (K)), Rows (Map (K)), 2 * S'Length));
         declare
            Inv : constant Mapping := Permutations.Inverse (P);
            J : constant Positive := Inv (I);
            Before : constant Mapping := P;
         begin
            pragma Assert (J >= I);
            if P (I) < I then
               pragma Assert (P (P (I)) = P (I));
               pragma Assert (P (P (I)) /= P (I));
            end if;
            pragma Assert (P (I) >= I);
            Key_Weakening (S, Rows (I), Rows (P (I)));
            Order_Laws (S, Rows (I), Rows (P (I)), Rows (I), 2 * S'Length);
            pragma Assert (Equal_Prefix (S, Rows (I), Rows (P (I)), 2 * S'Length));
            Permutations.Swap (P, I, J);
            for K in Rows'Range loop
               Equivalent_Order (S, Rows (P (K)), Rows (Before (K)), Rows (Map (K)));
               pragma Loop_Invariant
                 (for all Q in 1 .. K =>
                   Equal_Prefix (S, Rows (P (Q)), Rows (Map (Q)), 2 * S'Length));
            end loop;
            Same_Image (S, Rows, Before, P);
         end;
      end loop;
   end Sorted_Permutation;

   function Find (Rows : Table; R : Rotation) return Positive
   with Pre => (for some Q of Rows => Q = R),
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

   procedure Classical_Closed (S : String; Rows : Table) is
      Offsets : Mapping (1 .. Rows'Length) := (others => 1);
   begin
      for I in Rows'Range loop
         Offsets (I) := Rows (I).Offset + 1;
         pragma Loop_Invariant (for all J of Offsets => J in Rows'Range);
         pragma Loop_Invariant
           (for all J in 1 .. I => Offsets (J) = Rows (J).Offset + 1);
      end loop;
      pragma Assert (Permutation (Offsets));
      declare
         Inv : constant Mapping := Permutations.Inverse (Offsets);
      begin
         for I in Rows'Range loop
            declare
               J : constant Positive := Inv (Previous (Rows (I)).Offset + 1);
            begin
               pragma Assert (Rows (J) = Previous (Rows (I)));
            end;
            pragma Loop_Invariant
              (for all K in 1 .. I =>
                (for some R of Rows => R = Previous (Rows (K))));
         end loop;
      end;
   end Classical_Closed;

   procedure LF_Shifts (S : String; Rows : Table; Last : String; Map : Mapping) is
      Inv : constant Mapping := Permutations.Inverse (Map);
      Pred : Mapping (1 .. Rows'Length) := (others => 1);
      P : Mapping (1 .. Rows'Length) := (others => 1);
   begin
      for I in Rows'Range loop
         Pred (I) := Find (Rows, Previous (Rows (I)));
         pragma Loop_Invariant (for all J of Pred => J in Rows'Range);
         pragma Loop_Invariant
           (for all J in 1 .. I => Rows (Pred (J)) = Previous (Rows (J)));
      end loop;
      for I in Rows'Range loop
         for J in Rows'Range loop
            Previous_Injective (Rows (I), Rows (J));
            pragma Loop_Invariant
              (for all K in 1 .. J => (if I /= K then Pred (I) /= Pred (K)));
         end loop;
         pragma Loop_Invariant
           (for all A in 1 .. I => (for all B in Rows'Range =>
             (if A /= B then Pred (A) /= Pred (B))));
      end loop;
      pragma Assert (Permutation (Pred));
      for I in Rows'Range loop
         P (I) := Pred (Inv (I));
         pragma Loop_Invariant (for all J of P => J in Rows'Range);
         pragma Loop_Invariant (for all J in 1 .. I => P (J) = Pred (Inv (J)));
      end loop;
      pragma Assert (Permutation (P));
      for I in Rows'Range loop
         for J in I .. Rows'Last loop
            declare
               A : constant Positive := Inv (I);
               B : constant Positive := Inv (J);
            begin
               pragma Assert (Ordered (Last, A, B));
               if Last (A) = Last (B) then
                  Key_Weakening (S, Rows (A), Rows (B));
               end if;
               Prepend_Order (S, Rows (A), Rows (B));
            end;
            pragma Loop_Invariant
              (for all K in I .. J => LE (S, Rows (P (I)), Rows (P (K)), 2 * S'Length));
         end loop;
         pragma Loop_Invariant
           (for all A in 1 .. I => (for all B in A .. Rows'Last =>
             LE (S, Rows (P (A)), Rows (P (B)), 2 * S'Length)));
      end loop;
      Sorted_Permutation (S, Rows, P);
      for I in Rows'Range loop
         pragma Assert (P (Map (I)) = Pred (I));
         pragma Loop_Invariant
           (for all J in 1 .. I =>
             Equal_Prefix (S, Rows (Map (J)), Previous (Rows (J)), 2 * S'Length));
      end loop;
   end LF_Shifts;

   procedure Classical_Thread
     (S : String; Rows : Table; Last : String; Primary : Positive) is
      Map : constant Mapping := LF (Last);
      Row : Positive := Primary;
   begin
      LF_Shifts (S, Rows, Last, Map);
      for Steps in 0 .. S'Length - 1 loop
         pragma Loop_Invariant (Row in Rows'Range);
         pragma Loop_Invariant (Row = Walk (Last, Primary, Steps));
         pragma Loop_Invariant
           (Equal_Prefix
             (S, Rows (Row),
              (1, S'Length, (if Steps = 0 then 0 else S'Length - Steps)),
              2 * S'Length));
         pragma Loop_Invariant
           (for all K in 1 .. Steps =>
             Last (Walk (Last, Primary, K - 1)) = S (S'Length - K + 1));
         declare
            Expected : constant Rotation :=
              (1, S'Length, (if Steps = 0 then 0 else S'Length - Steps));
         begin
            Prefix_Letter (S, Rows (Row), Expected, 2 * S'Length, S'Length - 1);
            Classical_Character (S, Steps);
            pragma Assert (Last (Row) = S (S'Length - Steps));
            if Steps + 1 < S'Length then
               Shift_Equal (S, Rows (Row), Expected);
               Equivalent_Order
                 (S, Rows (Map (Row)), Previous (Rows (Row)), Previous (Expected));
               pragma Assert
                 (Previous (Expected) = (1, S'Length, S'Length - Steps - 1));
            end if;
         end;
         Row := Map (Row);
      end loop;
   end Classical_Thread;
end BWT.Matrices;
