--  Tui.Term.Signals — asynchronous OS events, made safe to observe.
--
--  Two things can happen to a full-screen program from outside its own input
--  stream, and a TUI must notice both:
--
--    * SIGWINCH — the window was resized. The new size must be re-queried and
--      the frame repainted.
--    * SIGTERM — someone is asking the process to stop (a `kill`). We catch it
--      so the exit is orderly and the terminal is restored. SIGINT is NOT
--      caught: this GNAT runtime reserves it, and in raw mode (ISIG off) an
--      interactive Ctrl-C is an ordinary 0x03 key event, not a signal — so the
--      host handles "Ctrl-C means quit" as a key, not here.
--
--  A signal can arrive at any instant, so the handlers do the minimum: they set
--  a flag inside a protected object (the only safe thing to touch from an
--  interrupt context) and return. The host's event loop polls these flags at a
--  safe point and acts — re-querying the size, or unwinding cleanly so the
--  Tui.Term.Mode.Session's Finalize restores the terminal. That last part is
--  why we catch SIGTERM at all: the default action would kill the process
--  outright, skipping finalization and leaving the terminal wedged.
--
--  Merely with-ing this package installs the handlers (they attach as the body
--  elaborates); Install is an explicit, idempotent way to say so at a call site.

package Tui.Term.Signals is

   --  Force/handlers-are-installed marker. With-ing the package already attaches
   --  them; calling this documents the dependency and guarantees elaboration.
   procedure Install;

   --  Read-and-clear: returns True at most once per resize burst, so the loop
   --  re-queries the size exactly when it changed and not on every tick.
   function Resize_Pending return Boolean;

   --  Latched: becomes True on the first SIGTERM and stays True, so a host that
   --  misses one poll still sees the request on the next.
   function Quit_Requested return Boolean;

end Tui.Term.Signals;
