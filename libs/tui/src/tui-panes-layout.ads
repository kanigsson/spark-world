--  Tui.Panes.Layout — a row of panes across the terminal width, and where a
--  screen position lands in it.
--
--  A pane asks for a share of the width (Weight), refuses to be squeezed
--  below Min_Cols, and says how willingly it gives up its place when the
--  terminal is too narrow for everyone (Priority). Separators are the single
--  columns between adjacent panes; a host paints them or leaves them blank.
--
--  Layout is strictly column-oriented: one row of panes, no nesting and no
--  vertical splits, because that is what the hosts have. Per-pane title rows
--  are not modelled either — a title is content the host paints into its own
--  pane surface. Rows the host reserves for chrome are described to Locate
--  as a first content row and a content height.

with Tui.Surface;

package Tui.Panes.Layout with SPARK_Mode => On is

   --  Screen extents. Bounded by the surface's own limit so that every sum
   --  of a start column and a width is provably in range.
   subtype Screen_Cols is Natural range 0 .. Natural (Tui.Surface.Max_Extent);

   --  The width of the gap between two adjacent panes: one column, or none.
   subtype Separator_Cols is Natural range 0 .. 1;

   --  A pane's floor, bounded for the same reason: a whole row of minima
   --  still fits in a Natural.
   subtype Pane_Min_Cols is Positive range 1 .. Natural (Tui.Surface.Max_Extent);

   type Pane_Spec is record
      Weight   : Weight_Percent := 0;   --  share of the terminal width
      Min_Cols : Pane_Min_Cols  := 1;   --  never painted narrower than this
      Priority : Natural        := 0;   --  higher gives up its place first
   end record;

   type Specs_Array is array (Pane_Index range <>) of Pane_Spec;

   --  Where one pane was placed. Start_Col is a 1-based screen column; a
   --  pane that did not fit is not shown, and says so with a zero width.
   type Placement is record
      Start_Col : Screen_Cols := 0;
      Cols      : Screen_Cols := 0;
   end record;

   type Placement_Array is array (Pane_Index range <>) of Placement;

   function Shown (P : Placement) return Boolean is (P.Cols > 0);

   --  Which pane gives up its place when the panes cannot all fit.
   --
   --  Drop_By_Priority keeps the panes the host declared least disposable,
   --  whatever has the keyboard; a host that uses it must then rescue focus
   --  onto a pane that survived (see Rescue_Focus). Keep_Focused instead
   --  protects the focused pane, which is what a host wants when narrowing
   --  the terminal should show you what you were looking at.
   type Drop_Rule is (Drop_By_Priority, Keep_Focused);

   ---------------------------------------------------------------------------
   --  The properties Compute establishes. They are what makes a composite
   --  paint unable to overflow the screen surface, so they are stated rather
   --  than left to the reader of the body.
   ---------------------------------------------------------------------------

   --  Shown panes run left to right, never overlap, and never reach past the
   --  terminal's last column.
   function Disjoint_And_Ordered
     (P : Placement_Array; Total : Natural) return Boolean
   is
     ((for all I in P'Range =>
         (Shown (P (I))) = (P (I).Start_Col > 0))
      and then (for all I in P'Range =>
                  (if Shown (P (I))
                   then P (I).Start_Col + P (I).Cols - 1 <= Total))
      and then (for all I in P'Range =>
                  (for all J in P'Range =>
                     (if I < J and then Shown (P (I)) and then Shown (P (J))
                      then P (I).Start_Col + P (I).Cols <= P (J).Start_Col))));

   function Any_Shown (P : Placement_Array) return Boolean is
     (for some I in P'Range => Shown (P (I)));

   --  The shown panes and the separators between them cover the width with
   --  nothing left over: the leftmost starts at column 1, each next one
   --  begins exactly Sep columns past its predecessor's end, and the
   --  rightmost ends on the terminal's last column.
   function Covers_Exactly
     (P : Placement_Array; Total : Natural; Sep : Separator_Cols)
      return Boolean
   is
     ((for all I in P'Range =>
         (if Shown (P (I))
            and then (for all J in P'Range =>
                        (if J < I then not Shown (P (J))))
          then P (I).Start_Col = 1))
      and then (for all I in P'Range =>
                  (if Shown (P (I))
                     and then (for all J in P'Range =>
                                 (if J > I then not Shown (P (J))))
                   then P (I).Start_Col + P (I).Cols - 1 = Total))
      and then (for all I in P'Range =>
                  (for all J in P'Range =>
                     (if I < J and then Shown (P (I)) and then Shown (P (J))
                        and then (for all K in P'Range =>
                                    (if K > I and then K < J
                                     then not Shown (P (K))))
                      then P (J).Start_Col
                             = P (I).Start_Col + P (I).Cols + Sep))));

   ---------------------------------------------------------------------------

   --  Place the panes across Total_Cols. Maximized gives the whole width to
   --  the focused pane; otherwise every pane that fits takes its weighted
   --  share of the width, clamped so that no shown pane falls below its
   --  minimum and the rightmost absorbs the rounding.
   procedure Compute
     (Specs      : Specs_Array;
      Total_Cols : Tui.Surface.Col_Count;
      Focused    : Pane_Index;
      Maximized  : Boolean;
      Separators : Boolean;
      Rule       : Drop_Rule;
      Result     : out Placement_Array)
   with Global => null,
        Pre    => Specs'Length > 0
                  and then Result'First = Specs'First
                  and then Result'Last = Specs'Last
                  and then Focused in Specs'Range,
        Post   =>
          Disjoint_And_Ordered (Result, Natural (Total_Cols))
          and then Covers_Exactly
                     (Result, Natural (Total_Cols),
                      (if Separators then 1 else 0))
          and then (Any_Shown (Result) = (Natural (Total_Cols) > 0));

   --  A focus that survived the layout: the focused pane when it is shown,
   --  otherwise the leftmost shown pane. Hosts using Drop_By_Priority call
   --  this after Compute so the keyboard never addresses an invisible pane.
   function Rescue_Focus
     (P : Placement_Array; Focused : Pane_Index) return Pane_Index
   with Global => null,
        Pre    => P'Length > 0 and then Focused in P'Range,
        Post   => Rescue_Focus'Result in P'Range
                  and then (if Shown (P (Focused))
                            then Rescue_Focus'Result = Focused);

   ---------------------------------------------------------------------------
   --  Hit-testing
   ---------------------------------------------------------------------------

   --  Where a screen position lands. Local coordinates are the pane's own
   --  frame: row 1 is the pane's first content row, column 1 its first
   --  column. Returning them is what keeps "which pane is to my left"
   --  arithmetic out of every caller.
   type Hit_Kind is (Pane_Hit, Separator_Hit, Nowhere);

   type Hit is record
      Kind      : Hit_Kind   := Nowhere;
      --  Pane_Hit: the pane hit. Separator_Hit: the pane to the separator's
      --  left, which is the boundary a drag would move.
      Pane      : Pane_Index  := 1;
      Local_Row : Screen_Cols := 0;
      Local_Col : Screen_Cols := 0;
   end record;

   --  Col and Row are 1-based screen coordinates as a mouse report gives
   --  them; 0 means the report carried no position. First_Row is the screen
   --  row of every pane's first content row, and Content_Rows how many rows
   --  the panes occupy below it.
   function Locate
     (P            : Placement_Array;
      First_Row    : Positive;
      Content_Rows : Natural;
      Col, Row     : Natural) return Hit
   with Global => null,
        Pre    => P'Length > 0,
        Post   => Locate'Result.Pane in P'Range
                  and then (if Locate'Result.Kind = Pane_Hit
                            then Locate'Result.Local_Row
                                   in 1 .. Content_Rows
                              and then Locate'Result.Local_Col
                                   in 1 .. P (Locate'Result.Pane).Cols)
                  and then (if Locate'Result.Kind = Separator_Hit
                            then Shown (P (Locate'Result.Pane)));

   ---------------------------------------------------------------------------
   --  Adjusting a two-pane split
   ---------------------------------------------------------------------------

   --  A weight a host lets the user move, by key or by dragging a separator.
   --  The bounds keep both sides of a split useful whatever the terminal
   --  width; Min_Cols then does the rest.
   subtype Split_Percentage is Weight_Percent range 25 .. 75;
   Split_Step : constant := 5;

   function Adjust
     (Current : Split_Percentage;
      Grow    : Boolean) return Split_Percentage
   with Global => null;

   --  Convert a dragged separator column to a bounded percentage. Column is
   --  a screen coordinate and may lie beyond Total in a malformed mouse
   --  report; clamping makes that harmless.
   function Split_At
     (Column : Natural;
      Total  : Tui.Surface.Col_Count) return Split_Percentage
   with Global => null,
        Pre    => Natural (Total) > 0;

end Tui.Panes.Layout;
