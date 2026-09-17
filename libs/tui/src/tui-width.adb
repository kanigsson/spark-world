package body Tui.Width with SPARK_Mode => On is

   type Interval is record
      Lo, Hi : Code_Point;
   end record;

   --  A bounded index range (well above any plausible table size) so the binary
   --  search's Mid + 1 provably cannot overflow.
   Max_Intervals : constant := 100_000;
   subtype Table_Range is Positive range 1 .. Max_Intervals;

   type Interval_Table is array (Table_Range range <>) of Interval;

   ---------------------------------------------------------------------------
   --  Interval tables (sorted by Lo, non-overlapping). Curated subset of the
   --  well-known Unicode blocks; see the package spec for provenance/scope.
   ---------------------------------------------------------------------------

   --  Combining / zero-width ranges.
   Zero : constant Interval_Table :=
     ((16#0300#, 16#036F#), (16#0483#, 16#0489#), (16#0591#, 16#05BD#),
      (16#05BF#, 16#05BF#), (16#05C1#, 16#05C2#), (16#05C4#, 16#05C5#),
      (16#05C7#, 16#05C7#), (16#0610#, 16#061A#), (16#064B#, 16#065F#),
      (16#0670#, 16#0670#), (16#06D6#, 16#06DC#), (16#06DF#, 16#06E4#),
      (16#06E7#, 16#06E8#), (16#06EA#, 16#06ED#), (16#0711#, 16#0711#),
      (16#0730#, 16#074A#), (16#07A6#, 16#07B0#), (16#07EB#, 16#07F3#),
      (16#0816#, 16#0819#), (16#081B#, 16#0823#), (16#0825#, 16#0827#),
      (16#0829#, 16#082D#), (16#0859#, 16#085B#), (16#08E3#, 16#0902#),
      (16#093C#, 16#093C#), (16#0941#, 16#0948#), (16#094D#, 16#094D#),
      (16#0951#, 16#0957#), (16#0962#, 16#0963#), (16#0981#, 16#0981#),
      (16#09BC#, 16#09BC#), (16#09C1#, 16#09C4#), (16#09CD#, 16#09CD#),
      (16#09E2#, 16#09E3#), (16#0A01#, 16#0A02#), (16#0A3C#, 16#0A3C#),
      (16#0A41#, 16#0A42#), (16#0A47#, 16#0A48#), (16#0A4B#, 16#0A4D#),
      (16#0A70#, 16#0A71#), (16#0A81#, 16#0A82#), (16#0ABC#, 16#0ABC#),
      (16#0AC1#, 16#0AC5#), (16#0AC7#, 16#0AC8#), (16#0ACD#, 16#0ACD#),
      (16#0B01#, 16#0B01#), (16#0B3C#, 16#0B3C#), (16#0B3F#, 16#0B3F#),
      (16#0B41#, 16#0B44#), (16#0B4D#, 16#0B4D#), (16#0B56#, 16#0B56#),
      (16#0B82#, 16#0B82#), (16#0BC0#, 16#0BC0#), (16#0BCD#, 16#0BCD#),
      (16#0C3E#, 16#0C40#), (16#0C46#, 16#0C48#), (16#0C4A#, 16#0C4D#),
      (16#0C55#, 16#0C56#), (16#0CBC#, 16#0CBC#), (16#0CBF#, 16#0CBF#),
      (16#0CC6#, 16#0CC6#), (16#0CCC#, 16#0CCD#), (16#0D41#, 16#0D44#),
      (16#0D4D#, 16#0D4D#), (16#0DCA#, 16#0DCA#), (16#0DD2#, 16#0DD4#),
      (16#0DD6#, 16#0DD6#), (16#0E31#, 16#0E31#), (16#0E34#, 16#0E3A#),
      (16#0E47#, 16#0E4E#), (16#0EB1#, 16#0EB1#), (16#0EB4#, 16#0EB9#),
      (16#0EBB#, 16#0EBC#), (16#0EC8#, 16#0ECD#), (16#0F18#, 16#0F19#),
      (16#0F35#, 16#0F35#), (16#0F37#, 16#0F37#), (16#0F39#, 16#0F39#),
      (16#0F71#, 16#0F7E#), (16#0F80#, 16#0F84#), (16#0F86#, 16#0F87#),
      (16#0F8D#, 16#0F97#), (16#0F99#, 16#0FBC#), (16#0FC6#, 16#0FC6#),
      (16#102D#, 16#1030#), (16#1032#, 16#1037#), (16#1039#, 16#103A#),
      (16#103D#, 16#103E#), (16#1058#, 16#1059#), (16#135D#, 16#135F#),
      (16#1712#, 16#1714#), (16#1732#, 16#1734#), (16#1752#, 16#1753#),
      (16#1772#, 16#1773#), (16#17B4#, 16#17B5#), (16#17B7#, 16#17BD#),
      (16#17C6#, 16#17C6#), (16#17C9#, 16#17D3#), (16#17DD#, 16#17DD#),
      (16#180B#, 16#180D#), (16#1920#, 16#1922#), (16#1927#, 16#1928#),
      (16#1932#, 16#1932#), (16#1939#, 16#193B#), (16#1A17#, 16#1A18#),
      (16#1B00#, 16#1B03#), (16#1B34#, 16#1B34#), (16#1B36#, 16#1B3A#),
      (16#1B3C#, 16#1B3C#), (16#1B42#, 16#1B42#), (16#1B6B#, 16#1B73#),
      (16#1DC0#, 16#1DFF#), (16#200B#, 16#200F#), (16#202A#, 16#202E#),
      (16#2060#, 16#2064#), (16#20D0#, 16#20F0#), (16#302A#, 16#302D#),
      (16#3099#, 16#309A#), (16#FE00#, 16#FE0F#), (16#FE20#, 16#FE2F#),
      (16#FEFF#, 16#FEFF#));

   --  East-Asian wide / fullwidth ranges.
   Wide : constant Interval_Table :=
     ((16#1100#, 16#115F#), (16#2329#, 16#232A#), (16#2E80#, 16#303E#),
      (16#3041#, 16#33FF#), (16#3400#, 16#4DBF#), (16#4E00#, 16#9FFF#),
      (16#A000#, 16#A4CF#), (16#A960#, 16#A97F#), (16#AC00#, 16#D7A3#),
      (16#F900#, 16#FAFF#), (16#FE10#, 16#FE19#), (16#FE30#, 16#FE6F#),
      (16#FF00#, 16#FF60#), (16#FFE0#, 16#FFE6#), (16#1F300#, 16#1F64F#),
      (16#1F900#, 16#1F9FF#), (16#20000#, 16#2FFFD#), (16#30000#, 16#3FFFD#));

   ---------------------------------------------------------------------------
   --  Binary search over a sorted interval table
   ---------------------------------------------------------------------------

   function In_Table (T : Interval_Table; CP : Code_Point) return Boolean is
      Lo : Integer := T'First;
      Hi : Integer := T'Last;
   begin
      while Lo <= Hi loop
         pragma Loop_Invariant (Lo >= T'First and then Hi <= T'Last);
         pragma Loop_Variant (Decreases => Hi - Lo);
         declare
            Mid : constant Integer := Lo + (Hi - Lo) / 2;
         begin
            if CP < T (Mid).Lo then
               Hi := Mid - 1;
            elsif CP > T (Mid).Hi then
               Lo := Mid + 1;
            else
               return True;
            end if;
         end;
      end loop;
      return False;
   end In_Table;

   -------------
   -- Is_Wide --
   -------------

   function Is_Wide (CP : Code_Point) return Boolean is (In_Table (Wide, CP));

   -------------------
   -- Is_Zero_Width --
   -------------------

   function Is_Zero_Width (CP : Code_Point) return Boolean is
     (In_Table (Zero, CP));

   ----------------
   -- Char_Width --
   ----------------

   function Char_Width (CP : Code_Point) return Column_Count is
   begin
      if Is_Control (CP) or else Is_Zero_Width (CP) then
         return 0;
      elsif Is_Wide (CP) then
         return 2;
      else
         return 1;
      end if;
   end Char_Width;

   ------------------------
   -- Tables_Well_Formed --
   ------------------------

   function Sorted (T : Interval_Table) return Boolean is
   begin
      for I in T'Range loop
         if T (I).Lo > T (I).Hi then
            return False;
         end if;
         if I > T'First and then not (T (I - 1).Hi < T (I).Lo) then
            return False;
         end if;
      end loop;
      return True;
   end Sorted;

   function Tables_Well_Formed return Boolean is
     (Sorted (Zero) and then Sorted (Wide));

end Tui.Width;
