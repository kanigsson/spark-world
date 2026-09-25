with BWT.Rotations;

package body BWT.Circular
  with SPARK_Mode
is
   use BWT.Rotations;

   --  Letter K of the rotation from O, without a division.
   function At_Offset (S : String; O, K : Natural) return Character
   with
     Inline,
     Pre  => Supported (S) and then O < S'Length and then K < S'Length,
     Post => At_Offset'Result = Letter (S, Rotated (S, O), K);

   function At_Offset (S : String; O, K : Natural) return Character is
   begin
      if O + K < S'Length then
         Letter_Direct (S, Rotated (S, O), K);
         return S (1 + O + K);
      else
         Letter_Wrap (S, Rotated (S, O), K);
         return S (1 + O + K - S'Length);
      end if;
   end At_Offset;

   --  The least offset found by comparing every rotation with the best so
   --  far. It only names the answer for the proof of the fast search.
   function Naive_Least (S : String) return Natural
   with
     Ghost,
     Global => null,
     Pre    => Supported (S) and then S'Length > 0,
     Post   => Is_Least_Rotation (S, Naive_Least'Result);

   function Naive_Least (S : String) return Natural is
      N    : constant Positive := S'Length;
      Best : Natural := 0;
   begin
      Order_Laws (S, Rotated (S, 0), Rotated (S, 0), Rotated (S, 0), N);
      for Q in 1 .. N - 1 loop
         pragma Loop_Invariant (Best < Q);
         pragma
           Loop_Invariant
             (for all X in 0 .. Q - 1 =>
                LE (S, Rotated (S, Best), Rotated (S, X), N));
         pragma
           Loop_Invariant
             (for all X in 0 .. Best - 1 =>
                not LE (S, Rotated (S, X), Rotated (S, Best), N));
         Order_Laws (S, Rotated (S, Best), Rotated (S, Q), Rotated (S, Q), N);
         if not LE (S, Rotated (S, Best), Rotated (S, Q), N) then
            for X in 0 .. Q - 1 loop
               Order_Laws
                 (S, Rotated (S, Q), Rotated (S, Best), Rotated (S, X), N);
               Order_Laws
                 (S, Rotated (S, Best), Rotated (S, X), Rotated (S, Q), N);
               pragma
                 Loop_Invariant
                   (for all Y in 0 .. X =>
                      LE (S, Rotated (S, Q), Rotated (S, Y), N)
                      and then not LE (S, Rotated (S, Y), Rotated (S, Q), N));
            end loop;
            Best := Q;
         end if;
      end loop;
      return Best;
   end Naive_Least;

   procedure Mod_Below (X, N : Natural)
   with Ghost, Global => null, Pre => X < N, Post => X mod N = X;

   procedure Mod_Below (X, N : Natural) is null;

   --  After a mismatch at K, the rotation from I + T is above the one from
   --  J + T, since they agree for K - T letters and then I's is larger.
   procedure Worse (S : String; I, J, K, T : Natural)
   with
     Ghost,
     Global => null,
     Pre    =>
       Supported (S)
       and then I < S'Length
       and then J < S'Length
       and then K < S'Length
       and then T <= K
       and then I + T < S'Length
       and then Equal_Prefix (S, Rotated (S, I), Rotated (S, J), K)
       and then Letter (S, Rotated (S, I), K) > Letter (S, Rotated (S, J), K),
     Post   =>
       not LE (S, Rotated (S, I + T), Skip (Rotated (S, J), T), S'Length);

   procedure Worse (S : String; I, J, K, T : Natural) is
      A : constant Rotation := Rotated (S, I);
      B : constant Rotation := Rotated (S, J);
   begin
      Decide (S, A, B, K, K + 1);
      Equal_Prefix_Shorter (S, A, B, K, T);
      Skip_Split (S, A, B, T, K + 1 - T);
      Mod_Below (I + T, S'Length);
      pragma Assert (Skip (A, T) = Rotated (S, I + T));
      pragma Assert (not LE (S, Skip (A, T), Skip (B, T), K + 1 - T));
   end Worse;

   --  The same mismatch rules out every offset from I to I + K.
   procedure Eliminate (S : String; Best, I, J, K : Natural)
   with
     Ghost,
     Global => null,
     Pre    =>
       Supported (S)
       and then Is_Least_Rotation (S, Best)
       and then I < S'Length
       and then J < S'Length
       and then K < S'Length
       and then Equal_Prefix (S, Rotated (S, I), Rotated (S, J), K)
       and then Letter (S, Rotated (S, I), K) > Letter (S, Rotated (S, J), K),
     Post   => Best not in I .. I + K;

   procedure Eliminate (S : String; Best, I, J, K : Natural) is
   begin
      for T in 0 .. K loop
         exit when I + T >= S'Length;
         Worse (S, I, J, K, T);
         pragma
           Assert
             (Skip (Rotated (S, J), T)
                = Rotated (S, Skip (Rotated (S, J), T).Offset));
         pragma Loop_Invariant (Best not in I .. I + T);
      end loop;
   end Eliminate;

   --  Two different offsets whose rotations are equal make S periodic, and
   --  only the earlier one can be the least offset.
   procedure Settle (S : String; Best, I, J : Natural)
   with
     Ghost,
     Global => null,
     Pre    =>
       Supported (S)
       and then Is_Least_Rotation (S, Best)
       and then I < S'Length
       and then J < S'Length
       and then I /= J
       and then Equal_Prefix (S, Rotated (S, I), Rotated (S, J), S'Length)
       and then (Best = I or else Best = J or else Best > Natural'Max (I, J)),
     Post   => Best = Natural'Min (I, J);

   procedure Settle (S : String; Best, I, J : Natural) is
      N  : constant Positive := S'Length;
      Lo : constant Natural := Natural'Min (I, J);
      Hi : constant Natural := Natural'Max (I, J);
      A  : constant Rotation := Rotated (S, Lo);
      B  : constant Rotation := Rotated (S, Hi);
   begin
      pragma Assert (Equal_Prefix (S, A, B, N));
      Order_Laws (S, A, B, B, N);
      if Best = Hi then
         pragma Assert (LE (S, A, B, N));
         pragma Assert (False);
      elsif Best > Hi then
         Same_Length_Extend (S, A, B, N, 2 * N);
         Equal_Prefix_Shorter (S, A, B, 2 * N, Best - Hi + N);
         Skip_Split (S, A, B, Best - Hi, N);
         Mod_Below (Lo + (Best - Hi), N);
         Mod_Below (Best, N);
         pragma Assert (Skip (A, Best - Hi) = Rotated (S, Best - (Hi - Lo)));
         pragma Assert (Skip (B, Best - Hi) = Rotated (S, Best));
         Order_Laws
           (S,
            Rotated (S, Best - (Hi - Lo)),
            Rotated (S, Best),
            Rotated (S, Best),
            N);
         pragma Assert (False);
      end if;
   end Settle;

   function Least_Rotation (S : String) return Natural is
      N    : constant Positive := S'Length;
      Best : constant Natural := Naive_Least (S)
      with Ghost;
      I    : Natural := 0;
      J    : Natural := 1;
      K    : Natural := 0;
   begin
      --  I and J are the two candidates, and their rotations agree for K
      --  letters. Every offset below the larger one, other than the
      --  smaller one, has been ruled out.
      while I < N and then J < N and then K < N loop
         pragma Loop_Invariant (I /= J);
         pragma
           Loop_Invariant
             (Equal_Prefix (S, Rotated (S, I), Rotated (S, J), K));
         pragma
           Loop_Invariant
             (Best = I or else Best = J or else Best > Natural'Max (I, J));
         pragma Loop_Variant (Increases => I + J, Increases => K);
         declare
            A : constant Character := At_Offset (S, I, K);
            B : constant Character := At_Offset (S, J, K);
         begin
            if A = B then
               K := K + 1;
            else
               if A > B then
                  Eliminate (S, Best, I, J, K);
                  I := I + K + 1;
               else
                  Eliminate (S, Best, J, I, K);
                  J := J + K + 1;
               end if;
               if I = J then
                  J := J + 1;
               end if;
               K := 0;
            end if;
         end;
      end loop;
      if K = N then
         Settle (S, Best, I, J);
      end if;
      return Natural'Min (I, J);
   end Least_Rotation;

   function Canonical (S : String) return String is
      N : constant Natural := S'Length;
   begin
      if N = 0 then
         return "";
      end if;
      declare
         O      : constant Natural := Least_Rotation (S);
         Result : String (1 .. N) := (others => Character'First);
      begin
         for X in 1 .. N loop
            Result (X) := At_Offset (S, O, X - 1);
            pragma
              Loop_Invariant
                (for all Y in 1 .. X =>
                   Result (Y) = Letter (S, Rotated (S, O), Y - 1));
         end loop;
         return Result;
      end;
   end Canonical;
end BWT.Circular;
