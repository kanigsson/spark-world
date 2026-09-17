--  Tui.Pager.Render — draw the viewport's content into a surface.
--
--  Pure: reads the content (a Tui.Text line index over a byte buffer) and the
--  viewport, and fills a Tui.Surface. No I/O. Rendering is data, not effect — a
--  host blits the surface afterwards. All SPARK, proved free of run-time errors.
--
--  What it does, per visible row:
--    * blanks the row, then draws the corresponding content line;
--    * decodes UTF-8 to code points and uses Tui.Width for column advance, so
--      CJK / wide glyphs take two cells and combining marks take none;
--    * expands tabs to the next tab stop;
--    * applies horizontal scroll (View.Left) and truncates at the surface width.
--
--  v1 simplifications (documented, revisitable):
--    * long lines are TRUNCATED, not wrapped (wrap is a future layout mode);
--    * control characters other than TAB, and zero-width/combining marks, are
--      not drawn (they advance nothing) rather than shown in caret notation;
--    * a wide glyph straddling the left scroll edge is skipped, and one
--      straddling the right edge keeps its head cell — minor edge effects.
--
--  The viewport's Height/Width are NOT consulted here: the surface's own
--  dimensions are the drawing region. Only View.Top and View.Left are used.

with Tui.Surface;
with Tui.Text;
with Tui.Pager.View;

package Tui.Pager.Render with SPARK_Mode => On is

   procedure Draw
     (Target  : in out Tui.Surface.Surface;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      V       : Tui.Pager.View.Viewport;
      Tab     : Tui.Pager.Tab_Width := Tui.Pager.Default_Tab_Width)
   with Global => null,
        Pre    => Content'First = 1
                  and then Content'Last >= Tui.Text.Scanned_Bytes (Index),
        --  Drawing paints text, never a selection: every cell it writes is
        --  plain, and it writes every cell. A host's highlight therefore
        --  starts from a surface with no inverse video on it, which is what
        --  lets "one row is highlighted" be a property of the host's own
        --  single call rather than an assumption about what drawing left
        --  behind.
        Post   => Tui.Surface.No_Inverse (Target);

end Tui.Pager.Render;
