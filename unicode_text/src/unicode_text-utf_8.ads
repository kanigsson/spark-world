pragma Ada_2022;

with SPARK.Big_Integers;  use SPARK.Big_Integers;
with Unicode_Text.Models; use Unicode_Text.Models;

package Unicode_Text.UTF_8
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;

   subtype Octet is Natural range 0 .. 255;

   type Encoded_Width is range 1 .. 4;

   type Decoded_Unit is record
      Value : Scalar_Value;
      Width : Encoded_Width;
   end record;

   type Validation_Result is record
      Valid        : Boolean;
      Error_Offset : Natural;
   end record;
   --  Error_Offset is zero based.  On success it is S'Length; on failure it
   --  identifies the first byte that cannot begin a valid scalar encoding.

   function To_Octet (Value : Character) return Octet
   is (Character'Pos (Value));

   function Octet_At (S : String; Byte_Offset : Natural) return Octet
   is (To_Octet (S (S'First + Byte_Offset)))
   with Pre => Byte_Offset < S'Length;

   function Encoding_Width (Value : Scalar_Value) return Encoded_Width
   is (if Value <= 16#007F#
       then 1
       elsif Value <= 16#07FF#
       then 2
       elsif Value <= 16#FFFF#
       then 3
       else 4);

   function Encode_One (Value : Scalar_Value) return String
   with
     Post =>
       Encode_One'Result'First = 1
       and then Encode_One'Result'Length = Encoding_Width (Value)
       and then
         (case Encoding_Width (Value) is
            when 1 => Octet_At (Encode_One'Result, 0) = Natural (Value),
            when 2 =>
              Octet_At (Encode_One'Result, 0) = 16#C0# + Natural (Value) / 64
              and then
                Octet_At (Encode_One'Result, 1)
                = 16#80# + Natural (Value) mod 64,
            when 3 =>
              Octet_At (Encode_One'Result, 0)
              = 16#E0# + Natural (Value) / 4_096
              and then
                Octet_At (Encode_One'Result, 1)
                = 16#80# + (Natural (Value) / 64) mod 64
              and then
                Octet_At (Encode_One'Result, 2)
                = 16#80# + Natural (Value) mod 64,
            when 4 =>
              Octet_At (Encode_One'Result, 0)
              = 16#F0# + Natural (Value) / 262_144
              and then
                Octet_At (Encode_One'Result, 1)
                = 16#80# + (Natural (Value) / 4_096) mod 64
              and then
                Octet_At (Encode_One'Result, 2)
                = 16#80# + (Natural (Value) / 64) mod 64
              and then
                Octet_At (Encode_One'Result, 3)
                = 16#80# + Natural (Value) mod 64);

   function Sequence_Width_At
     (S : String; Byte_Offset : Natural) return Natural
   is (if Octet_At (S, Byte_Offset) <= 16#7F#
       then 1
       elsif Octet_At (S, Byte_Offset) in 16#C2# .. 16#DF#
         and then S'Length - Byte_Offset >= 2
         and then Octet_At (S, Byte_Offset + 1) in 16#80# .. 16#BF#
       then 2
       elsif Octet_At (S, Byte_Offset) = 16#E0#
         and then S'Length - Byte_Offset >= 3
         and then Octet_At (S, Byte_Offset + 1) in 16#A0# .. 16#BF#
         and then Octet_At (S, Byte_Offset + 2) in 16#80# .. 16#BF#
       then 3
       elsif Octet_At (S, Byte_Offset) in 16#E1# .. 16#EC# | 16#EE# .. 16#EF#
         and then S'Length - Byte_Offset >= 3
         and then Octet_At (S, Byte_Offset + 1) in 16#80# .. 16#BF#
         and then Octet_At (S, Byte_Offset + 2) in 16#80# .. 16#BF#
       then 3
       elsif Octet_At (S, Byte_Offset) = 16#ED#
         and then S'Length - Byte_Offset >= 3
         and then Octet_At (S, Byte_Offset + 1) in 16#80# .. 16#9F#
         and then Octet_At (S, Byte_Offset + 2) in 16#80# .. 16#BF#
       then 3
       elsif Octet_At (S, Byte_Offset) = 16#F0#
         and then S'Length - Byte_Offset >= 4
         and then Octet_At (S, Byte_Offset + 1) in 16#90# .. 16#BF#
         and then Octet_At (S, Byte_Offset + 2) in 16#80# .. 16#BF#
         and then Octet_At (S, Byte_Offset + 3) in 16#80# .. 16#BF#
       then 4
       elsif Octet_At (S, Byte_Offset) in 16#F1# .. 16#F3#
         and then S'Length - Byte_Offset >= 4
         and then Octet_At (S, Byte_Offset + 1) in 16#80# .. 16#BF#
         and then Octet_At (S, Byte_Offset + 2) in 16#80# .. 16#BF#
         and then Octet_At (S, Byte_Offset + 3) in 16#80# .. 16#BF#
       then 4
       elsif Octet_At (S, Byte_Offset) = 16#F4#
         and then S'Length - Byte_Offset >= 4
         and then Octet_At (S, Byte_Offset + 1) in 16#80# .. 16#8F#
         and then Octet_At (S, Byte_Offset + 2) in 16#80# .. 16#BF#
         and then Octet_At (S, Byte_Offset + 3) in 16#80# .. 16#BF#
       then 4
       else 0)
   with
     Pre  => Byte_Offset < S'Length,
     Post =>
       Sequence_Width_At'Result <= 4
       and then
         (if Sequence_Width_At'Result > 0
          then Sequence_Width_At'Result <= S'Length - Byte_Offset);

   function Valid_At (S : String; Byte_Offset : Natural) return Boolean
   is (Sequence_Width_At (S, Byte_Offset) > 0)
   with Pre => Byte_Offset < S'Length;

   function Decode_One (S : String; Byte_Offset : Natural) return Decoded_Unit
   with
     Pre  => Byte_Offset < S'Length and then Valid_At (S, Byte_Offset),
     Post =>
       Natural (Decode_One'Result.Width) = Sequence_Width_At (S, Byte_Offset)
       and then Natural (Decode_One'Result.Width) <= S'Length - Byte_Offset
       and then
         (case Decode_One'Result.Width is
            when 1 =>
              Natural (Decode_One'Result.Value) = Octet_At (S, Byte_Offset),
            when 2 =>
              Natural (Decode_One'Result.Value)
              = (Octet_At (S, Byte_Offset) - 16#C0#)
                * 64
                + (Octet_At (S, Byte_Offset + 1) - 16#80#),
            when 3 =>
              Natural (Decode_One'Result.Value)
              = (Octet_At (S, Byte_Offset) - 16#E0#) * 4_096
                + (Octet_At (S, Byte_Offset + 1) - 16#80#) * 64
                + (Octet_At (S, Byte_Offset + 2) - 16#80#),
            when 4 =>
              Natural (Decode_One'Result.Value)
              = (Octet_At (S, Byte_Offset) - 16#F0#) * 262_144
                + (Octet_At (S, Byte_Offset + 1) - 16#80#) * 4_096
                + (Octet_At (S, Byte_Offset + 2) - 16#80#) * 64
                + (Octet_At (S, Byte_Offset + 3) - 16#80#));

   function Is_Valid_UTF_8 (S : String) return Boolean;

   function Is_ASCII (S : String) return Boolean
   is (S'Length = 0
       or else
         (for all Offset in Natural range 0 .. S'Length - 1 =>
            Octet_At (S, Offset) <= 16#7F#));

   function Byte_Length (S : String) return Natural
   is (S'Length);

   function Is_Encoding (S : String; Value : Text) return Boolean
   with Ghost => Static, Pre => Is_Valid_UTF_8 (S);
   --  Relates the complete byte sequence in S to the complete scalar sequence
   --  in Value.  It is independent of Ada array bounds.

   function Model (S : String) return Text
   with
     Ghost => Static,
     Pre  => Is_Valid_UTF_8 (S),
     Post =>
       (Static =>
          Is_Encoding (S, Model'Result)
          and then
            Scalar_Sequences.Length (Model'Result)
            <= To_Big_Integer (S'Length));

   function Same_Bytes
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      Count        : Natural) return Boolean
   is (Count = 0
       or else
         (Same_Bytes
            (Left, Left_Offset, Right, Right_Offset, Count - 1)
          and then
            Octet_At (Left, Left_Offset + Count - 1)
            = Octet_At (Right, Right_Offset + Count - 1)))
   with
     Ghost => Static,
     Pre                =>
       Left_Offset <= Left'Length
       and then Count <= Left'Length - Left_Offset
       and then Right_Offset <= Right'Length
       and then Count <= Right'Length - Right_Offset,
     Subprogram_Variant => (Decreases => Count);
   --  Positional equality of two byte ranges.  The relation uses zero-based
   --  offsets and is independent of the Ada bounds of either string.

   function Prefix_Bytes (S : String; Count : Natural) return String
   is (if Count = 0
       then ""
       else S (S'First .. S'Last - (S'Length - Count)))
   with Ghost => Static, Pre => Count <= S'Length;

   function Is_Byte_Concatenation
     (Left, Right, Result : String) return Boolean
   is (Result'Length = Left'Length + Right'Length
       and then Same_Bytes (Left, 0, Result, 0, Left'Length)
       and then
         Same_Bytes
           (Right, 0, Result, Left'Length, Right'Length))
   with
     Ghost => Static,
     Pre => Left'Length <= Natural'Last - Right'Length;

   procedure Lemma_Same_Bytes_Reflexive
     (S : String; Offset, Count : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    => Offset <= S'Length and then Count <= S'Length - Offset,
     Post   => Same_Bytes (S, Offset, S, Offset, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Same_Bytes_At
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      Count        : Natural;
      Index        : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left_Offset <= Left'Length
       and then Count <= Left'Length - Left_Offset
       and then Right_Offset <= Right'Length
       and then Count <= Right'Length - Right_Offset
       and then Same_Bytes (Left, Left_Offset, Right, Right_Offset, Count)
       and then Index < Count,
     Post   =>
       Octet_At (Left, Left_Offset + Index)
       = Octet_At (Right, Right_Offset + Index),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Same_Bytes_Suffix
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      Count        : Natural;
      Dropped      : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left_Offset <= Left'Length
       and then Count <= Left'Length - Left_Offset
       and then Right_Offset <= Right'Length
       and then Count <= Right'Length - Right_Offset
       and then Same_Bytes (Left, Left_Offset, Right, Right_Offset, Count)
       and then Dropped <= Count,
     Post   =>
       Same_Bytes
         (Left,
          Left_Offset + Dropped,
          Right,
          Right_Offset + Dropped,
          Count - Dropped),
     Subprogram_Variant => (Decreases => Count - Dropped);

   procedure Lemma_Same_Bytes_Concatenation
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      First_Count  : Natural;
      Second_Count : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left_Offset <= Left'Length
       and then First_Count <= Left'Length - Left_Offset
       and then Second_Count
                  <= Left'Length - Left_Offset - First_Count
       and then Right_Offset <= Right'Length
       and then First_Count <= Right'Length - Right_Offset
       and then Second_Count
                  <= Right'Length - Right_Offset - First_Count
       and then
         Same_Bytes
           (Left, Left_Offset, Right, Right_Offset, First_Count)
       and then
         Same_Bytes
           (Left,
            Left_Offset + First_Count,
            Right,
            Right_Offset + First_Count,
            Second_Count),
     Post   =>
       Same_Bytes
         (Left,
          Left_Offset,
          Right,
          Right_Offset,
          First_Count + Second_Count),
     Subprogram_Variant => (Decreases => Second_Count);

   procedure Lemma_Same_Bytes_Prefixes
     (Left, Right : String; Count : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Count <= Left'Length
       and then Count <= Right'Length
       and then Same_Bytes (Left, 0, Right, 0, Count),
     Post   =>
       Same_Bytes
         (Prefix_Bytes (Left, Count),
          0,
          Prefix_Bytes (Right, Count),
          0,
          Count);

   procedure Lemma_Same_Bytes_Whole_Equality (Left, Right : String)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left'Length = Right'Length
       and then Same_Bytes (Left, 0, Right, 0, Left'Length),
     Post   => Left = Right,
     Subprogram_Variant => (Decreases => Left'Length);

   procedure Lemma_Encoding_Injective
     (Left, Right : String; Value : Text)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Is_Valid_UTF_8 (Left)
       and then Is_Valid_UTF_8 (Right)
       and then Is_Encoding (Left, Value)
       and then Is_Encoding (Right, Value),
     Post   =>
       Left'Length = Right'Length
       and then Same_Bytes (Left, 0, Right, 0, Left'Length);

   procedure Lemma_Concatenation (Left, Right, Result : String)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Is_Valid_UTF_8 (Left)
       and then Is_Valid_UTF_8 (Right)
       and then Left'Length <= Natural'Last - Right'Length
       and then Is_Byte_Concatenation (Left, Right, Result),
     Post   =>
       Is_Valid_UTF_8 (Result)
       and then
         Is_Concatenation
           (Model (Left), Model (Right), Model (Result));

   function Code_Point_Length (S : String) return Natural
   with
     Pre  => Is_Valid_UTF_8 (S),
     Post =>
       (Runtime => Code_Point_Length'Result <= S'Length,
        Static  =>
          To_Big_Integer (Code_Point_Length'Result)
          = Scalar_Sequences.Length (Model (S))
          and then
            To_Big_Integer (S'Length)
            <= 4 * To_Big_Integer (Code_Point_Length'Result));

   procedure Lemma_ASCII_Valid (S : String)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Is_ASCII (S),
     Post   =>
       Is_Valid_UTF_8 (S)
       and then Code_Point_Length (S) = S'Length;

   function Element
     (S : String; Index : Positive) return Scalar_Value
   with
     Pre  =>
       Is_Valid_UTF_8 (S) and then Index <= Code_Point_Length (S),
     Post =>
       (Static =>
          Element'Result
          = Scalar_Sequences.Get (Model (S), To_Big_Integer (Index)));

   type Byte_Span is record
      First     : Natural;
      Past_Last : Natural;
   end record;

   function Is_Valid_Byte_Span (S : String; Span : Byte_Span) return Boolean
   with
     Post =>
       (if Is_Valid_Byte_Span'Result
        then
          Is_Valid_UTF_8 (S)
          and then Span.First <= Span.Past_Last
          and then Span.Past_Last <= S'Length);

   function Code_Point_Length (S : String; Span : Byte_Span) return Natural
   with
     Pre  => Is_Valid_Byte_Span (S, Span),
     Post =>
       Code_Point_Length'Result <= Span.Past_Last - Span.First;

   function Model (S : String; Span : Byte_Span) return Text
   with
     Ghost => Static,
     Pre   => Is_Valid_Byte_Span (S, Span),
     Post  =>
       Scalar_Sequences.Length (Model'Result)
       = To_Big_Integer (Code_Point_Length (S, Span));

   function Slice (S : String; Span : Byte_Span) return String
   with
     Pre  => Is_Valid_Byte_Span (S, Span),
     Post =>
       (Runtime =>
          Slice'Result'First = 1
          and then Slice'Result'Length = Span.Past_Last - Span.First
          and then
            Code_Point_Length (Slice'Result)
            = Code_Point_Length (S, Span)
          and then Is_Valid_UTF_8 (Slice'Result),
        Static =>
          Same_Bytes
            (S, Span.First, Slice'Result, 0, Slice'Result'Length)
          and then Model (Slice'Result) = Model (S, Span));

   function To_Byte_Span
     (S : String; First : Positive; Count : Natural) return Byte_Span
   with
     Pre  =>
       Is_Valid_UTF_8 (S)
       and then First - 1 <= Code_Point_Length (S)
       and then Count <= Code_Point_Length (S) - (First - 1),
     Post =>
       (Runtime =>
          Is_Valid_Byte_Span (S, To_Byte_Span'Result)
          and then
            Code_Point_Length (S, To_Byte_Span'Result) = Count,
        Static  =>
          Is_Slice
            (Source => Model (S),
             First  => To_Big_Integer (First),
             Count  => To_Big_Integer (Count),
             Result => Model (Slice (S, To_Byte_Span'Result))));

   function Slice
     (S : String; First : Positive; Count : Natural) return String
   with
     Pre  =>
       Is_Valid_UTF_8 (S)
       and then First - 1 <= Code_Point_Length (S)
       and then Count <= Code_Point_Length (S) - (First - 1),
     Post =>
       (Runtime =>
          Slice'Result'First = 1
          and then Slice'Result'Length <= S'Length
          and then Is_Valid_UTF_8 (Slice'Result),
        Static =>
          Is_Slice
            (Source => Model (S),
             First  => To_Big_Integer (First),
             Count  => To_Big_Integer (Count),
             Result => Model (Slice'Result)));

   function Find
     (S : String; Value : Scalar_Value; From : Positive := 1) return Natural
   with
     Pre  =>
       Is_Valid_UTF_8 (S) and then From - 1 <= Code_Point_Length (S),
     Post =>
       (Runtime => Find'Result <= Code_Point_Length (S),
        Static  =>
          Is_First_Occurrence
            (Source => Model (S),
             Value  => Value,
             From   => To_Big_Integer (From),
             Result => To_Big_Integer (Find'Result)));

   function Reverse_Find (S : String; Value : Scalar_Value) return Natural
   with
     Pre  => Is_Valid_UTF_8 (S),
     Post =>
       (Runtime => Reverse_Find'Result <= Code_Point_Length (S),
        Static  =>
          Is_Last_Occurrence
            (Source => Model (S),
             Value  => Value,
             Result => To_Big_Integer (Reverse_Find'Result)));

   function Find
     (Haystack : String; Needle : String; From : Positive := 1)
      return Natural
   with
     Pre  =>
       Is_Valid_UTF_8 (Haystack)
       and then Is_Valid_UTF_8 (Needle)
       and then From - 1 <= Code_Point_Length (Haystack),
     Post =>
       (Runtime =>
          Find'Result = 0
          or else Find'Result - 1 <= Code_Point_Length (Haystack),
        Static  =>
          Is_First_Occurrence
            (Haystack => Model (Haystack),
             Needle   => Model (Needle),
             From     => To_Big_Integer (From),
             Result   => To_Big_Integer (Find'Result)));

   function Contains (Haystack : String; Needle : String) return Boolean
   with
     Pre  => Is_Valid_UTF_8 (Haystack) and then Is_Valid_UTF_8 (Needle),
     Post =>
       (Static =>
          Contains'Result
          = Unicode_Text.Models.Contains (Model (Haystack), Model (Needle)));

   type Cursor_Type is private;

   type Cursor_Index is range 1 .. Long_Long_Integer'Last;

   function Byte_Offset (Cursor : Cursor_Type) return Natural;

   function Model_Index (Cursor : Cursor_Type) return Cursor_Index;

   function Big_Model_Index (Cursor : Cursor_Type) return Big_Positive
   with Ghost => Static;

   function Is_Valid_Cursor (S : String; Cursor : Cursor_Type) return Boolean
   with Ghost => Static;

   function First (S : String) return Cursor_Type
   with
     Pre  => Is_Valid_UTF_8 (S),
     Post =>
       (Runtime =>
          Is_Valid_UTF_8 (S)
          and then Byte_Offset (First'Result) = 0
          and then Model_Index (First'Result) = 1,
        Static => Is_Valid_Cursor (S, First'Result));

   function Has_Element (S : String; Cursor : Cursor_Type) return Boolean
   with
     Pre  =>
       (Runtime => Is_Valid_UTF_8 (S),
        Static  => Is_Valid_Cursor (S, Cursor)),
     Post =>
       (Runtime =>
          Has_Element'Result = (Byte_Offset (Cursor) < S'Length),
        Static =>
          Has_Element'Result
          = (Big_Model_Index (Cursor)
             <= Scalar_Sequences.Length (Model (S))));

   procedure Next
     (S : String; Cursor : in out Cursor_Type; Value : out Scalar_Value)
   with
     Pre  =>
       (Runtime =>
          Is_Valid_UTF_8 (S) and then Byte_Offset (Cursor) < S'Length,
        Static  => Is_Valid_Cursor (S, Cursor)),
     Post =>
       (Runtime =>
          Model_Index (Cursor) = Model_Index (Cursor'Old) + 1
          and then Byte_Offset (Cursor)
                   = Byte_Offset (Cursor'Old)
                     + Natural (Encoding_Width (Value))
          and then Byte_Offset (Cursor)
                   = Byte_Offset (Cursor'Old)
                     + Sequence_Width_At (S, Byte_Offset (Cursor'Old))
          and then
            Value = Decode_One (S, Byte_Offset (Cursor'Old)).Value
          and then Byte_Offset (Cursor) > Byte_Offset (Cursor'Old),
        Static =>
          Is_Valid_Cursor (S, Cursor)
          and then Value
                   = Scalar_Sequences.Get
                       (Model (S), Big_Model_Index (Cursor'Old)));

   type Comparison_Result is (Less, Equal, Greater);

   function Is_Prefix (Prefix, Whole : String) return Boolean
   with
     Pre  => Is_Valid_UTF_8 (Prefix) and then Is_Valid_UTF_8 (Whole),
     Post =>
       (Static =>
          Is_Prefix'Result
          = Unicode_Text.Models.Is_Prefix (Model (Prefix), Model (Whole)));

   function Is_Suffix (Suffix, Whole : String) return Boolean
   with
     Pre  => Is_Valid_UTF_8 (Suffix) and then Is_Valid_UTF_8 (Whole),
     Post =>
       (Static =>
          Is_Suffix'Result
          = Unicode_Text.Models.Is_Suffix (Model (Suffix), Model (Whole)));

   function Compare (Left, Right : String) return Comparison_Result
   with
     Pre  => Is_Valid_UTF_8 (Left) and then Is_Valid_UTF_8 (Right),
     Post =>
       (Static =>
          (case Compare'Result is
             when Less =>
               Is_Lexicographically_Less (Model (Left), Model (Right)),
             when Equal => Model (Left) = Model (Right),
             when Greater =>
               Is_Lexicographically_Less (Model (Right), Model (Left))));

   procedure Lemma_Equality (Left, Right : String)
   with
     Ghost => Static,
     Global => null,
     Pre    => Is_Valid_UTF_8 (Left) and then Is_Valid_UTF_8 (Right),
     Post   => (Left = Right) = (Model (Left) = Model (Right));

   procedure Lemma_Prefix (Prefix, Whole : String)
   with
     Ghost => Static,
     Global => null,
     Pre    => Is_Valid_UTF_8 (Prefix) and then Is_Valid_UTF_8 (Whole),
     Post   =>
       Is_Prefix (Prefix, Whole)
       = Unicode_Text.Models.Is_Prefix (Model (Prefix), Model (Whole));

   procedure Lemma_Suffix (Suffix, Whole : String)
   with
     Ghost => Static,
     Global => null,
     Pre    => Is_Valid_UTF_8 (Suffix) and then Is_Valid_UTF_8 (Whole),
     Post   =>
       Is_Suffix (Suffix, Whole)
       = Unicode_Text.Models.Is_Suffix (Model (Suffix), Model (Whole));

   procedure Lemma_Comparison (Left, Right : String)
   with
     Ghost => Static,
     Global => null,
     Pre    => Is_Valid_UTF_8 (Left) and then Is_Valid_UTF_8 (Right),
     Post   =>
       (case Compare (Left, Right) is
          when Less =>
            Is_Lexicographically_Less (Model (Left), Model (Right)),
          when Equal => Model (Left) = Model (Right),
          when Greater =>
            Is_Lexicographically_Less (Model (Right), Model (Left)));

   function Validate (S : String) return Validation_Result
   with
     Post =>
       Validate'Result.Valid = Is_Valid_UTF_8 (S)
       and then
         (if Validate'Result.Valid
          then Validate'Result.Error_Offset = S'Length
          else
            Validate'Result.Error_Offset < S'Length
            and then not Valid_At (S, Validate'Result.Error_Offset));

   procedure Lemma_Encoding_Unique (S : String; Left, Right : Text)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Is_Valid_UTF_8 (S)
       and then Is_Encoding (S, Left)
       and then Is_Encoding (S, Right),
     Post   => Left = Right;

   procedure Lemma_Encode_Decode (Value : Scalar_Value)
   with
     Ghost => Static,
     Global => null,
     Post   =>
       Is_Valid_UTF_8 (Encode_One (Value))
       and then Decode_One (Encode_One (Value), 0).Value = Value
       and then
         Decode_One (Encode_One (Value), 0).Width = Encoding_Width (Value)
       and then Model (Encode_One (Value)) = [Value];

private

   package Cursor_Index_Conversions is new Signed_Conversions (Cursor_Index);

   type Cursor_Type is record
      Offset : Natural := 0;
      Index  : Cursor_Index := 1;
   end record;

   function Byte_Offset (Cursor : Cursor_Type) return Natural
   is (Cursor.Offset);

   function Model_Index (Cursor : Cursor_Type) return Cursor_Index
   is (Cursor.Index);

   function Big_Model_Index (Cursor : Cursor_Type) return Big_Positive
   is (Cursor_Index_Conversions.To_Big_Integer (Cursor.Index));

end Unicode_Text.UTF_8;
