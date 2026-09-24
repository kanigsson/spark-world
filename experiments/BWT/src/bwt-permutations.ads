with BWT.Ranks;

package BWT.Permutations with SPARK_Mode, Ghost is
   use BWT.Ranks;

   function Inverse (Map : Mapping) return Mapping
   with Pre => Permutation (Map),
     Post => Inverse'Result'First = 1
       and then Inverse'Result'Length = Map'Length
       and then Permutation (Inverse'Result)
       and then (for all I in Map'Range => Inverse'Result (Map (I)) = I)
       and then (for all I in Map'Range => Map (Inverse'Result (I)) = I);

   procedure Swap (Map : in out Mapping; A, B : Positive)
   with Pre => Permutation (Map) and then A in Map'Range and then B in Map'Range,
     Post => Permutation (Map)
       and then (for all I in Map'Range => Map (I) =
         (if I = A then Map'Old (B) elsif I = B then Map'Old (A) else Map'Old (I)));
end BWT.Permutations;
