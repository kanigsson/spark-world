package body BWT.Rotations
  with SPARK_Mode
is
   procedure Previous_Injective (A, B : Rotation) is
   begin
      null;
   end Previous_Injective;

   procedure Modulo_Period (X : Natural; P : Positive)
   with
     Ghost,
     Pre  => X <= 5 * Max_Length and then P <= X,
     Post => X mod P = (X - P) mod P;

   procedure Modulo_Period (X : Natural; P : Positive) is
   begin
      pragma Assert (X / P = (X - P) / P + 1);
   end Modulo_Period;

   procedure Equal_Same (S : String; A, B : Rotation; Size : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      null;
   end Equal_Same;

   procedure Period (S : String; A : Rotation; K : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      Modulo_Period (A.Offset + K, A.Length);
   end Period;

   procedure Shift_Letter (S : String; R : Rotation; K : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
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
         pragma Loop_Invariant (LE (S, A, B, K) or LE (S, B, A, K));
         pragma
           Loop_Invariant
             ((LE (S, A, B, K) and LE (S, B, A, K))
                = Equal_Prefix (S, A, B, K));
         pragma
           Loop_Invariant
             (if LE (S, A, B, Size) and LE (S, B, C, Size)
                then
                  LE (S, A, C, K)
                  and then (if Equal_Prefix (S, A, C, K)
                            then
                              Equal_Prefix (S, A, B, K)
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
         pragma
           Assert
             (Letter (S, B, K - A.Length)
                = Letter (S, B, K - A.Length - B.Length));
         pragma
           Assert
             (Letter (S, A, K - B.Length)
                = Letter (S, A, K - A.Length - B.Length));
         pragma
           Assert (Letter (S, A, K - A.Length) = Letter (S, B, K - A.Length));
         pragma
           Assert (Letter (S, A, K - B.Length) = Letter (S, B, K - B.Length));
         pragma
           Assert
             (Letter (S, A, K - A.Length - B.Length)
                = Letter (S, B, K - A.Length - B.Length));
         pragma Assert (Letter (S, A, K) = Letter (S, B, K));
      end loop;
   end Extend_Equality;

   procedure Decide (S : String; A, B : Rotation; K, Size : Natural) is
   begin
      for N in K + 1 .. Size loop
         pragma Loop_Invariant (not Equal_Prefix (S, A, B, N));
         pragma
           Loop_Invariant
             (LE (S, A, B, N) = (Letter (S, A, K) < Letter (S, B, K)));
      end loop;
   end Decide;

   procedure Letter_Direct (S : String; R : Rotation; K : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      null;
   end Letter_Direct;

   procedure Letter_Wrap (S : String; R : Rotation; K : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      pragma Assert ((R.Offset + K) mod R.Length = R.Offset + K - R.Length);
   end Letter_Wrap;

   procedure Letter_Advance (S : String; R : Rotation; D, K : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
      A : constant Rotation := Advance (R, D);
   begin
      if R.Offset + D >= R.Length then
         Modulo_Period (R.Offset + K, R.Length);
         pragma Assert (A.Offset + (K - D) = R.Offset + K - R.Length);
      end if;
   end Letter_Advance;

   procedure Letter_Next (S : String; R : Rotation; K : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      if R.Offset + 1 = R.Length then
         Modulo_Period (R.Offset + K + 1, R.Length);
      end if;
   end Letter_Next;

   procedure Order_Next (S : String; A, B : Rotation; K : Natural) is
      NA : constant Rotation := Next_Rot (A);
      NB : constant Rotation := Next_Rot (B);
   begin
      for J in 0 .. K loop
         pragma
           Loop_Invariant
             (Equal_Prefix (S, A, B, J + 1)
                = (Letter (S, A, 0) = Letter (S, B, 0)
                   and then Equal_Prefix (S, NA, NB, J))
                and then LE (S, A, B, J + 1)
                         = (Letter (S, A, 0) < Letter (S, B, 0)
                            or else (Letter (S, A, 0) = Letter (S, B, 0)
                                     and then LE (S, NA, NB, J))));
         if J < K then
            Letter_Next (S, A, J);
            Letter_Next (S, B, J);
         end if;
      end loop;
   end Order_Next;

   --  Removing whole periods leaves the remainder.
   procedure Modulo_Periods (X : Natural; P : Positive; Q : Natural)
   with
     Ghost,
     Pre  =>
       X <= 5 * Max_Length
       and then Long_Long_Integer (Q) * Long_Long_Integer (P)
                <= Long_Long_Integer (X),
     Post => X mod P = (X - Q * P) mod P;

   procedure Modulo_Periods (X : Natural; P : Positive; Q : Natural) is
      Y : Natural := X;
   begin
      for I in 1 .. Q loop
         pragma Loop_Invariant (Y = X - (I - 1) * P);
         pragma Loop_Invariant (X mod P = Y mod P);
         pragma
           Loop_Invariant
             (Long_Long_Integer (Q - I + 1) * Long_Long_Integer (P)
                <= Long_Long_Integer (Y));
         Modulo_Period (Y, P);
         Y := Y - P;
      end loop;
      pragma Assert (Y = X - Q * P);
   end Modulo_Periods;

   procedure Letter_Skip (S : String; R : Rotation; D, K : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
      Q : constant Natural := (R.Offset + D) / R.Length;
   begin
      pragma
        Assert ((R.Offset + D) mod R.Length = R.Offset + D - Q * R.Length);
      pragma Assert (Q * R.Length <= R.Offset + K);
      Modulo_Periods (R.Offset + K, R.Length, Q);
      pragma
        Assert (Skip (R, D).Offset + (K - D) = R.Offset + K - Q * R.Length);
   end Letter_Skip;

   procedure Skip_Unskip (R : Rotation; D : Natural) is
      L  : constant Positive := R.Length;
      M  : constant Natural := D mod L;
      Up : constant Positive := R.Offset + (L - M);
      Q1 : constant Natural := Up / L;
      QD : constant Natural := D / L;
      X  : constant Natural := Unskip (R, D).Offset + D;
   begin
      pragma Assert (Q1 <= 1);
      pragma Assert (Unskip (R, D).Offset = Up - Q1 * L);
      pragma Assert (D = QD * L + M);
      pragma Assert (X = R.Offset + (1 - Q1 + QD) * L);
      Modulo_Periods (X, L, 1 - Q1 + QD);
      pragma Assert (R.Offset mod L = R.Offset);
   end Skip_Unskip;

   procedure Skip_Split (S : String; A, B : Rotation; H, M : Natural) is
      NA : constant Rotation := Skip (A, H);
      NB : constant Rotation := Skip (B, H);
   begin
      for J in 0 .. M loop
         pragma
           Loop_Invariant
             (Equal_Prefix (S, A, B, H + J)
                = (Equal_Prefix (S, A, B, H)
                   and then Equal_Prefix (S, NA, NB, J))
                and then LE (S, A, B, H + J)
                         = ((LE (S, A, B, H)
                             and then not Equal_Prefix (S, A, B, H))
                            or else (Equal_Prefix (S, A, B, H)
                                     and then LE (S, NA, NB, J))));
         if J < M then
            Letter_Skip (S, A, H, H + J);
            Letter_Skip (S, B, H, H + J);
         end if;
      end loop;
   end Skip_Split;

   procedure Settled (S : String; A, B : Rotation; H, Size : Natural) is
   begin
      if Equal_Prefix (S, A, B, H) then
         Equal_Prefix_Shorter (S, A, B, H, A.Length + B.Length);
         Extend_Equality (S, A, B, Size);
         Order_Laws (S, A, B, A, H);
         Order_Laws (S, A, B, A, Size);
      else
         declare
            K : constant Natural := Mismatch (S, A, B, H);
         begin
            if K >= A.Length + B.Length then
               Equal_Prefix_Shorter (S, A, B, K, A.Length + B.Length);
               Extend_Equality (S, A, B, H);
            end if;
            pragma Assert (K < Size);
            Decide (S, A, B, K, H);
            Decide (S, A, B, K, Size);
         end;
      end if;
   end Settled;

   function Mismatch
     (S : String; A, B : Rotation; Size : Natural) return Natural is
   begin
      for K in 0 .. Size - 1 loop
         pragma Loop_Invariant (Equal_Prefix (S, A, B, K));
         pragma Loop_Invariant (Equal_Prefix (S, B, A, K));
         if Letter (S, A, K) /= Letter (S, B, K) then
            return K;
         end if;
      end loop;
      return Size;
   end Mismatch;

   function Less (S : String; A, B : Rotation) return Boolean is
   begin
      --  A common comparison horizon makes order laws independent of the
      --  lengths. Extend_Equality justifies the shorter p + q stopping bound.
      for K in 0 .. 2 * S'Length - 1 loop
         pragma Loop_Invariant (Equal_Prefix (S, A, B, K));
         pragma Loop_Invariant (Equal_Prefix (S, B, A, K));
         if Letter (S, A, K) /= Letter (S, B, K) then
            Decide (S, B, A, K, 2 * S'Length);
            return Letter (S, A, K) < Letter (S, B, K);
         end if;
      end loop;
      return False;
   end Less;

   procedure Key_Order
     (S : String; A, B, C : Rotation; Ties : Tie_Order := Earlier_First)
   is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      Order_Laws (S, A, B, C, 2 * S'Length);
      Order_Laws (S, B, C, A, 2 * S'Length);
      Order_Laws (S, C, A, B, 2 * S'Length);
   end Key_Order;

   procedure Key_Weakening
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      null;
   end Key_Weakening;

   procedure Key_Intro
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      null;
   end Key_Intro;

   procedure Key_Tie
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      null;
   end Key_Tie;

   procedure Key_Antisym
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
   begin
      Order_Laws (S, A, B, A, 2 * S'Length);
      Order_Laws (S, B, A, B, 2 * S'Length);
   end Key_Antisym;

   procedure Equal_Prefix_Shorter (S : String; A, B : Rotation; H, K : Natural)
   is
   begin
      if K < H then
         Equal_Prefix_Shorter (S, A, B, H - 1, K);
      end if;
   end Equal_Prefix_Shorter;

   procedure Same_Length_Extend
     (S : String; A, B : Rotation; H, Size : Natural) is
   begin
      if Size <= H then
         Equal_Prefix_Shorter (S, A, B, H, Size);
      else
         for K in H .. Size - 1 loop
            pragma Loop_Invariant (Equal_Prefix (S, A, B, K));
            Period (S, A, K);
            Period (S, B, K);
            Prefix_Letter (S, A, B, K, K - A.Length);
         end loop;
      end if;
   end Same_Length_Extend;

   procedure Equal_Horizon (S : String; A, B : Rotation) is
   begin
      if A.Length + B.Length <= 2 * S'Length - 1 then
         Equal_Prefix_Shorter (S, A, B, 2 * S'Length - 1, A.Length + B.Length);
         Extend_Equality (S, A, B, 2 * S'Length);
      else
         pragma Assert (A.Length = S'Length and then B.Length = S'Length);
         Same_Length_Extend (S, A, B, 2 * S'Length - 1, 2 * S'Length);
      end if;
   end Equal_Horizon;

   procedure Unprepend (S : String; A, B : Rotation) is
      PA : constant Rotation := Previous (A);
      PB : constant Rotation := Previous (B);
      N  : constant Natural := 2 * S'Length;
   begin
      Shift_Letter (S, A, 0);
      Shift_Letter (S, B, 0);
      for K in 0 .. N - 1 loop
         pragma
           Loop_Invariant
             (LE (S, PA, PB, K + 1) = LE (S, A, B, K)
                and then Equal_Prefix (S, PA, PB, K + 1)
                         = Equal_Prefix (S, A, B, K));
         if K + 1 < N then
            Shift_Letter (S, A, K + 1);
            Shift_Letter (S, B, K + 1);
         end if;
      end loop;
      pragma Assert (LE (S, A, B, N - 1));
      if Equal_Prefix (S, A, B, N - 1) then
         Equal_Horizon (S, A, B);
         Order_Laws (S, A, B, A, N);
      end if;
   end Unprepend;

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
         pragma
           Loop_Invariant
             (Equal_Prefix (S, PA, PB, K)
                = (Letter (S, A, A.Length - 1) = Letter (S, B, B.Length - 1)
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
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Letter);
   begin
      if Steps > 0 then
         Modulo_Period (2 * S'Length - Steps - 1, S'Length);
      end if;
   end Classical_Character;

   function Key_Less
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
      return Boolean
   is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Key_LE);
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
