--  Behavioural tests for the line index. Complements gnatprove: proof shows the
--  contracts hold for all inputs; these pin concrete line splitting.

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Test_Checks;            use Test_Checks;
with Tui.Text;               use Tui.Text;

procedure Test_Text is

begin
   Start ("test_text", Echo_Passes => True);
   --  Three LF-terminated lines.
   declare
      B   : constant Buffer := To_Buffer ("a" & LF & "bb" & LF & "ccc" & LF);
      Idx : Index (100);
   begin
      Scan (Idx, B);
      Check (Line_Count (Idx) = 3, "3 LF lines -> 3");
      Check
        (Line_Span (Idx, 1) = (Start => 1, Length => 1)
         and then To_String (Line (Idx, B, 1)) = "a",
         "line 1 = a");
      Check
        (Line_Span (Idx, 2) = (Start => 3, Length => 2)
         and then To_String (Line (Idx, B, 2)) = "bb",
         "line 2 = bb");
      Check
        (Line_Span (Idx, 3) = (Start => 6, Length => 3)
         and then To_String (Line (Idx, B, 3)) = "ccc",
         "line 3 = ccc");
      Check (not Truncated (Idx), "not truncated");
   end;

   --  CRLF terminators: the CR is stripped from the content.
   declare
      B   : constant Buffer := To_Buffer ("a" & CR & LF & "bb" & CR & LF);
      Idx : Index (100);
   begin
      Scan (Idx, B);
      Check (Line_Count (Idx) = 2, "2 CRLF lines -> 2");
      Check
        (To_String (Line (Idx, B, 1)) = "a", "CRLF line 1 = a (CR stripped)");
      Check
        (To_String (Line (Idx, B, 2)) = "bb",
         "CRLF line 2 = bb (CR stripped)");
   end;

   --  Empty lines.
   declare
      B   : constant Buffer := To_Buffer (LF & LF);
      Idx : Index (100);
   begin
      Scan (Idx, B);
      Check (Line_Count (Idx) = 2, "two LFs -> 2 empty lines");
      Check
        (Line_Span (Idx, 1).Length = 0 and then Line (Idx, B, 1)'Length = 0,
         "empty line has length 0");
   end;

   --  No final newline: Scan ignores the tail; Seal finalises it.
   declare
      B   : constant Buffer := To_Buffer ("abc");
      Idx : Index (100);
   begin
      Scan (Idx, B);
      Check (Line_Count (Idx) = 0, "unterminated tail not recorded by Scan");
      Seal (Idx, B);
      Check
        (Line_Count (Idx) = 1 and then To_String (Line (Idx, B, 1)) = "abc",
         "Seal records the final unterminated line");
   end;

   --  One line + an unterminated tail, then Seal.
   declare
      B   : constant Buffer := To_Buffer ("x" & LF & "y");
      Idx : Index (100);
   begin
      Scan (Idx, B);
      Check
        (Line_Count (Idx) = 1 and then Scanned_Bytes (Idx) = 2,
         "Scan: 1 line, cursor past the LF");
      Seal (Idx, B);
      Check
        (Line_Count (Idx) = 2 and then To_String (Line (Idx, B, 2)) = "y",
         "Seal: tail becomes line 2");
   end;

   --  Incremental: rescan a grown (append-only) buffer continues where it left.
   declare
      B1  : constant Buffer := To_Buffer ("ab" & LF);
      B2  : constant Buffer := To_Buffer ("ab" & LF & "cd" & LF);
      Idx : Index (100);
   begin
      Scan (Idx, B1);
      Check (Line_Count (Idx) = 1, "incremental: first scan -> 1 line");
      Scan (Idx, B2);
      Check
        (Line_Count (Idx) = 2 and then To_String (Line (Idx, B2, 2)) = "cd",
         "incremental: second scan adds the new line");
   end;

   --  Capacity reached -> Truncated, no overflow.
   declare
      B   : constant Buffer := To_Buffer ("a" & LF & "b" & LF);
      Idx : Index (1);
   begin
      Scan (Idx, B);
      Check
        (Line_Count (Idx) = 1 and then Truncated (Idx),
         "capacity 1 -> 1 line, truncated");
   end;

   --  Empty buffer.
   declare
      B   : constant Buffer (1 .. 0) := (others => 0);
      Idx : Index (100);
   begin
      Scan (Idx, B);
      Check
        (Line_Count (Idx) = 0 and then Scanned_Bytes (Idx) = 0,
         "empty buffer -> 0 lines");
   end;

   Report;
end Test_Text;
