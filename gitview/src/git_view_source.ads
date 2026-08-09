--  Git_View_Source — the git subprocess edge, with a machine-checked
--  boundary.
--
--  This is the one place git is run. This spec carries the contracts the
--  proved app checks against (above all, that a loaded document reference
--  is never null where the app needs one), and they are PROVED, not
--  trusted: the body is SPARK too, holding the policy — argument
--  construction, exit-code handling, the failure fallback. Only the
--  spawn/capture mechanics sit behind a trusted private child, mirroring
--  the terminal driver's syscall edge.
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

   --  One optional git revision (branch, tag, object name or revision
   --  expression). The bounded representation crosses the proved source
   --  policy without heap ownership.
   Max_Revision_Length : constant := 255;
   subtype Revision_Length is Natural range 0 .. Max_Revision_Length;

   type Revision is record
      Text : String (1 .. Max_Revision_Length) := (others => ' ');
      Len  : Revision_Length := 0;  --  zero means git's default HEAD history
   end record;

   procedure Make_Revision
     (Text  : String;
      Value : out Revision;
      Ok    : out Boolean)
   with Global => null,
        Post   => Ok = (Text'Length in 1 .. Max_Revision_Length)
                  and then (if Ok then Value.Len = Text'Length);

   function Image (Value : Revision) return String is
     (Value.Text (1 .. Value.Len))
   with Post => Image'Result'First = 1
                and then Image'Result'Length = Value.Len;

   --  Read-only git-log filters. Bounded strings keep the command policy in
   --  SPARK and cross the OS edge as individual argv entries, never a shell
   --  command. A zero-length value means that filter is absent.
   Max_Filter_Length : constant := 255;
   subtype Filter_Length is Natural range 0 .. Max_Filter_Length;

   type Filter_Value is record
      Text : String (1 .. Max_Filter_Length) := (others => ' ');
      Len  : Filter_Length := 0;
   end record;

   procedure Make_Filter
     (Text  : String;
      Value : out Filter_Value;
      Ok    : out Boolean)
   with Global => null,
        Post   => Ok = (Text'Length in 1 .. Max_Filter_Length)
                  and then (if Ok then Value.Len = Text'Length);

   function Image (Value : Filter_Value) return String is
     (Value.Text (1 .. Value.Len))
   with Post => Image'Result'First = 1
                and then Image'Result'Length = Value.Len;

   type Filters is record
      Author       : Filter_Value;
      Since        : Filter_Value;
      Until_Date   : Filter_Value;
      Message      : Filter_Value;
      Path         : Filter_Value;
      All_Refs     : Boolean := False;
      First_Parent : Boolean := False;
   end record;

   --  True when a git executable can be found on PATH. A host checks this
   --  once at startup to fail with a clear message instead of a dead screen.
   function Available return Boolean with Global => null;

   --  Run git log in the current directory and load its output into a fresh
   --  document: one line per commit, the abbreviated id first. Ok is False —
   --  and Doc null — when git could not run or reported failure (typically:
   --  not inside a repository); git's own message goes to standard error,
   --  which is still the terminal at startup.
   procedure Load_Log
     (From    : Revision;
      Filter  : Filters;
      Doc     : out Tui.Text.Doc_Ref;
      Ok      : out Boolean)
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
