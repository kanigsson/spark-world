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

   subtype Text is Scalar_Sequences.Sequence;

   function Is_Equal (Left, Right : Text) return Boolean
   is (Scalar_Sequences.Length (Left) = Scalar_Sequences.Length (Right)
       and then
         (for all I in Left =>
            Scalar_Sequences.Get (Left, I) = Scalar_Sequences.Get (Right, I)))
   with Ghost;

   function Is_Prefix (Prefix, Whole : Text) return Boolean
   is (Scalar_Sequences.Length (Prefix) <= Scalar_Sequences.Length (Whole)
       and then
         (for all I in Prefix =>
            Scalar_Sequences.Get (Prefix, I)
            = Scalar_Sequences.Get (Whole, I)))
   with Ghost;

   function Is_Append
     (Before : Text; Value : Scalar_Value; After : Text) return Boolean
   is (Scalar_Sequences.Length (After) = Scalar_Sequences.Length (Before) + 1
       and then Is_Prefix (Before, After)
       and then
         Scalar_Sequences.Get (After, Scalar_Sequences.Last (After)) = Value)
   with Ghost;

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
   with Ghost;

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
   with Ghost;

   function Contains (Haystack, Needle : Text) return Boolean
   is (Scalar_Sequences.Length (Needle) = 0
       or else
         (for some First in Haystack =>
            Is_Slice
              (Source => Haystack,
               First  => First,
               Count  => Scalar_Sequences.Length (Needle),
               Result => Needle)))
   with Ghost;

   procedure Lemma_Equal_Reflexive (Value : Text)
   with Ghost, Global => null, Post => Is_Equal (Value, Value);

   procedure Lemma_Equal_Extensional (Left, Right : Text)
   with
     Ghost,
     Global => null,
     Post   => Is_Equal (Left, Right) = Scalar_Sequences."=" (Left, Right);

   procedure Lemma_Equal_Symmetric (Left, Right : Text)
   with
     Ghost,
     Global => null,
     Pre    => Is_Equal (Left, Right),
     Post   => Is_Equal (Right, Left);

   procedure Lemma_Equal_Transitive (First, Second, Third : Text)
   with
     Ghost,
     Global => null,
     Pre    => Is_Equal (First, Second) and then Is_Equal (Second, Third),
     Post   => Is_Equal (First, Third);

   procedure Lemma_Add_Is_Append (Before : Text; Value : Scalar_Value)
   with
     Ghost,
     Global => null,
     Post   => Is_Append (Before, Value, Scalar_Sequences.Add (Before, Value));

   procedure Lemma_Prefix_Reflexive (Value : Text)
   with Ghost, Global => null, Post => Is_Prefix (Value, Value);

   procedure Lemma_Prefix_Transitive (First, Second, Third : Text)
   with
     Ghost,
     Global => null,
     Pre    => Is_Prefix (First, Second) and then Is_Prefix (Second, Third),
     Post   => Is_Prefix (First, Third);

   procedure Lemma_Concatenation_Empty_Left (Value : Text)
   with
     Ghost,
     Global => null,
     Post   =>
       Is_Concatenation (Scalar_Sequences.Empty_Sequence, Value, Value);

   procedure Lemma_Concatenation_Empty_Right (Value : Text)
   with
     Ghost,
     Global => null,
     Post   =>
       Is_Concatenation (Value, Scalar_Sequences.Empty_Sequence, Value);

   procedure Lemma_Concatenation_Unique
     (Left, Right, First_Result, Second_Result : Text)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Concatenation (Left, Right, First_Result)
       and then Is_Concatenation (Left, Right, Second_Result),
     Post   => Is_Equal (First_Result, Second_Result);

   procedure Lemma_Concatenation_Associative
     (Left, Middle, Right                       : Text;
      Left_Middle, Middle_Right                 : Text;
      Left_Grouped_Result, Right_Grouped_Result : Text)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Concatenation (Left, Middle, Left_Middle)
       and then Is_Concatenation (Left_Middle, Right, Left_Grouped_Result)
       and then Is_Concatenation (Middle, Right, Middle_Right)
       and then Is_Concatenation (Left, Middle_Right, Right_Grouped_Result),
     Post   => Is_Equal (Left_Grouped_Result, Right_Grouped_Result);

   procedure Lemma_Slice_Whole (Source : Text)
   with
     Ghost,
     Global => null,
     Post   => Is_Slice (Source, 1, Scalar_Sequences.Length (Source), Source);

   procedure Lemma_Slice_Empty (Source : Text; First : Big_Positive)
   with
     Ghost,
     Global => null,
     Pre    => First <= Scalar_Sequences.Length (Source) + 1,
     Post   => Is_Slice (Source, First, 0, Scalar_Sequences.Empty_Sequence);

   procedure Lemma_Containment_Reflexive (Value : Text)
   with Ghost, Global => null, Post => Contains (Value, Value);

end Unicode_Text.Models;
