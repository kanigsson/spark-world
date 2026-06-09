--  Git_View_Source — the git subprocess edge, with a machine-checked
--  boundary.
--
--  This is the one place git is run. The seam between trusted and proved is
--  drawn exactly at this spec, mirroring the terminal driver's syscall edge:
--  the BODY is SPARK_Mode => Off by design — it spawns processes, captures
--  their output through a temporary file, and allocates argument strings —
--  while this SPEC carries the contracts the proved app checks against
--  (above all, that a loaded document reference is never null where the app
--  needs one).
--
--  Output capture goes through a temporary file rather than a pipe: the
--  subprocess can emit arbitrarily much (a huge diff) without anyone having
--  to drain a pipe concurrently, and the file is then read back with the
--  same single-buffer pattern the standalone pager uses for regular files.
--
--  Trusted pairing (prose contract): Load_Log's format keeps the abbreviated
--  commit id as the first space-terminated token of every line — exactly
--  what the proved commit-id parser expects.

with Tui.Text;
with Git_View_Sha;

package Git_View_Source with SPARK_Mode => On is

   use type Tui.Text.Doc_Ref;

   --  True when a git executable can be found on PATH. A host checks this
   --  once at startup to fail with a clear message instead of a dead screen.
   function Available return Boolean with Global => null;

   --  Run git log in the current directory and load its output into a fresh
   --  document: one line per commit, the abbreviated id first. Ok is False —
   --  and Doc null — when git could not run or reported failure (typically:
   --  not inside a repository); git's own message goes to standard error,
   --  which is still the terminal at startup.
   procedure Load_Log (Doc : out Tui.Text.Doc_Ref; Ok : out Boolean)
   with Global => null,
        Post   => Ok = (Doc /= null);

   --  Replace Doc with the diff of one commit (git show): any document it
   --  held is reclaimed, then the subprocess output is loaded fresh. Never
   --  null on return: on failure the document holds git's error text (or a
   --  one-line fallback) and Ok is False, so the caller can post a note
   --  while the diff pane stays well-formed.
   procedure Load_Diff
     (Id  : Git_View_Sha.Sha;
      Doc : in out Tui.Text.Doc_Ref;
      Ok  : out Boolean)
   with Global => null,
        Pre    => Git_View_Sha.Valid (Id),
        Post   => Doc /= null;

end Git_View_Source;
