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
with Tui.Panes;
with Tui.Panes.Layout;
with Tui.Panes.List;
with Git_View_Navigation;

package Git_View_Policy with SPARK_Mode => On is

   package Eng renames Tui.Pager.Engine;

   --  Which pane has the keyboard. The commit list moves a SELECTION (a
   --  highlighted line that decides what Enter shows); the diff pane scrolls
   --  a plain viewport.
   type Pane is (List_Pane, Diff_Pane);

   --  The legacy frontend's row of panes: the commit list on the left and
   --  the diff on the right, with a separator column between them. The list
   --  gives up its place last, because a diff with no history to pick from
   --  is not a viewer.
   Min_Pane_Width : constant := 28;

   Default_Split : constant Tui.Panes.Layout.Split_Percentage := 45;

   subtype Pane_Specs is Tui.Panes.Layout.Specs_Array (1 .. 2);

   function Specs
     (Split : Tui.Panes.Layout.Split_Percentage) return Pane_Specs
   is (1 => (Weight   => Split,
             Min_Cols => Min_Pane_Width,
             Priority => 0),
       2 => (Weight   => 100 - Split,
             Min_Cols => Min_Pane_Width,
             Priority => 1));

   --  Panes are addressed by position in the row; this frontend names them.
   function Index (P : Pane) return Tui.Panes.Pane_Index
   is (Pane'Pos (P) + 1);

   --  Total, so that a pane index taken from the pane layer needs no
   --  bounds reasoning at every use: this row has a leftmost pane and a
   --  right-hand one, and nothing else.
   function Named (I : Tui.Panes.Pane_Index) return Pane
   is (if I = 1 then List_Pane else Diff_Pane);

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
         when Move_Selection => Move     : Tui.Panes.List.Sel_Move;
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

end Git_View_Policy;
