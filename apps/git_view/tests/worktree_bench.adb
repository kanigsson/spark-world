--  Timing harness for worktree frames: what switching files in the
--  uncommitted snapshot costs once the caches are as warm as they get.
with Ada.Command_Line; use Ada.Command_Line;
with Git_View_Model;   use Git_View_Model;
with Git_View_Repository;
with Git_View_Bench;

procedure Worktree_Bench is
   V : View_State;
   F : Git_View_Repository.Frame;
begin
   V.Kind := Worktree;
   V.Lens := Hunks;
   V.Visibility := Changed_Only;
   Git_View_Bench.Timed ("cold", 1, V, F);
   Git_View_Bench.Timed ("warm, same view", 5, V, F);
   for I in 1 .. Argument_Count loop
      V.Scope := To_Text (Argument (I));
      Git_View_Bench.Timed ("scope " & Argument (I), 3, V, F);
   end loop;
   Git_View_Repository.Free (F);
end Worktree_Bench;
