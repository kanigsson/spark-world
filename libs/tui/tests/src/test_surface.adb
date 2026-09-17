--  Behavioural tests. These complement (do not replace) gnatprove: proof
--  shows the contracts hold for all inputs; these pin down a few concrete
--  expectations and double as runnable documentation. -gnata makes the
--  contracts themselves execute here too.

with Ada.Text_IO;        use Ada.Text_IO;
with Ada.Command_Line;
with Tui.Surface;        use Tui.Surface;
with Tui.Surface.Diff;

procedure Test_Surface is

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

begin
   --  Blank surface is all blank cells.
   declare
      S : constant Surface := Blank (4, 8);
   begin
      Check (S.Rows = 4 and S.Cols = 8, "Blank records its geometry");
      Check (Get (S, 1, 1) = Blank_Cell, "Blank cell at corner");
      Check (Get (S, 4, 8) = Blank_Cell, "Blank cell at far corner");
   end;

   --  Set writes one cell and leaves neighbours alone.
   declare
      S : Surface := Blank (3, 3);
      X : constant Cell := (Glyph => 'X', others => <>);
   begin
      Set (S, 2, 2, X);
      Check (Get (S, 2, 2) = X, "Set then Get round-trips");
      Check (Get (S, 1, 1) = Blank_Cell, "neighbour above-left untouched");
      Check (Get (S, 3, 3) = Blank_Cell, "neighbour below-right untouched");
   end;

   --  Diff: identical frames produce no changes.
   declare
      P   : constant Surface := Blank (5, 5);
      C   : constant Surface := Blank (5, 5);
      Buf : Diff.Change_Array (1 .. Diff.Cell_Count (C));
      N   : Natural;
   begin
      Diff.Compute (P, C, Buf, N);
      Check (N = 0, "identical frames -> 0 changes");
   end;

   --  Diff: a single changed cell produces exactly one change.
   declare
      P   : constant Surface := Blank (5, 5);
      C   : Surface := Blank (5, 5);
      Buf : Diff.Change_Array (1 .. Diff.Cell_Count (C));
      N   : Natural;
   begin
      Set (C, 3, 4, (Glyph => 'Z', others => <>));
      Diff.Compute (P, C, Buf, N);
      Check (N = 1, "one changed cell -> 1 change");
      Check (N >= 1 and then Buf (1).Row = 3 and then Buf (1).Column = 4,
             "change carries the right coordinates");
      Check (N >= 1 and then Buf (1).Value.Glyph = 'Z',
             "change carries the new value");
   end;

   --  Diff: total repaint reports every cell.
   declare
      P   : constant Surface := Blank (2, 3);
      C   : Surface := Blank (2, 3);
      Buf : Diff.Change_Array (1 .. Diff.Cell_Count (C));
      N   : Natural;
   begin
      Clear (C, (Glyph => '#', others => <>));
      Diff.Compute (P, C, Buf, N);
      Check (N = 6, "full repaint -> Rows*Cols changes");
   end;

   --  Copy: the rectangle holds the source, the rest is untouched.
   declare
      Pane   : Surface := Blank (2, 2);
      Screen : Surface := Blank (4, 6);
   begin
      Clear (Pane, (Glyph => 'P', others => <>));
      Set (Screen, 1, 1, (Glyph => 'A', others => <>));
      Copy (Pane, Screen, At_Row => 2, At_Col => 3);
      Check (Get (Screen, 2, 3).Glyph = 'P'
             and then Get (Screen, 3, 4).Glyph = 'P',
             "Copy fills the target rectangle");
      Check (Get (Screen, 1, 1).Glyph = 'A',
             "cell outside the rectangle untouched");
      Check (Get (Screen, 2, 2) = Blank_Cell
             and then Get (Screen, 4, 4) = Blank_Cell,
             "rectangle borders untouched");
   end;

   --  Copy: an empty source is a no-op.
   declare
      Pane   : constant Surface := Blank (0, 0);
      Screen : Surface := Blank (2, 2);
   begin
      Copy (Pane, Screen, At_Row => 1, At_Col => 1);
      Check (Get (Screen, 1, 1) = Blank_Cell, "empty source copies nothing");
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " TEST(S) FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Surface;
