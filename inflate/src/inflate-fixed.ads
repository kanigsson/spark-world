--  Inflate.Fixed -- the RFC 1951 fixed-Huffman compressor image.
--
--  The encoder emits one final fixed-Huffman block.  Most bytes are literals;
--  aligned three-byte groups may be represented by deliberately simple M6
--  matches of length 3 and distance 1 or 3.  The contracts below state both
--  halves of that image's round trip without making any
--  compression-optimality claim.

with Interfaces;

package Inflate.Fixed with Pure, SPARK_Mode => On is

   use type Byte;

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

   --  The intentionally small match finder considers aligned groups of
   --  three bytes.  It first recognizes a distance-1 run, including M4's
   --  overlapping-copy case, and otherwise recognizes repetition of the
   --  preceding three-byte group at distance 3.  Zero means use a literal.
   function Match_Distance
     (Data : Byte_Array; Position : Natural) return Natural
   is
     (if Position = 0
          or else Position >= Data'Length
          or else Position mod 3 /= 0
          or else Data'Length - Position < 3
      then 0
      elsif Data (Data'First + Position) =
              Data (Data'First + Position - 1)
        and then Data (Data'First + Position + 1) =
              Data (Data'First + Position - 1)
        and then Data (Data'First + Position + 2) =
              Data (Data'First + Position - 1)
      then 1
      elsif Position >= 3
        and then Data (Data'First + Position) =
              Data (Data'First + Position - 3)
        and then Data (Data'First + Position + 1) =
              Data (Data'First + Position - 2)
        and then Data (Data'First + Position + 2) =
              Data (Data'First + Position - 1)
      then 3
      else 0)
   with
     Post => Match_Distance'Result in 0 | 1 | 3
               and then
             (if Match_Distance'Result > 0
              then Match_Applies
                     (Data, Position, 3, Match_Distance'Result));

   function Match_Start
     (Data : Byte_Array; Position : Natural) return Boolean
   is
     (Match_Distance (Data, Position) > 0);

   function Match_Continuation
     (Data : Byte_Array; Position : Natural) return Boolean
   is
     (Position < Data'Length
      and then Position mod 3 /= 0
      and then Match_Start (Data, Position - Position mod 3));

   --  Number of bits occupied by the encoding of the first Count bytes.
   --  Inside a selected match group, intermediate Count values retain the
   --  group's starting offset; at the group boundary all twelve match bits
   --  are charged at once.  Encoder and proof cursors only use boundaries.
   function Data_Bits (Data : Byte_Array; Count : Natural) return Natural is
     (if Count = 0 then 0
      elsif Count mod 3 /= 0
        and then Match_Start (Data, Count - Count mod 3)
      then Data_Bits (Data, Count - Count mod 3)
      elsif Count >= 3 and then Match_Start (Data, Count - 3)
      then Data_Bits (Data, Count - 3) + 12
      else Data_Bits (Data, Count - 1)
             + Code_Length (Data (Data'First + Count - 1)))
   with
     Ghost,
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length,
     Post => Data_Bits'Result <= 9 * Count,
     Subprogram_Variant => (Decreases => Count);

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
   function Bit_Value
     (Input : Byte_Array; Position : Natural) return Natural is
     (Natural
        (Interfaces.Shift_Right
           (Input (Input'First + Position / 8), Position mod 8) and 1))
   with
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Position < 8 * Input'Length,
     Post => Bit_Value'Result <= 1;

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
     Post => Prefix_Value'Result < 2 ** Length
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
         (if Match_Start (Data, I)
          then 3 + Data_Bits (Data, I) + 12 <= 8 * Input'Length
               and then Prefix_Value
                 (Input, 3 + Data_Bits (Data, I), 7) = 1
               and then Prefix_Value
                 (Input, 3 + Data_Bits (Data, I) + 7, 5) =
                   Match_Distance (Data, I) - 1
          elsif not Match_Continuation (Data, I)
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

   type Symbol_Kind is
     (Literal, Match, End_Of_Block, Other, Truncated);

   type Symbol_Result is record
      Kind     : Symbol_Kind;
      Value    : Byte;
      Length   : Natural;
      Distance : Natural;
      Position : Natural;
   end record;

   --  Parse one symbol from the fixed block.  Match denotes one of the
   --  encoder's length-3 pairs, at distance 1 or 3.
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
              then Next_Symbol'Result.Length = 3
                   and then Next_Symbol'Result.Distance in 1 | 3
                   and then Next_Symbol'Result.Position = Position + 12
                   and then Prefix_Value (Input, Position, 7) = 1
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
                   and then Prefix_Value (Input, Position, 7) = 1
                   and then Prefix_Value (Input, Position + 7, 5) = 0
              then Next_Symbol'Result = (Match, 0, 3, 1, Position + 12))
               and then
             (if 12 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 7) = 1
                   and then Prefix_Value (Input, Position + 7, 5) = 2
              then Next_Symbol'Result = (Match, 0, 3, 3, Position + 12))
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

   --  Linear executable check for literals, length-3 matches at distance 1 or
   --  3, and end-of-block.  Its proof-only postcondition connects it to
   --  Spec_Matches.
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
   --  length-3 matches at distance 1 or 3.
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
