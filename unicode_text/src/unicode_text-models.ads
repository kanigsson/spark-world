pragma Ada_2022;

with SPARK.Big_Integers; use SPARK.Big_Integers;
with SPARK.Containers.Functional.Infinite_Sequences;

package Unicode_Text.Models
  with SPARK_Mode
is

   package Scalar_Sequences is new
     SPARK.Containers.Functional.Infinite_Sequences
       (Element_Type         => Scalar_Value,
        Use_Logical_Equality => True);
   use type Scalar_Sequences.Sequence;

   subtype Text is Scalar_Sequences.Sequence;

   function Is_Prefix (Prefix, Whole : Text) return Boolean
   is (Scalar_Sequences.Length (Prefix) <= Scalar_Sequences.Length (Whole)
       and then
         (for all I in Prefix =>
            Scalar_Sequences.Get (Prefix, I)
            = Scalar_Sequences.Get (Whole, I)))
   with Ghost => Static;

   function Is_Suffix (Suffix, Whole : Text) return Boolean
   is (Scalar_Sequences.Length (Suffix) <= Scalar_Sequences.Length (Whole)
       and then
         (for all I in Suffix =>
            Scalar_Sequences.Get (Suffix, I)
            = Scalar_Sequences.Get
                (Whole,
                 Scalar_Sequences.Length (Whole)
                 - Scalar_Sequences.Length (Suffix)
                 + I)))
   with Ghost => Static;

   function Is_Lexicographically_Less (Left, Right : Text) return Boolean
   is ((Scalar_Sequences.Length (Left) < Scalar_Sequences.Length (Right)
        and then Is_Prefix (Left, Right))
       or else
         (for some I in Left =>
            I <= Scalar_Sequences.Length (Right)
            and then
              (for all J in Left =>
                 (if J < I
                  then
                    Scalar_Sequences.Get (Left, J)
                    = Scalar_Sequences.Get (Right, J)))
            and then
              Scalar_Sequences.Get (Left, I)
              < Scalar_Sequences.Get (Right, I)))
   with Ghost => Static;

   function Is_Append
     (Before : Text; Value : Scalar_Value; After : Text) return Boolean
   is (Scalar_Sequences.Length (After) = Scalar_Sequences.Length (Before) + 1
       and then Is_Prefix (Before, After)
       and then
         Scalar_Sequences.Get (After, Scalar_Sequences.Last (After)) = Value)
   with Ghost => Static;

   function Is_Concatenation (Left, Right, Result : Text) return Boolean
   is (Scalar_Sequences.Length (Result)
       = Scalar_Sequences.Length (Left) + Scalar_Sequences.Length (Right)
       and then
         (for all I in Left =>
            Scalar_Sequences.Get (Result, I) = Scalar_Sequences.Get (Left, I))
       and then
         (for all I in Right =>
            Scalar_Sequences.Get (Result, Scalar_Sequences.Length (Left) + I)
            = Scalar_Sequences.Get (Right, I)))
   with Ghost => Static;

   function Is_Slice
     (Source : Text; First : Big_Positive; Count : Big_Natural; Result : Text)
      return Boolean
   is (First <= Scalar_Sequences.Length (Source) + 1
       and then Count <= Scalar_Sequences.Length (Source) - (First - 1)
       and then Scalar_Sequences.Length (Result) = Count
       and then
         (for all I in Result =>
            Scalar_Sequences.Get (Result, I)
            = Scalar_Sequences.Get (Source, First + I - 1)))
   with Ghost => Static;

   function Contains (Haystack, Needle : Text) return Boolean
   is (Scalar_Sequences.Length (Needle) = 0
       or else
         (for some First in Haystack =>
            Is_Slice
              (Source => Haystack,
               First  => First,
               Count  => Scalar_Sequences.Length (Needle),
               Result => Needle)))
   with Ghost => Static;

   function Matches_At
     (Haystack : Text; Needle : Text; First : Big_Positive) return Boolean
   is (Is_Slice
         (Source => Haystack,
          First  => First,
          Count  => Scalar_Sequences.Length (Needle),
          Result => Needle))
   with Ghost => Static;

   function Is_First_Occurrence
     (Haystack : Text;
      Needle   : Text;
      From     : Big_Positive;
      Result   : Big_Natural) return Boolean
   is (From <= Scalar_Sequences.Length (Haystack) + 1
       and then
         (if Result = 0
          then
            Scalar_Sequences.Length (Needle) > 0
            and then
              (for all I in Haystack =>
                 (if I >= From then not Matches_At (Haystack, Needle, I)))
          else
            Result >= From
            and then Matches_At (Haystack, Needle, Result)
            and then
              (for all I in Haystack =>
                 (if I >= From and then I < Result
                  then not Matches_At (Haystack, Needle, I)))))
   with Ghost => Static;

   function Is_First_Occurrence
     (Source : Text;
      Value  : Scalar_Value;
      From   : Big_Positive;
      Result : Big_Natural) return Boolean
   is (From <= Scalar_Sequences.Length (Source) + 1
       and then
         (if Result = 0
          then
            (for all I in Source =>
               (if I >= From
                then Scalar_Sequences.Get (Source, I) /= Value))
          else
            Result >= From
            and then Result <= Scalar_Sequences.Length (Source)
            and then Scalar_Sequences.Get (Source, Result) = Value
            and then
              (for all I in Source =>
                 (if I >= From and then I < Result
                  then Scalar_Sequences.Get (Source, I) /= Value))))
   with Ghost => Static;

   function Is_Last_Occurrence
     (Source : Text; Value : Scalar_Value; Result : Big_Natural)
      return Boolean
   is (if Result = 0
       then
         (for all I in Source => Scalar_Sequences.Get (Source, I) /= Value)
       else
         Result >= 1
         and then Result <= Scalar_Sequences.Length (Source)
         and then Scalar_Sequences.Get (Source, Result) = Value
         and then
           (for all I in Source =>
              (if I > Result
               then Scalar_Sequences.Get (Source, I) /= Value)))
   with Ghost => Static;

   function Is_Delimiter_Free
     (Source    : Text;
      Separator : Text;
      First     : Big_Positive;
      Count     : Big_Natural) return Boolean
   is (First <= Scalar_Sequences.Length (Source) + 1
       and then Count <= Scalar_Sequences.Length (Source) - (First - 1)
       and then
         (for all I in Source =>
            (if I >= First and then I < First + Count
             then not Matches_At (Source, Separator, I))))
   with Ghost => Static;
   --  States delimiter absence in source coordinates.  This form composes
   --  directly with first-occurrence search and avoids exposing UTF-8 byte
   --  positions to split clients.

   function Is_Delimiter_Free
     (Source    : Text;
      Separator : Scalar_Value;
      First     : Big_Positive;
      Count     : Big_Natural) return Boolean
   is (First <= Scalar_Sequences.Length (Source) + 1
       and then Count <= Scalar_Sequences.Length (Source) - (First - 1)
       and then
         (for all I in Source =>
            (if I >= First and then I < First + Count
             then Scalar_Sequences.Get (Source, I) /= Separator)))
   with Ghost => Static;

   function Is_Split_Step
     (Source     : Text;
      Separator  : Text;
      Segment    : Text;
      First      : Big_Positive;
      Next_First : Big_Positive;
      Final      : Boolean) return Boolean
   is (Scalar_Sequences.Length (Separator) > 0
       and then
         Is_Slice
           (Source => Source,
            First  => First,
            Count  => Scalar_Sequences.Length (Segment),
            Result => Segment)
       and then
         Is_Delimiter_Free
           (Source,
            Separator,
            First,
            Scalar_Sequences.Length (Segment))
       and then
         (if Final
          then
            Next_First = Scalar_Sequences.Length (Source) + 1
            and then
              First + Scalar_Sequences.Length (Segment) = Next_First
          else
            Matches_At
              (Source,
               Separator,
               First + Scalar_Sequences.Length (Segment))
            and then
              Next_First
              = First + Scalar_Sequences.Length (Segment)
                + Scalar_Sequences.Length (Separator)))
   with Ghost => Static;
   --  One allocation-free split step.  Segment is the exact source slice at
   --  First, contains no delimiter start, and is followed either by one
   --  separator or by the end of Source.  Chaining First/Next_First therefore
   --  reconstructs the source from the returned segments and separators.

   function Is_Split_Step
     (Source     : Text;
      Separator  : Scalar_Value;
      Segment    : Text;
      First      : Big_Positive;
      Next_First : Big_Positive;
      Final      : Boolean) return Boolean
   is (Is_Slice
         (Source => Source,
          First  => First,
          Count  => Scalar_Sequences.Length (Segment),
          Result => Segment)
       and then
         Is_Delimiter_Free
           (Source,
            Separator,
            First,
            Scalar_Sequences.Length (Segment))
       and then
         (if Final
          then
            Next_First = Scalar_Sequences.Length (Source) + 1
            and then
              First + Scalar_Sequences.Length (Segment) = Next_First
          else
            First + Scalar_Sequences.Length (Segment)
              <= Scalar_Sequences.Length (Source)
            and then
              Scalar_Sequences.Get
                (Source, First + Scalar_Sequences.Length (Segment))
              = Separator
            and then
              Next_First
              = First + Scalar_Sequences.Length (Segment) + 1))
   with Ghost => Static;

   procedure Lemma_Extend_Slice
     (Source : Text;
      First  : Big_Positive;
      Count  : Big_Natural;
      Before : Text;
      Value  : Scalar_Value;
      After  : Text)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Is_Slice (Source, First, Count, Before)
       and then First + Count <= Scalar_Sequences.Length (Source)
       and then Value = Scalar_Sequences.Get (Source, First + Count)
       and then Is_Concatenation (Before, [Value], After),
     Post   => Is_Slice (Source, First, Count + 1, After);

   procedure Lemma_Concatenation_Associative
     (Left, Middle, Right                       : Text;
      Left_Middle, Middle_Right                 : Text;
      Left_Grouped_Result, Right_Grouped_Result : Text)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Is_Concatenation (Left, Middle, Left_Middle)
       and then Is_Concatenation (Left_Middle, Right, Left_Grouped_Result)
       and then Is_Concatenation (Middle, Right, Middle_Right)
       and then Is_Concatenation (Left, Middle_Right, Right_Grouped_Result),
     Post   => Left_Grouped_Result = Right_Grouped_Result;

   procedure Lemma_Prepend_Concatenation
     (Value : Scalar_Value; Left, Right, Result : Text)
   with
     Ghost => Static,
     Global => null,
     Pre    => Is_Concatenation (Left, Right, Result),
     Post   =>
       Is_Concatenation
         (Scalar_Sequences.Add (Left, 1, Value),
          Right,
          Scalar_Sequences.Add (Result, 1, Value));

end Unicode_Text.Models;
