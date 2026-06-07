--  Tui.Term.Output — turn a Surface (or a frame Diff) into bytes on the wire.
--
--  This is the "rendering is data, becomes effect HERE" boundary: a producer
--  filled a Tui.Surface with the intent (glyphs, colours, attributes); this
--  package is where that intent finally becomes ANSI/SGR escape sequences sent
--  to the terminal. Nothing above it emits an escape; nothing below it knows
--  what a cell is.
--
--  Two ways to paint:
--    * Blit  — repaint a whole surface (first frame, or after a resize/clear).
--    * Apply — emit only the cells a Tui.Surface.Diff reported as changed; the
--      "doupdate" fast path that keeps redraws cheap over a slow link.
--
--  Colour downgrade. A surface always records the producer's full intent (24-bit
--  truecolour if it likes); this package downgrades to what the target terminal
--  can actually show, per the configured Color_Depth. Default is Truecolor
--  (modern xterm-likes); set a lower depth for older terminals.
--
--  v1 limitation (documented, shared with the rest of the stack): a wide (CJK)
--  glyph is emitted as a single cell. Surfaces currently store one code point
--  per cell, so column drift from a double-width glyph is possible within a row;
--  Blit re-homes the cursor every row and Apply positions every change
--  absolutely, which bounds the effect. Full wide-glyph cells are future work.

with Tui.Surface;
with Tui.Surface.Diff;

package Tui.Term.Output is

   --  How much colour the target terminal can render. The surface keeps full
   --  intent regardless; this only governs what bytes go out.
   type Color_Depth is
     (Truecolor,    --  24-bit (ESC[38;2;r;g;b)
      Palette_256,  --  xterm 256-colour cube + grays
      Basic_16,     --  the 8 + 8 bright ANSI colours
      Monochrome);  --  attributes only, no colour

   procedure Set_Color_Depth (D : Color_Depth);
   function Color_Depth_Setting return Color_Depth;

   ---------------------------------------------------------------------------
   --  Low-level primitives (a host rarely needs these directly)
   ---------------------------------------------------------------------------

   --  Write raw bytes to stdout, retrying short writes; never partial on return.
   procedure Put (Text : String);

   --  Clear the screen and home the cursor — the start of a from-scratch frame.
   procedure New_Frame;

   --  Move the cursor to a 1-based (Row, Col).
   procedure Move_To (Row, Col : Positive);

   procedure Hide_Cursor;
   procedure Show_Cursor;

   --  Reset all SGR attributes to the terminal default.
   procedure Reset_Style;

   ---------------------------------------------------------------------------
   --  Surface output
   ---------------------------------------------------------------------------

   --  Repaint the whole surface. Positions the cursor at the top-left and
   --  draws every cell, minimising SGR churn by only re-emitting style when it
   --  changes. Leaves the SGR state reset.
   procedure Blit (S : Tui.Surface.Surface);

   --  Emit only the changed cells from a diff (see Tui.Surface.Diff.Compute).
   --  Each change is positioned absolutely, so a stale previous frame is not
   --  required to be on screen contiguously. Leaves the SGR state reset.
   procedure Apply
     (Changes : Tui.Surface.Diff.Change_Array;
      Count   : Natural);

end Tui.Term.Output;
