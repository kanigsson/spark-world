with Tui.Pager.Engine;
with Tui.Text;
with Git_View_Source;

--  Frontend-independent navigation state. A location is a value: restoring
--  it also restores searches, horizontal offsets, selections and filters.
package Git_View_Model with SPARK_Mode => On is
   Max_Text : constant := 4_096;
   type Text is record
      Data : String (1 .. Max_Text) := (others => ' ');
      Last : Natural range 0 .. Max_Text := 0;
   end record;
   function To_Text (S : String) return Text
     with Pre => S'Length <= Max_Text;
   function Image (S : Text) return String is (S.Data (1 .. S.Last));

   type Snapshot_Kind is (Commit, Worktree, Staging);

   --  The uncommitted states are rows of the history pane above the
   --  commits, so they are reached by moving the selection like any other
   --  snapshot rather than by remembering a key. Their identities begin
   --  with a colon, which no object name can, so no commit is mistaken for
   --  one.
   Worktree_Row : constant String := ":worktree";
   Index_Row : constant String := ":index";
   function Row_Kind (Id : String) return Snapshot_Kind is
     (if Id = Worktree_Row then Worktree
      elsif Id = Index_Row then Staging
      else Commit);
   --  What a history row names as a snapshot: a commit is named by its
   --  object name, the uncommitted states by their kind alone.
   function Row_Snapshot (Id : String) return String is
     (if Row_Kind (Id) = Commit then Id else "");

   --  The commit message is a row of the tree pane like a file, so reading
   --  it is one more move of the selection. Its identity begins with a byte
   --  no path can contain.
   Message_Row : constant String := ASCII.NUL & "COMMIT_MSG";
   Message_Label : constant String := "COMMIT_MSG";
   function Is_Message (Path : String) return Boolean is (Path = Message_Row);
   --  A scope as it reads on a status line: the message row names itself.
   function Scope_Label (Path : String) return String is
     (if Is_Message (Path) then Message_Label else Path);

   type Change_Lens is (Plain, Gutter, Changed_Lines, Hunks, Before_After);
   type Tree_Visibility is (All_Files, Changed_Only);
   type Pane is (History_Pane, Tree_Pane, Source_Pane);
   type Engines is array (Pane) of Tui.Pager.Engine.Instance;
   type Selections is array (Pane) of Tui.Text.Line_Number;
   type View_State is record
      Snapshot : Text;
      Base : Text;
      Kind : Snapshot_Kind := Commit;
      Automatic_Base : Boolean := True;
      Scope : Text;
      Pin : Text;
      History_Root : Git_View_Source.Revision;
      History_Filter : Git_View_Source.Filters;
      Path_Filter : Text;
      Repository_Search : Text;
      Lens : Change_Lens := Hunks;
      Visibility : Tree_Visibility := Changed_Only;
      Focus : Pane := History_Pane;
      Views : Engines;
      Selected : Selections := (others => 1);
      Maximized : Boolean := False;
   end record;

   procedure Select_Snapshot
     (V : in out View_State; Name : Text; Kind : Snapshot_Kind := Commit);
   procedure Select_Scope (V : in out View_State; Path : Text);
   procedure Cycle_Lens (V : in out View_State);
   procedure Cycle_Tree (V : in out View_State);
   procedure Toggle_Pin (V : in out View_State);

   --  Bounded navigation history; when full the oldest entry is evicted.
   Stack_Capacity : constant := 128;
   type Navigation is private;
   procedure Push (N : in out Navigation; V : View_State);
   procedure Back (N : in out Navigation; V : in out View_State);
   procedure Forward (N : in out Navigation; V : in out View_State);
   function Can_Back (N : Navigation) return Boolean;
   function Can_Forward (N : Navigation) return Boolean;

   --  Shared overlay arithmetic, including Git's zero-length deletion anchor.
   function In_Range (Line, First, Count : Natural) return Boolean is
     (Line >= First and then Line - First < Count);
   function Deletion_Anchor (First, Count : Natural) return Natural is
     (if Count = 0 and then First < Natural'Last then First + 1 else First);
   function In_Context
     (Line, First, Count : Natural; Context : Natural := 3) return Boolean;
private
   type Locations is array (1 .. Stack_Capacity) of View_State;
   type Navigation is record
      Past, Future : Locations;
      Past_Count, Future_Count : Natural range 0 .. Stack_Capacity := 0;
   end record;
end Git_View_Model;
