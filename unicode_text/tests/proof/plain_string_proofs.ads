with Unicode_Text.UTF_8;

package Plain_String_Proofs
  with SPARK_Mode
is

   procedure Count_With_Cursor (S : String; Count : out Natural)
   with
     Pre  => Unicode_Text.UTF_8.Is_Valid_UTF_8 (S),
     Post => Count = Unicode_Text.UTF_8.Code_Point_Length (S);

   procedure Visit_In_Model_Order (S : String)
   with
     Ghost,
     Global => null,
     Pre    => Unicode_Text.UTF_8.Is_Valid_UTF_8 (S);

end Plain_String_Proofs;
