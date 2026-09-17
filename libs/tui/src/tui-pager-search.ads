--  Tui.Pager.Search — find content lines containing a literal pattern.
--
--  The hot-path matcher: a pure, proved literal (byte-for-byte) substring
--  search over the content the engine already holds (a Tui.Text index + the
--  buffer it was built over). It answers two questions a pager asks: "does this
--  line contain the pattern?" and "what is the next/previous matching line?".
--
--  Literal, byte-level, case-sensitive. That is deliberate for v1: UTF-8 is
--  self-synchronising, so a byte-substring match of one valid UTF-8 pattern
--  inside a valid UTF-8 line is exactly a code-point-substring match — no
--  decoding needed. A real regex backend (GNAT.Regpat, non-SPARK) is the future
--  island the roadmap parks behind this same surface; the literal path stays
--  proved.
--
--  All SPARK, proved free of run-time errors. The buffer/index preconditions
--  (mirroring Tui.Pager.Render's) are what make every byte access provably safe.

with Tui.Text;

package Tui.Pager.Search with SPARK_Mode => On is

   --  True when line N's bytes contain Pattern as a contiguous substring. An
   --  empty pattern never matches (the engine never searches with one), which
   --  keeps "no pattern" and "matches everything" from being confused.
   function Line_Matches
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Pattern : Tui.Text.Buffer;
      N       : Line_Number) return Boolean
   with Global => null,
        Pre => Content'First = 1
               and then Content'Last >= Tui.Text.Scanned_Bytes (Index)
               and then Pattern'First = 1
               and then N <= Tui.Text.Line_Count (Index);

   --  Scan for a matching line, starting at From (inclusive) and moving toward
   --  the end (Forward) or the start. On success Found is True and Line is the
   --  first match in that direction; otherwise Found is False and Line is From.
   procedure Find
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Pattern : Tui.Text.Buffer;
      From    : Line_Number;
      Forward : Boolean;
      Found   : out Boolean;
      Line    : out Line_Number)
   with Global => null,
        Pre  => Content'First = 1
                and then Content'Last >= Tui.Text.Scanned_Bytes (Index)
                and then Pattern'First = 1
                and then Tui.Text.Line_Count (Index) >= 1
                and then From <= Tui.Text.Line_Count (Index),
        Post => (if Found then Line <= Tui.Text.Line_Count (Index));

end Tui.Pager.Search;
