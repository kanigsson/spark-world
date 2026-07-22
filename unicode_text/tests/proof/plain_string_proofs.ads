with Unicode_Text.Models;
with Unicode_Text.UTF_8;

package Plain_String_Proofs
  with SPARK_Mode
is
   use type Unicode_Text.Models.Scalar_Sequences.Sequence;

   procedure Count_With_Cursor (S : String; Count : out Natural)
   with
     Pre  => Unicode_Text.UTF_8.Is_Valid_UTF_8 (S),
     Post => Count = Unicode_Text.UTF_8.Code_Point_Length (S);

   procedure Visit_In_Model_Order (S : String)
   with
     Ghost => Static,
     Global => null,
     Pre    => Unicode_Text.UTF_8.Is_Valid_UTF_8 (S);

   procedure Equal_Active_Prefixes
     (Left, Right : String; Used : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Used <= Left'Length
       and then Used <= Right'Length
       and then
         Unicode_Text.UTF_8.Is_Valid_UTF_8
           (Unicode_Text.UTF_8.Prefix_Bytes (Left, Used))
       and then
         Unicode_Text.UTF_8.Is_Valid_UTF_8
           (Unicode_Text.UTF_8.Prefix_Bytes (Right, Used))
       and then
         Unicode_Text.UTF_8.Same_Bytes (Left, 0, Right, 0, Used),
     Post   =>
       Unicode_Text.UTF_8.Prefix_Bytes (Left, Used)
       = Unicode_Text.UTF_8.Prefix_Bytes (Right, Used)
       and then
         Unicode_Text.UTF_8.Model
           (Unicode_Text.UTF_8.Prefix_Bytes (Left, Used))
         = Unicode_Text.UTF_8.Model
             (Unicode_Text.UTF_8.Prefix_Bytes (Right, Used));

   procedure Append_Valid_String
     (Before, Appended, After : String)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Unicode_Text.UTF_8.Is_Valid_UTF_8 (Before)
       and then Unicode_Text.UTF_8.Is_Valid_UTF_8 (Appended)
       and then Before'Length <= Natural'Last - Appended'Length
       and then
         Unicode_Text.UTF_8.Is_Byte_Concatenation
           (Before, Appended, After),
     Post   =>
       Unicode_Text.UTF_8.Is_Valid_UTF_8 (After)
       and then
         Unicode_Text.Models.Is_Concatenation
           (Unicode_Text.UTF_8.Model (Before),
            Unicode_Text.UTF_8.Model (Appended),
            Unicode_Text.UTF_8.Model (After));

end Plain_String_Proofs;
