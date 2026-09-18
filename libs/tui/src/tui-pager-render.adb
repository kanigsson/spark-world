with Tui.Width;
with Tui.UTF8;

package body Tui.Pager.Render
  with SPARK_Mode => On
is

   use Tui.Surface;

   --  UTF-8 decoding lives in the shared Tui.UTF8 codec; this crate only pulls
   --  each line's bytes out of the buffer and hands them over. Ill-formed input
   --  comes back as U+FFFD, which Char_Width treats like any other glyph.

   ---------------------------------------------------------------------------
   --  Draw one content line into row R, honouring scroll/tab/width.
   ---------------------------------------------------------------------------

   procedure Draw_Line
     (Target  : in out Tui.Surface.Surface;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Left    : Dimension;
      Tab     : Tui.Pager.Tab_Width;
      R       : Row_Index;
      N       : Line_Number)
   with
     Global => null,
     Pre    =>
       R <= Target.Rows
       and then Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Index)
       and then N <= Tui.Text.Line_Count (Index),
     --  Every cell this writes is plain, and it writes only in row R.
     Post   =>
       (for all RR in Row_Index range 1 .. Target.Rows =>
          (for all CC in Col_Index range 1 .. Target.Cols =>
             (if RR /= R
              then Get (Target, RR, CC) = Get (Target'Old, RR, CC)
              else
                not Get (Target, RR, CC).Attributes.Inverse
                or else Get (Target'Old, RR, CC).Attributes.Inverse)))
   is
      S     : constant Tui.Text.Span := Tui.Text.Line_Span (Index, N);
      Hi    : constant Natural :=
        S.Start + S.Length - 1;   --  last content byte
      Width : constant Natural := Natural (Target.Cols);
      Pos   : Natural := S.Start;
      Col   : Natural := 0;   --  source display column, 0-based
   begin
      while Pos <= Hi and then Col < Left + Width loop
         pragma Loop_Invariant (Pos >= S.Start);
         pragma
           Loop_Invariant
             (for all RR in Row_Index range 1 .. Target.Rows =>
                (for all CC in Col_Index range 1 .. Target.Cols =>
                   (if RR /= R
                    then Get (Target, RR, CC) = Get (Target'Loop_Entry, RR, CC)
                    else
                      not Get (Target, RR, CC).Attributes.Inverse
                      or else Get (Target'Loop_Entry, RR, CC)
                                .Attributes
                                .Inverse)));
         pragma Loop_Variant (Decreases => Integer (Hi) - Integer (Pos));
         declare
            B0  : constant Tui.Byte := Tui.Byte (Content (Pos));
            B1  : constant Tui.Byte :=
              (if Pos + 1 <= Hi then Tui.Byte (Content (Pos + 1)) else 0);
            B2  : constant Tui.Byte :=
              (if Pos + 2 <= Hi then Tui.Byte (Content (Pos + 2)) else 0);
            B3  : constant Tui.Byte :=
              (if Pos + 3 <= Hi then Tui.Byte (Content (Pos + 3)) else 0);
            CP  : Tui.Code_Point;
            Len : Positive;
            W   : Natural;
            Vis : Integer;
         begin
            Tui.UTF8.Decode
              (B0, B1, B2, B3, Avail => Hi - Pos + 1, CP => CP, Len => Len);
            if CP = 16#09# then
               --  tab -> advance to stop
               W := Tab - (Col mod Tab);
            elsif Tui.Width.Char_Width (CP) = 0 then
               W := 0;                              --  combining/control: skip
            else
               W := Tui.Width.Char_Width (CP);   --  1 or 2
               Vis := Col - Left;
               if Vis >= 0 and then Vis < Width then
                  Set
                    (Target,
                     R,
                     Col_Index (Vis + 1),
                     (Glyph      => Wide_Wide_Character'Val (CP),
                      Foreground => Default_Color,
                      Background => Default_Color,
                      Attributes => Plain));
                  if W = 2 and then Vis + 1 < Width then
                     Set
                       (Target,
                        R,
                        Col_Index (Vis + 2),
                        (Glyph      => ' ',
                         Foreground => Default_Color,
                         Background => Default_Color,
                         Attributes => Plain));
                  end if;
               end if;
            end if;
            Col := Col + W;
            Pos := Pos + Len;
         end;
      end loop;
   end Draw_Line;

   ---------------------------------------------------------------------------
   --  Blank row R, then draw its content line (if any).
   ---------------------------------------------------------------------------

   procedure Draw_Row
     (Target  : in out Tui.Surface.Surface;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      V       : Tui.Pager.View.Viewport;
      Tab     : Tui.Pager.Tab_Width;
      R       : Row_Index)
   with
     Global => null,
     Pre    =>
       R <= Target.Rows
       and then Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Index),
     --  The row is blanked before it is drawn, so whatever it carried --
     --  a selection the host had put there -- is gone, and no other row
     --  is touched.
     Post   =>
       (for all CC in Col_Index range 1 .. Target.Cols =>
          not Get (Target, R, CC).Attributes.Inverse)
       and then (for all RR in Row_Index range 1 .. Target.Rows =>
                   (for all CC in Col_Index range 1 .. Target.Cols =>
                      (if RR /= R
                       then Get (Target, RR, CC) = Get (Target'Old, RR, CC))))
   is
      Total : constant Line_Total := Tui.Text.Line_Count (Index);
      N     : constant Natural := V.Top + (Natural (R) - 1);
   begin
      for C in 1 .. Target.Cols loop
         Set (Target, R, C, Blank_Cell);
         pragma
           Loop_Invariant
             (for all CC in Col_Index range 1 .. C =>
                Get (Target, R, CC) = Blank_Cell);
         pragma
           Loop_Invariant
             (for all RR in Row_Index range 1 .. Target.Rows =>
                (for all CC in Col_Index range 1 .. Target.Cols =>
                   (if RR /= R
                    then
                      Get (Target, RR, CC)
                      = Get (Target'Loop_Entry, RR, CC))));
      end loop;
      if N <= Total then
         Draw_Line (Target, Content, Index, V.Left, Tab, R, N);
      end if;
   end Draw_Row;

   ----------
   -- Draw --
   ----------

   procedure Draw
     (Target  : in out Tui.Surface.Surface;
      Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      V       : Tui.Pager.View.Viewport;
      Tab     : Tui.Pager.Tab_Width := Tui.Pager.Default_Tab_Width) is
   begin
      for R in 1 .. Target.Rows loop
         Draw_Row (Target, Content, Index, V, Tab, R);
         pragma
           Loop_Invariant
             (for all RR in Row_Index range 1 .. R =>
                (for all CC in Col_Index range 1 .. Target.Cols =>
                   not Get (Target, RR, CC).Attributes.Inverse));
      end loop;
   end Draw;

end Tui.Pager.Render;
