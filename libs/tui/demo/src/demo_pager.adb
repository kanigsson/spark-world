--  Throwaway demo. NOT part of the library, NOT SPARK. Builds an in-memory
--  document, indexes it, renders the viewport into a Surface, and prints the
--  Surface framed so the rendering is observable with no terminal driver. Then
--  it scrolls and renders again.

with Ada.Text_IO;                          use Ada.Text_IO;
with Ada.Characters.Latin_1;               use Ada.Characters.Latin_1;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Tui.Surface;                          use Tui.Surface;
with Tui.Text;
with Tui.Pager.View;
with Tui.Pager.Render;

procedure Demo_Pager is

   package PV renames Tui.Pager.View;
   package PR renames Tui.Pager.Render;
   package Enc renames Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

   function Buf_Of (S : String) return Tui.Text.Buffer is
      B : Tui.Text.Buffer (1 .. S'Length);
   begin
      for I in S'Range loop
         B (1 + (I - S'First)) := Tui.Text.Byte (Character'Pos (S (I)));
      end loop;
      return B;
   end Buf_Of;

   procedure Frame (Surf : Surface; Title : String) is
   begin
      Put_Line (Title);
      Put ("+");
      for C in 1 .. Surf.Cols loop
         Put ("-");
      end loop;
      Put_Line ("+");
      for R in 1 .. Surf.Rows loop
         Put ("|");
         for C in 1 .. Surf.Cols loop
            Put (Enc.Encode ((1 => Get (Surf, R, C).Glyph)));
         end loop;
         Put_Line ("|");
      end loop;
      Put ("+");
      for C in 1 .. Surf.Cols loop
         Put ("-");
      end loop;
      Put_Line ("+");
   end Frame;

   Document : constant Tui.Text.Buffer :=
     Buf_Of ("The quick brown fox" & LF
             & "jumps over the lazy dog" & LF
             & "" & LF
             & "wide: " & Character'Val (16#E4#) & Character'Val (16#B8#)
                        & Character'Val (16#80#) & "  (U+4E00)" & LF
             & "tab:" & HT & "after-tab" & LF
             & "line six" & LF
             & "line seven" & LF
             & "the end (no newline)");

   Idx  : Tui.Text.Index (1_000);
   Surf : Surface := Blank (5, 22);     --  a small 5x22 viewport
   V    : PV.Viewport;

begin
   Tui.Text.Scan (Idx, Document);
   Tui.Text.Seal (Idx, Document);
   PV.Set_Size (V, Height => 5, Width => 22, Total => Tui.Text.Line_Count (Idx));

   Put_Line ("document has" & Tui.Text.Line_Count (Idx)'Image & " lines;"
             & " viewport is 5 rows x 22 cols");
   New_Line;

   PR.Draw (Surf, Document, Idx, V);
   Frame (Surf, "--- top of document ---");
   New_Line;

   PV.Scroll_Down (V, Tui.Text.Line_Count (Idx), 3);
   PR.Draw (Surf, Document, Idx, V);
   Frame (Surf, "--- after scrolling down 3 ---");
end Demo_Pager;
