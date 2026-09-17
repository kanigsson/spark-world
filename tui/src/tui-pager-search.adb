package body Tui.Pager.Search with SPARK_Mode => On is

   use type Tui.Text.Byte;

   ------------------
   -- Line_Matches --
   ------------------

   function Line_Matches
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Pattern : Tui.Text.Buffer;
      N       : Line_Number) return Boolean
   is
      S    : constant Tui.Text.Span := Tui.Text.Line_Span (Index, N);
      PLen : constant Natural := Pattern'Length;
   begin
      --  An empty pattern, or one longer than the line, cannot match.
      if PLen = 0 or else PLen > S.Length then
         return False;
      end if;

      --  Slide the pattern across every start offset that still fits. Line_Span
      --  guarantees S.Start + S.Length <= Scanned_Bytes + 1 <= Content'Last + 1,
      --  so every byte read below is provably in range.
      for O in 0 .. S.Length - PLen loop
         declare
            Matched : Boolean := True;
         begin
            for K in 0 .. PLen - 1 loop
               if Content (S.Start + O + K) /= Pattern (Pattern'First + K) then
                  Matched := False;
                  exit;
               end if;
            end loop;
            if Matched then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Line_Matches;

   ----------
   -- Find --
   ----------

   procedure Find
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      Pattern : Tui.Text.Buffer;
      From    : Line_Number;
      Forward : Boolean;
      Found   : out Boolean;
      Line    : out Line_Number)
   is
      Count : constant Line_Total := Tui.Text.Line_Count (Index);
   begin
      Found := False;
      Line  := From;

      if Forward then
         for L in From .. Count loop
            if Line_Matches (Content, Index, Pattern, L) then
               Found := True;
               Line  := L;
               return;
            end if;
         end loop;
      else
         for L in reverse 1 .. From loop
            if Line_Matches (Content, Index, Pattern, L) then
               Found := True;
               Line  := L;
               return;
            end if;
         end loop;
      end if;
   end Find;

end Tui.Pager.Search;
