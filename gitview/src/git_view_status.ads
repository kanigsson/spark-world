--  Git_View_Status — the git viewer's status-line formatter, as proved SPARK.
--
--  The bottom row shows one of: the search prompt being typed, a transient
--  note ("Pattern not found", "No commit on this line"), or a position
--  read-out for whichever pane has the keyboard. The text never needs to
--  exceed the screen width, so a fixed-size line buffer holds it and the
--  formatting is proved free of run-time errors, mirroring the standalone
--  pager's formatter.
--
--  The host still owns the surface: it fills the bar and paints Image (L)
--  onto the row, truncating to the real column count. This package only
--  builds the string.

with Tui.Text;

package Git_View_Status with SPARK_Mode => On is

   --  Upper bound on assembled status text. A surface row caps at 4096
   --  columns and the host truncates to the actual width when painting, so
   --  text past this point is never visible; a longer input is silently
   --  clipped here, never a buffer overrun.
   Max_Status : constant := 4_096;
   subtype Status_Length is Natural range 0 .. Max_Status;

   type Line is private;

   function Length (L : Line) return Status_Length;

   --  The assembled text, 1-based, ready for the host's painter.
   function Image (L : Line) return String
   with Post => Image'Result'First = 1
               and then Image'Result'Length = Length (L);

   --  A transient note. The wording lives here; the app only records which
   --  note (if any) is due.
   type Note is
     (No_Note,
      Pattern_Not_Found,   --  a search or repeat found nothing
      No_Pattern,          --  repeat requested with no pattern installed
      No_Commit_On_Line,   --  Enter on a line that carries no commit id
      Git_Show_Failed);    --  the diff subprocess reported an error

   --  Search prompt: '/' (forward) or '?' (backward), then the pattern
   --  bytes. Each byte is shown as a Latin-1 character, matching the host's
   --  painter (which maps one byte to one cell); multibyte UTF-8 thus
   --  renders as its raw bytes.
   procedure Format_Prompt
     (L       : out Line;
      Forward : Boolean;
      Pattern : Tui.Text.Buffer)
   with Pre => Pattern'Length = 0 or else Pattern'First >= 1;

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

private

   type Line is record
      Text : String (1 .. Max_Status) := (others => ' ');
      Len  : Status_Length            := 0;
   end record;

   function Length (L : Line) return Status_Length is (L.Len);

   function Image (L : Line) return String is (L.Text (1 .. L.Len));

end Git_View_Status;
