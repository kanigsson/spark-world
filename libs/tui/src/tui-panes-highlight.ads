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

package Tui.Panes.Highlight
  with SPARK_Mode => On
is

   use type Tui.Surface.Row_Count;
   use type Tui.Surface.Col_Count;
   use type Tui.Surface.Cell;

   --  The same cell with inverse video added, everything else kept: what
   --  marking a row does to each of its cells, named so a contract can say
   --  it.
   function Inverted (V : Tui.Surface.Cell) return Tui.Surface.Cell
   is (Glyph      => V.Glyph,
       Foreground => V.Foreground,
       Background => V.Background,
       Attributes =>
         (Bold      => V.Attributes.Bold,
          Italic    => V.Attributes.Italic,
          Underline => V.Attributes.Underline,
          Inverse   => True))
   with Global => null;

   --  Row R is marked and nothing else is: what a list-shaped pane looks
   --  like after it has been drawn and its current row marked. A host proves
   --  this of the pane it is about to composite, which is how "exactly one
   --  row is highlighted" becomes a checked property rather than a habit.
   function Only_Row_Marked
     (S : Tui.Surface.Surface; R : Tui.Surface.Row_Index) return Boolean
   is (for all RR in Tui.Surface.Row_Index range 1 .. S.Rows =>
         (for all CC in Tui.Surface.Col_Index range 1 .. S.Cols =>
            Tui.Surface.Get (S, RR, CC).Attributes.Inverse = (RR = R)))
   with Ghost, Pre => R <= S.Rows;

   --  The current row of a list-shaped pane: inverse video across its width.
   procedure Row (S : in out Tui.Surface.Surface; R : Tui.Surface.Row_Index)
   with
     Global => null,
     Pre    => R <= S.Rows,
     --  One row, and only that row: the cells of R gain inverse video and
     --  keep everything else, and no other cell is touched at all.
     Post   =>
       (for all RR in Tui.Surface.Row_Index range 1 .. S.Rows =>
          (for all CC in Tui.Surface.Col_Index range 1 .. S.Cols =>
             (if RR = R
              then
                Tui.Surface.Get (S, RR, CC)
                = Inverted (Tui.Surface.Get (S'Old, RR, CC))
              else
                Tui.Surface.Get (S, RR, CC)
                = Tui.Surface.Get (S'Old, RR, CC))));

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
   with Global => null, Pre => At_Col <= S.Cols and then Rows <= S.Rows;

end Tui.Panes.Highlight;
