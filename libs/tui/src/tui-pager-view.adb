package body Tui.Pager.View
  with SPARK_Mode => On
is

   -------------
   -- Max_Top --
   -------------

   function Max_Top (Total : Line_Total; Height : Dimension) return Line_Number
   is
   begin
      if Height = 0 or else Total <= Height then
         return 1;
      else
         return Total - Height + 1;
      end if;
   end Max_Top;

   --------------
   -- Set_Size --
   --------------

   procedure Set_Size
     (V : in out Viewport; Height, Width : Dimension; Total : Line_Total)
   is
      Cap : constant Line_Number := Max_Top (Total, Height);
   begin
      V.Height := Height;
      V.Width := Width;
      if V.Top > Cap then
         V.Top := Cap;
      end if;
   end Set_Size;

   -----------------
   -- Scroll_Down --
   -----------------

   procedure Scroll_Down
     (V : in out Viewport; Total : Line_Total; By : Dimension)
   is
      Cap  : constant Line_Number := Max_Top (Total, V.Height);
      Want : constant Natural := V.Top + By;
   begin
      V.Top := (if Want >= Cap then Cap else Want);
   end Scroll_Down;

   ---------------
   -- Scroll_Up --
   ---------------

   procedure Scroll_Up (V : in out Viewport; By : Dimension) is
   begin
      V.Top := (if V.Top > By then V.Top - By else 1);
   end Scroll_Up;

   ---------------
   -- Page_Down --
   ---------------

   procedure Page_Down (V : in out Viewport; Total : Line_Total) is
   begin
      Scroll_Down (V, Total, V.Height);
   end Page_Down;

   -------------
   -- Page_Up --
   -------------

   procedure Page_Up (V : in out Viewport) is
   begin
      Scroll_Up (V, V.Height);
   end Page_Up;

   --------------------
   -- Half_Page_Down --
   --------------------

   procedure Half_Page_Down (V : in out Viewport; Total : Line_Total) is
      By : Dimension := V.Height / 2;
   begin
      if By = 0 and then V.Height > 0 then
         By := 1;
      end if;
      Scroll_Down (V, Total, By);
   end Half_Page_Down;

   ------------------
   -- Half_Page_Up --
   ------------------

   procedure Half_Page_Up (V : in out Viewport) is
      By : Dimension := V.Height / 2;
   begin
      if By = 0 and then V.Height > 0 then
         By := 1;
      end if;
      Scroll_Up (V, By);
   end Half_Page_Up;

   ------------
   -- Go_Top --
   ------------

   procedure Go_Top (V : in out Viewport) is
   begin
      V.Top := 1;
   end Go_Top;

   ---------------
   -- Go_Bottom --
   ---------------

   procedure Go_Bottom (V : in out Viewport; Total : Line_Total) is
   begin
      V.Top := Max_Top (Total, V.Height);
   end Go_Bottom;

   ------------------
   -- Scroll_Right --
   ------------------

   procedure Scroll_Right (V : in out Viewport; By : Dimension) is
      Want : constant Natural := V.Left + By;
   begin
      V.Left := (if Want > Max_Dim then Max_Dim else Want);
   end Scroll_Right;

   -----------------
   -- Scroll_Left --
   -----------------

   procedure Scroll_Left (V : in out Viewport; By : Dimension) is
   begin
      V.Left := (if V.Left > By then V.Left - By else 0);
   end Scroll_Left;

   ------------------
   -- Last_Visible --
   ------------------

   function Last_Visible (V : Viewport; Total : Line_Total) return Line_Total
   is
   begin
      if Total = 0 or else V.Height = 0 then
         return 0;
      end if;
      declare
         Last : constant Natural := V.Top + V.Height - 1;
      begin
         return (if Last > Total then Total else Last);
      end;
   end Last_Visible;

end Tui.Pager.View;
