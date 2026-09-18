--  Git_View_Source.OS — the repository adapter, as small as it gets.
--
--  The parent draws the proved/trusted seam at its spec; this private child
--  holds the untrusted side: it drives the git_changes library, which owns
--  every repository query this program makes, and turns what comes back into a
--  document. The BODY is SPARK_Mode => Off by design; what can be decided
--  in proved code (what a failed load means for the pane, what to show
--  instead) stays in the parent's proved body.
--
--  Queries cross the boundary as the parent's own bounded records, so the
--  proved side never touches an access-to-string.

private package Git_View_Source.OS
  with SPARK_Mode => On
is

   --  True when the repository backend can be reached at all.
   function Find_Git return Boolean
   with Global => null;

   --  Walk history and render one line per commit, the abbreviated id
   --  first: the proved commit-id parser depends on that placement. Doc is
   --  null when the walk failed.
   procedure Load_History
     (From   : Revision;
      Filter : Filters;
      Doc    : out Tui.Text.Doc_Ref;
      Ok     : out Boolean)
   with Global => null, Post => Ok = (Doc /= null);

   --  Load the patch text of one commit. On failure Doc holds whatever the
   --  backend reported, so the diff pane shows a real message rather than a
   --  blank screen; it is null only when nothing could be obtained at all.
   procedure Load_Commit
     (Id : String; Doc : out Tui.Text.Doc_Ref; Ok : out Boolean)
   with Global => null;

end Git_View_Source.OS;
