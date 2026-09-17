--  Inflate.Bodies -- common semantic boundary for supported DEFLATE bodies.
--
--  The gzip layer should not need to know whether its DEFLATE payload was
--  emitted as stored blocks, as the bounded fixed-Huffman image, or as a
--  bounded dynamic-Huffman body.  This package collects those local relations
--  behind one predicate and exposes shared framing and functionality
--  consequences plus the recognition path used by the container proof.  The
--  top-level compressor can therefore select the dynamic image later without
--  widening the semantic relation again.

with Inflate.Model;
with Inflate.Fixed;
with Inflate.Dynamic;

package Inflate.Bodies with Pure, SPARK_Mode => On is

   pragma Assertion_Policy (Ghost => Ignore);

   --  The first Consumed bytes of Input are a supported DEFLATE body decoding
   --  to exactly Data.  Bytes after Consumed may contain a container trailer.
   --  The alternatives are deliberately local: producers and specialized
   --  decoders prove their own relations, while users above this package see
   --  only Body_Encodes.
   --  The common relation remains proof-only because the stored alternative
   --  is recursive; the input-side queries below remain executable.
   function Body_Encodes
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array) return Boolean
   is
     (Consumed in 1 .. Input'Length
      and then
        ((Input'Length >= 5
          and then Model.Encodes_Stored
            (Input, Input'First, Input'First + (Consumed - 1),
             Data,
             (if Data'Length > 0 then Data'First else 1),
             (if Data'Length > 0 then Data'Last else 0)))
         or else
         (Input'Length <= Fixed.Max_Stream_Bytes
          and then Data'Length <= Fixed.Max_Input
          and then Fixed.Is_Encoding (Input, Consumed, Data))
         or else
         Dynamic.Decodes (Input, Consumed, Data)))
   with Ghost;

   --  Input begins with one of the semantic bodies for which the shipping
   --  decoder exposes a completeness proof, and its decoded length fits in
   --  Out_Len.  Trailing bytes are ignored, which is what a container needs
   --  when its trailer follows the body.
   function Recognized
     (Input : Byte_Array; Out_Len : Natural) return Boolean
   is
     ((Input'Length >= 5
       and then Model.Stored_Stream_End
         (Input, Input'First, Input'Last) > 0
       and then Model.Stored_Decoded_Length
         (Input, Input'First, Input'Last) <= Out_Len)
      or else
      (Input'Length <= Fixed.Max_Stream_Bytes
       and then Fixed.Analyze (Input).Valid
       and then Fixed.Analyze (Input).Decoded_Length <= Out_Len)
      or else
      (Input'Length <= Fixed.Max_Stream_Bytes
       and then Dynamic.Analyze (Input).Valid
       and then Dynamic.Analyze (Input).Decoded_Length <= Out_Len));

   --  Exact byte count and decoded length selected by Recognized.  The stored,
   --  fixed, and dynamic block-type headers are pairwise disjoint, so the
   --  ordered choice is unambiguous.
   function Encoded_Size (Input : Byte_Array) return Natural is
     (if Input'Length >= 5
          and then Model.Stored_Stream_End
            (Input, Input'First, Input'Last) > 0
      then Model.Stored_Stream_End
             (Input, Input'First, Input'Last) - Input'First + 1
      elsif Input'Length <= Fixed.Max_Stream_Bytes
        and then Fixed.Analyze (Input).Valid
      then (Fixed.Analyze (Input).End_Bit + 7) / 8
      elsif Input'Length <= Fixed.Max_Stream_Bytes
        and then Dynamic.Analyze (Input).Valid
      then (Dynamic.Analyze (Input).End_Bit + 7) / 8
      else 0);

   function Decoded_Size (Input : Byte_Array) return Natural is
     (if Input'Length >= 5
          and then Model.Stored_Stream_End
            (Input, Input'First, Input'Last) > 0
      then Model.Stored_Decoded_Length
             (Input, Input'First, Input'Last)
      elsif Input'Length <= Fixed.Max_Stream_Bytes
        and then Fixed.Analyze (Input).Valid
      then Fixed.Analyze (Input).Decoded_Length
      elsif Input'Length <= Fixed.Max_Stream_Bytes
        and then Dynamic.Analyze (Input).Valid
      then Dynamic.Analyze (Input).Decoded_Length
      else 0);

   --  Introduction lemmas keep callers from unfolding the disjunction in a
   --  large decoder or container proof context.
   procedure Lemma_Stored_Encoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Consumed in 1 .. Input'Length
               and then Input'Length >= 5
               and then Model.Encodes_Stored
                 (Input, Input'First, Input'First + (Consumed - 1),
                  Data,
                  (if Data'Length > 0 then Data'First else 1),
                  (if Data'Length > 0 then Data'Last else 0)),
     Post => Body_Encodes (Input, Consumed, Data);

   --  Empty decoded ranges may carry different null bounds through slices.
   --  Normalize such a stored witness to the (1 .. 0) cursor used by
   --  Body_Encodes and transfer it to Data.
   procedure Lemma_Stored_Empty_Encoding
     (Input       : Byte_Array;
      Consumed    : Natural;
      Before_Data : Byte_Array;
      DF          : Positive;
      DL          : Natural;
      Data        : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Consumed in 1 .. Input'Length
               and then Input'Length >= 5
               and then Data'Length = 0
               and then DL = DF - 1
               and then Model.Encodes_Stored
                 (Input, Input'First, Input'First + (Consumed - 1),
                  Before_Data, DF, DL),
     Post => Body_Encodes (Input, Consumed, Data);

   procedure Lemma_Fixed_Encoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Fixed.Is_Encoding (Input, Consumed, Data),
     Post => Body_Encodes (Input, Consumed, Data);

   procedure Lemma_Dynamic_Encoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Dynamic.Is_Encoding (Input, Consumed, Data),
     Post => Body_Encodes (Input, Consumed, Data);

   procedure Lemma_Dynamic_Decoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Dynamic.Decodes (Input, Consumed, Data),
     Post => Body_Encodes (Input, Consumed, Data);

   --  A semantic body determines the input-side recognition facts needed by
   --  Inflate.Raw.Decompress.
   procedure Lemma_Encoding_Recognized
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Body_Encodes (Input, Consumed, Data),
     Post => Recognized (Input, Data'Length)
               and then Encoded_Size (Input) = Consumed
               and then Decoded_Size (Input) = Data'Length;

   --  Only the first Consumed bytes participate in the relation.
   procedure Lemma_Encoding_Frame
     (Before, After : Byte_Array;
      Consumed      : Natural;
      Data          : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Before'First = After'First
               and then Consumed in 1 .. Before'Length
               and then Consumed <= After'Length
               and then Body_Encodes (Before, Consumed, Data)
               and then
             (if Before'Length <= Fixed.Max_Stream_Bytes
                   and then Data'Length <= Fixed.Max_Input
                   and then Fixed.Is_Encoding (Before, Consumed, Data)
              then After'Length <= Fixed.Max_Stream_Bytes)
               and then
             (if Dynamic.Decodes (Before, Consumed, Data)
              then After'Length <= Fixed.Max_Stream_Bytes)
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Body_Encodes (After, Consumed, Data);

   --  One supported body has only one decoded byte sequence.
   procedure Lemma_Encoding_Functional
     (Input       : Byte_Array;
      Consumed    : Natural;
      Left, Right : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => Body_Encodes (Input, Consumed, Left)
               and then Body_Encodes (Input, Consumed, Right),
     Post => Left'Length = Right'Length
               and then
             (for all I in 0 .. Left'Length - 1 =>
                Left (Left'First + I) = Right (Right'First + I));

end Inflate.Bodies;
