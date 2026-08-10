with Tui.Surface;                                use Tui.Surface;
with Tui.Input;                                  use Tui.Input;
with Tui.Text;
with Tui.Pager.Engine;
with Git_View_Policy;
with Git_View_List;
with Git_View_Sha;
with Git_View_Status;
with Git_View_Theme;
with Git_View_Syntax;
with Git_View_Selection;
with Git_View_Clipboard;
with Git_View_Navigation;
with Git_View_Refs;
with Tui.App_Kit.Search_Input;

package body Git_View_App with
  SPARK_Mode    => On,
  Refined_State =>
    (State =>
       (List_Doc, Diff_Doc, List_Eng, Diff_Eng, Selected, Diff_Id,
        Focused, Searching, Forward, Pattern, Note,
        Syntax_Enabled,
        Maximized, Split, Resizing_Split,
        List_Width, Diff_Width, View_Rows, Screen_Width,
        Selecting, Selection_Shown, Selection_Pane,
        Selection_Start, Selection_End))
is

   package Eng_Pkg renames Tui.Pager.Engine;
   package Edit renames Tui.App_Kit.Search_Input;
   package Pol renames Git_View_Policy;
   package Thm renames Git_View_Theme;
   package Syn renames Git_View_Syntax;
   package Sel renames Git_View_Selection;
   package Nav renames Git_View_Navigation;
   package Refs renames Git_View_Refs;
   use type Eng_Pkg.Effect;
   use type Pol.Pane;
   use type Pol.Region;
   use type Git_View_Status.Note;
   use type Tui.Text.Doc_Ref;
   use type Sel.Position;
   use type Syn.Language;
   use type Tui.Text.Byte;

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
   Pattern   : Edit.Editor;
   Note      : Git_View_Status.Note := Git_View_Status.No_Note;

   --  Source-token foreground colours are optional. Diff polarity never
   --  depends on them: additions and removals retain a coloured gutter.
   Syntax_Enabled : Boolean := True;

   --  Layout preference. In a maximized layout Focused identifies the one
   --  visible pane. Split is retained while maximized and restored by `z`.
   Maximized      : Boolean := False;
   Split          : Pol.Split_Percentage := Pol.Default_Split;
   Resizing_Split : Boolean := False;

   --  The pane split as last painted. The key handler has no surface, so the
   --  painter leaves the geometry behind for mouse hit-testing; before the
   --  first frame everything is 0 and every position falls Outside.
   List_Width   : Natural := 0;
   Diff_Width   : Natural := 0;
   View_Rows    : Natural := 0;
   Screen_Width : Col_Count := 0;

   --  A drag is stored in document/display coordinates, not screen
   --  coordinates, so repainting and horizontal scrolling do not corrupt it.
   --  A click without motion is not displayed as a one-cell selection.
   Selecting      : Boolean := False;
   Selection_Shown : Boolean := False;
   Selection_Pane : Pol.Pane := Pol.List_Pane;
   Selection_Start : Sel.Position;
   Selection_End   : Sel.Position;

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

   procedure Init
     (From   : Git_View_Source.Revision;
      Filter : Git_View_Source.Filters;
      Ok     : out Boolean)
   is
      Log_Ok : Boolean;
   begin
      Git_View_Source.Load_Log (From, Filter, List_Doc, Log_Ok);
      Ok := Log_Ok;
      if not Log_Ok then
         return;
      end if;

      Selected := 1;
      Focused  := Pol.List_Pane;
      Maximized      := False;
      Split          := Pol.Default_Split;
      Resizing_Split := False;

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

   --  Set a row background while retaining glyphs, syntax foregrounds, and
   --  attributes. This gives diff polarity its own visual channel.
   procedure Shade_Row
     (S  : in out Surface;
      R  : Row_Index;
      Bg : Color)
   with Global => null,
        Pre    => R <= S.Rows
   is
   begin
      for C in Col_Index range 1 .. S.Cols loop
         declare
            Cl : Cell := Get (S, R, C);
         begin
            Cl.Background := Bg;
            Set (S, R, C, Cl);
         end;
      end loop;
   end Shade_Row;

   --  Tint a source-byte span after translating it through UTF-8/tab display
   --  columns and the diff viewport's horizontal offset.
   procedure Tint_Byte_Span
     (S    : in out Surface;
      R    : Row_Index;
      Line : Tui.Text.Buffer;
      From : Tui.Text.Byte_Index;
      To   : Tui.Text.Byte_Index;
      Left : Tui.Pager.Dimension;
      Fg   : Color)
   with Global => null,
        Pre    => R <= S.Rows
                  and then From in Line'Range
                  and then To in From .. Line'Last
   is
      First_Col : constant Natural :=
        Syn.Display_Column (Line, From - Line'First);
      After_Col : constant Natural :=
        Syn.Display_Column (Line, To - Line'First + 1);
      Right     : constant Natural := Left + Natural (S.Cols);
   begin
      if After_Col <= Left or else First_Col >= Right
        or else After_Col <= First_Col
      then
         return;
      end if;
      Tint_Cells
        (S, R,
         Natural'Max (First_Col, Left) - Left + 1,
         Natural'Min (After_Col, Right) - Left,
         Fg);
   end Tint_Byte_Span;

   procedure Colorize_Source_Line
     (S    : in out Surface;
      R    : Row_Index;
      Line : Tui.Text.Buffer;
      Lang : Syn.Language;
      Left : Tui.Pager.Dimension)
   with Global => null,
        Pre    => R <= S.Rows
   is
   begin
      --  Unified-diff source lines carry one leading marker (+, -, or space).
      if Lang = Syn.Plain or else Line'Length <= 1 then
         return;
      end if;
      declare
         subtype Scan_Index is
           Natural range 1 .. Tui.Text.Max_Bytes + 1;
         Last : constant Tui.Text.Byte_Index := Line'Last;
         Pos  : Scan_Index := Line'First + 1;
      begin
         while Pos <= Last loop
            pragma Loop_Invariant
              (Pos in Line'First + 1 .. Line'Last + 1);
            pragma Loop_Invariant (R <= S.Rows);
            pragma Loop_Variant (Decreases => Last + 1 - Pos);
            if Syn.Starts_Comment (Line, Pos, Lang) then
               Tint_Byte_Span
                 (S, R, Line, Pos, Last, Left, Thm.Comment_Color);
               return;
            elsif Line (Pos) = 34 or else Line (Pos) = 39
              or else Line (Pos) = 96
            then
               declare
                  Quote   : constant Tui.Text.Byte := Line (Pos);
                  Finish  : Tui.Text.Byte_Index := Pos;
                  Escaped : Boolean := False;
               begin
                  while Finish < Last loop
                     pragma Loop_Invariant (Finish in Pos .. Last);
                     pragma Loop_Variant (Decreases => Last - Finish);
                     Finish := Finish + 1;
                     if not Escaped and then Line (Finish) = Quote then
                        exit;
                     end if;
                     if not Escaped and then Line (Finish) = 92 then
                        Escaped := True;
                     else
                        Escaped := False;
                     end if;
                  end loop;
                  Tint_Byte_Span
                    (S, R, Line, Pos, Finish, Left, Thm.String_Color);
                  Pos := Finish + 1;
               end;
            elsif Syn.Is_Identifier_Start (Line (Pos)) then
               declare
                  Finish : Tui.Text.Byte_Index := Pos;
               begin
                  while Finish < Last
                    and then Syn.Is_Identifier (Line (Finish + 1))
                  loop
                     pragma Loop_Invariant (Finish in Pos .. Last);
                     pragma Loop_Variant (Decreases => Last - Finish);
                     Finish := Finish + 1;
                  end loop;
                  if Syn.Is_Keyword (Line, Pos, Finish, Lang) then
                     Tint_Byte_Span
                       (S, R, Line, Pos, Finish, Left, Thm.Keyword_Color);
                  end if;
                  Pos := Finish + 1;
               end;
            elsif Syn.Is_Digit (Line (Pos)) then
               declare
                  Finish : Tui.Text.Byte_Index := Pos;
               begin
                  while Finish < Last
                    and then (Syn.Is_Identifier (Line (Finish + 1))
                              or else Line (Finish + 1) = Character'Pos ('.'))
                  loop
                     pragma Loop_Invariant (Finish in Pos .. Last);
                     pragma Loop_Variant (Decreases => Last - Finish);
                     Finish := Finish + 1;
                  end loop;
                  Tint_Byte_Span
                    (S, R, Line, Pos, Finish, Left, Thm.Number_Color);
                  Pos := Finish + 1;
               end;
            else
               Pos := Pos + 1;
            end if;
         end loop;
      end;
   end Colorize_Source_Line;

   --  Colour the rendered diff rows by what their content lines are: the
   --  classification reads the document (not the surface), so it is
   --  independent of any horizontal scroll, and whole rows are tinted the
   --  way git's own porcelain colours diff output.
   procedure Colorize_Diff (DS : in out Surface)
   with Global => (Input => (Diff_Doc, Diff_Eng, Syntax_Enabled)),
        Pre    => Diff_Doc /= null
   is
      Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (Diff_Doc.all.Idx);
      Top   : constant Tui.Text.Line_Number := Eng_Pkg.Top_Line (Diff_Eng);
      Lang  : Syn.Language :=
        (if Total > 0 and then Top <= Total
         then Syn.Language_At
           (Diff_Doc.all.Bytes, Diff_Doc.all.Idx, Top)
         else Syn.Plain);
      Found       : Boolean;
      Header_Lang : Syn.Language;
   begin
      for R in Row_Index range 1 .. DS.Rows loop
         declare
            LN : constant Natural := Top + (Natural (R) - 1);
         begin
            exit when LN > Total;
            declare
               Line : constant Tui.Text.Buffer :=
                 Tui.Text.Line (Diff_Doc.all.Idx, Diff_Doc.all.Bytes, LN);
               Kind : constant Thm.Line_Kind := Thm.Classify (Line);
            begin
               Syn.Header_Language (Line, Found, Header_Lang);
               if Found then
                  Lang := Header_Lang;
               end if;
               case Kind is
                  when Thm.Plain_Line =>
                     null;
                  when Thm.Added =>
                     Shade_Row (DS, R, Thm.Added_Background);
                     if Eng_Pkg.Left_Col (Diff_Eng) = 0 then
                        Tint_Cells (DS, R, 1, 1, Thm.Added_Color);
                     end if;
                  when Thm.Removed =>
                     Shade_Row (DS, R, Thm.Removed_Background);
                     if Eng_Pkg.Left_Col (Diff_Eng) = 0 then
                        Tint_Cells (DS, R, 1, 1, Thm.Removed_Color);
                     end if;
                  when Thm.Hunk =>
                     Tint_Row (DS, R, Thm.Hunk_Color);
                  when Thm.File_Meta =>
                     Tint_Row (DS, R, Default_Color, Bold => True);
                  when Thm.Commit_Head =>
                     Tint_Row (DS, R, Thm.Commit_Color);
               end case;
               if Syntax_Enabled
                 and then Kind in Thm.Plain_Line | Thm.Added | Thm.Removed
               then
                  Colorize_Source_Line
                    (DS, R, Line, Lang, Eng_Pkg.Left_Col (Diff_Eng));
               end if;
            end;
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
               declare
                  Line : constant Tui.Text.Buffer :=
                    Tui.Text.Line
                      (List_Doc.all.Idx, List_Doc.all.Bytes, LN);
                  Found    : Boolean;
                  From, To : Tui.Text.Byte_Count;
               begin
                  Refs.Decoration_Span (Line, Id.Len, Found, From, To);
                  if Found then
                     Tint_Byte_Span
                       (LS, R, Line, Line'First + From, Line'First + To,
                        Eng_Pkg.Left_Col (List_Eng), Thm.Ref_Color);
                  end if;
               end;
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

   --  Overlay a retained linear mouse selection. Toggling inverse rather than
   --  merely setting it keeps the selected text visible inside the list's
   --  already-inverse current-commit row.
   procedure Highlight_Text_Selection
     (PS   : in out Surface;
      Pane : Pol.Pane;
      E    : Eng_Pkg.Instance)
   with Global => (Input => (Selection_Shown, Selection_Pane,
                             Selection_Start, Selection_End))
   is
      First, Last : Sel.Position;
      Top         : constant Tui.Text.Line_Number := Eng_Pkg.Top_Line (E);
      Left        : constant Natural := Eng_Pkg.Left_Col (E);
   begin
      if not Selection_Shown or else Selection_Pane /= Pane then
         return;
      end if;
      Sel.Ordered (Selection_Start, Selection_End, First, Last);
      for R in Row_Index range 1 .. PS.Rows loop
         declare
            LN : constant Natural := Top + (Natural (R) - 1);
         begin
            if LN >= First.Line and then LN <= Last.Line then
               for C in Col_Index range 1 .. PS.Cols loop
                  declare
                     DC : constant Natural := Left + Natural (C) - 1;
                     In_Range : constant Boolean :=
                       (if First.Line = Last.Line then
                           LN = First.Line
                           and then DC in First.Col .. Last.Col
                        elsif LN = First.Line then DC >= First.Col
                        elsif LN = Last.Line then DC <= Last.Col
                        else LN > First.Line and then LN < Last.Line);
                  begin
                     if In_Range then
                        declare
                           Cl : Cell := Get (PS, R, C);
                        begin
                           Cl.Attributes.Inverse := not Cl.Attributes.Inverse;
                           Set (PS, R, C, Cl);
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Highlight_Text_Selection;

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
           (L, Forward, Edit.Bytes (Pattern));
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

      --  A narrow normal layout shows the list alone. If the diff had focus
      --  before the resize, move focus to the pane that remains visible.
      Narrow : constant Boolean :=
        not Maximized and then Natural (S.Cols) < Pol.Min_Split_Width;
   begin
      if Narrow and then Focused = Pol.Diff_Pane then
         Focused := Pol.List_Pane;
      end if;
      declare
         L : constant Pol.Layout :=
           Pol.Compute_Layout (S.Cols, Focused, Maximized, Split);
         List_Cols : constant Natural := L.List_Cols;
         Diff_Cols : constant Natural := L.Diff_Cols;
         Is_Split  : constant Boolean := List_Cols > 0 and Diff_Cols > 0;
         Diff_At   : constant Col_Index :=
           (if Is_Split then Col_Index (List_Cols + 2) else 1);
      begin
         Eng_Pkg.Resize (List_Eng, Rows => Natural (Content_Rows),
                         Cols => List_Cols, Total => List_Total);
         Eng_Pkg.Resize (Diff_Eng, Rows => Natural (Content_Rows),
                         Cols => Diff_Cols, Total => Diff_Total);

         --  Leave the geometry behind for mouse hit-testing.
         List_Width  := List_Cols;
         Diff_Width  := Diff_Cols;
         View_Rows   := Natural (Content_Rows);
         Screen_Width := S.Cols;

         --  A resize can shrink the list viewport from under the selection.
         if List_Total > 0 then
            Git_View_List.Clamp (List_Eng, List_Total, Selected);
         end if;

         --  Each pane renders into its own surface; the region copy composites
         --  them into the screen.
         if List_Cols > 0 then
            declare
               LS : Surface := Blank (Content_Rows, Col_Count (List_Cols));
            begin
               Eng_Pkg.Render
                 (List_Eng, LS, List_Doc.all.Bytes, List_Doc.all.Idx);
               Colorize_List (LS);
               Highlight_Selection (LS, List_Total);
               Highlight_Text_Selection (LS, Pol.List_Pane, List_Eng);
               Copy (LS, S, At_Row => 1, At_Col => 1);
            end;
         end if;

         if Is_Split then
            declare
               Sep : constant Col_Index := Col_Index (List_Cols + 1);
               Focus_Glyph : constant Wide_Wide_Character :=
                 (if Focused = Pol.List_Pane
                  then Wide_Wide_Character'Val (16#258C#)  --  left half block
                  else Wide_Wide_Character'Val (16#2590#)); -- right half block
            begin
               for R in Row_Index range 1 .. Content_Rows loop
                  Set (S, R, Sep,
                       (Glyph      => Focus_Glyph,
                        Foreground => Thm.Bar_Accent,
                        Attributes => (Bold => True, others => False),
                        others     => <>));
               end loop;
            end;
         end if;
         if Diff_Cols > 0 then
            declare
               DS : Surface := Blank (Content_Rows, Col_Count (Diff_Cols));
            begin
               Eng_Pkg.Render (Diff_Eng, DS, Diff_Doc.all.Bytes,
                               Diff_Doc.all.Idx);
               Colorize_Diff (DS);
               Highlight_Text_Selection (DS, Pol.Diff_Pane, Diff_Eng);
               Copy (DS, S, At_Row => 1, At_Col => Diff_At);
            end;
         end if;

         Draw_Status (S);
      end;
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

   --  Jump to a structural diff landmark without touching pager search state.
   procedure Jump_Diff
     (Target : Nav.Landmark;
      Forward_Jump : Boolean;
      Changed : out Boolean)
   with Global => (In_Out => Diff_Eng, Input => Diff_Doc),
        Pre    => Diff_Doc /= null
   is
      Total : constant Tui.Text.Line_Total :=
        Tui.Text.Line_Count (Diff_Doc.all.Idx);
      Found : Boolean;
      Line  : Tui.Text.Line_Number;
   begin
      Changed := False;
      if Total = 0 then
         return;
      end if;
      Nav.Find
        (Diff_Doc.all.Bytes, Diff_Doc.all.Idx,
         Tui.Text.Line_Number'Min (Eng_Pkg.Top_Line (Diff_Eng), Total),
         Forward_Jump, Target, Found, Line);
      if Found then
         Eng_Pkg.Go_To_Line (Diff_Eng, Line, Total);
         Changed := True;
      end if;
   end Jump_Diff;

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
                 (List_Eng, Edit.Bytes (Pattern));
            else
               Eng_Pkg.Set_Pattern
                 (Diff_Eng, Edit.Bytes (Pattern));
            end if;
            declare
               Ignore : Boolean;
            begin
               Do_Find (Forward, Ignore);
            end;
         when Escape =>
            Searching := False;        --  cancel; leave any prior pattern
         when Backspace =>
            Edit.Backspace (Pattern);
         when Char =>
            Edit.Append (Pattern, Event.Code);
         when others =>
            null;
      end case;
   end Handle_Search_Key;

   --  One wheel notch scrolls this many lines, the desktop convention.
   Wheel_Lines : constant := 3;

   --  Map a mouse cell to the underlying pane's document/display coordinate.
   procedure Mouse_Position
     (Where : Pol.Region;
      Event : Key_Event;
      Pos   : out Sel.Position;
      Valid : out Boolean)
   with Global => (Input => (List_Doc, Diff_Doc, List_Eng, Diff_Eng,
                             List_Width)),
        Pre    => List_Doc /= null and then Diff_Doc /= null
                  and then (if Where = Pol.List_Region then Event.Col >= 1)
                  and then (if Where = Pol.Diff_Region
                            then (if List_Width = 0 then Event.Col >= 1
                                  else Event.Col > List_Width
                                    and then Event.Col - List_Width > 1))
                  and then (if Where in Pol.List_Region | Pol.Diff_Region
                            then Event.Row >= 1)
   is
      Top, Left, Local_Col, Total : Natural;
   begin
      Pos := (Line => 1, Col => 0);
      Valid := False;
      if Where = Pol.List_Region then
         Top       := Eng_Pkg.Top_Line (List_Eng);
         Left      := Eng_Pkg.Left_Col (List_Eng);
         Local_Col := Event.Col - 1;
         Total     := Tui.Text.Line_Count (List_Doc.all.Idx);
      elsif Where = Pol.Diff_Region then
         Top       := Eng_Pkg.Top_Line (Diff_Eng);
         Left      := Eng_Pkg.Left_Col (Diff_Eng);
         Local_Col :=
           (if List_Width = 0 then Event.Col - 1
            else Event.Col - List_Width - 2);
         Total     := Tui.Text.Line_Count (Diff_Doc.all.Idx);
      else
         return;
      end if;

      if Top <= Total and then Event.Row - 1 <= Total - Top then
         Pos.Line := Top + (Event.Row - 1);
         Pos.Col  := Natural'Min (Tui.Pager.Max_Dim, Left + Local_Col);
         Valid    := True;
      end if;
   end Mouse_Position;

   --  Carry out a mouse event against the layout the painter recorded. A
   --  left click loads the commit under the cursor and gives the clicked
   --  pane the keyboard; a drag selects and copies pane text. The wheel
   --  scrolls the pane UNDER the cursor —
   --  deliberately without moving the keyboard focus, so hovering to scroll
   --  never changes what the keys do.
   procedure Handle_Mouse (Event : Key_Event; Changed : out Boolean)
   with Global => (In_Out => (List_Eng, Diff_Eng, Diff_Doc, Diff_Id,
                              Selected, Focused, Note, Selecting,
                              Selection_Shown, Selection_Pane,
                              Selection_Start, Selection_End, Split,
                              Resizing_Split),
                   Input  => (List_Doc, List_Width, Diff_Width, View_Rows,
                              Screen_Width)),
        Pre    => List_Doc /= null and then Diff_Doc /= null,
        Post   => Diff_Doc /= null
   is
      Where : constant Pol.Region :=
        Pol.Locate (Event.Col, Event.Row, List_Width, Diff_Width, View_Rows);
   begin
      Changed := False;
      if Resizing_Split then
         if Event.Kind = Mouse_Motion and then Event.Button = Left_Button
           and then List_Width > 0 and then Diff_Width > 0
           and then Natural (Screen_Width) > 0
         then
            Split := Pol.Split_At (Event.Col, Screen_Width);
            Changed := True;
         elsif Event.Kind = Mouse_Release then
            Resizing_Split := False;
            Changed := True;
         end if;
         return;
      end if;

      if Where = Pol.Separator_Region then
         if Event.Kind = Mouse_Press and then Event.Button = Left_Button then
            Resizing_Split := True;
            Selecting := False;
            Selection_Shown := False;
            Changed := True;
         end if;
         return;
      end if;

      if Where = Pol.Outside then
         if Event.Kind = Mouse_Release then
            Selecting := False;
         end if;
         return;
      end if;

      case Event.Kind is
         when Mouse_Press =>
            if Event.Button = Left_Button then
               declare
                  Pos   : Sel.Position;
                  Valid : Boolean;
               begin
                  Mouse_Position (Where, Event, Pos, Valid);
                  Selecting       := Valid;
                  Selection_Shown := False;
                  if Valid then
                     Selection_Pane  := (if Where = Pol.List_Region
                                        then Pol.List_Pane else Pol.Diff_Pane);
                     Selection_Start := Pos;
                     Selection_End   := Pos;
                  end if;
               end;
               if Where = Pol.List_Region then
                  --  Select and immediately load the line under the cursor.
                  declare
                     Total : constant Tui.Text.Line_Total :=
                       Tui.Text.Line_Count (List_Doc.all.Idx);
                     Top   : constant Tui.Text.Line_Number :=
                       Eng_Pkg.Top_Line (List_Eng);
                     Off   : constant Natural := Event.Row - 1;
                  begin
                     if Total > 0 and then Top <= Total
                       and then Off <= Total - Top
                     then
                        Selected := Top + Off;
                        Changed  := True;
                        declare
                           Opened : Boolean;
                        begin
                           Open_Selected (Opened);
                           Changed := Changed or else Opened;
                        end;
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

         when Mouse_Motion =>
            if Selecting and then Event.Button = Left_Button
              and then ((Selection_Pane = Pol.List_Pane
                         and then Where = Pol.List_Region)
                        or else (Selection_Pane = Pol.Diff_Pane
                                 and then Where = Pol.Diff_Region))
            then
               declare
                  Pos   : Sel.Position;
                  Valid : Boolean;
               begin
                  Mouse_Position (Where, Event, Pos, Valid);
                  if Valid and then Pos /= Selection_End then
                     Selection_End   := Pos;
                     Selection_Shown := Pos /= Selection_Start;
                     Changed         := True;
                  end if;
               end;
            end if;

         when Mouse_Release =>
            if Selecting and then Event.Button = Left_Button then
               declare
                  Pos       : Sel.Position;
                  Valid     : Boolean;
                  Truncated : Boolean;
               begin
                  Mouse_Position (Where, Event, Pos, Valid);
                  if Valid
                    and then ((Selection_Pane = Pol.List_Pane
                               and then Where = Pol.List_Region)
                              or else (Selection_Pane = Pol.Diff_Pane
                                       and then Where = Pol.Diff_Region))
                  then
                     Selection_End   := Pos;
                     Selection_Shown := Pos /= Selection_Start;
                  end if;
                  Selecting := False;
                  if Selection_Shown then
                     if Selection_Pane = Pol.List_Pane then
                        declare
                           Total : constant Tui.Text.Line_Total :=
                             Tui.Text.Line_Count (List_Doc.all.Idx);
                        begin
                           if Selection_Start.Line <= Total
                             and then Selection_End.Line <= Total
                           then
                              Git_View_Clipboard.Copy
                                (List_Doc.all.Bytes, List_Doc.all.Idx,
                                 Selection_Start, Selection_End, Truncated);
                           else
                              Selection_Shown := False;
                              Truncated := False;
                           end if;
                        end;
                     else
                        declare
                           Total : constant Tui.Text.Line_Total :=
                             Tui.Text.Line_Count (Diff_Doc.all.Idx);
                        begin
                           if Selection_Start.Line <= Total
                             and then Selection_End.Line <= Total
                           then
                              Git_View_Clipboard.Copy
                                (Diff_Doc.all.Bytes, Diff_Doc.all.Idx,
                                 Selection_Start, Selection_End, Truncated);
                           else
                              Selection_Shown := False;
                              Truncated := False;
                           end if;
                        end;
                     end if;
                     if Selection_Shown then
                        Note := (if Truncated
                                 then Git_View_Status.Selection_Copy_Truncated
                                 else Git_View_Status.Selection_Copied);
                     end if;
                  end if;
                  Changed := True;
               end;
            end if;

         when Wheel_Up | Wheel_Down =>
            Selection_Shown := False;
            Selecting       := False;
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
            null;
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
          Mouse_Press | Mouse_Release | Mouse_Motion | Wheel_Up | Wheel_Down
      then
         return;
      end if;

      Note := Git_View_Status.No_Note;   --  a keystroke clears a stale note

      if Searching then
         Handle_Search_Key (Event, Dirty, Quit);
         return;
      end if;

      if Event.Kind in
        Mouse_Press | Mouse_Release | Mouse_Motion | Wheel_Up | Wheel_Down
      then
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
               --  In the responsive list-only layout, Tab remains a way to
               --  reach the diff: it opens the newly focused pane maximized.
               if Diff_Width = 0 and then Focused = Pol.Diff_Pane then
                  Maximized := True;
               end if;
               Dirty := True;

            when Pol.Toggle_Maximize =>
               Maximized := not Maximized;
               Dirty := True;

            when Pol.Resize_Split =>
               if not Maximized then
                  Split := Pol.Adjust_Split (Split, D.Grow_List);
                  Dirty := True;
               end if;

            when Pol.Toggle_Syntax =>
               Syntax_Enabled := not Syntax_Enabled;
               Dirty := True;

            when Pol.Jump_Diff =>
               Jump_Diff (D.Target, D.Jump_Forward, Dirty);

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
               Edit.Clear (Pattern);
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
