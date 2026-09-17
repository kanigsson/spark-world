with Ada.Text_IO;
with Git_View_Model; use Git_View_Model;
with Tui.Pager.Engine;
procedure Model_Tests is
   V, Saved : View_State;
   N : Navigation;
begin
   V.Snapshot := To_Text ("first");
   V.Base := To_Text ("base");
   V.Automatic_Base := False;
   V.Scope := To_Text ("src/file.adb");
   Toggle_Pin (V);
   V.Path_Filter := V.Scope;
   V.Repository_Search := To_Text ("needle");
   V.Focus := Source_Pane;
   V.Selected := (2, 4, 8);
   Tui.Pager.Engine.Resize (V.Views (Source_Pane), 12, 30, 200);
   Tui.Pager.Engine.Go_To_Line (V.Views (Source_Pane), 84, 200);
   Tui.Pager.Engine.Set_Pattern (V.Views (Source_Pane), [97, 98]);
   Saved := V;
   Push (N, V);
   Select_Snapshot (V, To_Text ("second"));
   pragma Assert (V.Scope = Saved.Scope and then V.Pin = Saved.Pin);
   pragma Assert (V.Automatic_Base and then V.Base.Last = 0);
   Back (N, V);
   pragma Assert (V = Saved);
   Forward (N, V);
   pragma Assert (V.Snapshot = To_Text ("second"));
   Back (N, V);
   Push (N, V);
   pragma Assert (not Can_Forward (N));
   for I in 1 .. 140 loop
      V.Scope := To_Text (I'Image); Push (N, V);
   end loop;
   for I in reverse 13 .. 140 loop
      Back (N, V); pragma Assert (V.Scope = To_Text (I'Image));
   end loop;
   pragma Assert (not Can_Back (N));
   pragma Assert (Deletion_Anchor (0, 0) = 1);
   pragma Assert (Deletion_Anchor (8, 0) = 9);
   pragma Assert (Deletion_Anchor (8, 2) = 8);
   pragma Assert (In_Range (Natural'Last, Natural'Last, 1));
   pragma Assert (not In_Range (0, 1, Natural'Last));
   pragma Assert (In_Context (Natural'Last, Natural'Last - 1, 1));
   Ada.Text_IO.Put_Line ("model tests passed");
end Model_Tests;
