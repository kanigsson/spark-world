with Tui.Surface;                                use Tui.Surface;
with Tui.Input;                                  use Tui.Input;
with Tui.Text;
with Tui.Pager.Engine;
with Git_View_Policy;
with Git_View_List;
with Git_View_Sha;
with Git_View_Source;
with Git_View_Search_Input;
with Git_View_Status;
with Git_View_Theme;

package body Git_View_App with
  SPARK_Mode    => On,
  Refined_State =>
    (State =>
       (List_Doc, Diff_Doc, List_Eng, Diff_Eng, Selected, Diff_Id,
        Focused, Searching, Forward, Pattern, Note,
        List_Width, Diff_Width, View_Rows))
is

   package Eng_Pkg renames Tui.Pager.Engine;
   package Pol renames Git_View_Policy;
   package Thm renames Git_View_Theme;
   use type Eng_Pkg.Effect;
   use type Pol.Pane;
   use type Pol.Region;
   use type Git_View_Status.Note;
   use type Tui.Text.Doc_Ref;

   ---------------------------------------------------------------------------
   --  State (set by Init, then driven by the callbacks)
   --
   --  Both documents are Tui.Text.Documents held by their owning references:
   --  buffer and line index bundled under one predicate (the index never
   --  scans past the buffer), which discharges the engines' content
   --  contracts at every call. The list is loaded once and never replaced;
   --  the diff is swapped — freed and reloaded — every time a commit is
   --  opened, and the predicate rides along through the swap.
   ---------------------------------------------------------------------------

   List_Doc : Tui.Text.Doc_Ref := null;
   Diff_Doc : Tui.Text.Doc_Ref := null;

   List_Eng : Eng_Pkg.Instance;
   Diff_Eng : Eng_Pkg.Instance;

   --  The highlighted commit-list line. The engine is a pure viewport; the
   --  selection lives here, kept inside the visible slice by the proved
   --  coupling rules. Meaningful only while the list has lines; every use
   --  re-clamps it against the current line count first.
   Selected : Tui.Text.Line_Number := 1;

   --  Whose diff the right pane currently shows (for the status line).
   Diff_Id : Git_View_Sha.Sha;

   Focused : Pol.Pane := Pol.List_Pane;

   --  Search-input mode: while Searching, keystrokes build Pattern instead
   --  of navigating; Enter installs it on the focused pane's engine.
   Searching : Boolean := False;
   Forward   : Boolean := True;
   Pattern   : Git_View_Search_Input.Editor;
   Note      : Git_View_Status.Note := Git_View_Status.No_Note;

   --  The pane split as last painted. The key handler has no surface, so the
   --  painter leaves the geometry behind for mouse hit-testing; before the
   --  first frame everything is 0 and every position falls Outside.
   List_Width : Natural := 0;
   Diff_Width : Natural := 0;
   View_Rows  : Natural := 0;

   -------------------
   -- Uninitialized --
   -------------------

   function Uninitialized return Boolean is
     (List_Doc = null and then Diff_Doc = null);

   -------------------
   -- Has_Documents --
   -------------------

   function Has_Documents return Boolean is
     (List_Doc /= null and then Diff_Doc /= null);

   ---------------------------------------------------------------------------
   --  Shared helpers
   ---------------------------------------------------------------------------

   --  The commit id on the selected line (invalid when the list is empty or
   --  the line carries none).
   procedure Selected_Id (Id : out Git_View_Sha.Sha)
   with Global => (Input => (List_Doc, Selected)),
        Pre    => List_Doc /= null
   is
      Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (List_Doc.all.Idx);
   begin
      if Total > 0 then
         Git_View_Sha.Extract
           (List_Doc.all.Bytes, List_Doc.all.Idx,
            Natural'Min (Selected, Total), Id);
      else
         Id := (Text => (others => ' '), Len => 0);
      end if;
   end Selected_Id;

   ----------
   -- Init --
   ----------

   procedure Init (Ok : out Boolean) is
      Log_Ok : Boolean;
   begin
      Git_View_Source.Load_Log (List_Doc, Log_Ok);
      Ok := Log_Ok;
      if not Log_Ok then
         return;
      end if;

      Selected := 1;
      Focused  := Pol.List_Pane;

      --  Open the newest commit's diff so the right pane starts populated.
      declare
         Total   : constant Tui.Text.Line_Total :=
           Tui.Text.Line_Count (List_Doc.all.Idx);
         Id      : Git_View_Sha.Sha;
         Diff_Ok : Boolean;
      begin
         if Total > 0 then
            Git_View_Sha.Extract (List_Doc.all.Bytes, List_Doc.all.Idx, 1, Id);
            if Git_View_Sha.Valid (Id) then
               Git_View_Source.Load_Diff (Id, Diff_Doc, Diff_Ok);
               Diff_Id := Id;
               if not Diff_Ok then
                  Note := Git_View_Status.Git_Show_Failed;
               end if;
            end if;
         end if;
      end;

      --  An empty list (or an unparsable first line) still needs a
      --  well-formed diff document for the callbacks' contracts.
      if Diff_Doc = null then
         declare
            Empty : constant Tui.Text.Buffer (1 .. 0) := (others => 0);
         begin
            Diff_Doc := Tui.Text.New_Document (Empty);
         end;
      end if;
   end Init;

   ---------------------------------------------------------------------------
   --  Painting
   ---------------------------------------------------------------------------

   procedure Put_String
     (S    : in out Surface;
      R    : Row_Index;
      Text : String;
      Attr : Style;
      Fg   : Color := Default_Color)
   with Global => null,
        Pre    => R <= S.Rows
   is
      Col : Col_Count := 0;
   begin
      for Ch of Text loop
         exit when Col >= S.Cols;
         Col := Col + 1;
         Set (S, R, Col,
              (Glyph => Wide_Wide_Character'Val (Character'Pos (Ch)),
               Foreground => Fg, Attributes => Attr, others => <>));
      end loop;
   end Put_String;

   --  Recolour a span of one row's cells, clipped to the surface. Glyphs and
   --  the other attributes are preserved, so a later inverse highlight (the
   --  selection, the status bar) stacks on top of the colour.
   procedure Tint_Cells
     (S    : in out Surface;
      R    : Row_Index;
      From : Positive;
      To   : Natural;
      Fg   : Color;
      Bold : Boolean := False)
   with Global => null,
        Pre    => R <= S.Rows
   is
   begin
      if From > Natural (S.Cols) or else To < From then
         return;
      end if;
      for C in Col_Index range Col_Index (From)
        .. Col_Index (Natural'Min (To, Natural (S.Cols)))
      loop
         declare
            Cl : Cell := Get (S, R, C);
         begin
            Cl.Foreground := Fg;
            if Bold then
               Cl.Attributes.Bold := True;
            end if;
            Set (S, R, C, Cl);
         end;
      end loop;
   end Tint_Cells;

   procedure Tint_Row
     (S    : in out Surface;
      R    : Row_Index;
      Fg   : Color;
      Bold : Boolean := False)
   with Global => null,
        Pre    => R <= S.Rows
   is
   begin
      Tint_Cells (S, R, 1, Natural (S.Cols), Fg, Bold);
   end Tint_Row;

   --  Colour the rendered diff rows by what their content lines are: the
   --  classification reads the document (not the surface), so it is
   --  independent of any horizontal scroll, and whole rows are tinted the
   --  way git's own porcelain colours diff output.
   procedure Colorize_Diff (DS : in out Surface)
   with Global => (Input => (Diff_Doc, Diff_Eng)),
        Pre    => Diff_Doc /= null
   is
      Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (Diff_Doc.all.Idx);
      Top   : constant Tui.Text.Line_Number := Eng_Pkg.Top_Line (Diff_Eng);
   begin
      for R in Row_Index range 1 .. DS.Rows loop
         declare
            LN : constant Natural := Top + (Natural (R) - 1);
         begin
            exit when LN > Total;
            case Thm.Classify
              (Tui.Text.Line (Diff_Doc.all.Idx, Diff_Doc.all.Bytes, LN))
            is
               when Thm.Plain_Line =>
                  null;
               when Thm.Added =>
                  Tint_Row (DS, R, Thm.Added_Color);
               when Thm.Removed =>
                  Tint_Row (DS, R, Thm.Removed_Color);
               when Thm.Hunk =>
                  Tint_Row (DS, R, Thm.Hunk_Color);
               when Thm.File_Meta =>
                  Tint_Row (DS, R, Default_Color, Bold => True);
               when Thm.Commit_Head =>
                  Tint_Row (DS, R, Thm.Commit_Color);
            end case;
         end;
      end loop;
   end Colorize_Diff;

   --  Colour the commit list's leading tokens: the abbreviated id (validated
   --  by the proved parser, so junk lines stay uncoloured) and the
   --  fixed-width date after it. Token columns line up with the rendered
   --  text only at zero horizontal scroll; a scrolled list stays plain.
   procedure Colorize_List (LS : in out Surface)
   with Global => (Input => (List_Doc, List_Eng)),
        Pre    => List_Doc /= null
   is
      Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (List_Doc.all.Idx);
      Top   : constant Tui.Text.Line_Number := Eng_Pkg.Top_Line (List_Eng);
   begin
      if Eng_Pkg.Left_Col (List_Eng) /= 0 then
         return;
      end if;
      for R in Row_Index range 1 .. LS.Rows loop
         declare
            LN : constant Natural := Top + (Natural (R) - 1);
            Id : Git_View_Sha.Sha;
         begin
            exit when LN > Total;
            Git_View_Sha.Extract (List_Doc.all.Bytes, List_Doc.all.Idx, LN,
                                  Id);
            if Git_View_Sha.Valid (Id) then
               Tint_Cells (LS, R, 1, Id.Len, Thm.Sha_Color);
               --  The date is the fixed-width (YYYY-MM-DD) token after the
               --  id; the log format guarantees its position.
               Tint_Cells (LS, R, Id.Len + 2, Id.Len + 11, Thm.Date_Color);
            end if;
         end;
      end loop;
   end Colorize_List;

   --  Restyle the selected line's row to inverse video. The defensive range
   --  test keeps this correct (and proved) even when the selection is
   --  momentarily outside the rendered slice.
   procedure Highlight_Selection
     (LS    : in out Surface;
      Total : Tui.Text.Line_Total)
   with Global => (Input => (List_Eng, Selected))
   is
      Top : constant Tui.Text.Line_Number := Eng_Pkg.Top_Line (List_Eng);
   begin
      if Total = 0 then
         return;
      end if;
      if Selected >= Top and then Selected - Top < Natural (LS.Rows) then
         declare
            R : constant Row_Index := Row_Index (Selected - Top + 1);
         begin
            for C in Col_Index range 1 .. LS.Cols loop
               declare
                  Cl : Cell := Get (LS, R, C);
               begin
                  Cl.Attributes.Inverse := True;
                  Set (LS, R, C, Cl);
               end;
            end loop;
         end;
      end if;
   end Highlight_Selection;

   procedure Draw_Status (S : in out Surface)
   with Global => (Input => (List_Doc, Diff_Doc, Diff_Eng, Selected,
                             Diff_Id, Focused, Searching, Forward, Pattern,
                             Note)),
        Pre    => List_Doc /= null and then Diff_Doc /= null
   is
      Bar : constant Style := (Inverse => True, others => False);

      --  Under inverse video the accent foreground shows as the bar's
      --  background, so the bar's colour tracks what it is saying.
      Accent : constant Color :=
        (if Searching then Thm.Prompt_Accent
         elsif Note /= Git_View_Status.No_Note then Thm.Note_Accent
         else Thm.Bar_Accent);

      Row : Row_Index;
      L   : Git_View_Status.Line;
   begin
      if S.Rows < 1 then
         return;   --  no room for a status bar
      end if;
      Row := S.Rows;

      --  Inverse-fill the whole row so it reads as a bar.
      for C in 1 .. S.Cols loop
         Set (S, Row, C,
              (Glyph => ' ', Foreground => Accent, Attributes => Bar,
               others => <>));
      end loop;

      if Searching then
         Git_View_Status.Format_Prompt
           (L, Forward, Git_View_Search_Input.Bytes (Pattern));
      elsif Note /= Git_View_Status.No_Note then
         Git_View_Status.Format_Note (L, Note);
      elsif Focused = Pol.List_Pane then
         declare
            Total : constant Tui.Text.Line_Total :=
              Tui.Text.Line_Count (List_Doc.all.Idx);
            Id    : Git_View_Sha.Sha;
         begin
            Selected_Id (Id);
            Git_View_Status.Format_List_Position
              (L,
               Selected => Natural'Min (Selected, Total),
               Total    => Total,
               Id       => Git_View_Sha.Image (Id));
         end;
      else
         declare
            Total : constant Tui.Text.Line_Total :=
              Tui.Text.Line_Count (Diff_Doc.all.Idx);
         begin
            Git_View_Status.Format_Diff_Position
              (L,
               Id    => Git_View_Sha.Image (Diff_Id),
               Top   => Eng_Pkg.Top_Line (Diff_Eng),
               Last  => Eng_Pkg.Last_Visible (Diff_Eng, Total),
               Total => Total);
         end;
      end if;

      Put_String (S, Row, Git_View_Status.Image (L), Bar, Accent);
   end Draw_Status;

   -----------
   -- Paint --
   -----------

   procedure Paint (S : in out Surface) is
      List_Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (List_Doc.all.Idx);
      Diff_Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (Diff_Doc.all.Idx);

      --  Reserve the last row for the status line.
      Content_Rows : constant Row_Count :=
        (if S.Rows >= 1 then S.Rows - 1 else 0);

      --  Split the width: list left (45%, at least 1 column), one separator
      --  column, diff right. Too narrow for three parts: list only.
      NC        : constant Natural := Natural (S.Cols);
      List_Cols : constant Natural :=
        (if NC >= 3
         then Natural'Max (1, Natural'Min (NC - 2, NC * 45 / 100))
         else NC);
      Diff_Cols : constant Natural :=
        (if NC >= 3 then NC - List_Cols - 1 else 0);
   begin
      Eng_Pkg.Resize (List_Eng, Rows => Natural (Content_Rows),
                      Cols => List_Cols, Total => List_Total);
      Eng_Pkg.Resize (Diff_Eng, Rows => Natural (Content_Rows),
                      Cols => Diff_Cols, Total => Diff_Total);

      --  Leave the geometry behind for mouse hit-testing.
      List_Width := List_Cols;
      Diff_Width := Diff_Cols;
      View_Rows  := Natural (Content_Rows);

      --  A resize can shrink the list viewport from under the selection.
      if List_Total > 0 then
         Git_View_List.Clamp (List_Eng, List_Total, Selected);
      end if;

      --  Each pane renders into its own surface; the region copy composites
      --  them into the screen.
      declare
         LS : Surface := Blank (Content_Rows, Col_Count (List_Cols));
      begin
         Eng_Pkg.Render (List_Eng, LS, List_Doc.all.Bytes, List_Doc.all.Idx);
         Colorize_List (LS);
         Highlight_Selection (LS, List_Total);
         Copy (LS, S, At_Row => 1, At_Col => 1);
      end;

      if Diff_Cols > 0 then
         declare
            Sep : constant Col_Index := Col_Index (List_Cols + 1);
         begin
            for R in Row_Index range 1 .. Content_Rows loop
               Set (S, R, Sep,
                    (Glyph      => Wide_Wide_Character'Val (16#2502#),
                     Foreground => Thm.Separator_Color,
                     others     => <>));
            end loop;
         end;
         declare
            DS : Surface := Blank (Content_Rows, Col_Count (Diff_Cols));
         begin
            Eng_Pkg.Render (Diff_Eng, DS, Diff_Doc.all.Bytes,
                            Diff_Doc.all.Idx);
            Colorize_Diff (DS);
            Copy (DS, S, At_Row => 1, At_Col => Col_Index (List_Cols + 2));
         end;
      end if;

      Draw_Status (S);
   end Paint;

   ---------------------------------------------------------------------------
   --  Key handling
   ---------------------------------------------------------------------------

   --  Run the current pattern in the given direction on the focused pane,
   --  noting a miss. A hit in the list pane moves the viewport, so the
   --  selection is pulled along into view.
   procedure Do_Find (Find_Forward : Boolean; Changed : out Boolean)
   with Global => (In_Out => (List_Eng, Diff_Eng, Selected, Note),
                   Input  => (List_Doc, Diff_Doc, Focused)),
        Pre    => List_Doc /= null and then Diff_Doc /= null
   is
      Res : Eng_Pkg.Effect;
      Cmd : constant Eng_Pkg.Command :=
        (if Find_Forward then Eng_Pkg.Find_Next else Eng_Pkg.Find_Prev);
      Missed_On_Pattern : Boolean;
   begin
      if Focused = Pol.List_Pane then
         Eng_Pkg.Handle (List_Eng, Cmd, List_Doc.all.Bytes, List_Doc.all.Idx,
                         Res);
         declare
            Total : constant Tui.Text.Line_Total :=
              Tui.Text.Line_Count (List_Doc.all.Idx);
         begin
            if Total > 0 then
               Git_View_List.Clamp (List_Eng, Total, Selected);
            end if;
         end;
         Missed_On_Pattern := Eng_Pkg.Has_Pattern (List_Eng);
      else
         Eng_Pkg.Handle (Diff_Eng, Cmd, Diff_Doc.all.Bytes, Diff_Doc.all.Idx,
                         Res);
         Missed_On_Pattern := Eng_Pkg.Has_Pattern (Diff_Eng);
      end if;

      if Res = Eng_Pkg.Search_Miss then
         Note := (if Missed_On_Pattern
                  then Git_View_Status.Pattern_Not_Found
                  else Git_View_Status.No_Pattern);
      end if;
      Changed := True;   --  always repaint: viewport moved or note changed
   end Do_Find;

   --  Show the selected commit's diff: free the old document, load the new
   --  one (never null, by the source's contract) and reset the diff view.
   procedure Open_Selected (Changed : out Boolean)
   with Global => (In_Out => (Diff_Doc, Diff_Eng, Diff_Id, Selected, Note),
                   Input  => List_Doc),
        Pre    => List_Doc /= null and then Diff_Doc /= null,
        Post   => Diff_Doc /= null
   is
      Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (List_Doc.all.Idx);
      Id : Git_View_Sha.Sha;
      Ok : Boolean;
   begin
      Changed := False;
      if Total = 0 then
         return;
      end if;
      if Selected > Total then
         Selected := Total;
      end if;

      Git_View_Sha.Extract (List_Doc.all.Bytes, List_Doc.all.Idx, Selected,
                            Id);
      if Git_View_Sha.Valid (Id) then
         Git_View_Source.Load_Diff (Id, Diff_Doc, Ok);
         Diff_Id := Id;
         declare
            Fresh : Eng_Pkg.Instance;
         begin
            Diff_Eng := Fresh;   --  new document: back to the top, no pattern
         end;
         if not Ok then
            Note := Git_View_Status.Git_Show_Failed;
         end if;
      else
         Note := Git_View_Status.No_Commit_On_Line;
      end if;
      Changed := True;
   end Open_Selected;

   --  Apply a selection move (clamping first: the callbacks' contracts do
   --  not carry the selection-within-list invariant across calls).
   procedure Move_Sel (M : Pol.Sel_Move; Changed : out Boolean)
   with Global => (In_Out => (List_Eng, Selected), Input => List_Doc),
        Pre    => List_Doc /= null
   is
      Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (List_Doc.all.Idx);
   begin
      Changed := False;
      if Total > 0 then
         if Selected > Total then
            Selected := Total;
         end if;
         Git_View_List.Move (List_Eng, M, List_Doc.all.Bytes,
                             List_Doc.all.Idx, Selected, Changed);
      end if;
   end Move_Sel;

   procedure Handle_Search_Key
     (Event : Key_Event;
      Dirty : out Boolean;
      Quit  : out Boolean)
   with Global => (In_Out => (List_Eng, Diff_Eng, Selected, Searching,
                              Pattern, Note),
                   Input  => (List_Doc, Diff_Doc, Focused, Forward)),
        Pre    => List_Doc /= null and then Diff_Doc /= null
   is
   begin
      Quit  := False;
      Dirty := True;   --  the prompt is on screen; any edit repaints it
      case Event.Kind is
         when Enter =>
            Searching := False;
            if Focused = Pol.List_Pane then
               Eng_Pkg.Set_Pattern
                 (List_Eng, Git_View_Search_Input.Bytes (Pattern));
            else
               Eng_Pkg.Set_Pattern
                 (Diff_Eng, Git_View_Search_Input.Bytes (Pattern));
            end if;
            declare
               Ignore : Boolean;
            begin
               Do_Find (Forward, Ignore);
            end;
         when Escape =>
            Searching := False;        --  cancel; leave any prior pattern
         when Backspace =>
            Git_View_Search_Input.Backspace (Pattern);
         when Char =>
            Git_View_Search_Input.Append (Pattern, Event.Code);
         when others =>
            null;
      end case;
   end Handle_Search_Key;

   --  One wheel notch scrolls this many lines, the desktop convention.
   Wheel_Lines : constant := 3;

   --  Carry out a mouse event against the layout the painter recorded. A
   --  left click selects the commit under the cursor and gives the clicked
   --  pane the keyboard; the wheel scrolls the pane UNDER the cursor —
   --  deliberately without moving the keyboard focus, so hovering to scroll
   --  never changes what the keys do.
   procedure Handle_Mouse (Event : Key_Event; Changed : out Boolean)
   with Global => (In_Out => (List_Eng, Diff_Eng, Selected, Focused),
                   Input  => (List_Doc, Diff_Doc,
                              List_Width, Diff_Width, View_Rows)),
        Pre    => List_Doc /= null and then Diff_Doc /= null
   is
      Where : constant Pol.Region :=
        Pol.Locate (Event.Col, Event.Row, List_Width, Diff_Width, View_Rows);
   begin
      Changed := False;
      if Where = Pol.Outside then
         return;
      end if;

      case Event.Kind is
         when Mouse_Press =>
            if Event.Button = Left_Button then
               if Where = Pol.List_Region then
                  --  Select the line under the cursor, when one is there.
                  declare
                     Total : constant Tui.Text.Line_Total :=
                       Tui.Text.Line_Count (List_Doc.all.Idx);
                     Top   : constant Tui.Text.Line_Number :=
                       Eng_Pkg.Top_Line (List_Eng);
                     Off   : constant Natural := Event.Row - 1;
                  begin
                     if Total > 0 and then Top <= Total
                       and then Off <= Total - Top
                       and then Selected /= Top + Off
                     then
                        Selected := Top + Off;
                        Changed  := True;
                     end if;
                  end;
                  if Focused /= Pol.List_Pane then
                     Focused := Pol.List_Pane;
                     Changed := True;
                  end if;
               else
                  if Focused /= Pol.Diff_Pane then
                     Focused := Pol.Diff_Pane;
                     Changed := True;
                  end if;
               end if;
            end if;

         when Wheel_Up | Wheel_Down =>
            declare
               Cmd : constant Eng_Pkg.Command :=
                 (if Event.Kind = Wheel_Up
                  then Eng_Pkg.Line_Up else Eng_Pkg.Line_Down);
               Res : Eng_Pkg.Effect;
            begin
               for Step in 1 .. Wheel_Lines loop
                  if Where = Pol.List_Region then
                     Eng_Pkg.Handle (List_Eng, Cmd, List_Doc.all.Bytes,
                                     List_Doc.all.Idx, Res);
                  else
                     Eng_Pkg.Handle (Diff_Eng, Cmd, Diff_Doc.all.Bytes,
                                     Diff_Doc.all.Idx, Res);
                  end if;
                  if Res /= Eng_Pkg.Unchanged then
                     Changed := True;
                  end if;
               end loop;
               --  A scrolled list pulls its selection along into view.
               if Where = Pol.List_Region and then Changed then
                  declare
                     Total : constant Tui.Text.Line_Total :=
                       Tui.Text.Line_Count (List_Doc.all.Idx);
                  begin
                     if Total > 0 then
                        Git_View_List.Clamp (List_Eng, Total, Selected);
                     end if;
                  end;
               end if;
            end;

         when others =>
            null;   --  releases mean nothing here
      end case;
   end Handle_Mouse;

   ------------
   -- On_Key --
   ------------

   procedure On_Key
     (Event : Key_Event;
      Dirty : out Boolean;
      Quit  : out Boolean)
   is
      Had_Note : constant Boolean := Note /= Git_View_Status.No_Note;
   begin
      Quit  := False;
      Dirty := False;

      --  While the search prompt is open the mouse is dormant: a click must
      --  not silently retarget the pane the pattern will land on.
      if Searching
        and then Event.Kind in
          Mouse_Press | Mouse_Release | Wheel_Up | Wheel_Down
      then
         return;
      end if;

      Note := Git_View_Status.No_Note;   --  a keystroke clears a stale note

      if Searching then
         Handle_Search_Key (Event, Dirty, Quit);
         return;
      end if;

      if Event.Kind in Mouse_Press | Mouse_Release | Wheel_Up | Wheel_Down then
         --  Mouse events speak the painter's geometry, not the keymap.
         Handle_Mouse (Event, Dirty);
         if Had_Note then
            Dirty := True;
         end if;
         return;
      end if;

      --  Decide what the key means (pure, proved policy), then carry it out.
      declare
         D : constant Pol.Decision := Pol.Classify (Focused, Event);
      begin
         case D.Kind is
            when Pol.Quit =>
               Quit := True;

            when Pol.Switch_Focus =>
               Focused := (if Focused = Pol.List_Pane
                           then Pol.Diff_Pane else Pol.List_Pane);
               Dirty := True;

            when Pol.Open_Diff =>
               Open_Selected (Dirty);

            when Pol.Move_Selection =>
               Move_Sel (D.Move, Dirty);

            when Pol.Navigate =>
               declare
                  Res : Eng_Pkg.Effect;
               begin
                  if Focused = Pol.List_Pane then
                     Eng_Pkg.Handle (List_Eng, D.Command, List_Doc.all.Bytes,
                                     List_Doc.all.Idx, Res);
                  else
                     Eng_Pkg.Handle (Diff_Eng, D.Command, Diff_Doc.all.Bytes,
                                     Diff_Doc.all.Idx, Res);
                  end if;
                  Dirty := Res /= Eng_Pkg.Unchanged;
               end;

            when Pol.Search =>
               Searching := True;
               Forward   := D.Forward;
               Git_View_Search_Input.Clear (Pattern);
               Dirty     := True;

            when Pol.Repeat_Search =>
               Do_Find ((if D.Reversed then not Forward else Forward), Dirty);

            when Pol.Ignore =>
               null;
         end case;
      end;

      --  A visible note was cleared above; make sure it leaves the screen.
      if Had_Note then
         Dirty := True;
      end if;
   end On_Key;

end Git_View_App;
