--  Git_View_Theme — the viewer's colour scheme and the diff-line classifier,
--  as proved SPARK.
--
--  A surface cell records full colour intent and the terminal driver
--  downgrades to whatever the terminal can show, so the scheme is written
--  against the 16-entry base palette: those indices survive every downgrade
--  and follow the user's terminal theme rather than imposing one.
--
--  Classification is a pure function of a line's leading bytes — the same
--  judgement git's own diff colouring makes — so the colours are a proved
--  function of the displayed content, like everything else painted here.

with Tui.Surface;
with Tui.Text;

package Git_View_Theme
  with SPARK_Mode => On
is

   subtype Color is Tui.Surface.Color;

   --  The conventional ANSI names for the base-palette indices used below.
   Red     : constant := 1;
   Green   : constant := 2;
   Yellow  : constant := 3;
   Blue    : constant := 4;
   Magenta : constant := 5;
   Cyan    : constant := 6;
   Gray    : constant := 8;   --  "bright black"

   function Palette (Index : Tui.Surface.Component) return Color
   is ((Kind => Tui.Surface.Palette, Index => Index));

   --  Diff pane. File_Meta lines carry no colour of their own — they are
   --  drawn bold in the default foreground (git's "meta" look), which adapts
   --  to light and dark terminal themes alike.
   Added_Color        : constant Color := Palette (Green);
   Removed_Color      : constant Color := Palette (Red);
   --  Very pale truecolour washes keep polarity visible across the complete
   --  row without turning it into a solid colour block. The terminal driver
   --  maps them to the closest available colour at lower colour depths.
   Added_Background   : constant Color :=
     (Kind => Tui.Surface.RGB, R => 230, G => 255, B => 236);
   Removed_Background : constant Color :=
     (Kind => Tui.Surface.RGB, R => 255, G => 235, B => 233);
   Hunk_Color         : constant Color := Palette (Cyan);
   Commit_Color       : constant Color := Palette (Yellow);

   --  Diff polarity is confined to the leading +/- gutter. Source-token
   --  foregrounds can therefore carry syntax without erasing that meaning.
   Keyword_Color : constant Color := Palette (Magenta);
   String_Color  : constant Color := Palette (Yellow);
   Comment_Color : constant Color := Palette (Gray);
   Number_Color  : constant Color := Palette (Cyan);

   --  Commit list: the leading abbreviated id and the date column.
   Sha_Color  : constant Color := Palette (Yellow);
   Date_Color : constant Color := Palette (Cyan);
   Ref_Color  : constant Color := Palette (Magenta);

   --  Chrome. The status bar keeps its Inverse attribute and adds a
   --  foreground ACCENT: under inverse video the accent shows as the bar's
   --  visible background, while a monochrome downgrade strips the colour and
   --  still leaves the plain inverse bar.
   Bar_Accent      : constant Color := Palette (Blue);
   Prompt_Accent   : constant Color := Palette (Yellow);
   Note_Accent     : constant Color := Palette (Red);
   Separator_Color : constant Color := Palette (Gray);

   --  What a diff line is, judged by its leading bytes. File-level metadata
   --  outranks the one-character add/remove markers that "+++" and "---"
   --  begin with.
   type Line_Kind is
     (Plain_Line,    --  context, commit message, anything unrecognised
      Added,         --  "+..."
      Removed,       --  "-..."
      Hunk,          --  "@@ -a,b +c,d @@ ..."
      File_Meta,     --  "diff --git", "index", "+++", "---", mode/rename...
      Commit_Head);  --  the "commit <id>" line of git show

   function Classify (Line : Tui.Text.Buffer) return Line_Kind
   with Global => null;

end Git_View_Theme;
