with Unicode_Text.Models; use Unicode_Text.Models;

package Model_Scaling
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;

   procedure Nonempty_Witness
   with Ghost, Global => null;

   procedure Concatenation_Associativity
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
     Post   => Left_Grouped_Result = Right_Grouped_Result;

   procedure Chain_1 (T0, T1, R1 : Text)
   with
     Ghost,
     Global => null,
     Pre    => Is_Concatenation (T0, T1, R1),
     Post   => Is_Prefix (T0, R1);

   procedure Chain_2 (T0, T1, T2, R1, R2 : Text)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Concatenation (T0, T1, R1) and then Is_Concatenation (R1, T2, R2),
     Post   => Is_Prefix (T0, R2);

   procedure Chain_4 (T0, T1, T2, T3, T4, R1, R2, R3, R4 : Text)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Concatenation (T0, T1, R1)
       and then Is_Concatenation (R1, T2, R2)
       and then Is_Concatenation (R2, T3, R3)
       and then Is_Concatenation (R3, T4, R4),
     Post   => Is_Prefix (T0, R4);

   procedure Chain_8
     (T0, T1, T2, T3, T4, T5, T6, T7, T8 : Text;
      R1, R2, R3, R4, R5, R6, R7, R8     : Text)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Concatenation (T0, T1, R1)
       and then Is_Concatenation (R1, T2, R2)
       and then Is_Concatenation (R2, T3, R3)
       and then Is_Concatenation (R3, T4, R4)
       and then Is_Concatenation (R4, T5, R5)
       and then Is_Concatenation (R5, T6, R6)
       and then Is_Concatenation (R6, T7, R7)
       and then Is_Concatenation (R7, T8, R8),
     Post   => Is_Prefix (T0, R8);

   procedure Chain_16
     (T0, T1, T2, T3, T4, T5, T6, T7, T8    : Text;
      T9, T10, T11, T12, T13, T14, T15, T16 : Text;
      R1, R2, R3, R4, R5, R6, R7, R8        : Text;
      R9, R10, R11, R12, R13, R14, R15, R16 : Text)
   with
     Ghost,
     Global => null,
     Pre    =>
       Is_Concatenation (T0, T1, R1)
       and then Is_Concatenation (R1, T2, R2)
       and then Is_Concatenation (R2, T3, R3)
       and then Is_Concatenation (R3, T4, R4)
       and then Is_Concatenation (R4, T5, R5)
       and then Is_Concatenation (R5, T6, R6)
       and then Is_Concatenation (R6, T7, R7)
       and then Is_Concatenation (R7, T8, R8)
       and then Is_Concatenation (R8, T9, R9)
       and then Is_Concatenation (R9, T10, R10)
       and then Is_Concatenation (R10, T11, R11)
       and then Is_Concatenation (R11, T12, R12)
       and then Is_Concatenation (R12, T13, R13)
       and then Is_Concatenation (R13, T14, R14)
       and then Is_Concatenation (R14, T15, R15)
       and then Is_Concatenation (R15, T16, R16),
     Post   => Is_Prefix (T0, R16);

end Model_Scaling;
