with BWT.Factorizations;
with BWT.Orders;
with BWT.Permutations;
with BWT.Ranks;
with BWT.Rotations;
with BWT.Sorting;

--  The bijective transform's internals, with the contracts its inverse laws
--  are proved from.

package BWT.Bijective
  with SPARK_Mode
is
   use BWT.Ranks;
   use BWT.Rotations;

   --  Duval emits the unique nonincreasing Lyndon factorization. Each factor
   --  contributes all its rotations, including every occurrence of duplicates.
   function Factor_Rotations (S : String) return Table
   with
     Pre  => Supported (S),
     Post => Factorizations.Factorization (S, Factor_Rotations'Result);

   --  Every factor rotation, in periodic order; rows with equal periodic
   --  words put the later start first.
   function Table_Of (S : String) return Table
   with
     Pre  => Supported (S),
     Post =>
       Sorting.Well_Formed (S, Table_Of'Result)
       and then Sorting.Distinct (Table_Of'Result)
       and then Sorting.Same_Rows (Table_Of'Result, Factor_Rotations (S))
       and then Sorting.Sorted (S, Table_Of'Result, Later_First);

   function Encode (S : String) return String
   with
     Pre  => Supported (S),
     Post =>
       Supported (Encode'Result)
       and then Encode'Result'Length = S'Length
       and then (for all I in Encode'Result'Range =>
                   Encode'Result (I)
                   = Letter
                       (S, Table_Of (S) (I), Table_Of (S) (I).Length - 1));

   --  The rows the decoder visits, by output position.
   function Decode_Order (Last : String) return Mapping
   with
     Pre  => Supported (Last),
     Post =>
       Decode_Order'Result'First = 1
       and then Decode_Order'Result'Length = Last'Length
       and then Permutation (Decode_Order'Result)
       and then Orders.Is_Order
                  (LF (Last),
                   Decode_Order'Result,
                   Permutations.Inverse (Decode_Order'Result));

   function Decode (Last : String) return String
   with
     Pre  => Supported (Last),
     Post =>
       Supported (Decode'Result)
       and then Decode'Result'Length = Last'Length
       and then (for all P in Decode'Result'Range =>
                   Decode'Result (P) = Last (Decode_Order (Last) (P)));
end BWT.Bijective;
