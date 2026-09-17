package body Git_View_Navigation with SPARK_Mode => On is

   use type Tui.Text.Byte;

   -----------------
   -- Is_Landmark --
   -----------------

   function Is_Landmark
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      N       : Tui.Text.Line_Number;
      Kind    : Landmark) return Boolean
   is
      S : constant Tui.Text.Span := Tui.Text.Line_Span (Index, N);
   begin
      case Kind is
         when Hunk_Header =>
            return S.Length >= 2
              and then Content (S.Start) = Character'Pos ('@')
              and then Content (S.Start + 1) = Character'Pos ('@');

         when File_Header =>
            return S.Length >= 11
              and then Content (S.Start)      = Character'Pos ('d')
              and then Content (S.Start + 1)  = Character'Pos ('i')
              and then Content (S.Start + 2)  = Character'Pos ('f')
              and then Content (S.Start + 3)  = Character'Pos ('f')
              and then Content (S.Start + 4)  = Character'Pos (' ')
              and then Content (S.Start + 5)  = Character'Pos ('-')
              and then Content (S.Start + 6)  = Character'Pos ('-')
              and then Content (S.Start + 7)  = Character'Pos ('g')
              and then Content (S.Start + 8)  = Character'Pos ('i')
              and then Content (S.Start + 9)  = Character'Pos ('t')
              and then Content (S.Start + 10) = Character'Pos (' ');
      end case;
   end Is_Landmark;

   ----------
   -- Find --
   ----------

   procedure Find
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      From    : Tui.Text.Line_Number;
      Forward : Boolean;
      Kind    : Landmark;
      Found   : out Boolean;
      Line    : out Tui.Text.Line_Number)
   is
      Count : constant Tui.Text.Line_Total := Tui.Text.Line_Count (Index);
   begin
      Found := False;
      Line  := From;

      if Forward then
         if From < Count then
            for L in From + 1 .. Count loop
               if Is_Landmark (Content, Index, L, Kind) then
                  Found := True;
                  Line  := L;
                  return;
               end if;
            end loop;
         end if;
      elsif From > 1 then
         for L in reverse 1 .. From - 1 loop
            if Is_Landmark (Content, Index, L, Kind) then
               Found := True;
               Line  := L;
               return;
            end if;
         end loop;
      end if;
   end Find;

end Git_View_Navigation;
