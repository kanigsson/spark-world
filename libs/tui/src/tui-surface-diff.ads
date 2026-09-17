--  Tui.Surface.Diff — minimal change set between two frames.
--
--  A driver keeps the surface it last painted ("previous") and the one the
--  producer just filled ("current"). Rather than repaint the whole screen, it
--  asks for the set of cells that actually changed and emits only those — the
--  same idea ncurses calls doupdate. This is the piece that makes a TUI feel
--  instant over a slow link, and it is pure logic over two grids, so it is the
--  natural first proof target of the ecosystem.

package Tui.Surface.Diff with SPARK_Mode => On is

   type Cell_Change is record
      Row    : Row_Index;
      Column : Col_Index;
      Value  : Cell;       --  the NEW contents at (Row, Column)
   end record;

   type Change_Array is array (Positive range <>) of Cell_Change;

   function Same_Geometry (A, B : Surface) return Boolean
   is (A.Rows = B.Rows and then A.Cols = B.Cols);

   function Cell_Count (S : Surface) return Natural
   is (Natural (S.Rows) * Natural (S.Cols));
   --  Total cells. Within Natural because each dimension <= Max_Extent, so the
   --  product is at most 4096 * 4096 = 16_777_216.

   --  Compute the cells that differ between Previous and Current.
   --
   --  The caller supplies the output buffer; the diff allocates nothing. The
   --  buffer must be able to hold the worst case (every cell changed), which
   --  is why the precondition demands Changes'Length >= Cell_Count.
   procedure Compute
     (Previous, Current : Surface;
      Changes           : out Change_Array;
      Count             : out Natural)
   with
     Pre  => Same_Geometry (Previous, Current)
             and then Changes'First = 1
             and then Changes'Length >= Cell_Count (Current),
     Post => Count <= Changes'Length
             --  SOUNDNESS: every reported change is a genuine difference and
             --  carries Current's value. This part proves today.
             and then
               (for all I in 1 .. Count =>
                  In_Bounds (Current, Changes (I).Row, Changes (I).Column)
                  and then
                    Changes (I).Value
                      = Get (Current, Changes (I).Row, Changes (I).Column)
                  and then
                    Get (Previous, Changes (I).Row, Changes (I).Column)
                      /= Get (Current, Changes (I).Row, Changes (I).Column));

   --  COMPLETENESS and UNIQUENESS — every differing cell appears exactly once
   --  — are the two further properties that make this a *correct* minimal
   --  diff rather than merely a *sound* one. They are stated as the ghost
   --  lemma below and are the next proof milestone; establishing them will
   --  likely need a small ghost model of "cells seen so far". Kept separate so
   --  the soundness contract above can be relied on in the meantime.
   function Is_Complete
     (Previous, Current : Surface; Changes : Change_Array; Count : Natural)
      return Boolean
   is (for all R in Row_Index range 1 .. Current.Rows =>
         (for all C in Col_Index range 1 .. Current.Cols =>
            (if Get (Previous, R, C) /= Get (Current, R, C)
             then (for some I in 1 .. Count =>
                     Changes (I).Row = R and then Changes (I).Column = C))))
   with Ghost,
        Pre => Same_Geometry (Previous, Current)
               and then Changes'First = 1
               and then Count <= Changes'Length;

end Tui.Surface.Diff;
