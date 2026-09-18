--  Inflate.Dynamic -- bounded code-length construction for dynamic Huffman.
--
--  This package owns the local dynamic-block construction. Build_Lengths
--  selects every symbol with nonzero frequency, adds dummy leaves only when
--  fewer than two symbols are used, and gives the selected leaves a balanced
--  complete prefix-code shape. The construction is not claimed to be optimal.
--  Build_Codebook turns those lengths into the common canonical
--  representation; Serialize_Header transmits those books through a simple
--  complete code-length alphabet; and Serialize_Payload uses the same token
--  writer as the fixed implementation.

with Inflate.Codebooks;
with Inflate.Fixed;
with Inflate.Payload;

package Inflate.Dynamic
  with Pure, SPARK_Mode => On
is

   use type Codebooks.Codebook_Kind;
   use type Codebooks.Codebook;
   use type Codebooks.Code_Length_Array;
   use type Codebooks.Length_Count_Array;
   use type Fixed.Symbol_Kind;
   use type Fixed.Symbol_Result;

   pragma Assertion_Policy (Ghost => Ignore);

   Max_Symbols : constant := 286;

   Literal_Length_Count : constant := 286;
   Distance_Count       : constant := 30;

   --  The local dynamic header uses all legal literal/length and distance
   --  slots.  Its code-length alphabet assigns a four-bit code to symbols
   --  0 .. 15 and leaves repeat symbols 16 .. 18 absent.  Consequently every
   --  transmitted length is one direct four-bit symbol: no RLE proof is needed
   --  in the common Body_Encodes relation.
   Header_Prefix_Bits : constant := 3 + 5 + 5 + 4 + 19 * 3;
   Header_Bit_Count   : constant :=
     Header_Prefix_Bits + 4 * (Literal_Length_Count + Distance_Count);
   Header_Byte_Count  : constant := (Header_Bit_Count + 7) / 8;

   --  Leave room for the dynamic header, a worst-case nine-bit code per input
   --  byte, a nine-bit end-of-block code, byte rounding, and the eight-byte
   --  gzip trailer carried in common recognition slices.
   Max_Input : constant Natural :=
     (8 * (Fixed.Max_Stream_Bytes - 8) - Header_Bit_Count - 16) / 9;

   function Max_Size (N : Natural) return Positive
   is ((Header_Bit_Count + 9 * N + 16) / 8)
   with
     Pre  => N <= Max_Input,
     Post => Max_Size'Result <= Fixed.Max_Stream_Bytes - 8;

   --  The first data-dependent top-level dynamic selection is deliberately
   --  narrow.  Long constant-byte runs have a small set of literal/length and
   --  distance symbols, so a sparse dynamic book repays this package's
   --  deliberately uncompressed header.  Other inputs retain the fixed or
   --  stored gzip paths while later M6 work generalizes frequency collection.
   Dynamic_Run_Min_Input : constant := 4_096;

   function Selects_Byte_Run (Data : Byte_Array) return Boolean
   is (Data'Length in Dynamic_Run_Min_Input .. Max_Input
       and then (for all B of Data => B = Data (Data'First)));

   subtype Symbol_Index is Natural range 0 .. Max_Symbols - 1;
   subtype Symbol_Count is Natural range 0 .. Max_Symbols;
   subtype Code_Length is Natural range 0 .. 15;

   type Frequency_Array is array (Symbol_Index range <>) of Natural;
   type Code_Length_Array is array (Symbol_Index range <>) of Code_Length;

   Pow2 : constant array (Natural range 0 .. 15) of Natural :=
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
      1_024,
      2_048,
      4_096,
      8_192,
      16_384,
      32_768);

   --  Number of nonzero frequencies in the first Count entries.
   function Active_Count
     (Frequencies : Frequency_Array; Count : Symbol_Count) return Symbol_Count
   is (if Count = 0
       then 0
       else
         Active_Count (Frequencies, Count - 1)
         + (if Frequencies (Symbol_Index (Count - 1)) = 0 then 0 else 1))
   with
     Pre                =>
       Frequencies'First = 0 and then Count <= Frequencies'Length,
     Post               => Active_Count'Result <= Count,
     Subprogram_Variant => (Decreases => Count);

   --  Number of assigned code lengths in the first Count entries.
   function Assigned_Count
     (Lengths : Code_Length_Array; Count : Symbol_Count) return Symbol_Count
   is (if Count = 0
       then 0
       else
         Assigned_Count (Lengths, Count - 1)
         + (if Lengths (Symbol_Index (Count - 1)) = 0 then 0 else 1))
   with
     Pre                => Lengths'First = 0 and then Count <= Lengths'Length,
     Post               => Assigned_Count'Result <= Count,
     Subprogram_Variant => (Decreases => Count);

   --  Kraft sum scaled by 2**15.  Equality with 2**15 says that the
   --  nonzero lengths exactly fill a complete binary prefix code.
   function Code_Space
     (Lengths : Code_Length_Array; Count : Symbol_Count) return Natural
   is (if Count = 0
       then 0
       elsif Lengths (Symbol_Index (Count - 1)) = 0
       then Code_Space (Lengths, Count - 1)
       else
         Code_Space (Lengths, Count - 1)
         + Pow2 (15 - Lengths (Symbol_Index (Count - 1))))
   with
     Pre                => Lengths'First = 0 and then Count <= Lengths'Length,
     Post               => Code_Space'Result <= Count * Pow2 (15),
     Subprogram_Variant => (Decreases => Count);

   function Required_Leaves (Frequencies : Frequency_Array) return Symbol_Count
   is (Symbol_Count'Max (2, Active_Count (Frequencies, Frequencies'Length)))
   with
     Pre  =>
       Frequencies'First = 0 and then Frequencies'Length in 2 .. Max_Symbols,
     Post => Required_Leaves'Result in 2 .. Frequencies'Length;

   --  Build a balanced complete code for all used symbols.  With at most 286
   --  selected leaves, the balanced construction needs at most nine bits;
   --  the stronger bound makes the RFC 1951 limit of fifteen immediate.
   pragma Assertion_Policy (Post => Ignore);
   procedure Build_Lengths
     (Frequencies : in Frequency_Array; Lengths : out Code_Length_Array)
   with
     Global => null,
     Pre    =>
       Frequencies'First = 0
       and then Frequencies'Length in 2 .. Max_Symbols
       and then Lengths'First = Frequencies'First
       and then Lengths'Last = Frequencies'Last,
     Post   =>
       (for all I in Frequencies'Range =>
          (if Frequencies (I) > 0 then Lengths (I) > 0))
       and then (for all I in Lengths'Range => Lengths (I) <= 9)
       and then Assigned_Count (Lengths, Lengths'Length)
                = Required_Leaves (Frequencies)
       and then Code_Space (Lengths, Lengths'Length) = Pow2 (15);
   pragma Assertion_Policy (Post => Check);

   --  Lift the bounded length builder into the shared codebook boundary.
   --  Success is retained as a defensive executable check at the boundary;
   --  whenever it is true the book is ready and covers every active symbol.
   procedure Build_Codebook
     (Frequencies : in Frequency_Array;
      Book        : out Codebooks.Codebook;
      Success     : out Boolean)
   with
     Global => null,
     Pre    =>
       Frequencies'First = 0
       and then Frequencies'Length in 2 .. Max_Symbols
       and then Book.Kind = Codebooks.Canonical,
     Post   =>
       Book.Kind = Codebooks.Canonical
       and then Codebooks.Exact_Counts (Book)
       and then (if Success
                 then
                   Codebooks.Ready (Book)
                   and then Codebooks.Lengths_At_Most (Book, 9)
                   and then (for all I in Frequencies'Range =>
                               (if Frequencies (I) > 0
                                then Codebooks.Length_Of (Book, I) > 0))
                   and then (for all I in
                               Frequencies'Length
                               .. Codebooks.Symbol_Index'Last =>
                               Codebooks.Length_Of (Book, I) = 0));

   --  The caller supplies the two canonical books produced for the complete
   --  DEFLATE alphabets.  Symbols beyond the counts carried by the dynamic
   --  header must be absent so the decoder reconstructs the same books.
   function Books_Encodable
     (Literal_Lengths : Codebooks.Codebook; Distances : Codebooks.Codebook)
      return Boolean
   is (Literal_Lengths.Kind = Codebooks.Canonical
       and then Distances.Kind = Codebooks.Canonical
       and then Codebooks.Ready (Literal_Lengths)
       and then Codebooks.Ready (Distances)
       and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
       and then Codebooks.Lengths_At_Most (Distances, 9)
       and then (for all I in
                   Literal_Length_Count .. Codebooks.Symbol_Index'Last =>
                   Codebooks.Length_Of (Literal_Lengths, I) = 0)
       and then (for all I in Distance_Count .. Codebooks.Symbol_Index'Last =>
                   Codebooks.Length_Of (Distances, I) = 0));

   --  Expected value of one of the fixed prefix bits before the 316 directly
   --  encoded literal/length and distance lengths.  Numeric DEFLATE fields are
   --  transmitted least-significant bit first.
   function Expected_Header_Bit (Position : Natural) return Natural
   is (if Position = 0
       then 1
       elsif Position = 2
       then 1
       elsif Position in 3 .. 7
       then (29 / Codebooks.Pow2 (Position - 3)) mod 2
       elsif Position in 8 .. 12
       then (29 / Codebooks.Pow2 (Position - 8)) mod 2
       elsif Position in 13 .. 16
       then 1
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
     (Input : Byte_Array; Start : Natural; Value : Code_Length) return Boolean
   is (Fixed.Bit_Value (Input, Start) = Value / 8
       and then Fixed.Bit_Value (Input, Start + 1) = (Value / 4) mod 2
       and then Fixed.Bit_Value (Input, Start + 2) = (Value / 2) mod 2
       and then Fixed.Bit_Value (Input, Start + 3) = Value mod 2)
   with
     Pre =>
       Input'Length <= Fixed.Max_Stream_Bytes
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
   is ((for all Position in 0 .. Header_Prefix_Bits - 1 =>
          Fixed.Bit_Value (Input, Position) = Expected_Header_Bit (Position))
       and then (for all I in 0 .. Literal_Length_Count - 1 =>
                   Length_Code_At
                     (Input,
                      Header_Prefix_Bits + 4 * I,
                      Codebooks.Length_Of (Literal_Lengths, I)))
       and then (for all I in 0 .. Distance_Count - 1 =>
                   Length_Code_At
                     (Input,
                      Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
                      Codebooks.Length_Of (Distances, I))))
   with
     Pre =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count
       and then Books_Encodable (Literal_Lengths, Distances);

   --  Recover the canonical books carried by the local header.  These
   --  functions make the dynamic image input-determined: callers above this
   --  package no longer need existential codebook witnesses merely to name
   --  the body relation.  Slots not transmitted by the header are zero, as
   --  required by Books_Encodable.
   function Literal_Book_From_Header
     (Input : Byte_Array) return Codebooks.Codebook
   with
     Pre  =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count,
     Post =>
       Literal_Book_From_Header'Result.Kind = Codebooks.Canonical
       and then Codebooks.Exact_Counts (Literal_Book_From_Header'Result)
       and then (for all I in 0 .. Literal_Length_Count - 1 =>
                   Codebooks.Length_Of (Literal_Book_From_Header'Result, I)
                   = Fixed.Prefix_Value (Input, Header_Prefix_Bits + 4 * I, 4))
       and then (for all I in
                   Literal_Length_Count .. Codebooks.Symbol_Index'Last =>
                   Codebooks.Length_Of (Literal_Book_From_Header'Result, I)
                   = 0);

   function Distance_Book_From_Header
     (Input : Byte_Array) return Codebooks.Codebook
   with
     Pre  =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count,
     Post =>
       Distance_Book_From_Header'Result.Kind = Codebooks.Canonical
       and then Codebooks.Exact_Counts (Distance_Book_From_Header'Result)
       and then (for all I in 0 .. Distance_Count - 1 =>
                   Codebooks.Length_Of (Distance_Book_From_Header'Result, I)
                   = Fixed.Prefix_Value
                       (Input,
                        Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
                        4))
       and then (for all I in Distance_Count .. Codebooks.Symbol_Index'Last =>
                   Codebooks.Length_Of (Distance_Book_From_Header'Result, I)
                   = 0);

   procedure Lemma_Header_Books_Recovered
     (Input           : Byte_Array;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook)
   with
     Ghost,
     Global => null,
     Pre    =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count
       and then Books_Encodable (Literal_Lengths, Distances)
       and then Header_Encodes (Input, Literal_Lengths, Distances),
     Post   =>
       Literal_Book_From_Header (Input) = Literal_Lengths
       and then Distance_Book_From_Header (Input) = Distances
       and then Literal_Book_From_Header (Input).Lengths
                = Literal_Lengths.Lengths
       and then Literal_Book_From_Header (Input).Counts
                = Literal_Lengths.Counts
       and then Distance_Book_From_Header (Input).Lengths = Distances.Lengths
       and then Distance_Book_From_Header (Input).Counts = Distances.Counts;

   --  Serialize only the dynamic block header.  Bits outside its half-open
   --  interval are preserved, so the shared payload writer can follow it.
   procedure Serialize_Header
     (Literal_Lengths : in Codebooks.Codebook;
      Distances       : in Codebooks.Codebook;
      Output          : in out Byte_Array;
      Next_Bit        : out Natural)
   with
     Global => null,
     Pre    =>
       Output'Length <= Fixed.Max_Stream_Bytes
       and then Output'Length >= Header_Byte_Count
       and then Books_Encodable (Literal_Lengths, Distances),
     Post   =>
       Next_Bit = Header_Bit_Count
       and then Header_Encodes (Output, Literal_Lengths, Distances)
       and then (for all Position in
                   Header_Bit_Count .. 8 * Output'Length - 1 =>
                   Fixed.Bit_Value (Output, Position)
                   = Fixed.Bit_Value (Output'Old, Position));

   --  Dynamic payloads use the same literal/match/end-of-block serializer as
   --  fixed payloads.  Start normally names Header_Bit_Count, but remains
   --  explicit so the shared writer can be checked independently.
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);
   procedure Serialize_Payload
     (Data            : in Byte_Array;
      Literal_Lengths : in Codebooks.Codebook;
      Distances       : in Codebooks.Codebook;
      Output          : in out Byte_Array;
      Start           : in Natural;
      Next_Bit        : out Natural)
   with
     Global => null,
     Pre    =>
       Output'Length <= Fixed.Max_Stream_Bytes
       and then Data'Length <= Fixed.Max_Input
       and then Codebooks.Ready (Literal_Lengths)
       and then Codebooks.Ready (Distances)
       and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
       and then Codebooks.Lengths_At_Most (Distances, 9)
       and then Payload.Covers (Literal_Lengths, Distances, Data)
       and then Start <= 8 * Output'Length
       and then Payload.Data_Bits
                  (Literal_Lengths, Distances, Data, Data'Length)
                + Codebooks.Length_Of (Literal_Lengths, 256)
                <= 8 * Output'Length - Start,
     Post   =>
       Next_Bit
       = Start
         + Payload.Data_Bits (Literal_Lengths, Distances, Data, Data'Length)
         + Codebooks.Length_Of (Literal_Lengths, 256)
       and then Payload.Is_Encoding
                  (Output, Start, Literal_Lengths, Distances, Data)
       and then (for all Position in 0 .. 8 * Output'Length - 1 =>
                   (if Position < Start or else Position >= Next_Bit
                    then
                      Fixed.Bit_Value (Output, Position)
                      = Fixed.Bit_Value (Output'Old, Position)));
   pragma Assertion_Policy (Pre => Check, Post => Check);

   --  Local relation for one complete final dynamic block.  Inflate.Bodies
   --  lifts its witness-free form into the common semantic relation; gzip does
   --  not select that alternative until decoder completeness is connected.
   function Is_Encoding
     (Input           : Byte_Array;
      Produced        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array) return Boolean
   is (Produced in 1 .. Input'Length
       and then Header_Encodes (Input, Literal_Lengths, Distances)
       and then Payload.Is_Encoding
                  (Input, Header_Bit_Count, Literal_Lengths, Distances, Data)
       and then Produced
                = (Header_Bit_Count
                   + Payload.Data_Bits
                       (Literal_Lengths, Distances, Data, Data'Length)
                   + Codebooks.Length_Of (Literal_Lengths, 256)
                   + 7)
                  / 8)
   with
     Ghost,
     Pre =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count
       and then Data'Length <= Max_Input
       and then Books_Encodable (Literal_Lengths, Distances)
       and then Payload.Covers (Literal_Lengths, Distances, Data);

   --  Witness-free form of the local dynamic relation.  The codebooks are
   --  recovered from Input, so the body has the same three-argument shape as
   --  the common body boundary.  Framing, input-side analysis, and
   --  functionality are proved below; Inflate.Bodies routes those semantic
   --  consequences while executable recognition awaits decoder completeness.
   function Is_Encoding
     (Input : Byte_Array; Produced : Natural; Data : Byte_Array) return Boolean
   is (Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count
       and then Data'Length <= Max_Input
       and then Books_Encodable
                  (Literal_Book_From_Header (Input),
                   Distance_Book_From_Header (Input))
       and then Payload.Covers
                  (Literal_Book_From_Header (Input),
                   Distance_Book_From_Header (Input),
                   Data)
       and then Is_Encoding
                  (Input,
                   Produced,
                   Literal_Book_From_Header (Input),
                   Distance_Book_From_Header (Input),
                   Data))
   with Ghost;

   type Stream_Info is record
      Valid          : Boolean;
      End_Bit        : Natural;
      Decoded_Length : Natural;
   end record;

   type Decoded_Symbol is record
      Valid    : Boolean;
      Symbol   : Codebooks.Symbol_Index;
      Position : Natural;
   end record;

   function Code_Matches
     (Input  : Byte_Array;
      Start  : Natural;
      Book   : Codebooks.Codebook;
      Symbol : Codebooks.Symbol_Index) return Boolean
   is (Codebooks.Length_Of (Book, Symbol) > 0
       and then Codebooks.Length_Of (Book, Symbol) <= 8 * Input'Length - Start
       and then Fixed.Prefix_Value
                  (Input, Start, Codebooks.Length_Of (Book, Symbol))
                = Codebooks.Code_Of (Book, Symbol))
   with
     Pre =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Start <= 8 * Input'Length
       and then Book.Kind = Codebooks.Canonical
       and then Codebooks.Ready (Book)
       and then Codebooks.Lengths_At_Most (Book, 9);

   --  Decode one canonical codeword, returning the original bit position on
   --  failure.  The exhaustive bounded scan is intentionally simple: the
   --  local books contain at most 288 symbols with lengths at most nine.
   pragma Assertion_Policy (Post => Ignore);
   function Decode_Symbol
     (Input : Byte_Array; Start : Natural; Book : Codebooks.Codebook)
      return Decoded_Symbol
   with
     Pre  =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Start <= 8 * Input'Length
       and then Book.Kind = Codebooks.Canonical
       and then Codebooks.Ready (Book)
       and then Codebooks.Lengths_At_Most (Book, 9),
     Post =>
       Decode_Symbol'Result.Position in Start .. 8 * Input'Length
       and then (if Decode_Symbol'Result.Valid
                 then
                   Code_Matches
                     (Input, Start, Book, Decode_Symbol'Result.Symbol)
                   and then Decode_Symbol'Result.Position
                            = Start
                              + Codebooks.Length_Of
                                  (Book, Decode_Symbol'Result.Symbol)
                 else
                   Decode_Symbol'Result = (False, 0, Start)
                   and then (for all Symbol in Codebooks.Symbol_Index =>
                               not Code_Matches (Input, Start, Book, Symbol)));
   pragma Assertion_Policy (Post => Check);

   --  Mathematical walk specified by the executable Walk below.  Decoded is
   --  the output cursor before Position; the result length counts only bytes
   --  produced by the remaining payload.
   function Spec_Walk
     (Input           : Byte_Array;
      Position        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Decoded         : Natural) return Stream_Info
   with
     Ghost,
     Pre                =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Position <= 8 * Input'Length
       and then Literal_Lengths.Kind = Codebooks.Canonical
       and then Distances.Kind = Codebooks.Canonical
       and then Codebooks.Ready (Literal_Lengths)
       and then Codebooks.Ready (Distances)
       and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
       and then Codebooks.Lengths_At_Most (Distances, 9)
       and then Decoded <= Max_Input,
     Post               =>
       (if Spec_Walk'Result.Valid
        then
          Spec_Walk'Result.End_Bit in Position + 1 .. 8 * Input'Length
          and then Spec_Walk'Result.Decoded_Length <= Max_Input - Decoded
        else Spec_Walk'Result = (False, 0, 0)),
     Contract_Cases     =>
       (not Decode_Symbol (Input, Position, Literal_Lengths).Valid
        => not Spec_Walk'Result.Valid,
        Decode_Symbol (Input, Position, Literal_Lengths).Valid
        and then Decode_Symbol (Input, Position, Literal_Lengths).Symbol <= 255
        and then Decoded < Max_Input
        =>
          (if Spec_Walk
                (Input,
                 Decode_Symbol (Input, Position, Literal_Lengths).Position,
                 Literal_Lengths,
                 Distances,
                 Decoded + 1)
                .Valid
           then
             Spec_Walk'Result
             = (True,
                Spec_Walk
                  (Input,
                   Decode_Symbol (Input, Position, Literal_Lengths).Position,
                   Literal_Lengths,
                   Distances,
                   Decoded + 1)
                  .End_Bit,
                Spec_Walk
                  (Input,
                   Decode_Symbol (Input, Position, Literal_Lengths).Position,
                   Literal_Lengths,
                   Distances,
                   Decoded + 1)
                  .Decoded_Length
                + 1)
           else Spec_Walk'Result = (False, 0, 0)),
        Decode_Symbol (Input, Position, Literal_Lengths).Valid
        and then Decode_Symbol (Input, Position, Literal_Lengths).Symbol = 256
        =>
          Spec_Walk'Result
          = (True,
             Decode_Symbol (Input, Position, Literal_Lengths).Position,
             0),
        Decode_Symbol (Input, Position, Literal_Lengths).Valid
        and then (Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                  in 257 .. 264)
        and then Decode_Symbol
                   (Input,
                    Decode_Symbol (Input, Position, Literal_Lengths).Position,
                    Distances)
                   .Valid
        and then Decode_Symbol
                   (Input,
                    Decode_Symbol (Input, Position, Literal_Lengths).Position,
                    Distances)
                   .Symbol
                 <= 3
        and then Decode_Symbol
                   (Input,
                    Decode_Symbol (Input, Position, Literal_Lengths).Position,
                    Distances)
                   .Symbol
                 + 1
                 <= Decoded
        and then Decode_Symbol (Input, Position, Literal_Lengths).Symbol - 254
                 <= Max_Input - Decoded
        =>
          (if Spec_Walk
                (Input,
                 Decode_Symbol
                   (Input,
                    Decode_Symbol (Input, Position, Literal_Lengths).Position,
                    Distances)
                   .Position,
                 Literal_Lengths,
                 Distances,
                 Decoded
                 + Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                 - 254)
                .Valid
           then
             Spec_Walk'Result
             = (True,
                Spec_Walk
                  (Input,
                   Decode_Symbol
                     (Input,
                      Decode_Symbol (Input, Position, Literal_Lengths)
                        .Position,
                      Distances)
                     .Position,
                   Literal_Lengths,
                   Distances,
                   Decoded
                   + Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                   - 254)
                  .End_Bit,
                Spec_Walk
                  (Input,
                   Decode_Symbol
                     (Input,
                      Decode_Symbol (Input, Position, Literal_Lengths)
                        .Position,
                      Distances)
                     .Position,
                   Literal_Lengths,
                   Distances,
                   Decoded
                   + Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                   - 254)
                  .Decoded_Length
                + Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                - 254)
           else Spec_Walk'Result = (False, 0, 0)),
        others
        => not Spec_Walk'Result.Valid),
     Subprogram_Variant => (Decreases => 8 * Input'Length - Position);

   pragma Assertion_Policy (Post => Ignore);
   function Walk
     (Input           : Byte_Array;
      Position        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Decoded         : Natural) return Stream_Info
   with
     Pre  =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Position <= 8 * Input'Length
       and then Literal_Lengths.Kind = Codebooks.Canonical
       and then Distances.Kind = Codebooks.Canonical
       and then Codebooks.Ready (Literal_Lengths)
       and then Codebooks.Ready (Distances)
       and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
       and then Codebooks.Lengths_At_Most (Distances, 9)
       and then Decoded <= Max_Input,
     Post =>
       Walk'Result
       = Spec_Walk (Input, Position, Literal_Lengths, Distances, Decoded);
   pragma Assertion_Policy (Post => Check);

   --  Recognize the bounded dynamic image from Input alone.  End_Bit is
   --  immediately after the end-of-block code and Decoded_Length is the
   --  number of bytes produced by the literal/match payload.  The analyzer
   --  recovers its canonical books from the serialized header; no codebook
   --  witness or output buffer is required.
   pragma Assertion_Policy (Post => Ignore);
   function Analyze (Input : Byte_Array) return Stream_Info
   with
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes,
     Post =>
       (if Input'Length >= Header_Byte_Count
          and then Books_Encodable
                     (Literal_Book_From_Header (Input),
                      Distance_Book_From_Header (Input))
          and then Header_Encodes
                     (Input,
                      Literal_Book_From_Header (Input),
                      Distance_Book_From_Header (Input))
        then
          Analyze'Result
          = Walk
              (Input,
               Header_Bit_Count,
               Literal_Book_From_Header (Input),
               Distance_Book_From_Header (Input),
               0))
       and then (if Analyze'Result.Valid
                 then
                   Input'Length >= Header_Byte_Count
                   and then Books_Encodable
                              (Literal_Book_From_Header (Input),
                               Distance_Book_From_Header (Input))
                   and then Header_Encodes
                              (Input,
                               Literal_Book_From_Header (Input),
                               Distance_Book_From_Header (Input))
                   and then Analyze'Result.End_Bit
                            in Header_Bit_Count + 1 .. 8 * Input'Length
                   and then Analyze'Result.Decoded_Length <= Max_Input);
   pragma Assertion_Policy (Post => Check);

   --  Decode the next payload token through the recovered canonical books.
   --  The supported local image needs no extra bits: literal/length symbols
   --  257 .. 264 denote lengths 3 .. 10 and distance symbols 0 .. 3 denote
   --  distances 1 .. 4.
   function Next_Symbol
     (Input           : Byte_Array;
      Position        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook) return Fixed.Symbol_Result
   with
     Pre  =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Position <= 8 * Input'Length
       and then Literal_Lengths.Kind = Codebooks.Canonical
       and then Distances.Kind = Codebooks.Canonical
       and then Codebooks.Ready (Literal_Lengths)
       and then Codebooks.Ready (Distances)
       and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
       and then Codebooks.Lengths_At_Most (Distances, 9),
     Post =>
       Next_Symbol'Result.Position in Position .. 8 * Input'Length
       and then (if not Decode_Symbol (Input, Position, Literal_Lengths).Valid
                 then
                   Next_Symbol'Result.Kind = Fixed.Truncated
                   and then Next_Symbol'Result.Value = 0
                   and then Next_Symbol'Result.Length = 0
                   and then Next_Symbol'Result.Distance = 0
                   and then Next_Symbol'Result.Position = Position
                 elsif Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                   <= 255
                 then
                   Next_Symbol'Result.Kind = Fixed.Literal
                   and then Next_Symbol'Result.Value
                            = Byte
                                (Decode_Symbol
                                   (Input, Position, Literal_Lengths)
                                   .Symbol)
                   and then Next_Symbol'Result.Length = 1
                   and then Next_Symbol'Result.Distance = 0
                   and then Next_Symbol'Result.Position
                            = Decode_Symbol (Input, Position, Literal_Lengths)
                                .Position
                 elsif Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                   = 256
                 then
                   Next_Symbol'Result.Kind = Fixed.End_Of_Block
                   and then Next_Symbol'Result.Value = 0
                   and then Next_Symbol'Result.Length = 0
                   and then Next_Symbol'Result.Distance = 0
                   and then Next_Symbol'Result.Position
                            = Decode_Symbol (Input, Position, Literal_Lengths)
                                .Position
                 elsif Decode_Symbol (Input, Position, Literal_Lengths).Symbol
                       in 257 .. 264
                 then
                   (if not Decode_Symbol
                             (Input,
                              Decode_Symbol (Input, Position, Literal_Lengths)
                                .Position,
                              Distances)
                             .Valid
                    then
                      Next_Symbol'Result.Kind = Fixed.Truncated
                      and then Next_Symbol'Result.Value = 0
                      and then Next_Symbol'Result.Length = 0
                      and then Next_Symbol'Result.Distance = 0
                      and then Next_Symbol'Result.Position
                               = Decode_Symbol
                                   (Input, Position, Literal_Lengths)
                                   .Position
                    elsif Decode_Symbol
                            (Input,
                             Decode_Symbol (Input, Position, Literal_Lengths)
                               .Position,
                             Distances)
                            .Symbol
                      <= 3
                    then
                      Next_Symbol'Result.Kind = Fixed.Match
                      and then Next_Symbol'Result.Value = 0
                      and then Next_Symbol'Result.Length
                               = Decode_Symbol
                                   (Input, Position, Literal_Lengths)
                                   .Symbol
                                 - 254
                      and then Next_Symbol'Result.Distance
                               = Decode_Symbol
                                   (Input,
                                    Decode_Symbol
                                      (Input, Position, Literal_Lengths)
                                      .Position,
                                    Distances)
                                   .Symbol
                                 + 1
                      and then Next_Symbol'Result.Position
                               = Decode_Symbol
                                   (Input,
                                    Decode_Symbol
                                      (Input, Position, Literal_Lengths)
                                      .Position,
                                    Distances)
                                   .Position
                    else
                      Next_Symbol'Result.Kind = Fixed.Other
                      and then Next_Symbol'Result.Value = 0
                      and then Next_Symbol'Result.Length = 0
                      and then Next_Symbol'Result.Distance = 0
                      and then Next_Symbol'Result.Position
                               = Decode_Symbol
                                   (Input,
                                    Decode_Symbol
                                      (Input, Position, Literal_Lengths)
                                      .Position,
                                    Distances)
                                   .Position)
                 else
                   Next_Symbol'Result.Kind = Fixed.Other
                   and then Next_Symbol'Result.Value = 0
                   and then Next_Symbol'Result.Length = 0
                   and then Next_Symbol'Result.Distance = 0
                   and then Next_Symbol'Result.Position
                            = Decode_Symbol (Input, Position, Literal_Lengths)
                                .Position);

   --  The payload bits through End_Bit decode to Data from Index onward.
   --  This relation admits any supported tokenization; unlike
   --  Payload.Is_Encoding, it does not require the compressor's deterministic
   --  token plan.
   function Spec_Matches
     (Input           : Byte_Array;
      End_Bit         : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Position        : Natural;
      Index           : Natural) return Boolean
   with
     Ghost,
     Pre                =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Data'Length <= Max_Input
       and then Position <= End_Bit
       and then End_Bit <= 8 * Input'Length
       and then Index <= Data'Length
       and then Literal_Lengths.Kind = Codebooks.Canonical
       and then Distances.Kind = Codebooks.Canonical
       and then Codebooks.Ready (Literal_Lengths)
       and then Codebooks.Ready (Distances)
       and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
       and then Codebooks.Lengths_At_Most (Distances, 9),
     Contract_Cases     =>
       (Next_Symbol (Input, Position, Literal_Lengths, Distances).Position
        > End_Bit                    => not Spec_Matches'Result,
        Next_Symbol (Input, Position, Literal_Lengths, Distances).Position
        <= End_Bit
        and then Index = Data'Length =>
          Spec_Matches'Result
          = (Next_Symbol (Input, Position, Literal_Lengths, Distances).Kind
             = Fixed.End_Of_Block
             and then Next_Symbol (Input, Position, Literal_Lengths, Distances)
                        .Position
                      = End_Bit),
        Next_Symbol (Input, Position, Literal_Lengths, Distances).Position
        <= End_Bit
        and then Index < Data'Length
        and then Next_Symbol (Input, Position, Literal_Lengths, Distances).Kind
                 = Fixed.Literal     =>
          Spec_Matches'Result
          = (Next_Symbol (Input, Position, Literal_Lengths, Distances).Value
             = Data (Data'First + Index)
             and then Spec_Matches
                        (Input,
                         End_Bit,
                         Literal_Lengths,
                         Distances,
                         Data,
                         Next_Symbol
                           (Input, Position, Literal_Lengths, Distances)
                           .Position,
                         Index + 1)),
        Next_Symbol (Input, Position, Literal_Lengths, Distances).Position
        <= End_Bit
        and then Index < Data'Length
        and then Next_Symbol (Input, Position, Literal_Lengths, Distances).Kind
                 = Fixed.Match       =>
          Spec_Matches'Result
          = (Fixed.Match_Applies
               (Data,
                Index,
                Next_Symbol (Input, Position, Literal_Lengths, Distances)
                  .Length,
                Next_Symbol (Input, Position, Literal_Lengths, Distances)
                  .Distance)
             and then Spec_Matches
                        (Input,
                         End_Bit,
                         Literal_Lengths,
                         Distances,
                         Data,
                         Next_Symbol
                           (Input, Position, Literal_Lengths, Distances)
                           .Position,
                         Index
                         + Next_Symbol
                             (Input, Position, Literal_Lengths, Distances)
                             .Length)),
        others                       => not Spec_Matches'Result),
     Subprogram_Variant =>
       (Decreases => Data'Length - Index, Decreases => End_Bit - Position);

   --  Linear executable check for literals, length-3 .. 10 matches at
   --  distance 1 .. 4, and an end-of-block ending exactly at End_Bit.
   --  Its proof-only postcondition connects it to Spec_Matches.
   pragma Assertion_Policy (Post => Ignore);
   function Encoding_Matches
     (Input           : Byte_Array;
      End_Bit         : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array) return Boolean
   with
     Pre  =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Data'Length <= Max_Input
       and then Header_Bit_Count <= End_Bit
       and then End_Bit <= 8 * Input'Length
       and then Books_Encodable (Literal_Lengths, Distances),
     Post =>
       Encoding_Matches'Result
       = Spec_Matches
           (Input,
            End_Bit,
            Literal_Lengths,
            Distances,
            Data,
            Header_Bit_Count,
            0);
   pragma Assertion_Policy (Post => Check);

   --  A supported self-describing dynamic body decodes to exactly Data.
   --  This is broader than Is_Encoding by design: analyzer acceptance is
   --  decode semantics, not a claim that the serializer chose those tokens.
   function Decodes
     (Input : Byte_Array; Produced : Natural; Data : Byte_Array) return Boolean
   is (Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count
       and then Data'Length <= Max_Input
       and then Books_Encodable
                  (Literal_Book_From_Header (Input),
                   Distance_Book_From_Header (Input))
       and then Header_Encodes
                  (Input,
                   Literal_Book_From_Header (Input),
                   Distance_Book_From_Header (Input))
       and then Analyze (Input).Valid
       and then Produced = (Analyze (Input).End_Bit + 7) / 8
       and then Analyze (Input).Decoded_Length = Data'Length
       and then Encoding_Matches
                  (Input,
                   Analyze (Input).End_Bit,
                   Literal_Book_From_Header (Input),
                   Distance_Book_From_Header (Input),
                   Data));

   --  A semantic dynamic body is accepted by the input-side analyzer with
   --  the same exact byte count and decoded length.  This is the one-way
   --  input-side consequence used by the common-boundary work.
   procedure Lemma_Encoding_Analyzes
     (Input : Byte_Array; Produced : Natural; Data : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre    => Is_Encoding (Input, Produced, Data),
     Post   =>
       Analyze (Input).Valid
       and then (Analyze (Input).End_Bit + 7) / 8 = Produced
       and then Analyze (Input).Decoded_Length = Data'Length;

   --  Every deterministic serializer image is also a member of the broader
   --  decoded-body relation used by executable recognition.
   procedure Lemma_Encoding_Decodes
     (Input : Byte_Array; Produced : Natural; Data : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre    => Is_Encoding (Input, Produced, Data),
     Post   => Decodes (Input, Produced, Data);

   --  Decode the supported self-describing dynamic fragment.  Analyzer
   --  acceptance is sufficient because Decodes records the actual token
   --  semantics rather than claiming the stream used the serializer plan.
   pragma Assertion_Policy (Post => Ignore);
   procedure Decompress
     (Input    : in Byte_Array;
      Output   : in out Byte_Array;
      Consumed : out Natural;
      Produced : out Natural;
      Success  : out Boolean)
   with
     Global => null,
     Pre    => Input'Length <= Fixed.Max_Stream_Bytes,
     Post   =>
       Consumed <= Input'Length
       and then Produced <= Output'Length
       and then Success
                = (Analyze (Input).Valid
                   and then Analyze (Input).Decoded_Length <= Output'Length)
       and then (if Success
                 then
                   Consumed = (Analyze (Input).End_Bit + 7) / 8
                   and then Produced = Analyze (Input).Decoded_Length
                   and then Decodes
                              (Input,
                               Consumed,
                               Output
                                 (Output'First
                                  .. Output'First - 1 + Produced)));
   pragma Assertion_Policy (Post => Check);

   procedure Lemma_Encoding_Uses_Header_Books
     (Input           : Byte_Array;
      Produced        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre    =>
       Input'Length <= Fixed.Max_Stream_Bytes
       and then Input'Length >= Header_Byte_Count
       and then Data'Length <= Max_Input
       and then Data'Length <= Fixed.Max_Input
       and then Books_Encodable (Literal_Lengths, Distances)
       and then Payload.Covers (Literal_Lengths, Distances, Data)
       and then Is_Encoding
                  (Input, Produced, Literal_Lengths, Distances, Data),
     Post   => Is_Encoding (Input, Produced, Data);

   --  Only the first Produced bytes participate in the self-describing
   --  dynamic relation.  In particular, appending a gzip trailer does not
   --  change the recovered codebooks or the encoded payload.
   procedure Lemma_Encoding_Frame
     (Before, After : Byte_Array; Produced : Natural; Data : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre    =>
       Before'Length <= Fixed.Max_Stream_Bytes
       and then After'Length <= Fixed.Max_Stream_Bytes
       and then Before'Length >= Header_Byte_Count
       and then After'Length >= Header_Byte_Count
       and then Produced in 1 .. Before'Length
       and then Produced <= After'Length
       and then Is_Encoding (Before, Produced, Data)
       and then (for all I in 0 .. Produced - 1 =>
                   After (After'First + I) = Before (Before'First + I)),
     Post   => Is_Encoding (After, Produced, Data);

   --  The broader decoded-body relation has the same container framing
   --  property: bytes after Produced do not participate in the block.
   procedure Lemma_Decoding_Frame
     (Before, After : Byte_Array; Produced : Natural; Data : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre    =>
       Before'First = After'First
       and then Before'Length <= Fixed.Max_Stream_Bytes
       and then After'Length <= Fixed.Max_Stream_Bytes
       and then Produced in 1 .. Before'Length
       and then Produced <= After'Length
       and then Decodes (Before, Produced, Data)
       and then (for all I in 0 .. Produced - 1 =>
                   After (After'First + I) = Before (Before'First + I)),
     Post   => Decodes (After, Produced, Data);

   --  A self-describing dynamic body determines one decoded byte sequence.
   --  The proof compares canonical codewords at each shared bit position and
   --  then uses the LZ77 window equation for matching back-references.
   procedure Lemma_Encoding_Functional
     (Input : Byte_Array; Produced : Natural; Left, Right : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Encoding (Input, Produced, Left)
       and then Is_Encoding (Input, Produced, Right),
     Post   =>
       Left'Length = Right'Length
       and then (for all I in 0 .. Left'Length - 1 =>
                   Left (Left'First + I) = Right (Right'First + I));

   --  A supported dynamic body has only one decoded byte sequence even when
   --  its tokenization is not the deterministic serializer plan.
   procedure Lemma_Decoding_Functional
     (Input : Byte_Array; Produced : Natural; Left, Right : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre    =>
       Decodes (Input, Produced, Left)
       and then Decodes (Input, Produced, Right),
     Post   =>
       Left'Length = Right'Length
       and then (for all I in 0 .. Left'Length - 1 =>
                   Left (Left'First + I) = Right (Right'First + I));

   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);
   procedure Serialize_Body
     (Data            : in Byte_Array;
      Literal_Lengths : in Codebooks.Codebook;
      Distances       : in Codebooks.Codebook;
      Output          : in out Byte_Array;
      Produced        : out Natural)
   with
     Global => null,
     Pre    =>
       Data'Length <= Max_Input
       and then Output'Length <= Fixed.Max_Stream_Bytes
       and then Output'Length >= Max_Size (Data'Length)
       and then Books_Encodable (Literal_Lengths, Distances)
       and then Payload.Covers (Literal_Lengths, Distances, Data),
     Post   =>
       Produced <= Max_Size (Data'Length)
       and then Is_Encoding
                  (Output, Produced, Literal_Lengths, Distances, Data);
   pragma Assertion_Policy (Pre => Check, Post => Check);

   --  Serialize the sparse dynamic body selected by Selects_Byte_Run.  The
   --  literal book is specialized to the repeated byte; the witness-free
   --  postcondition is the exact boundary consumed by gzip.
   pragma Assertion_Policy (Post => Ignore);
   procedure Compress_Byte_Run
     (Data     : in Byte_Array;
      Output   : in out Byte_Array;
      Produced : out Natural;
      Success  : out Boolean)
   with
     Global => null,
     Pre    =>
       Selects_Byte_Run (Data)
       and then Output'Length <= Fixed.Max_Stream_Bytes
       and then Output'Length >= Max_Size (Data'Length),
     Post   =>
       Produced <= Max_Size (Data'Length)
       and then (if Success
                 then Is_Encoding (Output, Produced, Data)
                 else Produced = 0);
   pragma Assertion_Policy (Post => Check);

end Inflate.Dynamic;
