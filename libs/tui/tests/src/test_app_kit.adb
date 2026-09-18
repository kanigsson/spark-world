--  Behavioural tests for the app kit. Complements gnatprove: proof shows the
--  contracts hold for all inputs; these pin concrete encodings and texts.

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Tui.Text;    use Tui.Text;
with Tui.App_Kit.Search_Input;
with Tui.App_Kit.Status;

procedure Test_App_Kit is

   package Edit renames Tui.App_Kit.Search_Input;
   package Stat renames Tui.App_Kit.Status;

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

   function Str_Of (B : Buffer) return String is
      S : String (1 .. B'Length);
   begin
      for I in B'Range loop
         S (1 + (I - B'First)) := Character'Val (Integer (B (I)));
      end loop;
      return S;
   end Str_Of;

begin
   --  Editor: ASCII appends one byte per code point.
   declare
      E : Edit.Editor;
   begin
      Edit.Append (E, Character'Pos ('a'));
      Edit.Append (E, Character'Pos ('b'));
      Check
        (Edit.Length (E) = 2 and then Str_Of (Edit.Bytes (E)) = "ab",
         "ASCII appends");
      Edit.Backspace (E);
      Check (Str_Of (Edit.Bytes (E)) = "a", "backspace removes one ASCII");
      Edit.Clear (E);
      Check (Edit.Length (E) = 0, "clear empties");
   end;

   --  Editor: multibyte UTF-8 encodings, and whole-code-point backspace.
   declare
      E : Edit.Editor;
   begin
      Edit.Append (E, 16#E9#);      --  é -> C3 A9
      Check
        (Edit.Length (E) = 2
         and then Edit.Bytes (E) (1) = 16#C3#
         and then Edit.Bytes (E) (2) = 16#A9#,
         "U+00E9 -> C3 A9");
      Edit.Append (E, 16#20AC#);    --  € -> E2 82 AC
      Check
        (Edit.Length (E) = 5
         and then Edit.Bytes (E) (3) = 16#E2#
         and then Edit.Bytes (E) (4) = 16#82#
         and then Edit.Bytes (E) (5) = 16#AC#,
         "U+20AC -> E2 82 AC");
      Edit.Append (E, 16#1F600#);   --  😀 -> F0 9F 98 80
      Check
        (Edit.Length (E) = 9
         and then Edit.Bytes (E) (6) = 16#F0#
         and then Edit.Bytes (E) (7) = 16#9F#
         and then Edit.Bytes (E) (8) = 16#98#
         and then Edit.Bytes (E) (9) = 16#80#,
         "U+1F600 -> F0 9F 98 80");
      Edit.Backspace (E);
      Check (Edit.Length (E) = 5, "backspace removes whole 4-byte point");
      Edit.Backspace (E);
      Check (Edit.Length (E) = 2, "backspace removes whole 3-byte point");
      Edit.Backspace (E);
      Check (Edit.Length (E) = 0, "backspace removes whole 2-byte point");
      Edit.Backspace (E);
      Check (Edit.Length (E) = 0, "backspace on empty is a no-op");
   end;

   --  Editor: a code point that would not fit is dropped whole.
   declare
      E : Edit.Editor;
   begin
      for I in 1 .. Edit.Max_Pattern - 1 loop
         Edit.Append (E, Character'Pos ('x'));
      end loop;
      Check (Edit.Length (E) = Edit.Max_Pattern - 1, "filled to cap - 1");
      Edit.Append (E, 16#E9#);      --  needs 2 bytes, only 1 free
      Check
        (Edit.Length (E) = Edit.Max_Pattern - 1,
         "overflowing point dropped whole");
      Edit.Append (E, Character'Pos ('y'));
      Check
        (Edit.Length (E) = Edit.Max_Pattern
         and then Edit.Bytes (E) (Edit.Max_Pattern) = Character'Pos ('y'),
         "last byte still usable");
   end;

   --  Status: building blocks.
   declare
      L : Stat.Line;
   begin
      Stat.Reset (L);
      Check (Stat.Length (L) = 0 and then Stat.Image (L) = "", "reset");
      Stat.Put (L, "lines ");
      Stat.Put_Nat (L, 42);
      Stat.Put_Char (L, '%');
      Check (Stat.Image (L) = "lines 42%", "put / put_nat / put_char");
      Stat.Reset (L);
      Stat.Put_Nat (L, 0);
      Check (Stat.Image (L) = "0", "put_nat 0 has no leading space");
   end;

   --  Status: appends truncate at the cap instead of overrunning.
   declare
      L : Stat.Line;
   begin
      Stat.Reset (L);
      for I in 1 .. Stat.Max_Status - 1 loop
         Stat.Put_Char (L, '.');
      end loop;
      Stat.Put (L, "abc");
      Check
        (Stat.Length (L) = Stat.Max_Status
         and then Stat.Image (L) (Stat.Max_Status) = 'a',
         "append truncates at Max_Status");
   end;

   --  Status: the search prompt, forward and backward, bytes as Latin-1.
   declare
      L : Stat.Line;
      P : constant Buffer :=
        (Character'Pos ('f'), Character'Pos ('o'), Character'Pos ('o'));
      E : constant Buffer (1 .. 0) := (others => 0);
   begin
      Stat.Format_Prompt (L, Forward => True, Pattern => P);
      Check (Stat.Image (L) = "/foo", "forward prompt");
      Stat.Format_Prompt (L, Forward => False, Pattern => P);
      Check (Stat.Image (L) = "?foo", "backward prompt");
      Stat.Format_Prompt (L, Forward => True, Pattern => E);
      Check (Stat.Image (L) = "/", "empty pattern prompt");
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_App_Kit;
