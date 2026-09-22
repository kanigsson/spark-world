--  Paint lightweight source-token colours onto an already-rendered row.
--  Only foregrounds are changed, so comparison backgrounds and selection
--  attributes remain independent visual channels.

with Git_View_Syntax;
with Tui.Pager;
with Tui.Surface;
with Tui.Text;

package Git_View_Highlight
  with SPARK_Mode => On
is
   use type Tui.Surface.Row_Count;

   procedure Source_Line
     (S      : in out Tui.Surface.Surface;
      Row    : Tui.Surface.Row_Index;
      Line   : Tui.Text.Buffer;
      Lang   : Git_View_Syntax.Language;
      Offset : Tui.Text.Byte_Count;
      Left   : Tui.Pager.Dimension)
   with Global => null, Pre => Row <= S.Rows and then Offset <= Line'Length;
end Git_View_Highlight;
