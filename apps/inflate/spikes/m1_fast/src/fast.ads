package Fast
  with SPARK_Mode => On
is

   Max_Symbols : constant := 288;
   Fast_Bits   : constant := 10;

   subtype Code_Length is Natural range 0 .. 15;
   subtype Code_Length_Pos is Code_Length range 1 .. 15;
   subtype Symbol_Count is Natural range 0 .. Max_Symbols;
   subtype Symbol_Value is Natural range 0 .. Max_Symbols - 1;
   subtype Fast_Length is Code_Length_Pos range 1 .. Fast_Bits;
   subtype Fast_Index is Natural range 0 .. 2**Fast_Bits - 1;
   subtype Packed_Entry is Natural range 0 .. Max_Symbols * 16 - 1;
   subtype Bit is Natural range 0 .. 1;

   type Length_Count_Array is array (Code_Length_Pos) of Symbol_Count;
   type Symbol_Map is array (Symbol_Value) of Symbol_Value;
   type Fast_Map is array (Fast_Index) of Packed_Entry;

   type Huffman_Table is record
      Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Map     : Fast_Map;
   end record;

   Pow2 : constant array (Natural range 0 .. 16) of Natural :=
     (1,
      2,
      4,
      8,
      16,
      32,
      64,
      128,
      256,
      512,
      1024,
      2048,
      4096,
      8192,
      16384,
      32768,
      65536);

   function Count_Before
     (Counts : Length_Count_Array; L : Code_Length_Pos) return Natural
   is (if L = 1 then 0 else Count_Before (Counts, L - 1) + Counts (L - 1))
   with
     Subprogram_Variant => (Decreases => L),
     Post               => Count_Before'Result <= (L - 1) * Max_Symbols;

   function First_Code
     (Counts : Length_Count_Array; L : Code_Length_Pos) return Natural
   is (if L = 1 then 0 else 2 * (First_Code (Counts, L - 1) + Counts (L - 1)))
   with
     Subprogram_Variant => (Decreases => L),
     Post               => First_Code'Result <= Max_Symbols * (Pow2 (L) - 2);

   --  The first L stream bits interpreted in the order used by Decode:
   --  the first bit read is the most significant bit of the code value.
   function Stream_Prefix (Bits : Fast_Index; L : Fast_Length) return Natural
   is (if L = 1
       then Bits mod 2
       else 2 * Stream_Prefix (Bits, L - 1) + (Bits / Pow2 (L - 1)) mod 2)
   with
     Subprogram_Variant => (Decreases => L),
     Post               => Stream_Prefix'Result < Pow2 (L);

   function Valid_Counts (Counts : Length_Count_Array) return Boolean
   is ((for all L in Fast_Length =>
          First_Code (Counts, L) + Counts (L) <= Pow2 (L))
       and then (for all L in Fast_Length =>
                   Count_Before (Counts, L) + Counts (L) <= Max_Symbols));

   function Code_Matches
     (Counts : Length_Count_Array; Bits : Fast_Index; L : Fast_Length)
      return Boolean
   is (Stream_Prefix (Bits, L) >= First_Code (Counts, L)
       and then Stream_Prefix (Bits, L) - First_Code (Counts, L) < Counts (L));

   procedure Lemma_Pow2_Step (N : Fast_Length)
   with Ghost, Pre => N > 1, Post => Pow2 (N) = 2 * Pow2 (N - 1);

   procedure Lemma_Double_Div (P : Fast_Index; B : Bit; Q : Positive)
   with
     Ghost,
     Pre  => Q <= Pow2 (Fast_Bits),
     Post => (2 * P + B) / (2 * Q) = P / Q;

   procedure Lemma_Div_Substitute (A, A2 : Natural; D, D2 : Positive)
   with Ghost, Pre => A = A2 and then D = D2, Post => A / D = A2 / D2;

   procedure Lemma_Div_Monotone (A, B : Natural; D : Positive)
   with Ghost, Pre => A >= B, Post => A / D >= B / D;

   procedure Lemma_First_Code_Separated
     (Counts : Length_Count_Array; Short, Long : Fast_Length)
   with
     Ghost,
     Always_Terminates,
     Pre                => Short < Long,
     Post               =>
       First_Code (Counts, Long) / Pow2 (Long - Short)
       >= First_Code (Counts, Short) + Counts (Short),
     Subprogram_Variant => (Decreases => Long - Short);

   procedure Lemma_Prefix_Shorten
     (Bits : Fast_Index; Short, Long : Fast_Length)
   with
     Ghost,
     Always_Terminates,
     Pre                => Short < Long,
     Post               =>
       Stream_Prefix (Bits, Short)
       = Stream_Prefix (Bits, Long) / Pow2 (Long - Short),
     Subprogram_Variant => (Decreases => Long - Short);

   function Reference_Entry
     (Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Bits    : Fast_Index;
      L       : Fast_Length := 1) return Packed_Entry
   is (if Stream_Prefix (Bits, L) >= First_Code (Counts, L)
         and then Stream_Prefix (Bits, L) - First_Code (Counts, L) < Counts (L)
       then
         Symbols
           (Count_Before (Counts, L)
            + (Stream_Prefix (Bits, L) - First_Code (Counts, L)))
         * 16
         + L
       elsif L = Fast_Bits
       then 0
       else Reference_Entry (Counts, Symbols, Bits, L + 1))
   with
     Pre                => Valid_Counts (Counts),
     Subprogram_Variant => (Decreases => Fast_Bits - L);

   function Fast_Entry_Valid
     (Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Bits    : Fast_Index;
      E       : Packed_Entry) return Boolean
   is (E = 0
       or else (E mod 16 in Fast_Length
                and then Code_Matches (Counts, Bits, E mod 16)
                and then E
                         = Symbols
                             (Count_Before (Counts, E mod 16)
                              + (Stream_Prefix (Bits, E mod 16)
                                 - First_Code (Counts, E mod 16)))
                           * 16
                           + E mod 16))
   with Pre => Valid_Counts (Counts);

   procedure Lemma_No_Shorter_Code
     (Counts : Length_Count_Array; Bits : Fast_Index; L : Fast_Length)
   with
     Ghost,
     Always_Terminates,
     Pre  => Valid_Counts (Counts) and then Code_Matches (Counts, Bits, L),
     Post =>
       (for all M in Fast_Length range 1 .. L - 1 =>
          not Code_Matches (Counts, Bits, M));

   procedure Lemma_Entry_Is_Reference
     (Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Bits    : Fast_Index;
      E       : Packed_Entry;
      From    : Fast_Length := 1)
   with
     Ghost,
     Always_Terminates,
     Pre                =>
       Valid_Counts (Counts)
       and then E /= 0
       and then Fast_Entry_Valid (Counts, Symbols, Bits, E)
       and then From <= E mod 16
       and then (for all M in Fast_Length range From .. E mod 16 - 1 =>
                   not Code_Matches (Counts, Bits, M)),
     Post               => Reference_Entry (Counts, Symbols, Bits, From) = E,
     Subprogram_Variant => (Decreases => E mod 16 - From);

   function Bit_Reverse (V : Natural; L : Fast_Length) return Natural
   is (if L = 1
       then V mod 2
       elsif Bit_Reverse (V / 2, L - 1) >= Pow2 (L - 1)
       then 0
       else (V mod 2) * Pow2 (L - 1) + Bit_Reverse (V / 2, L - 1))
   with Pre => V < Pow2 (L), Subprogram_Variant => (Decreases => L);

   procedure Lemma_Bit_Reverse (V : Natural; L : Fast_Length)
   with
     Ghost,
     Always_Terminates,
     Pre                => V < Pow2 (L),
     Post               =>
       Bit_Reverse (V, L) < Pow2 (L)
       and then Stream_Prefix (Fast_Index (Bit_Reverse (V, L)), L) = V,
     Subprogram_Variant => (Decreases => L);

   procedure Lemma_Bit_Reverse_Stream (Bits : Fast_Index; L : Fast_Length)
   with
     Ghost,
     Always_Terminates,
     Post               =>
       Bit_Reverse (Stream_Prefix (Bits, L), L) = Bits mod Pow2 (L),
     Subprogram_Variant => (Decreases => L);

   procedure Lemma_Stream_Prefix_Mod (Bits : Fast_Index; L : Fast_Length)
   with
     Ghost,
     Always_Terminates,
     Post               =>
       Stream_Prefix (Bits, L) = Stream_Prefix (Bits mod Pow2 (L), L),
     Subprogram_Variant => (Decreases => L);

   procedure Lemma_Mod_Level (Bits : Fast_Index; L : Fast_Length)
   with
     Ghost,
     Pre  => L > 1,
     Post =>
       (Bits mod Pow2 (L)) mod Pow2 (L - 1) = Bits mod Pow2 (L - 1)
       and then ((Bits mod Pow2 (L)) / Pow2 (L - 1)) mod 2
                = (Bits / Pow2 (L - 1)) mod 2;

   procedure Lemma_Mod_Split (Bits : Fast_Index; L : Fast_Length)
   with
     Ghost,
     Post =>
       Bits mod Pow2 (L)
       = ((Bits / Pow2 (L - 1)) mod 2) * Pow2 (L - 1) + Bits mod Pow2 (L - 1);

   procedure Lemma_Mod_Add_Step (X : Fast_Index; L : Fast_Length)
   with Ghost, Post => (X + Pow2 (L)) mod Pow2 (L) = X mod Pow2 (L);

   procedure Lemma_Reference_Zero
     (Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Bits    : Fast_Index;
      From    : Fast_Length := 1)
   with
     Ghost,
     Always_Terminates,
     Pre                =>
       Valid_Counts (Counts)
       and then (for all L in Fast_Length range From .. Fast_Bits =>
                   not Code_Matches (Counts, Bits, L)),
     Post               => Reference_Entry (Counts, Symbols, Bits, From) = 0,
     Subprogram_Variant => (Decreases => Fast_Bits - From);

   procedure Build_Fast (Table : in out Huffman_Table)
   with
     Pre  => Valid_Counts (Table.Counts),
     Post =>
       Table.Counts = Table.Counts'Old
       and then Table.Symbols = Table.Symbols'Old
       and then (for all J in Fast_Index =>
                   Fast_Entry_Valid
                     (Table.Counts, Table.Symbols, J, Table.Map (J)))
       and then (for all J in Fast_Index =>
                   Table.Map (J)
                   = Reference_Entry (Table.Counts, Table.Symbols, J));

end Fast;
