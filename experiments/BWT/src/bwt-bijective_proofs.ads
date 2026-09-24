with BWT.Bijective;

--  The bijective transform's inverse laws.

package BWT.Bijective_Proofs
  with SPARK_Mode, Ghost
is
   procedure Round_Trip (S : String)
   with
     Global => null,
     Pre    => Supported (S),
     Post   => Bijective.Decode (Bijective.Encode (S)) = S;
end BWT.Bijective_Proofs;
