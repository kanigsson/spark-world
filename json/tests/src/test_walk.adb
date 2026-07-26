--  Behavioural tests for JSON.Walk. Complements gnatprove: proof shows the
--  cursor stays in bounds and every step advances; these pin what the
--  helpers accept and reject. Runs with -gnata, so a contract violation
--  fails the run.

with Ada.Text_IO;       use Ada.Text_IO;
with Ada.Command_Line;
with Interfaces;        use type Interfaces.Integer_64;
with JSON.Pull;
with JSON.Walk;         use JSON.Walk;

procedure Test_Walk is

   use type JSON.Pull.State_Type;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("  ok   : " & Label);
      else
         Put_Line ("  FAIL : " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   function Text (Input : String; S : Span) return String is
     (Input (S.First .. S.Last));

begin
   --  Walk a small known shape: object, members in order, typed reads.
   declare
      Doc : constant String :=
        "{""name"": ""demo"", ""count"": 42, ""good"": true}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Key : Span;
      Val : Span;
      N   : Interfaces.Integer_64;
      B   : Boolean;
      Done : Boolean;
   begin
      Open_Object (Doc, P, St);
      Check (St = OK, "open object");
      Next_Member (Doc, P, Key, Done, St);
      Check (St = OK and then not Done
             and then Matches (Doc, Key, "name"), "first member is name");
      Get_String (Doc, P, Val, St);
      Check (St = OK and then Text (Doc, Val) = "demo"
             and then not Val.Escaped, "string payload");
      Next_Member (Doc, P, Key, Done, St);
      Check (St = OK and then Matches (Doc, Key, "count"), "second member");
      Get_Integer (Doc, P, N, St);
      Check (St = OK and then N = 42, "integer value");
      Next_Member (Doc, P, Key, Done, St);
      Check (St = OK and then Matches (Doc, Key, "good"), "third member");
      Get_Boolean (Doc, P, B, St);
      Check (St = OK and then B, "boolean value");
      Next_Member (Doc, P, Key, Done, St);
      Check (St = OK and then Done, "object end reported as Done");
   end;

   --  Find_Member skips earlier members of any shape, including nested
   --  containers, and stands before the found member's value.
   declare
      Doc : constant String :=
        "{""extra"": [1, {""deep"": [true, null]}, 3]," &
        " ""blob"": {""a"": 1, ""b"": [2]}," &
        " ""wanted"": 7}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Found : Boolean;
      N   : Interfaces.Integer_64;
   begin
      Open_Object (Doc, P, St);
      Check (St = OK, "open object (find test)");
      Find_Member (Doc, P, "wanted", Found, St);
      Check (St = OK and then Found, "found member behind nested skips");
      Get_Integer (Doc, P, N, St);
      Check (St = OK and then N = 7, "value after find");
   end;

   --  Find_Member on a missing name consumes the object and reports
   --  not-found without an error.
   declare
      Doc : constant String := "{""a"": 1, ""b"": 2}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Found : Boolean;
   begin
      Open_Object (Doc, P, St);
      Find_Member (Doc, P, "missing", Found, St);
      Check (St = OK and then not Found, "missing member: OK, not found");
      Check (P.State = JSON.Pull.Expect_EOF, "object fully consumed");
   end;

   --  Arrays: objects and strings, including empty arrays.
   declare
      Doc : constant String := "[{""x"": 1}, {}]";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Done, Found : Boolean;
   begin
      Open_Array (Doc, P, St);
      Next_Element_Object (Doc, P, Done, St);
      Check (St = OK and then not Done, "first element object");
      Find_Member (Doc, P, "x", Found, St);
      Check (St = OK and then Found, "member in element");
      Skip_Value (Doc, P, St);
      Check (St = OK, "skip element member value");
      Find_Member (Doc, P, "none", Found, St);   --  consumes to object end
      Check (St = OK and then not Found, "element consumed");
      Next_Element_Object (Doc, P, Done, St);
      Check (St = OK and then not Done, "second element object");
      Find_Member (Doc, P, "any", Found, St);
      Check (St = OK and then not Found, "empty element object");
      Next_Element_Object (Doc, P, Done, St);
      Check (St = OK and then Done, "array end");
   end;

   declare
      Doc : constant String := "[""one"", ""two""]";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Done : Boolean;
      Val  : Span;
   begin
      Open_Array (Doc, P, St);
      Next_Element_String (Doc, P, Val, Done, St);
      Check (St = OK and then not Done
             and then Text (Doc, Val) = "one", "string element 1");
      Next_Element_String (Doc, P, Val, Done, St);
      Check (St = OK and then not Done
             and then Text (Doc, Val) = "two", "string element 2");
      Next_Element_String (Doc, P, Val, Done, St);
      Check (St = OK and then Done, "string array end");
   end;

   --  Skip_Value consumes exactly one whole value at the top level.
   declare
      Doc : constant String := "{""a"": [[[1], 2], {""k"": [3]}]}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
   begin
      Skip_Value (Doc, P, St);
      Check (St = OK and then P.State = JSON.Pull.Expect_EOF,
             "skip whole nested document");
   end;

   --  Wrong shape: valid JSON that is not what was asked for.
   declare
      Doc : constant String := "[1]";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
   begin
      Open_Object (Doc, P, St);
      Check (St = Wrong_Shape, "array where object expected");
   end;

   declare
      Doc : constant String := "{""n"": ""text""}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Found : Boolean;
      N   : Interfaces.Integer_64;
   begin
      Open_Object (Doc, P, St);
      Find_Member (Doc, P, "n", Found, St);
      Get_Integer (Doc, P, N, St);
      Check (St = Wrong_Shape and then N = 0, "string where integer expected");
   end;

   declare
      Doc : constant String := "{""n"": 3.5}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Found : Boolean;
      N   : Interfaces.Integer_64;
   begin
      Open_Object (Doc, P, St);
      Find_Member (Doc, P, "n", Found, St);
      Get_Integer (Doc, P, N, St);
      Check (St = Wrong_Shape and then N = 0, "float where integer expected");
   end;

   declare
      Doc : constant String := "{""n"": 99999999999999999999999999}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Found : Boolean;
      N   : Interfaces.Integer_64;
   begin
      Open_Object (Doc, P, St);
      Find_Member (Doc, P, "n", Found, St);
      Get_Integer (Doc, P, N, St);
      Check (St = Wrong_Shape and then N = 0, "integer beyond Integer_64");
   end;

   --  Escaped and raw spellings compare as decoded JSON text. The first
   --  logically equal member wins.
   declare
      Doc : constant String := "{""a\u0062c"": 1, ""abc"": 2}";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Found : Boolean;
      N   : Interfaces.Integer_64;
   begin
      Open_Object (Doc, P, St);
      Find_Member (Doc, P, "abc", Found, St);
      Check (St = OK and then Found, "escaped ASCII key matched");
      Get_Integer (Doc, P, N, St);
      Check (St = OK and then N = 1, "first logical twin's value read");
   end;

   declare
      E_Acute : constant String :=
        (1 => Character'Val (16#C3#), 2 => Character'Val (16#A9#));
      G_Clef : constant String :=
        (1 => Character'Val (16#F0#), 2 => Character'Val (16#9D#),
         3 => Character'Val (16#84#), 4 => Character'Val (16#9E#));

      procedure Check_Key
        (Doc, Name : String; Expected : Boolean; Label : String)
      is
         P    : JSON.Pull.Parser;
         St   : Step_Status;
         Key  : Span;
         Done : Boolean;
      begin
         Open_Object (Doc, P, St);
         Next_Member (Doc, P, Key, Done, St);
         Check
           (St = OK
            and then not Done
            and then Matches (Doc, Key, Name) = Expected,
            Label);
      end Check_Key;
   begin
      Check_Key
        ("{""\u00e9"": 1}", E_Acute, True, "escaped BMP key");
      Check_Key
        ("{""\ud834\udd1e"": 1}", G_Clef, True,
         "escaped supplementary key");
      Check_Key
        ("{""a\u0062c"": 1}", "abd", False, "different escaped key");
      Check_Key
        ("{""\\"": 1}", "\", True, "escaped reverse solidus key");
      Check_Key
        ("{""" & E_Acute & """: 1}", E_Acute, True,
         "raw non-ASCII key");
   end;

   --  Bad JSON: truncated and garbage documents report Bad_JSON, never
   --  raise.
   declare
      Doc : constant String := "{""a"": [1, 2";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
      Found : Boolean;
   begin
      Open_Object (Doc, P, St);
      Find_Member (Doc, P, "a", Found, St);
      Check (St = OK and then Found, "key before truncation found");
      Skip_Value (Doc, P, St);
      Check (St = Bad_JSON, "truncated container: Bad_JSON");
   end;

   declare
      Doc : constant String := "nonsense";
      P   : JSON.Pull.Parser;
      St  : Step_Status;
   begin
      Open_Object (Doc, P, St);
      Check (St = Bad_JSON, "garbage: Bad_JSON");
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Walk;
