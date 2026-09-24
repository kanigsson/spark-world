--  Proof targets, not established lemmas. The bodies deliberately contain the
--  outstanding equalities: no assumptions, imported axioms or suppression.

package BWT.Theorems
  with SPARK_Mode, Ghost
is
   procedure Classical_Round_Trip (S : String)
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Classical_Decode
         (Classical_Encode (S).Last, Classical_Encode (S).Primary)
       = S;

   procedure Bijective_Round_Trip (S : String)
   with
     Global => null,
     Pre    => Supported (S),
     Post   => Bijective_Decode (Bijective_Encode (S)) = S;

   --  The second direction rules out a mere injection on a restricted image.
   procedure Bijective_Onto (Last : String)
   with
     Global => null,
     Pre    => Supported (Last),
     Post   => Bijective_Encode (Bijective_Decode (Last)) = Last;
end BWT.Theorems;
