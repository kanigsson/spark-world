with BWT.Ranks;
with BWT.Rotations;
with BWT.Sorting;

package BWT.Matrices with SPARK_Mode, Ghost is
   use BWT.Ranks;
   use BWT.Rotations;

   function Ordered_Image (S : String; Rows : Table; Map : Mapping)
     return Boolean is
     (for all I in Map'Range => (for all J in I .. Map'Last =>
        LE (S, Rows (Map (I)), Rows (Map (J)), 2 * S'Length)))
   with Pre => Sorting.Well_Formed (S, Rows) and then Permutation (Map)
     and then Map'Length = Rows'Length;

   procedure Sorted_Permutation (S : String; Rows : Table; Map : Mapping)
   with Pre => Sorting.Well_Formed (S, Rows)
     and then Sorting.Sorted (S, Rows) and then Permutation (Map)
     and then Map'Length = Rows'Length and then Ordered_Image (S, Rows, Map),
     Post => (for all I in Rows'Range =>
       Equal_Prefix (S, Rows (I), Rows (Map (I)), 2 * S'Length));

   function Closed (S : String; Rows : Table) return Boolean is
     (Sorting.Well_Formed (S, Rows) and then Sorting.Distinct (Rows)
       and then Sorting.Sorted (S, Rows)
       and then (for all R of Rows => (for some Q of Rows => Q = Previous (R))));

   procedure Classical_Closed (S : String; Rows : Table)
   with Pre => Sorting.Well_Formed (S, Rows) and then Sorting.Distinct (Rows)
     and then Sorting.Sorted (S, Rows)
     and then (for all R of Rows => R.First = 1 and then R.Length = S'Length),
     Post => Closed (S, Rows);

   procedure LF_Shifts (S : String; Rows : Table; Last : String; Map : Mapping)
   with Pre => Closed (S, Rows) and then Supported (Last)
     and then Last'Length = S'Length
     and then Permutation (Map) and then Map'Length = Rows'Length
     and then (for all A in Rows'Range => (for all B in Rows'Range =>
       (Ordered (Last, A, B) = (Map (A) <= Map (B)))))
     and then (for all I in Last'Range =>
       Last (I) = Letter (S, Rows (I), Rows (I).Length - 1)),
     Post => (for all I in Rows'Range =>
       Equal_Prefix (S, Rows (Map (I)), Previous (Rows (I)), 2 * S'Length));

   procedure Classical_Thread
     (S : String; Rows : Table; Last : String; Primary : Positive)
   with Pre => Closed (S, Rows) and then Supported (Last)
     and then Last'Length = S'Length and then Primary in Rows'Range
     and then Rows (Primary).Offset = 0
     and then (for all R of Rows => R.First = 1 and then R.Length = S'Length)
     and then (for all I in Last'Range =>
       Last (I) = Letter (S, Rows (I), S'Length - 1)),
     Post => (for all K in 0 .. S'Length - 1 =>
       Last (Ranks.Walk (Last, Primary, K)) = S (S'Length - K));
end BWT.Matrices;
