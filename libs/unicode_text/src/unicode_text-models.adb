package body Unicode_Text.Models
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;

   procedure Lemma_Extend_Slice
     (Source : Text;
      First  : Big_Positive;
      Count  : Big_Natural;
      Before : Text;
      Value  : Scalar_Value;
      After  : Text)
   is
   begin
      pragma Assert
        (Static => Scalar_Sequences.Length (After) = Count + 1);
      pragma Assert
        (Static =>
           (for all I in After =>
              (if I <= Count
               then
                 Scalar_Sequences.Get (After, I)
                 = Scalar_Sequences.Get (Before, I)
                 and then
                   Scalar_Sequences.Get (Before, I)
                   = Scalar_Sequences.Get (Source, First + I - 1)
               else
                 I = Count + 1
                 and then Scalar_Sequences.Get (After, I) = Value
                 and then
                   Value = Scalar_Sequences.Get (Source, First + I - 1))));
   end Lemma_Extend_Slice;

   procedure Lemma_Concatenation_Unique
     (Left, Right, First_Result, Second_Result : Text)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Is_Concatenation (Left, Right, First_Result)
       and then Is_Concatenation (Left, Right, Second_Result),
     Post   => First_Result = Second_Result
   is
   begin
      pragma Assert
        (Static =>
           Scalar_Sequences.Length (First_Result)
           = Scalar_Sequences.Length (Second_Result));
      pragma Assert
        (Static =>
           (for all I in First_Result =>
              (if I <= Scalar_Sequences.Length (Left)
               then
                 Scalar_Sequences.Get (First_Result, I)
                 = Scalar_Sequences.Get (Left, I)
                 and then
                   Scalar_Sequences.Get (Second_Result, I)
                   = Scalar_Sequences.Get (Left, I)
               else
                 Scalar_Sequences.Get (First_Result, I)
                 = Scalar_Sequences.Get
                     (Right, I - Scalar_Sequences.Length (Left))
                 and then
                   Scalar_Sequences.Get (Second_Result, I)
                   = Scalar_Sequences.Get
                       (Right, I - Scalar_Sequences.Length (Left)))));
   end Lemma_Concatenation_Unique;

   procedure Lemma_Concatenation_Associative
     (Left, Middle, Right                       : Text;
      Left_Middle, Middle_Right                 : Text;
      Left_Grouped_Result, Right_Grouped_Result : Text) is
   begin
      pragma Assert
        (Static =>
           Scalar_Sequences.Length (Left_Grouped_Result)
           = Scalar_Sequences.Length (Left)
             + Scalar_Sequences.Length (Middle_Right));
      pragma Assert
        (Static =>
           (for all I in Left =>
              Scalar_Sequences.Get (Left_Grouped_Result, I)
              = Scalar_Sequences.Get (Left, I)));
      pragma Assert
        (Static =>
           (for all I in Middle_Right =>
              (if I <= Scalar_Sequences.Length (Middle)
               then
                 Scalar_Sequences.Get
                   (Left_Grouped_Result, Scalar_Sequences.Length (Left) + I)
                 = Scalar_Sequences.Get (Middle, I)
                 and then
                   Scalar_Sequences.Get (Middle_Right, I)
                   = Scalar_Sequences.Get (Middle, I)
               else
                 Scalar_Sequences.Get
                   (Left_Grouped_Result, Scalar_Sequences.Length (Left) + I)
                 = Scalar_Sequences.Get
                     (Right, I - Scalar_Sequences.Length (Middle))
                 and then
                   Scalar_Sequences.Get (Middle_Right, I)
                   = Scalar_Sequences.Get
                       (Right, I - Scalar_Sequences.Length (Middle)))));
      pragma Assert
        (Static =>
           Is_Concatenation (Left, Middle_Right, Left_Grouped_Result));
      Lemma_Concatenation_Unique
        (Left, Middle_Right, Left_Grouped_Result, Right_Grouped_Result);
   end Lemma_Concatenation_Associative;

   procedure Lemma_Prepend_Concatenation
     (Value : Scalar_Value; Left, Right, Result : Text)
   is
      New_Left   : constant Text := Scalar_Sequences.Add (Left, 1, Value)
      with Ghost => Static;
      New_Result : constant Text := Scalar_Sequences.Add (Result, 1, Value)
      with Ghost => Static;
   begin
      pragma Assert
        (Static => Scalar_Sequences.Length (New_Result)
         = Scalar_Sequences.Length (New_Left)
           + Scalar_Sequences.Length (Right));
      pragma Assert (Static => Scalar_Sequences.Get (New_Result, 1) = Value);
      pragma Assert (Static => Scalar_Sequences.Get (New_Left, 1) = Value);
      pragma Assert
        (Static =>
           (for all I in New_Left =>
              (if I = 1
               then
                 Scalar_Sequences.Get (New_Result, I)
                 = Scalar_Sequences.Get (New_Left, I)
               else
                 Scalar_Sequences.Get (New_Result, I)
                 = Scalar_Sequences.Get (Result, I - 1)
                 and then
                   Scalar_Sequences.Get (New_Left, I)
                   = Scalar_Sequences.Get (Left, I - 1))));
      pragma Assert
        (Static =>
           (for all I in Right =>
              Scalar_Sequences.Get
                (New_Result, Scalar_Sequences.Length (New_Left) + I)
              = Scalar_Sequences.Get (Right, I)));
   end Lemma_Prepend_Concatenation;

end Unicode_Text.Models;
