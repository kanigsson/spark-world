with BWT.Bijective;
with BWT.Ranks;

--  The bijective transform's inverse laws.

package BWT.Bijective_Proofs
  with SPARK_Mode, Ghost
is
   procedure Round_Trip (S : String)
   with
     Global => null,
     Pre    => Supported (S),
     Post   => Bijective.Decode (Bijective.Encode (S)) = S;

   --  LF is exact on the bijective table: it moves each row to the row of
   --  the rotation one letter earlier in the same factor.
   procedure LF_Exact (S : String)
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       (for all K in 1 .. S'Length =>
          Bijective.Table_Of (S) (Ranks.LF (Bijective.Encode (S)) (K))
          = Previous (Bijective.Table_Of (S) (K)));
end BWT.Bijective_Proofs;
