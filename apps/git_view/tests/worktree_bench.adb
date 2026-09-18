--  Timing harness for worktree frames: what switching files in the
--  uncommitted snapshot costs once the caches are as warm as they get.
with Ada.Calendar;     use Ada.Calendar;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Git_View_Model;   use Git_View_Model;
with Git_View_Repository;

procedure Worktree_Bench is
   V : View_State;
   F : Git_View_Repository.Frame;
   procedure Timed (Name : String; Runs : Positive) is
      Start : Time;
      Total : Duration := 0.0;
   begin
      for I in 1 .. Runs loop
         Start := Clock;
         Git_View_Repository.Load (V, F);
         Total := Total + (Clock - Start);
      end loop;
      Put_Line (Name & ": " & Duration'Image (Total / Runs * 1000.0) & " ms");
   end Timed;
begin
   V.Kind := Worktree;
   V.Lens := Hunks;
   V.Visibility := Changed_Only;
   Timed ("cold", 1);
   Timed ("warm, same view", 5);
   for I in 1 .. Argument_Count loop
      V.Scope := To_Text (Argument (I));
      Timed ("scope " & Argument (I), 3);
   end loop;
   Git_View_Repository.Free (F);
end Worktree_Bench;
