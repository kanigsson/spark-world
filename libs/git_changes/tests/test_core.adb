with Ada.Text_IO;
with Git_Changes.Core.Hunks;
with Git_Changes.Core.Raw;
with Git_Changes.Core.Validation;

procedure Test_Core is
   use Ada.Text_IO;
   package Raw renames Git_Changes.Core.Raw;
   package Hunks renames Git_Changes.Core.Hunks;
   package Validation renames Git_Changes.Core.Validation;
   use type Raw.Parse_Result;
   use type Raw.Raw_Status;
   use type Hunks.Hunk_Result;

   NUL : constant Character := Character'Val (0);
   LF  : constant Character := Character'Val (10);
   Z40 : constant String (1 .. 40) := (others => '0');
   A40 : constant String (1 .. 40) := (others => 'a');
   B40 : constant String (1 .. 40) := (others => 'b');
   A64 : constant String (1 .. 64) := (others => 'a');
   B64 : constant String (1 .. 64) := (others => 'b');

   Checks : Natural := 0;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Raw_Image
     (Old_Mode, New_Mode, Old_Id, New_Id, Status, Paths : String)
      return String is
     (":" & Old_Mode & " " & New_Mode & " " & Old_Id & " " & New_Id
      & " " & Status & NUL & Paths);

   procedure Expect_Error (Input : String; Expected : Raw.Parse_Result) is
      Cursor : Positive := 1;
      Item   : Raw.Raw_Record;
      Result : Raw.Parse_Result;
   begin
      Raw.Parse_Next (Input, Cursor, Item, Result);
      Check (Result = Expected,
             "expected " & Raw.Parse_Result'Image (Expected) & " got "
             & Raw.Parse_Result'Image (Result));
   end Expect_Error;

   procedure Test_Raw is
      M : constant String :=
        Raw_Image ("100644", "100755", A40, B40, "M", "a b" & NUL);
      R : constant String :=
        Raw_Image ("100644", "100644", A40, B40, "R100",
                "old" & Character'Val (9) & NUL
                & "new" & Character'Val (10) & Character'Val (255) & NUL);
      C : constant String :=
        Raw_Image ("100644", "100644", A40, B40, "C87",
                   "source" & NUL & "copy" & NUL);
      S256 : constant String :=
        Raw_Image ("000000", "100644", [1 .. 64 => '0'], B64, "A", "wide" & NUL);
      Cursor : Positive := 1;
      Item   : Raw.Raw_Record;
      Result : Raw.Parse_Result;
      Statuses : constant String := "ADMTUXB";
   begin
      Raw.Parse_Next (M, Cursor, Item, Result);
      Check (Result = Raw.Parsed, "valid modified record rejected");
      Check (Cursor = M'Last + 1, "cursor did not consume record");
      Check (Item.Status = Raw.Status_Modified, "wrong modified status");
      Check (Raw.Value (M, Item.Old_Mode) = "100644", "wrong old mode");
      Check (Raw.Value (M, Item.New_Mode) = "100755", "wrong new mode");
      Check (Raw.Value (M, Item.First_Path) = "a b", "wrong path");
      Check (not Item.Has_Second_Path, "unexpected second path");

      Cursor := 1;
      Raw.Parse_Next (R, Cursor, Item, Result);
      Check (Result = Raw.Parsed, "valid rename rejected");
      Check (Item.Status = Raw.Status_Renamed, "wrong rename status");
      Check (Item.Score_Present and then Item.Score = 100, "wrong rename score");
      Check (Item.Has_Second_Path, "rename lost second path");
      Check (Raw.Value (R, Item.Second_Path)'Length = 5, "byte path changed");

      Cursor := 1;
      Raw.Parse_Next (C, Cursor, Item, Result);
      Check (Result = Raw.Parsed and then Item.Status = Raw.Status_Copied,
             "valid copy rejected");
      Check (Item.Score_Present and then Item.Score = 87, "wrong copy score");

      Cursor := 1;
      Raw.Parse_Next (S256, Cursor, Item, Result);
      Check (Result = Raw.Parsed, "SHA-256 record rejected");
      Check (Item.Old_Object.Length = 64, "SHA-256 width lost");

      for Length in 0 .. M'Length - 1 loop
         declare
            Prefix : constant String := M (1 .. Length);
            C : Positive := 1;
         begin
            Raw.Parse_Next (Prefix, C, Item, Result);
            Check (Result /= Raw.Parsed, "truncated record accepted at" & Length'Image);
         end;
      end loop;

      Expect_Error ("x", Raw.Expected_Colon);
      Expect_Error (":100644", Raw.Missing_Field);
      Expect_Error
        (Raw_Image ("100648", "100644", A40, B40, "M", "x" & NUL),
         Raw.Invalid_Mode);
      Expect_Error
        (Raw_Image ("100644", "100644", A40 (1 .. 39), B40, "M", "x" & NUL),
         Raw.Invalid_Object_Id);
      Expect_Error
        (Raw_Image ("100644", "100644", A40, B40, "Q", "x" & NUL),
         Raw.Invalid_Status);
      Expect_Error
        (Raw_Image ("100644", "100644", A40, B40, "R101", "a" & NUL & "b" & NUL),
         Raw.Invalid_Score);
      Expect_Error
        (Raw_Image ("100644", "100644", A40, B40, "R", "a" & NUL & "b" & NUL),
         Raw.Invalid_Score);
      Expect_Error
        (Raw_Image ("100644", "100644", A40, B40, "M", ""), Raw.Missing_Path);
      Expect_Error
        (Raw_Image ("100644", "100644", A40, B40, "R50", "a" & NUL),
         Raw.Missing_Second_Path);

      for Status of Statuses loop
         declare
            One : constant String :=
              Raw_Image ("100644", "100644", A40, B40, String'(1 => Status),
                      "p" & NUL);
            C : Positive := 1;
         begin
            Raw.Parse_Next (One, C, Item, Result);
            Check (Result = Raw.Parsed, "status rejected: " & Status);
         end;
      end loop;

      declare
         Two : constant String := M & S256;
         C : Positive := 1;
      begin
         Raw.Parse_Next (Two, C, Item, Result);
         Check (Result = Raw.Parsed and then C = M'Last + 1, "first sequence record");
         Raw.Parse_Next (Two, C, Item, Result);
         Check (Result = Raw.Parsed and then C = Two'Last + 1, "second sequence record");
         Raw.Parse_Next (Two, C, Item, Result);
         Check (Result = Raw.End_Of_Input, "sequence end not reported");
      end;
   end Test_Raw;

   procedure Test_Validation is
      Value : Natural;
      Valid : Boolean;
      Last  : Natural;
      Max_Image : constant String := Natural'Image (Natural'Last);
   begin
      Check (Validation.Is_Octal_Mode ("100644"), "valid mode rejected");
      Check (not Validation.Is_Octal_Mode ("10064"), "short mode accepted");
      Check (not Validation.Is_Octal_Mode ("100648"), "non-octal mode accepted");
      Check (Validation.Is_Hex_Object_Id (A40), "SHA-1 rejected");
      Check (Validation.Is_Hex_Object_Id (A64), "SHA-256 rejected");
      Check (not Validation.Is_Hex_Object_Id (A40 & "a"), "odd hash width accepted");
      Check (Validation.Is_All_Zero (Z40), "zero object not recognized");
      Check (not Validation.Is_All_Zero (A40), "nonzero object called zero");

      Validation.Parse_Natural ("0", Value, Valid);
      Check (Valid and then Value = 0, "zero decimal rejected");
      Validation.Parse_Natural ("100", Value, Valid);
      Check (Valid and then Value = 100, "decimal parse failed");
      Validation.Parse_Natural ("", Value, Valid);
      Check (not Valid, "empty decimal accepted");
      Validation.Parse_Natural ("1x", Value, Valid);
      Check (not Valid, "non-decimal accepted");
      Validation.Parse_Natural (Max_Image (2 .. Max_Image'Last) & "0", Value, Valid);
      Check (not Valid, "overflowing decimal accepted");

      Validation.Checked_Last (10, 3, Last, Valid);
      Check (Valid and then Last = 12, "range end wrong");
      Validation.Checked_Last (Natural'Last, 2, Last, Valid);
      Check (not Valid, "overflowing range accepted");
      Check (Validation.Line_Count ("") = 0, "empty content has lines");
      Check (Validation.Line_Count ("one") = 1, "unterminated line not counted");
      Check (Validation.Line_Count ("one" & LF) = 1, "terminated line count wrong");
      Check
        (Validation.Line_Count ("one" & LF & "two") = 2,
         "mixed line count wrong");
   end Test_Validation;

   procedure Test_Hunks is
      Patch : constant String :=
        "diff --git a/a b/a" & LF
        & "@@ -1,2 +1,3 @@ heading" & LF
        & "@@ -10 +11 @@" & LF
        & "@@ -20,0 +21,2 @@" & LF
        & "@@ -30,4 +33,0 @@" & LF;
      Cursor : Positive := 1;
      Item   : Hunks.Hunk;
      Result : Hunks.Hunk_Result;
   begin
      Hunks.Parse_Next (Patch, Cursor, Item, Result);
      Check (Result = Hunks.Hunk_Parsed, "first hunk rejected");
      Check (Item.Old_Lines.First = 1 and then Item.Old_Lines.Count = 2,
             "old replacement range wrong");
      Check (Item.New_Lines.First = 1 and then Item.New_Lines.Count = 3,
             "new replacement range wrong");
      Hunks.Parse_Next (Patch, Cursor, Item, Result);
      Check (Result = Hunks.Hunk_Parsed
             and then Item.Old_Lines.Count = 1 and then Item.New_Lines.Count = 1,
             "implicit hunk counts wrong");
      Hunks.Parse_Next (Patch, Cursor, Item, Result);
      Check (Result = Hunks.Hunk_Parsed and then Item.Old_Lines.Count = 0
             and then Item.New_Lines.Count = 2, "insertion range wrong");
      Hunks.Parse_Next (Patch, Cursor, Item, Result);
      Check (Result = Hunks.Hunk_Parsed and then Item.Old_Lines.Count = 4
             and then Item.New_Lines.Count = 0, "deletion range wrong");
      Hunks.Parse_Next (Patch, Cursor, Item, Result);
      Check (Result = Hunks.No_More_Hunks, "hunk end not found");

      declare
         Bad : constant String := "@@ -0,1 +1,1 @@" & LF;
         C : Positive := 1;
      begin
         Hunks.Parse_Next (Bad, C, Item, Result);
         Check (Result = Hunks.Malformed_Hunk, "zero present line accepted");
      end;
      declare
         Bad : constant String := "@@ -1,0 +2,0 @@" & LF;
         C : Positive := 1;
      begin
         Hunks.Parse_Next (Bad, C, Item, Result);
         Check (Result = Hunks.Malformed_Hunk, "empty hunk accepted");
      end;

      for Length in 0 .. 16 loop
         declare
            Full : constant String := "@@ -12,3 +14,5 @@" & LF;
            Prefix : constant String := Full (1 .. Length);
            C : Positive := 1;
         begin
            Hunks.Parse_Next (Prefix, C, Item, Result);
            Check (Result /= Hunks.Hunk_Parsed, "truncated hunk accepted");
         end;
      end loop;
   end Test_Hunks;

begin
   Test_Validation;
   Test_Raw;
   Test_Hunks;
   Put_Line ("core tests: " & Checks'Image & " checks passed");
end Test_Core;
