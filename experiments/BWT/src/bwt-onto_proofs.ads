with BWT.Bijective;

--  Every last column is the transform of what it decodes to.

package BWT.Onto_Proofs
  with SPARK_Mode, Ghost
is
   procedure Onto (Last : String)
   with
     Global => null,
     Pre    => Supported (Last),
     Post   => Bijective.Encode (Bijective.Decode (Last)) = Last;
end BWT.Onto_Proofs;
