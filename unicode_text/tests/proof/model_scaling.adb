package body Model_Scaling
  with SPARK_Mode
is

   procedure Nonempty_Witness is
      Left   : constant Text := [0, 16#7F#, 16#80#]
      with Ghost;
      Right  : constant Text := [16#D7FF#, 16#E000#, 16#10_FFFF#]
      with Ghost;
      Result : constant Text :=
        [0, 16#7F#, 16#80#, 16#D7FF#, 16#E000#, 16#10_FFFF#]
      with Ghost;
   begin
      pragma Assert (Is_Concatenation (Left, Right, Result));
      pragma Assert (Is_Slice (Result, 4, 3, Right));
      pragma Assert (Contains (Result, Right));
   end Nonempty_Witness;

   procedure Concatenation_Associativity
     (Left, Middle, Right                       : Text;
      Left_Middle, Middle_Right                 : Text;
      Left_Grouped_Result, Right_Grouped_Result : Text) is
   begin
      Lemma_Concatenation_Associative
        (Left,
         Middle,
         Right,
         Left_Middle,
         Middle_Right,
         Left_Grouped_Result,
         Right_Grouped_Result);
   end Concatenation_Associativity;

   procedure Chain_1 (T0, T1, R1 : Text) is null;

   procedure Chain_2 (T0, T1, T2, R1, R2 : Text) is null;

   procedure Chain_4 (T0, T1, T2, T3, T4, R1, R2, R3, R4 : Text) is null;

   procedure Chain_8
     (T0, T1, T2, T3, T4, T5, T6, T7, T8 : Text;
      R1, R2, R3, R4, R5, R6, R7, R8     : Text)
   is null;

   procedure Chain_16
     (T0, T1, T2, T3, T4, T5, T6, T7, T8    : Text;
      T9, T10, T11, T12, T13, T14, T15, T16 : Text;
      R1, R2, R3, R4, R5, R6, R7, R8        : Text;
      R9, R10, R11, R12, R13, R14, R15, R16 : Text)
   is null;

end Model_Scaling;
