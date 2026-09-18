--  Tui.App_Kit.Search_Input — the search-pattern editor, as proved SPARK.
--
--  While the user types a pattern, keystrokes grow a byte string instead of
--  navigating. The pattern is capped at Max_Pattern bytes by the engine, so a
--  fixed-size buffer carries it just as well and brings the edit logic —
--  including the UTF-8 encoding of a typed code point — into SPARK, proved
--  free of run-time errors. The engine keeps at most Max_Pattern bytes when a
--  pattern is installed; the editor never offers it more.
--
--  The bytes are UTF-8: ASCII code points map to one byte, the rest to the
--  two/three/four-byte encodings. Backspace removes a whole code point (its
--  lead byte and any trailing continuation bytes), so the buffer stays
--  well-formed.

with Tui.Input;
with Tui.Text;
with Tui.Pager.Engine;

package Tui.App_Kit.Search_Input
  with SPARK_Mode => On
is

   --  Mirror the engine's cap: there is no point holding bytes the engine
   --  would drop when the pattern is installed.
   Max_Pattern : constant := Tui.Pager.Engine.Max_Pattern;
   subtype Pattern_Length is Natural range 0 .. Max_Pattern;

   type Editor is private;
   --  Default-initialised to an empty pattern; just declare one.

   function Length (E : Editor) return Pattern_Length;

   procedure Clear (E : out Editor)
   with Post => Length (E) = 0;

   --  Append the UTF-8 encoding of one code point. A code point that would
   --  not fit within Max_Pattern bytes is dropped whole, leaving the editor
   --  unchanged — never a half-written character.
   procedure Append (E : in out Editor; Code : Tui.Input.Code_Point)
   with Post => Length (E) >= Length (E)'Old;

   --  Remove the last code point: its UTF-8 lead byte and any continuation
   --  bytes that followed it.
   procedure Backspace (E : in out Editor)
   with Post => Length (E) <= Length (E)'Old;

   --  The pattern bytes (UTF-8), 1-based — ready for the engine's pattern
   --  installer and for the host's status-line painter.
   function Bytes (E : Editor) return Tui.Text.Buffer
   with
     Post => Bytes'Result'First = 1 and then Bytes'Result'Length = Length (E);

private

   subtype Store is Tui.Text.Buffer (1 .. Max_Pattern);

   type Editor is record
      Pat : Store := (others => 0);
      Len : Pattern_Length := 0;
   end record;

   function Length (E : Editor) return Pattern_Length
   is (E.Len);

end Tui.App_Kit.Search_Input;
