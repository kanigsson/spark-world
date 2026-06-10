--  Tui.Term — the terminal driver: the ONE crate that talks to the OS.
--
--  Everything below this package — raw mode (termios), ANSI/SGR output, key
--  input, window-size and signal handling — is confined here, behind a thin
--  edge. The engine it serves (Tui.Pager) and the data it carries (Tui.Surface,
--  Tui.Input events) stay pure and provable. Within this crate the same line
--  is drawn once more: syscalls, controlled types and interrupt handlers are
--  SPARK_Mode Off, while the byte-level work around them — key decoding,
--  escape/SGR assembly — is proved SPARK behind the syscall shims' contracts.
--
--  Built AFTER the engine, on purpose: its shape is driven by what the engine
--  actually needs to display and read, not guessed up front. Sequences are
--  hardcoded ANSI/xterm (terminfo is deliberately skipped — see the roadmap).
--
--  This parent holds only the vocabulary the children share; it performs no I/O
--  itself. Three child names depart from the roadmap's sketch because "Out",
--  "In" and "Loop" are reserved words: output is Tui.Term.Output, the input
--  reader is Tui.Term.Input, and the convenience loop is Tui.Term.Event_Loop.

package Tui.Term is

   --  A POSIX file descriptor. The driver works on whichever descriptors a host
   --  hands it; the standard three have names so callers need not remember 0/1/2.
   subtype File_Descriptor is Integer;

   Stdin_FD  : constant File_Descriptor := 0;
   Stdout_FD : constant File_Descriptor := 1;
   Stderr_FD : constant File_Descriptor := 2;

   --  A terminal's size in character cells, as reported by the kernel. Zero in
   --  either field means "unknown" — e.g. when the descriptor is not a tty, or
   --  the size query failed; a host treats that as "do not paint yet".
   type Size is record
      Rows : Natural := 0;
      Cols : Natural := 0;
   end record;

   function Is_Known (S : Size) return Boolean is (S.Rows > 0 and then S.Cols > 0);

end Tui.Term;
