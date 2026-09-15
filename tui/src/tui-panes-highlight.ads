--  Tui.Panes.Highlight — overlays a host lays over an already-rendered pane
--  surface.
--
--  These are functions over a surface, not widgets: they hold nothing, decide
--  nothing, and are applied after the engine has painted the pane's text and
--  the host has applied its own colours. That ordering is what lets a host
--  keep token colours underneath a selection.

with Tui.Surface;
with Tui.Text;
with Tui.Pager;
with Tui.Panes.Selection;

package Tui.Panes.Highlight with SPARK_Mode => On is

   use type Tui.Surface.Row_Count;
   use type Tui.Surface.Col_Count;

   --  The current row of a list-shaped pane: inverse video across its width.
   procedure Row
     (S : in out Tui.Surface.Surface;
      R : Tui.Surface.Row_Index)
   with Global => null,
        Pre    => R <= S.Rows;

   --  A retained linear selection, in the pane's own frame: Top and Left are
   --  the viewport offsets the engine reports, First and Last the ordered
   --  ends of the selection in document coordinates.
   --
   --  Inverse video is TOGGLED rather than set, which is what keeps selected
   --  text visible where it crosses a row that is already inverse — a list's
   --  current row, most often.
   procedure Overlay
     (S           : in out Tui.Surface.Surface;
      Top         : Tui.Text.Line_Number;
      Left        : Tui.Pager.Dimension;
      First, Last : Selection.Position)
   with Global => null;

   --  The column between two panes. Points_Left says which side has the
   --  keyboard, drawn as a half block leaning that way, so focus is legible
   --  without a border around every pane.
   procedure Separator
     (S           : in out Tui.Surface.Surface;
      At_Col      : Tui.Surface.Col_Index;
      Rows        : Tui.Surface.Row_Count;
      Points_Left : Boolean;
      Foreground  : Tui.Surface.Color)
   with Global => null,
        Pre    => At_Col <= S.Cols and then Rows <= S.Rows;

end Tui.Panes.Highlight;
