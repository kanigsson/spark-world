package body Byte_Layer_Proofs
  with SPARK_Mode
is

   procedure Scalar_Round_Trip (Value : Scalar_Value) is
   begin
      Lemma_Encode_Decode (Value);
   end Scalar_Round_Trip;

   procedure Boundary_Witness is
   begin
      Lemma_Encode_Decode (16#0000#);
      Lemma_Encode_Decode (16#007F#);
      Lemma_Encode_Decode (16#0080#);
      Lemma_Encode_Decode (16#07FF#);
      Lemma_Encode_Decode (16#0800#);
      Lemma_Encode_Decode (16#D7FF#);
      Lemma_Encode_Decode (16#E000#);
      Lemma_Encode_Decode (16#FFFF#);
      Lemma_Encode_Decode (16#1_0000#);
      Lemma_Encode_Decode (16#10_FFFF#);
   end Boundary_Witness;

end Byte_Layer_Proofs;
