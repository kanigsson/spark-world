package BWT.Sorting
  with SPARK_Mode
is
   procedure Sort
     (S : String; Rows : in out Table; Ties : Tie_Order := Earlier_First)
   with
     Pre  => Well_Formed (S, Rows) and then Distinct (Rows),
     Post =>
       Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, Rows'Old)
       and then Sorted (S, Rows, Ties);

   procedure Same_Rows_Trans (A, B, C : Table)
   with
     Ghost,
     Pre  => Same_Rows (A, B) and then Same_Rows (B, C),
     Post => Same_Rows (A, C);

   --  A sorted arrangement is unique, when rows at one position are one row.
   procedure Sorted_Unique (S : String; A, B : Table; Ties : Tie_Order)
   with
     Ghost,
     Pre  =>
       Well_Formed (S, A)
       and then Well_Formed (S, B)
       and then Distinct (A)
       and then Distinct (B)
       and then Same_Rows (A, B)
       and then Sorted (S, A, Ties)
       and then Sorted (S, B, Ties)
       and then (for all I in A'Range =>
                   (for all J in A'Range =>
                      (if A (I).First + A (I).Offset
                         = A (J).First + A (J).Offset
                       then A (I) = A (J)))),
     Post => (for all I in A'Range => A (I) = B (I));
end BWT.Sorting;
