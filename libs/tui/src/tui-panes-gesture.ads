--  Tui.Panes.Gesture — recognising what the mouse is doing, and nothing more.
--
--  The mouse code in a terminal application fuses three separable things:
--  transport (which pane, which document coordinate), recognition
--  (press-drag-release is a range; press on a separator then drag is a
--  resize), and consequence (a click opens the commit under the cursor).
--  Recognition is mechanism and lives here; consequence is application policy
--  and stays with the application, which reads the described gesture and
--  decides what it means.
--
--  The contentious choices are not baked in either. Whether the wheel follows
--  the cursor or the keyboard, whether a drag may leave the pane it started
--  in, and whether Shift hands the drag back to the terminal are fields of a
--  Policy record the host fills in, so that two frontends of the same program
--  differ on purpose rather than by accident.
--
--  The recognizer never sees a document. It is handed each pane's scroll
--  offsets and line total as a Frame, which is all that turning a screen cell
--  into a document position needs, and which leaves document ownership — and
--  the proof leverage that comes with it — in the host.

with Tui.Input;
with Tui.Text;
with Tui.Pager;
with Tui.Panes.Layout;
with Tui.Panes.Selection;

package Tui.Panes.Gesture
  with SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Declared policy
   ---------------------------------------------------------------------------

   type Wheel_Target is
     (Pane_Under_Cursor,        --  the desktop convention: hover and scroll
      Focused_Pane,             --  keyboard-centric: the wheel follows Tab
      Under_Cursor_And_Focus);  --  scrolling a pane also gives it the keyboard

   type Policy is record
      Wheel             : Wheel_Target := Pane_Under_Cursor;
      Wheel_Notch_Lines : Positive := 3;
      Click_Focuses     : Boolean := True;
      Drag_Selects      : Boolean := True;
      Separator_Drag    : Boolean := True;

      --  A drag records the pane it started in and ignores motion elsewhere.
      Drag_Crosses_Panes : Boolean := False;

      --  With mouse tracking on, the terminal's own selection is unreachable,
      --  so a user cannot select across panes or into a status bar. Most
      --  terminals reserve Shift-drag for exactly that; ignoring shifted
      --  reports hands those back.
      Shift_Bypasses : Boolean := True;
   end record;

   ---------------------------------------------------------------------------
   --  What the host tells the recognizer about each pane
   ---------------------------------------------------------------------------

   type Frame is record
      Top   : Tui.Text.Line_Number := 1;   --  Tui.Pager.Engine.Top_Line
      Left  : Tui.Pager.Dimension := 0;   --  Tui.Pager.Engine.Left_Col
      Total : Tui.Text.Line_Total := 0;   --  Tui.Text.Line_Count
   end record;

   type Frame_Array is array (Pane_Index range <>) of Frame;

   ---------------------------------------------------------------------------
   --  What the recognizer tells the host
   ---------------------------------------------------------------------------

   type Gesture_Kind is
     (None,
      Click,              --  a press, before it is known to be a drag
      Range_Extended,     --  a drag in progress; First/Last have moved
      Range_Committed,    --  released with a range to copy
      Range_Cancelled,    --  released with nothing; a shown range is gone
      Separator_Dragged,  --  a boundary wants to move to Split_Col
      Wheel);

   type Gesture is record
      Kind : Gesture_Kind := None;

      --  Click, Range_*, Wheel: the pane concerned. Separator_Dragged: the
      --  pane to the left of the boundary being moved.
      Pane : Pane_Index := 1;

      --  Click: where in the pane's own frame, and the document line under
      --  it when the pane has one there.
      Local_Row : Natural := 0;
      Local_Col : Natural := 0;
      At_Line   : Tui.Text.Line_Number := 1;
      On_Line   : Boolean := False;

      --  Range_Extended and Range_Committed: the selection in document
      --  order, ready for Clip.Extract or Highlight.Overlay.
      First, Last : Selection.Position;

      --  Separator_Dragged: the screen column the boundary was dragged to.
      Split_Col : Natural := 0;

      --  Wheel.
      Notches : Positive := 1;
      Upward  : Boolean := False;

      --  Whether this gesture also asks for the keyboard, under the policy
      --  the host declared.
      Takes_Focus : Boolean := False;
   end record;

   ---------------------------------------------------------------------------
   --  The recognizer
   ---------------------------------------------------------------------------

   type Recognizer is private;
   --  Default-initialised to "nothing in progress"; just declare one.

   --  A selection the host should paint, held between events. Kept in
   --  document coordinates, so repainting and horizontal scrolling do not
   --  corrupt it.
   function Has_Selection (R : Recognizer) return Boolean
   with Global => null;

   function Selected_Pane (R : Recognizer) return Pane_Index
   with Global => null;

   procedure Selected_Range
     (R : Recognizer; First, Last : out Selection.Position)
   with Global => null, Post => Selection.Before_Or_Equal (First, Last);

   --  Forget any selection and abandon any drag. Hosts call this when the
   --  documents underneath change out from under a retained selection.
   procedure Reset (R : in out Recognizer)
   with Global => null, Post => not Has_Selection (R);

   --  Interpret one mouse event against the layout the painter recorded.
   --  Non-mouse events, and events the policy hands back to the terminal,
   --  yield a gesture of kind None and leave the recognizer alone.
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
   with
     Global => null,
     Pre    =>
       Placements'Length > 0
       and then Placements'First = Pane_Index'First
       and then Frames'First = Placements'First
       and then Frames'Last = Placements'Last
       and then Focused in Placements'Range,
     Post   =>
       Result.Pane in Placements'Range
       and then Selected_Pane (R) in Placements'Range
       and then (if Result.Kind in Range_Extended | Range_Committed
                 then Selection.Before_Or_Equal (Result.First, Result.Last))
       and then (if Result.On_Line
                 then Result.At_Line <= Frames (Result.Pane).Total);

private

   type Recognizer is record
      --  A drag is under way; the button has not come up yet.
      Dragging  : Boolean := False;
      --  A range large enough to be worth showing; a click without motion
      --  is not displayed as a one-cell selection.
      Showing   : Boolean := False;
      Pane      : Pane_Index := 1;
      Anchor    : Selection.Position;
      Live      : Selection.Position;
      --  A separator drag is under way, and which boundary it moves.
      Resizing  : Boolean := False;
      Separator : Pane_Index := 1;
   end record;

   function Has_Selection (R : Recognizer) return Boolean
   is (R.Showing);
   function Selected_Pane (R : Recognizer) return Pane_Index
   is (R.Pane);

end Tui.Panes.Gesture;
