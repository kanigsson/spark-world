package body Tui.Panes.Gesture with SPARK_Mode => On is

   use Tui.Input;
   use type Layout.Hit_Kind;
   use type Selection.Position;

   --------------------
   -- Selected_Range --
   --------------------

   procedure Selected_Range
     (R           : Recognizer;
      First, Last : out Selection.Position)
   is
   begin
      Selection.Ordered (R.Anchor, R.Live, First, Last);
   end Selected_Range;

   -----------
   -- Reset --
   -----------

   procedure Reset (R : in out Recognizer) is
   begin
      R.Dragging := False;
      R.Showing  := False;
      R.Resizing := False;
   end Reset;

   ----------
   -- Feed --
   ----------

   procedure Feed
     (R            : in out Recognizer;
      Event        : Tui.Input.Key_Event;
      Placements   : Layout.Placement_Array;
      Frames       : Frame_Array;
      First_Row    : Positive;
      Content_Rows : Natural;
      Focused      : Pane_Index;
      Rules        : Policy;
      Result       : out Gesture)
   is
      Where : Layout.Hit;

      --  Turn a hit into a document position in its pane. A row past the end
      --  of that pane's document has no position; the cursor is over blank
      --  space below the text.
      procedure Document_Position
        (H     : Layout.Hit;
         Pos   : out Selection.Position;
         Valid : out Boolean)
      with Global => (Input => Frames),
           Pre    => (if H.Kind = Layout.Pane_Hit
                      then H.Local_Row >= 1 and then H.Local_Col >= 1),
           Post   => (if Valid then Pos.Line <= Frames (H.Pane).Total)
      is
         F : Frame;
      begin
         Pos   := (Line => 1, Col => 0);
         Valid := False;
         if H.Kind /= Layout.Pane_Hit or else H.Pane not in Frames'Range then
            return;
         end if;
         F := Frames (H.Pane);
         if F.Top <= F.Total and then H.Local_Row - 1 <= F.Total - F.Top then
            Pos.Line := F.Top + (H.Local_Row - 1);
            Pos.Col  :=
              Natural'Min (Tui.Pager.Max_Dim, F.Left + H.Local_Col - 1);
            Valid    := True;
         end if;
      end Document_Position;

   begin
      Result := (Kind => None, Pane => Placements'First, others => <>);

      --  A row that no longer has the pane a drag was in cannot describe
      --  that drag any more; abandon it rather than report a stale pane.
      if R.Pane not in Placements'Range
        or else R.Separator not in Placements'Range
      then
         R.Dragging  := False;
         R.Showing   := False;
         R.Resizing  := False;
         R.Pane      := Placements'First;
         R.Separator := Placements'First;
      end if;

      if Event.Kind not in
        Mouse_Press | Mouse_Release | Mouse_Motion | Wheel_Up | Wheel_Down
      then
         return;
      end if;

      --  Hand shifted reports back to the terminal, whose own selection is
      --  otherwise unreachable while tracking is on.
      if Rules.Shift_Bypasses and then Event.Mods.Shift then
         return;
      end if;

      Where :=
        Layout.Locate (Placements, First_Row, Content_Rows,
                       Event.Col, Event.Row);

      ------------------------------------------------------------------
      --  A separator drag in progress owns every event until the button
      --  comes up, wherever the pointer has wandered to.
      ------------------------------------------------------------------
      if R.Resizing then
         if Event.Kind = Mouse_Motion and then Event.Button = Left_Button then
            Result := (Kind      => Separator_Dragged,
                       Pane      => R.Separator,
                       Split_Col => Event.Col,
                       others    => <>);
         elsif Event.Kind = Mouse_Release then
            R.Resizing := False;
         end if;
         return;
      end if;

      if Where.Kind = Layout.Separator_Hit then
         if Rules.Separator_Drag
           and then Event.Kind = Mouse_Press
           and then Event.Button = Left_Button
         then
            R.Resizing  := True;
            R.Separator := Where.Pane;
            R.Dragging  := False;
            R.Showing   := False;
            --  Arming only: the boundary has not moved yet, and reporting
            --  the column it is already at would jitter the layout.
         end if;
         return;
      end if;

      --  The wheel is answered before the "off the panes" test, because a
      --  host whose wheel follows the keyboard has a target wherever the
      --  pointer happens to be.
      if Event.Kind in Wheel_Up | Wheel_Down then
         --  Scrolling moves the text out from under a retained selection,
         --  so the selection goes rather than becoming wrong.
         R.Dragging := False;
         R.Showing  := False;
         if Rules.Wheel = Focused_Pane then
            Result := (Kind    => Wheel,
                       Pane    => Focused,
                       Notches => Rules.Wheel_Notch_Lines,
                       Upward  => Event.Kind = Wheel_Up,
                       others  => <>);
         elsif Where.Kind = Layout.Pane_Hit then
            Result :=
              (Kind        => Wheel,
               Pane        => Where.Pane,
               Notches     => Rules.Wheel_Notch_Lines,
               Upward      => Event.Kind = Wheel_Up,
               Takes_Focus => Rules.Wheel = Under_Cursor_And_Focus,
               others      => <>);
         end if;
         return;
      end if;

      if Where.Kind = Layout.Nowhere then
         --  A button released off the panes ends the drag without copying.
         if Event.Kind = Mouse_Release and then R.Dragging then
            R.Dragging := False;
            if R.Showing then
               R.Showing := False;
               Result := (Kind => Range_Cancelled, Pane => R.Pane,
                          others => <>);
            end if;
         end if;
         return;
      end if;

      case Event.Kind is
         when Mouse_Press =>
            if Event.Button /= Left_Button then
               return;
            end if;
            declare
               Pos   : Selection.Position;
               Valid : Boolean;
            begin
               Document_Position (Where, Pos, Valid);
               R.Showing := False;
               if Rules.Drag_Selects and then Valid then
                  R.Dragging := True;
                  R.Pane     := Where.Pane;
                  R.Anchor   := Pos;
                  R.Live     := Pos;
               else
                  R.Dragging := False;
               end if;
               Result := (Kind        => Click,
                          Pane        => Where.Pane,
                          Local_Row   => Where.Local_Row,
                          Local_Col   => Where.Local_Col,
                          At_Line     => Pos.Line,
                          On_Line     => Valid,
                          Takes_Focus => Rules.Click_Focuses,
                          others      => <>);
            end;

         when Mouse_Motion =>
            if R.Dragging and then Event.Button = Left_Button
              and then (Rules.Drag_Crosses_Panes
                        or else Where.Pane = R.Pane)
            then
               declare
                  Pos   : Selection.Position;
                  Valid : Boolean;
               begin
                  Document_Position (Where, Pos, Valid);
                  if Valid and then Pos /= R.Live then
                     R.Live    := Pos;
                     R.Showing := Pos /= R.Anchor;
                     Result := (Kind   => Range_Extended,
                                Pane   => R.Pane,
                                others => <>);
                     Selection.Ordered
                       (R.Anchor, R.Live, Result.First, Result.Last);
                  end if;
               end;
            end if;

         when Mouse_Release =>
            if R.Dragging and then Event.Button = Left_Button then
               declare
                  Pos   : Selection.Position;
                  Valid : Boolean;
               begin
                  Document_Position (Where, Pos, Valid);
                  if Valid
                    and then (Rules.Drag_Crosses_Panes
                              or else Where.Pane = R.Pane)
                  then
                     R.Live    := Pos;
                     R.Showing := Pos /= R.Anchor;
                  end if;
                  R.Dragging := False;
                  if R.Showing then
                     Result := (Kind   => Range_Committed,
                                Pane   => R.Pane,
                                others => <>);
                     Selection.Ordered
                       (R.Anchor, R.Live, Result.First, Result.Last);
                  else
                     Result := (Kind => Range_Cancelled, Pane => R.Pane,
                                others => <>);
                  end if;
               end;
            end if;


         when others =>
            null;
      end case;
   end Feed;

end Tui.Panes.Gesture;
