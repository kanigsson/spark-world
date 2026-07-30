--  Inflate.Fixed -- the RFC 1951 fixed-Huffman compressor image.
--
--  The encoder emits one final fixed-Huffman block.  At every reached token
--  boundary its bounded M6 finder selects the longest match of length 3 .. 10
--  at distance 1 .. 4, with literals as the fallback.  The contracts below
--  state both halves of that image's round trip without making any
--  compression-optimality claim.

package Inflate.Fixed with Pure, SPARK_Mode => On is

   --  Proof helpers are deliberately absent from checks-enabled builds;
   --  all executable relations below have ordinary non-ghost bodies.
   pragma Assertion_Policy (Ghost => Ignore);

   --  Keep every bit offset representable by Natural, including the eight
   --  gzip trailer bytes that follow a fixed block in the slices passed to
   --  the recognizer.  This is the largest literal count supported by that
   --  arithmetic model; the public compressor retains its stored fallback
   --  above it, so its theorem still covers the full existing API domain.
   Max_Stream_Bytes : constant Natural := Natural'Last / 8;
   Max_Input : constant Natural :=
     (8 * (Max_Stream_Bytes - 8) - 10) / 9;

   subtype Code_Bit_Length is Positive range 8 .. 9;

   function Code_Length (B : Byte) return Code_Bit_Length is
     (if B <= 143 then 8 else 9);

   function Code (B : Byte) return Natural is
     (if B <= 143 then 48 + Natural (B) else 256 + Natural (B))
   with Post => Code'Result < 2 ** Code_Length (B);

   --  Maximum raw-DEFLATE bytes needed for N literals: three block-header
   --  bits, at most nine bits per literal, seven end-of-block bits, rounded
   --  up to a byte.
   function Max_Size (N : Natural) return Positive is
     (N + (N + 17) / 8)
   with Pre => N <= Max_Input;

   type Symbol_Kind is
     (Literal, Match, End_Of_Block, Other, Truncated);

   type Symbol_Result is record
      Kind     : Symbol_Kind;
      Value    : Byte;
      Length   : Natural;
      Distance : Natural;
      Position : Natural;
   end record;

   --  A selected match reproduces Length bytes of Data through the same
   --  window equation used by M4.  Stating that equation once keeps the
   --  compressor plan independent of the concrete patterns it recognizes.
   function Match_Applies
     (Data : Byte_Array;
      Position, Length, Distance : Natural) return Boolean
   is
     (Position <= Data'Length
      and then Length in 1 .. Data'Length - Position
      and then Distance in 1 .. Position
      and then
        (for all K in 0 .. Length - 1 =>
           Data (Data'First + Position + K) =
             Data (Data'First + Position + K - Distance)));

   --  Select the token beginning at a reached compression-plan boundary.
   --  The bounded finder chooses the longest match of length 3 .. 10 at
   --  distance 1 .. 4, preferring the smaller distance on equal lengths.
   --  These are exactly the fixed-code length and distance ranges that need
   --  no extra bits, so every selected match still occupies twelve bits.
   function Selected_Token
     (Data : Byte_Array; Position : Natural) return Symbol_Result
   with
     Pre  => Data'Length <= Max_Input and then Position < Data'Length,
     Post => Selected_Token'Result.Kind in Literal | Match
               and then Selected_Token'Result.Position in
                          Position + 1 .. Data'Length
               and then
             (if Selected_Token'Result.Kind = Literal
              then Selected_Token'Result.Value =
                     Data (Data'First + Position)
                   and then Selected_Token'Result.Length = 1
                   and then Selected_Token'Result.Distance = 0
                   and then Selected_Token'Result.Position = Position + 1
              else Selected_Token'Result.Length in 3 .. 10
                   and then Selected_Token'Result.Distance in 1 .. 4
                   and then Selected_Token'Result.Position =
                              Position + Selected_Token'Result.Length
                   and then Match_Applies
                     (Data, Position,
                      Selected_Token'Result.Length,
                      Selected_Token'Result.Distance));

   function Next_Position
     (Data : Byte_Array; Position : Natural) return Natural
   is (Selected_Token (Data, Position).Position)
   with
     Pre  => Data'Length <= Max_Input and then Position < Data'Length,
     Post => Next_Position'Result in Position + 1 .. Data'Length
               and then Next_Position'Result =
                          Position + Selected_Token (Data, Position).Length;

   function Token_Bit_Cost
     (Data : Byte_Array; Position : Natural) return Positive
   is
     (if Selected_Token (Data, Position).Kind = Match
      then 12
      else Code_Length (Selected_Token (Data, Position).Value))
   with
     Pre  => Data'Length <= Max_Input and then Position < Data'Length,
     Post => Token_Bit_Cost'Result <=
               9 * (Next_Position (Data, Position) - Position);

   --  Number of bytes after Count that remain in the token, if any, selected
   --  at the preceding boundary.  This single forward recurrence gives every
   --  byte position a deterministic plan state.
   function Plan_Remaining
     (Data : Byte_Array; Count : Natural) return Natural
   is
     (if Count = 0 then 0
      elsif Plan_Remaining (Data, Count - 1) = 0
      then Selected_Token (Data, Count - 1).Length - 1
      else Plan_Remaining (Data, Count - 1) - 1)
   with
     Ghost,
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length,
     Post => Plan_Remaining'Result <= 9
               and then Plan_Remaining'Result <= Data'Length - Count,
     Subprogram_Variant => (Decreases => Count);

   --  Count is reached by repeatedly advancing through the selected tokens.
   --  This replaces the old modulo-three continuation convention and makes
   --  variable token lengths explicit in every encoder invariant.
   function Token_Boundary
     (Data : Byte_Array; Count : Natural) return Boolean
   is (Plan_Remaining (Data, Count) = 0)
   with
     Ghost,
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length;

   --  Start of the token containing Count - 1.  At a nonzero boundary this
   --  is the preceding token's start; inside a token it is the current
   --  token's start.
   function Plan_Start
     (Data : Byte_Array; Count : Natural) return Natural
   is
     (if Count = 0 then 0
      elsif Token_Boundary (Data, Count - 1) then Count - 1
      else Plan_Start (Data, Count - 1))
   with
     Ghost,
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length,
     Post => Plan_Start'Result <= Count
               and then
             (if Count > 0
              then Plan_Start'Result < Count
                   and then Token_Boundary (Data, Plan_Start'Result)
                   and then Count <=
                     Next_Position (Data, Plan_Start'Result)
                   and then
                     (if Token_Boundary (Data, Count)
                      then Next_Position (Data, Plan_Start'Result) = Count)),
     Subprogram_Variant => (Decreases => Count);

   --  Number of bits occupied by the complete selected tokens ending no later
   --  than Count.  At a token boundary this is the exact payload bit count;
   --  inside a token it remains at the preceding boundary's value.
   function Data_Bits (Data : Byte_Array; Count : Natural) return Natural is
     (if Count = 0 then 0
      elsif Token_Boundary (Data, Count)
      then Data_Bits (Data, Plan_Start (Data, Count))
        + Token_Bit_Cost (Data, Plan_Start (Data, Count))
      else Data_Bits (Data, Count - 1))
   with
     Ghost,
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length,
     Post => Data_Bits'Result <= 9 * Count,
     Subprogram_Variant => (Decreases => Count);

   --  Advance one selected token in the deterministic compression plan.  This
   --  is exposed for the shared fixed/dynamic payload serializer; it contains
   --  no codebook-specific facts.
   procedure Lemma_Encoding_Next
     (Data : Byte_Array; Index : Natural)
   with
     Ghost,
     Pre  => Data'Length <= Max_Input
               and then Index < Data'Length
               and then Token_Boundary (Data, Index),
     Post => Token_Boundary (Data, Next_Position (Data, Index))
               and then Plan_Start
                 (Data, Next_Position (Data, Index)) = Index
               and then Data_Bits (Data, Next_Position (Data, Index)) =
                          Data_Bits (Data, Index)
                            + Token_Bit_Cost (Data, Index)
               and then
             (for all Count in Index + 1 ..
                Next_Position (Data, Index) - 1 =>
                  not Token_Boundary (Data, Count)
                    and then Data_Bits (Data, Count) =
                      Data_Bits (Data, Index));

   pragma Assertion_Policy (Post => Ignore);
   function Encoded_Bit_Count (Data : Byte_Array) return Natural
   with
     Pre  => Data'Length <= Max_Input,
     Post => Encoded_Bit_Count'Result = Data_Bits (Data, Data'Length)
               and then Encoded_Bit_Count'Result <= 9 * Data'Length;
   pragma Assertion_Policy (Post => Check);

   --  Exact raw-DEFLATE size for Data, including selected matches.
   pragma Assertion_Policy (Post => Ignore);
   function Encoded_Size (Data : Byte_Array) return Positive is
     ((Encoded_Bit_Count (Data) + 17) / 8)
   with
     Pre  => Data'Length <= Max_Input,
     Post => Encoded_Size'Result <= Max_Size (Data'Length)
               and then 3 + Data_Bits (Data, Data'Length) + 7 <=
                          8 * Encoded_Size'Result;
   pragma Assertion_Policy (Post => Check);

   --  Value of Length consecutive stream bits, interpreted in Huffman
   --  transmission order (first bit is the most significant code bit).
   --  The bit itself is Ore's bit-addressed accessor, in the numbering
   --  DEFLATE uses: bits run from the least significant end of each byte.
   --  This is the arithmetic view of it, because a stream bit is summed into
   --  a code value rather than tested. Naming it through Ore is what lets
   --  the bit-level lemmas of the bit layer apply to the stream.
   function Bit_Value
     (Input : Byte_Array; Position : Natural) return Natural is
     (Bit_Cursors.Bit_Value (Input, Position, Bit_Cursors.Lsb_First))
   with
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Position < 8 * Input'Length,
     Post => Bit_Value'Result <= 1;

   --  The Length stream bits from Start as the number they encode. This is
   --  Ore's field in the stream's numbering and the order a Huffman code is
   --  transmitted in, and the first clause of the postcondition says so; what
   --  the clauses after it add is the recurrence over the field width, which
   --  is the form every contract here is proved through, and the bound the
   --  contracts state their codes with.
   pragma Assertion_Policy (Post => Ignore);
   function Prefix_Value
     (Input : Byte_Array;
      Start : Natural;
      Length : Natural) return Natural
   with
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Length <= 12
               and then Start <= 8 * Input'Length
               and then Length <= 8 * Input'Length - Start,
     Post => Prefix_Value'Result =
               Bit_Cursors.Field_Value
                 (Input, Start, Length,
                  Bit_Cursors.Lsb_First, Bit_Cursors.High_Bit_First)
               and then Prefix_Value'Result < 2 ** Length
               and then
             (if Length = 0
              then Prefix_Value'Result = 0
              else Prefix_Value'Result =
                     2 * Prefix_Value (Input, Start, Length - 1)
                       + Bit_Value (Input, Start + Length - 1)),
     Subprogram_Variant => (Decreases => Length);
   pragma Assertion_Policy (Post => Check);

   function Fixed_Header (Input : Byte_Array) return Boolean is
     (Input'Length > 0
      and then Bit_Value (Input, 0) = 1
      and then Bit_Value (Input, 1) = 1
      and then Bit_Value (Input, 2) = 0)
   with Pre => Input'Length <= Max_Stream_Bytes;

   --  The selected literal or match token at every encoding position before
   --  Count occurs at its canonical bit offset in Input.
   function Encodes_Prefix
     (Input : Byte_Array; Data : Byte_Array; Count : Natural) return Boolean
   is
     (3 + Data_Bits (Data, Count) <= 8 * Input'Length
      and then
      (for all I in 0 .. Count - 1 =>
         (if Token_Boundary (Data, I)
               and then Selected_Token (Data, I).Kind = Match
          then 3 + Data_Bits (Data, I) + 12 <= 8 * Input'Length
               and then Prefix_Value
                 (Input, 3 + Data_Bits (Data, I), 7) =
                   Selected_Token (Data, I).Length - 2
               and then Prefix_Value
                 (Input, 3 + Data_Bits (Data, I) + 7, 5) =
                   Selected_Token (Data, I).Distance - 1
          elsif Token_Boundary (Data, I)
          then 3 + Data_Bits (Data, I)
                 + Code_Length (Data (Data'First + I)) <= 8 * Input'Length
               and then Prefix_Value
                 (Input, 3 + Data_Bits (Data, I),
                  Code_Length (Data (Data'First + I))) =
                    Code (Data (Data'First + I)))))
   with
     Ghost,
     Pre => Input'Length <= Max_Stream_Bytes
              and then Data'Length <= Max_Input
              and then Count <= Data'Length;

   --  Parse one symbol from the fixed block.  Match denotes one of the
   --  encoder's no-extra-bit length/distance pairs.
   pragma Assertion_Policy (Post => Ignore);
   function Next_Symbol
     (Input : Byte_Array; Position : Natural) return Symbol_Result
   with
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Position <= 8 * Input'Length,
     Post => Next_Symbol'Result.Position in Position .. 8 * Input'Length
               and then
             (if Next_Symbol'Result.Kind /= Truncated
              then Next_Symbol'Result.Position > Position)
               and then
             (if Next_Symbol'Result.Kind = Literal
              then Next_Symbol'Result.Length = 1
                   and then Next_Symbol'Result.Position =
                     Position + Code_Length (Next_Symbol'Result.Value)
                   and then Prefix_Value
                     (Input, Position,
                      Code_Length (Next_Symbol'Result.Value)) =
                     Code (Next_Symbol'Result.Value))
               and then
             (if Next_Symbol'Result.Kind = Match
              then Next_Symbol'Result.Length in 3 .. 10
                   and then Next_Symbol'Result.Distance in 1 .. 4
                   and then Next_Symbol'Result.Position = Position + 12
                   and then Prefix_Value (Input, Position, 7) =
                              Next_Symbol'Result.Length - 2
                   and then Prefix_Value (Input, Position + 7, 5) =
                              Next_Symbol'Result.Distance - 1)
               and then
             (if Next_Symbol'Result.Kind = End_Of_Block
              then Next_Symbol'Result.Length = 0
                   and then Next_Symbol'Result.Position = Position + 7
                   and then Prefix_Value (Input, Position, 7) = 0)
               and then
             (if 7 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 7) = 0
              then Next_Symbol'Result =
                     (End_Of_Block, 0, 0, 0, Position + 7))
               and then
             (if 12 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 7) in 1 .. 8
                   and then Prefix_Value (Input, Position + 7, 5) <= 3
              then Next_Symbol'Result =
                     (Match,
                      0,
                      Prefix_Value (Input, Position, 7) + 2,
                      Prefix_Value (Input, Position + 7, 5) + 1,
                      Position + 12))
               and then
             (if 8 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 8) in 48 .. 191
              then Next_Symbol'Result =
                     (Literal,
                      Byte (Prefix_Value (Input, Position, 8) - 48),
                      1,
                      0,
                      Position + 8))
               and then
             (if 9 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 9) in 400 .. 511
              then Next_Symbol'Result =
                     (Literal,
                      Byte (Prefix_Value (Input, Position, 9) - 256),
                      1,
                      0,
                      Position + 9));
   pragma Assertion_Policy (Post => Check);

   --  Recursive mathematical relation specified by the iterative executable
   --  checker below.  Index is the decoded cursor in Data.
   function Spec_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index : Natural) return Boolean
   with
     Ghost,
     Pre => Input'Length <= Max_Stream_Bytes
              and then Data'Length <= Max_Input
              and then Consumed in 1 .. Input'Length
              and then Position <= 8 * Consumed
              and then Index <= Data'Length,
     Contract_Cases =>
       (Next_Symbol (Input, Position).Position > 8 * Consumed =>
          not Spec_Matches'Result,
        Next_Symbol (Input, Position).Position <= 8 * Consumed
          and then Index = Data'Length =>
          Spec_Matches'Result =
            (Next_Symbol (Input, Position).Kind = End_Of_Block
             and then Consumed =
               (Next_Symbol (Input, Position).Position + 7) / 8),
        Next_Symbol (Input, Position).Position <= 8 * Consumed
          and then Index < Data'Length
          and then Next_Symbol (Input, Position).Kind = Literal =>
          Spec_Matches'Result =
            (Next_Symbol (Input, Position).Value =
               Data (Data'First + Index)
             and then Spec_Matches
               (Input, Consumed, Data,
                Next_Symbol (Input, Position).Position, Index + 1)),
        Next_Symbol (Input, Position).Position <= 8 * Consumed
          and then Index < Data'Length
          and then Next_Symbol (Input, Position).Kind = Match =>
          Spec_Matches'Result =
            (Match_Applies
               (Data, Index,
                Next_Symbol (Input, Position).Length,
                Next_Symbol (Input, Position).Distance)
             and then Spec_Matches
               (Input, Consumed, Data,
                Next_Symbol (Input, Position).Position,
                Index + Next_Symbol (Input, Position).Length)),
        others => not Spec_Matches'Result),
     Subprogram_Variant => (Decreases => Data'Length - Index,
                            Decreases => 8 * Consumed - Position);

   --  Linear executable check for literals, length-3 .. 10 matches at
   --  distance 1 .. 4, and end-of-block.  Its proof-only postcondition
   --  connects it to Spec_Matches.
   pragma Assertion_Policy (Post => Ignore);
   function Encoding_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array) return Boolean
   with
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Consumed in 1 .. Input'Length
               and then Fixed_Header (Input),
     Post => Encoding_Matches'Result =
               Spec_Matches (Input, Consumed, Data, 3, 0);
   pragma Assertion_Policy (Post => Check);

   --  Input's first Consumed bytes are a fixed block decoding exactly to
   --  Data.  Bytes after Consumed may be a container trailer.
   function Is_Encoding
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array) return Boolean
   is
     (Consumed in 1 .. Input'Length
      and then Input'Length <= Max_Stream_Bytes
      and then Data'Length <= Max_Input
      and then Fixed_Header (Input)
      and then Encoding_Matches (Input, Consumed, Data));

   type Stream_Info is record
      Valid          : Boolean;
      End_Bit        : Natural;
      Decoded_Length : Natural;
   end record;

   --  Recursive mathematical walk used to specify the iterative analyzer.
   --  Position names the next Huffman code bit (the three block-header bits
   --  have already been consumed).
   function Spec_Walk
     (Input : Byte_Array; Position, Decoded : Natural) return Stream_Info
   with
     Ghost,
     Pre => Input'Length <= Max_Stream_Bytes
              and then Position <= 8 * Input'Length
              and then Decoded <= Max_Input,
     Post => (if Spec_Walk'Result.Valid then
                Spec_Walk'Result.End_Bit in Position + 7 .. 8 * Input'Length
                and then Spec_Walk'Result.Decoded_Length <=
                           Max_Input - Decoded),
     Contract_Cases =>
       (Next_Symbol (Input, Position).Kind = Literal
          and then Decoded < Max_Input =>
          (if Spec_Walk
             (Input, Next_Symbol (Input, Position).Position, Decoded + 1).Valid
           then Spec_Walk'Result =
             (True,
              Spec_Walk
                (Input, Next_Symbol (Input, Position).Position, Decoded + 1)
                  .End_Bit,
              Spec_Walk
                (Input, Next_Symbol (Input, Position).Position, Decoded + 1)
                  .Decoded_Length + 1)
           else Spec_Walk'Result = (False, 0, 0)),
        Next_Symbol (Input, Position).Kind = Match
          and then Next_Symbol (Input, Position).Distance <= Decoded
          and then Next_Symbol (Input, Position).Length <=
                     Max_Input - Decoded =>
          (if Spec_Walk
             (Input, Next_Symbol (Input, Position).Position,
              Decoded + Next_Symbol (Input, Position).Length).Valid
           then Spec_Walk'Result =
             (True,
              Spec_Walk
                (Input, Next_Symbol (Input, Position).Position,
                 Decoded + Next_Symbol (Input, Position).Length)
                  .End_Bit,
              Spec_Walk
                (Input, Next_Symbol (Input, Position).Position,
                 Decoded + Next_Symbol (Input, Position).Length)
                  .Decoded_Length + Next_Symbol (Input, Position).Length)
           else Spec_Walk'Result = (False, 0, 0)),
        Next_Symbol (Input, Position).Kind = End_Of_Block =>
          Spec_Walk'Result =
            (True, Next_Symbol (Input, Position).Position, 0),
        others => Spec_Walk'Result = (False, 0, 0)),
     Subprogram_Variant => (Decreases => 8 * Input'Length - Position);

   pragma Assertion_Policy (Post => Ignore);
   function Walk
     (Input : Byte_Array; Position, Decoded : Natural) return Stream_Info
   with
     Pre => Input'Length <= Max_Stream_Bytes
              and then Position <= 8 * Input'Length
              and then Decoded <= Max_Input,
     Post => Walk'Result = Spec_Walk (Input, Position, Decoded);
   pragma Assertion_Policy (Post => Check);

   --  Recognize this fixed literal/match fragment.  End_Bit is
   --  immediately after the end-of-block code; the containing byte count is
   --  (End_Bit + 7) / 8.  Trailing bytes are ignored.
   pragma Assertion_Policy (Post => Ignore);
   function Analyze (Input : Byte_Array) return Stream_Info
   with
     Pre  => Input'Length <= Max_Stream_Bytes,
     Post => (if Fixed_Header (Input)
                   and then Walk (Input, 3, 0).Valid
              then Analyze'Result = Walk (Input, 3, 0))
               and then
             (if Analyze'Result.Valid then
                Fixed_Header (Input)
                and then Analyze'Result = Walk (Input, 3, 0)
                and then Analyze'Result.End_Bit in 10 .. 8 * Input'Length
                and then Analyze'Result.Decoded_Length <= Max_Input);
   pragma Assertion_Policy (Post => Check);

   procedure Lemma_Encoding_Analyzes
     (Input : Byte_Array; Consumed : Natural; Data : Byte_Array)
   with
     Ghost,
     Pre  => Is_Encoding (Input, Consumed, Data),
     Post => Analyze (Input).Valid
               and then (Analyze (Input).End_Bit + 7) / 8 = Consumed
               and then Analyze (Input).Decoded_Length = Data'Length;

   procedure Lemma_Encoding_Frame
     (Before, After : Byte_Array; Consumed : Natural; Data : Byte_Array)
   with
     Ghost,
     Pre  => Is_Encoding (Before, Consumed, Data)
               and then After'Length <= Max_Stream_Bytes
               and then Consumed <= After'Length
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Is_Encoding (After, Consumed, Data);

   procedure Lemma_Encoding_Functional
     (Input : Byte_Array; Consumed : Natural; Left, Right : Byte_Array)
   with
     Ghost,
     Pre  => Is_Encoding (Input, Consumed, Left)
               and then Is_Encoding (Input, Consumed, Right),
     Post => Left'Length = Right'Length
               and then
             (for all I in 0 .. Left'Length - 1 =>
                Left (Left'First + I) = Right (Right'First + I));

   --  Emit one final fixed-Huffman block containing literals and selected
   --  length-3 .. 10 matches at distance 1 .. 4.
   procedure Compress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural)
   with
     Global => null,
     Pre    => Input'Length <= Max_Input
               and then Output'Length >= Encoded_Size (Input)
               and then Output'Length <= Max_Stream_Bytes,
     Post   => Produced = Encoded_Size (Input)
               and then Is_Encoding
                          (Output, Produced, Input);

   --  Decode this fixed literal/match fragment when it is present.
   --  Success=False means only that this specialized fragment did not apply;
   --  callers may fall back to the general DEFLATE decoder.
   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Success  :    out Boolean)
   with
     Global => null,
     Pre    => Input'Length <= Max_Stream_Bytes,
     Post   => Consumed <= Input'Length
               and then Produced <= Output'Length
               and then Success =
                 (Analyze (Input).Valid
                  and then Analyze (Input).Decoded_Length <= Output'Length)
               and then
                 (if Analyze (Input).Valid
                       and then Analyze (Input).Decoded_Length <= Output'Length
                  then Success
                       and then Consumed =
                                  (Analyze (Input).End_Bit + 7) / 8
                       and then Produced = Analyze (Input).Decoded_Length
                       and then Is_Encoding
                                  (Input, Consumed,
                                   Output
                                     (Output'First ..
                                      Output'First - 1 + Produced)));

end Inflate.Fixed;
