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

   type Action_Kind is
     (Quit,             --  leave the viewer        (q / Q / Ctrl-C)
      Switch_Focus,     --  move the keyboard to the other pane    (Tab)
      Toggle_Syntax,    --  enable/disable source token colours       (s)
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
   type Region is (List_Region, Diff_Region, Outside);

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
                            then Col > List_Cols
                              and then Col - List_Cols > 1);

end Git_View_Policy;
