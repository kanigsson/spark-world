package body Tui.Surface.Diff
  with SPARK_Mode => On
is

   -------------
   -- Compute --
   -------------

   procedure Compute
     (Previous, Current : Surface;
      Changes           : out Change_Array;
      Count             : out Natural)
   is
      N : Natural := 0;  --  number of changes recorded so far
   begin
      --  Fully initialise the out parameter so flow analysis is happy; the
      --  postcondition only constrains the 1 .. Count prefix.
      Changes := (others => (Row => 1, Column => 1, Value => Blank_Cell));

      for R in Row_Index range 1 .. Current.Rows loop

         for C in Col_Index range 1 .. Current.Cols loop

            if Get (Previous, R, C) /= Get (Current, R, C) then
               N := N + 1;
               Changes (N) :=
                 (Row => R, Column => C, Value => Get (Current, R, C));
            end if;

            --  Invariant at the END of the body so it captures the increment
            --  just made. After handling cell (R, C) we have recorded at most
            --  one change per cell visited so far in this row, on top of the
            --  full rows below R.
            pragma
              Loop_Invariant
                (N
                   <= (Natural (R) - 1)
                      * Natural (Current.Cols)
                      + Natural (C));
            pragma
              Loop_Invariant
                (for all I in 1 .. N =>
                   In_Bounds (Current, Changes (I).Row, Changes (I).Column)
                   and then Changes (I).Value
                            = Get
                                (Current, Changes (I).Row, Changes (I).Column)
                   and then Get (Previous, Changes (I).Row, Changes (I).Column)
                            /= Get
                                 (Current,
                                  Changes (I).Row,
                                  Changes (I).Column));
         end loop;

         --  After a full row, N is bounded by all rows visited so far.
         pragma Loop_Invariant (N <= Natural (R) * Natural (Current.Cols));
         pragma
           Loop_Invariant
             (for all I in 1 .. N =>
                In_Bounds (Current, Changes (I).Row, Changes (I).Column)
                and then Changes (I).Value
                         = Get (Current, Changes (I).Row, Changes (I).Column)
                and then Get (Previous, Changes (I).Row, Changes (I).Column)
                         /= Get
                              (Current, Changes (I).Row, Changes (I).Column));
      end loop;

      Count := N;
   end Compute;

end Tui.Surface.Diff;
