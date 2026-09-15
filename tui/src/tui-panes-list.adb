package body Tui.Panes.List with SPARK_Mode => On is

   use type Eng.Effect;

   -----------
   -- Clamp --
   -----------

   procedure Clamp
     (E        : Eng.Instance;
      Total    : Tui.Text.Line_Total;
      Selected : in out Tui.Text.Line_Number)
   is
      Top  : constant Tui.Text.Line_Number := Eng.Top_Line (E);
      Last : constant Tui.Text.Line_Total  := Eng.Last_Visible (E, Total);
   begin
      if Selected > Total then
         Selected := Total;
      end if;
      --  Last >= Top means a visible slice exists; otherwise (zero-height
      --  viewport, empty document) leave the selection where it is.
      if Last >= Top then
         if Selected < Top then
            Selected := Natural'Min (Top, Total);
         elsif Selected > Last then
            Selected := Natural'Min (Last, Total);
         end if;
      end if;
   end Clamp;

   ----------
   -- Move --
   ----------

   procedure Move
     (E        : in out Eng.Instance;
      M        : Sel_Move;
      Content  : Tui.Text.Buffer;
      Index    : Tui.Text.Index;
      Selected : in out Tui.Text.Line_Number;
      Changed  : out Boolean)
   is
      Total : constant Tui.Text.Line_Total  := Tui.Text.Line_Count (Index);
      Old   : constant Tui.Text.Line_Number := Selected;
      Res   : Eng.Effect := Eng.Unchanged;
   begin
      case M is
         when Sel_Down =>
            if Selected < Total then
               Selected := Selected + 1;
               if Selected > Eng.Last_Visible (E, Total) then
                  Eng.Handle (E, Eng.Line_Down, Content, Index, Res);
               end if;
            end if;

         when Sel_Up =>
            if Selected > 1 then
               Selected := Selected - 1;
               if Selected < Eng.Top_Line (E) then
                  Eng.Handle (E, Eng.Line_Up, Content, Index, Res);
               end if;
            end if;

         when Sel_Page_Down =>
            Eng.Handle (E, Eng.Page_Down, Content, Index, Res);
            if Res = Eng.Unchanged then
               Selected := Total;   --  already on the last page: jump to end
            else
               Clamp (E, Total, Selected);
            end if;

         when Sel_Page_Up =>
            Eng.Handle (E, Eng.Page_Up, Content, Index, Res);
            if Res = Eng.Unchanged then
               Selected := 1;       --  already on the first page: jump home
            else
               Clamp (E, Total, Selected);
            end if;

         when Sel_Top =>
            Eng.Handle (E, Eng.To_Top, Content, Index, Res);
            Selected := 1;

         when Sel_Bottom =>
            Eng.Handle (E, Eng.To_Bottom, Content, Index, Res);
            Selected := Total;
      end case;

      Changed := Selected /= Old or else Res /= Eng.Unchanged;
   end Move;

end Tui.Panes.List;
