--  Git_View_Policy — the git viewer's keymap, as proved SPARK.
--
--  Deciding what a keystroke MEANS is pure: it depends only on the event and
--  on which pane has the keyboard, never on I/O or the documents. That pure
--  decision lives here, mirroring the standalone pager's proved keymap; the
--  app body carries out the decided effect — moving the selection, driving
--  an engine, swapping the diff document.
--
--  Only NAVIGATION-mode keys are classified here. Search-input editing stays
--  in the app, where the pattern editor lives.

with Tui.Input;
with Tui.Pager.Engine;
with Tui.Surface;
with Git_View_Navigation;

package Git_View_Policy with SPARK_Mode => On is

   package Eng renames Tui.Pager.Engine;

   --  Which pane has the keyboard. The commit list moves a SELECTION (a
   --  highlighted line that decides what Enter shows); the diff pane scrolls
   --  a plain viewport.
   type Pane is (List_Pane, Diff_Pane);

   --  How the list selection moves. Distinct from a viewport command: moving
   --  the selection only scrolls the list when it would leave the screen.
   type Sel_Move is
     (Sel_Up, Sel_Down,            --  one entry
      Sel_Page_Up, Sel_Page_Down,  --  a page of entries
      Sel_Top, Sel_Bottom);        --  ends of the list

   --  The normal two-pane layout keeps both panes useful. Split is the share
   --  of the terminal width assigned to the commit list; the painter clamps
   --  the actual columns further when either pane reaches its minimum.
   Min_Pane_Width  : constant := 28;
   Min_Split_Width : constant := Min_Pane_Width * 2 + 1;

   subtype Split_Percentage is Natural range 25 .. 75;
   Default_Split : constant Split_Percentage := 45;
   Split_Step    : constant                  := 5;

   type Layout is record
      List_Cols : Natural := 0;
      Diff_Cols : Natural := 0;
   end record;

   function Compute_Layout
     (Cols      : Tui.Surface.Col_Count;
      Focused   : Pane;
      Maximized : Boolean;
      Split     : Split_Percentage) return Layout
   with Global => null,
        Post   => Compute_Layout'Result.List_Cols
                    + Compute_Layout'Result.Diff_Cols
                    + (if Compute_Layout'Result.List_Cols > 0
                         and then Compute_Layout'Result.Diff_Cols > 0
                       then 1 else 0) = Natural (Cols);

   function Adjust_Split
     (Current   : Split_Percentage;
      Grow_List : Boolean) return Split_Percentage
   with Global => null;

   --  Convert a dragged separator column to a bounded percentage. Column is a
   --  screen coordinate and may lie beyond Total in a malformed mouse report;
   --  clamping makes that harmless.
   function Split_At
     (Column : Natural;
      Total  : Tui.Surface.Col_Count) return Split_Percentage
   with Global => null,
        Pre    => Natural (Total) > 0;

   type Action_Kind is
     (Quit,             --  leave the viewer        (q / Q / Ctrl-C)
      Switch_Focus,     --  move the keyboard to the other pane    (Tab)
      Toggle_Maximize,  --  maximize/restore the focused pane         (z)
      Resize_Split,     --  shrink/grow the commit-list pane        (, .)
      Toggle_Syntax,    --  enable/disable source token colours       (s)
      Jump_Diff,        --  next/previous file or hunk            ([ ] { })
      Open_Diff,        --  show the selected commit's diff        (Enter)
      Move_Selection,   --  move the list selection   (see Move)
      Navigate,         --  move the focused viewport (see Command)
      Search,           --  begin entering a pattern  ('/' forward, '?' back)
      Repeat_Search,    --  re-run the last pattern   ('n' same, 'N' reversed)
      Ignore);          --  key is not bound

   type Decision (Kind : Action_Kind := Ignore) is record
      case Kind is
         when Move_Selection => Move     : Sel_Move;
         when Navigate       => Command  : Eng.Command;
         when Resize_Split   => Grow_List : Boolean;
         when Jump_Diff      =>
            Target   : Git_View_Navigation.Landmark;
            Jump_Forward : Boolean;
         when Search         => Forward  : Boolean;
         when Repeat_Search  => Reversed : Boolean;
         when others         => null;
      end case;
   end record;

   --  Classify a keystroke seen while navigating. Pure: no state, no I/O.
   function Classify
     (Focused : Pane;
      Event   : Tui.Input.Key_Event) return Decision
   with Global => null;

   --  Where a screen position lands in the painted layout: one of the panes,
   --  or neither (the separator column, the status row, past the content).
   --  Pure geometry over the split the painter recorded; the postcondition
   --  hands the position's lower bounds to the app's row/column arithmetic.
   type Region is (List_Region, Separator_Region, Diff_Region, Outside);

   function Locate
     (Col, Row     : Natural;    --  1-based screen position (0: no position)
      List_Cols    : Natural;    --  width of the list pane
      Diff_Cols    : Natural;    --  width of the diff pane (0 when not shown)
      Content_Rows : Natural)    --  rows above the status line
      return Region
   with Global => null,
        Post   => (if Locate'Result /= Outside
                   then Col >= 1 and Row in 1 .. Content_Rows)
                  and then (if Locate'Result = List_Region
                            then Col <= List_Cols)
                  and then (if Locate'Result = Diff_Region
                            then (if List_Cols = 0
                                  then Col <= Diff_Cols
                                  else Col > List_Cols
                                    and then Col - List_Cols > 1))
                  and then (if Locate'Result = Separator_Region
                            then List_Cols > 0 and then Diff_Cols > 0
                              and then Col = List_Cols + 1);

end Git_View_Policy;
