--  Behavioural tests for the input decoder. Complements gnatprove: proof shows
--  the contracts hold for all byte sequences; these pin concrete mappings.

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Command_Line;
with Tui.Input;             use Tui.Input;

procedure Test_Input is

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("  ok   : " & Label);
      else
         Put_Line ("  FAIL : " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   type Bytes is array (Positive range <>) of Byte;

   function C (Ch : Character) return Byte is (Byte (Character'Pos (Ch)));

   --  Feed a whole sequence; report the FIRST event produced and the total
   --  number of events. Optionally Flush at the end (driver timeout).
   procedure Decode
     (Seq       : Bytes;
      Flush_It  : Boolean;
      First     : out Key_Event;
      Count     : out Natural)
   is
      D     : Decoder;
      E     : Key_Event;
      Avail : Boolean;
   begin
      First := (Kind => Unknown, Mods => No_Modifiers, Code => 0,
                others => <>);
      Count := 0;
      for I in Seq'Range loop
         Feed (D, Seq (I), E, Avail);
         if Avail then
            if Count = 0 then
               First := E;
            end if;
            Count := Count + 1;
         end if;
      end loop;
      if Flush_It then
         Flush (D, E, Avail);
         if Avail then
            if Count = 0 then
               First := E;
            end if;
            Count := Count + 1;
         end if;
      end if;
   end Decode;

   E : Key_Event;
   N : Natural;

begin
   Decode ((1 => C ('a')), False, E, N);
   Check (N = 1 and then E.Kind = Char and then E.Code = Character'Pos ('a')
          and then not E.Mods.Ctrl and then not E.Mods.Alt,
          "'a' -> Char a");

   Decode ((1 => 16#0D#), False, E, N);
   Check (N = 1 and then E.Kind = Enter, "CR -> Enter");

   Decode ((1 => 16#09#), False, E, N);
   Check (N = 1 and then E.Kind = Tab, "HT -> Tab");

   Decode ((1 => 16#7F#), False, E, N);
   Check (N = 1 and then E.Kind = Backspace, "DEL -> Backspace");

   Decode ((1 => 16#03#), False, E, N);  --  Ctrl-C
   Check (N = 1 and then E.Kind = Char and then E.Code = Character'Pos ('C')
          and then E.Mods.Ctrl, "0x03 -> Ctrl-C");

   Decode ((16#1B#, C ('['), C ('A')), False, E, N);
   Check (N = 1 and then E.Kind = Up and then not E.Mods.Ctrl, "ESC[A -> Up");

   Decode ((16#1B#, C ('['), C ('D')), False, E, N);
   Check (N = 1 and then E.Kind = Left, "ESC[D -> Left");

   Decode ((16#1B#, C ('['), C ('H')), False, E, N);
   Check (N = 1 and then E.Kind = Home, "ESC[H -> Home");

   Decode ((16#1B#, C ('['), C ('3'), C ('~')), False, E, N);
   Check (N = 1 and then E.Kind = Delete, "ESC[3~ -> Delete");

   Decode ((16#1B#, C ('['), C ('5'), C ('~')), False, E, N);
   Check (N = 1 and then E.Kind = Page_Up, "ESC[5~ -> PageUp");

   Decode ((16#1B#, C ('['), C ('1'), C (';'), C ('5'), C ('A')), False, E, N);
   Check (N = 1 and then E.Kind = Up and then E.Mods.Ctrl
          and then not E.Mods.Alt and then not E.Mods.Shift,
          "ESC[1;5A -> Ctrl-Up");

   Decode ((16#1B#, C ('O'), C ('P')), False, E, N);
   Check (N = 1 and then E.Kind = F1, "ESC O P -> F1");

   Decode ((16#1B#, C ('['), C ('1'), C ('5'), C ('~')), False, E, N);
   Check (N = 1 and then E.Kind = F5, "ESC[15~ -> F5");

   Decode ((16#1B#, C ('x')), False, E, N);
   Check (N = 1 and then E.Kind = Char and then E.Code = Character'Pos ('x')
          and then E.Mods.Alt and then not E.Mods.Ctrl, "ESC x -> Alt-x");

   Decode ((1 => 16#1B#), True, E, N);  --  lone ESC then timeout
   Check (N = 1 and then E.Kind = Escape, "lone ESC + Flush -> Escape");

   Decode ((16#C3#, 16#A9#), False, E, N);  --  'é' U+00E9
   Check (N = 1 and then E.Kind = Char and then E.Code = 16#E9#,
          "UTF-8 C3 A9 -> U+00E9");

   Decode ((16#E2#, 16#82#, 16#AC#), False, E, N);  --  '€' U+20AC
   Check (N = 1 and then E.Kind = Char and then E.Code = 16#20AC#,
          "UTF-8 E2 82 AC -> U+20AC");

   Decode ((1 => 16#FF#), False, E, N);
   Check (N = 1 and then E.Kind = Unknown, "0xFF -> Unknown");

   --  SGR mouse reports: ESC [ < Pb ; Px ; Py M (press) / m (release).
   Decode ((16#1B#, C ('['), C ('<'), C ('0'), C (';'),
            C ('1'), C ('2'), C (';'), C ('5'), C ('M')), False, E, N);
   Check (N = 1 and then E.Kind = Mouse_Press
          and then E.Button = Left_Button
          and then E.Col = 12 and then E.Row = 5
          and then not E.Mods.Ctrl,
          "ESC[<0;12;5M -> left press at (12,5)");

   Decode ((16#1B#, C ('['), C ('<'), C ('0'), C (';'),
            C ('1'), C ('2'), C (';'), C ('5'), C ('m')), False, E, N);
   Check (N = 1 and then E.Kind = Mouse_Release
          and then E.Button = Left_Button
          and then E.Col = 12 and then E.Row = 5,
          "ESC[<0;12;5m -> left release at (12,5)");

   Decode ((16#1B#, C ('['), C ('<'), C ('3'), C ('2'), C (';'),
            C ('1'), C ('4'), C (';'), C ('6'), C ('M')), False, E, N);
   Check (N = 1 and then E.Kind = Mouse_Motion
          and then E.Button = Left_Button
          and then E.Col = 14 and then E.Row = 6,
          "ESC[<32;14;6M -> left-button motion at (14,6)");

   Decode ((16#1B#, C ('['), C ('<'), C ('2'), C (';'),
            C ('7'), C (';'), C ('3'), C ('M')), False, E, N);
   Check (N = 1 and then E.Kind = Mouse_Press
          and then E.Button = Right_Button
          and then E.Col = 7 and then E.Row = 3,
          "ESC[<2;7;3M -> right press at (7,3)");

   Decode ((16#1B#, C ('['), C ('<'), C ('6'), C ('4'), C (';'),
            C ('8'), C ('0'), C (';'), C ('2'), C ('4'), C ('M')),
           False, E, N);
   Check (N = 1 and then E.Kind = Wheel_Up
          and then E.Col = 80 and then E.Row = 24,
          "ESC[<64;80;24M -> wheel up at (80,24)");

   Decode ((16#1B#, C ('['), C ('<'), C ('6'), C ('5'), C (';'),
            C ('1'), C (';'), C ('1'), C ('M')), False, E, N);
   Check (N = 1 and then E.Kind = Wheel_Down
          and then E.Col = 1 and then E.Row = 1,
          "ESC[<65;1;1M -> wheel down at (1,1)");

   Decode ((16#1B#, C ('['), C ('<'), C ('1'), C ('6'), C (';'),
            C ('3'), C (';'), C ('4'), C ('M')), False, E, N);
   Check (N = 1 and then E.Kind = Mouse_Press
          and then E.Button = Left_Button
          and then E.Mods.Ctrl and then not E.Mods.Shift,
          "ESC[<16;3;4M -> Ctrl + left press");

   --  An SGR-marked sequence with a foreign final must not leak a key event.
   Decode ((16#1B#, C ('['), C ('<'), C ('1'), C (';'),
            C ('5'), C ('A')), False, E, N);
   Check (N = 1 and then E.Kind = Unknown,
          "ESC[<1;5A -> Unknown (not Ctrl-Up)");

   --  A key sequence after a mouse report decodes normally (state reset).
   Decode ((16#1B#, C ('['), C ('<'), C ('0'), C (';'),
            C ('1'), C (';'), C ('1'), C ('M'),
            16#1B#, C ('['), C ('A')), False, E, N);
   Check (N = 2 and then E.Kind = Mouse_Press,
          "mouse report then ESC[A -> two events");

   --  Is_Pending exposure: bare ESC leaves the decoder mid-sequence.
   declare
      D     : Decoder;
      Ev    : Key_Event;
      Avail : Boolean;
   begin
      Feed (D, 16#1B#, Ev, Avail);
      Check (Is_Pending (D) and then not Avail, "after ESC: pending, no event");
      Feed (D, C ('['), Ev, Avail);
      Feed (D, C ('B'), Ev, Avail);
      Check (not Is_Pending (D) and then Avail and then Ev.Kind = Down,
             "ESC[B completes -> Down, not pending");
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Input;
