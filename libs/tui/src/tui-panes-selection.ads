--  Linear text-selection coordinates inside a pane. Lines are document lines;
--  columns are zero-based display cells, counted before the viewport's
--  horizontal offset is applied, so a selection survives scrolling and
--  repainting unchanged.

with Tui.Text;
with Tui.Pager;

package Tui.Panes.Selection
  with SPARK_Mode => On
is

   type Position is record
      Line : Tui.Text.Line_Number := 1;
      Col  : Tui.Pager.Dimension := 0;
   end record;

   function Before_Or_Equal (Left, Right : Position) return Boolean
   is (Left.Line < Right.Line
       or else (Left.Line = Right.Line and then Left.Col <= Right.Col));

   --  Put the two ends of a drag into document order; a drag upwards or to
   --  the left is the same selection as the one that made it downwards.
   procedure Ordered (A, B : Position; First, Last : out Position)
   with
     Global => null,
     Post   =>
       Before_Or_Equal (First, Last)
       and then (First = A or else First = B)
       and then (Last = A or else Last = B);

end Tui.Panes.Selection;
