--  Tui.Surface — an in-memory grid of styled character cells.
--
--  This is the ecosystem's central data type: the lingua franca between
--  things that PRODUCE user interface (a pager, a list, a diff view) and
--  things that DISPLAY it (terminal drivers). Producers write cells into a
--  Surface; drivers read cells out of one. The Surface itself knows nothing
--  about terminals, escape sequences, or I/O — rendering here is *data*, not
--  a side effect. That is what lets the same producer be embedded in any host
--  and what lets this whole package be proved free of run-time errors.
--
--  Everything in this unit is SPARK. No syscalls, no I/O, no globals.

package Tui.Surface with SPARK_Mode => On is

   --  Upper bound on either dimension. No real terminal approaches this; the
   --  cap exists so that index and area arithmetic (notably Rows * Cols in the
   --  diff) stays comfortably inside 32-bit Integer, which keeps the
   --  overflow-freedom proofs trivial.
   Max_Extent : constant := 4_096;

   type Row_Count is range 0 .. Max_Extent;
   type Col_Count is range 0 .. Max_Extent;

   --  Positions are 1-based. A count of 0 means "no rows/cols" (empty
   --  surface); a valid position therefore starts at 1.
   subtype Row_Index is Row_Count range 1 .. Row_Count'Last;
   subtype Col_Index is Col_Count range 1 .. Col_Count'Last;

   ---------------------------------------------------------------------------
   --  Cell contents
   ---------------------------------------------------------------------------

   --  Colour model: the terminal's own default, a 256-colour palette index,
   --  or 24-bit truecolour. A driver downgrades whatever the terminal can't
   --  do; the Surface always records the producer's full intent.
   type Color_Kind is (Default, Palette, RGB);
   subtype Component is Natural range 0 .. 255;

   type Color (Kind : Color_Kind := Default) is record
      case Kind is
         when Default => null;
         when Palette => Index   : Component;
         when RGB     => R, G, B : Component;
      end case;
   end record;

   Default_Color : constant Color := (Kind => Default);

   type Style is record
      Bold, Italic, Underline, Inverse : Boolean := False;
   end record;

   Plain : constant Style := (others => False);

   --  One display column. Wide (e.g. CJK) glyphs and grapheme clusters are a
   --  later concern owned by a separate width crate; when that lands, a wide
   --  glyph will occupy a head cell plus a continuation cell. For now a Cell
   --  is exactly one column holding one code point.
   type Cell is record
      Glyph      : Wide_Wide_Character := ' ';
      Foreground : Color  := Default_Color;
      Background : Color  := Default_Color;
      Attributes : Style  := Plain;
   end record;

   Blank_Cell : constant Cell := (others => <>);

   ---------------------------------------------------------------------------
   --  The surface
   ---------------------------------------------------------------------------

   --  Dimensions are discriminants, so they are visible to clients and fixed
   --  for the life of a given surface. Two surfaces can be diffed only when
   --  their discriminants match (see Tui.Surface.Diff).
   type Surface (Rows : Row_Count; Cols : Col_Count) is private;

   function In_Bounds (S : Surface; R : Row_Index; C : Col_Index) return Boolean
   is (R <= S.Rows and then C <= S.Cols);
   --  The guard used throughout the contracts below.

   function Get (S : Surface; R : Row_Index; C : Col_Index) return Cell
   with Pre => In_Bounds (S, R, C);

   procedure Set (S : in out Surface; R : Row_Index; C : Col_Index; To : Cell)
   with Pre  => In_Bounds (S, R, C),
        Post => Get (S, R, C) = To
                --  Frame condition: Set touches exactly one cell. This is the
                --  property the diff relies on, and the reason every mutator
                --  carries an explicit "everything else is unchanged" clause.
                and then
                  (for all RR in Row_Index range 1 .. S.Rows =>
                     (for all CC in Col_Index range 1 .. S.Cols =>
                        (if RR /= R or else CC /= C
                         then Get (S, RR, CC) = Get (S'Old, RR, CC))));

   function Blank (Rows : Row_Count; Cols : Col_Count) return Surface
   with Post => Blank'Result.Rows = Rows
               and then Blank'Result.Cols = Cols
               and then
                 (for all R in Row_Index range 1 .. Rows =>
                    (for all C in Col_Index range 1 .. Cols =>
                       Get (Blank'Result, R, C) = Blank_Cell));

   procedure Clear (S : in out Surface; To : Cell := Blank_Cell)
   with Post => (for all R in Row_Index range 1 .. S.Rows =>
                   (for all C in Col_Index range 1 .. S.Cols =>
                      Get (S, R, C) = To));

   --  Blit an entire source surface into a rectangle of a destination whose
   --  top-left corner is (At_Row, At_Col). This is the compositing primitive:
   --  a host renders each pane of a multi-pane screen into its own
   --  pane-sized surface, then copies the panes into the one surface a
   --  driver displays. The source must fit inside the destination at the
   --  given position; an empty source is allowed and copies nothing.
   procedure Copy
     (Src    : Surface;
      Dst    : in out Surface;
      At_Row : Row_Index;
      At_Col : Col_Index)
   with Pre  => Natural (At_Row) - 1 + Natural (Src.Rows) <= Natural (Dst.Rows)
                  and then
                Natural (At_Col) - 1 + Natural (Src.Cols) <= Natural (Dst.Cols),
        Post => --  The rectangle now holds the source, cell for cell.
                (for all R in Row_Index range 1 .. Src.Rows =>
                   (for all C in Col_Index range 1 .. Src.Cols =>
                      Get (Dst, At_Row + R - 1, At_Col + C - 1)
                        = Get (Src, R, C)))
                --  Frame condition: every cell outside the rectangle is
                --  unchanged, mirroring the single-cell mutator's clause.
                and then
                  (for all R in Row_Index range 1 .. Dst.Rows =>
                     (for all C in Col_Index range 1 .. Dst.Cols =>
                        (if R < At_Row
                           or else
                             Natural (R) >= Natural (At_Row) + Natural (Src.Rows)
                           or else C < At_Col
                           or else
                             Natural (C) >= Natural (At_Col) + Natural (Src.Cols)
                         then Get (Dst, R, C) = Get (Dst'Old, R, C))));

private

   type Cell_Grid is array (Row_Index range <>, Col_Index range <>) of Cell;

   type Surface (Rows : Row_Count; Cols : Col_Count) is record
      Cells : Cell_Grid (1 .. Rows, 1 .. Cols);
   end record;

   function Get (S : Surface; R : Row_Index; C : Col_Index) return Cell
   is (S.Cells (R, C));

end Tui.Surface;
