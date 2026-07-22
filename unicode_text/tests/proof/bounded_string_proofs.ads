package Bounded_String_Proofs
  with SPARK_Mode
is

   procedure Fill_Exact_Capacity
   with Ghost => Static, Global => null;

   procedure Repeated_Appends
   with Ghost => Static, Global => null;

end Bounded_String_Proofs;
