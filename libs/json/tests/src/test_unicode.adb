with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;

with JSON; use JSON;
with JSON.Pull;
with JSON.Strings;
with Unicode_Text.UTF_8;

procedure Test_Unicode is

   BS : constant Character := '\';

   E_Acute : constant String :=
     (1 => Character'Val (16#C3#), 2 => Character'Val (16#A9#));
   Euro    : constant String :=
     (1 => Character'Val (16#E2#),
      2 => Character'Val (16#82#),
      3 => Character'Val (16#AC#));
   G_Clef  : constant String :=
     (1 => Character'Val (16#F0#),
      2 => Character'Val (16#9D#),
      3 => Character'Val (16#84#),
      4 => Character'Val (16#9E#));

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Label : String) is
   begin
      if Condition then
         Put_Line ("  ok   : " & Label);
      else
         Put_Line ("  FAIL : " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Check_Decode
     (Raw, Expected : String; Expected_Status : Status_Type; Label : String)
   is
      Buffer : String (7 .. 6 + Raw'Length) := (others => Character'Val (0));
      Length : Natural;
      Status : Status_Type;
   begin
      JSON.Strings.Decode (Raw, Buffer, Length, Status);
      Check
        (Status = Expected_Status
         and then (if Status = OK
                   then
                     JSON.Strings.Active_Prefix (Buffer, Length) = Expected
                     and then Unicode_Text.UTF_8.Is_Valid_UTF_8
                                (JSON.Strings.Active_Prefix (Buffer, Length))
                   else Length = 0),
         Label);
   end Check_Decode;

   procedure Check_Invalid_UTF8 (Raw : String; Label : String) is
      Status : Status_Type;
   begin
      JSON.Pull.Validate ('"' & Raw & '"', Status);
      Check (Status = Invalid_UTF8, Label);
   end Check_Invalid_UTF8;

begin
   Check_Decode ("", "", OK, "empty output");
   Check_Decode ("ASCII", "ASCII", OK, "ASCII");
   Check_Decode (E_Acute, E_Acute, OK, "raw two-byte scalar");
   Check_Decode (Euro, Euro, OK, "raw three-byte scalar");
   Check_Decode (G_Clef, G_Clef, OK, "raw four-byte scalar");

   Check_Decode (BS & '"', String'(1 => '"'), OK, "escaped quote");
   Check_Decode (BS & BS, String'(1 => BS), OK, "escaped reverse solidus");
   Check_Decode (BS & '/', "/", OK, "escaped solidus");
   Check_Decode (BS & "b", String'(1 => Character'Val (8)), OK, "backspace");
   Check_Decode (BS & "f", String'(1 => Character'Val (12)), OK, "form feed");
   Check_Decode (BS & "n", String'(1 => Character'Val (10)), OK, "newline");
   Check_Decode (BS & "r", String'(1 => Character'Val (13)), OK, "return");
   Check_Decode (BS & "t", String'(1 => Character'Val (9)), OK, "tab");
   Check_Decode (BS & "u0000", String'(1 => Character'Val (0)), OK, "U+0000");
   Check_Decode (BS & "u00E9", E_Acute, OK, "escaped BMP two-byte");
   Check_Decode (BS & "u20AC", Euro, OK, "escaped BMP three-byte");
   Check_Decode (BS & "uD834" & BS & "uDD1E", G_Clef, OK, "surrogate pair");
   Check_Decode
     (E_Acute & BS & "u20AC",
      E_Acute & Euro,
      OK,
      "raw and escaped scalars mixed");

   Check_Decode (BS & "uD800", "", Truncated, "lone high surrogate");
   Check_Decode (BS & "uDC00", "", Invalid_Escape, "lone low surrogate");
   Check_Decode
     (BS & "uD800" & BS & "u0041",
      "",
      Invalid_Escape,
      "high surrogate with non-low");

   Check_Invalid_UTF8
     (String'(1 => Character'Val (16#80#)), "isolated continuation");
   Check_Invalid_UTF8
     ((1 => Character'Val (16#C0#), 2 => Character'Val (16#AF#)),
      "two-byte overlong");
   Check_Invalid_UTF8
     ((1 => Character'Val (16#E0#),
       2 => Character'Val (16#80#),
       3 => Character'Val (16#80#)),
      "three-byte overlong");
   Check_Invalid_UTF8
     ((1 => Character'Val (16#F0#),
       2 => Character'Val (16#80#),
       3 => Character'Val (16#80#),
       4 => Character'Val (16#80#)),
      "four-byte overlong");
   Check_Invalid_UTF8
     ((1 => Character'Val (16#ED#),
       2 => Character'Val (16#A0#),
       3 => Character'Val (16#80#)),
      "UTF-8 surrogate");
   Check_Invalid_UTF8
     ((1 => Character'Val (16#F4#),
       2 => Character'Val (16#90#),
       3 => Character'Val (16#80#),
       4 => Character'Val (16#80#)),
      "above U+10FFFF");
   Check_Invalid_UTF8
     (String'(1 => Character'Val (16#C2#)), "truncated two-byte");
   Check_Invalid_UTF8
     ((1 => Character'Val (16#E2#), 2 => Character'Val (16#82#)),
      "truncated three-byte");
   Check_Invalid_UTF8
     ((1 => Character'Val (16#F0#),
       2 => Character'Val (16#9F#),
       3 => Character'Val (16#98#)),
      "truncated four-byte");
   Check_Invalid_UTF8
     (String'(1 => Character'Val (16#80#)) & BS & "n",
      "invalid UTF-8 before escape");
   Check_Invalid_UTF8
     (BS & "n" & Character'Val (16#80#), "invalid UTF-8 after escape");

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL UNICODE TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Unicode;
