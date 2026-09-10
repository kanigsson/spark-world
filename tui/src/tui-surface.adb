package body Tui.Surface with SPARK_Mode => On is

   ----------
   -- Set  --
   ----------

   procedure Set (S : in out Surface; R : Row_Index; C : Col_Index; To : Cell)
   is
   begin
      S.Cells (R, C) := To;
   end Set;

   -----------
   -- Blank --
   -----------

   function Blank (Rows : Row_Count; Cols : Col_Count) return Surface is
   begin
      return S : Surface (Rows, Cols) do
         S.Cells := (others => (others => Blank_Cell));
      end return;
   end Blank;

   -----------
   -- Clear --
   -----------

   procedure Clear (S : in out Surface; To : Cell := Blank_Cell) is
   begin
      S.Cells := (others => (others => To));
   end Clear;

   ----------
   -- Copy --
   ----------

   procedure Copy
     (Src    : Surface;
      Dst    : in out Surface;
      At_Row : Row_Index;
      At_Col : Col_Index)
   is
   begin
      Over_Rows :
      for R in Row_Index range 1 .. Src.Rows loop

         Over_Cols :
         for C in Col_Index range 1 .. Src.Cols loop
            Dst.Cells (At_Row + R - 1, At_Col + C - 1) := Src.Cells (R, C);

            --  The prefix of the current destination row holds the source.
            pragma Loop_Invariant
              (for all CC in Col_Index range 1 .. C =>
                 Dst.Cells (At_Row + R - 1, At_Col + CC - 1)
                   = Src.Cells (R, CC));
            --  Only that prefix has been touched since this row began.
            pragma Loop_Invariant
              (for all RR in Row_Index range 1 .. Dst.Rows =>
                 (for all CC in Col_Index range 1 .. Dst.Cols =>
                    (if RR /= At_Row + R - 1
                       or else CC < At_Col
                       or else Natural (CC) >= Natural (At_Col) + Natural (C)
                     then Dst.Cells (RR, CC)
                            = Dst.Cells'Loop_Entry (RR, CC))));
         end loop Over_Cols;

         --  All rows processed so far hold the source.
         pragma Loop_Invariant
           (for all RR in Row_Index range 1 .. R =>
              (for all CC in Col_Index range 1 .. Src.Cols =>
                 Dst.Cells (At_Row + RR - 1, At_Col + CC - 1)
                   = Src.Cells (RR, CC)));
         --  Everything outside the full target rectangle is untouched.
         pragma Loop_Invariant
           (for all RR in Row_Index range 1 .. Dst.Rows =>
              (for all CC in Col_Index range 1 .. Dst.Cols =>
                 (if RR < At_Row
                    or else
                      Natural (RR) >= Natural (At_Row) + Natural (Src.Rows)
                    or else CC < At_Col
                    or else
                      Natural (CC) >= Natural (At_Col) + Natural (Src.Cols)
                  then Dst.Cells (RR, CC)
                         = Dst.Cells'Loop_Entry (RR, CC))));
      end loop Over_Rows;
   end Copy;

end Tui.Surface;
