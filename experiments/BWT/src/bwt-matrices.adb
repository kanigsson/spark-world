with BWT.Permutations;

package body BWT.Matrices
  with SPARK_Mode
is
   pragma Annotate (GNATprove, Hide_Info, "Expression_Function_Body", LE);
   procedure Same_Image (S : String; Rows : Table; A, B : Mapping)
   with
     Pre  =>
       Well_Formed (S, Rows)
       and then Permutation (A)
       and then Permutation (B)
       and then A'Length = Rows'Length
       and then B'Length = Rows'Length
       and then (for all I in Rows'Range =>
                   Equal_Prefix (S, Rows (A (I)), Rows (B (I)), 2 * S'Length)),
     Post => Ordered_Image (S, Rows, A) = Ordered_Image (S, Rows, B);

   procedure Same_Image (S : String; Rows : Table; A, B : Mapping) is
   begin
      for I in Rows'Range loop
         for J in I .. Rows'Last loop
            Equivalent_Order (S, Rows (A (I)), Rows (B (I)), Rows (A (J)));
            Equivalent_Order (S, Rows (A (J)), Rows (B (J)), Rows (B (I)));
            pragma
              Loop_Invariant
                (for all K in I .. J =>
                   (LE (S, Rows (A (I)), Rows (A (K)), 2 * S'Length)
                    = LE (S, Rows (B (I)), Rows (B (K)), 2 * S'Length)));
         end loop;
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                (for all Q in P .. Rows'Last =>
                   (LE (S, Rows (A (P)), Rows (A (Q)), 2 * S'Length)
                    = LE (S, Rows (B (P)), Rows (B (Q)), 2 * S'Length))));
      end loop;
   end Same_Image;

   procedure Sorted_Permutation (S : String; Rows : Table; Map : Mapping) is
      P : Mapping := Map;
   begin
      for I in Rows'Range loop
         pragma Loop_Invariant (Permutation (P));
         pragma Loop_Invariant (Ordered_Image (S, Rows, P));
         pragma Loop_Invariant (for all K in 1 .. I - 1 => P (K) = K);
         pragma
           Loop_Invariant
             (for all K in Rows'Range =>
                Equal_Prefix (S, Rows (P (K)), Rows (Map (K)), 2 * S'Length));
         declare
            Inv    : constant Mapping := Permutations.Inverse (P);
            J      : constant Positive := Inv (I);
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
            pragma
              Assert (Equal_Prefix (S, Rows (I), Rows (P (I)), 2 * S'Length));
            Permutations.Swap (P, I, J);
            for K in Rows'Range loop
               Equivalent_Order
                 (S, Rows (P (K)), Rows (Before (K)), Rows (Map (K)));
               pragma
                 Loop_Invariant
                   (for all Q in 1 .. K =>
                      Equal_Prefix
                        (S, Rows (P (Q)), Rows (Map (Q)), 2 * S'Length));
            end loop;
            Same_Image (S, Rows, Before, P);
         end;
      end loop;
   end Sorted_Permutation;

   function Find (Rows : Table; R : Rotation) return Positive
   with
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

   procedure Classical_Closed (S : String; Rows : Table) is
      Offsets : Mapping (1 .. Rows'Length) := (others => 1);
   begin
      for I in Rows'Range loop
         Offsets (I) := Rows (I).Offset + 1;
         pragma Loop_Invariant (for all J of Offsets => J in Rows'Range);
         pragma
           Loop_Invariant
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
            pragma
              Loop_Invariant
                (for all K in 1 .. I =>
                   (for some R of Rows => R = Previous (Rows (K))));
         end loop;
      end;
   end Classical_Closed;

   --  Prepending equal last letters preserves order, so ordering by LF rank
   --  orders the predecessor rotations.
   procedure Prepend_Ranked
     (S : String; Rows : Table; Last : String; A, B : Positive)
   with
     Pre  =>
       Well_Formed (S, Rows)
       and then Sorted (S, Rows)
       and then Supported (Last)
       and then Last'Length = S'Length
       and then A in Rows'Range
       and then B in Rows'Range
       and then Ordered (Last, A, B)
       and then Last (A) = Letter (S, Rows (A), Rows (A).Length - 1)
       and then Last (B) = Letter (S, Rows (B), Rows (B).Length - 1),
     Post => LE (S, Previous (Rows (A)), Previous (Rows (B)), 2 * S'Length);

   procedure Prepend_Ranked
     (S : String; Rows : Table; Last : String; A, B : Positive) is
   begin
      if Last (A) = Last (B) then
         pragma Assert (A <= B);
         Key_Weakening (S, Rows (A), Rows (B));
      end if;
      Prepend_Order (S, Rows (A), Rows (B));
   end Prepend_Ranked;

   procedure Shifted_Row_Ordered
     (S           : String;
      Rows        : Table;
      Last        : String;
      Map, Inv, P : Mapping;
      I           : Positive)
   with
     Pre  =>
       Well_Formed (S, Rows)
       and then Sorted (S, Rows)
       and then Supported (Last)
       and then Last'Length = S'Length
       and then Permutation (Map)
       and then Map'Length = Rows'Length
       and then Permutation (Inv)
       and then Inv'Length = Rows'Length
       and then Permutation (P)
       and then P'Length = Rows'Length
       and then I in Rows'Range
       and then (for all K in Rows'Range => Map (Inv (K)) = K)
       and then (for all K in Rows'Range =>
                   Rows (P (K)) = Previous (Rows (Inv (K))))
       and then (for all A in Rows'Range =>
                   (for all B in Rows'Range =>
                      (Ordered (Last, A, B) = (Map (A) <= Map (B)))))
       and then (for all K in Last'Range =>
                   Last (K) = Letter (S, Rows (K), Rows (K).Length - 1)),
     Post =>
       (for all K in I .. Rows'Last =>
          LE (S, Rows (P (I)), Rows (P (K)), 2 * S'Length));

   procedure Shifted_Row_Ordered
     (S           : String;
      Rows        : Table;
      Last        : String;
      Map, Inv, P : Mapping;
      I           : Positive) is
   begin
      for J in I .. Rows'Last loop
         pragma Assert (Ordered (Last, Inv (I), Inv (J)));
         Prepend_Ranked (S, Rows, Last, Inv (I), Inv (J));
         pragma Assert (Rows (P (I)) = Previous (Rows (Inv (I))));
         pragma Assert (Rows (P (J)) = Previous (Rows (Inv (J))));
         pragma
           Loop_Invariant
             (for all K in I .. J =>
                LE (S, Rows (P (I)), Rows (P (K)), 2 * S'Length));
      end loop;
   end Shifted_Row_Ordered;

   procedure Shifted_Rows_Ordered
     (S : String; Rows : Table; Last : String; Map, Inv, P : Mapping)
   with
     Pre  =>
       Well_Formed (S, Rows)
       and then Sorted (S, Rows)
       and then Supported (Last)
       and then Last'Length = S'Length
       and then Permutation (Map)
       and then Map'Length = Rows'Length
       and then Permutation (Inv)
       and then Inv'Length = Rows'Length
       and then Permutation (P)
       and then P'Length = Rows'Length
       and then (for all K in Rows'Range => Map (Inv (K)) = K)
       and then (for all K in Rows'Range =>
                   Rows (P (K)) = Previous (Rows (Inv (K))))
       and then (for all A in Rows'Range =>
                   (for all B in Rows'Range =>
                      (Ordered (Last, A, B) = (Map (A) <= Map (B)))))
       and then (for all K in Last'Range =>
                   Last (K) = Letter (S, Rows (K), Rows (K).Length - 1)),
     Post => Ordered_Image (S, Rows, P);

   procedure Shifted_Rows_Ordered
     (S : String; Rows : Table; Last : String; Map, Inv, P : Mapping) is
   begin
      for I in Rows'Range loop
         Shifted_Row_Ordered (S, Rows, Last, Map, Inv, P, I);
         pragma
           Loop_Invariant
             (for all A in 1 .. I =>
                (for all B in A .. Rows'Last =>
                   LE (S, Rows (P (A)), Rows (P (B)), 2 * S'Length)));
      end loop;
   end Shifted_Rows_Ordered;

   --  Where each row's predecessor rotation sits.
   function Pred_Build (Rows : Table) return Mapping
   with
     Pre  =>
       Rows'First = 1
       and then Rows'Length <= Max_Length
       and then (for all R of Rows => R.Offset < R.Length)
       and then (for all R of Rows =>
                   (for some Q of Rows => Q = Previous (R))),
     Post =>
       Pred_Build'Result'First = 1
       and then Pred_Build'Result'Length = Rows'Length
       and then (for all J in Rows'Range =>
                   Pred_Build'Result (J) in Rows'Range
                   and then Rows (Pred_Build'Result (J))
                            = Previous (Rows (J)));

   function Pred_Build (Rows : Table) return Mapping is
      Pred : Mapping (1 .. Rows'Length) := (others => 1);
   begin
      for I in Rows'Range loop
         Pred (I) := Find (Rows, Previous (Rows (I)));
         pragma Loop_Invariant (for all J in 1 .. I => Pred (J) in Rows'Range);
         pragma
           Loop_Invariant
             (for all J in 1 .. I => Rows (Pred (J)) = Previous (Rows (J)));
      end loop;
      return Pred;
   end Pred_Build;

   function Unshared (Pred : Mapping; I : Positive) return Boolean
   is (for all B in Pred'Range => (if I /= B then Pred (I) /= Pred (B)))
   with Pre => I in Pred'Range;

   --  Distinct rows have distinct predecessors.
   procedure Pred_Injective (Rows : Table; Pred : Mapping; I : Positive)
   with
     Pre  =>
       Rows'First = 1
       and then Rows'Length <= Max_Length
       and then Distinct (Rows)
       and then (for all R of Rows => R.Offset < R.Length)
       and then Pred'First = 1
       and then Pred'Length = Rows'Length
       and then (for all J in Rows'Range =>
                   Pred (J) in Rows'Range
                   and then Rows (Pred (J)) = Previous (Rows (J)))
       and then I in Rows'Range,
     Post => Unshared (Pred, I);

   procedure Pred_Injective (Rows : Table; Pred : Mapping; I : Positive) is
   begin
      for J in Rows'Range loop
         Previous_Injective (Rows (I), Rows (J));
         pragma
           Loop_Invariant
             (for all K in 1 .. J => (if I /= K then Pred (I) /= Pred (K)));
      end loop;
   end Pred_Injective;

   procedure All_Unshared (Pred : Mapping)
   with
     Pre  =>
       Pred'First = 1
       and then Pred'Length <= Max_Length
       and then (for all J in Pred'Range => Pred (J) in Pred'Range)
       and then (for all A in Pred'Range => Unshared (Pred, A)),
     Post => Permutation (Pred);

   procedure All_Unshared (Pred : Mapping) is null;

   function Pred_Rows (Rows : Table) return Mapping
   with
     Pre  =>
       Rows'First = 1
       and then Rows'Length <= Max_Length
       and then Distinct (Rows)
       and then (for all R of Rows => R.Offset < R.Length)
       and then (for all R of Rows =>
                   (for some Q of Rows => Q = Previous (R))),
     Post =>
       Pred_Rows'Result'First = 1
       and then Pred_Rows'Result'Length = Rows'Length
       and then (for all J in Rows'Range =>
                   Pred_Rows'Result (J) in Rows'Range
                   and then Rows (Pred_Rows'Result (J)) = Previous (Rows (J)))
       and then Permutation (Pred_Rows'Result);

   function Pred_Rows (Rows : Table) return Mapping is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Distinct);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Unshared);
      Pred : constant Mapping := Pred_Build (Rows);
   begin
      for I in Rows'Range loop
         Pred_Injective (Rows, Pred, I);
         pragma Loop_Invariant (for all A in 1 .. I => Unshared (Pred, A));
      end loop;
      All_Unshared (Pred);
      return Pred;
   end Pred_Rows;

   --  Following one permutation after another.
   function Compose_Perm (First, Second : Mapping) return Mapping
   with
     Pre  =>
       Permutation (First)
       and then Permutation (Second)
       and then First'Length = Second'Length,
     Post =>
       Compose_Perm'Result'First = 1
       and then Compose_Perm'Result'Length = First'Length
       and then (for all I in Second'Range =>
                   Compose_Perm'Result (I) = First (Second (I)))
       and then Permutation (Compose_Perm'Result);

   function Compose_Perm (First, Second : Mapping) return Mapping is
      P : Mapping (1 .. First'Length) := (others => 1);
   begin
      for I in P'Range loop
         P (I) := First (Second (I));
         pragma
           Loop_Invariant (for all J in 1 .. I => P (J) = First (Second (J)));
      end loop;
      pragma Assert (for all J in P'Range => P (J) in P'Range);
      return P;
   end Compose_Perm;

   procedure LF_Shifts (S : String; Rows : Table; Last : String; Map : Mapping)
   is
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Ordered_Image);
      Inv  : constant Mapping := Permutations.Inverse (Map);
      Pred : constant Mapping := Pred_Rows (Rows);
      P    : constant Mapping := Compose_Perm (Pred, Inv);
   begin
      pragma
        Assert
          (for all K in Rows'Range =>
             Rows (P (K)) = Previous (Rows (Inv (K))));
      pragma Assert (Permutation (P));
      Shifted_Rows_Ordered (S, Rows, Last, Map, Inv, P);
      Sorted_Permutation (S, Rows, P);
      for I in Rows'Range loop
         pragma Assert (P (Map (I)) = Pred (I));
         pragma
           Loop_Invariant
             (for all J in 1 .. I =>
                Equal_Prefix
                  (S, Rows (Map (J)), Previous (Rows (J)), 2 * S'Length));
      end loop;
   end LF_Shifts;

   function Classical_Row (N : Positive; Steps : Natural) return Rotation
   is (1, N, (if Steps = 0 then 0 else N - Steps))
   with Pre => N <= Max_Length and then Steps < N;

   --  One LF step moves from the rotation starting Steps letters before the
   --  end of S to the one starting a letter earlier.
   procedure Thread_Step
     (S         : String;
      Rows      : Table;
      Last      : String;
      Row, Next : Positive;
      Steps     : Natural)
   with
     Pre  =>
       Well_Formed (S, Rows)
       and then S'Length > 0
       and then Supported (Last)
       and then Last'Length = S'Length
       and then Row in Rows'Range
       and then Next in Rows'Range
       and then Steps < S'Length
       and then Rows (Row).Length = S'Length
       and then Last (Row) = Letter (S, Rows (Row), S'Length - 1)
       and then Equal_Prefix
                  (S,
                   Rows (Row),
                   Classical_Row (S'Length, Steps),
                   2 * S'Length)
       and then Equal_Prefix
                  (S, Rows (Next), Previous (Rows (Row)), 2 * S'Length),
     Post =>
       Last (Row) = S (S'Length - Steps)
       and then (if Steps + 1 < S'Length
                 then
                   Equal_Prefix
                     (S,
                      Rows (Next),
                      Classical_Row (S'Length, Steps + 1),
                      2 * S'Length));

   procedure Thread_Step
     (S         : String;
      Rows      : Table;
      Last      : String;
      Row, Next : Positive;
      Steps     : Natural)
   is
      Expected : constant Rotation := Classical_Row (S'Length, Steps);
   begin
      Prefix_Letter (S, Rows (Row), Expected, 2 * S'Length, S'Length - 1);
      Classical_Character (S, Steps);
      pragma Assert (Last (Row) = S (S'Length - Steps));
      if Steps + 1 < S'Length then
         Shift_Equal (S, Rows (Row), Expected);
         Equivalent_Order
           (S, Rows (Next), Previous (Rows (Row)), Previous (Expected));
         pragma
           Assert (Previous (Expected) = Classical_Row (S'Length, Steps + 1));
      end if;
   end Thread_Step;

   procedure Classical_Thread
     (S : String; Rows : Table; Last : String; Primary : Positive)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Sorted);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Distinct);
      Map : constant Mapping := LF (Last);
      Row : Positive := Primary;
   begin
      LF_Shifts (S, Rows, Last, Map);
      Equal_Same
        (S, Rows (Primary), Classical_Row (S'Length, 0), 2 * S'Length);
      Ranks.Walk_Step (Last, Primary, 0);
      for Steps in 0 .. S'Length - 1 loop
         pragma Loop_Invariant (Row in Rows'Range);
         pragma Loop_Invariant (Row = Ranks.Walk (Last, Primary, Steps));
         pragma
           Loop_Invariant
             (Equal_Prefix
                (S,
                 Rows (Row),
                 Classical_Row (S'Length, Steps),
                 2 * S'Length));
         pragma
           Loop_Invariant
             (for all K in 0 .. Steps - 1 =>
                Last (Ranks.Walk (Last, Primary, K)) = S (S'Length - K));
         Thread_Step (S, Rows, Last, Row, Map (Row), Steps);
         if Steps + 1 < S'Length then
            Ranks.Walk_Step (Last, Primary, Steps);
         end if;
         pragma
           Assert
             (Last (Ranks.Walk (Last, Primary, Steps)) = S (S'Length - Steps));
         Row := Map (Row);
      end loop;
   end Classical_Thread;
end BWT.Matrices;
