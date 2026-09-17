with Ada.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;        use Ada.Text_IO;
with Unicode_Text;       use Unicode_Text;
with Unicode_Text.UTF_8; use Unicode_Text.UTF_8;

procedure Plain_String_Tests is

   Checks : Natural := 0;

   function C (Value : Octet) return Character
   is (Character'Val (Value));

   procedure Check (Condition : Boolean; Message : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Check_Executable_Precondition is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Scalar_Value := Element ([1 => C (16#80#)], 1);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Ada.Assertions.Assertion_Error =>
            Raised := True;
      end;
      Check (Raised, "invalid UTF-8 precondition is checked");
   end Check_Executable_Precondition;

   procedure Check_Empty_Split_Separator is
      Raised    : Boolean := False;
      State     : Split_State := Start_Split;
      Segment   : Byte_Span;
      Has_Value : Boolean;
   begin
      begin
         Next ("text", "", State, Segment, Has_Value);
      exception
         when Ada.Assertions.Assertion_Error =>
            Raised := True;
      end;
      Check (Raised, "empty split separator is rejected");
   end Check_Empty_Split_Separator;

   procedure Check_Substring_Split
     (Source : String; Separator : String; Expected_Count : Positive)
   is
      State         : Split_State := Start_Split;
      Segment       : Byte_Span;
      Has_Value     : Boolean;
      Count         : Natural := 0;
      Reconstructed : Unbounded_String;
   begin
      loop
         Next (Source, Separator, State, Segment, Has_Value);
         exit when not Has_Value;
         if Count > 0 then
            Append (Reconstructed, Separator);
         end if;
         declare
            Part : constant String := Slice (Source, Segment);
         begin
            Check (not Contains (Part, Separator), "split delimiter absence");
            Append (Reconstructed, Part);
         end;
         Count := Count + 1;
      end loop;
      Check (Count = Expected_Count, "substring split segment count");
      Check (To_String (Reconstructed) = Source, "substring split reconstructs");
      Check (Split_Complete (State), "substring split completes");
      Check
        (Split_Model_Index (State)
         = (if Code_Point_Length (Source) = 0
            then 1
            else Cursor_Index (Code_Point_Length (Source)) + 1),
         "substring split reaches model end");
   end Check_Substring_Split;

   procedure Check_Scalar_Split
     (Source : String; Separator : Scalar_Value; Expected_Count : Positive)
   is
      State         : Split_State := Start_Split;
      Segment       : Byte_Span;
      Has_Value     : Boolean;
      Count         : Natural := 0;
      Reconstructed : Unbounded_String;
      Encoded       : constant String := Encode_One (Separator);
   begin
      loop
         Next (Source, Separator, State, Segment, Has_Value);
         exit when not Has_Value;
         if Count > 0 then
            Append (Reconstructed, Encoded);
         end if;
         declare
            Part : constant String := Slice (Source, Segment);
         begin
            Check (Find (Part, Separator) = 0, "scalar split delimiter absence");
            Append (Reconstructed, Part);
         end;
         Count := Count + 1;
      end loop;
      Check (Count = Expected_Count, "scalar split segment count");
      Check (To_String (Reconstructed) = Source, "scalar split reconstructs");
      Check (Split_Complete (State), "scalar split completes");
   end Check_Scalar_Split;

   A       : constant String := "A";
   U_0080  : constant String := [C (16#C2#), C (16#80#)];
   U_0800  : constant String := [C (16#E0#), C (16#A0#), C (16#80#)];
   U_10000 : constant String :=
     [C (16#F0#), C (16#90#), C (16#80#), C (16#80#)];
   Mixed   : constant String := A & U_0080 & U_0800 & U_10000;

begin
   Check (Byte_Length ("") = 0, "empty byte length");
   Check (Code_Point_Length ("") = 0, "empty code-point length");
   Check (Byte_Length (Mixed) = 10, "mixed byte length");
   Check (Code_Point_Length (Mixed) = 4, "mixed code-point length");
   Check (Element (Mixed, 1) = 16#41#, "mixed element 1");
   Check (Element (Mixed, 2) = 16#80#, "mixed element 2");
   Check (Element (Mixed, 3) = 16#800#, "mixed element 3");
   Check (Element (Mixed, 4) = 16#1_0000#, "mixed element 4");

   declare
      Cursor           : Cursor_Type := First (Mixed);
      Value            : Scalar_Value;
      Expected_Offsets : constant array (Positive range 1 .. 5) of Natural :=
        [0, 1, 3, 6, 10];
      Expected_Values  : constant array (Positive range 1 .. 4) of Scalar_Value :=
        [16#41#, 16#80#, 16#800#, 16#1_0000#];
   begin
      for Index in Expected_Values'Range loop
         Check (Has_Element (Mixed, Cursor), "cursor has element");
         Check
           (Byte_Offset (Cursor) = Expected_Offsets (Index),
            "cursor byte offset");
         Check
           (Model_Index (Cursor) = Cursor_Index (Index),
            "cursor model index");
         Next (Mixed, Cursor, Value);
         Check (Value = Expected_Values (Index), "cursor value");
      end loop;
      Check (not Has_Element (Mixed, Cursor), "cursor reaches end");
      Check (Byte_Offset (Cursor) = Expected_Offsets (5), "cursor end offset");
      Check (Model_Index (Cursor) = 5, "cursor end model index");
   end;

   Check (Is_Prefix ("", Mixed), "empty prefix");
   Check (Is_Prefix (A & U_0080, Mixed), "multibyte prefix");
   Check (not Is_Prefix (A & U_0800, Mixed), "prefix mismatch");
   Check (Is_Suffix ("", Mixed), "empty suffix");
   Check (Is_Suffix (U_0800 & U_10000, Mixed), "multibyte suffix");
   Check (not Is_Suffix (U_0080 & U_10000, Mixed), "suffix mismatch");

   Check (Compare ("", A) = Less, "empty comparison");
   Check (Compare (A, A) = Equal, "equal comparison");
   Check (Compare (A, A & A) = Less, "prefix comparison");
   Check (Compare (U_0080, A) = Greater, "two-byte comparison");
   Check (Compare (U_0800, U_10000) = Less, "wide comparison");

   declare
      Middle : constant Byte_Span := To_Byte_Span (Mixed, 2, 2);
      At_End : constant Byte_Span := To_Byte_Span (Mixed, 5, 0);
   begin
      Check
        (Middle = (First => 1, Past_Last => 6),
         "mixed code-point span");
      Check (Is_Valid_Byte_Span (Mixed, Middle), "mixed span validity");
      Check (Slice (Mixed, Middle) = U_0080 & U_0800, "span slice");
      Check (Slice (Mixed, 2, 2) = U_0080 & U_0800, "indexed slice");
      Check
        (At_End = (First => Mixed'Length, Past_Last => Mixed'Length),
         "empty ending span");
      Check (Slice (Mixed, At_End) = "", "empty ending slice");
   end;

   Check (Find (Mixed, Scalar_Value'(16#41#)) = 1, "find ASCII scalar");
   Check (Find (Mixed, Scalar_Value'(16#80#)) = 2, "find two-byte scalar");
   Check (Find (Mixed, Scalar_Value'(16#800#)) = 3, "find three-byte scalar");
   Check
     (Find (Mixed, Scalar_Value'(16#1_0000#)) = 4,
      "find four-byte scalar");
   Check
     (Find (Mixed, Scalar_Value'(16#80#), From => 3) = 0,
      "scalar search from later position");
   Check
     (Reverse_Find (Mixed & U_0080, Scalar_Value'(16#80#)) = 5,
      "reverse scalar search");
   Check
     (Find (Mixed, U_0080 & U_0800) = 2,
      "find multibyte substring");
   Check
     (Find (Mixed, U_0080 & U_0800, From => 3) = 0,
      "substring search from later position");
   Check (Find (Mixed, "") = 1, "empty needle at start");
   Check (Find (Mixed, "", From => 5) = 5, "empty needle at end");
   Check (Contains (Mixed, U_0800 & U_10000), "substring containment");
   Check (not Contains (Mixed, U_10000 & U_0800), "missing substring");
   Check (Find ("aaa", "aa") = 1, "overlapping first substring");
   Check (Find ("aaa", "aa", From => 2) = 2, "overlapping search from");

   Check_Substring_Split ("", ",", 1);
   Check_Substring_Split ("abc", ",", 1);
   Check_Substring_Split (",a,,b,", ",", 5);
   Check_Substring_Split ("aaa", "aa", 2);
   Check_Substring_Split
     (A & U_0080 & U_0800 & U_0080, U_0080, 3);
   Check_Scalar_Split (",a,,b,", Character'Pos (','), 5);
   Check_Scalar_Split
     (A & U_0080 & U_0800 & U_0080, 16#80#, 3);

   declare
      State     : Split_State := Start_Split;
      Segment   : Byte_Span;
      Has_Value : Boolean;
      Source    : constant String := ",a,,b,";
      Expected  : constant array (Positive range 1 .. 5) of Byte_Span :=
        [(0, 0), (1, 2), (3, 3), (4, 5), (6, 6)];
   begin
      for Index in Expected'Range loop
         Next (Source, ",", State, Segment, Has_Value);
         Check (Has_Value, "split has expected segment");
         Check (Segment = Expected (Index), "split span coordinates");
      end loop;
      Next (Source, ",", State, Segment, Has_Value);
      Check (not Has_Value, "completed split remains exhausted");
   end;

   Check_Executable_Precondition;
   Check_Empty_Split_Separator;

   declare
      Shifted : String (10 .. 19) := Mixed;
      Cursor  : Cursor_Type := First (Shifted);
      Value   : Scalar_Value;
   begin
      Check (Code_Point_Length (Shifted) = 4, "shifted code-point length");
      Check (Element (Shifted, 3) = 16#800#, "shifted element");
      Next (Shifted, Cursor, Value);
      Check (Value = 16#41#, "shifted cursor value");
      Check (Is_Prefix (A & U_0080, Shifted), "shifted prefix");
      Check (Compare (Shifted, Mixed) = Equal, "shifted comparison");
      Check (Slice (Shifted, 2, 2) = U_0080 & U_0800, "shifted slice");
      Check
        (Find (Shifted, U_0080 & U_0800) = 2,
         "shifted substring search");
      Check_Substring_Split (Shifted, U_0800, 2);
   end;

   Put_Line ("Plain-string runtime tests passed:" & Checks'Image & " checks");
end Plain_String_Tests;
