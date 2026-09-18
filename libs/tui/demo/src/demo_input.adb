--  Throwaway demo. NOT part of the library. Rather than read a real terminal
--  (that needs the future driver crate), it feeds a fixed, representative byte
--  stream through the decoder and prints the decoded events — so the state
--  machine is observable with no OS involvement.

with Ada.Text_IO; use Ada.Text_IO;
with Tui.Input;   use Tui.Input;

procedure Demo_Input is

   type Bytes is array (Positive range <>) of Byte;
   function C (Ch : Character) return Byte
   is (Byte (Character'Pos (Ch)));

   --  "Hi", Enter, Ctrl-C, Up, Ctrl-Right, Delete, F1, Alt-x, 'é', then a
   --  lone ESC (resolved by the trailing Flush).
   Stream : constant Bytes :=
     (C ('H'),
      C ('i'),
      16#0D#,
      16#03#,
      16#1B#,
      C ('['),
      C ('A'),
      16#1B#,
      C ('['),
      C ('1'),
      C (';'),
      C ('5'),
      C ('C'),
      16#1B#,
      C ('['),
      C ('3'),
      C ('~'),
      16#1B#,
      C ('O'),
      C ('P'),
      16#1B#,
      C ('x'),
      16#C3#,
      16#A9#,
      16#1B#);

   function Mods_Str (M : Modifiers) return String is
      S : String (1 .. 0) := "";
   begin
      return
        (if M.Ctrl then "C-" else "")
        & (if M.Alt then "A-" else "")
        & (if M.Shift then "S-" else "")
        & S;
   end Mods_Str;

   procedure Show (E : Key_Event) is
   begin
      Put ("  event: " & Mods_Str (E.Mods) & Key_Kind'Image (E.Kind));
      if E.Kind = Char then
         Put (" code=" & E.Code'Image);
         if E.Code in 16#20# .. 16#7E# then
            Put (" '" & Character'Val (E.Code) & "'");
         end if;
      end if;
      New_Line;
   end Show;

   D     : Decoder;
   E     : Key_Event;
   Avail : Boolean;

begin
   Put_Line ("feeding" & Stream'Length'Image & " bytes:");
   for I in Stream'Range loop
      Feed (D, Stream (I), E, Avail);
      if Avail then
         Show (E);
      end if;
   end loop;
   Flush (D, E, Avail);
   if Avail then
      Show (E);
   end if;
end Demo_Input;
