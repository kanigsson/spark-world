--  Lightweight syntax policy for source lines inside a unified diff. This is
--  deliberately lexical and dependency-free: language detection and token
--  classification remain SPARK instead of moving app state behind a parser
--  FFI boundary.

with Tui.Text;
with Tui.Pager;

package Git_View_Syntax
  with SPARK_Mode => On
is

   type Language is
     (Plain, Ada_Lang, C_Family, Python_Like, Shell_Like, Config);

   --  A --- a/path or +++ b/path header selects the language for following
   --  hunk lines. /dev/null does not erase the language learned from the
   --  other side of a deletion.
   procedure Header_Language
     (Line : Tui.Text.Buffer; Found : out Boolean; Lang : out Language)
   with Global => null;

   function Language_At
     (Content : Tui.Text.Buffer;
      Idx     : Tui.Text.Index;
      N       : Tui.Text.Line_Number) return Language
   with
     Global => null,
     Pre    =>
       N <= Tui.Text.Line_Count (Idx)
       and then Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Idx);

   function Is_Identifier_Start (B : Tui.Text.Byte) return Boolean
   with Global => null;

   function Is_Identifier (B : Tui.Text.Byte) return Boolean
   with Global => null;

   function Is_Digit (B : Tui.Text.Byte) return Boolean
   is (B in Character'Pos ('0') .. Character'Pos ('9'));

   function Is_Keyword
     (Line : Tui.Text.Buffer;
      From : Tui.Text.Byte_Index;
      To   : Tui.Text.Byte_Index;
      Lang : Language) return Boolean
   with
     Global => null,
     Pre    => From in Line'Range and then To in From .. Line'Last;

   function Starts_Comment
     (Line : Tui.Text.Buffer; Pos : Tui.Text.Byte_Index; Lang : Language)
      return Boolean
   with Global => null, Pre => Pos in Line'Range;

   --  Display column immediately before Offset bytes of Line, saturated at
   --  the pager's maximum horizontal coordinate.
   function Display_Column
     (Line : Tui.Text.Buffer; Offset : Tui.Text.Byte_Count)
      return Tui.Pager.Dimension
   with Global => null, Pre => Offset <= Line'Length;

end Git_View_Syntax;
