--  Behavioural tests for the pager engine: viewport clamping and rendering.
--  Complements gnatprove (which shows the core cannot crash); these pin the
--  actual scrolling and layout behaviour.

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Tui.Surface;            use Tui.Surface;
with Tui.Text;
with Tui.Pager.View;
with Tui.Pager.Render;

procedure Test_Pager is

   package PV renames Tui.Pager.View;
   package PR renames Tui.Pager.Render;

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

   function Buf_Of (S : String) return Tui.Text.Buffer is
      B : Tui.Text.Buffer (1 .. S'Length);
   begin
      for I in S'Range loop
         B (1 + (I - S'First)) := Tui.Text.Byte (Character'Pos (S (I)));
      end loop;
      return B;
   end Buf_Of;

   --  Glyphs of row R as a String (non-ASCII shown as '?'), for easy asserts.
   function Row_Text (Surf : Surface; R : Row_Index) return String is
      S : String (1 .. Natural (Surf.Cols));
   begin
      for C in 1 .. Surf.Cols loop
         declare
            P : constant Natural :=
              Wide_Wide_Character'Pos (Get (Surf, R, C).Glyph);
         begin
            S (Natural (C)) := (if P in 32 .. 126 then Character'Val (P) else '?');
         end;
      end loop;
      return S;
   end Row_Text;

begin
   -------------------------------------------------------------------
   --  Viewport
   -------------------------------------------------------------------
   declare
      V : PV.Viewport;
   begin
      PV.Set_Size (V, Height => 10, Width => 80, Total => 100);
      Check (V.Top = 1, "initial top is 1");

      PV.Scroll_Down (V, 100, 5);
      Check (V.Top = 6, "scroll down 5 -> top 6");

      PV.Go_Bottom (V, 100);
      Check (V.Top = 91, "go bottom -> top 91 (100-10+1)");

      PV.Scroll_Down (V, 100, 50);
      Check (V.Top = 91, "scroll past end clamps at bottom");

      PV.Scroll_Up (V, 1000);
      Check (V.Top = 1, "scroll past start clamps at top");

      PV.Page_Down (V, 100);
      Check (V.Top = 11, "page down by height 10 -> top 11");

      PV.Go_Top (V);
      Check (V.Top = 1, "go top -> 1");

      PV.Go_Bottom (V, 5);
      Check (V.Top = 1, "go bottom with fewer lines than height -> 1");
   end;

   -------------------------------------------------------------------
   --  Rendering
   -------------------------------------------------------------------
   declare
      Content : constant Tui.Text.Buffer :=
        Buf_Of ("abc" & LF & "hello world" & LF & "third");
      Idx  : Tui.Text.Index (100);
      Surf : Surface := Blank (3, 10);
      V    : PV.Viewport;
   begin
      Tui.Text.Scan (Idx, Content);
      Tui.Text.Seal (Idx, Content);     --  "third" has no trailing newline

      PR.Draw (Surf, Content, Idx, V);
      Check (Row_Text (Surf, 1) = "abc       ", "row 1 = abc, padded");
      Check (Row_Text (Surf, 2) = "hello worl", "row 2 truncated at width 10");
      Check (Row_Text (Surf, 3) = "third     ", "row 3 = third, padded");

      --  Horizontal scroll by 6: 'hello world' shows from 'world'.
      V.Left := 6;
      PR.Draw (Surf, Content, Idx, V);
      Check (Row_Text (Surf, 2) = "world     ", "hscroll 6 shows 'world'");
      Check (Row_Text (Surf, 1) = "          ", "hscroll past short line -> blank");
   end;

   --  Rows past end-of-content are blanked.
   declare
      Content : constant Tui.Text.Buffer := Buf_Of ("one" & LF & "two" & LF);
      Idx  : Tui.Text.Index (100);
      Surf : Surface := Blank (4, 6);
      V    : PV.Viewport;
   begin
      Tui.Text.Scan (Idx, Content);
      PR.Draw (Surf, Content, Idx, V);
      Check (Row_Text (Surf, 2) = "two   ", "row 2 = two");
      Check (Row_Text (Surf, 3) = "      ", "row 3 blank (past EOF)");
      Check (Row_Text (Surf, 4) = "      ", "row 4 blank (past EOF)");
   end;

   --  Tab expansion to the next 8-column stop.
   declare
      Content : constant Tui.Text.Buffer := Buf_Of ("a" & HT & "b");
      Idx  : Tui.Text.Index (100);
      Surf : Surface := Blank (1, 10);
      V    : PV.Viewport;
   begin
      Tui.Text.Scan (Idx, Content);
      Tui.Text.Seal (Idx, Content);
      PR.Draw (Surf, Content, Idx, V);
      Check (Row_Text (Surf, 1) = "a       b ", "tab expands 'a'+TAB+'b'");
   end;

   --  Wide (CJK) glyph occupies two columns; a continuation blank follows.
   declare
      Content : constant Tui.Text.Buffer :=
        Buf_Of ("X" & Character'Val (16#E4#) & Character'Val (16#B8#)
                & Character'Val (16#80#) & "Y");   --  X U+4E00 Y
      Idx  : Tui.Text.Index (100);
      Surf : Surface := Blank (1, 10);
      V    : PV.Viewport;
   begin
      Tui.Text.Scan (Idx, Content);
      Tui.Text.Seal (Idx, Content);
      PR.Draw (Surf, Content, Idx, V);
      Check (Wide_Wide_Character'Pos (Get (Surf, 1, 2).Glyph) = 16#4E00#,
             "wide glyph U+4E00 placed at column 2");
      Check (Get (Surf, 1, 3).Glyph = ' ', "wide glyph continuation at column 3");
      Check (Get (Surf, 1, 4).Glyph = 'Y', "'Y' follows wide glyph at column 4");
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Pager;
