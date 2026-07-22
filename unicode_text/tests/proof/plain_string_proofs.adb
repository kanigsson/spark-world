with SPARK.Big_Integers;  use SPARK.Big_Integers;
with Unicode_Text;        use Unicode_Text;
with Unicode_Text.Models; use Unicode_Text.Models;
with Unicode_Text.UTF_8;  use Unicode_Text.UTF_8;

package body Plain_String_Proofs
  with SPARK_Mode
is

   procedure Count_With_Cursor (S : String; Count : out Natural) is
      Cursor : Cursor_Type := First (S);
      Value  : Scalar_Value;
   begin
      Count := 0;
      while Has_Element (S, Cursor) loop
         pragma Loop_Invariant (Static => Is_Valid_Cursor (S, Cursor));
         pragma Loop_Invariant
           (Static =>
              Big_Model_Index (Cursor) = To_Big_Integer (Count) + 1);
         pragma Loop_Variant (Decreases => S'Length - Byte_Offset (Cursor));

         Next (S, Cursor, Value);
         pragma Assert (Value in Scalar_Value);
         Count := Count + 1;
      end loop;
   end Count_With_Cursor;

   procedure Visit_In_Model_Order (S : String) is
      Cursor : Cursor_Type := First (S);
      Value  : Scalar_Value;
   begin
      while Has_Element (S, Cursor) loop
         pragma Loop_Invariant (Static => Is_Valid_Cursor (S, Cursor));
         pragma Loop_Variant (Decreases => S'Length - Byte_Offset (Cursor));

         declare
            Index : constant Big_Positive := Big_Model_Index (Cursor)
            with Ghost => Static;
         begin
            Next (S, Cursor, Value);
            pragma Assert
              (Static =>
                 Value = Scalar_Sequences.Get (Model (S), Index));
         end;
      end loop;
   end Visit_In_Model_Order;

   procedure Equal_Active_Prefixes
     (Left, Right : String; Used : Natural)
   is
      Left_Active  : constant String := Prefix_Bytes (Left, Used)
      with Ghost => Static;
      Right_Active : constant String := Prefix_Bytes (Right, Used)
      with Ghost => Static;
   begin
      Lemma_Same_Bytes_Prefixes (Left, Right, Used);
      Lemma_Same_Bytes_Whole_Equality (Left_Active, Right_Active);
      Lemma_Equality (Left_Active, Right_Active);
   end Equal_Active_Prefixes;

   procedure Append_Valid_String
     (Before, Appended, After : String) is
   begin
      Lemma_Concatenation (Before, Appended, After);
   end Append_Valid_String;

   procedure Slice_Uses_Model
     (S : String; First : Positive; Count : Natural)
   is
      Result : constant String := Slice (S, First, Count)
      with Ghost => Static;
   begin
      pragma Assert
        (Static =>
           Is_Slice
             (Source => Model (S),
              First  => To_Big_Integer (First),
              Count  => To_Big_Integer (Count),
              Result => Model (Result)));
   end Slice_Uses_Model;

   procedure Search_Uses_Model
     (Haystack : String;
      Needle   : String;
      From     : Positive;
      Result   : out Natural)
   is
   begin
      Result := Find (Haystack, Needle, From);
   end Search_Uses_Model;

   procedure Search_Witnesses is
      Source          : constant String := "aba" with Ghost => Static;
      Positive_Needle : constant String := "ba" with Ghost => Static;
      Negative_Needle : constant String := "z" with Ghost => Static;
      Empty_Needle    : constant String := "" with Ghost => Static;
   begin
      Lemma_ASCII_Valid (Source);
      Lemma_ASCII_Valid (Positive_Needle);
      Lemma_ASCII_Valid (Negative_Needle);
      Lemma_ASCII_Valid (Empty_Needle);
      declare
         Positive_Result : constant Natural := Find (Source, Positive_Needle)
         with Ghost => Static;
         Negative_Result : constant Natural := Find (Source, Negative_Needle)
         with Ghost => Static;
         Empty_Result    : constant Natural :=
           Find (Source, Empty_Needle, From => 4)
         with Ghost => Static;
      begin
         pragma Assert
           (Static =>
              Is_First_Occurrence
                (Haystack => Model (Source),
                 Needle   => Model (Positive_Needle),
                 From     => 1,
                 Result   => To_Big_Integer (Positive_Result)));
         pragma Assert
           (Static =>
              Is_First_Occurrence
                (Haystack => Model (Source),
                 Needle   => Model (Negative_Needle),
                 From     => 1,
                 Result   => To_Big_Integer (Negative_Result)));
         pragma Assert (Static => Empty_Result = 4);
         pragma Assert
           (Static =>
              Contains (Source, Positive_Needle)
              = Unicode_Text.Models.Contains
                  (Model (Source), Model (Positive_Needle)));
         pragma Assert
           (Static =>
              Contains (Source, Negative_Needle)
              = Unicode_Text.Models.Contains
                  (Model (Source), Model (Negative_Needle)));
      end;
   end Search_Witnesses;

end Plain_String_Proofs;
