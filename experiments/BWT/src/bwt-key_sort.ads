with BWT.Ranks;

--  A stable counting sort over small integer keys. It is Ranks.LF with the
--  alphabet replaced by 0 .. Buckets - 1.

package BWT.Key_Sort
  with SPARK_Mode
is
   use BWT.Ranks;

   type Keys is array (Positive range <>) of Natural;

   function Bounded (K : Keys; Buckets : Positive) return Boolean
   is (K'First = 1
       and then K'Length <= Max_Length
       and then Buckets <= Max_Length
       and then (for all X of K => X < Buckets));

   function Ordered (K : Keys; A, B : Positive) return Boolean
   is (K (A) < K (B) or else (K (A) = K (B) and then A <= B))
   with Pre => A in K'Range and then B in K'Range;

   --  Where each element lands when the elements are sorted by key, equal
   --  keys keeping their order.
   function Place (K : Keys; Buckets : Positive) return Mapping
   with
     Pre  => Bounded (K, Buckets),
     Post =>
       Place'Result'First = 1
       and then Place'Result'Length = K'Length
       and then Permutation (Place'Result)
       and then (for all I in K'Range =>
                   (for all J in K'Range =>
                      (Ordered (K, I, J)
                       = (Place'Result (I) <= Place'Result (J)))));
end BWT.Key_Sort;
