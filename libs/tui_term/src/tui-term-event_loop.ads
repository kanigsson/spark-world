--  Tui.Term.Event_Loop — the optional "just run it" convenience.
--
--  Everything a full-screen app needs is already in the sibling packages: enter
--  raw/alt mode (Mode), read keys (Input), watch for resize/quit (Signals),
--  paint a surface (Output). A host is free to wire them itself and own its own
--  loop. This package is the batteries-included alternative: hand it two
--  callbacks and it runs the whole cycle.
--
--  What Run does, in order, forever until told to stop:
--    * enter raw mode + alternate screen (a Mode.Session — so the terminal is
--      ALWAYS restored on the way out, including on exception);
--    * size a back-buffer Surface to the terminal and call Paint to fill it;
--    * blit it, then loop: read a key (Input), let On_Key react, and on any
--      change repaint by DIFFING against the previous frame and emitting only
--      the cells that moved;
--    * on SIGWINCH, re-query the size, rebuild the buffers, full-repaint;
--    * on On_Key asking to quit, a SIGINT/SIGTERM, or stdin closing, return.
--
--  Named Event_Loop, not the roadmap's "Loop", because "loop" is a reserved
--  word.

with Tui.Surface;
with Tui.Input;

package Tui.Term.Event_Loop is

   --  Fill the frame. S arrives blanked and sized to the current terminal; read
   --  S.Rows / S.Cols for the geometry and Set cells into it. Called for the
   --  first frame, after every resize, and whenever On_Key reports a change.
   type Painter is access procedure (S : in out Tui.Surface.Surface);

   --  React to one key. Set Quit => True to leave the loop; set Dirty => True
   --  when the key changed what should be on screen (asks for a repaint).
   type Key_Handler is
     access procedure
       (Event : Tui.Input.Key_Event; Dirty : out Boolean; Quit : out Boolean);

   --  Run the loop to completion. A no-op (returns at once) when stdin/stdout is
   --  not a terminal. Restores the terminal unconditionally before returning.
   --  Mouse asks the terminal to report mouse activity, so On_Key also sees
   --  the mouse event kinds, including button motion (at the cost of native
   --  text selection; see Mode).
   procedure Run
     (Paint : Painter; On_Key : Key_Handler; Mouse : Boolean := False);

end Tui.Term.Event_Loop;
