package body Unicode_Text.Models
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;

   procedure Lemma_Concatenation_Unique
     (Left, Right, First_Result, Second_Result : Text)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Concatenation (Left, Right, First_Result)
       and then Is_Concatenation (Left, Right, Second_Result),
     Post   => First_Result = Second_Result
   is
   begin
      pragma
        Assert
          (Scalar_Sequences.Length (First_Result)
           = Scalar_Sequences.Length (Second_Result));
      pragma
        Assert
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
                      (Right, I - Scalar_Sequences.Length (Left))));
   end Lemma_Concatenation_Unique;

   procedure Lemma_Concatenation_Associative
     (Left, Middle, Right                       : Text;
      Left_Middle, Middle_Right                 : Text;
      Left_Grouped_Result, Right_Grouped_Result : Text) is
   begin
      pragma
        Assert
          (Scalar_Sequences.Length (Left_Grouped_Result)
           = Scalar_Sequences.Length (Left)
             + Scalar_Sequences.Length (Middle_Right));
      pragma
        Assert
          (for all I in Left =>
             Scalar_Sequences.Get (Left_Grouped_Result, I)
             = Scalar_Sequences.Get (Left, I));
      pragma
        Assert
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
                      (Right, I - Scalar_Sequences.Length (Middle))));
      pragma
        Assert (Is_Concatenation (Left, Middle_Right, Left_Grouped_Result));
      Lemma_Concatenation_Unique
        (Left, Middle_Right, Left_Grouped_Result, Right_Grouped_Result);
   end Lemma_Concatenation_Associative;

end Unicode_Text.Models;
