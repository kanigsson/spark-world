--  Inflate.Payload -- shared Huffman token-payload serialization.
--
--  The verified token plan currently lives in Inflate.Fixed; this package
--  deliberately depends only on that plan and on the codebook interface, not
--  on a block header.  Fixed and dynamic blocks therefore share the literal,
--  length/distance, and end-of-block writer while retaining separate codebook
--  construction and header proofs.

with Inflate.Codebooks;
with Inflate.Fixed;

package Inflate.Payload with Pure, SPARK_Mode => On is

   use type Fixed.Symbol_Kind;

   pragma Assertion_Policy (Ghost => Ignore);

   function Length_Symbol (Length : Natural) return Codebooks.Symbol_Index is
     (Codebooks.Symbol_Index (Length + 254))
   with Pre => Length in 3 .. 10;

   function Distance_Symbol
     (Distance : Natural) return Codebooks.Symbol_Index is
     (Codebooks.Symbol_Index (Distance - 1))
   with Pre => Distance in 1 .. 4;

   --  Every symbol selected by the shared token plan, plus end-of-block, has
   --  an assigned code in the supplied books.
   function Covers
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array) return Boolean
   is
     (Codebooks.Length_Of (Literal_Lengths, 256) > 0
      and then
        (for all I in 0 .. Data'Length - 1 =>
           (if Fixed.Token_Boundary (Data, I)
            then
              (if Fixed.Selected_Token (Data, I).Kind = Fixed.Match
               then Codebooks.Length_Of
                      (Literal_Lengths,
                       Length_Symbol (Fixed.Selected_Token (Data, I).Length)) > 0
                    and then Codebooks.Length_Of
                      (Distances,
                       Distance_Symbol
                         (Fixed.Selected_Token (Data, I).Distance)) > 0
               else Codebooks.Length_Of
                      (Literal_Lengths,
                       Natural (Data (Data'First + I))) > 0))))
   with
     Ghost,
     Pre => Data'Length <= Fixed.Max_Input;

   function Token_Bit_Cost
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Position        : Natural) return Positive
   is
     (if Fixed.Selected_Token (Data, Position).Kind = Fixed.Match
      then Codebooks.Length_Of
             (Literal_Lengths,
              Length_Symbol (Fixed.Selected_Token (Data, Position).Length))
        + Codebooks.Length_Of
             (Distances,
              Distance_Symbol
                (Fixed.Selected_Token (Data, Position).Distance))
      else Codebooks.Length_Of
             (Literal_Lengths,
              Natural (Data (Data'First + Position))))
   with
     Ghost,
     Pre  => Data'Length <= Fixed.Max_Input
               and then Position < Data'Length
               and then Fixed.Token_Boundary (Data, Position)
               and then Covers (Literal_Lengths, Distances, Data)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9),
     Post => Token_Bit_Cost'Result <=
               9 * (Fixed.Next_Position (Data, Position) - Position);

   function Data_Bits
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Count           : Natural) return Natural
   is
     (if Count = 0 then 0
      elsif Fixed.Token_Boundary (Data, Count)
      then Data_Bits
             (Literal_Lengths, Distances, Data,
              Fixed.Plan_Start (Data, Count))
        + Token_Bit_Cost
             (Literal_Lengths, Distances, Data,
              Fixed.Plan_Start (Data, Count))
      else Data_Bits (Literal_Lengths, Distances, Data, Count - 1))
   with
     Ghost,
     Pre  => Data'Length <= Fixed.Max_Input
               and then Count <= Data'Length
               and then Covers (Literal_Lengths, Distances, Data)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9),
     Post => Data_Bits'Result <= 9 * Count,
     Subprogram_Variant => (Decreases => Count);

   --  An interval at Start + Offset lies within Output.  Keeping the
   --  arithmetic in subtraction form gives callers the facts needed to form
   --  bit positions without overflowing Natural.
   function Fits_At
     (Output : Byte_Array;
      Start, Offset, Length : Natural) return Boolean
   is
     (Start <= 8 * Output'Length
      and then Offset <= 8 * Output'Length - Start
      and then Length <= 8 * Output'Length - Start - Offset)
   with
     Ghost,
     Pre => Output'Length <= Fixed.Max_Stream_Bytes;

   function Token_Encoded
     (Output          : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Position        : Natural) return Boolean
   is
     (if Fixed.Selected_Token (Data, Position).Kind = Fixed.Match
      then Fits_At
             (Output, Start,
              Data_Bits (Literal_Lengths, Distances, Data, Position),
              Codebooks.Length_Of
                (Literal_Lengths,
                 Length_Symbol
                   (Fixed.Selected_Token (Data, Position).Length))
                + Codebooks.Length_Of
                    (Distances,
                     Distance_Symbol
                       (Fixed.Selected_Token (Data, Position).Distance)))
           and then Fixed.Prefix_Value
             (Output,
              Start + Data_Bits
                (Literal_Lengths, Distances, Data, Position),
              Codebooks.Length_Of
                (Literal_Lengths,
                 Length_Symbol
                   (Fixed.Selected_Token (Data, Position).Length))) =
             Codebooks.Code_Of
               (Literal_Lengths,
                Length_Symbol
                  (Fixed.Selected_Token (Data, Position).Length))
           and then Fixed.Prefix_Value
             (Output,
              Start + Data_Bits
                (Literal_Lengths, Distances, Data, Position)
                + Codebooks.Length_Of
                    (Literal_Lengths,
                     Length_Symbol
                       (Fixed.Selected_Token (Data, Position).Length)),
              Codebooks.Length_Of
                (Distances,
                 Distance_Symbol
                   (Fixed.Selected_Token (Data, Position).Distance))) =
             Codebooks.Code_Of
               (Distances,
                Distance_Symbol
                  (Fixed.Selected_Token (Data, Position).Distance))
      else Fits_At
             (Output, Start,
              Data_Bits (Literal_Lengths, Distances, Data, Position),
              Codebooks.Length_Of
                (Literal_Lengths,
                 Natural (Data (Data'First + Position))))
           and then Fixed.Prefix_Value
             (Output,
              Start + Data_Bits
                (Literal_Lengths, Distances, Data, Position),
              Codebooks.Length_Of
                (Literal_Lengths,
                 Natural (Data (Data'First + Position)))) =
             Codebooks.Code_Of
               (Literal_Lengths,
                Natural (Data (Data'First + Position))))
   with
     Ghost,
     Pre => Output'Length <= Fixed.Max_Stream_Bytes
              and then Data'Length <= Fixed.Max_Input
              and then Position < Data'Length
              and then Fixed.Token_Boundary (Data, Position)
              and then Covers (Literal_Lengths, Distances, Data)
              and then Codebooks.Ready (Literal_Lengths)
              and then Codebooks.Ready (Distances)
              and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
              and then Codebooks.Lengths_At_Most (Distances, 9);

   function Encodes_Prefix
     (Output          : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Count           : Natural) return Boolean
   is
     (Fits_At
        (Output, Start,
         Data_Bits (Literal_Lengths, Distances, Data, Count), 0)
      and then
        (for all I in 0 .. Count - 1 =>
           (if Fixed.Token_Boundary (Data, I)
            then Token_Encoded
              (Output, Start, Literal_Lengths, Distances, Data, I))))
   with
     Ghost,
     Pre => Output'Length <= Fixed.Max_Stream_Bytes
              and then Data'Length <= Fixed.Max_Input
              and then Count <= Data'Length
              and then Covers (Literal_Lengths, Distances, Data)
              and then Codebooks.Ready (Literal_Lengths)
              and then Codebooks.Ready (Distances)
              and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
              and then Codebooks.Lengths_At_Most (Distances, 9);

   function Is_Encoding
     (Output          : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array) return Boolean
   is
     (Encodes_Prefix
        (Output, Start, Literal_Lengths, Distances, Data, Data'Length)
      and then Fits_At
        (Output, Start,
         Data_Bits (Literal_Lengths, Distances, Data, Data'Length),
         Codebooks.Length_Of (Literal_Lengths, 256))
      and then Fixed.Prefix_Value
        (Output,
         Start + Data_Bits
           (Literal_Lengths, Distances, Data, Data'Length),
         Codebooks.Length_Of (Literal_Lengths, 256)) =
           Codebooks.Code_Of (Literal_Lengths, 256))
   with
     Ghost,
     Pre => Output'Length <= Fixed.Max_Stream_Bytes
              and then Data'Length <= Fixed.Max_Input
              and then Covers (Literal_Lengths, Distances, Data)
              and then Codebooks.Ready (Literal_Lengths)
              and then Codebooks.Ready (Distances)
              and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
              and then Codebooks.Lengths_At_Most (Distances, 9);

   --  Append the token payload and end-of-block code at Start.  Bits outside
   --  the returned half-open interval are preserved.
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);
   procedure Serialize
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
                 and then Covers (Literal_Lengths, Distances, Data)
                 and then Start <= 8 * Output'Length
                 and then Data_Bits
                   (Literal_Lengths, Distances, Data, Data'Length)
                   + Codebooks.Length_Of (Literal_Lengths, 256) <=
                     8 * Output'Length - Start,
     Post   => Next_Bit = Start + Data_Bits
                 (Literal_Lengths, Distances, Data, Data'Length)
                   + Codebooks.Length_Of (Literal_Lengths, 256)
                 and then Is_Encoding
                   (Output, Start, Literal_Lengths, Distances, Data)
                 and then
               (for all Position in 0 .. 8 * Output'Length - 1 =>
                  (if Position < Start or else Position >= Next_Bit
                   then Fixed.Bit_Value (Output, Position) =
                          Fixed.Bit_Value (Output'Old, Position)));
   pragma Assertion_Policy (Pre => Check, Post => Check);

end Inflate.Payload;
