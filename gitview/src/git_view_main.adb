--  git_view — a git-history viewer. Wires the proved Git_View_App (two
--  embedded pager engines: commit list + diff) to the Tui.Term driver. The
--  orchestration is itself SPARK: that the event loop only ever starts after
--  a successful Init is proved here against the app's contracts rather than
--  trusted. All repository access lives behind the proved Git_View_Source
--  spec; all state and policy live in the proved Git_View_App.
--
--  Usage:
--    git_view [OPTIONS] [REVISION] [-- PATH]
--
--  Keys: j/k move the selection, Enter shows the commit's diff, Tab moves
--  the keyboard between panes, / ? n N search within the focused pane,
--  q quits.
--
--  Mouse: a left click opens the commit under the cursor (and gives the
--  clicked pane the keyboard); a drag selects text; the wheel scrolls the
--  pane under the cursor.
--  --no-mouse leaves the mouse to the terminal, so its native text
--  selection works without holding Shift.

with Ada.Command_Line;            use Ada.Command_Line;
with Ada.Text_IO;
with Tui.Term.Event_Loop;
with Git_View_App;
with Git_View_Source;
with Git_View_Model;
with Git_View_Explorer;
with Git_View_Loop;
with Git_View_Repository;

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
   procedure Run (Mouse : Boolean)
   with Global => (In_Out => Git_View_App.State),
        Pre    => Git_View_App.Has_Documents;

   procedure Run (Mouse : Boolean) with SPARK_Mode => Off is
   begin
      Tui.Term.Event_Loop.Run
        (Paint  => Git_View_App.Paint'Access,
         On_Key => Git_View_App.On_Key'Access,
         Mouse  => Mouse);
   end Run;

   procedure Run_Explorer (Mouse : Boolean)
     with Global => (In_Out => (Git_View_Explorer.State, Git_View_Repository.State));
   procedure Run_Explorer (Mouse : Boolean) with SPARK_Mode => Off is
   begin
      Git_View_Loop.Run (Mouse);
   end Run_Explorer;

   --  Message output sits outside SPARK only because the standard-error
   --  handle is not a SPARK-visible entity in this runtime.
   procedure Fail (Msg : String) with Global => null;

   procedure Fail (Msg : String) with SPARK_Mode => Off is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "git_view: " & Msg);
      Set_Exit_Status (Failure);
   end Fail;

   --  Reject an unusable command-line argument. Also outside SPARK: quoting
   --  the argument concatenates strings whose lengths the prover cannot
   --  bound.
   procedure Fail_Usage (Arg : String) with Global => null;

   procedure Fail_Usage (Arg : String) with SPARK_Mode => Off is
   begin
      Fail ("unknown option or extra argument """ & Arg & """");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "usage: git_view [OPTIONS] [REVISION] [-- PATH]");
   end Fail_Usage;

   procedure Print_Help with Global => null;

   procedure Print_Help with SPARK_Mode => Off is
   begin
      Ada.Text_IO.Put_Line ("usage: git_view [OPTIONS] [REVISION] [-- PATH]");
      Ada.Text_IO.Put_Line ("Browse git history at REVISION (default: HEAD).");
      Ada.Text_IO.Put_Line
        ("Filters: --author VALUE  --since DATE  --until DATE  --grep TEXT");
      Ada.Text_IO.Put_Line ("         --all  --first-parent  -- PATH");
      Ada.Text_IO.Put_Line ("Display: --no-mouse");
      Ada.Text_IO.Put_Line ("Explorer: --worktree  --index  --base REVISION");
      Ada.Text_IO.Put_Line ("          --legacy (original two-pane diff viewer)");
   end Print_Help;

   type Pending_Filter is
     (No_Filter, Need_Author, Need_Since, Need_Until, Need_Message);

   Ok            : Boolean;
   Use_Mouse     : Boolean := True;
   From          : Git_View_Source.Revision;
   History_Filter : Git_View_Source.Filters;
   Have_From     : Boolean := False;
   Path_Mode     : Boolean := False;
   Pending       : Pending_Filter := No_Filter;
   Legacy        : Boolean := False;
   Kind          : Git_View_Model.Snapshot_Kind := Git_View_Model.Commit;
   Base          : Git_View_Source.Revision;
   Need_Base     : Boolean := False;

begin
   for I in 1 .. Argument_Count loop
      if Need_Base then
         Git_View_Source.Make_Revision (Argument (I), Base, Ok);
         if not Ok then Fail ("base must contain 1 to 255 characters"); return; end if;
         Need_Base := False;
      elsif Pending /= No_Filter then
         declare
            Value : Git_View_Source.Filter_Value;
            Valid : Boolean;
         begin
            Git_View_Source.Make_Filter (Argument (I), Value, Valid);
            if not Valid then
               Fail ("filter value must contain 1 to 255 characters");
               return;
            end if;
            case Pending is
               when Need_Author  => History_Filter.Author := Value;
               when Need_Since   => History_Filter.Since := Value;
               when Need_Until   => History_Filter.Until_Date := Value;
               when Need_Message => History_Filter.Message := Value;
               when No_Filter    => null;
            end case;
            Pending := No_Filter;
         end;
      elsif Path_Mode then
         if History_Filter.Path.Len > 0 then
            Fail_Usage (Argument (I));
            return;
         end if;
         declare
            Valid : Boolean;
         begin
            Git_View_Source.Make_Filter
              (Argument (I), History_Filter.Path, Valid);
            if not Valid then
               Fail ("path must contain 1 to 255 characters");
               return;
            end if;
         end;
      elsif Argument (I) = "--no-mouse" then
         Use_Mouse := False;
      elsif Argument (I) = "--legacy" then
         Legacy := True;
      elsif Argument (I) = "--worktree" then
         Kind := Git_View_Model.Worktree;
      elsif Argument (I) = "--index" then
         Kind := Git_View_Model.Staging;
      elsif Argument (I) = "--base" then
         Need_Base := True;
      elsif Argument (I) = "--help" or else Argument (I) = "-h"
      then
         Print_Help;
         return;
      elsif Argument (I) = "--all" then
         History_Filter.All_Refs := True;
      elsif Argument (I) = "--first-parent" then
         History_Filter.First_Parent := True;
      elsif Argument (I) = "--author" then
         Pending := Need_Author;
      elsif Argument (I) = "--since" then
         Pending := Need_Since;
      elsif Argument (I) = "--until" then
         Pending := Need_Until;
      elsif Argument (I) = "--grep" then
         Pending := Need_Message;
      elsif Argument (I) = "--" then
         Path_Mode := True;
      elsif Argument (I)'Length > 0
        and then Argument (I) (Argument (I)'First) = '-'
      then
         Fail_Usage (Argument (I));
         return;
      elsif Have_From then
         Fail_Usage (Argument (I));
         return;
      else
         declare
            Valid : Boolean;
         begin
            Git_View_Source.Make_Revision (Argument (I), From, Valid);
            if not Valid then
               Fail ("revision must contain 1 to 255 characters");
               return;
            end if;
            Have_From := True;
         end;
      end if;
   end loop;

   if Pending /= No_Filter or else Need_Base then
      Fail ("filter option requires a value");
      return;
   end if;

   if not Legacy then
      Git_View_Explorer.Init (From, History_Filter, Kind, Base);
      Run_Explorer (Use_Mouse);
      return;
   end if;

   if not Git_View_Source.Available then
      Fail ("git not found on PATH");
      return;
   end if;

   --  Load the commit list (and the first diff). On failure the repository
   --  adapter has already written the backend's own message ("fatal: not a
   --  git repository ...") to standard error, which is still the terminal
   --  at this point.
   Git_View_App.Init (From, History_Filter, Ok);
   if not Ok then
      Fail ("cannot read the git log");
      return;
   end if;

   Run (Mouse => Use_Mouse);

exception
   --  The last-chance net. The proof shows the orchestration itself raises
   --  nothing, but it does not cover storage exhaustion nor whatever the
   --  unproved loop driver might let escape.
   when others =>
      Fail ("unexpected failure");
end Git_View_Main;
