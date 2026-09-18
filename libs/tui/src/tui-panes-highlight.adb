package body Tui.Panes.Highlight
  with SPARK_Mode => On
is

   use Tui.Surface;

   ---------
   -- Row --
   ---------

   procedure Row (S : in out Tui.Surface.Surface; R : Tui.Surface.Row_Index) is
   begin
      for C in Col_Index range 1 .. S.Cols loop
         Set (S, R, C, Inverted (Get (S, R, C)));
         pragma
           Loop_Invariant
             (for all RR in Row_Index range 1 .. S.Rows =>
                (for all CC in Col_Index range 1 .. S.Cols =>
                   (if RR = R and then CC <= C
                    then
                      Get (S, RR, CC) = Inverted (Get (S'Loop_Entry, RR, CC))
                    else Get (S, RR, CC) = Get (S'Loop_Entry, RR, CC))));
      end loop;
   end Row;

   -------------
   -- Overlay --
   -------------

   procedure Overlay
     (S           : in out Tui.Surface.Surface;
      Top         : Tui.Text.Line_Number;
      Left        : Tui.Pager.Dimension;
      First, Last : Selection.Position) is
   begin
      for R in Row_Index range 1 .. S.Rows loop
         declare
            Line : constant Natural := Top + (Natural (R) - 1);
         begin
            if Line >= First.Line and then Line <= Last.Line then
               for C in Col_Index range 1 .. S.Cols loop
                  declare
                     Column : constant Natural := Left + Natural (C) - 1;

                     --  A one-line selection is bounded at both ends; a
                     --  multi-line one runs to the end of its first row and
                     --  from the start of its last.
                     Inside : constant Boolean :=
                       (if First.Line = Last.Line
                        then
                          Line = First.Line
                          and then Column >= First.Col
                          and then Column <= Last.Col
                        elsif Line = First.Line
                        then Column >= First.Col
                        elsif Line = Last.Line
                        then Column <= Last.Col
                        else True);
                  begin
                     if Inside then
                        declare
                           Value : Cell := Get (S, R, C);
                        begin
                           Value.Attributes.Inverse :=
                             not Value.Attributes.Inverse;
                           Set (S, R, C, Value);
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Overlay;

   ---------------
   -- Separator --
   ---------------

   procedure Separator
     (S           : in out Tui.Surface.Surface;
      At_Col      : Tui.Surface.Col_Index;
      Rows        : Tui.Surface.Row_Count;
      Points_Left : Boolean;
      Foreground  : Tui.Surface.Color)
   is
      Glyph : constant Wide_Wide_Character :=
        (if Points_Left
         then Wide_Wide_Character'Val (16#258C#)
         --  left half block
         else Wide_Wide_Character'Val (16#2590#));  --  right half block
   begin
      for R in Row_Index range 1 .. Rows loop
         Set
           (S,
            R,
            At_Col,
            (Glyph      => Glyph,
             Foreground => Foreground,
             Attributes => (Bold => True, others => False),
             others     => <>));
      end loop;
   end Separator;

end Tui.Panes.Highlight;
