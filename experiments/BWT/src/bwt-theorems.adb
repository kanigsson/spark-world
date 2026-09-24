package body BWT.Theorems
  with SPARK_Mode
is
   procedure Classical_Round_Trip (S : String) is
      Encoded : constant Classical_Result := Classical_Encode (S);
      Decoded : constant String :=
        Classical_Decode (Encoded.Last, Encoded.Primary);
   begin
      --  Both contracts describe position I through the same LF orbit step.
      for I in S'Range loop
         pragma Assert
           (Decoded (I)
            = Encoded.Last (Walk (Encoded.Last, Encoded.Primary, S'Length - I)));
         pragma Loop_Invariant (for all J in 1 .. I => Decoded (J) = S (J));
      end loop;
      pragma Assert (Decoded = S);
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
