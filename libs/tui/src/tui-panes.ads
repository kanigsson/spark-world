--  Tui.Panes — the layer between "one engine painting one surface" and an
--  application.
--
--  An application that shows more than one document at once needs a row of
--  panes, a rule for where a mouse report lands in them, a text selection a
--  drag describes, and a highlighted row that keeps step with its viewport.
--  None of that is engine work and all of it is mechanism rather than policy,
--  so it lives here rather than in each host.
--
--  The layer never owns content. It is handed each pane's scroll offsets and
--  line total as a small value, so document ownership — and the proof
--  leverage that comes with it — stays in the application. What a click MEANS
--  stays there too: this layer recognises gestures and describes them, and
--  the host decides their consequences.
--
--  Panes are a fixed, client-declared set indexed by position from the left.
--  Hosts that name their panes with an enumeration convert with
--  `Pane'Pos (P) + 1`. A runtime pane tree would be a different and much
--  larger library, and nothing asks for one.

package Tui.Panes
  with Pure, SPARK_Mode => On
is

   --  Enough for any row of panes a terminal can usefully show; the bound
   --  exists so that every array here is statically sized.
   Max_Panes : constant := 8;

   subtype Pane_Index is Positive range 1 .. Max_Panes;
   subtype Pane_Count is Natural range 0 .. Max_Panes;

   --  A pane's requested share of the terminal width.
   subtype Weight_Percent is Natural range 0 .. 100;

end Tui.Panes;
