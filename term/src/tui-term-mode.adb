with System;
with Interfaces.C;             use Interfaces.C;
with Tui.Term.Output;

package body Tui.Term.Mode is

   ESC : constant Character := Character'Val (16#1B#);

   --  Platform constants (Linux/x86-64). Hardcoded with the rest of the ANSI
   --  assumptions; revisit only if a target misbehaves.
   TCSAFLUSH  : constant := 2;
   TIOCGWINSZ : constant := 16#5413#;

   ---------------------------------------------------------------------------
   --  libc bindings — the syscall edge of this package.
   --
   --  This unit is SPARK_Mode => Off (it owns a controlled type), so the
   --  contracts below are not consumed by the prover the way Tui.Term.Sys's are;
   --  they make the OS-edge assumptions explicit anyway — Global => null states
   --  these calls touch no Ada global state, and isatty's Post pins its result to
   --  the {0,1} the rest of this body branches on (checked under -gnata).
   ---------------------------------------------------------------------------

   function C_Isatty (FD : int) return int
     with Import, Convention => C, External_Name => "isatty",
          Global => null,
          Post   => C_Isatty'Result in 0 .. 1;

   function C_Tcgetattr (FD : int; T : System.Address) return int
     with Import, Convention => C, External_Name => "tcgetattr",
          Global => null;

   function C_Tcsetattr (FD : int; Optional_Actions : int; T : System.Address)
      return int
     with Import, Convention => C, External_Name => "tcsetattr",
          Global => null;

   procedure C_Cfmakeraw (T : System.Address)
     with Import, Convention => C, External_Name => "cfmakeraw",
          Global => null;

   function C_Ioctl (FD : int; Request : unsigned_long; Arg : System.Address)
      return int
     with Import, Convention => C, External_Name => "ioctl",
          Global => null;

   --  The kernel's struct winsize: rows, cols, then pixel dims we ignore.
   type Winsize is record
      Ws_Row    : unsigned_short := 0;
      Ws_Col    : unsigned_short := 0;
      Ws_XPixel : unsigned_short := 0;
      Ws_YPixel : unsigned_short := 0;
   end record
     with Convention => C;

   ---------------------------------------------------------------------------
   --  Size
   ---------------------------------------------------------------------------

   function Get_Size (FD : File_Descriptor := Stdout_FD) return Size is
      W : aliased Winsize;
   begin
      if C_Ioctl (int (FD), TIOCGWINSZ, W'Address) = 0 then
         return (Rows => Natural (W.Ws_Row), Cols => Natural (W.Ws_Col));
      else
         return (Rows => 0, Cols => 0);
      end if;
   end Get_Size;

   ---------------------------------------------------------------------------
   --  Enter on construction, restore on destruction
   ---------------------------------------------------------------------------

   overriding procedure Initialize (S : in out Session) is
   begin
      --  Only drive a real terminal. A redirected stdin/stdout is left alone.
      if C_Isatty (int (Stdin_FD)) /= 1
        or else C_Isatty (int (Stdout_FD)) /= 1
      then
         S.Is_Active := False;
         return;
      end if;

      if C_Tcgetattr (int (Stdin_FD), S.Saved'Address) /= 0 then
         S.Is_Active := False;
         return;
      end if;

      --  Build a raw copy from the saved settings, leaving Saved pristine for
      --  the exact restore in Finalize.
      declare
         Raw : Termios_Blob := S.Saved;
      begin
         C_Cfmakeraw (Raw'Address);
         if C_Tcsetattr (int (Stdin_FD), TCSAFLUSH, Raw'Address) /= 0 then
            S.Is_Active := False;
            return;
         end if;
      end;

      S.Is_Active := True;

      --  Switch to the alternate screen, hide the cursor, start clean.
      Output.Put (ESC & "[?1049h");
      Output.Hide_Cursor;
      Output.New_Frame;
   end Initialize;

   ------------------
   -- Enable_Mouse --
   ------------------

   procedure Enable_Mouse (S : in out Session) is
   begin
      if not S.Is_Active or else S.Mouse_On then
         return;
      end if;
      S.Mouse_On := True;
      Output.Put (ESC & "[?1000h");   --  report button presses and releases
      Output.Put (ESC & "[?1006h");   --  ... encoded as SGR sequences
   end Enable_Mouse;

   overriding procedure Finalize (S : in out Session) is
   begin
      if not S.Is_Active then
         return;
      end if;
      S.Is_Active := False;   --  idempotent: a second Finalize is a no-op

      --  Undo in the reverse order, then hand the original mode back.
      if S.Mouse_On then
         S.Mouse_On := False;
         Output.Put (ESC & "[?1006l");
         Output.Put (ESC & "[?1000l");
      end if;
      Output.Reset_Style;
      Output.Show_Cursor;
      Output.Put (ESC & "[?1049l");
      if C_Tcsetattr (int (Stdin_FD), TCSAFLUSH, S.Saved'Address) /= 0 then
         null;   --  nothing useful to do if even the restore fails
      end if;
   end Finalize;

end Tui.Term.Mode;
