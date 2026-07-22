with Unicode_Text;        use Unicode_Text;
with Unicode_Text.Models; use Unicode_Text.Models;
with Unicode_Text.UTF_8;  use Unicode_Text.UTF_8;

package Byte_Layer_Proofs
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;

   procedure Scalar_Round_Trip (Value : Scalar_Value)
   with
     Ghost,
     Global => null,
     Post   =>
       Is_Valid_UTF_8 (Encode_One (Value))
       and then Decode_One (Encode_One (Value), 0).Value = Value
       and then
         Decode_One (Encode_One (Value), 0).Width = Encoding_Width (Value)
       and then
         Is_Append
           (Scalar_Sequences.Empty_Sequence,
            Value,
            Model (Encode_One (Value)));

   procedure Boundary_Witness
   with Ghost, Global => null;

end Byte_Layer_Proofs;
