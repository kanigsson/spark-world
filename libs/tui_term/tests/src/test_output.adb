--  Terminal-free tests for Tui.Term.Output. The pty demo proves the live path;
--  these pin the exact bytes — SGR shape and the colour-depth downgrades — by
--  redirecting fd 1 through an OS pipe, running the output routines, and reading
--  back what was written. No terminal involved, deterministic, CI-friendly.

with Ada.Text_IO;       use Ada.Text_IO;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Test_Checks;       use Test_Checks;
with System;
with Interfaces.C;      use Interfaces.C;
with Tui.Surface;       use Tui.Surface;
with Tui.Surface.Diff;
with Tui.Term.Output;   use Tui.Term.Output;

procedure Test_Output is

   ESC : constant Character := Character'Val (16#1B#);

   function Contains (Haystack, Needle : String) return Boolean
   is (Index (Haystack, Needle) /= 0);

   ---------------------------------------------------------------------------
   --  Capture: redirect fd 1 to a pipe, then read back what was written
   ---------------------------------------------------------------------------

   function C_Pipe (Fds : System.Address) return int
   with Import, Convention => C, External_Name => "pipe";
   function C_Dup (Old_Fd : int) return int
   with Import, Convention => C, External_Name => "dup";
   function C_Dup2 (Old_Fd, New_Fd : int) return int
   with Import, Convention => C, External_Name => "dup2";
   function C_Close (Fd : int) return int
   with Import, Convention => C, External_Name => "close";
   function C_Read (Fd : int; Buf : System.Address; Count : size_t) return long
   with Import, Convention => C, External_Name => "read";

   type Fd_Pair is array (0 .. 1) of aliased int with Convention => C;

   Saved_Stdout : int;
   Pipe_Fds     : aliased Fd_Pair;

   procedure Begin_Capture is
      Ignore : int;
   begin
      Saved_Stdout := C_Dup (1);
      Ignore := C_Pipe (Pipe_Fds'Address);
      Ignore := C_Dup2 (Pipe_Fds (1), 1);   --  fd 1 -> pipe write end
      Ignore := C_Close (Pipe_Fds (1));      --  fd 1 is now the only writer
      pragma Unreferenced (Ignore);
   end Begin_Capture;

   function End_Capture return String is
      Ignore : int;
      Buf    : aliased String (1 .. 8192);
      N      : long;
      Result : String (1 .. 0) := "";
   begin
      --  Restoring stdout also drops fd 1's reference to the pipe writer, so the
      --  read below sees EOF after the captured bytes.
      Ignore := C_Dup2 (Saved_Stdout, 1);
      Ignore := C_Close (Saved_Stdout);
      pragma Unreferenced (Ignore);
      N := C_Read (Pipe_Fds (0), Buf'Address, Buf'Length);
      declare
         Got   : constant String :=
           (if N > 0 then Buf (1 .. Natural (N)) else Result);
         Dummy : int;
      begin
         Dummy := C_Close (Pipe_Fds (0));
         pragma Unreferenced (Dummy);
         return Got;
      end;
   end End_Capture;

   ---------------------------------------------------------------------------
   --  A 1x1 surface holding one cell, blitted under a given depth
   ---------------------------------------------------------------------------

   function Blit_One (C : Cell; Depth : Color_Depth) return String is
      S : Surface := Blank (1, 1);
   begin
      Set_Color_Depth (Depth);
      Set (S, 1, 1, C);
      Begin_Capture;
      Blit (S);
      return End_Capture;
   end Blit_One;

   Red_RGB : constant Color := (Kind => RGB, R => 255, G => 0, B => 0);

begin
   Start ("test_output", Echo_Passes => True);
   ------------------------------------------------------------------ cursor
   Begin_Capture;
   Move_To (2, 3);
   Check (End_Capture = ESC & "[2;3H", "Move_To emits CUP row;col H");

   Begin_Capture;
   New_Frame;
   Check
     (End_Capture = ESC & "[2J" & ESC & "[H", "New_Frame clears and homes");

   ------------------------------------------------------------------ truecolor
   declare
      Out_S : constant String :=
        Blit_One
          ((Glyph      => 'X',
            Foreground => (Kind => RGB, R => 10, G => 20, B => 30),
            others     => <>),
           Truecolor);
   begin
      Check (Contains (Out_S, "38;2;10;20;30"), "Truecolor fg -> 38;2;r;g;b");
      Check (Contains (Out_S, "X"), "glyph emitted");
      Check
        (Out_S (Out_S'Last - 2 .. Out_S'Last) = ESC & "[0m"
         or else Contains (Out_S, ESC & "[0m"),
         "frame ends with SGR reset");
   end;

   --  Palette index passes through unchanged at truecolor.
   Check
     (Contains
        (Blit_One
           ((Glyph      => ' ',
             Foreground => (Kind => Palette, Index => 200),
             others     => <>),
            Truecolor),
         "38;5;200"),
      "Palette fg -> 38;5;idx");

   ------------------------------------------------------------------ 256 downgrade
   --  Pure red maps to the top of the 6x6x6 cube: 16 + 36*5 = 196.
   Check
     (Contains
        (Blit_One
           ((Glyph => ' ', Foreground => Red_RGB, others => <>), Palette_256),
         "38;5;196"),
      "Palette_256 downgrades RGB red -> 38;5;196");

   ------------------------------------------------------------------ 16 downgrade
   --  Pure red is base colour 9 (bright red) -> fg code 91.
   Check
     (Contains
        (Blit_One
           ((Glyph => ' ', Foreground => Red_RGB, others => <>), Basic_16),
         ";91"),
      "Basic_16 downgrades RGB red -> 91");

   ------------------------------------------------------------------ monochrome
   declare
      Out_S : constant String :=
        Blit_One
          ((Glyph      => ' ',
            Foreground => Red_RGB,
            Attributes => (Bold => True, others => False),
            others     => <>),
           Monochrome);
   begin
      Check (not Contains (Out_S, "38;"), "Monochrome emits no colour");
      Check
        (Contains (Out_S, ESC & "[0;1m"),
         "Monochrome keeps attributes (bold)");
   end;

   ------------------------------------------------------------------ diff Apply
   Set_Color_Depth (Truecolor);
   declare
      Changes : constant Tui.Surface.Diff.Change_Array (1 .. 1) :=
        (1 =>
           (Row    => 4,
            Column => 7,
            Value  => (Glyph => 'Z', Foreground => Red_RGB, others => <>)));
   begin
      Begin_Capture;
      Apply (Changes, 1);
      declare
         Got : constant String := End_Capture;
      begin
         Check
           (Contains (Got, ESC & "[4;7H"), "Apply positions the changed cell");
         Check (Contains (Got, "Z"), "Apply emits the new glyph");
      end;
   end;

   Report;
end Test_Output;
