--  The classical table by prefix doubling. Each round ranks the rotations by
--  twice as many letters as the last, from pairs of the last round's ranks.
--  The result meets the hypotheses of Classical_Rows_Unique, so it is the
--  specified table without reference to how that one is sorted.

package BWT.Doubling
  with SPARK_Mode
is
   function Classical_Table (S : String) return Table
   with
     Pre  => Supported (S),
     Post =>
       Well_Formed (S, Classical_Table'Result)
       and then Distinct (Classical_Table'Result)
       and then Same_Rows (Classical_Table'Result, Rotations_Of (S))
       and then Sorted (S, Classical_Table'Result, Earlier_First)
       and then (for all R of Classical_Table'Result =>
                   R.First = 1 and then R.Length = S'Length)
       and then (if S'Length > 0
                 then
                   (for some J in Classical_Table'Result'Range =>
                      Classical_Table'Result (J).Offset = 0));
end BWT.Doubling;
