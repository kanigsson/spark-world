--  Tui.Width — display column width of a Unicode code point.
--
--  A terminal cell grid advances by columns, not by characters: a combining
--  mark overlays the previous glyph (0 columns), an East-Asian wide glyph takes
--  2, most everything takes 1. This is the Ada/SPARK analogue of POSIX
--  `wcwidth`, which Ada's standard library does not provide. The pager's layout
--  uses it to map code points to cells; without it, CJK and combining text
--  misalign.
--
--  Pure lookup, no state, no I/O — all SPARK, proved free of run-time errors.
--  The classification is a binary search over sorted interval tables.
--
--  TABLE PROVENANCE / SCOPE: the interval tables in the body are a *curated
--  subset* of the well-known Unicode blocks (the classic Markus-Kuhn wcwidth
--  set): the common combining ranges and the standard CJK / Hangul / fullwidth
--  / emoji wide ranges. They are correct for the common cases but are NOT the
--  full Unicode Character Database. A complete implementation regenerates them
--  offline from UnicodeData.txt (general categories Mn, Me, Cf) and
--  EastAsianWidth.txt (W, F); the tables are shaped like that generated output
--  so they can be replaced wholesale. `Tables_Well_Formed` checks the ordering
--  invariant the search relies on.

package Tui.Width with SPARK_Mode => On is

   subtype Code_Point   is Natural range 0 .. 16#10_FFFF#;
   subtype Column_Count is Natural range 0 .. 2;

   --  Columns the code point occupies when rendered:
   --    0 = combining / zero-width, or a non-printable control,
   --    2 = East-Asian wide / fullwidth,
   --    1 = everything else.
   function Char_Width (CP : Code_Point) return Column_Count
   with Global => null,
        Post   => Char_Width'Result =
                    (if Is_Control (CP) or else Is_Zero_Width (CP) then 0
                     elsif Is_Wide (CP) then 2
                     else 1);

   --  C0 (0..16#1F#) and C1 (16#7F#..16#9F#) control codes. Char_Width is 0 for
   --  these; a caller that renders controls specially (tabs, caret notation)
   --  should branch on this before asking for a width.
   function Is_Control (CP : Code_Point) return Boolean
   is (CP <= 16#1F# or else (CP in 16#7F# .. 16#9F#))
   with Global => null;

   --  East-Asian wide / fullwidth: occupies 2 columns.
   function Is_Wide (CP : Code_Point) return Boolean with Global => null;

   --  Combining mark or otherwise zero-width: occupies 0 columns.
   function Is_Zero_Width (CP : Code_Point) return Boolean with Global => null;

   --  Diagnostic: True iff the internal interval tables are sorted and
   --  non-overlapping — the precondition the binary search relies on. Exposed so
   --  tests can guard against transcription errors when the tables are edited.
   function Tables_Well_Formed return Boolean with Global => null;

end Tui.Width;
