with Git_View_Source;
with Git_View_Model;
with Git_View_Repository;
with Tui.Surface;
with Tui.Input;

package Git_View_Explorer
  with SPARK_Mode => On, Abstract_State => State, Initializes => State
is
   procedure Init
     (From   : Git_View_Source.Revision;
      Filter : Git_View_Source.Filters;
      Kind   : Git_View_Model.Snapshot_Kind;
      Base   : Git_View_Source.Revision)
   with Global => (In_Out => (State, Git_View_Repository.State));
   procedure Paint (S : in out Tui.Surface.Surface)
   with Global => (In_Out => State);
   procedure On_Key (Event : Tui.Input.Key_Event; Dirty, Quit : out Boolean)
   with Global => (In_Out => (State, Git_View_Repository.State));
   procedure Tick (Dirty : out Boolean)
   with Global => (In_Out => (State, Git_View_Repository.State));
   procedure Stop
   with Global => (In_Out => (State, Git_View_Repository.State));
end Git_View_Explorer;
