with System;
with Interfaces.C;
with Ada.Strings.Unbounded;          use Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

package body Tui.Term.Output is

   package Enc renames Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

   ESC : constant Character := Character'Val (16#1B#);

   Depth : Color_Depth := Truecolor;

   ---------------------------------------------------------------------------
   --  Configuration
   ---------------------------------------------------------------------------

   procedure Set_Color_Depth (D : Color_Depth) is
   begin
      Depth := D;
   end Set_Color_Depth;

   function Color_Depth_Setting return Color_Depth is (Depth);

   ---------------------------------------------------------------------------
   --  Raw write (the single syscall in this package)
   ---------------------------------------------------------------------------

   function C_Write
     (FD    : Interfaces.C.int;
      Buf   : System.Address;
      Count : Interfaces.C.size_t) return Interfaces.C.long
   with Import, Convention => C, External_Name => "write";

   procedure Put (Text : String) is
      use type Interfaces.C.long;
      Offset    : Natural := 0;
      Remaining : Natural := Text'Length;
      N         : Interfaces.C.long;
   begin
      while Remaining > 0 loop
         N := C_Write
           (Interfaces.C.int (Stdout_FD),
            Text (Text'First + Offset)'Address,
            Interfaces.C.size_t (Remaining));
         exit when N <= 0;   --  error or closed pipe: give up rather than spin
         Offset    := Offset    + Natural (N);
         Remaining := Remaining - Natural (N);
      end loop;
   end Put;

   ---------------------------------------------------------------------------
   --  Small formatting helpers
   ---------------------------------------------------------------------------

   --  A non-negative integer with no leading space (Integer'Image inserts one).
   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Utf8 (G : Wide_Wide_Character) return String is
     (Enc.Encode ((1 => G)));

   ---------------------------------------------------------------------------
   --  Colour: a surface keeps full intent; here we downgrade to Depth
   ---------------------------------------------------------------------------

   subtype Ansi_16 is Natural range 0 .. 15;
   type RGB_Triple is record R, G, B : Tui.Surface.Component; end record;

   --  The conventional xterm RGB of the 16 base colours; used only to find a
   --  nearest match when downgrading, so the exact values are not critical.
   Base_16 : constant array (Ansi_16) of RGB_Triple :=
     (0  => (0, 0, 0),       1  => (205, 0, 0),    2  => (0, 205, 0),
      3  => (205, 205, 0),   4  => (0, 0, 238),    5  => (205, 0, 205),
      6  => (0, 205, 205),   7  => (229, 229, 229),
      8  => (127, 127, 127), 9  => (255, 0, 0),    10 => (0, 255, 0),
      11 => (255, 255, 0),   12 => (92, 92, 255),  13 => (255, 0, 255),
      14 => (0, 255, 255),   15 => (255, 255, 255));

   --  Map a 256-palette index to its approximate RGB (16 base, 6x6x6 cube,
   --  24-step gray ramp), so any palette colour can be re-downgraded further.
   function Pal_To_RGB (Index : Tui.Surface.Component) return RGB_Triple is
      Levels : constant array (0 .. 5) of Tui.Surface.Component :=
        (0, 95, 135, 175, 215, 255);
   begin
      if Index < 16 then
         return Base_16 (Ansi_16 (Index));
      elsif Index < 232 then
         declare
            N : constant Natural := Natural (Index) - 16;
         begin
            return (R => Levels ((N / 36) mod 6),
                    G => Levels ((N / 6) mod 6),
                    B => Levels (N mod 6));
         end;
      else
         declare
            Gray : constant Tui.Surface.Component := 8 + (Index - 232) * 10;
         begin
            return (Gray, Gray, Gray);
         end;
      end if;
   end Pal_To_RGB;

   function Dist (A, B : RGB_Triple) return Natural is
      DR : constant Integer := Integer (A.R) - Integer (B.R);
      DG : constant Integer := Integer (A.G) - Integer (B.G);
      DB : constant Integer := Integer (A.B) - Integer (B.B);
   begin
      return DR * DR + DG * DG + DB * DB;
   end Dist;

   function Nearest_16 (C : RGB_Triple) return Ansi_16 is
      Best   : Ansi_16 := 0;
      Best_D : Natural := Natural'Last;
   begin
      for I in Ansi_16 loop
         declare
            D : constant Natural := Dist (C, Base_16 (I));
         begin
            if D < Best_D then
               Best_D := D;
               Best   := I;
            end if;
         end;
      end loop;
      return Best;
   end Nearest_16;

   --  Quantise one channel to the 6-level cube (0,95,135,175,215,255).
   function Cube_Level (V : Tui.Surface.Component) return Natural is
   begin
      if V < 48 then return 0;
      elsif V < 115 then return 1;
      else return (Natural (V) - 35) / 40;
      end if;
   end Cube_Level;

   function Nearest_256 (C : RGB_Triple) return Natural is
     (16 + 36 * Cube_Level (C.R) + 6 * Cube_Level (C.G) + Cube_Level (C.B));

   --  SGR fragment selecting a colour, for the given role base codes:
   --    Foreground => (38, 30, 90);  Background => (48, 40, 100).
   function Color_SGR
     (C            : Tui.Surface.Color;
      Ext, Lo, Hi  : Natural) return String
   is
      use Tui.Surface;

      function As_16 (Idx : Ansi_16) return String is
        (if Idx < 8 then ";" & Img (Lo + Idx) else ";" & Img (Hi + (Idx - 8)));

      function To_RGB return RGB_Triple is
        (case C.Kind is
            when RGB     => (C.R, C.G, C.B),
            when Palette => Pal_To_RGB (C.Index),
            when Default => (0, 0, 0));   --  unreachable; Default handled below
   begin
      if C.Kind = Default or else Depth = Monochrome then
         return "";   --  the leading SGR "0" reset already restored the default
      end if;

      case Depth is
         when Monochrome =>
            return "";
         when Basic_16 =>
            return As_16 (Nearest_16 (To_RGB));
         when Palette_256 =>
            case C.Kind is
               when Palette => return ";" & Img (Ext) & ";5;" & Img (Natural (C.Index));
               when RGB     => return ";" & Img (Ext) & ";5;" & Img (Nearest_256 (To_RGB));
               when Default => return "";
            end case;
         when Truecolor =>
            case C.Kind is
               when Palette =>
                  return ";" & Img (Ext) & ";5;" & Img (Natural (C.Index));
               when RGB =>
                  return ";" & Img (Ext) & ";2;"
                    & Img (Natural (C.R)) & ";"
                    & Img (Natural (C.G)) & ";"
                    & Img (Natural (C.B));
               when Default =>
                  return "";
            end case;
      end case;
   end Color_SGR;

   --  A complete, absolute SGR for a cell: always leads with "0" (reset), then
   --  adds attributes and colours. Absolute form means no per-cell bookkeeping
   --  of "what to turn off" — and identical adjacent cells collapse to nothing
   --  because the caller compares the produced string to the last one emitted.
   function Cell_SGR (C : Tui.Surface.Cell) return String is
      P : Unbounded_String := To_Unbounded_String ("0");
   begin
      if C.Attributes.Bold      then Append (P, ";1"); end if;
      if C.Attributes.Italic    then Append (P, ";3"); end if;
      if C.Attributes.Underline then Append (P, ";4"); end if;
      if C.Attributes.Inverse   then Append (P, ";7"); end if;
      Append (P, Color_SGR (C.Foreground, 38, 30, 90));
      Append (P, Color_SGR (C.Background, 48, 40, 100));
      return ESC & "[" & To_String (P) & "m";
   end Cell_SGR;

   ---------------------------------------------------------------------------
   --  Cursor / screen primitives
   ---------------------------------------------------------------------------

   function Move_Str (Row, Col : Positive) return String is
     (ESC & "[" & Img (Row) & ";" & Img (Col) & "H");

   procedure Move_To (Row, Col : Positive) is
   begin
      Put (Move_Str (Row, Col));
   end Move_To;

   procedure New_Frame is
   begin
      Put (ESC & "[2J" & ESC & "[H");
   end New_Frame;

   procedure Hide_Cursor is
   begin
      Put (ESC & "[?25l");
   end Hide_Cursor;

   procedure Show_Cursor is
   begin
      Put (ESC & "[?25h");
   end Show_Cursor;

   procedure Reset_Style is
   begin
      Put (ESC & "[0m");
   end Reset_Style;

   ---------------------------------------------------------------------------
   --  Surface output
   ---------------------------------------------------------------------------

   procedure Blit (S : Tui.Surface.Surface) is
      use Tui.Surface;
      Buf      : Unbounded_String;
      Last_SGR : Unbounded_String;   --  empty => force first emit
      First    : Boolean := True;
   begin
      for R in Row_Index range 1 .. S.Rows loop
         Append (Buf, Move_Str (Positive (R), 1));
         for C in Col_Index range 1 .. S.Cols loop
            declare
               Cell_Here : constant Cell   := Get (S, R, C);
               SGR_Here  : constant String := Cell_SGR (Cell_Here);
            begin
               if First or else SGR_Here /= To_String (Last_SGR) then
                  Append (Buf, SGR_Here);
                  Last_SGR := To_Unbounded_String (SGR_Here);
                  First    := False;
               end if;
               Append (Buf, Utf8 (Cell_Here.Glyph));
            end;
         end loop;
      end loop;
      Append (Buf, ESC & "[0m");
      Put (To_String (Buf));
   end Blit;

   procedure Apply
     (Changes : Tui.Surface.Diff.Change_Array;
      Count   : Natural)
   is
      Buf      : Unbounded_String;
      Last_SGR : Unbounded_String;
      First    : Boolean := True;
   begin
      for I in 1 .. Count loop
         declare
            Ch       : constant Tui.Surface.Diff.Cell_Change := Changes (I);
            SGR_Here : constant String := Cell_SGR (Ch.Value);
         begin
            Append (Buf, Move_Str (Positive (Ch.Row), Positive (Ch.Column)));
            if First or else SGR_Here /= To_String (Last_SGR) then
               Append (Buf, SGR_Here);
               Last_SGR := To_Unbounded_String (SGR_Here);
               First    := False;
            end if;
            Append (Buf, Utf8 (Ch.Value.Glyph));
         end;
      end loop;
      if Count > 0 then
         Append (Buf, ESC & "[0m");
      end if;
      Put (To_String (Buf));
   end Apply;

end Tui.Term.Output;
