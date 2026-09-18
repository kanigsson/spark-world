with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Git_View_Model;   use Git_View_Model;
with Git_View_Repository;
with Git_View_Source;
with Tui.Text;

procedure Explorer_Probe is
   V  : View_State;
   F  : Git_View_Repository.Frame;
   Ok : Boolean;
   procedure Dump (Name : String; D : Tui.Text.Document) is
   begin
      Put_Line ("=== " & Name);
      for B of D.Bytes loop
         Put (Character'Val (B));
      end loop;
      New_Line;
   end Dump;
begin
   V.Snapshot := To_Text (Argument (1));
   --  The commit-message row identifies itself with a byte no path can
   --  contain, which no command line can carry: it is named by its label.
   V.Scope :=
     To_Text
       (if Argument (2) = Message_Label then Message_Row else Argument (2));
   V.Kind := Snapshot_Kind'Value (Argument (3));
   V.Visibility := Tree_Visibility'Value (Argument (4));
   V.Lens := Change_Lens'Value (Argument (5));
   if Argument_Count >= 6 then
      V.Base := To_Text (Argument (6));
      V.Automatic_Base := V.Base.Last = 0;
   end if;
   if Argument_Count >= 7 then
      V.Repository_Search := To_Text (Argument (7));
   end if;
   if Argument_Count >= 8 then
      V.Path_Filter := To_Text (Argument (8));
   end if;
   if Argument_Count >= 9 then
      Git_View_Source.Make_Revision (Argument (9), V.History_Root, Ok);
   end if;
   Git_View_Repository.Load (V, F);
   Put_Line ("snapshot=" & Image (F.Resolved_Snapshot));
   Put_Line ("base=" & Image (F.Resolved_Base));
   Put_Line ("scope=" & Image (F.Scope));
   Put_Line ("notice=" & Image (F.Notice));
   Dump ("history", F.History.all);
   Dump ("tree", F.Tree.all);
   Dump ("source", F.Source.all);
   Git_View_Repository.Free (F);
end Explorer_Probe;
