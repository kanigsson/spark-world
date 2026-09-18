--  Tui.Term.Input — read the terminal, hand back decoded key events.
--
--  This is the read half of the driver. It pulls raw bytes from stdin and pumps
--  them through a Tui.Input.Decoder (the proved, OS-free state machine), so the
--  host deals in typed Key_Events, never bytes. The decoder is the caller's:
--  the host owns one and passes it in, keeping this package stateless about
--  *interpretation* (it buffers only the raw bytes read but not yet decoded).
--
--  The lone-ESC problem. A bare ESC is ambiguous — the Escape key, or the start
--  of an escape sequence whose tail has not arrived? The decoder never guesses
--  on a clock; resolving it is exactly the timing this layer supplies. When a
--  read leaves the decoder mid-sequence and nothing more is immediately
--  available, Next waits only a short window (Default_Esc_Timeout_Ms) and then
--  Flushes — turning a stranded ESC into the Escape key without stalling.
--
--  Note: named Tui.Term.Input rather than the roadmap's "In" because "in" is a
--  reserved word. It is distinct from Tui.Input (the decoder); this just feeds
--  one from the real terminal.

with Tui.Input;

package Tui.Term.Input
  with SPARK_Mode => On
is

   --  How long (ms) to wait for an escape sequence's continuation before
   --  deciding a pending ESC was the Escape key. Long enough for a paste/keymap
   --  burst, short enough to feel instant.
   Default_Esc_Timeout_Ms : constant := 40;

   type Read_Status is
     (Got_Event,      --  Event holds a decoded key
      Timed_Out,      --  the timeout elapsed (or a signal interrupted the wait)
      End_Of_Input);  --  stdin reached end-of-file (pipe closed)

   --  Produce the next key event, decoding as many raw bytes as it takes.
   --
   --  Timeout is in milliseconds: a negative value blocks until a key arrives
   --  (subject to the ESC window above) or a signal interrupts the wait; 0 polls
   --  without blocking; a positive value bounds the wait. A signal (SIGWINCH,
   --  etc.) interrupting the wait surfaces as Timed_Out, so a host loop returns
   --  to check Tui.Term.Signals and then calls Next again.
   procedure Next
     (D       : in out Tui.Input.Decoder;
      Event   : out Tui.Input.Key_Event;
      Status  : out Read_Status;
      Timeout : Integer := -1);

end Tui.Term.Input;
