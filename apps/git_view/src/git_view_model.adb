package body Git_View_Model
  with SPARK_Mode => On
is
   function To_Text (S : String) return Text is
      R : Text;
   begin
      R.Data (1 .. S'Length) := S;
      R.Last := S'Length;
      return R;
   end To_Text;

   procedure Select_Snapshot
     (V : in out View_State; Name : Text; Kind : Snapshot_Kind := Commit)
   is
      Empty : Tui.Pager.Engine.Instance;
   begin
      V.Snapshot := Name;
      V.Kind := Kind;
      V.Automatic_Base := True;
      V.Base := To_Text ("");
      if V.Pin.Last > 0 then
         V.Scope := V.Pin;
      end if;
      V.Views (Tree_Pane) := Empty;
      V.Views (Source_Pane) := Empty;
      V.Selected (Source_Pane) := 1;
      V.Selected (Tree_Pane) := 1;
      V.Repository_Search := To_Text ("");
   end Select_Snapshot;

   procedure Select_Scope (V : in out View_State; Path : Text) is
      Empty : Tui.Pager.Engine.Instance;
   begin
      V.Scope := Path;
      V.Views (Source_Pane) := Empty;
      V.Selected (Source_Pane) := 1;
   end Select_Scope;

   procedure Select_Preset (V : in out View_State; Value : Source_Preset) is
   begin
      case Value is
         when Plain         =>
            V.Extent := Full_File;
            V.Decoration := Plain;

         when Gutter        =>
            V.Extent := Full_File;
            V.Decoration := Gutter;

         when Changed_Lines =>
            V.Extent := Full_File;
            V.Decoration := Emphasized;

         when Hunks         =>
            V.Extent := Context;
            V.Decoration := Gutter;
      end case;
   end Select_Preset;

   procedure Cycle_Preset (V : in out View_State) is
   begin
      Select_Preset
        (V,
         (if Preset (V) = Source_Preset'Last
          then Source_Preset'First
          else Source_Preset'Succ (Preset (V))));
   end Cycle_Preset;

   procedure Cycle_Side (V : in out View_State) is
   begin
      V.Side :=
        (if V.Side = Source_Side'Last
         then Source_Side'First
         else Source_Side'Succ (V.Side));
   end Cycle_Side;

   procedure Cycle_Tree (V : in out View_State) is
   begin
      V.Visibility :=
        (if V.Visibility = Tree_Visibility'Last
         then Tree_Visibility'First
         else Tree_Visibility'Succ (V.Visibility));
      V.Selected (Tree_Pane) := 1;
   end Cycle_Tree;

   procedure Toggle_Pin (V : in out View_State) is
   begin
      if V.Pin.Last > 0 then
         V.Pin := To_Text ("");
      else
         V.Pin := V.Scope;
      end if;
   end Toggle_Pin;

   procedure Append
     (Items : in out Locations; Count : in out Natural; V : View_State)
   with Pre => Count <= Stack_Capacity, Post => Count in 1 .. Stack_Capacity
   is
   begin
      if Count = Stack_Capacity then
         for I in 1 .. Stack_Capacity - 1 loop
            Items (I) := Items (I + 1);
         end loop;
      else
         Count := Count + 1;
      end if;
      Items (Count) := V;
   end Append;

   procedure Push (N : in out Navigation; V : View_State) is
   begin
      Append (N.Past, N.Past_Count, V);
      N.Future_Count := 0;
   end Push;
   procedure Back (N : in out Navigation; V : in out View_State) is
   begin
      if N.Past_Count > 0 then
         Append (N.Future, N.Future_Count, V);
         V := N.Past (N.Past_Count);
         N.Past_Count := N.Past_Count - 1;
      end if;
   end Back;
   procedure Forward (N : in out Navigation; V : in out View_State) is
   begin
      if N.Future_Count > 0 then
         Append (N.Past, N.Past_Count, V);
         V := N.Future (N.Future_Count);
         N.Future_Count := N.Future_Count - 1;
      end if;
   end Forward;
   function Can_Back (N : Navigation) return Boolean
   is (N.Past_Count > 0);
   function Can_Forward (N : Navigation) return Boolean
   is (N.Future_Count > 0);

   function In_Context
     (Line, First, Count : Natural; Context : Natural := 3) return Boolean is
   begin
      if Line < First then
         return First - Line <= Context;
      else
         return
           Line - First < Count
           or else Line - First - Natural'Min (Line - First, Count) <= Context;
      end if;
   end In_Context;
end Git_View_Model;
