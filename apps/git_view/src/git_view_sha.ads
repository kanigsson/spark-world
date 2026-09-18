--  Git_View_Sha — extracting the commit id from a commit-list line, as proved
--  SPARK.
--
--  The commit list shown in the left pane is the output of a git log
--  invocation whose format puts the abbreviated commit id first on every
--  line, followed by a space. Mapping "the selected line" to "the commit to
--  show" is therefore a pure parse of the line's leading token, done here
--  over the document's own line index so that the mapping is a proved
--  function of the displayed content — there is no separate id table that
--  could drift out of step with the list.
--
--  Trusted pairing (prose contract): the OS edge that produces the list must
--  use a log format whose lines start with the abbreviated commit id and a
--  space. A line that does not parse (blank, malformed) yields an invalid
--  result, which the app treats as "no commit on this line".

with Tui.Text;

package Git_View_Sha
  with SPARK_Mode => On
is

   --  A full git object name is 40 hexadecimal characters; abbreviated ids
   --  are shorter. A longer leading token is not a commit id.
   Max_Sha : constant := 40;
   subtype Sha_Length is Natural range 0 .. Max_Sha;

   type Sha is record
      Text : String (1 .. Max_Sha) := (others => ' ');
      Len  : Sha_Length := 0;   --  0 = no commit id on the line
   end record;

   function Valid (S : Sha) return Boolean
   is (S.Len > 0);

   --  The id's characters, 1-based — ready for a repository query or the
   --  status line.
   function Image (S : Sha) return String
   is (S.Text (1 .. S.Len))
   with Post => Image'Result'First = 1 and then Image'Result'Length = S.Len;

   --  Parse line N of the commit list: the leading run of hexadecimal
   --  characters up to the first space (or the line's end). Result.Len = 0
   --  when the line carries no such token.
   procedure Extract
     (Content : Tui.Text.Buffer;
      Idx     : Tui.Text.Index;
      N       : Tui.Text.Line_Number;
      Result  : out Sha)
   with
     Global => null,
     Pre    =>
       N <= Tui.Text.Line_Count (Idx)
       and then Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Idx);

end Git_View_Sha;
