--  Tui.Pager.View — the viewport: which slice of the content is on screen.
--
--  Pure arithmetic over a line count and the screen size. Every operation keeps
--  the viewport within the content (you cannot scroll past either end), which is
--  the property this package exists to guarantee. No I/O, no dependencies beyond
--  the line-numbering vocabulary. All SPARK, proved free of run-time errors.

package Tui.Pager.View with SPARK_Mode => On is

   type Viewport is record
      Top    : Line_Number := 1;   --  first visible content line (1-based)
      Left   : Dimension   := 0;   --  horizontal scroll, in display columns
      Height : Dimension   := 0;   --  visible rows
      Width  : Dimension   := 0;   --  visible columns
   end record;

   --  The largest Top that still fills the viewport: the top line of the last
   --  page. Always >= 1 (so an empty or short document pins to the top).
   function Max_Top (Total : Line_Total; Height : Dimension) return Line_Number
   with Global => null,
        Post   => (if Height = 0 or else Total <= Height
                   then Max_Top'Result = 1);

   --  Update the visible size (e.g. on terminal resize) and re-clamp Top so the
   --  view stays within the content.
   procedure Set_Size
     (V : in out Viewport; Height, Width : Dimension; Total : Line_Total)
   with Global => null,
        Post   => V.Height = Height and then V.Width = Width
                  and then V.Top <= Max_Top (Total, Height);

   procedure Scroll_Down (V : in out Viewport; Total : Line_Total; By : Dimension)
   with Global => null, Post => V.Top <= Max_Top (Total, V.Height);

   procedure Scroll_Up (V : in out Viewport; By : Dimension)
   with Global => null;

   procedure Page_Down (V : in out Viewport; Total : Line_Total)
   with Global => null, Post => V.Top <= Max_Top (Total, V.Height);

   procedure Page_Up (V : in out Viewport) with Global => null;

   procedure Half_Page_Down (V : in out Viewport; Total : Line_Total)
   with Global => null, Post => V.Top <= Max_Top (Total, V.Height);

   procedure Half_Page_Up (V : in out Viewport) with Global => null;

   procedure Go_Top (V : in out Viewport)
   with Global => null, Post => V.Top = 1;

   procedure Go_Bottom (V : in out Viewport; Total : Line_Total)
   with Global => null, Post => V.Top = Max_Top (Total, V.Height);

   procedure Scroll_Right (V : in out Viewport; By : Dimension)
   with Global => null;

   procedure Scroll_Left (V : in out Viewport; By : Dimension)
   with Global => null;

   --  The last content line currently visible (0 if the document is empty or
   --  the viewport has no height).
   function Last_Visible (V : Viewport; Total : Line_Total) return Line_Total
   with Global => null;

end Tui.Pager.View;
