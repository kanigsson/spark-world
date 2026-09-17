--  Git_View_App — the git viewer's state and its two Event_Loop callbacks.
--
--  The terminal driver drives the screen through access-to-subprogram, so
--  the paint/key handlers must be library-level; the documents, the two
--  engine instances, the selection and the search state therefore live in
--  this package, set up once by Init before the loop starts.
--
--  This is the multi-pane case the engine's component model exists for: TWO
--  pager engines — the commit list and the diff — each rendered into its own
--  pane-sized surface and composited into the screen with the surface
--  crate's region copy. The engine knows nothing about git; this package
--  decides policy (the keymap, the selection, the status line) and pulls
--  content through the repository edge.
--
--  Like the standalone pager's app package, this is proved SPARK. Both
--  documents are owned, line-indexed holders whose predicate ties the buffer
--  length to the index's scanned prefix, so the engines' content
--  preconditions discharge by construction at every Render/Handle call —
--  including right after the diff document is swapped for a new commit's.

with Tui.Surface;
with Tui.Input;
with Git_View_Source;

package Git_View_App with
  SPARK_Mode        => On,
  Abstract_State    => State,
  Initializes       => State,
  Initial_Condition => Uninitialized
is

   --  True before Init has run: nothing is loaded yet. Init requires it (it
   --  would otherwise leak the documents it overwrites).
   function Uninitialized return Boolean with Global => (Input => State);

   --  True once Init has loaded the commit list and a diff document. The
   --  callbacks require it: the host must call Init — successfully — before
   --  running the event loop.
   function Has_Documents return Boolean with Global => (Input => State);

   --  Load the commit list and the first commit's diff through the git
   --  repository edge. Ok is False when the log could not be loaded (then
   --  nothing is held and the host should exit with a message); a diff
   --  failure is not fatal — the pane shows the error and a note is posted.
   procedure Init
     (From   : Git_View_Source.Revision;
      Filter : Git_View_Source.Filters;
      Ok     : out Boolean)
   with Global => (In_Out => State),
        Pre    => Uninitialized,
        Post   => Ok = Has_Documents;

   --  Event_Loop callbacks.
   procedure Paint (S : in out Tui.Surface.Surface)
   with Global => (In_Out => State),
        Pre    => Has_Documents,
        Post   => Has_Documents;

   procedure On_Key
     (Event : Tui.Input.Key_Event;
      Dirty : out Boolean;
      Quit  : out Boolean)
   with Global => (In_Out => State),
        Pre    => Has_Documents,
        Post   => Has_Documents;

end Git_View_App;
