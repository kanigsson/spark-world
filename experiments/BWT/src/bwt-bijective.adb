with BWT.Counting;
with BWT.Words;

package body BWT.Bijective
  with SPARK_Mode
is
   use BWT.Factorizations;
   use BWT.Words;

   function Factor_Rotations (S : String) return Table is
      pragma
        Annotate
          (GNATprove,
           Hide_Info,
           "Expression_Function_Body",
           Prefix_Factorization);

      Rows : Table (1 .. S'Length) := (others => (1, 1, 0));
      I    : Positive := 1;
      J, K : Positive;
      Size : Positive;
      --  The text from I agrees with the previous factor for Dom letters and
      --  then falls below it, so no later factor can exceed that one.
      Dom  : Natural := 0
      with Ghost;

      procedure Emit (Rows : in out Table; I, Size : Positive)
      with
        Pre  =>
          Rows'Last <= Max_Length
          and then I in Rows'Range
          and then Size <= Rows'Last - I + 1,
        Post =>
          (for all P in Rows'Range =>
             (if P in I .. I + Size - 1
              then Rows (P) = (I, Size, P - I)
              else Rows (P) = Rows'Old (P)));

      procedure Emit (Rows : in out Table; I, Size : Positive) is
      begin
         for Offset in 0 .. Size - 1 loop
            Rows (I + Offset) := (I, Size, Offset);
            pragma Loop_Invariant
              (for all P in Rows'Range =>
                 (if P in I .. I + Offset
                  then Rows (P) = (I, Size, P - I)
                  else Rows (P) = Rows'Loop_Entry (P)));
         end loop;
      end Emit;
   begin
      Empty_Prefix (S, Rows);
      while I <= S'Length loop
         pragma Loop_Invariant (I <= S'Length + 1);
         pragma Loop_Invariant (Prefix_Factorization (S, Rows, I));
         pragma Loop_Invariant
           (if I > 1
            then Dominated (S, I, Rows (I - 1).First, Rows (I - 1).Length, Dom));
         pragma Loop_Variant (Increases => I);
         J := I + 1;
         K := I;
         --  S (I .. J - 1) repeats the Lyndon word S (I .. I + J - K - 1).
         while J <= S'Length and then S (K) <= S (J) loop
            pragma Loop_Invariant (I <= K and then K < J);
            pragma Loop_Invariant (J in I + 1 .. S'Length + 1);
            pragma Loop_Invariant (Lyndon (S, I, J - K));
            pragma Loop_Invariant (Periodic (S, I, J, J - K));
            pragma Loop_Variant (Increases => J);
            if S (K) < S (J) then
               Lyndon_Extend (S, I, J, J - K);
               K := I;
            else
               K := K + 1;
            end if;
            J := J + 1;
         end loop;
         Size := J - K;
         pragma Assert (J > S'Length or else S (J - Size) > S (J));
         declare
            Run_Start : constant Positive := I
            with Ghost;
         begin
            if I > 1 then
               Dominated_Less
                 (S, I, Rows (I - 1).First, Rows (I - 1).Length, Dom, Size);
            end if;
            while I <= K loop
               pragma Loop_Invariant (I in Run_Start .. K + Size);
               pragma Loop_Invariant (I <= S'Length + 1);
               pragma Loop_Invariant (Prefix_Factorization (S, Rows, I));
               pragma Loop_Invariant (Lyndon (S, I, Size));
               pragma Loop_Invariant
                 (if I > 1
                  then
                    Lex_LE
                      (S, I, Size, Rows (I - 1).First, Rows (I - 1).Length));
               pragma Loop_Invariant
                 (if I > Run_Start
                  then
                    Rows (I - 1).First = I - Size
                    and then Rows (I - 1).Length = Size);
               pragma Loop_Variant (Increases => I);
               declare
                  Old : constant Table := Rows
                  with Ghost;
               begin
                  Emit (Rows, I, Size);
                  Extend_Prefix (S, Old, Rows, I, Size);
               end;
               I := I + Size;
               if I <= K then
                  pragma Assert (Same (S, I - Size, I, Size));
                  Lyndon_Same (S, I - Size, I, Size);
                  Lex_Total (S, I, Size, I - Size, Size);
               end if;
            end loop;
            pragma Assert (I > Run_Start);
            Dom := J - I;
            pragma Assert (Same (S, I, I - Size, Dom));
         end;
      end loop;
      return Rows;
   end Factor_Rotations;

   function Table_Of (S : String) return Table is
      Rows : Table := Factor_Rotations (S);
   begin
      pragma Assert (Sorting.Well_Formed (S, Rows));
      pragma Assert
        (for all I in Rows'Range =>
           (for all J in Rows'Range =>
              (if I /= J then Rows (I) /= Rows (J))));
      declare
         Original : constant Table := Rows
         with Ghost;
      begin
         Sorting.Sort (S, Rows, Later_First);
         pragma Assert (Sorting.Same_Rows (Rows, Original));
      end;
      return Rows;
   end Table_Of;

   function Encode (S : String) return String is
      Rows   : constant Table := Table_Of (S);
      Result : String (1 .. S'Length) := (others => Character'First);
   begin
      for I in Rows'Range loop
         Result (I) := Letter (S, Rows (I), Rows (I).Length - 1);
         pragma Loop_Invariant
           (for all J in 1 .. I =>
              Result (J) = Letter (S, Rows (J), Rows (J).Length - 1));
      end loop;
      return Result;
   end Encode;

   function Decode_Order (Last : String) return Mapping is
      use Counting;
      N     : constant Natural := Last'Length;
      Map   : constant Mapping := LF (Last);
      Seen  : Flags (1 .. N) := (others => False);
      Order : Mapping (1 .. N) := (others => 1);
      Pos   : Mapping (1 .. N) := (others => 1)
      with Ghost;
      Next  : Natural := N;
      Row   : Positive;
   begin
      All_Clear (Seen);
      --  The least unvisited row starts the least remaining Lyndon factor.
      --  LF walks it backwards. Writing right to left puts successive factors
      --  into nonincreasing order without a second sort or a temporary word.
      for Start in Last'Range loop
         pragma Loop_Invariant (Next = Unseen (Seen, N));
         pragma Loop_Invariant (for all I in 1 .. Start - 1 => Seen (I));
         pragma Loop_Invariant (for all P in 1 .. N => Order (P) in 1 .. N);
         pragma Loop_Invariant (for all R in 1 .. N => Pos (R) in 1 .. N);
         pragma Loop_Invariant
           (for all R in 1 .. N =>
              (if Seen (R)
               then Pos (R) in Next + 1 .. N and then Order (Pos (R)) = R));
         pragma Loop_Invariant
           (for all P in Next + 1 .. N =>
              Seen (Order (P)) and then Pos (Order (P)) = P);
         pragma Loop_Invariant
           (for all R in 1 .. N => (if Seen (R) then Seen (Map (R))));
         pragma Loop_Invariant (if Next < N then Order (N) = 1);
         pragma Loop_Invariant
           (for all P in Next + 2 .. N =>
              Seen (Map (Order (P)))
              and then (if Pos (Map (Order (P))) < P
                        then Order (P - 1) = Map (Order (P))
                        else
                          (for all Y in 1 .. Order (P - 1) - 1 =>
                             Seen (Y) and then Pos (Y) >= P)));
         Row := Start;
         while not Seen (Row) loop
            pragma Loop_Invariant (Row in 1 .. N);
            pragma Loop_Invariant (Next = Unseen (Seen, N));
            pragma Loop_Invariant (for all I in 1 .. Start - 1 => Seen (I));
            pragma Loop_Invariant (if Row /= Start then Seen (Start));
            pragma Loop_Invariant
              (for all P in 1 .. N => Order (P) in 1 .. N);
            pragma Loop_Invariant (for all R in 1 .. N => Pos (R) in 1 .. N);
            pragma Loop_Invariant
              (for all R in 1 .. N =>
                 (if Seen (R)
                  then Pos (R) in Next + 1 .. N and then Order (Pos (R)) = R));
            pragma Loop_Invariant
              (for all P in Next + 1 .. N =>
                 Seen (Order (P)) and then Pos (Order (P)) = P);
            pragma Loop_Invariant
              (if Row /= Start
               then Next < N and then Row = Map (Order (Next + 1)));
            pragma Loop_Invariant
              (for all R in 1 .. N =>
                 (if Seen (R)
                  then
                    Seen (Map (R))
                    or else (Row /= Start and then R = Order (Next + 1))));
            pragma Loop_Invariant (if Next < N then Order (N) = 1);
            pragma Loop_Invariant
              (for all P in Next + 2 .. N =>
                 Seen (Map (Order (P)))
                 and then (if Pos (Map (Order (P))) < P
                           then Order (P - 1) = Map (Order (P))
                           else
                             (for all Y in 1 .. Order (P - 1) - 1 =>
                                Seen (Y) and then Pos (Y) >= P)));
            pragma Loop_Variant (Decreases => Next);
            pragma Assert (Next > 0);
            Order (Next) := Row;
            Pos (Row) := Next;
            declare
               Before : constant Flags := Seen
               with Ghost;
            begin
               Seen (Row) := True;
               Marked (Before, Seen, Row);
            end;
            Next := Next - 1;
            Row := Map (Row);
         end loop;
      end loop;
      pragma Assert (Next = 0);
      pragma Assert (for all P in 1 .. N => Pos (Order (P)) = P);
      pragma Assert (Permutation (Order));
      declare
         Inv : constant Mapping := Permutations.Inverse (Order)
         with Ghost;
      begin
         pragma Assert (for all R in 1 .. N => Inv (R) = Pos (R));
      end;
      return Order;
   end Decode_Order;

   function Decode (Last : String) return String is
      Order  : constant Mapping := Decode_Order (Last);
      Result : String (1 .. Last'Length) := (others => Character'First);
   begin
      for P in Result'Range loop
         Result (P) := Last (Order (P));
         pragma Loop_Invariant
           (for all Q in 1 .. P => Result (Q) = Last (Order (Q)));
      end loop;
      return Result;
   end Decode;
end BWT.Bijective;
