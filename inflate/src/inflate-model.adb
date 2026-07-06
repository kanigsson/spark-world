package body Inflate.Model with SPARK_Mode => On is

   ------------------------
   -- Lemma_Encodes_Step --
   ------------------------

   procedure Lemma_Encodes_Step
     (C : Byte_Array; CF : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; DL : Natural)
   is null;

   --------------------------
   -- Lemma_Encodes_Frame --
   --------------------------

   procedure Lemma_Encodes_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; D2 : Byte_Array; DF : Positive; DL : Natural)
   is
      Len : constant Natural := Block_Length (C1, CF);
   begin
      pragma Assert (Block_Length (C2, CF) = Len);
      if C1 (CF) /= 1 then
         --  Not the final block: the tail relation transfers by induction
         --  on the remaining stream, then this block's own fields transfer
         --  byte for byte.
         Lemma_Encodes_Frame
           (C1, C2, CF + 5 + Len, CL, D1, D2, DF + Len, DL);
      end if;
   end Lemma_Encodes_Frame;

end Inflate.Model;
