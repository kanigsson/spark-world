--  Tui.Panes.Clip — turning a selection into the bytes a clipboard carries.
--
--  Encoding is pure and lives here; EMISSION is a terminal effect and lives
--  in the driver (Tui.Term.Clipboard). Splitting the two is what keeps a
--  terminal write out of proved code and makes the encoder testable without
--  a terminal.
--
--  The payload is bounded. A selection larger than Max_Payload is copied up
--  to the bound and reports itself truncated, so the host can say so rather
--  than let the terminal silently drop an over-long sequence.

with Tui.Text;
with Tui.Panes.Selection;

package Tui.Panes.Clip
  with SPARK_Mode => On
is

   Max_Payload : constant := 65_536;

   subtype Payload_Length is Natural range 0 .. Max_Payload;

   type Payload is private;

   function Length (P : Payload) return Payload_Length
   with Global => null;

   --  Copy the selected text out of a document. Tabs count as their expanded
   --  cells when the ends are resolved but stay tabs in the copied bytes,
   --  and rows are joined with a newline.
   procedure Extract
     (Content     : Tui.Text.Buffer;
      Idx         : Tui.Text.Index;
      First, Last : Selection.Position;
      Text        : out Payload;
      Truncated   : out Boolean)
   with
     Global => null,
     Pre    =>
       Selection.Before_Or_Equal (First, Last)
       and then Last.Line <= Tui.Text.Line_Count (Idx)
       and then Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Idx);

   ---------------------------------------------------------------------------
   --  Base64, a quartet at a time
   --
   --  A whole encoded buffer would be 87 KB of stack for a payload the driver
   --  writes straight out, so the encoder hands over one quartet at a time
   --  and the driver streams them.
   ---------------------------------------------------------------------------

   subtype Quartet is String (1 .. 4);

   function Quartet_Count (P : Payload) return Natural
   with Global => null, Post => Quartet_Count'Result = (Length (P) + 2) / 3;

   function Encode (P : Payload; N : Positive) return Quartet
   with Global => null, Pre => N <= Quartet_Count (P);

private

   type Byte_Store is array (Positive range 1 .. Max_Payload) of Tui.Text.Byte;

   type Payload is record
      Bytes : Byte_Store := (others => 0);
      Len   : Payload_Length := 0;
   end record;

   function Length (P : Payload) return Payload_Length
   is (P.Len);

   function Quartet_Count (P : Payload) return Natural
   is ((P.Len + 2) / 3);

end Tui.Panes.Clip;
