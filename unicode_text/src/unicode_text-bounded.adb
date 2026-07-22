with Unicode_Text.UTF_8; use Unicode_Text.UTF_8;

package body Unicode_Text.Bounded
  with SPARK_Mode
is
   function Has_Valid_Representation
     (Data : Buffer; Used : Length_Range) return Boolean
   is
   begin
      if Used = 0 then
         pragma Assert (Static => Validate (Data (1 .. Used)).Valid);
         return True;
      else
         return Is_Valid_UTF_8 (Data (1 .. Used));
      end if;
   end Has_Valid_Representation;

   procedure Lemma_Copied_Bytes
     (Left         : String;
      Right        : String;
      Right_Offset : Natural;
      Count        : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Count <= Left'Length
       and then Right_Offset <= Right'Length
       and then Count <= Right'Length - Right_Offset
       and then
         (Count = 0
          or else
            (for all I in Natural range 0 .. Count - 1 =>
               Octet_At (Left, I) = Octet_At (Right, Right_Offset + I))),
     Post   => Same_Bytes (Left, 0, Right, Right_Offset, Count),
     Subprogram_Variant => (Decreases => Count)
   is
   begin
      if Count > 0 then
         Lemma_Copied_Bytes (Left, Right, Right_Offset, Count - 1);
      end if;
   end Lemma_Copied_Bytes;

   function Empty return Bounded_String is
   begin
      return (Data => (others => Character'Val (0)), Used => 0);
   end Empty;

   function Is_Empty (S : Bounded_String) return Boolean
   is (S.Used = 0);

   function Byte_Length (S : Bounded_String) return Natural
   is (S.Used);

   function Model (S : Bounded_String) return Text
   is (Unicode_Text.UTF_8.Model (S.Data (1 .. S.Used)));

   function To_Bounded_String (S : String) return Bounded_String is
      Result : Bounded_String := Empty;
   begin
      Append (Result, S);
      return Result;
   end To_Bounded_String;

   function To_String (S : Bounded_String) return String
   is (S.Data (1 .. S.Used));

   function Code_Point_Length (S : Bounded_String) return Natural
   is (Unicode_Text.UTF_8.Code_Point_Length (S.Data (1 .. S.Used)));

   function Element
     (S : Bounded_String; Index : Positive) return Scalar_Value
   is (Unicode_Text.UTF_8.Element (S.Data (1 .. S.Used), Index));

   procedure Clear (S : out Bounded_String) is
   begin
      S := Empty;
   end Clear;

   procedure Append (S : in out Bounded_String; Other : String) is
      Old_Used : constant Natural := S.Used;
      New_Used : constant Length_Range := Old_Used + Other'Length;
      New_Data : Buffer := S.Data;
      Before   : constant String := S.Data (1 .. S.Used)
      with Ghost => Static;

      procedure Lemma_Final_Representation
        (Data : Buffer; Used : Length_Range)
      with
        Ghost  => Static,
        Global => null,
        Pre    => Is_Valid_UTF_8 (Data (1 .. Used)),
        Post   => Has_Valid_Representation (Data, Used)
      is
      begin
         if Used = 0 then
            pragma Assert
              (Static => Has_Valid_Representation (Data, Used));
         else
            pragma Assert
              (Static => Has_Valid_Representation (Data, Used));
         end if;
      end Lemma_Final_Representation;
   begin
      New_Data (Old_Used + 1 .. New_Used) := Other;

      declare
         After : constant String := New_Data (1 .. New_Used)
         with Ghost => Static;
      begin
         pragma Assert
           (Static =>
              Other'Length = 0
              or else
                (for all I in Natural range 0 .. Other'Length - 1 =>
                   Octet_At (Other, I)
                   = Octet_At (After, Before'Length + I)));
         Lemma_Copied_Bytes
           (Other, After, Before'Length, Other'Length);
         pragma Assert
           (Static => Is_Byte_Concatenation (Before, Other, After));
         Lemma_Concatenation (Before, Other, After);
         pragma Assert
           (Static => Is_Valid_UTF_8 (New_Data (1 .. New_Used)));
         Lemma_Final_Representation (New_Data, New_Used);
         pragma Assert
           (Static => Has_Valid_Representation (New_Data, New_Used));
         S := (Data => New_Data, Used => New_Used);
      end;
   end Append;

   procedure Append (S : in out Bounded_String; Value : Scalar_Value) is
      Encoded : constant String := Encode_One (Value);
   begin
      Lemma_Encode_Decode (Value);
      Append (S, Encoded);
   end Append;

   procedure Append
     (S : in out Bounded_String; Other : Bounded_String)
   is
   begin
      Append (S, Other.Data (1 .. Other.Used));
   end Append;

   overriding function "="
     (Left, Right : Bounded_String) return Boolean
   is
      Left_Active  : constant String := Left.Data (1 .. Left.Used)
      with Ghost => Static;
      Right_Active : constant String := Right.Data (1 .. Right.Used)
      with Ghost => Static;
   begin
      Lemma_Equality (Left_Active, Right_Active);
      return
        Left.Used = Right.Used
        and then Left.Data (1 .. Left.Used) = Right.Data (1 .. Right.Used);
   end "=";

   function Byte_Offset (Cursor : Cursor_Type) return Natural
   is (Unicode_Text.UTF_8.Byte_Offset (Cursor));

   function Model_Index (Cursor : Cursor_Type) return Cursor_Index
   is (Unicode_Text.UTF_8.Model_Index (Cursor));

   function Big_Model_Index (Cursor : Cursor_Type) return Big_Positive
   is (Unicode_Text.UTF_8.Big_Model_Index (Cursor));

   function Is_Valid_Cursor
     (S : Bounded_String; Cursor : Cursor_Type) return Boolean
   is
     (Unicode_Text.UTF_8.Is_Valid_Cursor
        (S.Data (1 .. S.Used), Cursor));

   function First (S : Bounded_String) return Cursor_Type
   is (Unicode_Text.UTF_8.First (S.Data (1 .. S.Used)));

   function Has_Element
     (S : Bounded_String; Cursor : Cursor_Type) return Boolean
   is
     (Unicode_Text.UTF_8.Has_Element
        (S.Data (1 .. S.Used), Cursor));

   procedure Next
     (S      : Bounded_String;
      Cursor : in out Cursor_Type;
      Value  : out Scalar_Value) is
   begin
      Unicode_Text.UTF_8.Next (S.Data (1 .. S.Used), Cursor, Value);
   end Next;

end Unicode_Text.Bounded;
