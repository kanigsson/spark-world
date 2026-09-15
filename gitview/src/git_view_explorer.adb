with Tui.Pager.Engine;
with Tui.App_Kit.Search_Input;
with Tui.Text;
with Tui.Panes;
with Tui.Panes.Clip;
with Tui.Panes.Gesture;
with Tui.Panes.Highlight;
with Tui.Panes.Layout;
with Tui.Panes.List;
with Tui.Panes.Selection;
with Tui.Term.Clipboard;

package body Git_View_Explorer with SPARK_Mode => On,
  Refined_State => (State => (V, Stack, Data, Loading, Input_Mode, Editor,
                             Places, Weights, Rows, Screen_Width, Mouse,
                             Message))
is
   package M renames Git_View_Model;
   package R renames Git_View_Repository;
   package E renames Tui.Pager.Engine;
   package Edit renames Tui.App_Kit.Search_Input;
   package Pan renames Tui.Panes;
   package Lay renames Tui.Panes.Layout;
   package Gest renames Tui.Panes.Gesture;
   package Mark renames Tui.Panes.Highlight;
   package Clip renames Tui.Panes.Clip;
   use type Gest.Gesture_Kind;
   use type M.Pane;
   use type M.Change_Lens;
   use type M.Snapshot_Kind;
   use type M.Text;
   use type Tui.Text.Doc_Ref;
   use type R.Target_Ref;
   use type R.Mark_Ref;
   use type R.Mark;
   use Tui.Surface;
   use Tui.Input;
   V : M.View_State;
   Stack : M.Navigation;
   Data : R.Frame;
   Loading : Boolean := False;
   type Prompt is (No_Prompt, File_Search, Repository_Search, Snapshot_Prompt, Base_Prompt);
   Input_Mode : Prompt := No_Prompt;
   Editor : Edit.Editor;
   Rows : Row_Count := 0;
   Message : M.Text;

   ---------------------------------------------------------------------------
   --  The pane row
   --
   --  Three panes side by side with a separator between each pair. The
   --  source pane gives up its place last, because it is what the explorer
   --  is built around; the tree gives up first, since a scope can be
   --  reached by search instead. Below three panes' worth of minimum width
   --  the row narrows a pane at a time, and the focused pane always
   --  survives, so narrowing the terminal keeps showing what you were
   --  looking at.
   ---------------------------------------------------------------------------

   Min_Pane_Width : constant := 28;

   function Index_Of (P : M.Pane) return Pan.Pane_Index
   is (M.Pane'Pos (P) + 1);

   --  Total, so that a pane index taken from the pane layer needs no bounds
   --  reasoning at every use.
   function Named (I : Pan.Pane_Index) return M.Pane
   is (if I = 1 then M.History_Pane
       elsif I = 2 then M.Tree_Pane
       else M.Source_Pane);

   subtype Places_Array is Lay.Placement_Array (1 .. 3);
   type Weight_Array is array (M.Pane) of Pan.Weight_Percent;

   --  History lines carry the longest text of the three panes while the
   --  source pane needs no more than ordinary code width, so the left
   --  column takes the larger share of a wide terminal. A separator drag
   --  moves these.
   Weights : Weight_Array := (M.History_Pane => 30,
                              M.Tree_Pane    => 25,
                              M.Source_Pane  => 45);

   Places       : Places_Array := (others => (Start_Col => 0, Cols => 0));
   Screen_Width : Col_Count := 0;

   function Specs return Lay.Specs_Array is
     (1 => (Weight   => Weights (M.History_Pane),
            Min_Cols => Min_Pane_Width, Priority => 1),
      2 => (Weight   => Weights (M.Tree_Pane),
            Min_Cols => Min_Pane_Width, Priority => 2),
      3 => (Weight   => Weights (M.Source_Pane),
            Min_Cols => Min_Pane_Width, Priority => 0));

   --  Scrolling a pane here also gives it the keyboard, unlike the legacy
   --  viewer: the explorer's panes are a chain you follow with the pointer,
   --  so the pane you just scrolled is the one you mean to act on next.
   Mouse       : Gest.Recognizer;
   Mouse_Rules : constant Gest.Policy :=
     (Wheel => Gest.Under_Cursor_And_Focus, others => <>);

   procedure Reload
     with Global => (Input => V, Output => (Loading, Message), In_Out => R.State)
   is
   begin
      R.Request (V);
      Loading := True;
      Message := M.To_Text ("");
   end Reload;

   procedure Init
     (From : Git_View_Source.Revision;
      Filter : Git_View_Source.Filters;
      Kind : M.Snapshot_Kind;
      Base : Git_View_Source.Revision)
   is
   begin
      V.History_Root := From;
      V.History_Filter := Filter;
      V.Snapshot := M.To_Text (Git_View_Source.Image (From));
      V.Kind := Kind;
      if Base.Len > 0 then
         V.Base := M.To_Text (Git_View_Source.Image (Base));
         V.Automatic_Base := False;
      end if;
      Reload;
   end Init;

   procedure Tick (Dirty : out Boolean) is
      Ready : Boolean;
   begin
      R.Poll (Data, Ready);
      Dirty := Ready;
      if Ready then
         Loading := False;
         if V.Kind = M.Commit and then Data.Resolved_Snapshot.Last > 0 then
            V.Snapshot := Data.Resolved_Snapshot;
         end if;
         if not V.Automatic_Base and then Data.Resolved_Base.Last > 0 then
            V.Base := Data.Resolved_Base;
         end if;
         if V.Scope.Last = 0 then V.Scope := Data.Scope; end if;
         Message := Data.Notice;
      end if;
   end Tick;

   procedure Stop is
   begin
      R.Stop;
      R.Free (Data);
   end Stop;

   procedure Put
     (S : in out Surface; Row : Row_Index; Text : String;
      Inverse : Boolean := False)
     with Pre => Row <= S.Rows
   is
      C : Col_Count := 0;
   begin
      for Ch of Text loop
         exit when C >= S.Cols;
         C := C + 1;
         Set (S, Row, C,
              (Glyph => (if Character'Pos (Ch) < 32 or else Ch = ASCII.DEL
                         then '?' else Wide_Wide_Character'Val (Character'Pos (Ch))),
               Attributes => (Inverse => Inverse, others => False), others => <>));
      end loop;
   end Put;

   function Input_Text return M.Text is
      B : constant Tui.Text.Buffer := Edit.Bytes (Editor);
      T : M.Text;
   begin
      for I in B'Range loop T.Data (I) := Character'Val (B (I)); end loop;
      T.Last := B'Length;
      return T;
   end Input_Text;

   procedure Paint_Pane
     (S : in out Surface; P : M.Pane;
      Content : Tui.Text.Buffer; Index : Tui.Text.Index)
     with Pre => Rows + 3 <= S.Rows and then Lay.Shown (Places (Index_Of (P)))
       and then Places (Index_Of (P)).Start_Col >= 1
       and then Places (Index_Of (P)).Start_Col - 1
                  + Places (Index_Of (P)).Cols <= Natural (S.Cols)
       and then Content'First = 1 and then Content'Last >= Tui.Text.Scanned_Bytes (Index)
   is
      Place : constant Lay.Placement := Places (Index_Of (P));
      Width : constant Col_Count := Col_Count (Place.Cols);
      At_Col : constant Col_Index := Col_Index (Place.Start_Col);
      Total : constant Tui.Text.Line_Total := Tui.Text.Line_Count (Index);
      Part : Surface := Blank (Rows, Width);
      Title : Surface := Blank (1, Width);
   begin
      E.Resize (V.Views (P), Natural (Rows), Natural (Width), Total);
      if Total > 0 and then P /= M.Source_Pane then
         Tui.Panes.List.Clamp (V.Views (P), Total, V.Selected (P));
      end if;
      E.Render (V.Views (P), Part, Content, Index);
      for Row in Row_Index range 1 .. Rows loop
         declare
            Line : constant Natural := E.Top_Line (V.Views (P)) + Natural (Row) - 1;
            Kind : R.Mark := R.Normal;
         begin
            if P = M.Source_Pane and then Data.Marks /= null
              and then Line in Data.Marks'Range
            then Kind := Data.Marks (Line); end if;
            if P /= M.Source_Pane and then Line = V.Selected (P) then
               Mark.Row (Part, Row);
            elsif P = M.Source_Pane then
               for C in Col_Index range 1 .. Part.Cols loop
                  declare
                     Cell_Value : Cell := Get (Part, Row, C);
                  begin
                     if Kind = R.Ghost then
                        Cell_Value.Background := (RGB, 255, 235, 233);
                        Cell_Value.Attributes.Italic := True;
                     elsif Kind = R.Addition then
                        if V.Lens /= M.Gutter or else C = 1 then
                           Cell_Value.Background := (RGB, 230, 255, 236);
                        end if;
                        Cell_Value.Attributes.Bold := V.Lens = M.Changed_Lines;
                     elsif Kind = R.Hunk_Header then
                        Cell_Value.Foreground := (Palette, 6);
                     elsif V.Lens = M.Changed_Lines then
                        Cell_Value.Foreground := (Palette, 8);
                     end if;
                     Set (Part, Row, C, Cell_Value);
                  end;
               end loop;
            end if;
         end;
      end loop;

      --  A retained mouse selection sits on top of the pane's own colours,
      --  toggling inverse video so it stays legible over a selected row.
      if Gest.Has_Selection (Mouse)
        and then Named (Gest.Selected_Pane (Mouse)) = P
      then
         declare
            First, Last : Tui.Panes.Selection.Position;
         begin
            Gest.Selected_Range (Mouse, First, Last);
            Mark.Overlay (Part, E.Top_Line (V.Views (P)),
                          E.Left_Col (V.Views (P)), First, Last);
         end;
      end if;

      Put (Title, 1, (case P is when M.History_Pane => "HISTORY",
                       when M.Tree_Pane => "TREE / " & M.Tree_Visibility'Image (V.Visibility),
                       when M.Source_Pane => "SOURCE / " & M.Change_Lens'Image (V.Lens)), V.Focus = P);
      Copy (Title, S, 1, At_Col);
      Copy (Part, S, 2, At_Col);
   end Paint_Pane;

   procedure Paint (S : in out Surface) is
   begin
      Places := (others => (Start_Col => 0, Cols => 0));
      Rows := 0;
      Screen_Width := S.Cols;
      if S.Rows < 5 or else S.Cols < 1 then return; end if;
      Rows := S.Rows - 4;

      Lay.Compute (Specs      => Specs,
                   Total_Cols => S.Cols,
                   Focused    => Index_Of (V.Focus),
                   Maximized  => V.Maximized,
                   Separators => True,
                   Rule       => Lay.Keep_Focused,
                   Result     => Places);

      if Loading then
         Put (S, 1, "Loading repository... (navigation and q remain available)");
      elsif R.Loaded (Data) then
         if Lay.Shown (Places (Index_Of (M.History_Pane))) then
            Paint_Pane (S, M.History_Pane, Data.History.Bytes, Data.History.Idx);
         end if;
         if Lay.Shown (Places (Index_Of (M.Tree_Pane))) then
            Paint_Pane (S, M.Tree_Pane, Data.Tree.Bytes, Data.Tree.Idx);
         end if;
         if Lay.Shown (Places (Index_Of (M.Source_Pane))) then
            Paint_Pane (S, M.Source_Pane, Data.Source.Bytes, Data.Source.Idx);
         end if;

         --  A separator column between each adjacent pair, leaning towards
         --  the pane that has the keyboard.
         for P in M.Pane loop
            declare
               Place : constant Lay.Placement := Places (Index_Of (P));
            begin
               if Lay.Shown (Place)
                 and then P /= M.Source_Pane
                 and then Lay.Shown (Places (Index_Of (M.Pane'Succ (P))))
               then
                  Mark.Separator
                    (S,
                     At_Col      => Col_Index (Place.Start_Col + Place.Cols),
                     Rows        => Rows + 1,
                     Points_Left => V.Focus = P,
                     Foreground  => (Palette, 4));
               end if;
            end;
         end loop;
      end if;
      declare
         Snapshot : constant M.Text := (if Loading then V.Snapshot else Data.Resolved_Snapshot);
         Base : constant M.Text := (if Loading then V.Base else Data.Resolved_Base);
      begin
         Put (S, S.Rows - 1, "snapshot: " & Snapshot.Data (1 .. Natural'Min (12, Snapshot.Last))
           & "  base: " & Base.Data (1 .. Natural'Min (12, Base.Last))
           & "  scope: " & M.Image (V.Scope)
           & "  lens: " & M.Change_Lens'Image (V.Lens), True);
      end;
      if Input_Mode /= No_Prompt then
         Put (S, S.Rows, Prompt'Image (Input_Mode) & ": " & M.Image (Input_Text), True);
      elsif Message.Last > 0 then Put (S, S.Rows, M.Image (Message));
      else
         Put (S, S.Rows, "Tab panes  a tree  d lens  f history  p pin  [/] hunks  {/} files  / search  S repo-search  c snapshot  b base  w worktree  i index  BS back  Alt-Right forward");
      end if;
      if V.Pin.Last > 0 or else V.Path_Filter.Last > 0 or else V.Repository_Search.Last > 0 then
         Put (S, S.Rows - 2, "pin: " & M.Image (V.Pin) & "  history filter: "
              & M.Image (V.Path_Filter) & "  search: " & M.Image (V.Repository_Search));
      elsif V.History_Filter.Path.Len > 0 then
         Put (S, S.Rows - 2, "history filter: " & Git_View_Source.Image (V.History_Filter.Path));
      end if;
   end Paint;

   procedure Drive (Cmd : E.Command)
     with Global => (Input => Data, In_Out => V)
   is
      Result : E.Effect;
   begin
      case V.Focus is
         when M.History_Pane =>
            if Data.History /= null then E.Handle (V.Views (V.Focus), Cmd, Data.History.Bytes, Data.History.Idx, Result); end if;
         when M.Tree_Pane =>
            if Data.Tree /= null then E.Handle (V.Views (V.Focus), Cmd, Data.Tree.Bytes, Data.Tree.Idx, Result); end if;
         when M.Source_Pane =>
            if Data.Source /= null then E.Handle (V.Views (V.Focus), Cmd, Data.Source.Bytes, Data.Source.Idx, Result); end if;
      end case;
      if V.Focus = M.Source_Pane then
         V.Selected (M.Source_Pane) := E.Top_Line (V.Views (M.Source_Pane));
      end if;
   end Drive;

   procedure Move_Selection (Down : Boolean)
     with Global => (Input => (Data, Rows), In_Out => V)
   is
      Total : Natural := 0;
   begin
      case V.Focus is
         when M.History_Pane => if Data.History /= null then Total := Tui.Text.Line_Count (Data.History.Idx); end if;
         when M.Tree_Pane => if Data.Tree /= null then Total := Tui.Text.Line_Count (Data.Tree.Idx); end if;
         when M.Source_Pane => Drive ((if Down then E.Line_Down else E.Line_Up)); return;
      end case;
      if Down then
         if V.Selected (V.Focus) < Total and then V.Selected (V.Focus) < Tui.Text.Line_Number'Last then
            V.Selected (V.Focus) := V.Selected (V.Focus) + 1;
         end if;
      elsif V.Selected (V.Focus) > 1 then V.Selected (V.Focus) := V.Selected (V.Focus) - 1;
      end if;
      if V.Selected (V.Focus) < E.Top_Line (V.Views (V.Focus)) then Drive (E.Line_Up);
      elsif V.Selected (V.Focus) >= E.Top_Line (V.Views (V.Focus)) + Natural (Rows) then Drive (E.Line_Down);
      end if;
   end Move_Selection;

   procedure Follow
     with Global => (Input => Data, In_Out => (V, Stack, Loading, Message, R.State))
   is
      Row : constant Tui.Text.Line_Number := V.Selected (V.Focus);
   begin
      if V.Focus = M.History_Pane and then Data.Commits /= null and then Row in Data.Commits'Range then
         M.Push (Stack, V);
         M.Select_Snapshot (V, Data.Commits (Row).Path);
         Reload;
      elsif V.Focus = M.Tree_Pane and then Data.Paths /= null and then Row in Data.Paths'Range then
         declare
            Target : constant R.Row_Target := Data.Paths (Row);
         begin
            M.Push (Stack, V);
            M.Select_Scope (V, Target.Path);
            if Target.Path.Last > 0 and then Target.Path.Data (Target.Path.Last) = '/' then
               V.Path_Filter := Target.Path;
            else
               V.Focus := M.Source_Pane;
               if V.Repository_Search.Last > 0 then
                  V.Lens := M.Plain;
                  E.Go_To_Line (V.Views (M.Source_Pane), Target.Line, Tui.Text.Max_Lines);
               end if;
            end if;
            Reload;
         end;
      end if;
   end Follow;

   procedure Jump_Change (Next, File : Boolean)
     with Global => (Input => Data, In_Out => (V, Stack, Loading, Message, R.State))
   is
      Row : Tui.Text.Line_Total := 0;
      Last : Tui.Text.Line_Total := 0;
      Found : Boolean := False;
   begin
      if File then
         Row := V.Selected (M.Tree_Pane);
         if Data.Paths /= null then
            Last := Natural'Min (Tui.Text.Max_Lines, Natural'Max (0, Data.Paths'Last));
            for I in Data.Paths'Range loop
               if Data.Paths (I).Path = V.Scope then Row := I; exit; end if;
            end loop;
         end if;
      else
         Row := V.Selected (M.Source_Pane);
         if Data.Marks /= null then
            Last := Natural'Min (Tui.Text.Max_Lines, Natural'Max (0, Data.Marks'Last));
         end if;
      end if;
      while Row in 1 .. Last loop
         if Next then exit when Row = Last; Row := Row + 1;
         else exit when Row = 1; Row := Row - 1; end if;
         if File and then Data.Paths /= null and then Row in Data.Paths'Range then
            Found := Data.Paths (Row).Changed and then Data.Paths (Row).Path.Last > 0
              and then Data.Paths (Row).Path.Data (Data.Paths (Row).Path.Last) /= '/';
         elsif not File and then Data.Marks /= null and then Row in Data.Marks'Range then
            Found := Data.Marks (Row) = R.Hunk_Header
              or else (Data.Marks (Row) in R.Addition | R.Ghost
                and then (Row = Data.Marks'First or else Data.Marks (Row - 1) = R.Normal));
         end if;
         exit when Found;
      end loop;
      if Found and then Row in Tui.Text.Line_Number then
         if File then
            V.Focus := M.Tree_Pane; V.Selected (M.Tree_Pane) := Row; Follow;
         elsif Data.Source /= null then
            V.Selected (M.Source_Pane) := Row;
            E.Go_To_Line (V.Views (M.Source_Pane), Row, Tui.Text.Line_Count (Data.Source.Idx));
         end if;
      end if;
   end Jump_Change;

   --  What the recognizer needs to turn a screen cell into a document
   --  position: each pane's viewport offsets and how much document it has.
   procedure Pane_Frames (F : out Gest.Frame_Array)
     with Global => (Input => (V, Data)),
          Pre => F'First = 1 and then F'Last = 3
   is
      Total : Tui.Text.Line_Total;
   begin
      F := (others => (Top => 1, Left => 0, Total => 0));
      for P in M.Pane loop
         Total := 0;
         case P is
            when M.History_Pane =>
               if Data.History /= null then
                  Total := Tui.Text.Line_Count (Data.History.Idx);
               end if;
            when M.Tree_Pane =>
               if Data.Tree /= null then
                  Total := Tui.Text.Line_Count (Data.Tree.Idx);
               end if;
            when M.Source_Pane =>
               if Data.Source /= null then
                  Total := Tui.Text.Line_Count (Data.Source.Idx);
               end if;
         end case;
         F (Index_Of (P)) := (Top   => E.Top_Line (V.Views (P)),
                              Left  => E.Left_Col (V.Views (P)),
                              Total => Total);
      end loop;
   end Pane_Frames;

   --  Put a committed drag on the clipboard. The bounds are re-tested here
   --  because a drag outlives the events that made it: a repository query
   --  can have replaced the document under it in between.
   procedure Copy_Selection (G : Gest.Gesture)
     with Global => (Input => Data, In_Out => (Message, Mouse)),
          Pre => G.Kind = Gest.Range_Committed
                 and then Tui.Panes.Selection.Before_Or_Equal
                            (G.First, G.Last)
   is
      P : constant M.Pane := Named (G.Pane);

      --  The document is reached through its own pane's branch rather than
      --  through a shared reference: an access value read out of the frame
      --  would be a move, and the frame keeps ownership.
      Total : constant Tui.Text.Line_Total :=
        (case P is
            when M.History_Pane =>
              (if Data.History /= null
               then Tui.Text.Line_Count (Data.History.Idx) else 0),
            when M.Tree_Pane =>
              (if Data.Tree /= null
               then Tui.Text.Line_Count (Data.Tree.Idx) else 0),
            when M.Source_Pane =>
              (if Data.Source /= null
               then Tui.Text.Line_Count (Data.Source.Idx) else 0));
      Text : Clip.Payload;
      Truncated : Boolean := False;
   begin
      if Total = 0 or else G.Last.Line > Total then
         Gest.Reset (Mouse);
         return;
      end if;
      case P is
         when M.History_Pane =>
            Clip.Extract (Data.History.Bytes, Data.History.Idx,
                          G.First, G.Last, Text, Truncated);
         when M.Tree_Pane =>
            Clip.Extract (Data.Tree.Bytes, Data.Tree.Idx,
                          G.First, G.Last, Text, Truncated);
         when M.Source_Pane =>
            Clip.Extract (Data.Source.Bytes, Data.Source.Idx,
                          G.First, G.Last, Text, Truncated);
      end case;
      Tui.Term.Clipboard.Set (Text);
      Message := M.To_Text
        (if Truncated then "Selection copied (truncated)"
         else "Selection copied");
   end Copy_Selection;

   --  Move a separator: the pane to its left takes the width the drag asks
   --  for and its right-hand neighbour gives up exactly that much, so the
   --  rest of the row stays where it is.
   procedure Resize_At (Left : Pan.Pane_Index; Column : Natural)
     with Global => (Input => (Places, Screen_Width), In_Out => Weights),
          Pre => Left <= 2
   is
      Left_Pane  : constant M.Pane := Named (Left);
      Right_Pane : constant M.Pane := Named (Left + 1);
      Pair       : constant Natural :=
        Weights (Left_Pane) + Weights (Right_Pane);
      Start      : constant Natural := Places (Left).Start_Col;
      Wanted     : Natural;
   begin
      if Natural (Screen_Width) = 0 or else Start = 0
        or else Column <= Start
        or else Start >= Natural (Screen_Width)
        or else Pair < 10 or else Pair > 100
      then
         return;
      end if;
      Wanted := ((Natural'Min (Column, Natural (Screen_Width)) - Start) * 100)
                / Natural (Screen_Width);
      Wanted := Natural'Max (5, Natural'Min (Pair - 5, Wanted));
      Weights (Left_Pane)  := Wanted;
      Weights (Right_Pane) := Pair - Wanted;
   end Resize_At;

   --  Carry out a mouse event against the layout the painter recorded. The
   --  pane layer decides what the gesture IS; this decides what it means —
   --  a click follows the row under it, a drag reaches the clipboard, a
   --  separator drag reshapes the row.
   procedure Handle_Mouse (Event : Key_Event; Dirty : in out Boolean)
     with Global => (Input => (Places, Rows, Screen_Width),
                     In_Out => (V, Stack, Data, Loading, Message, Weights,
                                Mouse, R.State))
   is
      Frames : Gest.Frame_Array (1 .. 3);
      G      : Gest.Gesture;
   begin
      Pane_Frames (Frames);
      Gest.Feed (R            => Mouse,
                 Event        => Event,
                 Placements   => Places,
                 Frames       => Frames,
                 First_Row    => 2,        --  row 1 is the pane title
                 Content_Rows => Natural (Rows),
                 Focused      => Index_Of (V.Focus),
                 Rules        => Mouse_Rules,
                 Result       => G);

      case G.Kind is
         when Gest.Click =>
            if G.Takes_Focus then
               V.Focus := Named (G.Pane);
            end if;
            if G.On_Line then
               V.Selected (Named (G.Pane)) := G.At_Line;
               Follow;
            end if;

         when Gest.Range_Committed =>
            Copy_Selection (G);

         when Gest.Separator_Dragged =>
            if G.Pane <= 2 then
               Resize_At (G.Pane, G.Split_Col);
            end if;

         when Gest.Wheel =>
            if G.Takes_Focus then
               V.Focus := Named (G.Pane);
            end if;
            for Step in 1 .. G.Notches loop
               Move_Selection (not G.Upward);
            end loop;

         when Gest.Range_Extended | Gest.Range_Cancelled =>
            null;

         when Gest.None =>
            Dirty := False;
      end case;
   end Handle_Mouse;

   procedure On_Key (Event : Key_Event; Dirty, Quit : out Boolean) is
      Ch : Character := ASCII.NUL;
   begin
      Dirty := True; Quit := False;
      if Event.Kind = Char and then Event.Code <= 127 then Ch := Character'Val (Event.Code); end if;
      if Input_Mode /= No_Prompt then
         case Event.Kind is
            when Escape => Input_Mode := No_Prompt;
            when Backspace => Edit.Backspace (Editor);
            when Char => Edit.Append (Editor, Event.Code);
            when Enter =>
               if Input_Mode = File_Search then
                  E.Set_Pattern (V.Views (V.Focus), Edit.Bytes (Editor)); Drive (E.Find_Next);
               else
                  M.Push (Stack, V);
                  case Input_Mode is
                     when Repository_Search =>
                        V.Repository_Search := Input_Text; V.Focus := M.Tree_Pane;
                        V.Selected (M.Tree_Pane) := 1;
                     when Snapshot_Prompt =>
                        M.Select_Snapshot (V, Input_Text);
                        if Edit.Length (Editor) <= Git_View_Source.Max_Revision_Length then
                           declare
                              Valid : Boolean;
                           begin Git_View_Source.Make_Revision (M.Image (Input_Text), V.History_Root, Valid); end;
                        end if;
                     when Base_Prompt => V.Base := Input_Text; V.Automatic_Base := V.Base.Last = 0;
                     when others => null;
                  end case;
                  Reload;
               end if;
               Input_Mode := No_Prompt;
            when others => null;
         end case;
         return;
      end if;
      if Ch = 'q' then Quit := True; return; end if;
      if Event.Kind = Backspace or else (Event.Mods.Alt and then Event.Kind = Left) then
         if M.Can_Back (Stack) then M.Back (Stack, V); Reload; end if; return;
      elsif Event.Mods.Alt and then Event.Kind = Right then
         if M.Can_Forward (Stack) then M.Forward (Stack, V); Reload; end if; return;
      end if;
      if Event.Kind = Tab then
         V.Focus := (if V.Focus = M.Source_Pane then M.History_Pane else M.Pane'Succ (V.Focus));
      elsif Ch = 'z' then V.Maximized := not V.Maximized;
      elsif Ch = 'w' or else Ch = 'i' then
         M.Push (Stack, V); M.Select_Snapshot (V, M.To_Text (""), (if Ch = 'w' then M.Worktree else M.Staging)); Reload;
      elsif Ch = 'c' or else Ch = 'b' or else Ch = '/' or else Ch = 'S' then
         Edit.Clear (Editor);
         Input_Mode := (case Ch is when 'c' => Snapshot_Prompt, when 'b' => Base_Prompt,
                          when '/' => File_Search, when others => Repository_Search);
      elsif Loading then null;
      elsif Event.Kind in Mouse_Press | Mouse_Release | Mouse_Motion
                        | Wheel_Up | Wheel_Down
      then
         Handle_Mouse (Event, Dirty);
      elsif Event.Kind = Enter then Follow;
      elsif Event.Kind = Down or else Ch = 'j' then Move_Selection (True);
      elsif Event.Kind = Up or else Ch = 'k' then Move_Selection (False);
      elsif Event.Kind = Left or else Ch = 'h' then Drive (E.Col_Left);
      elsif Event.Kind = Right or else Ch = 'l' then Drive (E.Col_Right);
      elsif Event.Kind = Page_Down or else Ch = ' ' then Drive (E.Page_Down);
      elsif Event.Kind = Page_Up then Drive (E.Page_Up);
      elsif Event.Kind = Home or else Ch = 'g' then Drive (E.To_Top);
      elsif Event.Kind = End_Key or else Ch = 'G' then Drive (E.To_Bottom);
      elsif Ch = 'n' then Drive (E.Find_Next);
      elsif Ch = 'N' then Drive (E.Find_Prev);
      elsif Ch = 'd' then M.Push (Stack, V); M.Cycle_Lens (V); Reload;
      elsif Ch = 'a' then M.Push (Stack, V); M.Cycle_Tree (V); Reload;
      elsif Ch = 'p' then M.Push (Stack, V); M.Toggle_Pin (V);
      elsif Ch = 'f' then M.Push (Stack, V); V.Path_Filter := V.Scope; Reload;
      elsif Ch = 'F' then
         M.Push (Stack, V); V.Path_Filter := M.To_Text ("");
         V.History_Filter.Path.Len := 0; V.Repository_Search := M.To_Text (""); Reload;
      elsif Ch = 'r' then R.Request (V, Refresh => True); Loading := True;
      elsif Ch = ']' or else Ch = '[' then Jump_Change (Ch = ']', False);
      elsif Ch = '}' or else Ch = '{' then Jump_Change (Ch = '}', True);
      else Dirty := False;
      end if;
   end On_Key;
end Git_View_Explorer;
