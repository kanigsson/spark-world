package body Git_View_Policy with SPARK_Mode => On is

   use Tui.Input;

   --------------------
   -- Compute_Layout --
   --------------------

   function Compute_Layout
     (Cols      : Tui.Surface.Col_Count;
      Focused   : Pane;
      Maximized : Boolean;
      Split     : Split_Percentage) return Layout
   is
      NC : constant Natural := Natural (Cols);
   begin
      if Maximized then
         return (if Focused = List_Pane
                 then (List_Cols => NC, Diff_Cols => 0)
                 else (List_Cols => 0, Diff_Cols => NC));
      elsif NC < Min_Split_Width then
         return (List_Cols => NC, Diff_Cols => 0);
      else
         declare
            Wanted : constant Natural := NC * Split / 100;
            List_Width : constant Natural :=
              Natural'Max
                (Min_Pane_Width,
                 Natural'Min (NC - Min_Pane_Width - 1, Wanted));
         begin
            return (List_Cols => List_Width,
                    Diff_Cols => NC - List_Width - 1);
         end;
      end if;
   end Compute_Layout;

   ------------------
   -- Adjust_Split --
   ------------------

   function Adjust_Split
     (Current   : Split_Percentage;
      Grow_List : Boolean) return Split_Percentage
   is
   begin
      if Grow_List then
         return Split_Percentage'Min
           (Split_Percentage'Last, Current + Split_Step);
      else
         return Split_Percentage'Max
           (Split_Percentage'First, Current - Split_Step);
      end if;
   end Adjust_Split;

   --------------
   -- Split_At --
   --------------

   function Split_At
     (Column : Natural;
      Total  : Tui.Surface.Col_Count) return Split_Percentage
   is
      Raw : constant Natural :=
        Natural'Min
          (100, (Natural'Min (Column, Natural (Total)) * 100)
                / Natural (Total));
   begin
      return Split_Percentage'Max
        (Split_Percentage'First,
         Split_Percentage'Min (Split_Percentage'Last, Raw));
   end Split_At;

   --  Map a movement key to a viewport command, the diff pane's vocabulary.
   --  This mirrors the standalone pager's table so the diff pane feels like
   --  the pager it embeds. Found = False if the key is not a movement.
   procedure Map_Command
     (Event : Key_Event;
      Found : out Boolean;
      Cmd   : out Eng.Command)
   is
   begin
      Found := True;
      Cmd   := Eng.Line_Down;   --  default, overwritten below
      case Event.Kind is
         when Down      => Cmd := Eng.Line_Down;
         when Up        => Cmd := Eng.Line_Up;
         when Page_Down => Cmd := Eng.Page_Down;
         when Page_Up   => Cmd := Eng.Page_Up;
         when Left      => Cmd := Eng.Col_Left;
         when Right     => Cmd := Eng.Col_Right;
         when Home      => Cmd := Eng.To_Top;
         when End_Key   => Cmd := Eng.To_Bottom;
         when Enter     => Cmd := Eng.Line_Down;
         when Char =>
            case Event.Code is
               when Character'Pos ('j') => Cmd := Eng.Line_Down;
               when Character'Pos ('k') => Cmd := Eng.Line_Up;
               when Character'Pos (' ') => Cmd := Eng.Page_Down;
               when Character'Pos ('f') => Cmd := Eng.Page_Down;
               when Character'Pos ('b') => Cmd := Eng.Page_Up;
               when Character'Pos ('d') => Cmd := Eng.Half_Down;
               when Character'Pos ('u') => Cmd := Eng.Half_Up;
               when Character'Pos ('g') => Cmd := Eng.To_Top;
               when Character'Pos ('G') => Cmd := Eng.To_Bottom;
               when Character'Pos ('h') => Cmd := Eng.Col_Left;
               when Character'Pos ('l') => Cmd := Eng.Col_Right;
               when others              => Found := False;
            end case;
         when others => Found := False;
      end case;
   end Map_Command;

   --  Map a movement key to a selection move, the list pane's vocabulary.
   procedure Map_Selection
     (Event : Key_Event;
      Found : out Boolean;
      Move  : out Sel_Move)
   is
   begin
      Found := True;
      Move  := Sel_Down;   --  default, overwritten below
      case Event.Kind is
         when Down      => Move := Sel_Down;
         when Up        => Move := Sel_Up;
         when Page_Down => Move := Sel_Page_Down;
         when Page_Up   => Move := Sel_Page_Up;
         when Home      => Move := Sel_Top;
         when End_Key   => Move := Sel_Bottom;
         when Char =>
            case Event.Code is
               when Character'Pos ('j') => Move := Sel_Down;
               when Character'Pos ('k') => Move := Sel_Up;
               when Character'Pos (' ') => Move := Sel_Page_Down;
               when Character'Pos ('f') => Move := Sel_Page_Down;
               when Character'Pos ('b') => Move := Sel_Page_Up;
               when Character'Pos ('g') => Move := Sel_Top;
               when Character'Pos ('G') => Move := Sel_Bottom;
               when others              => Found := False;
            end case;
         when others => Found := False;
      end case;
   end Map_Selection;

   --------------
   -- Classify --
   --------------

   function Classify
     (Focused : Pane;
      Event   : Tui.Input.Key_Event) return Decision
   is
   begin
      --  Quit: q / Q / Ctrl-C, whichever pane has the keyboard.
      if Event.Kind = Char
        and then (Event.Code = Character'Pos ('q')
                  or else Event.Code = Character'Pos ('Q')
                  or else (Event.Mods.Ctrl
                           and then Event.Code = Character'Pos ('C')))
      then
         return (Kind => Quit);
      end if;

      --  Tab moves the keyboard to the other pane.
      if Event.Kind = Tab then
         return (Kind => Switch_Focus);
      end if;

      if Event.Kind = Char and then Event.Code = Character'Pos ('z') then
         return (Kind => Toggle_Maximize);
      end if;

      if Event.Kind = Char and then Event.Code = Character'Pos (',') then
         return (Kind => Resize_Split, Grow_List => False);
      end if;
      if Event.Kind = Char and then Event.Code = Character'Pos ('.') then
         return (Kind => Resize_Split, Grow_List => True);
      end if;

      --  Syntax colour is a viewer-wide display option, whichever pane has
      --  the keyboard. Diff polarity remains visible in the coloured gutter.
      if Event.Kind = Char and then Event.Code = Character'Pos ('s') then
         return (Kind => Toggle_Syntax);
      end if;

      --  Enter search-input mode; the pattern targets the focused pane.
      if Event.Kind = Char and then Event.Code = Character'Pos ('/') then
         return (Kind => Search, Forward => True);
      end if;
      if Event.Kind = Char and then Event.Code = Character'Pos ('?') then
         return (Kind => Search, Forward => False);
      end if;

      --  Repeat the last search ('n' same direction, 'N' reversed).
      if Event.Kind = Char and then Event.Code = Character'Pos ('n') then
         return (Kind => Repeat_Search, Reversed => False);
      end if;
      if Event.Kind = Char and then Event.Code = Character'Pos ('N') then
         return (Kind => Repeat_Search, Reversed => True);
      end if;

      case Focused is
         when List_Pane =>
            --  Enter drills into the selected commit.
            if Event.Kind = Enter then
               return (Kind => Open_Diff);
            end if;

            --  Long subjects can still be scrolled sideways.
            if Event.Kind = Left
              or else (Event.Kind = Char
                       and then Event.Code = Character'Pos ('h'))
            then
               return (Kind => Navigate, Command => Eng.Col_Left);
            end if;
            if Event.Kind = Right
              or else (Event.Kind = Char
                       and then Event.Code = Character'Pos ('l'))
            then
               return (Kind => Navigate, Command => Eng.Col_Right);
            end if;

            declare
               Found : Boolean;
               Move  : Sel_Move;
            begin
               Map_Selection (Event, Found, Move);
               if Found then
                  return (Kind => Move_Selection, Move => Move);
               end if;
            end;

         when Diff_Pane =>
            if Event.Kind = Char then
               case Event.Code is
                  when Character'Pos (']') =>
                     return (Kind => Jump_Diff,
                             Target => Git_View_Navigation.Hunk_Header,
                             Jump_Forward => True);
                  when Character'Pos ('[') =>
                     return (Kind => Jump_Diff,
                             Target => Git_View_Navigation.Hunk_Header,
                             Jump_Forward => False);
                  when Character'Pos ('}') =>
                     return (Kind => Jump_Diff,
                             Target => Git_View_Navigation.File_Header,
                             Jump_Forward => True);
                  when Character'Pos ('{') =>
                     return (Kind => Jump_Diff,
                             Target => Git_View_Navigation.File_Header,
                             Jump_Forward => False);
                  when others =>
                     null;
               end case;
            end if;
            declare
               Found : Boolean;
               Cmd   : Eng.Command;
            begin
               Map_Command (Event, Found, Cmd);
               if Found then
                  return (Kind => Navigate, Command => Cmd);
               end if;
            end;
      end case;

      return (Kind => Ignore);
   end Classify;

   ------------
   -- Locate --
   ------------

   function Locate
     (Col, Row     : Natural;
      List_Cols    : Natural;
      Diff_Cols    : Natural;
      Content_Rows : Natural) return Region
   is
   begin
      --  The comparisons are phrased as subtractions so they stay provably
      --  in range whatever widths the caller hands in.
      if Row = 0 or else Row > Content_Rows or else Col = 0 then
         return Outside;
      elsif List_Cols > 0 and then Col <= List_Cols then
         return List_Region;
      elsif List_Cols = 0 and then Diff_Cols > 0 and then Col <= Diff_Cols then
         return Diff_Region;
      elsif List_Cols > 0 and then Diff_Cols > 0
        and then Col = List_Cols + 1
      then
         return Separator_Region;
      elsif List_Cols > 0 and then Diff_Cols > 0
        and then Col - List_Cols > 1            --  past the separator column
        and then Col - List_Cols - 1 <= Diff_Cols
      then
         return Diff_Region;
      else
         return Outside;
      end if;
   end Locate;

end Git_View_Policy;
