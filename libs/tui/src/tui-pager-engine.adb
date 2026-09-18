with Tui.Pager.Render;
with Tui.Pager.Search;

package body Tui.Pager.Engine
  with SPARK_Mode => On
is

   package V renames Tui.Pager.View;
   use type V.Viewport;

   ------------
   -- Resize --
   ------------

   procedure Resize
     (E     : in out Instance;
      Rows  : Dimension;
      Cols  : Dimension;
      Total : Line_Total) is
   begin
      V.Set_Size (E.View, Height => Rows, Width => Cols, Total => Total);
   end Resize;

   -------------
   -- Set_Tab --
   -------------

   procedure Set_Tab (E : in out Instance; Tab : Tab_Width) is
   begin
      E.Tab := Tab;
   end Set_Tab;

   ----------------
   -- Go_To_Line --
   ----------------

   procedure Go_To_Line
     (E : in out Instance; Line : Line_Number; Total : Line_Total) is
   begin
      E.View.Top := Line_Number'Min (Line, V.Max_Top (Total, E.View.Height));
   end Go_To_Line;

   -----------------
   -- Set_Pattern --
   -----------------

   procedure Set_Pattern (E : in out Instance; Pattern : Tui.Text.Buffer) is
      N : constant Pattern_Length := Natural'Min (Pattern'Length, Max_Pattern);
   begin
      for I in 1 .. N loop
         E.Pat (I) := Pattern (Pattern'First + (I - 1));
      end loop;
      E.Pat_Len := N;
   end Set_Pattern;

   ---------------
   -- Do_Search --
   ---------------

   procedure Do_Search
     (E       : in out Instance;
      Cmd     : Command;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Total   : Line_Total;
      Result  : out Effect)
   with
     Global => null,
     Pre    =>
       Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Index)
       and then Total = Tui.Text.Line_Count (Index)
       and then (Cmd = Find_Next or else Cmd = Find_Prev)
   is
      Forward : constant Boolean := Cmd = Find_Next;
      From    : Line_Number;
      Found   : Boolean;
      L       : Line_Number;
   begin
      --  Nothing to search, or nowhere to go in this direction.
      if E.Pat_Len = 0 or else Total = 0 then
         Result := Search_Miss;
         return;
      end if;

      if Forward then
         if E.View.Top >= Total then
            Result := Search_Miss;
            return;
         end if;
         --  Search below the current top. The Min guards From <= Total = the
         --  line count even if the viewport were somehow past the end.
         From := Line_Number'Min (E.View.Top + 1, Total);
      else
         if E.View.Top = 1 then
            Result := Search_Miss;
            return;
         end if;
         From := Line_Number'Min (E.View.Top - 1, Total);
      end if;

      declare
         --  Fixed-size local (a variable-bound subtype is illegal in SPARK);
         --  the active pattern is the leading slice, which carries 'First = 1.
         Pat : Tui.Text.Buffer (1 .. Max_Pattern) := (others => 0);
      begin
         for I in 1 .. E.Pat_Len loop
            Pat (I) := E.Pat (I);
         end loop;

         Tui.Pager.Search.Find
           (Content, Index, Pat (1 .. E.Pat_Len), From, Forward, Found, L);
      end;

      if Found then
         --  Put the match on screen: pin it to the top where possible, but never
         --  scroll past the last page (Max_Top), which still leaves it visible.
         E.View.Top := Line_Number'Min (L, V.Max_Top (Total, E.View.Height));
         Result := Search_Hit;
      else
         Result := Search_Miss;
      end if;
   end Do_Search;

   ------------
   -- Handle --
   ------------

   procedure Handle
     (E       : in out Instance;
      Cmd     : Command;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Result  : out Effect)
   is
      Total : constant Line_Total := Tui.Text.Line_Count (Index);
      Old   : constant V.Viewport := E.View;
   begin
      case Cmd is
         when Line_Up               =>
            V.Scroll_Up (E.View, 1);

         when Line_Down             =>
            V.Scroll_Down (E.View, Total, 1);

         when Half_Up               =>
            V.Half_Page_Up (E.View);

         when Half_Down             =>
            V.Half_Page_Down (E.View, Total);

         when Page_Up               =>
            V.Page_Up (E.View);

         when Page_Down             =>
            V.Page_Down (E.View, Total);

         when To_Top                =>
            V.Go_Top (E.View);

         when To_Bottom             =>
            V.Go_Bottom (E.View, Total);

         when Col_Left              =>
            V.Scroll_Left (E.View, H_Scroll_Step);

         when Col_Right             =>
            V.Scroll_Right (E.View, H_Scroll_Step);

         when Find_Next | Find_Prev =>
            Do_Search (E, Cmd, Content, Index, Total, Result);
            return;
      end case;

      Result := (if E.View = Old then Unchanged else Moved);
   end Handle;

   ------------
   -- Render --
   ------------

   procedure Render
     (E       : Instance;
      Target  : in out Tui.Surface.Surface;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index) is
   begin
      Tui.Pager.Render.Draw (Target, Content, Index, E.View, E.Tab);
   end Render;

end Tui.Pager.Engine;
