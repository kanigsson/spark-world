package body BWT.Theorems
  with SPARK_Mode
is
   procedure Classical_Round_Trip (S : String) is
      Encoded : constant Classical_Result := Classical_Encode (S);
   begin
      pragma Assert (Classical_Decode (Encoded.Last, Encoded.Primary) = S);
   end Classical_Round_Trip;

   procedure Bijective_Round_Trip (S : String) is
   begin
      pragma Assert (Bijective_Decode (Bijective_Encode (S)) = S);
   end Bijective_Round_Trip;

   procedure Bijective_Onto (Last : String) is
   begin
      pragma Assert (Bijective_Encode (Bijective_Decode (Last)) = Last);
   end Bijective_Onto;
end BWT.Theorems;
