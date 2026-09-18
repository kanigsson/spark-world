with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Tui.Surface;           use Tui.Surface;

package body Box_Demo is

   --  Desired top-left of the box, in surface coordinates. Kept across calls and
   --  re-clamped to the live surface inside Paint, so a resize can never strand
   --  the box off-screen.
   Box_Top  : Integer := 3;
   Box_Left : Integer := 5;

   Box_H : constant := 6;
   Box_W : constant := 20;

   Last_Key : Unbounded_String := To_Unbounded_String ("(press a key)");

   --  Palette intent — full RGB; Tui.Term.Output downgrades per terminal.
   Border_FG : constant Color := (Kind => RGB, R => 0, G => 220, B => 220);
   Fill_BG   : constant Color := (Kind => RGB, R => 30, G => 30, B => 90);
   Title_FG  : constant Color := (Kind => RGB, R => 255, G => 220, B => 120);

   ---------------------------------------------------------------------------
   --  Small surface helpers
   ---------------------------------------------------------------------------

   function Glyph (Ch : Character) return Wide_Wide_Character
   is (Wide_Wide_Character'Val (Character'Pos (Ch)));

   procedure Put_Text
     (S    : in out Surface;
      R    : Row_Index;
      C    : Col_Index;
      Text : String;
      FG   : Color := Default_Color;
      BG   : Color := Default_Color;
      Attr : Style := Plain)
   is
      Col : Col_Count := C;
   begin
      for Ch of Text loop
         exit when Col > S.Cols;
         Set
           (S,
            R,
            Col,
            (Glyph      => Glyph (Ch),
             Foreground => FG,
             Background => BG,
             Attributes => Attr));
         Col := Col + 1;
      end loop;
   end Put_Text;

   ---------------------------------------------------------------------------
   --  Paint
   ---------------------------------------------------------------------------

   procedure Paint (S : in out Surface) is
   begin
      --  Title row.
      Put_Text
        (S,
         1,
         1,
         "tui_term demo  -  arrows move the box,  q / Esc quits",
         FG   => Title_FG,
         Attr => (Bold => True, others => False));

      --  Need a few rows for title + box + status to fit; otherwise just show
      --  the title and status and skip the box.
      if S.Rows >= Row_Count (Box_H + 3)
        and then S.Cols >= Col_Count (Box_W + 2)
      then
         --  Clamp the (possibly resized-out-of-range) box into the drawable
         --  band, row 2 .. last-but-one, and write the clamp back.
         declare
            Max_Top  : constant Integer := Integer (S.Rows) - 1 - Box_H;
            Max_Left : constant Integer := Integer (S.Cols) - Box_W;
         begin
            Box_Top := Integer'Max (2, Integer'Min (Box_Top, Max_Top));
            Box_Left := Integer'Max (1, Integer'Min (Box_Left, Max_Left));
         end;

         for DR in 0 .. Box_H - 1 loop
            for DC in 0 .. Box_W - 1 loop
               declare
                  R      : constant Row_Index := Row_Index (Box_Top + DR);
                  C      : constant Col_Index := Col_Index (Box_Left + DC);
                  Border : constant Boolean :=
                    DR = 0
                    or else DR = Box_H - 1
                    or else DC = 0
                    or else DC = Box_W - 1;
               begin
                  if Border then
                     Set
                       (S,
                        R,
                        C,
                        (Glyph      => Glyph ('#'),
                         Foreground => Border_FG,
                         others     => <>));
                  else
                     Set
                       (S,
                        R,
                        C,
                        (Glyph => ' ', Background => Fill_BG, others => <>));
                  end if;
               end;
            end loop;
         end loop;

         Put_Text
           (S,
            Row_Index (Box_Top + 2),
            Col_Index (Box_Left + 2),
            "Hello, terminal!",
            BG => Fill_BG);
      end if;

      --  Status row (bottom), shown inverse.
      declare
         Status : constant String :=
           "size"
           & S.Rows'Image
           & " x"
           & S.Cols'Image
           & "   last key: "
           & To_String (Last_Key);
      begin
         Put_Text
           (S, S.Rows, 1, Status, Attr => (Inverse => True, others => False));
      end;
   end Paint;

   ---------------------------------------------------------------------------
   --  Key handling
   ---------------------------------------------------------------------------

   function Describe (E : Tui.Input.Key_Event) return String is
      use Tui.Input;
      Mods : constant String :=
        (if E.Mods.Ctrl then "C-" else "")
        & (if E.Mods.Alt then "A-" else "")
        & (if E.Mods.Shift then "S-" else "");
   begin
      if E.Kind = Char then
         if E.Code in 16#20# .. 16#7E# then
            return Mods & "'" & Character'Val (E.Code) & "'";
         else
            return Mods & "char" & E.Code'Image;
         end if;
      else
         return Mods & Key_Kind'Image (E.Kind);
      end if;
   end Describe;

   procedure On_Key
     (Event : Tui.Input.Key_Event; Dirty : out Boolean; Quit : out Boolean)
   is
      use Tui.Input;
   begin
      Quit := False;
      Dirty := True;   --  every key at least refreshes the status line
      Last_Key := To_Unbounded_String (Describe (Event));

      case Event.Kind is
         when Up     =>
            Box_Top := Box_Top - 1;

         when Down   =>
            Box_Top := Box_Top + 1;

         when Left   =>
            Box_Left := Box_Left - 1;

         when Right  =>
            Box_Left := Box_Left + 1;

         when Escape =>
            Quit := True;

         when Char   =>
            --  q/Q to quit, and Ctrl-C (raw mode delivers it as a key, code 'C').
            if Event.Code = Character'Pos ('q')
              or else Event.Code = Character'Pos ('Q')
              or else (Event.Mods.Ctrl
                       and then Event.Code = Character'Pos ('C'))
            then
               Quit := True;
            end if;

         when others =>
            null;
      end case;
   end On_Key;

end Box_Demo;
