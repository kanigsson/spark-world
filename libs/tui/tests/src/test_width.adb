--  Behavioural tests for display width. Complements gnatprove: proof shows the
--  lookup cannot crash; these pin concrete widths against known code points.

with Ada.Text_IO;       use Ada.Text_IO;
with Ada.Command_Line;
with Tui.Width;         use Tui.Width;

procedure Test_Width is

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

begin
   --  The tables must be sorted/non-overlapping for the search to be meaningful.
   Check (Tables_Well_Formed, "interval tables are sorted and non-overlapping");

   --  Normal width 1.
   Check (Char_Width (Character'Pos ('A')) = 1, "'A' -> 1");
   Check (Char_Width (Character'Pos (' ')) = 1, "space -> 1");
   Check (Char_Width (16#00E9#) = 1, "U+00E9 (e-acute, precomposed) -> 1");

   --  Controls -> 0, and flagged.
   Check (Char_Width (16#00#) = 0 and then Is_Control (16#00#), "NUL -> 0");
   Check (Char_Width (16#1B#) = 0 and then Is_Control (16#1B#), "ESC -> 0");
   Check (Char_Width (16#7F#) = 0 and then Is_Control (16#7F#), "DEL -> 0");

   --  Combining / zero-width -> 0.
   Check (Char_Width (16#0301#) = 0 and then Is_Zero_Width (16#0301#),
          "U+0301 combining acute -> 0");
   Check (Char_Width (16#200D#) = 0, "U+200D ZWJ -> 0");
   Check (Char_Width (16#FE0F#) = 0, "U+FE0F variation selector -> 0");

   --  East-Asian wide / fullwidth / emoji -> 2.
   Check (Char_Width (16#4E00#) = 2 and then Is_Wide (16#4E00#),
          "U+4E00 CJK -> 2");
   Check (Char_Width (16#3042#) = 2, "U+3042 hiragana A -> 2");
   Check (Char_Width (16#AC00#) = 2, "U+AC00 hangul -> 2");
   Check (Char_Width (16#FF21#) = 2, "U+FF21 fullwidth A -> 2");
   Check (Char_Width (16#1F600#) = 2, "U+1F600 emoji -> 2");

   --  Boundaries around a wide interval (U+2329..U+232A).
   Check (Char_Width (16#2328#) = 1, "U+2328 (just below) -> 1");
   Check (Char_Width (16#2329#) = 2, "U+2329 (interval start) -> 2");
   Check (Char_Width (16#232A#) = 2, "U+232A (interval end) -> 2");
   Check (Char_Width (16#232B#) = 1, "U+232B (just above) -> 1");

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Width;
