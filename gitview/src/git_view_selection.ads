--  Linear text-selection coordinates for either rendered pane. Lines are
--  document lines; columns are zero-based display-cell columns before the
--  viewport's horizontal offset is applied.

with Tui.Text;
with Tui.Pager;

package Git_View_Selection with SPARK_Mode => On is

   type Position is record
      Line : Tui.Text.Line_Number := 1;
      Col  : Tui.Pager.Dimension := 0;
   end record;

   function Before_Or_Equal (Left, Right : Position) return Boolean is
     (Left.Line < Right.Line
      or else (Left.Line = Right.Line and then Left.Col <= Right.Col));

   procedure Ordered
     (A, B        : Position;
      First, Last : out Position)
   with Global => null,
        Post   => Before_Or_Equal (First, Last)
                  and then (First = A or else First = B)
                  and then (Last = A or else Last = B);

end Git_View_Selection;
