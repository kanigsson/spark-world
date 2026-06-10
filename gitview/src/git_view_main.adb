--  git_view — a git-history viewer. Wires the proved Git_View_App (two
--  embedded pager engines: commit list + diff) to the Tui.Term driver. The
--  orchestration is itself SPARK: that the event loop only ever starts after
--  a successful Init is proved here against the app's contracts rather than
--  trusted. All git subprocess work lives behind the proved Git_View_Source
--  spec; all state and policy live in the proved Git_View_App.
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

--  The precondition restates the app package's initial condition: the tools
--  check it at program start against that package's elaboration, and assume
--  it here — which is what lets the Init call prove.
procedure Git_View_Main with
  SPARK_Mode => On,
  Pre        => Git_View_App.Uninitialized
is

   --  The one piece that stays outside SPARK: the loop driver takes its
   --  callbacks as access values, and an access value cannot carry the
   --  callbacks' precondition (the documents are loaded) — so that
   --  obligation is hoisted onto this wrapper, where the proof discharges
   --  it at the call site instead of trusting the hookup.
   procedure Run
   with Global => (In_Out => Git_View_App.State),
        Pre    => Git_View_App.Has_Documents;

   procedure Run with SPARK_Mode => Off is
   begin
      Tui.Term.Event_Loop.Run
        (Paint  => Git_View_App.Paint'Access,
         On_Key => Git_View_App.On_Key'Access);
   end Run;

   --  Message output sits outside SPARK only because the standard-error
   --  handle is not a SPARK-visible entity in this runtime.
   procedure Fail (Msg : String) with Global => null;

   procedure Fail (Msg : String) with SPARK_Mode => Off is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "git_view: " & Msg);
      Set_Exit_Status (Failure);
   end Fail;

   Ok : Boolean;

begin
   if not Git_View_Source.Available then
      Fail ("git not found on PATH");
      return;
   end if;

   --  Load the commit list (and the first diff). On failure git has already
   --  written its own message ("fatal: not a git repository ...") to
   --  standard error, which is still the terminal at this point.
   Git_View_App.Init (Ok);
   if not Ok then
      Fail ("cannot read the git log");
      return;
   end if;

   Run;

exception
   --  The last-chance net. The proof shows the orchestration itself raises
   --  nothing, but it does not cover storage exhaustion nor whatever the
   --  unproved loop driver might let escape.
   when others =>
      Fail ("unexpected failure");
end Git_View_Main;
