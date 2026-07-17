--  Inflate.Dynamic -- bounded code-length construction for dynamic Huffman.
--
--  This package owns the local dynamic-block construction, but deliberately
--  does not connect it to the gzip compressor yet.  Build_Lengths selects every
--  symbol with nonzero frequency, adds dummy leaves only when fewer than two
--  symbols are used, and gives the selected leaves a balanced complete
--  prefix-code shape.  The construction is not claimed to be optimal.
--  Build_Codebook turns those lengths into the common canonical
--  representation; Serialize_Header transmits those books through a simple
--  complete code-length alphabet; and Serialize_Payload uses the same token
--  writer as the fixed implementation.

with Inflate.Codebooks;
with Inflate.Fixed;
with Inflate.Payload;

package Inflate.Dynamic with Pure, SPARK_Mode => On is

   use type Codebooks.Codebook_Kind;

   pragma Assertion_Policy (Ghost => Ignore);

   Max_Symbols : constant := 286;

   Literal_Length_Count : constant := 286;
   Distance_Count       : constant := 30;

   --  The local dynamic header uses all legal literal/length and distance
   --  slots.  Its code-length alphabet assigns a four-bit code to symbols
   --  0 .. 15 and leaves repeat symbols 16 .. 18 absent.  Consequently every
   --  transmitted length is one direct four-bit symbol: no RLE proof is needed
   --  before the dynamic body is connected through the common Body_Encodes
   --  relation.
   Header_Prefix_Bits : constant := 3 + 5 + 5 + 4 + 19 * 3;
   Header_Bit_Count   : constant :=
     Header_Prefix_Bits
       + 4 * (Literal_Length_Count + Distance_Count);
   Header_Byte_Count  : constant := (Header_Bit_Count + 7) / 8;

   --  Leave room for the dynamic header, a worst-case nine-bit code per input
   --  byte, a nine-bit end-of-block code, and byte rounding.
   Max_Input : constant Natural :=
     (8 * Fixed.Max_Stream_Bytes - Header_Bit_Count - 16) / 9;

   function Max_Size (N : Natural) return Positive is
     ((Header_Bit_Count + 9 * N + 16) / 8)
   with
     Pre  => N <= Max_Input,
     Post => Max_Size'Result <= Fixed.Max_Stream_Bytes;

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
                       then Codebooks.Length_Of (Book, I) > 0))
                     and then
                   (for all I in Frequencies'Length ..
                      Codebooks.Symbol_Index'Last =>
                        Codebooks.Length_Of (Book, I) = 0));

   --  The caller supplies the two canonical books produced for the complete
   --  DEFLATE alphabets.  Symbols beyond the counts carried by the dynamic
   --  header must be absent so the decoder reconstructs the same books.
   function Books_Encodable
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook) return Boolean
   is
     (Literal_Lengths.Kind = Codebooks.Canonical
      and then Distances.Kind = Codebooks.Canonical
      and then Codebooks.Ready (Literal_Lengths)
      and then Codebooks.Ready (Distances)
      and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
      and then Codebooks.Lengths_At_Most (Distances, 9)
      and then
        (for all I in Literal_Length_Count .. Codebooks.Symbol_Index'Last =>
           Codebooks.Length_Of (Literal_Lengths, I) = 0)
      and then
        (for all I in Distance_Count .. Codebooks.Symbol_Index'Last =>
           Codebooks.Length_Of (Distances, I) = 0));

   --  Expected value of one of the fixed prefix bits before the 316 directly
   --  encoded literal/length and distance lengths.  Numeric DEFLATE fields are
   --  transmitted least-significant bit first.
   function Expected_Header_Bit (Position : Natural) return Natural is
     (if Position = 0 then 1
      elsif Position = 2 then 1
      elsif Position in 3 .. 7
      then (29 / Codebooks.Pow2 (Position - 3)) mod 2
      elsif Position in 8 .. 12
      then (29 / Codebooks.Pow2 (Position - 8)) mod 2
      elsif Position in 13 .. 16 then 1
      elsif Position >= 17
        and then (Position - 17) / 3 >= 3
        and then (Position - 17) mod 3 = 2
      then 1
      else 0)
   with
     Pre  => Position < Header_Prefix_Bits,
     Post => Expected_Header_Bit'Result <= 1;

   --  Four stream bits spell one canonical code-length symbol.  The local
   --  code-length alphabet contains symbols 0 .. 15, all at length four.
   function Length_Code_At
     (Input : Byte_Array;
      Start : Natural;
      Value : Code_Length) return Boolean
   is
     (Fixed.Bit_Value (Input, Start) = Value / 8
      and then Fixed.Bit_Value (Input, Start + 1) = (Value / 4) mod 2
      and then Fixed.Bit_Value (Input, Start + 2) = (Value / 2) mod 2
      and then Fixed.Bit_Value (Input, Start + 3) = Value mod 2)
   with
     Pre => Input'Length <= Fixed.Max_Stream_Bytes
              and then Start <= 8 * Input'Length
              and then 4 <= 8 * Input'Length - Start;

   --  The first Header_Bit_Count bits are one final dynamic-block header that
   --  reconstructs Literal_Lengths and Distances exactly.  The code-length
   --  tree is the complete four-bit assignment for direct symbols 0 .. 15;
   --  repeat symbols are deliberately unused.
   function Header_Encodes
     (Input           : Byte_Array;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook) return Boolean
   is
     ((for all Position in 0 .. Header_Prefix_Bits - 1 =>
         Fixed.Bit_Value (Input, Position) =
           Expected_Header_Bit (Position))
      and then
        (for all I in 0 .. Literal_Length_Count - 1 =>
           Length_Code_At
             (Input, Header_Prefix_Bits + 4 * I,
              Codebooks.Length_Of (Literal_Lengths, I)))
      and then
        (for all I in 0 .. Distance_Count - 1 =>
           Length_Code_At
             (Input,
              Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
              Codebooks.Length_Of (Distances, I))))
   with
     Pre => Input'Length <= Fixed.Max_Stream_Bytes
              and then Input'Length >= Header_Byte_Count
              and then Books_Encodable (Literal_Lengths, Distances);

   --  Serialize only the dynamic block header.  Bits outside its half-open
   --  interval are preserved, so the shared payload writer can follow it.
   procedure Serialize_Header
     (Literal_Lengths : in     Codebooks.Codebook;
      Distances       : in     Codebooks.Codebook;
      Output          : in out Byte_Array;
      Next_Bit        :    out Natural)
   with
     Global => null,
     Pre    => Output'Length <= Fixed.Max_Stream_Bytes
                 and then Output'Length >= Header_Byte_Count
                 and then Books_Encodable (Literal_Lengths, Distances),
     Post   => Next_Bit = Header_Bit_Count
                 and then Header_Encodes
                   (Output, Literal_Lengths, Distances)
                 and then
               (for all Position in Header_Bit_Count ..
                  8 * Output'Length - 1 =>
                    Fixed.Bit_Value (Output, Position) =
                      Fixed.Bit_Value (Output'Old, Position));

   --  Dynamic payloads use the same literal/match/end-of-block serializer as
   --  fixed payloads.  Start normally names Header_Bit_Count, but remains
   --  explicit so the shared writer can be checked independently.
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
                   (Output, Start, Literal_Lengths, Distances, Data)
                 and then
               (for all Position in 0 .. 8 * Output'Length - 1 =>
                  (if Position < Start or else Position >= Next_Bit
                   then Fixed.Bit_Value (Output, Position) =
                          Fixed.Bit_Value (Output'Old, Position)));
   pragma Assertion_Policy (Pre => Check, Post => Check);

   --  Local relation for one complete final dynamic block.  This deliberately
   --  stops below Inflate.GZip: the next milestone will lift stored, fixed,
   --  and dynamic bodies through one Body_Encodes relation.
   function Is_Encoding
     (Input           : Byte_Array;
      Produced        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array) return Boolean
   is
     (Produced in 1 .. Input'Length
      and then Header_Encodes (Input, Literal_Lengths, Distances)
      and then Payload.Is_Encoding
        (Input, Header_Bit_Count, Literal_Lengths, Distances, Data)
      and then Produced =
        (Header_Bit_Count
           + Payload.Data_Bits
               (Literal_Lengths, Distances, Data, Data'Length)
           + Codebooks.Length_Of (Literal_Lengths, 256) + 7) / 8)
   with
     Ghost,
     Pre => Input'Length <= Fixed.Max_Stream_Bytes
              and then Input'Length >= Header_Byte_Count
              and then Data'Length <= Max_Input
              and then Books_Encodable (Literal_Lengths, Distances)
              and then Payload.Covers
                (Literal_Lengths, Distances, Data);

   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);
   procedure Serialize_Body
     (Data            : in     Byte_Array;
      Literal_Lengths : in     Codebooks.Codebook;
      Distances       : in     Codebooks.Codebook;
      Output          : in out Byte_Array;
      Produced        :    out Natural)
   with
     Global => null,
     Pre    => Data'Length <= Max_Input
                 and then Output'Length <= Fixed.Max_Stream_Bytes
                 and then Output'Length >= Max_Size (Data'Length)
                 and then Books_Encodable (Literal_Lengths, Distances)
                 and then Payload.Covers
                   (Literal_Lengths, Distances, Data),
     Post   => Produced <= Max_Size (Data'Length)
                 and then Is_Encoding
                   (Output, Produced, Literal_Lengths, Distances, Data);
   pragma Assertion_Policy (Pre => Check, Post => Check);

end Inflate.Dynamic;
