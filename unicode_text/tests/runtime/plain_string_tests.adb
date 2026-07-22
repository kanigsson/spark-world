with Ada.Assertions;
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

   Check_Executable_Precondition;

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
   end;

   Put_Line ("Plain-string runtime tests passed:" & Checks'Image & " checks");
end Plain_String_Tests;
