with BWT.Rotations;

package body BWT.Lyndon_Order
  with SPARK_Mode
is
   use BWT.Rotations;

   procedure Lyndon_Least (S : String; F, L, O : Positive) is
      A : constant Rotation := (F, L, 0);
      B : constant Rotation := (F, L, O);
      D : constant Natural := Common (S, F, F + O, L - O);
   begin
      pragma Assert (Below_Suffix (S, F, L, F + O));
      pragma Assert (D < L - O);
      for K in 0 .. D - 1 loop
         pragma Loop_Invariant (Equal_Prefix (S, B, A, K));
         Letter_Direct (S, A, K);
         Letter_Direct (S, B, K);
      end loop;
      Letter_Direct (S, A, D);
      Letter_Direct (S, B, D);
      Decide (S, B, A, D, 2 * S'Length);
   end Lyndon_Least;

   --  Every proper suffix of V, followed by V forever, lies above U forever,
   --  when U is a proper prefix of the Lyndon word V.
   procedure Suffix_Above
     (S : String; UF, N, VF, M, O : Positive; E : out Natural)
   with
     Pre                =>
       In_Word (S, UF, N)
       and then In_Word (S, VF, M)
       and then Lyndon (S, VF, M)
       and then N < M
       and then Same (S, UF, VF, N)
       and then O < M,
     Post               =>
       E < M - O
       and then Equal_Prefix (S, (VF, M, O), (UF, N, 0), E)
       and then Letter (S, (UF, N, 0), E) < Letter (S, (VF, M, O), E),
     Subprogram_Variant => (Decreases => M - O);

   procedure Suffix_Above
     (S : String; UF, N, VF, M, O : Positive; E : out Natural)
   is
      U  : constant Rotation := (UF, N, 0);
      V  : constant Rotation := (VF, M, O);
      Y  : constant Positive := VF + O;
      DV : constant Natural := Common (S, VF, Y, M - O);
      C  : constant Natural := Common (S, UF, Y, Natural'Min (N, M - O));
   begin
      pragma Assert (Below_Suffix (S, VF, M, Y));
      pragma Assert (DV < M - O);
      if C < Natural'Min (N, M - O) then
         pragma
           Assert
             (if DV < C
                then
                  S (UF + DV) = S (VF + DV) and then S (UF + DV) = S (Y + DV));
         pragma
           Assert
             (if DV > C
                then S (UF + C) = S (VF + C) and then S (VF + C) = S (Y + C));
         pragma Assert (DV = C);
         E := C;
         for K in 0 .. C - 1 loop
            pragma Loop_Invariant (Equal_Prefix (S, V, U, K));
            Letter_Direct (S, U, K);
            Letter_Direct (S, V, K);
         end loop;
         Letter_Direct (S, U, C);
         Letter_Direct (S, V, C);
      elsif M - O <= N then
         for X in VF .. VF + (M - O) - 1 loop
            pragma Assert (S (X - VF + UF) = S (X));
            pragma Assert (S (X - VF + UF) = S (X - VF + Y));
            pragma
              Loop_Invariant (for all Z in VF .. X => S (Z) = S (Z - VF + Y));
         end loop;
         pragma Assert (Same (S, VF, Y, M - O));
         pragma Assert (Common (S, VF, Y, M - O) = M - O);
         E := 0;
      else
         declare
            E2 : Natural;
            W  : constant Rotation := (VF, M, O + N);
         begin
            Suffix_Above (S, UF, N, VF, M, O + N, E2);
            E := N + E2;
            for K in 0 .. E - 1 loop
               pragma Loop_Invariant (Equal_Prefix (S, V, U, K));
               if K < N then
                  Letter_Direct (S, U, K);
                  Letter_Direct (S, V, K);
               else
                  Period (S, U, K);
                  Letter_Advance (S, V, N, K);
                  pragma Assert (Advance (V, N) = W);
                  Prefix_Letter (S, W, U, E2, K - N);
               end if;
            end loop;
            Period (S, U, E);
            Letter_Advance (S, V, N, E);
            pragma Assert (Advance (V, N) = W);
         end;
      end if;
   end Suffix_Above;

   procedure Lyndon_Omega (S : String; UF, N, VF, M : Positive) is
      U : constant Rotation := (UF, N, 0);
      V : constant Rotation := (VF, M, 0);
      D : constant Natural := Common (S, UF, VF, Natural'Min (N, M));
   begin
      if D < Natural'Min (N, M) then
         for K in 0 .. D - 1 loop
            pragma Loop_Invariant (Equal_Prefix (S, V, U, K));
            Letter_Direct (S, U, K);
            Letter_Direct (S, V, K);
         end loop;
         Letter_Direct (S, U, D);
         Letter_Direct (S, V, D);
         Decide (S, V, U, D, 2 * S'Length);
      else
         pragma Assert (N < M);
         pragma Assert (Same (S, UF, VF, N));
         declare
            E2 : Natural;
            W  : constant Rotation := (VF, M, N);
            E  : Natural;
         begin
            Suffix_Above (S, UF, N, VF, M, N, E2);
            E := N + E2;
            for K in 0 .. E - 1 loop
               pragma Loop_Invariant (Equal_Prefix (S, V, U, K));
               if K < N then
                  Letter_Direct (S, U, K);
                  Letter_Direct (S, V, K);
               else
                  Period (S, U, K);
                  Letter_Advance (S, V, N, K);
                  pragma Assert (Advance (V, N) = W);
                  Prefix_Letter (S, W, U, E2, K - N);
               end if;
            end loop;
            Period (S, U, E);
            Letter_Advance (S, V, N, E);
            pragma Assert (Advance (V, N) = W);
            Decide (S, V, U, E, 2 * S'Length);
         end;
      end if;
   end Lyndon_Omega;

   --  One suffix of a word that precedes its other rotations.
   procedure Least_Suffix (S : String; F, L, O : Positive)
   with
     Pre  =>
       In_Word (S, F, L)
       and then O < L
       and then (for all Q in 1 .. L - 1 =>
                   Omega_Less (S, (F, L, 0), (F, L, Q))),
     Post => Below_Suffix (S, F, L, F + O);

   procedure Least_Suffix (S : String; F, L, O : Positive) is
      A : constant Rotation := (F, L, 0);
      B : constant Rotation := (F, L, O);
      E : constant Natural := Mismatch (S, A, B, 2 * S'Length);
   begin
      pragma Assert (Omega_Less (S, A, B));
      if E = 2 * S'Length then
         Order_Laws (S, A, B, A, 2 * S'Length);
      end if;
      pragma Assert (E < 2 * S'Length);
      Decide (S, B, A, E, 2 * S'Length);
      pragma Assert (Letter (S, A, E) < Letter (S, B, E));
      if E >= L then
         Period (S, A, E);
         Period (S, B, E);
         Prefix_Letter (S, A, B, E, E - L);
      end if;
      pragma Assert (E < L);
      if E >= L - O then
         --  Then the rotation by L - O would precede A.
         declare
            T : constant Natural := E - (L - O);
            C : constant Rotation := (F, L, L - O);
         begin
            for K in 0 .. T - 1 loop
               pragma Loop_Invariant (Equal_Prefix (S, C, A, K));
               Letter_Direct (S, C, K);
               Letter_Direct (S, A, K);
               Prefix_Letter (S, A, B, E, L - O + K);
               Letter_Direct (S, A, L - O + K);
               Letter_Wrap (S, B, L - O + K);
            end loop;
            Letter_Direct (S, C, T);
            Letter_Direct (S, A, T);
            Letter_Direct (S, A, E);
            Letter_Wrap (S, B, E);
            pragma Assert (Letter (S, C, T) < Letter (S, A, T));
            Decide (S, C, A, T, 2 * S'Length);
            pragma Assert (Omega_Less (S, A, C));
         end;
      end if;
      pragma Assert (E < L - O);
      for K in 0 .. E - 1 loop
         pragma Loop_Invariant (Same (S, F, F + O, K));
         Prefix_Letter (S, A, B, E, K);
         Letter_Direct (S, A, K);
         Letter_Direct (S, B, K);
      end loop;
      Letter_Direct (S, A, E);
      Letter_Direct (S, B, E);
      pragma Assert (Common (S, F, F + O, L - O) = E);
   end Least_Suffix;

   procedure Least_Lyndon (S : String; F, L : Positive) is
   begin
      for O in 1 .. L - 1 loop
         Least_Suffix (S, F, L, O);
         pragma
           Loop_Invariant
             (for all X in F + 1 .. F + O => Below_Suffix (S, F, L, X));
      end loop;
   end Least_Lyndon;

   procedure Primitive_Ordered (S : String; F, L, A, B : Natural)
   with
     Pre  =>
       In_Word (S, F, L)
       and then F >= 1
       and then Lyndon (S, F, L)
       and then A < B
       and then B < L,
     Post => not Equal_Prefix (S, (F, L, A), (F, L, B), 2 * S'Length);

   procedure Primitive_Ordered (S : String; F, L, A, B : Natural) is
      RA : constant Rotation := (F, L, A);
      RB : constant Rotation := (F, L, B);
   begin
      if A = 0 then
         Lyndon_Least (S, F, L, B);
         Order_Laws (S, RA, RB, RA, 2 * S'Length);
      elsif Equal_Prefix (S, RA, RB, 2 * S'Length) then
         declare
            D  : constant Positive := L - A;
            XA : constant Rotation := (F, L, 0);
            XB : constant Rotation := (F, L, B - A);
         begin
            for K in 0 .. L - 1 loop
               pragma Loop_Invariant (Equal_Prefix (S, XA, XB, K));
               Letter_Advance (S, RA, D, K + D);
               Letter_Advance (S, RB, D, K + D);
               pragma Assert (Advance (RA, D) = XA);
               pragma Assert (Advance (RB, D) = XB);
               Prefix_Letter (S, RA, RB, 2 * S'Length, K + D);
            end loop;
            Same_Length_Extend (S, XA, XB, L, 2 * S'Length);
            Lyndon_Least (S, F, L, B - A);
            Order_Laws (S, XA, XB, XA, 2 * S'Length);
         end;
      end if;
   end Primitive_Ordered;

   procedure Primitive (S : String; F, L, A, B : Natural) is
   begin
      if A < B then
         Primitive_Ordered (S, F, L, A, B);
      else
         Primitive_Ordered (S, F, L, B, A);
         Order_Laws (S, (F, L, A), (F, L, B), (F, L, A), 2 * S'Length);
         Order_Laws (S, (F, L, B), (F, L, A), (F, L, B), 2 * S'Length);
      end if;
   end Primitive;

   procedure Same_Word_Equal (S : String; G, H, L : Positive) is
      A : constant Rotation := (G, L, 0);
      B : constant Rotation := (H, L, 0);
   begin
      for K in 0 .. L - 1 loop
         pragma Loop_Invariant (Equal_Prefix (S, A, B, K));
         Letter_Direct (S, A, K);
         Letter_Direct (S, B, K);
      end loop;
      Same_Length_Extend (S, A, B, L, 2 * S'Length);
   end Same_Word_Equal;
end BWT.Lyndon_Order;
