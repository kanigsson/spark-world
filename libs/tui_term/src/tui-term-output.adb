with Tui.Term.Sys;
with Tui.Width;

package body Tui.Term.Output
  with SPARK_Mode => On, Refined_State => (Color_Config => Depth)
is

   ESC : constant Character := Character'Val (16#1B#);

   Depth : Color_Depth := Truecolor;

   ---------------------------------------------------------------------------
   --  Configuration
   ---------------------------------------------------------------------------

   procedure Set_Color_Depth (D : Color_Depth) is
   begin
      Depth := D;
   end Set_Color_Depth;

   function Color_Depth_Setting return Color_Depth
   is (Depth);

   ---------------------------------------------------------------------------
   --  Raw write (the single syscall in this package, via the proved shim)
   ---------------------------------------------------------------------------

   procedure Put (Text : String) is
      Offset    : Natural := 0;
      Remaining : Natural := Text'Length;
      Written   : Natural;
   begin
      while Remaining > 0 loop
         pragma Loop_Invariant (Offset + Remaining = Text'Length);
         pragma Loop_Variant (Decreases => Remaining);
         Tui.Term.Sys.Write
           (Stdout_FD, Text (Text'First + Offset .. Text'Last), Written);
         exit when Written = 0;   --  error or closed pipe: give up, don't spin
         Offset := Offset + Written;
         Remaining := Remaining - Written;
      end loop;
   end Put;

   ---------------------------------------------------------------------------
   --  Small formatting helpers
   ---------------------------------------------------------------------------

   function Digit (D : Natural) return Character
   is (Character'Val (Character'Pos ('0') + D))
   with Pre => D <= 9;

   --  Decimal image with no leading space, length-bounded so every emitted
   --  fragment has a proved size. Four digits cover the largest values that
   --  reach here: surface extents and colour components.
   function Img (N : Natural) return String
   with
     Pre  => N <= 9_999,
     Post =>
       Img'Result'First = 1
       and then Img'Result'Length
                = (if N < 10
                   then 1
                   elsif N < 100
                   then 2
                   elsif N < 1_000
                   then 3
                   else 4);

   function Img (N : Natural) return String is
   begin
      if N < 10 then
         return (1 => Digit (N));
      elsif N < 100 then
         return (Digit (N / 10), Digit (N mod 10));
      elsif N < 1_000 then
         return (Digit (N / 100), Digit ((N / 10) mod 10), Digit (N mod 10));
      else
         return
           (Digit (N / 1_000),
            Digit ((N / 100) mod 10),
            Digit ((N / 10) mod 10),
            Digit (N mod 10));
      end if;
   end Img;

   --  Encode one code point as UTF-8. The standard one-to-four-byte forms
   --  cover the whole Unicode range; a code point beyond it (the glyph type
   --  reaches further) becomes the replacement character rather than bytes
   --  no terminal accepts.
   function Utf8 (G : Wide_Wide_Character) return String
   with Post => Utf8'Result'First = 1 and then Utf8'Result'Length in 1 .. 4;

   function Utf8 (G : Wide_Wide_Character) return String is
      Replacement : constant := 16#FFFD#;

      function B (V : Natural) return Character
      is (Character'Val (V))
      with Pre => V <= 255;

      P : constant Natural :=
        (if Wide_Wide_Character'Pos (G) <= 16#10_FFFF#
         then Wide_Wide_Character'Pos (G)
         else Replacement);
   begin
      if P < 16#80# then
         return (1 => B (P));
      elsif P < 16#800# then
         return (B (16#C0# + P / 2**6), B (16#80# + P mod 2**6));
      elsif P < 16#1_0000# then
         return
           (B (16#E0# + P / 2**12),
            B (16#80# + (P / 2**6) mod 2**6),
            B (16#80# + P mod 2**6));
      else
         return
           (B (16#F0# + P / 2**18),
            B (16#80# + (P / 2**12) mod 2**6),
            B (16#80# + (P / 2**6) mod 2**6),
            B (16#80# + P mod 2**6));
      end if;
   end Utf8;

   ---------------------------------------------------------------------------
   --  The staging buffer: frame assembly in fixed memory
   ---------------------------------------------------------------------------

   --  Escape sequences accumulate here and flush to the write shim whenever
   --  the next piece might not fit, so a frame of any size streams through
   --  bounded memory while still going out in large writes.
   --
   --  The capacity is chosen so that an ordinary frame leaves in a single
   --  write: a flush in the middle of one is a point at which the terminal
   --  may render what it has so far, which is what a half-drawn frame looks
   --  like. Synchronized output covers the frames too large for even this.

   Stage_Capacity : constant := 65_536;
   subtype Stage_Count is Natural range 0 .. Stage_Capacity;

   type Stage is record
      Len  : Stage_Count := 0;
      Data : String (1 .. Stage_Capacity) := (others => ' ');
   end record;

   procedure Flush (B : in out Stage)
   with Post => B.Len = 0;

   procedure Flush (B : in out Stage) is
   begin
      Put (B.Data (1 .. B.Len));
      B.Len := 0;
   end Flush;

   procedure Emit (B : in out Stage; Piece : String)
   with Pre => Piece'Length <= Stage_Capacity;

   procedure Emit (B : in out Stage; Piece : String) is
   begin
      if B.Len + Piece'Length > Stage_Capacity then
         Flush (B);
      end if;
      B.Data (B.Len + 1 .. B.Len + Piece'Length) := Piece;
      B.Len := B.Len + Piece'Length;
   end Emit;

   ---------------------------------------------------------------------------
   --  Colour: a surface keeps full intent; here we downgrade to Depth
   ---------------------------------------------------------------------------

   subtype Ansi_16 is Natural range 0 .. 15;
   type RGB_Triple is record
      R, G, B : Tui.Surface.Component;
   end record;

   --  The conventional xterm RGB of the 16 base colours; used only to find a
   --  nearest match when downgrading, so the exact values are not critical.
   Base_16 : constant array (Ansi_16) of RGB_Triple :=
     (0  => (0, 0, 0),
      1  => (205, 0, 0),
      2  => (0, 205, 0),
      3  => (205, 205, 0),
      4  => (0, 0, 238),
      5  => (205, 0, 205),
      6  => (0, 205, 205),
      7  => (229, 229, 229),
      8  => (127, 127, 127),
      9  => (255, 0, 0),
      10 => (0, 255, 0),
      11 => (255, 255, 0),
      12 => (92, 92, 255),
      13 => (255, 0, 255),
      14 => (0, 255, 255),
      15 => (255, 255, 255));

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
            return
              (R => Levels ((N / 36) mod 6),
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
               Best := I;
            end if;
         end;
      end loop;
      return Best;
   end Nearest_16;

   --  Quantise one channel to the 6-level cube (0,95,135,175,215,255).
   function Cube_Level (V : Tui.Surface.Component) return Natural
   with Post => Cube_Level'Result <= 5;

   function Cube_Level (V : Tui.Surface.Component) return Natural is
   begin
      if V < 48 then
         return 0;
      elsif V < 115 then
         return 1;
      else
         return (Natural (V) - 35) / 40;
      end if;
   end Cube_Level;

   function Nearest_256 (C : RGB_Triple) return Natural
   is (16 + 36 * Cube_Level (C.R) + 6 * Cube_Level (C.G) + Cube_Level (C.B))
   with Post => Nearest_256'Result <= 255;

   ---------------------------------------------------------------------------
   --  SGR assembly, in a bounded scratch buffer per cell
   ---------------------------------------------------------------------------

   --  A cell's SGR parameter list. The worst case is bounded by construction:
   --  the "0" reset, four two-byte attributes, and two colour fragments of at
   --  most 17 bytes each (";38;2;255;255;255").
   SGR_Capacity : constant := 64;
   subtype SGR_Count is Natural range 0 .. SGR_Capacity;

   type SGR_Params is record
      Len  : SGR_Count := 0;
      Data : String (1 .. SGR_Capacity) := (others => ' ');
   end record;

   function Same (A, B : SGR_Params) return Boolean
   is (A.Len = B.Len and then A.Data (1 .. A.Len) = B.Data (1 .. B.Len));

   procedure Add (P : in out SGR_Params; Piece : String)
   with
     Pre  => Piece'Length <= SGR_Capacity - P.Len,
     Post => P.Len = P.Len'Old + Piece'Length;

   procedure Add (P : in out SGR_Params; Piece : String) is
   begin
      P.Data (P.Len + 1 .. P.Len + Piece'Length) := Piece;
      P.Len := P.Len + Piece'Length;
   end Add;

   --  Append the SGR fragment selecting a colour, for the given role base
   --  codes: Foreground => (38, 30, 90); Background => (48, 40, 100).
   procedure Add_Color
     (P : in out SGR_Params; C : Tui.Surface.Color; Ext, Lo, Hi : Natural)
   with
     Pre  =>
       Ext <= 48
       and then Lo <= 40
       and then Hi <= 100
       and then P.Len <= SGR_Capacity - 17,
     Post => P.Len <= P.Len'Old + 17;

   procedure Add_Color
     (P : in out SGR_Params; C : Tui.Surface.Color; Ext, Lo, Hi : Natural)
   is
      use Tui.Surface;

      function To_RGB return RGB_Triple
      is (case C.Kind is
            when RGB     => (C.R, C.G, C.B),
            when Palette => Pal_To_RGB (C.Index),
            when Default =>
              (0, 0, 0));   --  unreachable; Default handled below
   begin
      if C.Kind = Default or else Depth = Monochrome then
         return;   --  the leading SGR "0" reset already restored the default

      end if;

      case Depth is
         when Monochrome  =>
            null;

         when Basic_16    =>
            declare
               Idx : constant Ansi_16 := Nearest_16 (To_RGB);
            begin
               if Idx < 8 then
                  Add (P, ";" & Img (Lo + Idx));
               else
                  Add (P, ";" & Img (Hi + (Idx - 8)));
               end if;
            end;

         when Palette_256 =>
            case C.Kind is
               when Palette =>
                  Add (P, ";" & Img (Ext) & ";5;" & Img (Natural (C.Index)));

               when RGB     =>
                  Add
                    (P, ";" & Img (Ext) & ";5;" & Img (Nearest_256 (To_RGB)));

               when Default =>
                  null;
            end case;

         when Truecolor   =>
            case C.Kind is
               when Palette =>
                  Add (P, ";" & Img (Ext) & ";5;" & Img (Natural (C.Index)));

               when RGB     =>
                  Add
                    (P,
                     ";"
                     & Img (Ext)
                     & ";2;"
                     & Img (Natural (C.R))
                     & ";"
                     & Img (Natural (C.G))
                     & ";"
                     & Img (Natural (C.B)));

               when Default =>
                  null;
            end case;
      end case;
   end Add_Color;

   --  The complete, absolute SGR parameter list for a cell: always leads with
   --  "0" (reset), then adds attributes and colours. Absolute form means no
   --  per-cell bookkeeping of "what to turn off" — and identical adjacent
   --  cells collapse to nothing because the caller compares the produced
   --  parameters to the last ones emitted.
   procedure Cell_SGR (C : Tui.Surface.Cell; P : out SGR_Params) is
   begin
      P := (Len => 0, Data => (others => ' '));
      Add (P, "0");
      if C.Attributes.Bold then
         Add (P, ";1");
      end if;
      if C.Attributes.Italic then
         Add (P, ";3");
      end if;
      if C.Attributes.Underline then
         Add (P, ";4");
      end if;
      if C.Attributes.Inverse then
         Add (P, ";7");
      end if;
      Add_Color (P, C.Foreground, 38, 30, 90);
      Add_Color (P, C.Background, 48, 40, 100);
   end Cell_SGR;

   --  Append a cell's style as a full escape sequence.
   procedure Emit_SGR (B : in out Stage; P : SGR_Params) is
   begin
      Emit (B, ESC & "[" & P.Data (1 .. P.Len) & "m");
   end Emit_SGR;

   ---------------------------------------------------------------------------
   --  Cursor / screen primitives
   ---------------------------------------------------------------------------

   function Move_Str (Row, Col : Positive) return String
   with
     Pre  => Row <= 9_999 and then Col <= 9_999,
     Post => Move_Str'Result'Length <= 12;

   function Move_Str (Row, Col : Positive) return String
   is (ESC & "[" & Img (Row) & ";" & Img (Col) & "H");

   procedure Move_To (Row, Col : Positive) is
   begin
      Put (Move_Str (Row, Col));
   end Move_To;

   procedure New_Frame is
   begin
      Put (ESC & "[2J" & ESC & "[H");
   end New_Frame;

   --  Synchronized output (DEC private mode 2026). Between the two markers a
   --  terminal that understands them presents nothing, then presents the
   --  whole frame at once, so a frame is never seen half applied -- which is
   --  what reads as flicker when a repaint is large enough to span more than
   --  one write. A terminal that does not understand the mode ignores both
   --  markers, so this costs twelve bytes a frame and is never wrong.

   procedure Begin_Sync (B : in out Stage) is
   begin
      Emit (B, ESC & "[?2026h");
   end Begin_Sync;

   procedure End_Sync (B : in out Stage) is
   begin
      Emit (B, ESC & "[?2026l");
   end End_Sync;

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
      B        : Stage;
      Here     : SGR_Params;
      Last_SGR : SGR_Params;
      First    : Boolean := True;
   begin
      Begin_Sync (B);
      for R in Row_Index range 1 .. S.Rows loop
         Emit (B, Move_Str (Positive (R), 1));
         for C in Col_Index range 1 .. S.Cols loop
            declare
               Cell_Here : constant Cell := Get (S, R, C);
            begin
               Cell_SGR (Cell_Here, Here);
               if First or else not Same (Here, Last_SGR) then
                  Emit_SGR (B, Here);
                  Last_SGR := Here;
                  First := False;
               end if;
               Emit (B, Utf8 (Cell_Here.Glyph));
            end;
         end loop;
      end loop;
      Emit (B, ESC & "[0m");
      End_Sync (B);
      Flush (B);
   end Blit;

   procedure Apply (Changes : Tui.Surface.Diff.Change_Array; Count : Natural)
   is
      B        : Stage;
      Here     : SGR_Params;
      Last_SGR : SGR_Params;
      First    : Boolean := True;

      --  Where the terminal's cursor stands, as a row and the column the
      --  next glyph would land in; zero until the first move places it.
      --  Writing a glyph advances the cursor one column, which for a run of
      --  neighbouring changed cells is exactly where the next one goes, so
      --  only a break in the run needs an absolute move. A move costs up to
      --  twelve bytes against one to four for the glyph, so on a frame that
      --  changes whole lines -- a scroll, a new pane -- the moves are most
      --  of what goes out.
      --
      --  The test is "is the cursor already there?", not "was the previous
      --  change adjacent?", so it stays correct whatever order the changes
      --  arrive in; a diff happens to produce them in row-major order, which
      --  is what makes it pay.
      Row_At : Natural := 0;
      Col_At : Natural := 0;
   begin
      if Count = 0 then
         return;
      end if;
      Begin_Sync (B);
      for I in 1 .. Count loop
         declare
            Ch      : constant Tui.Surface.Diff.Cell_Change :=
              Changes (Changes'First + (I - 1));
            --  Columns the glyph will advance the cursor by. A run may only
            --  be continued across a glyph that advances exactly one: a wide
            --  or combining glyph leaves the cursor somewhere this package
            --  does not model, so the next change is positioned outright.
            Advance : constant Natural :=
              Tui.Width.Char_Width
                (if Wide_Wide_Character'Pos (Ch.Value.Glyph) <= 16#10_FFFF#
                 then Wide_Wide_Character'Pos (Ch.Value.Glyph)
                 else 16#FFFD#);
         begin
            if Natural (Ch.Row) /= Row_At or else Natural (Ch.Column) /= Col_At
            then
               Emit (B, Move_Str (Positive (Ch.Row), Positive (Ch.Column)));
            end if;
            Cell_SGR (Ch.Value, Here);
            if First or else not Same (Here, Last_SGR) then
               Emit_SGR (B, Here);
               Last_SGR := Here;
               First := False;
            end if;
            Emit (B, Utf8 (Ch.Value.Glyph));
            if Advance = 1 then
               Row_At := Natural (Ch.Row);
               Col_At := Natural (Ch.Column) + 1;
            else
               Row_At := 0;
               Col_At := 0;
            end if;
         end;
      end loop;
      Emit (B, ESC & "[0m");
      End_Sync (B);
      Flush (B);
   end Apply;

end Tui.Term.Output;
