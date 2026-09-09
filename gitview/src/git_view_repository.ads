with Git_View_Model;
with Tui.Text;

--  Repository adapter. Every question about the repository — snapshots,
--  contents, comparisons, history — is asked through the git_changes
--  library, and only the worker asks them. Documents and row identities are
--  transferred together, never reparsed from escaped presentation text.
package Git_View_Repository with SPARK_Mode => On,
  Abstract_State => State, Initializes => State
is
   package M renames Git_View_Model;
   use type Tui.Text.Doc_Ref;
   type Row_Target is record
      Path : M.Text;
      Line : Tui.Text.Line_Number := 1;
      Changed : Boolean := False;
   end record;
   type Target_Array is array (Tui.Text.Line_Number range <>) of Row_Target;
   type Target_Ref is access Target_Array;
   type Mark is (Normal, Addition, Ghost, Hunk_Header);
   type Mark_Array is array (Tui.Text.Line_Number range <>) of Mark;
   type Mark_Ref is access Mark_Array;
   type Frame is record
      History, Tree, Source : Tui.Text.Doc_Ref;
      Commits, Paths : Target_Ref;
      Marks : Mark_Ref;
      Resolved_Snapshot, Resolved_Base, Scope, Notice : M.Text;
   end record;
   function Loaded (F : Frame) return Boolean is
     (F.History /= null and then F.Tree /= null and then F.Source /= null);
   procedure Free (F : in out Frame)
     with Global => null, Post => not Loaded (F);
   --  Synchronous entrypoint for nonterminal clients and fixture tests.
   procedure Load (V : M.View_State; F : in out Frame)
     with Global => (In_Out => State), Post => Loaded (F);
   --  Latest request wins. Poll never publishes an obsolete generation.
   procedure Request (V : M.View_State; Refresh : Boolean := False)
     with Global => (In_Out => State);
   procedure Poll (F : in out Frame; Ready : out Boolean)
     with Global => (In_Out => State), Post => (if Ready then Loaded (F));
   procedure Stop with Global => (In_Out => State);
end Git_View_Repository;
