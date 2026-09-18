package body Tui.Panes.Layout
  with SPARK_Mode => On
is

   type Shown_Set is array (Pane_Index range <>) of Boolean;

   --  The largest total a row of minima and separators can reach.
   Max_Floor : constant := Max_Panes * (Natural (Tui.Surface.Max_Extent) + 1);

   subtype Floor_Total is Natural range 0 .. Max_Floor;

   --  What a set of panes cannot do without: each kept pane's minimum plus a
   --  separator column for every kept pane after the first.
   function Floor_Width
     (Specs : Specs_Array; Keep : Shown_Set; From : Pane_Index; Sep : Natural)
      return Floor_Total
   with
     Global => null,
     Pre    =>
       Keep'First = Specs'First
       and then Keep'Last = Specs'Last
       and then From in Specs'Range
       and then Sep <= 1
   is
      Sum : Floor_Total := 0;
   begin
      for I in From .. Specs'Last loop
         if Keep (I) then
            Sum := Sum + Specs (I).Min_Cols + Sep;
         end if;
         pragma
           Loop_Invariant
             (Sum
                <= (I - Specs'First + 1)
                   * (Natural (Tui.Surface.Max_Extent) + 1));
      end loop;
      --  The leftmost kept pane has no separator to its left.
      return (if Sum >= Sep then Sum - Sep else 0);
   end Floor_Width;

   -------------
   -- Compute --
   -------------

   procedure Compute
     (Specs      : Specs_Array;
      Total_Cols : Tui.Surface.Col_Count;
      Focused    : Pane_Index;
      Maximized  : Boolean;
      Separators : Boolean;
      Rule       : Drop_Rule;
      Result     : out Placement_Array)
   is
      Total : constant Natural := Natural (Total_Cols);
      Sep   : constant Natural := (if Separators then 1 else 0);

      Keep  : Shown_Set (Specs'Range) := (others => True);
      Count : Pane_Count := Specs'Length;
   begin
      Result := (others => (Start_Col => 0, Cols => 0));

      if Total = 0 then
         return;
      end if;

      if Maximized then
         Result (Focused) := (Start_Col => 1, Cols => Total);
         return;
      end if;

      --  Give up places, most disposable first, until the rest fit. The last
      --  pane standing is shown however narrow the terminal is: a squeezed
      --  pane beats an empty screen.
      while Count > 1
        and then Floor_Width (Specs, Keep, Specs'First, Sep) > Total
      loop
         declare
            Victim : Pane_Index := Specs'First;
            Found  : Boolean := False;
         begin
            for I in Specs'Range loop
               if Keep (I)
                 and then (Rule = Drop_By_Priority or else I /= Focused)
                 and then (not Found
                           or else Specs (I).Priority
                                   >= Specs (Victim).Priority)
               then
                  Victim := I;
                  Found := True;
               end if;
               pragma Loop_Invariant (Victim in Specs'Range);
            end loop;
            exit when not Found;
            Keep (Victim) := False;
            Count := Count - 1;
         end;
         pragma Loop_Variant (Decreases => Count);
      end loop;

      ------------------------------------------------------------------
      --  Assign places left to right.
      --
      --  Remaining is the width the panes not yet placed, and the
      --  separators still to come, have between them; a pane's separator
      --  is taken BEFORE it rather than after, so the rightmost pane ends
      --  on the terminal's last column and no column is wasted. That, plus
      --  the rightmost pane absorbing whatever is left, is what makes the
      --  row cover the width exactly.
      ------------------------------------------------------------------
      declare
         Col       : Positive := 1;
         Remaining : Natural := Total;
         Placed    : Boolean := False;
         First_Set : Pane_Index := Specs'First;
         Last_Set  : Pane_Index := Specs'First;
      begin
         for I in Specs'Range loop
            declare
               --  The separator column this pane would need to its left.
               Lead    : constant Separator_Cols :=
                 (if Placed then Sep else 0);
               --  What every pane to the right of this one, and the
               --  separator before each of them, must keep.
               Right   : constant Floor_Total :=
                 (if Keep (I) and then I < Specs'Last
                  then Floor_Width (Specs, Keep, I + 1, Sep)
                  else 0);
               Reserve : constant Natural :=
                 (if Right > 0 then Right + Sep else 0);
               Avail   : constant Natural :=
                 (if Remaining > Lead then Remaining - Lead else 0);
               Width   : Natural := 0;
            begin
               if Keep (I) and then Avail > 0 then
                  if Reserve = 0 then
                     --  Nothing to the right: absorb the rounding.
                     Width := Avail;
                  else
                     declare
                        Ceiling : constant Natural :=
                          (if Avail > Reserve then Avail - Reserve else 1);
                        Want    : constant Natural :=
                          Total * Specs (I).Weight / 100;
                     begin
                        Width := Want;
                        if Width < Specs (I).Min_Cols then
                           Width := Specs (I).Min_Cols;
                        end if;
                        if Width > Ceiling then
                           Width := Ceiling;
                        end if;
                        if Width > Avail then
                           Width := Avail;
                        end if;
                     end;
                  end if;
               end if;

               if Width > 0 then
                  Remaining := Remaining - Lead - Width;
                  Col := Col + Lead;
                  Result (I) := (Start_Col => Col, Cols => Width);
                  Col := Col + Width;
                  if not Placed then
                     First_Set := I;
                  end if;
                  Placed := True;
                  Last_Set := I;
               end if;
            end;

            pragma
              Loop_Invariant
                (First_Set in Specs'Range and then Last_Set in Specs'Range);
            pragma Loop_Invariant (Col + Remaining = Total + 1);
            pragma Loop_Invariant (Col <= Total + 1);
            pragma
              Loop_Invariant
                (Placed
                   = (for some J in Specs'First .. I => Result (J).Cols > 0));
            pragma
              Loop_Invariant
                (for all J in Specs'Range =>
                   (if J > I then Result (J).Cols = 0));
            pragma
              Loop_Invariant
                (for all J in Specs'Range =>
                   (Result (J).Cols > 0) = (Result (J).Start_Col > 0));
            pragma
              Loop_Invariant
                (if Placed
                   then
                     Last_Set <= I
                     and then Result (Last_Set).Cols > 0
                     and then Result (Last_Set).Start_Col
                              + Result (Last_Set).Cols
                              = Col
                     and then (for all J in Specs'Range =>
                                 (if J > Last_Set then Result (J).Cols = 0)));
            pragma Loop_Invariant (if not Placed then Col = 1);
            pragma
              Loop_Invariant
                (if Placed
                   then
                     First_Set <= I
                     and then First_Set <= Last_Set
                     and then Result (First_Set).Cols > 0
                     and then Result (First_Set).Start_Col = 1
                     and then (for all J in Specs'Range =>
                                 (if J < First_Set then Result (J).Cols = 0)));
            pragma
              Loop_Invariant
                (for all J in Specs'Range =>
                   (if Result (J).Cols > 0
                    then Result (J).Start_Col + Result (J).Cols <= Col));
            pragma
              Loop_Invariant
                (for all J in Specs'Range =>
                   (for all K in Specs'Range =>
                      (if J < K
                         and then Result (J).Cols > 0
                         and then Result (K).Cols > 0
                       then
                         Result (J).Start_Col + Result (J).Cols + Sep
                         <= Result (K).Start_Col)));
            pragma
              Loop_Invariant
                (for all J in Specs'Range =>
                   (for all K in Specs'Range =>
                      (if J < K
                         and then Result (J).Cols > 0
                         and then Result (K).Cols > 0
                         and then (for all L in Specs'Range =>
                                     (if L > J and then L < K
                                      then Result (L).Cols = 0))
                       then
                         Result (K).Start_Col
                         = Result (J).Start_Col + Result (J).Cols + Sep)));
         end loop;

         if not Placed then
            --  Nothing was placed at all, which the drop rule is written to
            --  prevent. Give the row to the focused pane rather than paint
            --  an empty screen.
            Result := (others => (Start_Col => 0, Cols => 0));
            Result (Focused) := (Start_Col => 1, Cols => Total);
         else
            --  Rounding no pane took leaves a tail; the rightmost pane takes
            --  it, so the row ends on the terminal's last column.
            if Remaining > 0 then
               Result (Last_Set).Cols := Result (Last_Set).Cols + Remaining;
               Remaining := 0;
            end if;

            --  A shown pane with nothing shown to its left IS the leftmost
            --  one, which the loop placed at column 1.
            pragma
              Assert
                (for all I in Specs'Range =>
                   (if Result (I).Cols > 0
                      and then (for all J in Specs'Range =>
                                  (if J < I then Result (J).Cols = 0))
                    then I = First_Set));
         end if;
      end;
   end Compute;   ------------------
   -- Rescue_Focus --
   ------------------

   function Rescue_Focus
     (P : Placement_Array; Focused : Pane_Index) return Pane_Index is
   begin
      if Shown (P (Focused)) then
         return Focused;
      end if;
      for I in P'Range loop
         if Shown (P (I)) then
            return I;
         end if;
      end loop;
      return Focused;
   end Rescue_Focus;

   ------------
   -- Locate --
   ------------

   function Locate
     (P            : Placement_Array;
      First_Row    : Positive;
      Content_Rows : Natural;
      Col, Row     : Natural) return Hit
   is
      Nothing : constant Hit :=
        (Kind => Nowhere, Pane => P'First, Local_Row => 0, Local_Col => 0);
   begin
      if Col = 0
        or else Row < First_Row
        or else Row - First_Row + 1 > Content_Rows
        or else Content_Rows > Screen_Cols'Last
      then
         return Nothing;
      end if;

      for I in P'Range loop
         if Shown (P (I)) then
            if Col >= P (I).Start_Col
              and then Col - P (I).Start_Col < P (I).Cols
            then
               return
                 (Kind      => Pane_Hit,
                  Pane      => I,
                  Local_Row => Row - First_Row + 1,
                  Local_Col => Col - P (I).Start_Col + 1);

            elsif Col = P (I).Start_Col + P (I).Cols then
               --  The column just past a pane is its separator, but only
               --  when there is a pane on the other side of it.
               for J in P'Range loop
                  if J > I and then Shown (P (J)) then
                     return
                       (Kind      => Separator_Hit,
                        Pane      => I,
                        Local_Row => 0,
                        Local_Col => 0);
                  end if;
               end loop;
               return Nothing;
            end if;
         end if;
      end loop;

      return Nothing;
   end Locate;

   ------------
   -- Adjust --
   ------------

   function Adjust
     (Current : Split_Percentage; Grow : Boolean) return Split_Percentage is
   begin
      if Grow then
         return
           Split_Percentage'Min (Split_Percentage'Last, Current + Split_Step);
      else
         return
           Split_Percentage'Max (Split_Percentage'First, Current - Split_Step);
      end if;
   end Adjust;

   --------------
   -- Split_At --
   --------------

   function Split_At
     (Column : Natural; Total : Tui.Surface.Col_Count) return Split_Percentage
   is
      Raw : constant Natural :=
        Natural'Min
          (100,
           (Natural'Min (Column, Natural (Total)) * 100) / Natural (Total));
   begin
      return
        Split_Percentage'Max
          (Split_Percentage'First,
           Split_Percentage'Min (Split_Percentage'Last, Raw));
   end Split_At;

end Tui.Panes.Layout;
