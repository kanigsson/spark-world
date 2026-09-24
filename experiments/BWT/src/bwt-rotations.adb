package body BWT.Rotations with SPARK_Mode is
   procedure Previous_Injective (A, B : Rotation) is
   begin
      null;
   end Previous_Injective;

   function Letter (S : String; R : Rotation; K : Natural) return Character is
     (S (R.First + (R.Offset + K) mod R.Length));

   procedure Modulo_Period (X : Natural; P : Positive)
   with Ghost, Pre => X <= 5 * Max_Length and then P <= X,
     Post => X mod P = (X - P) mod P;

   procedure Modulo_Period (X : Natural; P : Positive) is
   begin
      pragma Assert (X / P = (X - P) / P + 1);
   end Modulo_Period;

   procedure Equal_Same (S : String; A, B : Rotation; Size : Natural) is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      null;
   end Equal_Same;

   procedure Period (S : String; A : Rotation; K : Natural) is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      Modulo_Period (A.Offset + K, A.Length);
   end Period;

   procedure Shift_Letter (S : String; R : Rotation; K : Natural) is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      if R.Offset = 0 and then K > 0 then
         Modulo_Period (R.Length - 1 + K, R.Length);
      elsif R.Offset > 0 and then K = 0 then
         Modulo_Period (R.Offset + R.Length - 1, R.Length);
      end if;
   end Shift_Letter;

   procedure Prefix_Letter (S : String; A, B : Rotation; Size, K : Natural) is
   begin
      if K + 1 < Size then
         Prefix_Letter (S, A, B, Size - 1, K);
      end if;
   end Prefix_Letter;
   procedure Order_Laws (S : String; A, B, C : Rotation; Size : Natural) is
   begin
      for K in 0 .. Size loop
         pragma Loop_Invariant
           (LE (S, A, B, K) or LE (S, B, A, K));
         pragma Loop_Invariant
           ((LE (S, A, B, K) and LE (S, B, A, K)) =
              Equal_Prefix (S, A, B, K));
         pragma Loop_Invariant
           (if LE (S, A, B, Size) and LE (S, B, C, Size)
            then LE (S, A, C, K)
              and then (if Equal_Prefix (S, A, C, K)
                        then Equal_Prefix (S, A, B, K)
                          and then Equal_Prefix (S, B, C, K)));
      end loop;
   end Order_Laws;

   procedure Extend_Equality (S : String; A, B : Rotation; Size : Natural) is
   begin
      for K in A.Length + B.Length .. Size - 1 loop
         pragma Loop_Invariant (Equal_Prefix (S, A, B, K));
         Prefix_Letter (S, A, B, K, K - A.Length);
         Prefix_Letter (S, A, B, K, K - B.Length);
         Prefix_Letter (S, A, B, K, K - A.Length - B.Length);
         Period (S, A, K);
         Period (S, B, K);
         Period (S, B, K - A.Length);
         Period (S, A, K - B.Length);
         pragma Assert (Letter (S, A, K) = Letter (S, A, K - A.Length));
         pragma Assert (Letter (S, B, K) = Letter (S, B, K - B.Length));
         pragma Assert
           (Letter (S, B, K - A.Length) =
              Letter (S, B, K - A.Length - B.Length));
         pragma Assert
           (Letter (S, A, K - B.Length) =
              Letter (S, A, K - A.Length - B.Length));
         pragma Assert
           (Letter (S, A, K - A.Length) = Letter (S, B, K - A.Length));
         pragma Assert
           (Letter (S, A, K - B.Length) = Letter (S, B, K - B.Length));
         pragma Assert
           (Letter (S, A, K - A.Length - B.Length) =
              Letter (S, B, K - A.Length - B.Length));
         pragma Assert (Letter (S, A, K) = Letter (S, B, K));
      end loop;
   end Extend_Equality;

   procedure Decide (S : String; A, B : Rotation; K, Size : Natural)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Size <= 4 * Max_Length
     and then K < Size and then Equal_Prefix (S, A, B, K)
     and then Letter (S, A, K) /= Letter (S, B, K),
     Post => LE (S, A, B, Size) = (Letter (S, A, K) < Letter (S, B, K));

   procedure Decide (S : String; A, B : Rotation; K, Size : Natural) is
   begin
      for N in K + 1 .. Size loop
         pragma Loop_Invariant (not Equal_Prefix (S, A, B, N));
         pragma Loop_Invariant
           (LE (S, A, B, N) = (Letter (S, A, K) < Letter (S, B, K)));
      end loop;
   end Decide;

   function Less (S : String; A, B : Rotation) return Boolean is
   begin
      --  A common comparison horizon makes order laws independent of the
      --  lengths. Extend_Equality justifies the shorter p + q stopping bound.
      for K in 0 .. 2 * S'Length - 1 loop
         pragma Loop_Invariant (Equal_Prefix (S, A, B, K));
         if Letter (S, A, K) /= Letter (S, B, K) then
            Decide (S, B, A, K, 2 * S'Length);
            return Letter (S, A, K) < Letter (S, B, K);
         end if;
      end loop;
      return False;
   end Less;

   procedure Key_Order
     (S : String; A, B, C : Rotation; Ties : Tie_Order := Earlier_First) is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      Order_Laws (S, A, B, C, 2 * S'Length);
      Order_Laws (S, B, C, A, 2 * S'Length);
      Order_Laws (S, C, A, B, 2 * S'Length);
   end Key_Order;

   procedure Key_Weakening
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First) is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      null;
   end Key_Weakening;

   procedure Equivalent_Order (S : String; A, B, C : Rotation) is
      N : constant Natural := 2 * S'Length;
   begin
      Order_Laws (S, A, B, C, N);
      Order_Laws (S, B, A, C, N);
      Order_Laws (S, C, A, B, N);
      Order_Laws (S, C, B, A, N);
      Order_Laws (S, A, C, B, N);
      Order_Laws (S, B, C, A, N);
   end Equivalent_Order;

   procedure Prepend_Order (S : String; A, B : Rotation) is
      PA : constant Rotation := Previous (A);
      PB : constant Rotation := Previous (B);
   begin
      Shift_Letter (S, A, 0);
      Shift_Letter (S, B, 0);
      for K in 1 .. 2 * S'Length loop
         Shift_Letter (S, A, K - 1);
         Shift_Letter (S, B, K - 1);
         pragma Loop_Invariant
           (Equal_Prefix (S, PA, PB, K) =
             (Letter (S, A, A.Length - 1) = Letter (S, B, B.Length - 1)
               and then Equal_Prefix (S, A, B, K - 1)));
         pragma Loop_Invariant (LE (S, PA, PB, K));
      end loop;
   end Prepend_Order;

   procedure Shift_Equal (S : String; A, B : Rotation) is
   begin
      Prefix_Letter (S, A, B, 2 * S'Length, A.Length - 1);
      Order_Laws (S, A, B, A, 2 * S'Length);
      Prepend_Order (S, A, B);
      Prepend_Order (S, B, A);
      Order_Laws (S, Previous (A), Previous (B), Previous (A), 2 * S'Length);
   end Shift_Equal;

   procedure Classical_Character (S : String; Steps : Natural) is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      if Steps > 0 then
         Modulo_Period (2 * S'Length - Steps - 1, S'Length);
      end if;
   end Classical_Character;

   function Key_Less
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
     return Boolean is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      Order_Laws (S, A, B, A, 2 * S'Length);
      if Less (S, A, B) then
         return True;
      elsif Less (S, B, A) then
         return False;
      else
         return not Tie_LE (B, A, Ties);
      end if;
   end Key_Less;
end BWT.Rotations;
