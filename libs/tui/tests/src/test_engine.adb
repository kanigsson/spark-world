--  Behavioural tests for Tui.Pager.Engine — the roadmap's "done when" for the
--  engine: scrolling, search and resize validated PURELY by rendering into a
--  Surface and asserting on the cells, with no terminal anywhere in sight. This
--  is the payoff of "rendering is data".

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Tui.Surface;            use Tui.Surface;
with Tui.Text;
with Tui.Pager.Engine;

procedure Test_Engine is

   package PE renames Tui.Pager.Engine;
   use type PE.Effect;

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

   function Row_Text (Surf : Surface; R : Row_Index) return String is
      S : String (1 .. Natural (Surf.Cols));
   begin
      for C in 1 .. Surf.Cols loop
         declare
            P : constant Natural :=
              Wide_Wide_Character'Pos (Get (Surf, R, C).Glyph);
         begin
            S (Natural (C)) :=
              (if P in 32 .. 126 then Character'Val (P) else '?');
         end;
      end loop;
      return S;
   end Row_Text;

   --  Eight clearly-distinguishable lines; no trailing newline on the last.
   Content : constant Tui.Text.Buffer :=
     Buf_Of
       ("alpha"
        & LF
        & "bravo"
        & LF
        & "charlie"
        & LF
        & "delta"
        & LF
        & "echo"
        & LF
        & "foxtrot"
        & LF
        & "golf"
        & LF
        & "hotel");

   Idx  : Tui.Text.Index (100);
   E    : PE.Instance;
   Surf : Surface := Blank (3, 10);   --  3-row content area, 10 cols
   Res  : PE.Effect;

   procedure Repaint is
   begin
      PE.Render (E, Surf, Content, Idx);
   end Repaint;

begin
   Tui.Text.Scan (Idx, Content);
   Tui.Text.Seal (Idx, Content);     --  records "hotel" -> 8 lines total

   Check (Tui.Text.Line_Count (Idx) = 8, "indexed 8 lines");

   PE.Resize (E, Rows => 3, Cols => 10, Total => 8);

   ----------------------------------------------------------------- top frame
   Repaint;
   Check (Row_Text (Surf, 1) = "alpha     ", "top: row1 alpha");
   Check (Row_Text (Surf, 3) = "charlie   ", "top: row3 charlie");

   ----------------------------------------------------------------- paging
   PE.Handle (E, PE.Page_Down, Content, Idx, Res);
   Check (Res = PE.Moved, "page down reports Moved");
   Repaint;
   Check (Row_Text (Surf, 1) = "delta     ", "after page down: row1 delta");
   Check (Row_Text (Surf, 3) = "foxtrot   ", "after page down: row3 foxtrot");

   PE.Handle (E, PE.Line_Up, Content, Idx, Res);
   Check (Res = PE.Moved and then PE.Top_Line (E) = 3, "line up -> top 3");

   ----------------------------------------------------------------- bottom + clamp
   PE.Handle (E, PE.To_Bottom, Content, Idx, Res);
   Check (PE.Top_Line (E) = 6, "to bottom -> top 6 (8-3+1)");
   PE.Handle (E, PE.To_Bottom, Content, Idx, Res);
   Check (Res = PE.Unchanged, "to bottom again -> Unchanged");
   Repaint;
   Check (Row_Text (Surf, 3) = "hotel     ", "bottom: row3 hotel");

   ----------------------------------------------------------------- search fwd
   PE.Handle (E, PE.To_Top, Content, Idx, Res);
   PE.Set_Pattern (E, Buf_Of ("echo"));
   Check (PE.Has_Pattern (E), "pattern set");
   PE.Handle (E, PE.Find_Next, Content, Idx, Res);
   Check (Res = PE.Search_Hit, "find 'echo' -> Search_Hit");
   Check (PE.Top_Line (E) = 5, "find 'echo' moves top to line 5");
   Repaint;
   Check (Row_Text (Surf, 1) = "echo      ", "search: row1 echo");

   ----------------------------------------------------------------- search back
   PE.Set_Pattern (E, Buf_Of ("alpha"));
   PE.Handle (E, PE.Find_Prev, Content, Idx, Res);
   Check
     (Res = PE.Search_Hit and then PE.Top_Line (E) = 1,
      "find prev 'alpha' -> top 1");

   ----------------------------------------------------------------- search miss
   PE.Set_Pattern (E, Buf_Of ("zzz"));
   declare
      Before : constant Tui.Text.Line_Number := PE.Top_Line (E);
   begin
      PE.Handle (E, PE.Find_Next, Content, Idx, Res);
      Check (Res = PE.Search_Miss, "find 'zzz' -> Search_Miss");
      Check (PE.Top_Line (E) = Before, "miss leaves viewport unchanged");
   end;

   ----------------------------------------------------------------- resize reclamp
   PE.Handle (E, PE.To_Bottom, Content, Idx, Res);   --  top = 6
   PE.Resize (E, Rows => 6, Cols => 10, Total => 8); --  Max_Top now 8-6+1 = 3
   Check (PE.Top_Line (E) = 3, "growing the view re-clamps top to 3");

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL ENGINE TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Engine;
