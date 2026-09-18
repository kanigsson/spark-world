--  Tui.App_Kit.Status — the status-line buffer, as proved SPARK.
--
--  The bottom row of the screen shows one short piece of text at a time: the
--  search prompt being typed, a transient note, or a position read-out. The
--  text never needs to exceed the screen width, so a fixed-size line buffer
--  holds it just as well as a dynamic string and brings the formatting into
--  SPARK, proved free of run-time errors.
--
--  This package owns the buffer and its building blocks, plus the one piece
--  of text every consumer formats identically: the search prompt. What the
--  notes say and how the position read-out is laid out differ per app, so
--  each app assembles those itself from the Put primitives — the wording is
--  policy, the buffer is mechanism.
--
--  The host still owns the surface: it fills the bar and paints Image (L)
--  onto the row, truncating to the real column count. This package only
--  builds the string.

with Tui.Text;

package Tui.App_Kit.Status
  with SPARK_Mode => On
is

   --  Upper bound on assembled status text. A surface row caps at 4096
   --  columns (the surface crate's extent cap) and the host truncates to the
   --  actual width when painting, so text past this point is never visible;
   --  longer input is silently clipped here, never a buffer overrun.
   Max_Status : constant := 4_096;
   subtype Status_Length is Natural range 0 .. Max_Status;

   type Line is private;

   function Length (L : Line) return Status_Length;

   --  The assembled text, 1-based, ready for the host's painter.
   function Image (L : Line) return String
   with
     Post => Image'Result'First = 1 and then Image'Result'Length = Length (L);

   ---------------------------------------------------------------------------
   --  Building blocks. Every append truncates at Max_Status, so a formatter
   --  built from these cannot overrun the buffer, only lose invisible text.
   ---------------------------------------------------------------------------

   procedure Reset (L : out Line);

   procedure Put_Char (L : in out Line; C : Character);

   procedure Put (L : in out Line; S : String);

   --  Decimal image of N with no leading space (Natural'Image prefixes one).
   procedure Put_Nat (L : in out Line; N : Natural);

   --  One pattern byte, shown as a Latin-1 character.
   procedure Put_Byte (L : in out Line; B : Tui.Text.Byte);

   --  Search prompt: '/' (forward) or '?' (backward), then the pattern bytes.
   --  Each byte is shown as a Latin-1 character, matching the host's painter
   --  (which maps one byte to one cell); multibyte UTF-8 thus renders as its
   --  raw bytes, the pre-existing behaviour.
   procedure Format_Prompt
     (L : out Line; Forward : Boolean; Pattern : Tui.Text.Buffer)
   with Pre => Pattern'Length = 0 or else Pattern'First >= 1;

private

   type Line is record
      Text : String (1 .. Max_Status) := (others => ' ');
      Len  : Status_Length := 0;
   end record;

   function Length (L : Line) return Status_Length
   is (L.Len);

   function Image (L : Line) return String
   is (L.Text (1 .. L.Len));

end Tui.App_Kit.Status;
