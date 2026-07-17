--  Inflate.Codebooks -- canonical Huffman codebook boundary for encoders.
--
--  Fixed and dynamic blocks differ in how their code lengths are obtained.
--  Payload serialization consumes only this interface: Length_Of, Code_Of,
--  and Ready.  Fixed books are constant RFC 1951 assignments; canonical
--  books carry caller-supplied lengths and their exact histogram.

package Inflate.Codebooks with Pure, SPARK_Mode => On is

   Max_Symbols : constant := 288;

   subtype Symbol_Index is Natural range 0 .. Max_Symbols - 1;
   subtype Symbol_Count is Natural range 0 .. Max_Symbols;
   subtype Code_Length is Natural range 0 .. 15;
   subtype Code_Length_Pos is Code_Length range 1 .. 15;

   type Code_Length_Array is array (Symbol_Index) of Code_Length;
   type Length_Count_Array is array (Code_Length_Pos) of Symbol_Count;

   Pow2 : constant array (Natural range 0 .. 15) of Natural :=
     (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1_024, 2_048,
      4_096, 8_192, 16_384, 32_768);

   type Codebook_Kind is
     (Fixed_Literal_Length, Fixed_Distance, Canonical);

   type Codebook (Kind : Codebook_Kind := Canonical) is record
      case Kind is
         when Canonical =>
            Lengths : Code_Length_Array;
            Counts  : Length_Count_Array;
         when Fixed_Literal_Length | Fixed_Distance =>
            null;
      end case;
   end record;

   Fixed_Literal_Length_Book : constant Codebook :=
     (Kind => Fixed_Literal_Length);
   Fixed_Distance_Book : constant Codebook :=
     (Kind => Fixed_Distance);

   function Count_Length
     (Lengths : Code_Length_Array;
      Length  : Code_Length_Pos;
      Count   : Symbol_Count) return Symbol_Count
   is
     (if Count = 0 then 0
      else Count_Length (Lengths, Length, Count - 1)
        + (if Lengths (Symbol_Index (Count - 1)) = Length then 1 else 0))
   with
     Post => Count_Length'Result <= Count,
     Subprogram_Variant => (Decreases => Count);

   function First_Code
     (Counts : Length_Count_Array;
      Length : Code_Length_Pos) return Natural
   is
     (if Length = 1 then 0
      else 2 * (First_Code (Counts, Length - 1) + Counts (Length - 1)))
   with
     Post => First_Code'Result <= Max_Symbols * (Pow2 (Length) - 2),
     Subprogram_Variant => (Decreases => Length);

   function Kraft_Value
     (Counts : Length_Count_Array;
      Length : Code_Length) return Natural
   is
     (if Length = 0 then 0
      else 2 * Kraft_Value (Counts, Length - 1) + Counts (Length))
   with
     Post => Kraft_Value'Result <= Max_Symbols * (Pow2 (Length) - 1),
     Subprogram_Variant => (Decreases => Length);

   function Exact_Counts (Book : Codebook) return Boolean is
     (Book.Kind = Canonical
      and then
        (for all Length in Code_Length_Pos =>
           Book.Counts (Length) =
             Count_Length (Book.Lengths, Length, Max_Symbols)));

   function Canonical_Valid (Book : Codebook) return Boolean is
     (Book.Kind = Canonical
      and then
        (for all Length in Code_Length_Pos =>
           First_Code (Book.Counts, Length) + Book.Counts (Length) <=
             Pow2 (Length)));

   function Complete (Book : Codebook) return Boolean is
     (Book.Kind = Canonical
      and then Kraft_Value (Book.Counts, 15) = Pow2 (15));

   --  Ready is the common payload-facing validity predicate.  The two fixed
   --  assignments are valid by construction.  A canonical book is ready when
   --  its histogram is exact, its canonical ranges fit, and its Kraft sum is
   --  complete.
   function Ready (Book : Codebook) return Boolean is
     (case Book.Kind is
         when Fixed_Literal_Length | Fixed_Distance => True,
         when Canonical =>
           Exact_Counts (Book) and then Canonical_Valid (Book)
             and then Complete (Book));

   function Length_Of
     (Book : Codebook; Symbol : Symbol_Index) return Code_Length
   is
     (case Book.Kind is
         when Fixed_Literal_Length =>
           (if Symbol <= 143 then 8
            elsif Symbol <= 255 then 9
            elsif Symbol <= 279 then 7
            else 8),
         when Fixed_Distance => (if Symbol <= 31 then 5 else 0),
         when Canonical => Book.Lengths (Symbol));

   function Rank_Of
     (Book : Codebook; Symbol : Symbol_Index) return Symbol_Count
   with
     Pre  => Book.Kind = Canonical
               and then Exact_Counts (Book)
               and then Book.Lengths (Symbol) /= 0,
     Post => Rank_Of'Result =
               Count_Length
                 (Book.Lengths, Book.Lengths (Symbol), Symbol)
               and then Rank_Of'Result <
                 Book.Counts (Book.Lengths (Symbol));

   function Code_Of
     (Book : Codebook; Symbol : Symbol_Index) return Natural
   is
     (case Book.Kind is
         when Fixed_Literal_Length =>
           (if Symbol <= 143 then 48 + Symbol
            elsif Symbol <= 255 then 256 + Symbol
            elsif Symbol <= 279 then Symbol - 256
            else Symbol - 88),
         when Fixed_Distance => Symbol,
         when Canonical =>
           First_Code (Book.Counts, Book.Lengths (Symbol))
             + Rank_Of (Book, Symbol))
   with
     Pre  => Ready (Book) and then Length_Of (Book, Symbol) /= 0,
     Post => Code_Of'Result < Pow2 (Length_Of (Book, Symbol));

   function Lengths_At_Most
     (Book : Codebook; Maximum : Code_Length) return Boolean is
     (for all Symbol in Symbol_Index =>
        Length_Of (Book, Symbol) <= Maximum);

   --  Construct the canonical representation of Lengths.  Success is exactly
   --  the Ready predicate, so callers may retain a defensive failure path for
   --  malformed external lengths.  Inflate.Dynamic supplies proved complete
   --  lengths and uses the successful result for payload serialization.
   procedure Build
     (Lengths : in     Code_Length_Array;
      Book    :    out Codebook;
      Success :    out Boolean)
   with
     Global => null,
     Pre    => Book.Kind = Canonical,
     Post   => Book.Kind = Canonical
                 and then Book.Lengths = Lengths
                 and then Exact_Counts (Book)
                 and then Success = Ready (Book);

   --  A canonical representation is determined by its length array: exact
   --  histograms cannot differ once the per-symbol lengths agree.
   procedure Lemma_Exact_Books_Equal (Left, Right : Codebook)
   with
     Ghost,
     Global => null,
     Pre    => Left.Kind = Canonical
                 and then Right.Kind = Canonical
                 and then Exact_Counts (Left)
                 and then Exact_Counts (Right)
                 and then Left.Lengths = Right.Lengths,
     Post   => Left = Right;

   procedure Lemma_Length_Arrays_Equal
     (Left, Right : Code_Length_Array)
   with
     Ghost,
     Global => null,
     Pre    => (for all I in Symbol_Index => Left (I) = Right (I)),
     Post   => Left = Right;

   procedure Lemma_Canonical_Lengths_Equal (Left, Right : Codebook)
   with
     Ghost,
     Global => null,
     Pre    => Left.Kind = Canonical
                 and then Right.Kind = Canonical
                 and then
               (for all I in Symbol_Index =>
                  Length_Of (Left, I) = Length_Of (Right, I)),
     Post   => Left.Lengths = Right.Lengths;

   procedure Lemma_Ready_From_Fields (Left, Right : Codebook)
   with
     Ghost,
     Global => null,
     Pre    => Left.Kind = Canonical
                 and then Right.Kind = Canonical
                 and then Left.Lengths = Right.Lengths
                 and then Left.Counts = Right.Counts
                 and then Ready (Left),
     Post   => Ready (Right);

   procedure Lemma_Lengths_At_Most_From_Fields
     (Left, Right : Codebook;
      Maximum     : Code_Length)
   with
     Ghost,
     Global => null,
     Pre    => Left.Kind = Canonical
                 and then Right.Kind = Canonical
                 and then Left.Lengths = Right.Lengths
                 and then Lengths_At_Most (Left, Maximum),
     Post   => Lengths_At_Most (Right, Maximum);

   procedure Lemma_Length_Of_From_Fields (Left, Right : Codebook)
   with
     Ghost,
     Global => null,
     Pre    => Left.Kind = Canonical
                 and then Right.Kind = Canonical
                 and then Left.Lengths = Right.Lengths,
     Post   =>
       (for all Symbol in Symbol_Index =>
          Length_Of (Left, Symbol) = Length_Of (Right, Symbol));

   procedure Lemma_Code_Of_From_Fields
     (Left, Right : Codebook;
      Symbol      : Symbol_Index)
   with
     Ghost,
     Global => null,
     Pre    => Left.Kind = Canonical
                 and then Right.Kind = Canonical
                 and then Left.Lengths = Right.Lengths
                 and then Left.Counts = Right.Counts
                 and then Ready (Left)
                 and then Ready (Right)
                 and then Length_Of (Left, Symbol) /= 0,
     Post   => Length_Of (Left, Symbol) = Length_Of (Right, Symbol)
                 and then Code_Of (Left, Symbol) = Code_Of (Right, Symbol);

end Inflate.Codebooks;
