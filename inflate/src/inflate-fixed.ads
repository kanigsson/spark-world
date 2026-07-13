--  Inflate.Fixed -- the RFC 1951 fixed-Huffman literal fragment.
--
--  This package is the first M6 encoder: one final fixed-Huffman block,
--  containing literal symbols followed by end-of-block.  It deliberately
--  emits no length/distance pairs yet.  The format is nevertheless ordinary
--  DEFLATE, and the contracts below state both halves of its round trip.

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

   function Code_Length (B : Byte) return Positive is
     (if B <= 143 then 8 else 9);

   function Code (B : Byte) return Natural is
     (if B <= 143 then 48 + Natural (B) else 256 + Natural (B));

   --  Maximum raw-DEFLATE bytes needed for N literals: three block-header
   --  bits, at most nine bits per literal, seven end-of-block bits, rounded
   --  up to a byte.
   function Max_Size (N : Natural) return Positive is
     (N + (N + 17) / 8)
   with Pre => N <= Max_Input;

   --  Number of bits occupied by the first Count bytes of Data.
   function Data_Bits (Data : Byte_Array; Count : Natural) return Natural is
     (if Count = 0 then 0
      else Data_Bits (Data, Count - 1)
             + Code_Length (Data (Data'First + Count - 1)))
   with
     Ghost,
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length,
     Post => Data_Bits'Result in 8 * Count .. 9 * Count,
     Subprogram_Variant => (Decreases => Count);

   pragma Assertion_Policy (Post => Ignore);
   function Long_Literal_Count
     (Data : Byte_Array; Count : Natural) return Natural
   with
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length,
     Post => Long_Literal_Count'Result <= Count
               and then Data_Bits (Data, Count) =
                          8 * Count + Long_Literal_Count'Result;
   pragma Assertion_Policy (Post => Check);

   --  Exact raw-DEFLATE size for Data.  Unlike Max_Size, this accounts for
   --  the fixed code's eight-bit literals 0 .. 143.
   pragma Assertion_Policy (Post => Ignore);
   function Encoded_Size (Data : Byte_Array) return Positive is
     (Data'Length + (Long_Literal_Count (Data, Data'Length) + 17) / 8)
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
               and then Length <= 9
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

   --  The first Count symbols of Data occur as fixed-Huffman literals at
   --  their canonical bit offsets in Input.
   function Encodes_Prefix
     (Input : Byte_Array; Data : Byte_Array; Count : Natural) return Boolean
   is
     (3 + Data_Bits (Data, Count) <= 8 * Input'Length
      and then
      (for all I in 0 .. Count - 1 =>
         3 + Data_Bits (Data, I)
           + Code_Length (Data (Data'First + I)) <= 8 * Input'Length
         and then Prefix_Value
           (Input, 3 + Data_Bits (Data, I),
            Code_Length (Data (Data'First + I))) =
              Code (Data (Data'First + I))))
   with
     Ghost,
     Pre => Input'Length <= Max_Stream_Bytes
              and then Data'Length <= Max_Input
              and then Count <= Data'Length;

   --  Linear executable check for the literal sequence and end-of-block.
   --  The postcondition connects that implementation to the pointwise
   --  relation used by the proof.  Keep that deliberately quantified
   --  bridge out of checks-enabled executables; the body itself remains the
   --  linear executable relation.
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
       (3 + Data_Bits (Data, Data'Length) + 7 <= 8 * Input'Length
        and then Encodes_Prefix (Input, Data, Data'Length)
        and then Prefix_Value
          (Input, 3 + Data_Bits (Data, Data'Length), 7) = 0
        and then Consumed =
          (3 + Data_Bits (Data, Data'Length) + 7 + 7) / 8);
   pragma Assertion_Policy (Post => Check);

   --  Input's first Consumed bytes are exactly the literal-only fixed block
   --  for Data.  Bytes after Consumed may be a container trailer.
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

   type Symbol_Kind is (Literal, End_Of_Block, Other, Truncated);

   type Symbol_Result is record
      Kind     : Symbol_Kind;
      Value    : Byte;
      Position : Natural;
   end record;

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
              then Next_Symbol'Result.Position =
                     Position + Code_Length (Next_Symbol'Result.Value)
                   and then Prefix_Value
                     (Input, Position,
                      Code_Length (Next_Symbol'Result.Value)) =
                     Code (Next_Symbol'Result.Value))
               and then
             (if Next_Symbol'Result.Kind = End_Of_Block
              then Next_Symbol'Result.Position = Position + 7
                   and then Prefix_Value (Input, Position, 7) = 0)
               and then
             (if 7 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 7) = 0
              then Next_Symbol'Result.Kind = End_Of_Block)
               and then
             (if 8 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 8) in 48 .. 191
              then Next_Symbol'Result =
                     (Literal,
                      Byte (Prefix_Value (Input, Position, 8) - 48),
                      Position + 8))
               and then
             (if 9 <= 8 * Input'Length - Position
                   and then Prefix_Value (Input, Position, 9) in 400 .. 511
              then Next_Symbol'Result =
                     (Literal,
                      Byte (Prefix_Value (Input, Position, 9) - 256),
                      Position + 9));
   pragma Assertion_Policy (Post => Check);

   --  Recursive mathematical walk used to specify the iterative analyzer.
   --  Position names the next Huffman code bit (the three block-header bits
   --  have already been consumed).
   function Spec_Walk (Input : Byte_Array; Position : Natural) return Stream_Info
   with
     Ghost,
     Pre => Input'Length <= Max_Stream_Bytes
              and then Position <= 8 * Input'Length,
     Post => (if Spec_Walk'Result.Valid then
                Spec_Walk'Result.End_Bit in Position + 7 .. 8 * Input'Length
                and then Spec_Walk'Result.Decoded_Length <=
                           (8 * Input'Length - Position) / 8
                and then
                  (if Next_Symbol (Input, Position).Kind = Literal
                   then Spec_Walk (Input,
                              Next_Symbol (Input, Position).Position).Valid
                        and then Spec_Walk'Result.End_Bit =
                          Spec_Walk (Input,
                                Next_Symbol (Input, Position).Position).End_Bit
                        and then Spec_Walk'Result.Decoded_Length =
                          Spec_Walk
                            (Input,
                             Next_Symbol (Input, Position).Position)
                              .Decoded_Length + 1
                   else Next_Symbol (Input, Position).Kind = End_Of_Block
                        and then Spec_Walk'Result.End_Bit =
                                   Next_Symbol (Input, Position).Position
                        and then Spec_Walk'Result.Decoded_Length = 0)),
     Contract_Cases =>
       (Next_Symbol (Input, Position).Kind = Literal =>
          (if Spec_Walk
             (Input, Next_Symbol (Input, Position).Position).Valid
           then Spec_Walk'Result =
             (True,
              Spec_Walk
                (Input, Next_Symbol (Input, Position).Position).End_Bit,
              Spec_Walk
                (Input, Next_Symbol (Input, Position).Position)
                  .Decoded_Length + 1)
           else Spec_Walk'Result = (False, 0, 0)),
        Next_Symbol (Input, Position).Kind = End_Of_Block =>
          Spec_Walk'Result =
            (True, Next_Symbol (Input, Position).Position, 0),
        others => Spec_Walk'Result = (False, 0, 0)),
     Subprogram_Variant => (Decreases => 8 * Input'Length - Position);

   pragma Assertion_Policy (Post => Ignore);
   function Walk (Input : Byte_Array; Position : Natural) return Stream_Info
   with
     Pre => Input'Length <= Max_Stream_Bytes
              and then Position <= 8 * Input'Length,
     Post => Walk'Result = Spec_Walk (Input, Position);
   pragma Assertion_Policy (Post => Check);

   --  Recognize the literal-only fixed fragment.  End_Bit is
   --  immediately after the end-of-block code; the containing byte count is
   --  (End_Bit + 7) / 8.  Trailing bytes are ignored.
   pragma Assertion_Policy (Post => Ignore);
   function Analyze (Input : Byte_Array) return Stream_Info
   with
     Pre  => Input'Length <= Max_Stream_Bytes,
     Post => (if Fixed_Header (Input)
                   and then Walk (Input, 3).Valid
                   and then Walk (Input, 3).Decoded_Length <= Max_Input
              then Analyze'Result = Walk (Input, 3))
               and then
             (if Analyze'Result.Valid then
                Fixed_Header (Input)
                and then Analyze'Result = Walk (Input, 3)
                and then Analyze'Result.End_Bit in 10 .. 8 * Input'Length
                and then Analyze'Result.Decoded_Length <= Max_Input);
   pragma Assertion_Policy (Post => Check);

   procedure Lemma_Encoding_Analyzes
     (Input : Byte_Array; Consumed : Natural; Data : Byte_Array)
   with
     Ghost,
     Pre  => Is_Encoding (Input, Consumed, Data),
     Post => Analyze (Input).Valid
               and then Analyze (Input).End_Bit =
                          3 + Data_Bits (Data, Data'Length) + 7
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

   --  Emit one final fixed-Huffman block containing only literals.
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

   --  Decode the fixed-literal fragment when it is present.  Success=False
   --  means only that this specialized fragment did not apply; callers may
   --  fall back to the general DEFLATE decoder.
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
