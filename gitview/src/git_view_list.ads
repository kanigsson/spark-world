--  Git_View_List — keeping the list selection and its viewport in step, as
--  proved SPARK.
--
--  The pager engine is a pure viewport: it knows which lines are on screen,
--  not which one is "current". The commit list adds that notion on top: a
--  selected line, highlighted by the painter, that decides what Enter shows.
--  The coupling rules live here: moving the selection drags the viewport
--  along only when it would leave the screen, and viewport jumps (paging,
--  search hits, resize) pull the selection back into view. Pure arithmetic
--  over the engine's read-only state — no I/O, no surfaces.

with Tui.Pager.Engine;
with Tui.Text;
with Git_View_Policy;

package Git_View_List with SPARK_Mode => On is

   package Eng renames Tui.Pager.Engine;

   --  Pull the selection back into the visible slice of the list (after a
   --  viewport jump the selection did not cause: a page move, a search hit,
   --  a resize). When the viewport shows nothing (zero height), only the
   --  selection's upper bound is enforced.
   procedure Clamp
     (E        : Eng.Instance;
      Total    : Tui.Text.Line_Total;
      Selected : in out Tui.Text.Line_Number)
   with Global => null,
        Pre  => Total > 0,
        Post => Selected <= Total;

   --  Apply one selection move, scrolling the list viewport just enough to
   --  keep the selection visible. Changed reports whether anything moved
   --  (for the host's repaint decision).
   procedure Move
     (E        : in out Eng.Instance;
      M        : Git_View_Policy.Sel_Move;
      Content  : Tui.Text.Buffer;
      Index    : Tui.Text.Index;
      Selected : in out Tui.Text.Line_Number;
      Changed  : out Boolean)
   with Global => null,
        Pre  => Tui.Text.Line_Count (Index) > 0
                and then Selected <= Tui.Text.Line_Count (Index)
                and then Content'First = 1
                and then Content'Last >= Tui.Text.Scanned_Bytes (Index),
        Post => Selected <= Tui.Text.Line_Count (Index);

end Git_View_List;
