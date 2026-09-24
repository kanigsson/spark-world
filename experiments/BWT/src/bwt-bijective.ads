with BWT.Factorizations;
with BWT.Rotations;

--  The bijective transform's internals, with the contracts its inverse laws
--  are proved from.

package BWT.Bijective
  with SPARK_Mode
is
   use BWT.Rotations;

   --  Duval emits the unique nonincreasing Lyndon factorization. Each factor
   --  contributes all its rotations, including every occurrence of duplicates.
   function Factor_Rotations (S : String) return Table
   with
     Pre  => Supported (S),
     Post => Factorizations.Factorization (S, Factor_Rotations'Result);
end BWT.Bijective;
