--  M3: a standalone canonical-Huffman round-trip theorem.
--
--  The codebook is built from the M2 code-length construction.  Ready is
--  returned only for a complete canonical code.  Round_Trip then encodes a
--  bounded sequence of symbols into a bit buffer and decodes solely from that
--  buffer.  Its postcondition is the finite-sequence prefix-code bijection:
--  the decoded symbols and their count are exactly the input symbols and count.

with Kraft;

package Huffman_Round_Trip
  with SPARK_Mode => On
is

   use type Kraft.Code_Length_Array;

   Max_Message_Symbols : constant := 32;
   Max_Message_Bits    : constant := Max_Message_Symbols * 15;

   subtype Full_Length_Array is Kraft.Code_Length_Array (0 .. 287);
   subtype Message_Index is Natural range 0 .. Max_Message_Symbols - 1;
   subtype Bit_Index is Natural range 0 .. Max_Message_Bits - 1;
   subtype Message_Count is Natural range 0 .. Max_Message_Symbols;
   subtype Bit_Count is Natural range 0 .. Max_Message_Bits;

   type Message_Buffer is array (Message_Index) of Kraft.Symbol_Value;
   type Bit_Buffer is array (Bit_Index) of Kraft.Bit;

   type Codebook is record
      Lengths : Full_Length_Array;
      Counts  : Kraft.Length_Count_Array;
   end record;

   function First_Code
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length_Pos)
      return Natural
   is (if L = 1 then 0 else 2 * (First_Code (Counts, L - 1) + Counts (L - 1)))
   with
     Subprogram_Variant => (Decreases => L),
     Post               =>
       First_Code'Result <= Kraft.Max_Symbols * (Kraft.Pow2 (L) - 2);

   function Count_Length
     (Lengths : Full_Length_Array; L : Kraft.Code_Length_Pos; Hi : Natural)
      return Kraft.Symbol_Count
   is (if Hi = 0
       then 0
       else
         Count_Length (Lengths, L, Hi - 1)
         + (if Lengths (Hi - 1) = L then 1 else 0))
   with
     Pre                => Hi <= Lengths'Last + 1,
     Subprogram_Variant => (Decreases => Hi),
     Post               => Count_Length'Result <= Hi;

   function Kraft_Value
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length) return Natural
   is (if L = 0 then 0 else 2 * Kraft_Value (Counts, L - 1) + Counts (L))
   with
     Subprogram_Variant => (Decreases => L),
     Post               =>
       Kraft_Value'Result <= Kraft.Max_Symbols * (Kraft.Pow2 (L) - 1);

   function Exact_Counts (Book : Codebook) return Boolean
   is (for all L in Kraft.Code_Length_Pos =>
         Book.Counts (L)
         = Count_Length (Book.Lengths, L, Book.Lengths'Last + 1));

   function Canonical_Valid (Book : Codebook) return Boolean
   is (for all L in Kraft.Code_Length_Pos =>
         First_Code (Book.Counts, L) + Book.Counts (L) <= Kraft.Pow2 (L));

   function Complete (Book : Codebook) return Boolean
   is (Kraft_Value (Book.Counts, 15) = Kraft.Pow2 (15));

   function Ready (Book : Codebook) return Boolean
   is (Exact_Counts (Book)
       and then Canonical_Valid (Book)
       and then Complete (Book));

   function Rank_Of
     (Book : Codebook; Symbol : Kraft.Symbol_Value) return Kraft.Symbol_Count
   with
     Pre  => Book.Lengths (Symbol) /= 0 and then Exact_Counts (Book),
     Post =>
       Rank_Of'Result
       = Count_Length (Book.Lengths, Book.Lengths (Symbol), Symbol)
       and then Rank_Of'Result < Book.Counts (Book.Lengths (Symbol));

   function Code_Of
     (Book : Codebook; Symbol : Kraft.Symbol_Value) return Natural
   is (First_Code (Book.Counts, Book.Lengths (Symbol))
       + Rank_Of (Book, Symbol))
   with
     Pre  =>
       Book.Lengths (Symbol) /= 0
       and then Exact_Counts (Book)
       and then Canonical_Valid (Book),
     Post => Code_Of'Result < Kraft.Pow2 (Book.Lengths (Symbol));

   function Prefix_Value
     (Bits : Bit_Buffer; Start : Bit_Index; Length : Kraft.Code_Length)
      return Natural
   is (if Length = 0
       then 0
       else
         2
         * Prefix_Value (Bits, Start, Length - 1)
         + Bits (Start + Length - 1))
   with
     Pre                => Start + Length <= Max_Message_Bits,
     Subprogram_Variant => (Decreases => Length),
     Post               => Prefix_Value'Result < Kraft.Pow2 (Length);

   function Encoded_Length
     (Book : Codebook; Input : Message_Buffer; Count : Message_Count)
      return Bit_Count
   is (if Count = 0
       then 0
       else
         Encoded_Length (Book, Input, Count - 1)
         + Book.Lengths (Input (Count - 1)))
   with
     Pre                =>
       (for all I in Message_Index range 0 .. Count - 1 =>
          Book.Lengths (Input (I)) /= 0),
     Subprogram_Variant => (Decreases => Count),
     Post               => Encoded_Length'Result <= Count * 15;

   function Is_Encoding
     (Book         : Codebook;
      Bits         : Bit_Buffer;
      Length       : Bit_Count;
      Symbols      : Message_Buffer;
      Symbol_Count : Message_Count) return Boolean
   is (Length = Encoded_Length (Book, Symbols, Symbol_Count)
       and then (for all I in Message_Index range 0 .. Symbol_Count - 1 =>
                   Prefix_Value
                     (Bits,
                      Encoded_Length (Book, Symbols, I),
                      Book.Lengths (Symbols (I)))
                   = Code_Of (Book, Symbols (I))))
   with
     Pre =>
       Ready (Book)
       and then (for all I in Message_Index range 0 .. Symbol_Count - 1 =>
                   Book.Lengths (Symbols (I)) /= 0);

   procedure Build
     (Lengths : in Full_Length_Array;
      Book    : out Codebook;
      Success : out Boolean)
   with
     Global => null,
     Post   => Book.Lengths = Lengths and then (if Success then Ready (Book));

   procedure Round_Trip
     (Book           : in Codebook;
      Input          : in Message_Buffer;
      Input_Count    : in Message_Count;
      Bits           : out Bit_Buffer;
      Length         : out Bit_Count;
      Restored       : out Message_Buffer;
      Restored_Count : out Message_Count)
   with
     Global => null,
     Pre    =>
       Ready (Book)
       and then (for all I in Message_Index range 0 .. Input_Count - 1 =>
                   Book.Lengths (Input (I)) /= 0),
     Post   =>
       Length = Encoded_Length (Book, Input, Input_Count)
       and then Restored_Count = Input_Count
       and then (for all I in Message_Index range 0 .. Input_Count - 1 =>
                   Restored (I) = Input (I));

end Huffman_Round_Trip;
