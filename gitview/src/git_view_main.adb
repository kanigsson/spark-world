--  git_view — a git-history viewer. Wires the proved Git_View_App (two
--  embedded pager engines: commit list + diff) to the Tui.Term driver. NOT
--  SPARK: this is the thin OS edge — argument handling, the startup checks,
--  the event-loop hookup. All git subprocess work lives behind the proved
--  Git_View_Source spec; all state and policy live in the proved
--  Git_View_App.
--
--  Usage:
--    git_view          browse the history of the repository at $PWD
--
--  Keys: j/k move the selection, Enter shows the commit's diff, Tab moves
--  the keyboard between panes, / ? n N search within the focused pane,
--  q quits.

with Ada.Command_Line;            use Ada.Command_Line;
with Ada.Text_IO;
with Tui.Term.Event_Loop;
with Git_View_App;
with Git_View_Source;

procedure Git_View_Main with SPARK_Mode => Off is
   Ok : Boolean;
begin
   if not Git_View_Source.Available then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "git_view: git not found on PATH");
      Set_Exit_Status (Failure);
      return;
   end if;

   --  Load the commit list (and the first diff). On failure git has already
   --  written its own message ("fatal: not a git repository ...") to
   --  standard error, which is still the terminal at this point.
   Git_View_App.Init (Ok);
   if not Ok then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "git_view: cannot read the git log");
      Set_Exit_Status (Failure);
      return;
   end if;

   Tui.Term.Event_Loop.Run
     (Paint  => Git_View_App.Paint'Access,
      On_Key => Git_View_App.On_Key'Access);

exception
   when others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "git_view: unexpected failure");
      Set_Exit_Status (Failure);
end Git_View_Main;
