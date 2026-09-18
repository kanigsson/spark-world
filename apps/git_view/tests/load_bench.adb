--  Timing harness for the repository adapter: reports how long one frame
--  build takes cold, then warm, then while only the scope moves, which is
--  what a keystroke costs once the caches are populated.
with Ada.Calendar;      use Ada.Calendar;
with Ada.Strings;       use Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Command_Line;  use Ada.Command_Line;
with Ada.Text_IO;       use Ada.Text_IO;
with Git_View_Model;    use Git_View_Model;
with Git_View_Repository;

procedure Load_Bench is
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
   V.Snapshot := To_Text (Argument (1));
   V.Lens := Hunks;
   V.Visibility := Changed_Only;
   Timed ("cold", 1);
   Timed ("warm, same view", 5);
   for I in 2 .. Argument_Count loop
      V.Scope := To_Text (Argument (I));
      Timed ("scope " & Argument (I), 3);
   end loop;
   V.Scope := To_Text ("");
   for I in 1 .. 5 loop
      V.Snapshot :=
        To_Text ("HEAD~" & Trim (Integer'Image (I), Ada.Strings.Both));
      Timed ("snapshot HEAD~" & Trim (Integer'Image (I), Ada.Strings.Both), 1);
   end loop;
   Git_View_Repository.Free (F);
end Load_Bench;
