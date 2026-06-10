--  Tui.Term.Output — turn a Surface (or a frame Diff) into bytes on the wire.
--
--  This is the "rendering is data, becomes effect HERE" boundary: a producer
--  filled a Tui.Surface with the intent (glyphs, colours, attributes); this
--  package is where that intent finally becomes ANSI/SGR escape sequences sent
--  to the terminal. Nothing above it emits an escape; nothing below it knows
--  what a cell is.
--
--  Proved SPARK: escape assembly is pure data work — digits, SGR fragments,
--  UTF-8 bytes, a bounded staging buffer — so the whole package is
--  SPARK_Mode => On and verified, down to the partial-write loop over the
--  syscall shim. Frames of any size stream through the fixed staging buffer,
--  which flushes whenever the next piece might not fit.
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

package Tui.Term.Output with
  SPARK_Mode     => On,
  Abstract_State => Color_Config,
  Initializes    => Color_Config
is

   --  How much colour the target terminal can render. The surface keeps full
   --  intent regardless; this only governs what bytes go out.
   type Color_Depth is
     (Truecolor,    --  24-bit (ESC[38;2;r;g;b)
      Palette_256,  --  xterm 256-colour cube + grays
      Basic_16,     --  the 8 + 8 bright ANSI colours
      Monochrome);  --  attributes only, no colour

   procedure Set_Color_Depth (D : Color_Depth)
   with Global => (Output => Color_Config);

   function Color_Depth_Setting return Color_Depth
   with Global => (Input => Color_Config);

   ---------------------------------------------------------------------------
   --  Low-level primitives (a host rarely needs these directly)
   ---------------------------------------------------------------------------

   --  Write raw bytes to stdout, retrying short writes; never partial on return.
   procedure Put (Text : String)
   with Global => null;

   --  Clear the screen and home the cursor — the start of a from-scratch frame.
   procedure New_Frame
   with Global => null;

   --  Move the cursor to a 1-based (Row, Col), within the surface extents.
   procedure Move_To (Row, Col : Positive)
   with Global => null,
        Pre    => Row <= Tui.Surface.Max_Extent
                  and then Col <= Tui.Surface.Max_Extent;

   procedure Hide_Cursor
   with Global => null;

   procedure Show_Cursor
   with Global => null;

   --  Reset all SGR attributes to the terminal default.
   procedure Reset_Style
   with Global => null;

   ---------------------------------------------------------------------------
   --  Surface output
   ---------------------------------------------------------------------------

   --  Repaint the whole surface. Positions the cursor at the top-left and
   --  draws every cell, minimising SGR churn by only re-emitting style when it
   --  changes. Leaves the SGR state reset.
   procedure Blit (S : Tui.Surface.Surface)
   with Global => (Input => Color_Config);

   --  Emit only the changed cells from a diff (see Tui.Surface.Diff.Compute).
   --  Each change is positioned absolutely, so a stale previous frame is not
   --  required to be on screen contiguously. Leaves the SGR state reset.
   procedure Apply
     (Changes : Tui.Surface.Diff.Change_Array;
      Count   : Natural)
   with Global => (Input => Color_Config),
        Pre    => Count <= Changes'Length;

end Tui.Term.Output;
