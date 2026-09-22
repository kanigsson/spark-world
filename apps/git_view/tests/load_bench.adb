--  Timing harness for the repository adapter: reports how long one frame
--  build takes cold, then warm, then while only the scope moves, which is
--  what a keystroke costs once the caches are populated.
with Ada.Command_Line; use Ada.Command_Line;
with Ore.Images;
with Git_View_Model;   use Git_View_Model;
with Git_View_Repository;
with Git_View_Bench;

procedure Load_Bench is
   V : View_State;
   F : Git_View_Repository.Frame;
begin
   V.Snapshot := To_Text (Argument (1));
   Select_Preset (V, Hunks);
   V.Visibility := Changed_Only;
   Git_View_Bench.Timed ("cold", 1, V, F);
   Git_View_Bench.Timed ("warm, same view", 5, V, F);
   for I in 2 .. Argument_Count loop
      V.Scope := To_Text (Argument (I));
      Git_View_Bench.Timed ("scope " & Argument (I), 3, V, F);
   end loop;
   V.Scope := To_Text ("");
   for I in 1 .. 5 loop
      V.Snapshot := To_Text ("HEAD~" & Ore.Images.Decimal (I));
      Git_View_Bench.Timed
        ("snapshot HEAD~" & Ore.Images.Decimal (I), 1, V, F);
   end loop;
   Git_View_Repository.Free (F);
end Load_Bench;
