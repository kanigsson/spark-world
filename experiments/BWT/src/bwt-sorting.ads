with BWT.Rotations;

package BWT.Sorting with SPARK_Mode is
   use BWT.Rotations;

   function Well_Formed (S : String; Rows : Table) return Boolean is
     (Supported (S) and then Rows'First = 1 and then Rows'Length = S'Length
       and then (for all R of Rows => Valid (R, S'Length)));

   function Same_Rows (A, B : Table) return Boolean is
     (A'First = B'First and then A'Last = B'Last
       and then (for all I in A'Range => (for some J in B'Range => A (I) = B (J)))
       and then (for all I in B'Range => (for some J in A'Range => B (I) = A (J))))
   with Ghost;

   function Distinct (Rows : Table) return Boolean is
     (for all I in Rows'Range => (for all J in Rows'Range =>
       (if I /= J then Rows (I) /= Rows (J))))
   with Ghost;

   function Sorted
     (S : String; Rows : Table; Ties : Tie_Order := Earlier_First)
     return Boolean is
     (for all I in Rows'Range => (for all J in I .. Rows'Last =>
        Key_LE (S, Rows (I), Rows (J), Ties)))
   with Ghost, Pre => Well_Formed (S, Rows);

   procedure Sort
     (S : String; Rows : in out Table; Ties : Tie_Order := Earlier_First)
   with Pre => Well_Formed (S, Rows) and then Distinct (Rows),
     Post => Well_Formed (S, Rows) and then Distinct (Rows)
       and then Same_Rows (Rows, Rows'Old) and then Sorted (S, Rows, Ties);
end BWT.Sorting;
