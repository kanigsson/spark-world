with BWT.Counting;
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

   --  Duval emits the unique nonincreasing Lyndon factorization. Each factor
   --  contributes all its rotations, including every occurrence of duplicates.
   function Factor_Rotations (S : String) return Rotation_Table
   with
     Pre  => Supported (S),
     Post =>
       Factor_Rotations'Result'First = 1
       and then Factor_Rotations'Result'Length = S'Length
       and then (for all I in Factor_Rotations'Result'Range =>
         Factor_Rotations'Result (I).First + Factor_Rotations'Result (I).Offset = I)
       and then (for all R of Factor_Rotations'Result => Valid (R, S'Length));

   function Factor_Rotations (S : String) return Rotation_Table is
      Rows : Rotation_Table (1 .. S'Length);
      I    : Positive := 1;
      J, K : Positive;
      Size : Positive;
   begin
      while I <= S'Length loop
         pragma Loop_Invariant (I in 1 .. S'Length + 1);
         pragma Loop_Invariant
           (for all P in 1 .. I - 1 => Rows (P).First + Rows (P).Offset = P);
         pragma
           Loop_Invariant
             (for all P in 1 .. I - 1 => Valid (Rows (P), S'Length));
         pragma Loop_Variant (Increases => I);
         J := I + 1;
         K := I;
         while J <= S'Length and then S (K) <= S (J) loop
            pragma Loop_Invariant (I <= K and then K < J);
            pragma Loop_Invariant (J in I + 1 .. S'Length + 1);
            pragma Loop_Variant (Increases => J);
            if S (K) < S (J) then
               K := I;
            else
               K := K + 1;
            end if;
            J := J + 1;
         end loop;
         Size := J - K;
         while I <= K loop
            pragma Loop_Invariant
              (for all P in 1 .. I - 1 => Rows (P).First + Rows (P).Offset = P);
            pragma Loop_Invariant (I + Size <= S'Length + 1);
            pragma
              Loop_Invariant
                (for all P in 1 .. I - 1 => Valid (Rows (P), S'Length));
            pragma Loop_Variant (Increases => I);
            for Offset in 0 .. Size - 1 loop
               Rows (I + Offset) := (I, Size, Offset);
               pragma Loop_Invariant
                 (for all P in 1 .. I + Offset => Rows (P).First + Rows (P).Offset = P);
               pragma
                 Loop_Invariant
                   (for all P in 1 .. I + Offset =>
                      Valid (Rows (P), S'Length));
            end loop;
            I := I + Size;
         end loop;
      end loop;
      return Rows;
   end Factor_Rotations;

   function Bijective_Encode (S : String) return String is
      Rows   : Rotation_Table := Factor_Rotations (S);
      Result : String (1 .. S'Length) := (others => Character'First);
   begin
      Sort (S, Rows);
      for I in Rows'Range loop
         Result (I) := Letter (S, Rows (I), Rows (I).Length - 1);
      end loop;
      return Result;
   end Bijective_Encode;

   function Bijective_Decode (Last : String) return String is
      Map    : constant Indices := LF (Last);
      Seen   : Counting.Flags (1 .. Last'Length) := (others => False);
      Result : String (1 .. Last'Length) := (others => Character'First);
      Next   : Natural := Last'Length;
      Row    : Positive;
   begin
      Counting.All_Clear (Seen);
      --  The least unvisited row starts the least remaining Lyndon factor.
      --  LF walks it backwards. Writing right to left puts successive factors
      --  into nonincreasing order without a second sort or a temporary word.
      for Start in Last'Range loop
         pragma Loop_Invariant (Next = Counting.Unseen (Seen, Seen'Length));
         pragma Loop_Invariant (for all I in 1 .. Start - 1 => Seen (I));
         Row := Start;
         while not Seen (Row) loop
            pragma Loop_Invariant (Row in Last'Range);
            pragma Loop_Invariant (Next <= Last'Length);
            pragma Loop_Invariant
              (Next = Counting.Unseen (Seen, Seen'Length));
            pragma Loop_Invariant (for all I in 1 .. Start - 1 => Seen (I));
            pragma Loop_Invariant (if Row /= Start then Seen (Start));
            pragma Loop_Variant (Decreases => Next);
            Result (Next) := Last (Row);
            Next := Next - 1;
            declare
               Before : constant Counting.Flags := Seen with Ghost;
            begin
               Seen (Row) := True;
               Counting.Marked (Before, Seen, Row);
            end;
            Row := Map (Row);
         end loop;
         pragma Assert (Seen (Start));
      end loop;
      pragma Assert (Next = 0);
      return Result;
   end Bijective_Decode;
end BWT;
