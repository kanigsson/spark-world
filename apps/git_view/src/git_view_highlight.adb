with Git_View_Theme;

package body Git_View_Highlight
  with SPARK_Mode => On
is
   package Syn renames Git_View_Syntax;
   package Thm renames Git_View_Theme;
   use Tui.Surface;
   use type Tui.Text.Byte;
   use type Syn.Language;

   procedure Tint_Cells
     (S    : in out Surface;
      Row  : Row_Index;
      From : Positive;
      To   : Natural;
      Fg   : Color)
   with Global => null, Pre => Row <= S.Rows
   is
   begin
      if From > Natural (S.Cols) or else To < From then
         return;
      end if;
      for Col in
        Col_Index
          range Col_Index (From)
                .. Col_Index (Natural'Min (To, Natural (S.Cols)))
      loop
         declare
            Value : Cell := Get (S, Row, Col);
         begin
            Value.Foreground := Fg;
            Set (S, Row, Col, Value);
         end;
      end loop;
   end Tint_Cells;

   procedure Tint_Byte_Span
     (S    : in out Surface;
      Row  : Row_Index;
      Line : Tui.Text.Buffer;
      From : Tui.Text.Byte_Index;
      To   : Tui.Text.Byte_Index;
      Left : Tui.Pager.Dimension;
      Fg   : Color)
   with
     Global => null,
     Pre    =>
       Row <= S.Rows
       and then From in Line'Range
       and then To in From .. Line'Last
   is
      First_Col : constant Natural :=
        Syn.Display_Column (Line, From - Line'First);
      After_Col : constant Natural :=
        Syn.Display_Column (Line, To - Line'First + 1);
      Right     : constant Natural := Left + Natural (S.Cols);
   begin
      if After_Col <= Left
        or else First_Col >= Right
        or else After_Col <= First_Col
      then
         return;
      end if;
      Tint_Cells
        (S,
         Row,
         Natural'Max (First_Col, Left) - Left + 1,
         Natural'Min (After_Col, Right) - Left,
         Fg);
   end Tint_Byte_Span;

   function Quote_Start (B : Tui.Text.Byte; Lang : Syn.Language) return Boolean
   is (case Lang is
         when Syn.Markdown => B = Character'Pos ('`'),
         when Syn.Ada_Lang => B = Character'Pos ('"'),
         when Syn.Plain    => False,
         when others       =>
           B = Character'Pos ('"') or else B = Character'Pos ('''));

   procedure Source_Line
     (S      : in out Surface;
      Row    : Row_Index;
      Line   : Tui.Text.Buffer;
      Lang   : Syn.Language;
      Offset : Tui.Text.Byte_Count;
      Left   : Tui.Pager.Dimension) is
   begin
      if Lang = Syn.Plain or else Offset >= Line'Length then
         return;
      end if;
      declare
         subtype Scan_Index is Natural range 1 .. Tui.Text.Max_Bytes + 1;
         Last : constant Tui.Text.Byte_Index := Line'Last;
         Pos  : Scan_Index := Line'First + Offset;
      begin
         --  Markdown headings are structural tokens rather than comments.
         --  Colour the complete heading, which also leaves inline code easy
         --  to distinguish on ordinary prose lines below it.
         if Lang = Syn.Markdown then
            while Pos <= Last and then Line (Pos) = Character'Pos (' ') loop
               pragma
                 Loop_Invariant (Pos in Line'First + Offset .. Line'Last + 1);
               pragma Loop_Variant (Decreases => Last + 1 - Pos);
               Pos := Pos + 1;
            end loop;
            if Pos <= Last and then Line (Pos) = Character'Pos ('#') then
               Tint_Byte_Span
                 (S, Row, Line, Pos, Last, Left, Thm.Keyword_Color);
               return;
            end if;
            Pos := Line'First + Offset;
         end if;

         while Pos <= Last loop
            pragma
              Loop_Invariant (Pos in Line'First + Offset .. Line'Last + 1);
            pragma Loop_Invariant (Row <= S.Rows);
            pragma Loop_Variant (Decreases => Last + 1 - Pos);
            if Syn.Starts_Comment (Line, Pos, Lang) then
               Tint_Byte_Span
                 (S, Row, Line, Pos, Last, Left, Thm.Comment_Color);
               return;
            elsif Quote_Start (Line (Pos), Lang) then
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
                    (S, Row, Line, Pos, Finish, Left, Thm.String_Color);
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
                       (S, Row, Line, Pos, Finish, Left, Thm.Keyword_Color);
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
                    (S, Row, Line, Pos, Finish, Left, Thm.Number_Color);
                  Pos := Finish + 1;
               end;
            else
               Pos := Pos + 1;
            end if;
         end loop;
      end;
   end Source_Line;
end Git_View_Highlight;
