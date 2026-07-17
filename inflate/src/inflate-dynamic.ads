--  Inflate.Dynamic -- bounded code-length construction for dynamic Huffman.
--
--  This package deliberately solves only the local tree-building problem.
--  It does not serialize a dynamic header or connect a dynamic block to the
--  gzip compressor.  Build_Lengths selects every symbol with nonzero
--  frequency, adds dummy leaves only when fewer than two symbols are used,
--  and gives the selected leaves a balanced complete prefix-code shape.
--  The construction is not claimed to be optimal.  Build_Codebook turns those
--  lengths into the common canonical representation, and Serialize_Payload
--  uses the same token writer as the fixed implementation.

with Inflate.Codebooks;
with Inflate.Fixed;
with Inflate.Payload;

package Inflate.Dynamic with Pure, SPARK_Mode => On is

   use type Codebooks.Codebook_Kind;

   Max_Symbols : constant := 286;

   subtype Symbol_Index is Natural range 0 .. Max_Symbols - 1;
   subtype Symbol_Count is Natural range 0 .. Max_Symbols;
   subtype Code_Length is Natural range 0 .. 15;

   type Frequency_Array is array (Symbol_Index range <>) of Natural;
   type Code_Length_Array is array (Symbol_Index range <>) of Code_Length;

   Pow2 : constant array (Natural range 0 .. 15) of Natural :=
     (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1_024, 2_048,
      4_096, 8_192, 16_384, 32_768);

   --  Number of nonzero frequencies in the first Count entries.
   function Active_Count
     (Frequencies : Frequency_Array;
      Count       : Symbol_Count) return Symbol_Count
   is
     (if Count = 0 then 0
      else Active_Count (Frequencies, Count - 1)
        + (if Frequencies (Symbol_Index (Count - 1)) = 0 then 0 else 1))
   with
     Pre  => Frequencies'First = 0
               and then Count <= Frequencies'Length,
     Post => Active_Count'Result <= Count,
     Subprogram_Variant => (Decreases => Count);

   --  Number of assigned code lengths in the first Count entries.
   function Assigned_Count
     (Lengths : Code_Length_Array;
      Count   : Symbol_Count) return Symbol_Count
   is
     (if Count = 0 then 0
      else Assigned_Count (Lengths, Count - 1)
        + (if Lengths (Symbol_Index (Count - 1)) = 0 then 0 else 1))
   with
     Pre  => Lengths'First = 0 and then Count <= Lengths'Length,
     Post => Assigned_Count'Result <= Count,
     Subprogram_Variant => (Decreases => Count);

   --  Kraft sum scaled by 2**15.  Equality with 2**15 says that the
   --  nonzero lengths exactly fill a complete binary prefix code.
   function Code_Space
     (Lengths : Code_Length_Array;
      Count   : Symbol_Count) return Natural
   is
     (if Count = 0 then 0
      elsif Lengths (Symbol_Index (Count - 1)) = 0
      then Code_Space (Lengths, Count - 1)
      else Code_Space (Lengths, Count - 1)
        + Pow2 (15 - Lengths (Symbol_Index (Count - 1))))
   with
     Pre  => Lengths'First = 0 and then Count <= Lengths'Length,
     Post => Code_Space'Result <= Count * Pow2 (15),
     Subprogram_Variant => (Decreases => Count);

   function Required_Leaves
     (Frequencies : Frequency_Array) return Symbol_Count
   is
     (Symbol_Count'Max
        (2, Active_Count (Frequencies, Frequencies'Length)))
   with
     Pre  => Frequencies'First = 0
               and then Frequencies'Length in 2 .. Max_Symbols,
     Post => Required_Leaves'Result in 2 .. Frequencies'Length;

   --  Build a balanced complete code for all used symbols.  With at most 286
   --  selected leaves, the balanced construction needs at most nine bits;
   --  the stronger bound makes the RFC 1951 limit of fifteen immediate.
   pragma Assertion_Policy (Post => Ignore);
   procedure Build_Lengths
     (Frequencies : in     Frequency_Array;
      Lengths     :    out Code_Length_Array)
   with
     Global => null,
     Pre    => Frequencies'First = 0
                 and then Frequencies'Length in 2 .. Max_Symbols
                 and then Lengths'First = Frequencies'First
                 and then Lengths'Last = Frequencies'Last,
     Post   =>
       (for all I in Frequencies'Range =>
          (if Frequencies (I) > 0 then Lengths (I) > 0))
       and then
       (for all I in Lengths'Range => Lengths (I) <= 9)
       and then Assigned_Count (Lengths, Lengths'Length) =
                  Required_Leaves (Frequencies)
       and then Code_Space (Lengths, Lengths'Length) = Pow2 (15);
   pragma Assertion_Policy (Post => Check);

   --  Lift the bounded length builder into the shared codebook boundary.
   --  Success is retained as a defensive executable check at the boundary;
   --  whenever it is true the book is ready and covers every active symbol.
   procedure Build_Codebook
     (Frequencies : in     Frequency_Array;
      Book        :    out Codebooks.Codebook;
      Success     :    out Boolean)
   with
     Global => null,
     Pre    => Frequencies'First = 0
                 and then Frequencies'Length in 2 .. Max_Symbols
                 and then Book.Kind = Codebooks.Canonical,
     Post   => Book.Kind = Codebooks.Canonical
                 and then Codebooks.Exact_Counts (Book)
                 and then
               (if Success
                then Codebooks.Ready (Book)
                     and then Codebooks.Lengths_At_Most (Book, 9)
                     and then
                   (for all I in Frequencies'Range =>
                      (if Frequencies (I) > 0
                       then Codebooks.Length_Of (Book, I) > 0)));

   --  Dynamic payloads use the same literal/match/end-of-block serializer as
   --  fixed payloads.  Header serialization is intentionally the next local
   --  step, so Start names the first payload bit supplied by that future
   --  header writer.
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);
   procedure Serialize_Payload
     (Data            : in     Byte_Array;
      Literal_Lengths : in     Codebooks.Codebook;
      Distances       : in     Codebooks.Codebook;
      Output          : in out Byte_Array;
      Start           : in     Natural;
      Next_Bit        :    out Natural)
   with
     Global => null,
     Pre    => Output'Length <= Fixed.Max_Stream_Bytes
                 and then Data'Length <= Fixed.Max_Input
                 and then Codebooks.Ready (Literal_Lengths)
                 and then Codebooks.Ready (Distances)
                 and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
                 and then Codebooks.Lengths_At_Most (Distances, 9)
                 and then Payload.Covers
                   (Literal_Lengths, Distances, Data)
                 and then Start <= 8 * Output'Length
                 and then Payload.Data_Bits
                   (Literal_Lengths, Distances, Data, Data'Length)
                   + Codebooks.Length_Of (Literal_Lengths, 256) <=
                     8 * Output'Length - Start,
     Post   => Next_Bit = Start + Payload.Data_Bits
                 (Literal_Lengths, Distances, Data, Data'Length)
                   + Codebooks.Length_Of (Literal_Lengths, 256)
                 and then Payload.Is_Encoding
                   (Output, Start, Literal_Lengths, Distances, Data);
   pragma Assertion_Policy (Pre => Check, Post => Check);

end Inflate.Dynamic;
