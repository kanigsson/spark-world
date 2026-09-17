--  Tui.Panes.List — keeping a pane's selected line and its viewport in step.
--
--  The pager engine is a pure viewport: it knows which lines are on screen,
--  not which one is "current". A list-shaped pane adds that notion on top: a
--  selected line, highlighted by the host, that decides what following it
--  shows. The coupling rules live here — moving the selection drags the
--  viewport along only when it would leave the screen, and viewport jumps
--  (paging, search hits, a resize) pull the selection back into view.
--
--  Pure arithmetic over the engine's read-only state: no I/O, no surfaces,
--  and no notion of what the lines mean.

with Tui.Pager.Engine;
with Tui.Text;

package Tui.Panes.List with SPARK_Mode => On is

   package Eng renames Tui.Pager.Engine;

   --  How the selection moves. Distinct from a viewport command: moving the
   --  selection only scrolls the pane when it would otherwise leave view.
   type Sel_Move is
     (Sel_Up, Sel_Down,            --  one entry
      Sel_Page_Up, Sel_Page_Down,  --  a page of entries
      Sel_Top, Sel_Bottom);        --  ends of the list

   --  Pull the selection back into the visible slice (after a viewport jump
   --  the selection did not cause). When the viewport shows nothing (zero
   --  height), only the selection's upper bound is enforced.
   procedure Clamp
     (E        : Eng.Instance;
      Total    : Tui.Text.Line_Total;
      Selected : in out Tui.Text.Line_Number)
   with Global => null,
        Pre  => Total > 0,
        Post => Selected <= Total;

   --  The dual of Clamp: bring a selection chosen elsewhere -- by name, by a
   --  jump, by a restored location -- into view, moving the viewport as
   --  little as will do it. A line already on screen leaves the viewport
   --  alone, a line above it becomes the first row, a line below it the last.
   --  A viewport jump instead (top := the line) would scroll a list whenever
   --  the selection was set from outside, which reads as the list losing its
   --  place: the rows above the selection disappear although nothing asked
   --  them to.
   procedure Reveal
     (E     : in out Eng.Instance;
      Line  : Tui.Text.Line_Number;
      Total : Tui.Text.Line_Total)
   with Global => null,
        Pre  => Line <= Total,
        Post => --  Nothing moves for a line that was already on screen.
                (if Line >= Eng.Top_Line (E'Old)
                   and then Line <= Eng.Last_Visible (E'Old, Total)
                 then Eng.Top_Line (E) = Eng.Top_Line (E'Old))
                --  And whatever the viewport does, the line ends up in it.
                and then
                  (if Eng.Height (E'Old) > 0
                   then Line >= Eng.Top_Line (E)
                        and then Line <= Eng.Last_Visible (E, Total));

   --  Apply one selection move, scrolling the viewport just enough to keep
   --  the selection visible. Changed reports whether anything moved, for the
   --  host's repaint decision.
   procedure Move
     (E        : in out Eng.Instance;
      M        : Sel_Move;
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

end Tui.Panes.List;
