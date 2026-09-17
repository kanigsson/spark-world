pragma Ada_2022;

with SPARK.Big_Integers;  use SPARK.Big_Integers;
with Unicode_Text.Models; use Unicode_Text.Models;
with Unicode_Text.UTF_8;

generic
   Capacity : Natural;
package Unicode_Text.Bounded
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;
   use type Unicode_Text.UTF_8.Cursor_Index;

   Max_Byte_Length : constant Natural := Capacity;

   type Bounded_String is private
   with Default_Initial_Condition => Is_Empty (Bounded_String);

   function Empty return Bounded_String
   with
     Post =>
       (Runtime => Is_Empty (Empty'Result),
        Static  => Model (Empty'Result) = Scalar_Sequences.Empty_Sequence);

   function Is_Empty (S : Bounded_String) return Boolean
   with Post => Is_Empty'Result = (Byte_Length (S) = 0);

   function Byte_Length (S : Bounded_String) return Natural
   with Post => Byte_Length'Result <= Max_Byte_Length;

   function Model (S : Bounded_String) return Text
   with Ghost => Static;

   function To_Bounded_String (S : String) return Bounded_String
   with
     Pre  =>
       Unicode_Text.UTF_8.Is_Valid_UTF_8 (S)
       and then S'Length <= Max_Byte_Length,
     Post =>
       (Runtime => Byte_Length (To_Bounded_String'Result) = S'Length,
        Static  => Model (To_Bounded_String'Result)
                   = Unicode_Text.UTF_8.Model (S));

   function To_String (S : Bounded_String) return String
   with
     Post =>
       (Runtime =>
          To_String'Result'First = 1
          and then To_String'Result'Length = Byte_Length (S)
          and then Unicode_Text.UTF_8.Is_Valid_UTF_8 (To_String'Result),
        Static => Unicode_Text.UTF_8.Model (To_String'Result) = Model (S));

   function Code_Point_Length (S : Bounded_String) return Natural
   with
     Post =>
       (Runtime => Code_Point_Length'Result <= Byte_Length (S),
        Static  =>
          To_Big_Integer (Code_Point_Length'Result)
          = Scalar_Sequences.Length (Model (S)));

   function Element
     (S : Bounded_String; Index : Positive) return Scalar_Value
   with
     Pre  => Index <= Code_Point_Length (S),
     Post =>
       (Static =>
          Element'Result
          = Scalar_Sequences.Get (Model (S), To_Big_Integer (Index)));

   subtype Byte_Span is Unicode_Text.UTF_8.Byte_Span;

   function Is_Valid_Byte_Span
     (S : Bounded_String; Span : Byte_Span) return Boolean
   with
     Post =>
       (if Is_Valid_Byte_Span'Result
        then
          Span.First <= Span.Past_Last
          and then Span.Past_Last <= Byte_Length (S));

   function To_Byte_Span
     (S : Bounded_String; First : Positive; Count : Natural) return Byte_Span
   with
     Pre  =>
       First - 1 <= Code_Point_Length (S)
       and then Count <= Code_Point_Length (S) - (First - 1),
     Post =>
       (Runtime => Is_Valid_Byte_Span (S, To_Byte_Span'Result),
        Static  =>
          Is_Slice
            (Source => Model (S),
             First  => To_Big_Integer (First),
             Count  => To_Big_Integer (Count),
             Result =>
               Unicode_Text.UTF_8.Model
                 (Unicode_Text.UTF_8.Slice
                    (To_String (S), To_Byte_Span'Result))));

   function Slice (S : Bounded_String; Span : Byte_Span) return Bounded_String
   with
     Pre  => Is_Valid_Byte_Span (S, Span),
     Post =>
       (Runtime => Byte_Length (Slice'Result) = Span.Past_Last - Span.First,
        Static  =>
          Model (Slice'Result)
          = Unicode_Text.UTF_8.Model
              (Unicode_Text.UTF_8.Slice (To_String (S), Span)));

   function Slice
     (S : Bounded_String; First : Positive; Count : Natural)
      return Bounded_String
   with
     Pre  =>
       First - 1 <= Code_Point_Length (S)
       and then Count <= Code_Point_Length (S) - (First - 1),
     Post =>
       (Static =>
          Is_Slice
            (Source => Model (S),
             First  => To_Big_Integer (First),
             Count  => To_Big_Integer (Count),
             Result => Model (Slice'Result)));

   function Find
     (S : Bounded_String; Value : Scalar_Value; From : Positive := 1)
      return Natural
   with
     Pre  => From - 1 <= Code_Point_Length (S),
     Post =>
       (Runtime => Find'Result <= Code_Point_Length (S),
        Static  =>
          Is_First_Occurrence
            (Source => Model (S),
             Value  => Value,
             From   => To_Big_Integer (From),
             Result => To_Big_Integer (Find'Result)));

   function Reverse_Find
     (S : Bounded_String; Value : Scalar_Value) return Natural
   with
     Post =>
       (Runtime => Reverse_Find'Result <= Code_Point_Length (S),
        Static  =>
          Is_Last_Occurrence
            (Source => Model (S),
             Value  => Value,
             Result => To_Big_Integer (Reverse_Find'Result)));

   function Find
     (Haystack : Bounded_String;
      Needle   : String;
      From     : Positive := 1) return Natural
   with
     Pre  =>
       Unicode_Text.UTF_8.Is_Valid_UTF_8 (Needle)
       and then From - 1 <= Code_Point_Length (Haystack),
     Post =>
       (Runtime =>
          Find'Result = 0
          or else Find'Result - 1 <= Code_Point_Length (Haystack),
        Static  =>
          Is_First_Occurrence
            (Haystack => Model (Haystack),
             Needle   => Unicode_Text.UTF_8.Model (Needle),
             From     => To_Big_Integer (From),
             Result   => To_Big_Integer (Find'Result)));

   function Find
     (Haystack : Bounded_String;
      Needle   : Bounded_String;
      From     : Positive := 1) return Natural
   with
     Pre  => From - 1 <= Code_Point_Length (Haystack),
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

   function Contains
     (Haystack : Bounded_String; Needle : String) return Boolean
   with
     Pre  => Unicode_Text.UTF_8.Is_Valid_UTF_8 (Needle),
     Post =>
       (Static =>
          Contains'Result
          = Unicode_Text.Models.Contains
              (Model (Haystack), Unicode_Text.UTF_8.Model (Needle)));

   function Contains
     (Haystack : Bounded_String; Needle : Bounded_String) return Boolean
   with
     Post =>
       (Static =>
          Contains'Result
          = Unicode_Text.Models.Contains (Model (Haystack), Model (Needle)));

   procedure Clear (S : out Bounded_String)
   with Post => Is_Empty (S);

   procedure Append (S : in out Bounded_String; Value : Scalar_Value)
   with
     Pre  =>
       Natural (Unicode_Text.UTF_8.Encoding_Width (Value))
       <= Max_Byte_Length - Byte_Length (S),
     Post =>
       (Runtime =>
          Byte_Length (S)
          = Byte_Length (S)'Old
            + Natural (Unicode_Text.UTF_8.Encoding_Width (Value)),
        Static => Is_Append (Model (S)'Old, Value, Model (S)));

   procedure Append (S : in out Bounded_String; Other : String)
   with
     Pre  =>
       Unicode_Text.UTF_8.Is_Valid_UTF_8 (Other)
       and then Other'Length <= Max_Byte_Length - Byte_Length (S),
     Post =>
       (Runtime =>
          Byte_Length (S) = Byte_Length (S)'Old + Other'Length,
        Static =>
          Is_Concatenation
            (Model (S)'Old, Unicode_Text.UTF_8.Model (Other), Model (S)));

   procedure Append
     (S : in out Bounded_String; Other : Bounded_String)
   with
     Pre  =>
       Byte_Length (Other) <= Max_Byte_Length - Byte_Length (S),
     Post =>
       (Runtime =>
          Byte_Length (S)
          = Byte_Length (S)'Old + Byte_Length (Other),
        Static =>
          Is_Concatenation (Model (S)'Old, Model (Other), Model (S)));

   overriding function "=" (Left, Right : Bounded_String) return Boolean
   with
     Post => (Static => "="'Result = (Model (Left) = Model (Right)));

   subtype Cursor_Type is Unicode_Text.UTF_8.Cursor_Type;
   subtype Cursor_Index is Unicode_Text.UTF_8.Cursor_Index;

   function Byte_Offset (Cursor : Cursor_Type) return Natural;

   function Model_Index (Cursor : Cursor_Type) return Cursor_Index;

   function Big_Model_Index (Cursor : Cursor_Type) return Big_Positive
   with Ghost => Static;

   function Is_Valid_Cursor
     (S : Bounded_String; Cursor : Cursor_Type) return Boolean
   with Ghost => Static;

   function First (S : Bounded_String) return Cursor_Type
   with
     Post =>
       (Runtime =>
          Byte_Offset (First'Result) = 0
          and then Model_Index (First'Result) = 1,
        Static => Is_Valid_Cursor (S, First'Result));

   function Has_Element
     (S : Bounded_String; Cursor : Cursor_Type) return Boolean
   with
     Pre  =>
       (Static => Is_Valid_Cursor (S, Cursor)),
     Post =>
       (Runtime =>
          Has_Element'Result = (Byte_Offset (Cursor) < Byte_Length (S)),
        Static =>
          Has_Element'Result
          = (Big_Model_Index (Cursor)
             <= Scalar_Sequences.Length (Model (S))));

   procedure Next
     (S      : Bounded_String;
      Cursor : in out Cursor_Type;
      Value  : out Scalar_Value)
   with
     Pre  =>
       (Runtime => Byte_Offset (Cursor) < Byte_Length (S),
        Static  =>
          Is_Valid_Cursor (S, Cursor)
          and then
            Big_Model_Index (Cursor)
            <= Scalar_Sequences.Length (Model (S))),
     Post =>
       (Runtime =>
          Model_Index (Cursor) = Model_Index (Cursor'Old) + 1
          and then Byte_Offset (Cursor)
                   = Byte_Offset (Cursor'Old)
                     + Natural (Unicode_Text.UTF_8.Encoding_Width (Value))
          and then Byte_Offset (Cursor) > Byte_Offset (Cursor'Old),
        Static =>
          Is_Valid_Cursor (S, Cursor)
          and then Value
                   = Scalar_Sequences.Get
                       (Model (S), Big_Model_Index (Cursor'Old)));

private
   subtype Buffer is String (1 .. Capacity);
   subtype Length_Range is Natural range 0 .. Capacity;

   type Bounded_String_Representation is record
      Data : Buffer := (others => Character'Val (0));
      Used : Length_Range := 0;
   end record;

   function Has_Valid_Representation
     (Data : Buffer; Used : Length_Range) return Boolean
   with
     Post =>
       (Static =>
          Has_Valid_Representation'Result
          = (Used = 0
             or else
               Unicode_Text.UTF_8.Is_Valid_UTF_8 (Data (1 .. Used)))
          and then
            (not Has_Valid_Representation'Result
             or else
               Unicode_Text.UTF_8.Is_Valid_UTF_8 (Data (1 .. Used))));

   type Bounded_String is new Bounded_String_Representation
   with
     Dynamic_Predicate =>
       Has_Valid_Representation (Data, Used);

end Unicode_Text.Bounded;
