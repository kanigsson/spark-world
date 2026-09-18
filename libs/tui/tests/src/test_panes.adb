--  Behavioural tests for the pane layer. Complements gnatprove: proof shows
--  the contracts hold for all inputs; these pin the decisions — which pane a
--  narrow row keeps, what a drag across two rows copies, which pane the wheel
--  scrolls under each declared policy.
--
--  The gesture recognizer, the selection-to-viewport coupling and the
--  clipboard encoder were the parts of this layer that had no tests while
--  they lived inside a frontend, because testing them there would have meant
--  writing them twice. They have one home now, so they are tested here.

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Tui.Input;
with Tui.Pager.Engine;
with Tui.Surface; use Tui.Surface;
with Tui.Text;
with Tui.Panes;   use Tui.Panes;
with Tui.Panes.Clip;
with Tui.Panes.Gesture;
with Tui.Panes.Highlight;
with Tui.Panes.Layout;
with Tui.Panes.List;
with Tui.Panes.Selection;

procedure Test_Panes is

   package Lay renames Tui.Panes.Layout;
   package Sel renames Tui.Panes.Selection;
   package Gest renames Tui.Panes.Gesture;
   package Clip renames Tui.Panes.Clip;
   package Mark renames Tui.Panes.Highlight;
   package PList renames Tui.Panes.List;
   package Eng renames Tui.Pager.Engine;

   use type Lay.Hit_Kind;
   use type Gest.Gesture_Kind;
   use type Tui.Panes.Pane_Index;
   use type Eng.Effect;
   use type Sel.Position;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("  ok   : " & Label);
      else
         Put_Line ("  FAIL : " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   --  A byte buffer over literal text, 1-based as the buffer contracts want.
   function Bytes (S : String) return Tui.Text.Buffer is
      B : Tui.Text.Buffer (1 .. S'Length);
   begin
      for I in S'Range loop
         B (1 + (I - S'First)) := Tui.Text.Byte (Character'Pos (S (I)));
      end loop;
      return B;
   end Bytes;

   function Text_Of (P : Clip.Payload) return String is
      Q : constant Natural := Clip.Quartet_Count (P);
      R : String (1 .. Q * 4);
   begin
      for N in 1 .. Q loop
         R (N * 4 - 3 .. N * 4) := Clip.Encode (P, N);
      end loop;
      return R;
   end Text_Of;

   function Mouse
     (Kind   : Tui.Input.Key_Kind;
      Col    : Natural;
      Row    : Natural;
      Button : Tui.Input.Mouse_Button := Tui.Input.Left_Button;
      Shift  : Boolean := False) return Tui.Input.Key_Event
   is ((Kind   => Kind,
        Mods   => (Shift => Shift, others => False),
        Code   => 0,
        Button => Button,
        Col    => Col,
        Row    => Row));

begin
   ---------------------------------------------------------------------------
   --  Selection ordering
   ---------------------------------------------------------------------------
   declare
      A           : constant Sel.Position := (Line => 5, Col => 2);
      B           : constant Sel.Position := (Line => 3, Col => 9);
      First, Last : Sel.Position;
   begin
      Sel.Ordered (A, B, First, Last);
      Check
        (First = B and then Last = A,
         "a drag upwards is the same selection as one made downwards");
      Sel.Ordered (A, A, First, Last);
      Check (First = A and then Last = A, "a one-cell drag orders trivially");
      Sel.Ordered ((3, 9), (3, 2), First, Last);
      Check
        (First.Col = 2 and then Last.Col = 9,
         "within one line the leftmost column comes first");
   end;

   ---------------------------------------------------------------------------
   --  Layout: weights, minima, drop order, exact cover
   ---------------------------------------------------------------------------
   declare
      Spec : constant Lay.Specs_Array (1 .. 3) :=
        (1 => (Weight => 30, Min_Cols => 20, Priority => 1),
         2 => (Weight => 25, Min_Cols => 20, Priority => 2),
         3 => (Weight => 45, Min_Cols => 20, Priority => 0));
      P    : Lay.Placement_Array (1 .. 3);
   begin
      Lay.Compute (Spec, 100, 1, False, True, Lay.Drop_By_Priority, P);
      Check
        (P (1).Cols + P (2).Cols + P (3).Cols + 2 = 100,
         "the panes and their separators cover the width exactly");
      Check
        (P (1).Start_Col = 1
         and then P (2).Start_Col = P (1).Cols + 2
         and then P (3).Start_Col = P (1).Cols + P (2).Cols + 3,
         "each pane starts one separator past its predecessor");
      Check
        (P (1).Cols = 30 and then P (2).Cols = 25,
         "a pane takes its declared share of the width");

      --  Without separators the panes are flush and still cover exactly.
      Lay.Compute (Spec, 100, 1, False, False, Lay.Drop_By_Priority, P);
      Check
        (P (1).Cols + P (2).Cols + P (3).Cols = 100
         and then P (2).Start_Col = P (1).Cols + 1,
         "a row without separators is flush and still covers the width");

      --  Too narrow for three: the highest priority gives up its place.
      Lay.Compute (Spec, 55, 1, False, True, Lay.Drop_By_Priority, P);
      Check
        (P (2).Cols = 0 and then P (1).Cols > 0 and then P (3).Cols > 0,
         "the most disposable pane gives up its place first");
      Check
        (P (1).Cols + P (3).Cols + 1 = 55,
         "what remains still covers the width exactly");

      --  Keep_Focused protects the pane with the keyboard instead.
      Lay.Compute (Spec, 30, 2, False, True, Lay.Keep_Focused, P);
      Check
        (P (2).Cols = 30 and then P (1).Cols = 0 and then P (3).Cols = 0,
         "under Keep_Focused the last pane standing is the focused one");
      Check (Lay.Rescue_Focus (P, 2) = 2, "a shown pane keeps the keyboard");
      Check
        (Lay.Rescue_Focus (P, 1) = 2,
         "focus is rescued onto the leftmost pane that survived");

      --  A pane narrower than its own minimum is still shown when it is the
      --  only one: a squeezed pane beats an empty screen.
      Lay.Compute (Spec, 5, 3, False, True, Lay.Keep_Focused, P);
      Check (P (3).Cols = 5, "the last pane standing takes whatever is left");

      Lay.Compute (Spec, 0, 1, False, True, Lay.Drop_By_Priority, P);
      Check
        (P (1).Cols = 0 and then P (2).Cols = 0 and then P (3).Cols = 0,
         "a zero-width terminal paints nothing");

      Lay.Compute (Spec, 100, 2, True, True, Lay.Drop_By_Priority, P);
      Check
        (P (2).Cols = 100
         and then P (2).Start_Col = 1
         and then P (1).Cols = 0
         and then P (3).Cols = 0,
         "maximizing gives the whole width to the focused pane");
   end;

   ---------------------------------------------------------------------------
   --  Hit-testing returns pane-local coordinates
   ---------------------------------------------------------------------------
   declare
      P : Lay.Placement_Array (1 .. 2) :=
        (1 => (Start_Col => 1, Cols => 10), 2 => (Start_Col => 12, Cols => 8));
      H : Lay.Hit;
   begin
      H := Lay.Locate (P, 1, 5, Col => 12, Row => 3);
      Check
        (H.Kind = Lay.Pane_Hit
         and then H.Pane = 2
         and then H.Local_Col = 1
         and then H.Local_Row = 3,
         "the second pane's first column is its own column 1");
      H := Lay.Locate (P, 1, 5, Col => 11, Row => 1);
      Check
        (H.Kind = Lay.Separator_Hit and then H.Pane = 1,
         "a separator names the pane to its left");
      H := Lay.Locate (P, 3, 5, Col => 1, Row => 3);
      Check
        (H.Kind = Lay.Pane_Hit and then H.Local_Row = 1,
         "the first content row is local row 1 wherever it is on screen");
      Check
        (Lay.Locate (P, 3, 5, 1, 2).Kind = Lay.Nowhere,
         "a row reserved for chrome is nowhere");
      Check
        (Lay.Locate (P, 1, 5, 21, 1).Kind = Lay.Nowhere,
         "past the last pane is nowhere");
      Check
        (Lay.Locate (P, 1, 5, 0, 1).Kind = Lay.Nowhere,
         "a report with no position is nowhere");

      --  The column past the RIGHTMOST pane is not a separator: there is
      --  nothing on the other side of it to drag against.
      P (2) := (Start_Col => 0, Cols => 0);
      Check
        (Lay.Locate (P, 1, 5, 11, 1).Kind = Lay.Nowhere,
         "the column past a lone pane is not a separator");
   end;

   ---------------------------------------------------------------------------
   --  The gesture recognizer
   ---------------------------------------------------------------------------
   declare
      P           : constant Lay.Placement_Array (1 .. 2) :=
        (1 => (Start_Col => 1, Cols => 10), 2 => (Start_Col => 12, Cols => 8));
      F           : constant Gest.Frame_Array (1 .. 2) :=
        (1 => (Top => 1, Left => 0, Total => 4),
         2 => (Top => 3, Left => 5, Total => 100));
      Rules       : constant Gest.Policy := (others => <>);
      R           : Gest.Recognizer;
      G           : Gest.Gesture;
      First, Last : Sel.Position;
   begin
      --  A press reports a click and the document line under it.
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Press, 3, 2), P, F, 1, 5, 1, Rules, G);
      Check
        (G.Kind = Gest.Click
         and then G.Pane = 1
         and then G.On_Line
         and then G.At_Line = 2
         and then G.Takes_Focus,
         "a press is a click on the line under it, and takes the keyboard");

      --  A drag reports a range, in document order, and only once it moves.
      Check (not Gest.Has_Selection (R), "a press alone is not a selection");
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Motion, 6, 4), P, F, 1, 5, 1, Rules, G);
      Check
        (G.Kind = Gest.Range_Extended
         and then G.First = (Line => 2, Col => 2)
         and then G.Last = (Line => 4, Col => 5),
         "a drag extends a range in document coordinates");
      Check
        (Gest.Has_Selection (R) and then Gest.Selected_Pane (R) = 1,
         "the range is retained for the host to paint");

      --  Motion into another pane is ignored: the drag stays where it began.
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Motion, 14, 4), P, F, 1, 5, 1, Rules, G);
      Check (G.Kind = Gest.None, "a drag does not cross a pane boundary");
      Gest.Selected_Range (R, First, Last);
      Check
        (Last = (Line => 4, Col => 5),
         "a drag that left its pane keeps the range it had");

      --  Releasing commits it.
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Release, 6, 4), P, F, 1, 5, 1, Rules, G);
      Check
        (G.Kind = Gest.Range_Committed and then G.Pane = 1,
         "releasing commits the range");

      --  A press and release without motion is a click, not a selection.
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Press, 3, 2), P, F, 1, 5, 1, Rules, G);
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Release, 3, 2), P, F, 1, 5, 1, Rules, G);
      Check
        (G.Kind = Gest.Range_Cancelled and then not Gest.Has_Selection (R),
         "a click without motion copies nothing");

      --  A press below the end of the document focuses but names no line.
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Press, 3, 5), P, F, 1, 5, 1, Rules, G);
      Check
        (G.Kind = Gest.Click and then not G.On_Line,
         "a press below the text is still a click on the pane");

      --  Shift hands the drag back to the terminal.
      Gest.Feed
        (R,
         Mouse (Tui.Input.Mouse_Press, 3, 2, Shift => True),
         P,
         F,
         1,
         5,
         1,
         Rules,
         G);
      Check (G.Kind = Gest.None, "Shift bypasses tracking");

      --  A separator press arms a resize; motion then moves the boundary,
      --  wherever the pointer has wandered to.
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Press, 11, 2), P, F, 1, 5, 1, Rules, G);
      Check (G.Kind = Gest.None, "pressing a separator moves nothing yet");
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Motion, 15, 2), P, F, 1, 5, 1, Rules, G);
      Check
        (G.Kind = Gest.Separator_Dragged
         and then G.Pane = 1
         and then G.Split_Col = 15,
         "dragging a separator reports the column it moved to");
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Motion, 90, 2), P, F, 1, 5, 1, Rules, G);
      Check
        (G.Kind = Gest.Separator_Dragged,
         "a separator drag keeps going past the panes");
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Release, 90, 2), P, F, 1, 5, 1, Rules, G);
      Gest.Feed
        (R, Mouse (Tui.Input.Mouse_Motion, 15, 2), P, F, 1, 5, 1, Rules, G);
      Check (G.Kind = Gest.None, "releasing ends the separator drag");
   end;

   ---------------------------------------------------------------------------
   --  Wheel policy: the divergence the two frontends had, now declared
   ---------------------------------------------------------------------------
   declare
      P : constant Lay.Placement_Array (1 .. 2) :=
        (1 => (Start_Col => 1, Cols => 10), 2 => (Start_Col => 12, Cols => 8));
      F : constant Gest.Frame_Array (1 .. 2) :=
        (others => (Top => 1, Left => 0, Total => 50));
      R : Gest.Recognizer;
      G : Gest.Gesture;
   begin
      Gest.Feed
        (R,
         Mouse (Tui.Input.Wheel_Down, 14, 2),
         P,
         F,
         1,
         5,
         Focused => 1,
         Rules   => (Wheel => Gest.Pane_Under_Cursor, others => <>),
         Result  => G);
      Check
        (G.Kind = Gest.Wheel
         and then G.Pane = 2
         and then not G.Takes_Focus
         and then not G.Upward
         and then G.Notches = 3,
         "the wheel scrolls the pane under the cursor without the keyboard");

      Gest.Feed
        (R,
         Mouse (Tui.Input.Wheel_Up, 14, 2),
         P,
         F,
         1,
         5,
         Focused => 1,
         Rules   => (Wheel => Gest.Focused_Pane, others => <>),
         Result  => G);
      Check
        (G.Kind = Gest.Wheel and then G.Pane = 1 and then G.Upward,
         "a keyboard-centric wheel scrolls the focused pane instead");

      Gest.Feed
        (R,
         Mouse (Tui.Input.Wheel_Down, 14, 2),
         P,
         F,
         1,
         5,
         Focused => 1,
         Rules   => (Wheel => Gest.Under_Cursor_And_Focus, others => <>),
         Result  => G);
      Check
        (G.Kind = Gest.Wheel and then G.Pane = 2 and then G.Takes_Focus,
         "the third policy scrolls under the cursor and takes the keyboard");

      --  A wheel report off the panes has no target under the cursor.
      Gest.Feed
        (R,
         Mouse (Tui.Input.Wheel_Down, 40, 2),
         P,
         F,
         1,
         5,
         Focused => 1,
         Rules   => (Wheel => Gest.Pane_Under_Cursor, others => <>),
         Result  => G);
      Check (G.Kind = Gest.None, "a wheel over nothing scrolls nothing");
      Gest.Feed
        (R,
         Mouse (Tui.Input.Wheel_Down, 40, 2),
         P,
         F,
         1,
         5,
         Focused => 2,
         Rules   => (Wheel => Gest.Focused_Pane, others => <>),
         Result  => G);
      Check
        (G.Kind = Gest.Wheel and then G.Pane = 2,
         "a keyboard-centric wheel has a target wherever the pointer is");
   end;

   ---------------------------------------------------------------------------
   --  The clipboard encoder
   ---------------------------------------------------------------------------
   declare
      Content : constant Tui.Text.Buffer :=
        Bytes ("alpha" & ASCII.LF & "beta" & ASCII.LF & "gamma" & ASCII.LF);
      Idx     : Tui.Text.Index (Capacity => 8);
      Text    : Clip.Payload;
      Cut     : Boolean;
   begin
      Tui.Text.Scan (Idx, Content);
      Tui.Text.Seal (Idx, Content);

      --  A range within one line.
      Clip.Extract (Content, Idx, (1, 1), (1, 3), Text, Cut);
      Check
        (Clip.Length (Text) = 3 and then not Cut,
         "a one-line range copies the cells it covers");
      Check (Text_Of (Text) = "bHBo", "the payload is base64 of ""lph""");

      --  A range across lines is joined with a newline.
      Clip.Extract (Content, Idx, (1, 3), (2, 1), Text, Cut);
      Check
        (Text_Of (Text) = "aGEKYmU=",
         "a two-line range is joined with one newline (""ha"" LF ""be"")");

      --  The end point is exclusive of nothing: the cell under Last is in.
      Clip.Extract (Content, Idx, (2, 0), (2, 3), Text, Cut);
      Check
        (Clip.Length (Text) = 4, "the cell under the last column is copied");

      --  Padding: a payload whose length is not a multiple of three.
      Clip.Extract (Content, Idx, (1, 0), (1, 0), Text, Cut);
      Check (Text_Of (Text) = "YQ==", "a single byte pads its quartet");
      Clip.Extract (Content, Idx, (1, 0), (1, 1), Text, Cut);
      Check (Text_Of (Text) = "YWw=", "two bytes pad one place");
      Clip.Extract (Content, Idx, (1, 0), (1, 2), Text, Cut);
      Check (Text_Of (Text) = "YWxw", "three bytes need no padding");
   end;

   ---------------------------------------------------------------------------
   --  Selection-to-viewport coupling
   ---------------------------------------------------------------------------
   declare
      Content  : Tui.Text.Buffer (1 .. 200);
      Idx      : Tui.Text.Index (Capacity => 64);
      E        : Eng.Instance;
      Sel_Line : Tui.Text.Line_Number := 1;
      Moved    : Boolean;
   begin
      --  Fifty one-character lines.
      for I in 1 .. 50 loop
         Content (I * 2 - 1) := Tui.Text.Byte (Character'Pos ('x'));
         Content (I * 2) := Tui.Text.Byte (Character'Pos (ASCII.LF));
      end loop;
      Tui.Text.Scan (Idx, Content (1 .. 100));
      Tui.Text.Seal (Idx, Content (1 .. 100));
      Eng.Resize (E, Rows => 10, Cols => 20, Total => 50);

      --  Moving down inside the visible slice does not scroll.
      for Step in 1 .. 9 loop
         PList.Move
           (E, PList.Sel_Down, Content (1 .. 100), Idx, Sel_Line, Moved);
      end loop;
      Check
        (Sel_Line = 10 and then Eng.Top_Line (E) = 1,
         "the selection moves without dragging the viewport");

      --  The step that would leave the screen drags it along by one.
      PList.Move (E, PList.Sel_Down, Content (1 .. 100), Idx, Sel_Line, Moved);
      Check
        (Sel_Line = 11 and then Eng.Top_Line (E) = 2 and then Moved,
         "leaving the screen drags the viewport by one line");

      --  A page move takes the selection with the viewport.
      PList.Move
        (E, PList.Sel_Page_Down, Content (1 .. 100), Idx, Sel_Line, Moved);
      Check
        (Sel_Line >= Eng.Top_Line (E)
         and then Sel_Line <= Eng.Last_Visible (E, 50),
         "a page move leaves the selection on screen");

      PList.Move
        (E, PList.Sel_Bottom, Content (1 .. 100), Idx, Sel_Line, Moved);
      Check (Sel_Line = 50, "Sel_Bottom selects the last line");
      PList.Move (E, PList.Sel_Down, Content (1 .. 100), Idx, Sel_Line, Moved);
      Check
        (Sel_Line = 50 and then not Moved,
         "the selection does not run off the end");

      --  A viewport jump the selection did not cause pulls it back.
      declare
         Res : Eng.Effect;
      begin
         Eng.Handle (E, Eng.To_Top, Content (1 .. 100), Idx, Res);
         Check (Res /= Eng.Unchanged, "the viewport jumped home");
      end;
      PList.Clamp (E, 50, Sel_Line);
      Check
        (Sel_Line = 10, "a viewport jump pulls the selection back into view");

      --  Reveal is the other direction: the viewport follows a selection set
      --  from outside, and moves as little as will show it.
      Eng.Resize (E, Rows => 10, Cols => 20, Total => 50);
      Eng.Go_To_Line (E, 20, 50);
      PList.Reveal (E, 25, 50);
      Check
        (Eng.Top_Line (E) = 20,
         "revealing a line already on screen scrolls nothing");
      PList.Reveal (E, 34, 50);
      Check
        (Eng.Top_Line (E) = 25,
         "a line below the slice becomes its last row, no further");
      PList.Reveal (E, 12, 50);
      Check
        (Eng.Top_Line (E) = 12,
         "a line above the slice becomes its first row");

      --  The head of a list stays visible when the row just below it is
      --  selected by name -- the worktree and index rows of a history pane.
      Eng.Go_To_Line (E, 1, 50);
      PList.Reveal (E, 2, 50);
      Check
        (Eng.Top_Line (E) = 1,
         "selecting the second row keeps the first one on screen");
   end;

   ---------------------------------------------------------------------------
   --  Overlays
   ---------------------------------------------------------------------------
   declare
      S : Surface := Blank (3, 4);
   begin
      Mark.Row (S, 2);
      Check
        (Get (S, 2, 1).Attributes.Inverse
         and then not Get (S, 1, 1).Attributes.Inverse,
         "a highlighted row is inverse across its width");

      --  The selection overlay TOGGLES inverse, so it stays visible where it
      --  crosses a row that is already inverse.
      Mark.Overlay
        (S,
         Top   => 1,
         Left  => 0,
         First => (Line => 2, Col => 0),
         Last  => (Line => 2, Col => 3));
      Check
        (not Get (S, 2, 1).Attributes.Inverse,
         "a selection over an inverse row toggles back to normal");
      Mark.Overlay
        (S,
         Top   => 1,
         Left  => 0,
         First => (Line => 1, Col => 1),
         Last  => (Line => 1, Col => 2));
      Check
        (not Get (S, 1, 1).Attributes.Inverse
         and then Get (S, 1, 2).Attributes.Inverse
         and then Get (S, 1, 3).Attributes.Inverse
         and then not Get (S, 1, 4).Attributes.Inverse,
         "a selection covers exactly the columns it names");

      --  A multi-line selection runs to the end of its first row and from
      --  the start of its last.
      declare
         T : Surface := Blank (3, 4);
      begin
         Mark.Overlay
           (T,
            Top   => 1,
            Left  => 0,
            First => (Line => 1, Col => 2),
            Last  => (Line => 3, Col => 1));
         Check
           (not Get (T, 1, 2).Attributes.Inverse
            and then Get (T, 1, 3).Attributes.Inverse
            and then Get (T, 2, 1).Attributes.Inverse
            and then Get (T, 2, 4).Attributes.Inverse
            and then Get (T, 3, 2).Attributes.Inverse
            and then not Get (T, 3, 3).Attributes.Inverse,
            "a multi-line selection runs to and from the row edges");
      end;

      --  The viewport's horizontal offset shifts what a column means.
      declare
         T : Surface := Blank (1, 4);
      begin
         Mark.Overlay
           (T,
            Top   => 1,
            Left  => 5,
            First => (Line => 1, Col => 6),
            Last  => (Line => 1, Col => 6));
         Check
           (Get (T, 1, 2).Attributes.Inverse
            and then not Get (T, 1, 1).Attributes.Inverse,
            "a scrolled pane maps document columns onto its own cells");
      end;
   end;

   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " CHECKS FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Panes;
