--  Git_View_Status — the git viewer's status-line formatter, as proved SPARK.
--
--  The bottom row shows one of: the search prompt being typed, a transient
--  note ("Pattern not found", "No commit on this line"), or a position
--  read-out for whichever pane has the keyboard. The line buffer, its
--  building blocks and the prompt formatting are mechanism and live in the
--  shared app kit; this package keeps what is this app's policy — which
--  notes exist, their wording, and the two panes' read-out layouts — and
--  re-exports the kit's Line so the host deals with one package for the
--  status row.
--
--  The host still owns the surface: it fills the bar and paints Image (L)
--  onto the row, truncating to the real column count. This package only
--  builds the string.

with Tui.Text;
with Tui.App_Kit.Status;

package Git_View_Status with SPARK_Mode => On is

   subtype Line is Tui.App_Kit.Status.Line;

   --  The assembled text, 1-based, ready for the host's painter.
   function Image (L : Line) return String
     renames Tui.App_Kit.Status.Image;

   --  A transient note. The wording lives here; the app only records which
   --  note (if any) is due.
   type Note is
     (No_Note,
      Pattern_Not_Found,   --  a search or repeat found nothing
      No_Pattern,          --  repeat requested with no pattern installed
      No_Commit_On_Line,   --  Enter on a line that carries no commit id
      Git_Show_Failed,     --  the diff subprocess reported an error
      Selection_Copied,
      Selection_Copy_Truncated);

   --  Search prompt: '/' (forward) or '?' (backward), then the pattern
   --  bytes.
   procedure Format_Prompt
     (L       : out Line;
      Forward : Boolean;
      Pattern : Tui.Text.Buffer)
     renames Tui.App_Kit.Status.Format_Prompt;

   --  One of the fixed note messages.
   procedure Format_Note (L : out Line; N : Note)
   with Pre => N /= No_Note;

   --  Position read-out while the commit list has the keyboard:
   --    [commits] SELECTED/TOTAL  ID   (Enter diff  Tab pane  / search  q quit)
   --  Id is the selected commit's abbreviated object name ("" when the line
   --  carries none).
   procedure Format_List_Position
     (L        : out Line;
      Selected : Natural;
      Total    : Natural;
      Id       : String)
   with Pre => Selected <= Tui.Text.Max_Lines
               and then Total <= Tui.Text.Max_Lines;

   --  Position read-out while the diff pane has the keyboard:
   --    [diff] ID  TOP-LAST/TOTAL  PCT%   (Tab pane  / search  q quit)
   procedure Format_Diff_Position
     (L     : out Line;
      Id    : String;
      Top   : Natural;
      Last  : Natural;
      Total : Natural)
   with Pre => Last <= Tui.Text.Max_Lines
               and then Total <= Tui.Text.Max_Lines;

end Git_View_Status;
