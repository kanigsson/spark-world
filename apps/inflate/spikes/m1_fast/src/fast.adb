package body Fast with SPARK_Mode => On is

   procedure Lemma_Pow2_Step (N : Fast_Length) is
   begin
      case N is
         when 1 => null;
         when 2 => null;
         when 3 => null;
         when 4 => null;
         when 5 => null;
         when 6 => null;
         when 7 => null;
         when 8 => null;
         when 9 => null;
         when 10 => null;
      end case;
   end Lemma_Pow2_Step;

   procedure Lemma_Double_Div (P : Fast_Index; B : Bit; Q : Positive) is null;

   procedure Lemma_Div_Substitute
     (A, A2 : Natural; D, D2 : Positive) is null;

   procedure Lemma_Div_Monotone (A, B : Natural; D : Positive) is null;

   procedure Lemma_First_Code_Separated
     (Counts : Length_Count_Array; Short, Long : Fast_Length)
   is
   begin
      if Long > Short + 1 then
         Lemma_First_Code_Separated (Counts, Short, Long - 1);
         Lemma_Pow2_Step (Long - Short);
         pragma Assert
           (First_Code (Counts, Long) >= 2 * First_Code (Counts, Long - 1));
         pragma Assert
           (First_Code (Counts, Long) / Pow2 (Long - Short) >=
              First_Code (Counts, Long - 1) / Pow2 (Long - Short - 1));
      else
         pragma Assert (Long = Short + 1);
         pragma Assert
           (First_Code (Counts, Long) =
              2 * (First_Code (Counts, Short) + Counts (Short)));
      end if;
   end Lemma_First_Code_Separated;

   procedure Lemma_Prefix_Shorten
     (Bits : Fast_Index; Short, Long : Fast_Length)
   is
   begin
      if Long > Short + 1 then
         Lemma_Prefix_Shorten (Bits, Short, Long - 1);
         Lemma_Pow2_Step (Long - Short);
         declare
            P : constant Fast_Index := Stream_Prefix (Bits, Long - 1);
            B : constant Bit := (Bits / Pow2 (Long - 1)) mod 2;
            Q : constant Positive := Pow2 (Long - Short - 1);
         begin
            pragma Assert (P = Stream_Prefix (Bits, Long - 1));
            pragma Assert (B = (Bits / Pow2 (Long - 1)) mod 2);
            pragma Assert (Q = Pow2 (Long - Short - 1));
            pragma Assert (Stream_Prefix (Bits, Long) = 2 * P + B);
            Lemma_Double_Div (P, B, Q);
            pragma Assert (Pow2 (Long - Short) = 2 * Q);
            pragma Assert ((2 * P + B) / (2 * Q) = P / Q);
            Lemma_Div_Substitute
              (Stream_Prefix (Bits, Long), 2 * P + B,
               Pow2 (Long - Short), 2 * Q);
            pragma Assert
              (P / Q = Stream_Prefix (Bits, Long - 1) /
                         Pow2 (Long - Short - 1));
            pragma Assert
              (Stream_Prefix (Bits, Long) / Pow2 (Long - Short) =
                 Stream_Prefix (Bits, Long - 1) /
                   Pow2 (Long - Short - 1));
         end;
      else
         pragma Assert (Long = Short + 1);
         pragma Assert
           (Stream_Prefix (Bits, Long) / 2 = Stream_Prefix (Bits, Short));
      end if;
   end Lemma_Prefix_Shorten;

   procedure Lemma_No_Shorter_Code
     (Counts : Length_Count_Array; Bits : Fast_Index; L : Fast_Length)
   is
   begin
      for M in Fast_Length range 1 .. L - 1 loop
         pragma Loop_Invariant
           (for all K in Fast_Length range 1 .. M - 1 =>
              not Code_Matches (Counts, Bits, K));
         Lemma_First_Code_Separated (Counts, M, L);
         Lemma_Prefix_Shorten (Bits, M, L);
         Lemma_Div_Monotone
           (Stream_Prefix (Bits, L), First_Code (Counts, L), Pow2 (L - M));
         pragma Assert
           (Stream_Prefix (Bits, M) >=
              First_Code (Counts, L) / Pow2 (L - M));
         pragma Assert
           (Stream_Prefix (Bits, M) >=
              First_Code (Counts, M) + Counts (M));
         pragma Assert (not Code_Matches (Counts, Bits, M));
      end loop;
   end Lemma_No_Shorter_Code;

   procedure Lemma_Entry_Is_Reference
     (Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Bits    : Fast_Index;
      E       : Packed_Entry;
      From    : Fast_Length := 1)
   is
   begin
      if From < E mod 16 then
         pragma Assert (not Code_Matches (Counts, Bits, From));
         Lemma_Entry_Is_Reference (Counts, Symbols, Bits, E, From + 1);
         pragma Assert
           (Reference_Entry (Counts, Symbols, Bits, From) =
              Reference_Entry (Counts, Symbols, Bits, From + 1));
      else
         pragma Assert (From = E mod 16);
         pragma Assert (Code_Matches (Counts, Bits, From));
         pragma Assert
           (E = Symbols
                  (Count_Before (Counts, From)
                   + (Stream_Prefix (Bits, From) - First_Code (Counts, From)))
                * 16 + From);
      end if;
   end Lemma_Entry_Is_Reference;

   procedure Lemma_Bit_Reverse (V : Natural; L : Fast_Length) is
   begin
      if L > 1 then
         Lemma_Bit_Reverse (V / 2, L - 1);
         declare
            Tail : constant Natural := Bit_Reverse (V / 2, L - 1);
            R    : constant Natural := (V mod 2) * Pow2 (L - 1) + Tail;
         begin
            pragma Assert (Pow2 (L) = 2 * Pow2 (L - 1));
            pragma Assert (Tail < Pow2 (L - 1));
            if V mod 2 = 0 then
               pragma Assert (R = Tail);
            else
               pragma Assert (V mod 2 = 1);
               pragma Assert (R = Pow2 (L - 1) + Tail);
            end if;
            pragma Assert (R < Pow2 (L));
            pragma Assert (R mod Pow2 (L - 1) = Tail);
            pragma Assert ((R / Pow2 (L - 1)) mod 2 = V mod 2);
            Lemma_Stream_Prefix_Mod (Fast_Index (R), L - 1);
            pragma Assert
              (Stream_Prefix (Fast_Index (R), L - 1) =
                 Stream_Prefix (Fast_Index (Tail), L - 1));
            pragma Assert (2 * (V / 2) + V mod 2 = V);
         end;
      end if;
   end Lemma_Bit_Reverse;

   procedure Lemma_Bit_Reverse_Stream
     (Bits : Fast_Index; L : Fast_Length)
   is
   begin
      if L > 1 then
         Lemma_Bit_Reverse_Stream (Bits, L - 1);
         declare
            Prefix : constant Natural := Stream_Prefix (Bits, L - 1);
            B      : constant Bit := (Bits / Pow2 (L - 1)) mod 2;
         begin
            Lemma_Bit_Reverse (Prefix, L - 1);
            pragma Assert (Stream_Prefix (Bits, L) = 2 * Prefix + B);
            pragma Assert ((2 * Prefix + B) / 2 = Prefix);
            pragma Assert ((2 * Prefix + B) mod 2 = B);
            Lemma_Mod_Level (Bits, L);
            Lemma_Mod_Split (Bits, L);
            pragma Assert
              (Bits mod Pow2 (L) =
                 B * Pow2 (L - 1) + Bits mod Pow2 (L - 1));
         end;
      end if;
   end Lemma_Bit_Reverse_Stream;

   procedure Lemma_Mod_Level (Bits : Fast_Index; L : Fast_Length) is
   begin
      case L is
         when 1 => null;
         when 2 => null;
         when 3 => null;
         when 4 => null;
         when 5 => null;
         when 6 => null;
         when 7 => null;
         when 8 => null;
         when 9 => null;
         when 10 => null;
      end case;
   end Lemma_Mod_Level;

   procedure Lemma_Mod_Split (Bits : Fast_Index; L : Fast_Length) is
   begin
      case L is
         when 1 => null;
         when 2 => null;
         when 3 => null;
         when 4 => null;
         when 5 => null;
         when 6 => null;
         when 7 => null;
         when 8 => null;
         when 9 => null;
         when 10 => null;
      end case;
   end Lemma_Mod_Split;

   procedure Lemma_Mod_Add_Step (X : Fast_Index; L : Fast_Length) is
   begin
      case L is
         when 1 => null;
         when 2 => null;
         when 3 => null;
         when 4 => null;
         when 5 => null;
         when 6 => null;
         when 7 => null;
         when 8 => null;
         when 9 => null;
         when 10 => null;
      end case;
   end Lemma_Mod_Add_Step;

   procedure Lemma_Reference_Zero
     (Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Bits    : Fast_Index;
      From    : Fast_Length := 1)
   is
   begin
      if From < Fast_Bits then
         pragma Assert (not Code_Matches (Counts, Bits, From));
         Lemma_Reference_Zero (Counts, Symbols, Bits, From + 1);
      end if;
   end Lemma_Reference_Zero;

   procedure Lemma_Stream_Prefix_Mod (Bits : Fast_Index; L : Fast_Length) is
   begin
      if L > 1 then
         Lemma_Stream_Prefix_Mod (Bits, L - 1);
         Lemma_Stream_Prefix_Mod (Fast_Index (Bits mod Pow2 (L)), L - 1);
         pragma Assert (Pow2 (L) = 2 * Pow2 (L - 1));
         Lemma_Mod_Level (Bits, L);
      end if;
   end Lemma_Stream_Prefix_Mod;

   subtype Fast_Step is Positive range 1 .. Pow2 (Fast_Bits);

   function Entries_Valid (Table : Huffman_Table) return Boolean is
     (for all B in Fast_Index =>
        Fast_Entry_Valid
          (Table.Counts, Table.Symbols, B, Table.Map (B)))
   with
     Ghost,
     Pre => Valid_Counts (Table.Counts);

   function Map_Grows (Before, After : Fast_Map) return Boolean is
     (for all B in Fast_Index => Before (B) = 0 or else After (B) /= 0)
   with Ghost;

   function Covered_Through
     (Counts : Length_Count_Array;
      Map    : Fast_Map;
      Last   : Natural) return Boolean
   is
     (for all B in Fast_Index =>
        Map (B) /= 0
        or else
          (for all L in Fast_Length =>
             L > Last or else not Code_Matches (Counts, B, L)))
   with Ghost;

   function Covered_Before
     (Map        : Fast_Map;
      L          : Fast_Length;
      First_Code : Natural;
      Next_Code  : Natural) return Boolean
   is
     (for all B in Fast_Index =>
        Map (B) /= 0
        or else Stream_Prefix (B, L) < First_Code
        or else Stream_Prefix (B, L) >= Next_Code)
   with Ghost;

   function Length_Covered
     (Counts : Length_Count_Array;
      Map    : Fast_Map;
      L      : Fast_Length) return Boolean
   is
     (for all B in Fast_Index =>
        Map (B) /= 0 or else not Code_Matches (Counts, B, L))
   with Ghost;

   procedure Lemma_Initial_Remainder (R : Fast_Index; Step : Fast_Step)
   with
     Ghost,
     Pre  => R < Step,
     Post => (for all B in Fast_Index =>
                B >= R or else B mod Step /= R);

   procedure Lemma_Initial_Remainder (R : Fast_Index; Step : Fast_Step)
   is null;

   procedure Lemma_Remainder_Window (J : Fast_Index; Step : Fast_Step)
   with
     Ghost,
     Post => (for all B in Fast_Index =>
                B >= J + Step
                or else B <= J
                or else B mod Step /= J mod Step);

   procedure Lemma_Remainder_Window (J : Fast_Index; Step : Fast_Step)
   is null;

   procedure Lemma_Covered_Through_Grows
     (Counts       : Length_Count_Array;
      Before, After : Fast_Map;
      Last         : Natural)
   with
     Ghost,
     Pre  => Covered_Through (Counts, Before, Last)
               and then Map_Grows (Before, After),
     Post => Covered_Through (Counts, After, Last);

   procedure Lemma_Covered_Through_Grows
     (Counts       : Length_Count_Array;
      Before, After : Fast_Map;
      Last         : Natural)
   is null;

   procedure Lemma_Extend_Coverage
     (Before, After : Fast_Map;
      L             : Fast_Length;
      First_Code    : Natural;
      Next_Code     : Natural)
   with
     Ghost,
     Pre  => Next_Code < Pow2 (L)
               and then Covered_Before
                          (Before, L, First_Code, Next_Code)
               and then Map_Grows (Before, After)
               and then
                 (for all B in Fast_Index =>
                    Stream_Prefix (B, L) /= Next_Code
                    or else After (B) /= 0),
     Post => Covered_Before
               (After, L, First_Code, Next_Code + 1);

   procedure Lemma_Extend_Coverage
     (Before, After : Fast_Map;
      L             : Fast_Length;
      First_Code    : Natural;
      Next_Code     : Natural)
   is null;

   procedure Lemma_Length_Covered
     (Counts : Length_Count_Array;
      Map    : Fast_Map;
      L      : Fast_Length)
   with
     Ghost,
     Pre  => Covered_Before
               (Map, L, First_Code (Counts, L),
                First_Code (Counts, L) + Counts (L)),
     Post => Length_Covered (Counts, Map, L);

   procedure Lemma_Length_Covered
     (Counts : Length_Count_Array;
      Map    : Fast_Map;
      L      : Fast_Length)
   is null;

   procedure Lemma_Extend_Through
     (Counts : Length_Count_Array;
      Map    : Fast_Map;
      Done   : Natural;
      L      : Fast_Length)
   with
     Ghost,
     Pre  => Done < Fast_Bits
               and then L = Done + 1
               and then Covered_Through (Counts, Map, Done)
               and then Length_Covered (Counts, Map, L),
     Post => Covered_Through (Counts, Map, L);

   procedure Lemma_Extend_Through
     (Counts : Length_Count_Array;
      Map    : Fast_Map;
      Done   : Natural;
      L      : Fast_Length)
   is null;

   procedure Lemma_Extend_Remainder
     (Before, After : Fast_Map;
      J             : Fast_Index;
      Step          : Fast_Step;
      R             : Fast_Index)
   with
     Ghost,
     Pre  => R = J mod Step
               and then Map_Grows (Before, After)
               and then After (J) /= 0
               and then
                 (for all B in Fast_Index =>
                    B >= J
                    or else B mod Step /= R
                    or else Before (B) /= 0),
     Post => (for all B in Fast_Index =>
                B >= J + Step
                or else B mod Step /= R
                or else After (B) /= 0);

   procedure Lemma_Extend_Remainder
     (Before, After : Fast_Map;
      J             : Fast_Index;
      Step          : Fast_Step;
      R             : Fast_Index)
   is
   begin
      Lemma_Remainder_Window (J, Step);
   end Lemma_Extend_Remainder;

   procedure Lemma_Filled_Code
     (Map  : Fast_Map;
      L    : Fast_Length;
      Code : Natural;
      Step : Positive;
      Next : Natural)
   with
     Ghost,
     Pre  => Code < Pow2 (L)
               and then Step = Pow2 (L)
               and then Next > Fast_Index'Last
               and then
                 (for all B in Fast_Index =>
                    B >= Next
                    or else B mod Step /= Bit_Reverse (Code, L)
                    or else Map (B) /= 0),
     Post => (for all B in Fast_Index =>
                Stream_Prefix (B, L) /= Code or else Map (B) /= 0)
   is
   begin
      for B in Fast_Index loop
         pragma Loop_Invariant
           (for all X in Fast_Index =>
              X >= B
              or else Stream_Prefix (X, L) /= Code
              or else Map (X) /= 0);
         Lemma_Bit_Reverse_Stream (B, L);
         if Stream_Prefix (B, L) = Code then
            pragma Assert
              (B mod Step = Bit_Reverse (Code, L));
            pragma Assert (Map (B) /= 0);
         end if;
      end loop;
   end Lemma_Filled_Code;

   procedure Fill_Code
     (Table        : in out Huffman_Table;
      L            : Fast_Length;
      Code         : Natural;
      Symbol_Index : Symbol_Value;
      Done         : Natural)
   with
     Pre  => Valid_Counts (Table.Counts)
               and then Entries_Valid (Table)
               and then Covered_Through
                          (Table.Counts, Table.Map, Done)
               and then Code >= First_Code (Table.Counts, L)
               and then Code - First_Code (Table.Counts, L) <
                          Table.Counts (L)
               and then Symbol_Index =
                          Count_Before (Table.Counts, L)
                          + (Code - First_Code (Table.Counts, L)),
     Post => Table.Counts = Table.Counts'Old
               and then Table.Symbols = Table.Symbols'Old
               and then Entries_Valid (Table)
               and then Map_Grows (Table.Map'Old, Table.Map)
               and then Covered_Through
                          (Table.Counts, Table.Map, Done)
               and then
                 (for all B in Fast_Index =>
                    Stream_Prefix (B, L) /= Code
                    or else Table.Map (B) /= 0)
   is
      Step   : constant Fast_Step := Pow2 (L);
      E      : constant Packed_Entry := Table.Symbols (Symbol_Index) * 16 + L;
      Before : constant Fast_Map := Table.Map with Ghost;
      Previous : Fast_Map with Ghost;
      J      : Natural;
   begin
      Lemma_Bit_Reverse (Code, L);
      J := Bit_Reverse (Code, L);
      Lemma_Initial_Remainder (Fast_Index (J), Step);
      while J <= Fast_Index'Last loop
         pragma Loop_Invariant
           (J mod Step = Bit_Reverse (Code, L));
         pragma Loop_Invariant (Entries_Valid (Table));
         pragma Loop_Invariant (Map_Grows (Before, Table.Map));
         pragma Loop_Invariant
           (for all B in Fast_Index =>
              B >= J
              or else B mod Step /= Bit_Reverse (Code, L)
              or else Table.Map (B) /= 0);
         pragma Loop_Variant (Increases => J);
         Lemma_Stream_Prefix_Mod (Fast_Index (J), L);
         pragma Assert (Stream_Prefix (Fast_Index (J), L) = Code);
         pragma Assert
           (Fast_Entry_Valid
              (Table.Counts, Table.Symbols, Fast_Index (J), E));
         Previous := Table.Map;
         Table.Map (J) := E;
         Lemma_Extend_Remainder
           (Previous, Table.Map, Fast_Index (J), Step,
            Bit_Reverse (Code, L));
         Lemma_Mod_Add_Step (Fast_Index (J), L);
         J := J + Step;
      end loop;
      Lemma_Filled_Code (Table.Map, L, Code, Step, J);
      Lemma_Covered_Through_Grows
        (Table.Counts, Before, Table.Map, Done);
   end Fill_Code;

   procedure Lemma_Map_Is_Reference (Table : Huffman_Table)
   with
     Ghost,
     Pre  => Valid_Counts (Table.Counts)
               and then Entries_Valid (Table)
               and then Covered_Through
                          (Table.Counts, Table.Map, Fast_Bits),
     Post => (for all B in Fast_Index =>
                Table.Map (B) =
                  Reference_Entry (Table.Counts, Table.Symbols, B))
   is
   begin
      for B in Fast_Index loop
         pragma Loop_Invariant
           (for all X in Fast_Index =>
              X >= B
              or else Table.Map (X) =
                Reference_Entry (Table.Counts, Table.Symbols, X));
         if Table.Map (B) = 0 then
            Lemma_Reference_Zero (Table.Counts, Table.Symbols, B);
         else
            declare
               L : constant Fast_Length := Table.Map (B) mod 16;
            begin
               Lemma_No_Shorter_Code (Table.Counts, B, L);
               Lemma_Entry_Is_Reference
                 (Table.Counts, Table.Symbols, B, Table.Map (B));
            end;
         end if;
      end loop;
   end Lemma_Map_Is_Reference;

   procedure Build_Fast (Table : in out Huffman_Table) is
      Code   : Natural := 0;
      Index  : Natural := 0;
      Count  : Symbol_Count;
      Done   : Natural range 0 .. Fast_Bits := 0;
      Built  : Symbol_Count with Ghost;
      Before : Fast_Map with Ghost;
      Original_Counts  : constant Length_Count_Array := Table.Counts with Ghost;
      Original_Symbols : constant Symbol_Map := Table.Symbols with Ghost;
   begin
      Table.Map := (others => 0);
      for Len in Fast_Length loop
         pragma Loop_Invariant (Done = Len - 1);
         pragma Loop_Invariant (Table.Counts = Original_Counts);
         pragma Loop_Invariant (Table.Symbols = Original_Symbols);
         pragma Loop_Invariant (Valid_Counts (Table.Counts));
         pragma Loop_Invariant (Code = First_Code (Table.Counts, Len));
         pragma Loop_Invariant (Index = Count_Before (Table.Counts, Len));
         pragma Loop_Invariant (Code + Table.Counts (Len) <= Pow2 (Len));
         pragma Loop_Invariant (Index + Table.Counts (Len) <= Max_Symbols);
         pragma Loop_Invariant (Entries_Valid (Table));
         pragma Loop_Invariant
           (Covered_Through (Table.Counts, Table.Map, Done));

         Count := Table.Counts (Len);
         Built := 0;
         for K in 0 .. Count - 1 loop
            pragma Loop_Invariant (Built = K);
            pragma Loop_Invariant (Table.Counts = Original_Counts);
            pragma Loop_Invariant (Table.Symbols = Original_Symbols);
            pragma Loop_Invariant (Valid_Counts (Table.Counts));
            pragma Loop_Invariant (Entries_Valid (Table));
            pragma Loop_Invariant
              (Covered_Through (Table.Counts, Table.Map, Done));
            pragma Loop_Invariant
              (Covered_Before
                 (Table.Map, Len, Code, Code + Built));
            Before := Table.Map;
            pragma Assert
              (Covered_Through (Table.Counts, Before, Done));
            pragma Assert
              (Covered_Before (Before, Len, Code, Code + Built));
            Fill_Code (Table, Len, Code + K, Index + K, Done);
            pragma Assert (Map_Grows (Before, Table.Map));
            Lemma_Extend_Coverage
              (Before, Table.Map, Len, Code, Code + Built);
            Built := Built + 1;
         end loop;
         pragma Assert (Built = Count);
         pragma Assert
           (Covered_Before
              (Table.Map, Len,
               First_Code (Table.Counts, Len),
               First_Code (Table.Counts, Len) + Table.Counts (Len)));
         Lemma_Length_Covered (Table.Counts, Table.Map, Len);
         Lemma_Extend_Through (Table.Counts, Table.Map, Done, Len);
         Index := Index + Count;
         Code  := (Code + Count) * 2;
         Done  := Len;
      end loop;
      pragma Assert (Done = Fast_Bits);
      pragma Assert
        (Covered_Through (Table.Counts, Table.Map, Fast_Bits));
      Lemma_Map_Is_Reference (Table);
   end Build_Fast;

end Fast;
