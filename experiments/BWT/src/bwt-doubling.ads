--  Rotation tables sorted by prefix doubling. Each round ranks the rows by
--  twice as many letters as the last, from pairs of the last round's ranks.
--  The result meets the hypotheses of Classical_Rows_Unique and
--  Bijective_Rows_Unique, so it is the specified table without reference to
--  how that one is sorted.

package BWT.Doubling
  with SPARK_Mode
is
   --  Row P is the rotation, starting at P, of the factor that contains P.
   --  The classical table sorts such rows for a single factor, the
   --  bijective one for the Lyndon factors.
   function Cycles (S : String; Factors : Table) return Boolean
   is (Factors'First = 1
       and then Factors'Length = S'Length
       and then (for all P in Factors'Range =>
                   Valid (Factors (P), S'Length)
                   and then Factors (P).First + Factors (P).Offset = P
                   and then (for all Q in
                               Factors (P).First
                               .. Factors (P).First + Factors (P).Length - 1 =>
                               Factors (Q).First = Factors (P).First
                               and then Factors (Q).Length
                                        = Factors (P).Length)))
   with Ghost, Pre => Supported (S);

   function Sorted_Rows
     (S : String; Factors : Table; Ties : Tie_Order) return Table
   with
     Pre  => Supported (S) and then Cycles (S, Factors),
     Post =>
       Well_Formed (S, Sorted_Rows'Result)
       and then Distinct (Sorted_Rows'Result)
       and then Same_Rows (Sorted_Rows'Result, Factors)
       and then Sorted (S, Sorted_Rows'Result, Ties);
end BWT.Doubling;
