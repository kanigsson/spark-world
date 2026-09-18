--  Tui.Term.Mode — own the terminal's mode, and ALWAYS hand it back.
--
--  A Session is a controlled (RAII) object. Declaring one switches the terminal
--  into the state a full-screen TUI needs — raw input (no line buffering, no
--  echo, no signal/flow keys), the alternate screen, hidden cursor — and, the
--  whole point, its Finalize restores every bit of that on the way out: normal
--  scope exit, an unhandled exception, anything that unwinds the stack. The
--  terminal is never left wedged.
--
--    declare
--       Term : Tui.Term.Mode.Session;        --  raw + alt-screen now in effect
--    begin
--       ... draw, read keys, resize ...
--    end;                                     --  cooked mode + main screen back
--
--  Raw mode is built with the libc cfmakeraw recipe (so e.g. ISIG is off — a
--  Ctrl-C arrives as the byte 0x03, a normal key event, not a signal). External
--  termination (kill, SIGTERM) is the job of Tui.Term.Signals, which turns it
--  into an orderly exit so this Finalize still runs.
--
--  If stdin/stdout is not a terminal (a pipe, a file), a Session does nothing
--  and reports Active = False; the program runs, it just is not driving a tty.

private with Ada.Finalization;
private with Interfaces.C;

package Tui.Term.Mode is

   type Session is tagged limited private;

   --  True when this Session actually put a terminal into raw/alt-screen mode
   --  (i.e. stdin and stdout were ttys). False is not an error — it just means
   --  there is nothing to drive, so a host should skip painting.
   function Active (S : Session) return Boolean;

   --  Ask the terminal to report mouse activity (presses, releases, button
   --  motion and wheel) as
   --  SGR escape sequences on stdin, which the input decoder turns into mouse
   --  events. Opt-in, because it has a price: the terminal stops doing native
   --  text selection while reporting is on (users hold Shift to get it back).
   --  A no-op on an inactive Session; Finalize undoes it like everything else.
   procedure Enable_Mouse (S : in out Session);

   --  The terminal's current size in cells, queried from the kernel
   --  (TIOCGWINSZ) on the given descriptor. Size.Rows/Cols are 0 when the
   --  query fails or the descriptor is not a tty (see Tui.Term.Is_Known).
   --  Independent of any Session, so a resize handler can call it freely.
   function Get_Size (FD : File_Descriptor := Stdout_FD) return Size;

private

   --  Opaque storage for a C `struct termios` (60 bytes on Linux/x86-64). Kept
   --  as machine words rather than bytes so the buffer is word-aligned, which
   --  the libc calls expect; generously oversized against ABI drift.
   type Termios_Blob is array (1 .. 16) of Interfaces.C.unsigned;

   type Session is new Ada.Finalization.Limited_Controlled with record
      Is_Active : Boolean := False;
      Mouse_On  : Boolean := False;
      Saved     : Termios_Blob := (others => 0);
   end record;

   overriding
   procedure Initialize (S : in out Session);
   overriding
   procedure Finalize (S : in out Session);

   function Active (S : Session) return Boolean
   is (S.Is_Active);

end Tui.Term.Mode;
