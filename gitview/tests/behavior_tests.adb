--  Behaviour_Tests -- deterministic tests for the viewer's decision policies.
--
--  Proof establishes that these units cannot fail at run time; it says
--  nothing about what they decide. This suite pins the decisions themselves:
--  which byte sequence is a commit id, where a ref decoration sits, which
--  lines are structural landmarks, what a diff line and a source token are,
--  what a keystroke means in each pane, how the width is split between the
--  panes, and the exact status text. They are the regression net for moving
--  this code between frontends and crates, where a rewrite that stays
--  provably safe can still quietly change an answer.
--
--  No repository, no terminal, no timing: every input is a literal here.

with Ada.Command_Line;
with Ada.Text_IO;

with Tui.Input;
with Tui.Pager.Engine;
with Tui.Surface;
with Tui.Text;

with Git_View_Navigation;
with Git_View_Policy;
with Git_View_Refs;
with Git_View_Sha;
with Git_View_Status;
with Git_View_Syntax;
with Git_View_Theme;

procedure Behavior_Tests is

   use type Tui.Pager.Engine.Command;
   use type Tui.Text.Byte_Count;

   package Nav renames Git_View_Navigation;
   package Pol renames Git_View_Policy;
   package Syn renames Git_View_Syntax;
   package Thm renames Git_View_Theme;

   Checks   : Natural := 0;
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; What : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & What);
      end if;
   end Check;

   --  The literal text of a test line, as the byte buffer every unit here
   --  takes. 1-based, which is what the buffer contracts require.
   function Bytes (S : String) return Tui.Text.Buffer is
      B : Tui.Text.Buffer (1 .. S'Length);
   begin
      for I in 1 .. S'Length loop
         B (I) := Character'Pos (S (S'First + (I - 1)));
      end loop;
      return B;
   end Bytes;

   --  A document over literal text, line-indexed. Caller frees it.
   function Doc (S : String) return Tui.Text.Doc_Ref is
     (Tui.Text.New_Document (Bytes (S)));

   function Ch (C : Character) return Tui.Input.Key_Event is
     ((Kind => Tui.Input.Char, Code => Character'Pos (C), others => <>));

   function Ctrl_Key (C : Character) return Tui.Input.Key_Event is
     ((Kind   => Tui.Input.Char,
       Mods   => (Ctrl => True, others => False),
       Code   => Character'Pos (C),
       others => <>));

   function Key (K : Tui.Input.Key_Kind) return Tui.Input.Key_Event is
     ((Kind => K, others => <>));

   --------------------------
   -- Commit-id extraction --
   --------------------------

   procedure Test_Commit_Ids is
      --  One document per shape, so the tested line is always line 1 and the
      --  parse is not entangled with the line index.
      procedure Parses (Text : String; Expect : String) is
         D : Tui.Text.Doc_Ref := Doc (Text & ASCII.LF);
         S : Git_View_Sha.Sha;
      begin
         Git_View_Sha.Extract (D.Bytes, D.Idx, 1, S);
         Check (Git_View_Sha.Valid (S)
                and then Git_View_Sha.Image (S) = Expect,
                "commit id of """ & Text & """ is """ & Expect & """");
         Tui.Text.Free (D);
      end Parses;

      procedure Rejects (Text : String; Why : String) is
         D : Tui.Text.Doc_Ref := Doc (Text & ASCII.LF);
         S : Git_View_Sha.Sha;
      begin
         Git_View_Sha.Extract (D.Bytes, D.Idx, 1, S);
         Check (not Git_View_Sha.Valid (S), "no commit id: " & Why);
         Tui.Text.Free (D);
      end Rejects;

      Forty : constant String (1 .. 40) := (others => 'a');
   begin
      Parses ("1a2b3c4 2026-09-10 subject", "1a2b3c4");
      Parses ("deadbeef", "deadbeef");           --  no trailing field
      Parses (Forty & " subject", Forty);        --  a full object name
      Rejects ("", "an empty line");
      Rejects ("   indented", "a line starting with a space");
      Rejects ("zzz1234 subject", "a non-hexadecimal token");
      Rejects ("1A2B3C4 subject", "uppercase: git prints ids in lowercase");
      Rejects (Forty & "a rest", "a token longer than an object name");
      Rejects ("* 1a2b3c4 subject", "a graph column before the id");
   end Test_Commit_Ids;

   ---------------------------
   -- Ref-decoration spans   --
   ---------------------------

   procedure Test_Decorations is
      --  "%h %ad" puts the bracket at Sha_Length + 12: the id, a space, ten
      --  date bytes, and git's own space before the decoration.
      Decorated : constant String :=
        "abc1234 2026-09-10 [HEAD -> main] subject";
      Found     : Boolean;
      From, To  : Tui.Text.Byte_Count;
   begin
      Git_View_Refs.Decoration_Span (Bytes (Decorated), 7, Found, From, To);
      Check (Found and then From = 19 and then To = 32,
             "the decoration span covers [HEAD -> main]");
      Check (Decorated (Decorated'First + 19) = '['
             and then Decorated (Decorated'First + 32) = ']',
             "the span's ends are the brackets themselves");

      Git_View_Refs.Decoration_Span
        (Bytes ("abc1234 2026-09-10 subject"), 7, Found, From, To);
      Check (not Found, "an undecorated line has no span");

      Git_View_Refs.Decoration_Span
        (Bytes ("abc1234 2026-09-10 [HEAD"), 7, Found, From, To);
      Check (not Found, "an unterminated bracket is not a span");

      --  The offset is computed from the id's length; a wrong length looks
      --  elsewhere and must simply miss rather than colour the wrong bytes.
      Git_View_Refs.Decoration_Span (Bytes (Decorated), 8, Found, From, To);
      Check (not Found, "a mismatched id length finds no bracket");

      Git_View_Refs.Decoration_Span (Bytes ("abc1234"), 7, Found, From, To);
      Check (not Found, "a line too short to reach the bracket");

      Git_View_Refs.Decoration_Span (Bytes (""), 0, Found, From, To);
      Check (not Found, "an empty line");
   end Test_Decorations;

   --  A small but complete git-show shape, shared by the landmark and
   --  language tests. Line numbers are given in the checks below.
   Show_Text : constant String :=
     "commit 1a2b3c4d"                    & ASCII.LF   --   1
     & ""                                 & ASCII.LF   --   2
     & "    subject line"                 & ASCII.LF   --   3
     & ""                                 & ASCII.LF   --   4
     & "diff --git a/src/x.adb b/src/x.adb" & ASCII.LF --   5
     & "index 1111111..2222222 100644"    & ASCII.LF   --   6
     & "--- a/src/x.adb"                  & ASCII.LF   --   7
     & "+++ b/src/x.adb"                  & ASCII.LF   --   8
     & "@@ -1,2 +1,3 @@ procedure X"      & ASCII.LF   --   9
     & " context"                         & ASCII.LF   --  10
     & "+   return;"                      & ASCII.LF   --  11
     & "diff --git a/y.py b/y.py"         & ASCII.LF   --  12
     & "--- a/y.py"                       & ASCII.LF   --  13
     & "+++ b/y.py"                       & ASCII.LF   --  14
     & "@@ -1 +1 @@"                      & ASCII.LF   --  15
     & "-old"                             & ASCII.LF   --  16
     & "+def f():"                        & ASCII.LF;  --  17

   ------------------------
   -- Landmark navigation --
   ------------------------

   procedure Test_Landmarks is
      D     : Tui.Text.Doc_Ref := Doc (Show_Text);
      Found : Boolean;
      Line  : Tui.Text.Line_Number;
   begin
      Check (Tui.Text.Line_Count (D.Idx) = 17, "the fixture has 17 lines");

      Check (Nav.Is_Landmark (D.Bytes, D.Idx, 5, Nav.File_Header),
             "a diff --git line is a file header");
      Check (not Nav.Is_Landmark (D.Bytes, D.Idx, 6, Nav.File_Header),
             "an index line is not a file header");
      Check (not Nav.Is_Landmark (D.Bytes, D.Idx, 7, Nav.File_Header),
             "a --- path line is not a file header");
      Check (Nav.Is_Landmark (D.Bytes, D.Idx, 9, Nav.Hunk_Header),
             "an @@ line is a hunk header");
      Check (not Nav.Is_Landmark (D.Bytes, D.Idx, 10, Nav.Hunk_Header),
             "a context line is not a hunk header");
      Check (not Nav.Is_Landmark (D.Bytes, D.Idx, 5, Nav.Hunk_Header),
             "a file header is not a hunk header");

      Nav.Find (D.Bytes, D.Idx, 1, True, Nav.File_Header, Found, Line);
      Check (Found and then Line = 5, "the first file header is line 5");

      Nav.Find (D.Bytes, D.Idx, 5, True, Nav.File_Header, Found, Line);
      Check (Found and then Line = 12,
             "forward from a landmark finds the NEXT one, not itself");

      Nav.Find (D.Bytes, D.Idx, 12, True, Nav.File_Header, Found, Line);
      Check (not Found and then Line = 12,
             "a forward miss leaves the position where it was");

      Nav.Find (D.Bytes, D.Idx, 17, False, Nav.Hunk_Header, Found, Line);
      Check (Found and then Line = 15, "backward from the end finds line 15");

      Nav.Find (D.Bytes, D.Idx, 9, False, Nav.Hunk_Header, Found, Line);
      Check (not Found and then Line = 9,
             "a backward miss leaves the position where it was");

      Nav.Find (D.Bytes, D.Idx, 1, True, Nav.Hunk_Header, Found, Line);
      Check (Found and then Line = 9, "the first hunk header is line 9");

      Tui.Text.Free (D);

      --  Prefixes of the markers must not count as landmarks.
      declare
         Near : Tui.Text.Doc_Ref :=
           Doc ("@" & ASCII.LF & "diff --gi" & ASCII.LF
                & "diff --gitx" & ASCII.LF);
      begin
         Check (not Nav.Is_Landmark (Near.Bytes, Near.Idx, 1,
                                     Nav.Hunk_Header),
                "a single @ is not a hunk header");
         Check (not Nav.Is_Landmark (Near.Bytes, Near.Idx, 2,
                                     Nav.File_Header),
                "a truncated diff --gi is not a file header");
         Check (not Nav.Is_Landmark (Near.Bytes, Near.Idx, 3,
                                     Nav.File_Header),
                "diff --git needs its trailing space");
         Tui.Text.Free (Near);
      end;
   end Test_Landmarks;

   ------------------------------
   -- Diff-line classification --
   ------------------------------

   procedure Test_Diff_Lines is
      use type Thm.Line_Kind;

      procedure Kind_Of (Text : String; Expect : Thm.Line_Kind) is
      begin
         Check (Thm.Classify (Bytes (Text)) = Expect,
                """" & Text & """ classifies as " & Expect'Image);
      end Kind_Of;
   begin
      --  File metadata outranks the one-character polarity markers its own
      --  lines begin with; that ordering is the point of the classifier.
      Kind_Of ("+++ b/src/x.adb", Thm.File_Meta);
      Kind_Of ("--- a/src/x.adb", Thm.File_Meta);
      Kind_Of ("diff --git a/x b/x", Thm.File_Meta);
      Kind_Of ("index 1111111..2222222 100644", Thm.File_Meta);
      Kind_Of ("new file mode 100644", Thm.File_Meta);
      Kind_Of ("deleted file mode 100644", Thm.File_Meta);
      Kind_Of ("rename from old.txt", Thm.File_Meta);
      Kind_Of ("similarity index 95%", Thm.File_Meta);
      Kind_Of ("Binary files a/x and b/x differ", Thm.File_Meta);

      Kind_Of ("@@ -1,2 +1,3 @@", Thm.Hunk);
      Kind_Of ("+added", Thm.Added);
      Kind_Of ("-removed", Thm.Removed);
      Kind_Of ("commit 1a2b3c4d", Thm.Commit_Head);

      Kind_Of (" context", Thm.Plain_Line);
      Kind_Of ("", Thm.Plain_Line);
      Kind_Of ("    subject line", Thm.Plain_Line);
      Kind_Of ("commit", Thm.Plain_Line);       --  no space: not the header
      Kind_Of ("indexed", Thm.Plain_Line);      --  no space: not metadata
      Kind_Of ("++", Thm.Added);                --  a "++" source line
      Kind_Of ("@", Thm.Plain_Line);
   end Test_Diff_Lines;

   ------------------------------
   -- Syntax classification     --
   ------------------------------

   procedure Test_Syntax is
      use type Syn.Language;

      procedure Header (Text : String; Expect : Syn.Language) is
         Found : Boolean;
         Lang  : Syn.Language;
      begin
         Syn.Header_Language (Bytes (Text), Found, Lang);
         Check (Found and then Lang = Expect,
                """" & Text & """ selects " & Expect'Image);
      end Header;

      procedure No_Header (Text : String; Why : String) is
         Found : Boolean;
         Lang  : Syn.Language;
      begin
         Syn.Header_Language (Bytes (Text), Found, Lang);
         Check (not Found, "not a language header: " & Why);
      end No_Header;

      procedure Keyword (Text : String; Lang : Syn.Language) is
         B : constant Tui.Text.Buffer := Bytes (Text);
      begin
         Check (Syn.Is_Keyword (B, B'First, B'Last, Lang),
                """" & Text & """ is a " & Lang'Image & " keyword");
      end Keyword;

      procedure Not_Keyword (Text : String; Lang : Syn.Language) is
         B : constant Tui.Text.Buffer := Bytes (Text);
      begin
         Check (not Syn.Is_Keyword (B, B'First, B'Last, Lang),
                """" & Text & """ is not a " & Lang'Image & " keyword");
      end Not_Keyword;

      procedure Comment (Text : String; Lang : Syn.Language; Yes : Boolean) is
         B : constant Tui.Text.Buffer := Bytes (Text);
      begin
         Check (Syn.Starts_Comment (B, B'First, Lang) = Yes,
                """" & Text & """ starts a " & Lang'Image & " comment: "
                & Yes'Image);
      end Comment;

      procedure Column (Text : String; Offset : Natural; Expect : Natural) is
      begin
         Check (Syn.Display_Column (Bytes (Text), Offset) = Expect,
                "display column after" & Offset'Image & " bytes of """
                & Text & """ is" & Expect'Image);
      end Column;
   begin
      --  Language detection from a unified-diff header.
      Header ("+++ b/src/x.adb", Syn.Ada_Lang);
      Header ("--- a/src/x.ads", Syn.Ada_Lang);
      Header ("+++ b/tui.gpr", Syn.Ada_Lang);
      Header ("+++ b/src/main.c", Syn.C_Family);
      Header ("+++ b/src/app.tsx", Syn.C_Family);
      Header ("--- a/run_tests.py", Syn.Python_Like);
      Header ("+++ b/build.sh", Syn.Shell_Like);
      Header ("+++ b/alire.toml", Syn.Config);
      Header ("+++ b/README", Syn.Plain);        --  a header, no language
      Header ("--- a/SRC/X.ADB", Syn.Ada_Lang);  --  extensions fold case

      No_Header ("+++ /dev/null", "the /dev/null side of a deletion");
      No_Header ("+added line", "an ordinary added line");
      No_Header ("@@ -1 +1 @@", "a hunk header");
      No_Header ("", "an empty line");

      --  The per-line lookup scans backwards to the nearest header, so a
      --  second file in the same document switches the language.
      declare
         D : Tui.Text.Doc_Ref := Doc (Show_Text);
      begin
         Check (Syn.Language_At (D.Bytes, D.Idx, 1) = Syn.Plain,
                "lines before any header are plain");
         Check (Syn.Language_At (D.Bytes, D.Idx, 11) = Syn.Ada_Lang,
                "a line under the first file takes its language");
         Check (Syn.Language_At (D.Bytes, D.Idx, 17) = Syn.Python_Like,
                "a line under the second file takes the new language");
         Tui.Text.Free (D);
      end;

      --  Keywords. Ada folds case; the others do not.
      Keyword ("procedure", Syn.Ada_Lang);
      Keyword ("PROCEDURE", Syn.Ada_Lang);
      Keyword ("Return", Syn.Ada_Lang);
      Not_Keyword ("procedures", Syn.Ada_Lang);
      Not_Keyword ("def", Syn.Ada_Lang);
      Keyword ("if", Syn.C_Family);
      Not_Keyword ("IF", Syn.C_Family);
      Keyword ("def", Syn.Python_Like);
      Keyword ("None", Syn.Python_Like);
      Keyword ("esac", Syn.Shell_Like);
      Keyword ("true", Syn.Config);
      Not_Keyword ("procedure", Syn.Plain);

      Comment ("-- a remark", Syn.Ada_Lang, True);
      Comment ("- a removal", Syn.Ada_Lang, False);
      Comment ("// a remark", Syn.C_Family, True);
      Comment ("/* a remark", Syn.C_Family, True);
      Comment ("/ divided", Syn.C_Family, False);
      Comment ("# a remark", Syn.Python_Like, True);
      Comment ("# a remark", Syn.Shell_Like, True);
      Comment ("-- a remark", Syn.Plain, False);

      Check (Syn.Is_Identifier_Start (Character'Pos ('_')),
             "underscore starts an identifier");
      Check (not Syn.Is_Identifier_Start (Character'Pos ('1')),
             "a digit does not start an identifier");
      Check (Syn.Is_Identifier (Character'Pos ('1')),
             "a digit continues an identifier");
      Check (not Syn.Is_Identifier (Character'Pos ('-')),
             "a hyphen is not an identifier byte");

      --  Token-to-cell arithmetic: what maps a byte offset onto a column.
      Column ("abc", 0, 0);
      Column ("abc", 3, 3);
      Column (ASCII.HT & "x", 1, 8);           --  a tab to the next stop
      Column ("ab" & ASCII.HT, 3, 8);
      Column ("é", 2, 1);                       --  two bytes, one column
   end Test_Syntax;

   ----------------
   -- Key policy --
   ----------------

   procedure Test_Key_Policy is
      use type Pol.Action_Kind;
      use type Pol.Sel_Move;
      use type Nav.Landmark;

      procedure Both (E : Tui.Input.Key_Event; Expect : Pol.Action_Kind;
                      What : String) is
      begin
         Check (Pol.Classify (Pol.List_Pane, E).Kind = Expect
                and then Pol.Classify (Pol.Diff_Pane, E).Kind = Expect,
                What & " in either pane");
      end Both;

      D : Pol.Decision;
   begin
      --  Viewer-wide keys mean the same thing whichever pane has focus.
      Both (Ch ('q'), Pol.Quit, "q quits");
      Both (Ch ('Q'), Pol.Quit, "Q quits");
      Both (Ctrl_Key ('C'), Pol.Quit, "Ctrl-C quits");
      Both (Key (Tui.Input.Tab), Pol.Switch_Focus, "Tab switches focus");
      Both (Ch ('z'), Pol.Toggle_Maximize, "z maximizes");
      Both (Ch ('s'), Pol.Toggle_Syntax, "s toggles syntax colour");

      D := Pol.Classify (Pol.List_Pane, Ch (','));
      Check (D.Kind = Pol.Resize_Split and then not D.Grow_List,
             ", shrinks the commit list");
      D := Pol.Classify (Pol.List_Pane, Ch ('.'));
      Check (D.Kind = Pol.Resize_Split and then D.Grow_List,
             ". grows the commit list");

      D := Pol.Classify (Pol.Diff_Pane, Ch ('/'));
      Check (D.Kind = Pol.Search and then D.Forward, "/ searches forward");
      D := Pol.Classify (Pol.Diff_Pane, Ch ('?'));
      Check (D.Kind = Pol.Search and then not D.Forward,
             "? searches backward");
      D := Pol.Classify (Pol.Diff_Pane, Ch ('n'));
      Check (D.Kind = Pol.Repeat_Search and then not D.Reversed,
             "n repeats the search");
      D := Pol.Classify (Pol.Diff_Pane, Ch ('N'));
      Check (D.Kind = Pol.Repeat_Search and then D.Reversed,
             "N repeats the search reversed");

      --  The list pane moves a selection; the diff pane scrolls a viewport.
      --  The same keystroke therefore means different things in each.
      Check (Pol.Classify (Pol.List_Pane, Key (Tui.Input.Enter)).Kind
             = Pol.Open_Diff, "Enter opens the selected commit");
      D := Pol.Classify (Pol.Diff_Pane, Key (Tui.Input.Enter));
      Check (D.Kind = Pol.Navigate
             and then D.Command = Tui.Pager.Engine.Line_Down,
             "Enter scrolls the diff pane");

      D := Pol.Classify (Pol.List_Pane, Ch ('j'));
      Check (D.Kind = Pol.Move_Selection and then D.Move = Pol.Sel_Down,
             "j moves the selection down");
      D := Pol.Classify (Pol.Diff_Pane, Ch ('j'));
      Check (D.Kind = Pol.Navigate
             and then D.Command = Tui.Pager.Engine.Line_Down,
             "j scrolls the diff pane down");

      D := Pol.Classify (Pol.List_Pane, Key (Tui.Input.Page_Down));
      Check (D.Kind = Pol.Move_Selection and then D.Move = Pol.Sel_Page_Down,
             "Page Down moves a page of entries");
      D := Pol.Classify (Pol.List_Pane, Ch ('G'));
      Check (D.Kind = Pol.Move_Selection and then D.Move = Pol.Sel_Bottom,
             "G selects the last entry");
      D := Pol.Classify (Pol.List_Pane, Ch ('g'));
      Check (D.Kind = Pol.Move_Selection and then D.Move = Pol.Sel_Top,
             "g selects the first entry");

      --  Long subjects still scroll sideways in the list.
      D := Pol.Classify (Pol.List_Pane, Ch ('h'));
      Check (D.Kind = Pol.Navigate
             and then D.Command = Tui.Pager.Engine.Col_Left,
             "h scrolls the list sideways");
      D := Pol.Classify (Pol.List_Pane, Key (Tui.Input.Right));
      Check (D.Kind = Pol.Navigate
             and then D.Command = Tui.Pager.Engine.Col_Right,
             "Right scrolls the list sideways");

      --  Landmark jumps belong to the diff pane only.
      D := Pol.Classify (Pol.Diff_Pane, Ch (']'));
      Check (D.Kind = Pol.Jump_Diff and then D.Target = Nav.Hunk_Header
             and then D.Jump_Forward, "] jumps to the next hunk");
      D := Pol.Classify (Pol.Diff_Pane, Ch ('['));
      Check (D.Kind = Pol.Jump_Diff and then D.Target = Nav.Hunk_Header
             and then not D.Jump_Forward, "[ jumps to the previous hunk");
      D := Pol.Classify (Pol.Diff_Pane, Ch ('}'));
      Check (D.Kind = Pol.Jump_Diff and then D.Target = Nav.File_Header
             and then D.Jump_Forward, "} jumps to the next file");
      D := Pol.Classify (Pol.Diff_Pane, Ch ('{'));
      Check (D.Kind = Pol.Jump_Diff and then D.Target = Nav.File_Header
             and then not D.Jump_Forward, "{ jumps to the previous file");
      Check (Pol.Classify (Pol.List_Pane, Ch (']')).Kind = Pol.Ignore,
             "] is unbound in the commit list");

      D := Pol.Classify (Pol.Diff_Pane, Ch ('d'));
      Check (D.Kind = Pol.Navigate
             and then D.Command = Tui.Pager.Engine.Half_Down,
             "d scrolls the diff pane half a page");
      Check (Pol.Classify (Pol.List_Pane, Ch ('d')).Kind = Pol.Ignore,
             "d is unbound in the commit list");

      --  Unbound keys are ignored rather than guessed at.
      Both (Ch ('x'), Pol.Ignore, "x is unbound");
      Both (Key (Tui.Input.F1), Pol.Ignore, "F1 is unbound");
      Both (Key (Tui.Input.Unknown), Pol.Ignore, "an unknown key is ignored");
   end Test_Key_Policy;

   ---------------------------------
   -- Responsive layout behaviour --
   ---------------------------------

   procedure Test_Layout is
      use type Pol.Region;

      function L (Cols : Natural; Split : Pol.Split_Percentage := 45;
                  Focused : Pol.Pane := Pol.List_Pane;
                  Maximized : Boolean := False) return Pol.Layout
      is (Pol.Compute_Layout (Tui.Surface.Col_Count (Cols), Focused,
                              Maximized, Split));

      Wide, Narrow : Pol.Layout;
   begin
      Check (Pol.Min_Split_Width = Pol.Min_Pane_Width * 2 + 1,
             "the two-pane breakpoint is two minimum panes and a separator");

      --  Below the breakpoint the layout collapses to a single pane; at it,
      --  both panes appear at exactly their minimum.
      Narrow := L (Pol.Min_Split_Width - 1);
      Check (Narrow.List_Cols = 56 and then Narrow.Diff_Cols = 0,
             "56 columns show the commit list alone");
      Wide := L (Pol.Min_Split_Width);
      Check (Wide.List_Cols = 28 and then Wide.Diff_Cols = 28,
             "57 columns show both panes at their minimum");

      Wide := L (100);
      Check (Wide.List_Cols = 45 and then Wide.Diff_Cols = 54,
             "100 columns split 45/55 around the separator");

      --  The split percentage never starves a pane below its minimum.
      Wide := L (100, Split => 75);
      Check (Wide.List_Cols = 71 and then Wide.Diff_Cols = 28,
             "the widest split still leaves the diff pane its minimum");
      Wide := L (100, Split => 25);
      Check (Wide.List_Cols = 28 and then Wide.Diff_Cols = 71,
             "the narrowest split still leaves the list its minimum");

      --  Maximizing gives the whole width to the focused pane.
      Wide := L (100, Focused => Pol.List_Pane, Maximized => True);
      Check (Wide.List_Cols = 100 and then Wide.Diff_Cols = 0,
             "a maximized list takes the full width");
      Wide := L (100, Focused => Pol.Diff_Pane, Maximized => True);
      Check (Wide.List_Cols = 0 and then Wide.Diff_Cols = 100,
             "a maximized diff takes the full width");

      Narrow := L (0);
      Check (Narrow.List_Cols = 0 and then Narrow.Diff_Cols = 0,
             "a zero-width terminal paints nothing");

      --  Resizing steps by Split_Step and saturates at the bounds.
      Check (Pol.Adjust_Split (45, Grow_List => True) = 50,
             "growing the list steps the split up");
      Check (Pol.Adjust_Split (45, Grow_List => False) = 40,
             "shrinking the list steps the split down");
      Check (Pol.Adjust_Split (Pol.Split_Percentage'Last, True)
             = Pol.Split_Percentage'Last, "growing saturates at the maximum");
      Check (Pol.Adjust_Split (Pol.Split_Percentage'First, False)
             = Pol.Split_Percentage'First,
             "shrinking saturates at the minimum");

      --  A dragged separator becomes a bounded percentage, whatever column
      --  the mouse report claims.
      Check (Pol.Split_At (50, 100) = 50, "a drag to mid-screen is 50%");
      Check (Pol.Split_At (0, 100) = Pol.Split_Percentage'First,
             "a drag to column 0 clamps to the minimum");
      Check (Pol.Split_At (9_999, 100) = Pol.Split_Percentage'Last,
             "a drag past the screen clamps to the maximum");

      --  Hit-testing the painted layout: 28 | separator | 28.
      Check (Pol.Locate (1, 1, 28, 28, 20) = Pol.List_Region,
             "the first column is the list pane");
      Check (Pol.Locate (28, 1, 28, 28, 20) = Pol.List_Region,
             "the list pane's last column is still the list");
      Check (Pol.Locate (29, 1, 28, 28, 20) = Pol.Separator_Region,
             "the column after the list is the separator");
      Check (Pol.Locate (30, 1, 28, 28, 20) = Pol.Diff_Region,
             "the column after the separator is the diff pane");
      Check (Pol.Locate (57, 1, 28, 28, 20) = Pol.Diff_Region,
             "the last painted column is the diff pane");
      Check (Pol.Locate (58, 1, 28, 28, 20) = Pol.Outside,
             "past the painted width is outside");
      Check (Pol.Locate (10, 21, 28, 28, 20) = Pol.Outside,
             "the status row is outside the panes");
      Check (Pol.Locate (0, 1, 28, 28, 20) = Pol.Outside,
             "a report with no column is outside");
      Check (Pol.Locate (10, 0, 28, 28, 20) = Pol.Outside,
             "a report with no row is outside");

      --  Single-pane layouts have no separator to hit.
      Check (Pol.Locate (30, 1, 56, 0, 20) = Pol.List_Region,
             "a collapsed layout is all list");
      Check (Pol.Locate (57, 1, 56, 0, 20) = Pol.Outside,
             "past a collapsed list is outside");
      Check (Pol.Locate (1, 1, 0, 56, 20) = Pol.Diff_Region,
             "a maximized diff owns the first column");
   end Test_Layout;

   ----------------------
   -- Status formatting --
   ----------------------

   procedure Test_Status is
      S : Git_View_Status.Line;

      procedure Note (N : Git_View_Status.Note; Expect : String) is
      begin
         Git_View_Status.Format_Note (S, N);
         Check (Git_View_Status.Image (S) = Expect,
                N'Image & " reads """ & Expect & """");
      end Note;

      Keys_List : constant String :=
        "   (Enter diff  Tab pane  z zoom  / search  q quit)";
      Keys_Diff : constant String :=
        "   (Tab pane  z zoom  / search  q quit)";
   begin
      Note (Git_View_Status.Pattern_Not_Found, "Pattern not found");
      Note (Git_View_Status.No_Pattern, "No pattern");
      Note (Git_View_Status.No_Commit_On_Line, "No commit on this line");
      Note (Git_View_Status.Git_Show_Failed, "git show failed");
      Note (Git_View_Status.Selection_Copied, "Selection copied");
      Note (Git_View_Status.Selection_Copy_Truncated,
            "Selection copied (first 65536 bytes)");

      Git_View_Status.Format_List_Position (S, 3, 40, "1a2b3c4");
      Check (Git_View_Status.Image (S)
             = "[commits] 3/40  1a2b3c4" & Keys_List,
             "the list read-out shows position and id");

      --  A line carrying no commit id drops the id and its separator rather
      --  than leaving a gap.
      Git_View_Status.Format_List_Position (S, 1, 1, "");
      Check (Git_View_Status.Image (S) = "[commits] 1/1" & Keys_List,
             "the list read-out omits an absent id");

      Git_View_Status.Format_List_Position (S, 0, 0, "");
      Check (Git_View_Status.Image (S) = "[commits] 0/0" & Keys_List,
             "an empty history reads 0/0");

      --  The percentage is of the last visible line, so a full screen of a
      --  short document reads 100%.
      Git_View_Status.Format_Diff_Position (S, "1a2b3c4", 1, 20, 200);
      Check (Git_View_Status.Image (S)
             = "[diff] 1a2b3c4  1-20/200  10%" & Keys_Diff,
             "the diff read-out shows id, range and percentage");
      Git_View_Status.Format_Diff_Position (S, "1a2b3c4", 181, 200, 200);
      Check (Git_View_Status.Image (S)
             = "[diff] 1a2b3c4  181-200/200  100%" & Keys_Diff,
             "the end of the document reads 100%");
      Git_View_Status.Format_Diff_Position (S, "", 0, 0, 0);
      Check (Git_View_Status.Image (S) = "[diff] 0-0/0  100%" & Keys_Diff,
             "an empty document reads 100% and omits the id");

      Git_View_Status.Format_Prompt (S, True, Bytes ("needle"));
      Check (Git_View_Status.Image (S) = "/needle",
             "a forward search prompt");
      Git_View_Status.Format_Prompt (S, False, Bytes ("needle"));
      Check (Git_View_Status.Image (S) = "?needle",
             "a backward search prompt");
      Git_View_Status.Format_Prompt (S, True, Bytes (""));
      Check (Git_View_Status.Image (S) = "/", "an empty prompt is the sigil");
   end Test_Status;

begin
   Test_Commit_Ids;
   Test_Decorations;
   Test_Landmarks;
   Test_Diff_Lines;
   Test_Syntax;
   Test_Key_Policy;
   Test_Layout;
   Test_Status;

   if Failures = 0 then
      Ada.Text_IO.Put_Line
        ("behavior tests passed (" & Checks'Image & " checks)");
   else
      Ada.Text_IO.Put_Line
        (Failures'Image & " of" & Checks'Image & " behavior checks failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Behavior_Tests;
