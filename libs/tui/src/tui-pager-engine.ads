--  Tui.Pager.Engine — the embeddable pager instance.
--
--  This is the unit a host actually drives, and the thing the git viewer will
--  embed (twice — a list pane and a diff pane). It bundles the viewport
--  (Tui.Pager.View), the layout/draw (Tui.Pager.Render) and search
--  (Tui.Pager.Search) behind a small command-oriented API:
--
--    Resize  — tell it the content area's size (and the line total) on startup
--              and on every terminal resize; it re-clamps the viewport.
--    Handle  — apply one Command (scroll/page/top-bottom/search) and report,
--              via an Effect, what happened — so the host repaints only when
--              something moved and can surface a "pattern not found".
--    Render  — fill a target Surface with the current view.
--
--  Content is NOT owned here. The engine holds only view + search state; the
--  host keeps the materialised content (a Tui.Text index over a byte buffer)
--  and passes it to Handle/Render. That is the roadmap's deliberate shape: the
--  I/O boundary (the "source") lives in the host, the engine stays a pure,
--  provable function of (state, content). All SPARK, proved free of run-time
--  errors; the viewport-within-bounds invariant rides along through View.
--
--  The STATUS LINE is a host concern, not the engine's: a host that wants one
--  reserves a row by passing a content height one less than the screen, renders
--  the engine into the whole surface, then overwrites that last row itself. The
--  engine therefore needs no notion of a status line, which keeps it reusable
--  for panes that have none.

with Tui.Surface;
with Tui.Text;
with Tui.Pager.View;

package Tui.Pager.Engine
  with SPARK_Mode => On
is

   --  Longest search pattern retained. Generous for interactive use; a pattern
   --  is a literal byte string (see Tui.Pager.Search).
   Max_Pattern : constant := 256;

   type Instance is private;
   --  Default-initialised to an empty top-of-document view; just declare one.

   ---------------------------------------------------------------------------
   --  Commands and their reported effect
   ---------------------------------------------------------------------------

   type Command is
     (Line_Up,
      Line_Down,     --  one line
      Half_Up,
      Half_Down,     --  half a page
      Page_Up,
      Page_Down,     --  a full page
      To_Top,
      To_Bottom,     --  ends of the document
      Col_Left,
      Col_Right,     --  horizontal scroll
      Find_Next,
      Find_Prev);    --  next/previous match of the current pattern

   type Effect is
     (Unchanged,     --  the command was a no-op (already at the edge, etc.)
      Moved,         --  the viewport changed
      Search_Hit,    --  a search command found a match and moved to it
      Search_Miss);  --  a search command found nothing (viewport unchanged)

   ---------------------------------------------------------------------------
   --  Read-only state (for a host's status line, and for the contracts of
   --  the operations below, which are stated in terms of it)
   ---------------------------------------------------------------------------

   function Top_Line (E : Instance) return Line_Number
   with Global => null;
   function Left_Col (E : Instance) return Dimension
   with Global => null;
   --  The viewport's visible height, as Resize last set it. A pane layered on
   --  the engine needs it to decide how far to scroll for a line off screen.
   function Height (E : Instance) return Dimension
   with Global => null;
   function Last_Visible (E : Instance; Total : Line_Total) return Line_Total
   with Global => null;

   ---------------------------------------------------------------------------
   --  Configuration / content geometry
   ---------------------------------------------------------------------------

   --  Set the visible content area (rows x cols) and the document's line total,
   --  re-clamping the viewport to stay within the content. Call on startup and
   --  on every resize. Rows is the CONTENT height: a host reserving a status
   --  row passes screen-rows minus one.
   procedure Resize
     (E     : in out Instance;
      Rows  : Dimension;
      Cols  : Dimension;
      Total : Line_Total)
   with Global => null;

   procedure Set_Tab (E : in out Instance; Tab : Tab_Width)
   with Global => null;

   --  Put a document line at the top where possible, clamping at the final
   --  full page. Unlike search this preserves the installed pattern and the
   --  horizontal offset, so hosts can implement structural navigation.
   procedure Go_To_Line
     (E : in out Instance; Line : Line_Number; Total : Line_Total)
   with
     Global => null,
     Post   =>
       Height (E) = Height (E'Old)
       and then Top_Line (E)
                = Line_Number'Min
                    (Line, Tui.Pager.View.Max_Top (Total, Height (E)));

   --  Install the literal search pattern (bytes). An empty Pattern clears it.
   --  At most Max_Pattern bytes are kept.
   procedure Set_Pattern (E : in out Instance; Pattern : Tui.Text.Buffer)
   with Global => null, Pre => Pattern'Length = 0 or else Pattern'First >= 1;

   function Has_Pattern (E : Instance) return Boolean
   with Global => null;

   ---------------------------------------------------------------------------
   --  Driving
   ---------------------------------------------------------------------------

   procedure Handle
     (E       : in out Instance;
      Cmd     : Command;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Result  : out Effect)
   with
     Global => null,
     Pre    =>
       Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Index);

   procedure Render
     (E       : Instance;
      Target  : in out Tui.Surface.Surface;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index)
   with
     Global => null,
     Pre    =>
       Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Index),
     --  A rendered pane carries text only. Whatever says "current row"
     --  goes on top of it afterwards, and is the host's single call.
     Post   => Tui.Surface.No_Inverse (Target);

private

   subtype Pattern_Length is Natural range 0 .. Max_Pattern;
   type Pattern_Bytes is array (1 .. Max_Pattern) of Tui.Text.Byte;

   --  How far Col_Left/Col_Right shift the horizontal offset per command.
   H_Scroll_Step : constant := 8;

   type Instance is record
      View    : Tui.Pager.View.Viewport;
      Tab     : Tab_Width := Default_Tab_Width;
      Pat     : Pattern_Bytes := (others => 0);
      Pat_Len : Pattern_Length := 0;
   end record;

   function Has_Pattern (E : Instance) return Boolean
   is (E.Pat_Len > 0);
   function Top_Line (E : Instance) return Line_Number
   is (E.View.Top);
   function Height (E : Instance) return Dimension
   is (E.View.Height);
   function Left_Col (E : Instance) return Dimension
   is (E.View.Left);
   function Last_Visible (E : Instance; Total : Line_Total) return Line_Total
   is (Tui.Pager.View.Last_Visible (E.View, Total));

end Tui.Pager.Engine;
