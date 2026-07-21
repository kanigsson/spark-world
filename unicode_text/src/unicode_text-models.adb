package body Unicode_Text.Models
  with SPARK_Mode
is

   procedure Lemma_Equal_Reflexive (Value : Text) is null;

   procedure Lemma_Equal_Extensional (Left, Right : Text) is null;

   procedure Lemma_Equal_Symmetric (Left, Right : Text) is null;

   procedure Lemma_Equal_Transitive (First, Second, Third : Text) is null;

   procedure Lemma_Add_Is_Append (Before : Text; Value : Scalar_Value) is null;

   procedure Lemma_Prefix_Reflexive (Value : Text) is null;

   procedure Lemma_Prefix_Transitive (First, Second, Third : Text) is null;

   procedure Lemma_Concatenation_Empty_Left (Value : Text) is null;

   procedure Lemma_Concatenation_Empty_Right (Value : Text) is null;

   procedure Lemma_Concatenation_Unique
     (Left, Right, First_Result, Second_Result : Text) is
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

   procedure Lemma_Slice_Whole (Source : Text) is null;

   procedure Lemma_Slice_Empty (Source : Text; First : Big_Positive) is null;

   procedure Lemma_Containment_Reflexive (Value : Text) is
   begin
      if Scalar_Sequences.Length (Value) > 0 then
         Lemma_Slice_Whole (Value);
         pragma
           Assert
             (Is_Slice (Value, 1, Scalar_Sequences.Length (Value), Value));
      end if;
   end Lemma_Containment_Reflexive;

end Unicode_Text.Models;
