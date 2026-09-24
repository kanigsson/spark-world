with BWT.Permutations;
with BWT.Ranks;
with BWT.Rotations;

package body BWT.Search
  with SPARK_Mode
is
   use BWT.Ranks;
   use BWT.Rotations;

   ---------------------------------------------------------------------------
   --  The search itself, on the last column alone
   ---------------------------------------------------------------------------

   --  A naive rank: one scan of the column.
   function Step (Last : String; C : Character; T : Natural) return Natural
   with
     Pre  => Supported (Last),
     Post => Step'Result = Hits (Step_Flags (Last, C, T), Last'Length);

   function Step (Last : String; C : Character; T : Natural) return Natural is
      Result : Natural := 0;
   begin
      for I in Last'Range loop
         if Last (I) < C or else (Last (I) = C and then I <= T) then
            Result := Result + 1;
         end if;
         pragma Loop_Invariant (Result = Hits (Step_Flags (Last, C, T), I));
      end loop;
      return Result;
   end Step;

   --  Setting more flags never lowers the count.
   procedure Hits_Mono (A, B : Flags; N : Natural)
   with
     Ghost,
     Pre  =>
       A'First = 1
       and then B'First = 1
       and then A'Length = N
       and then B'Length = N
       and then N <= Max_Length
       and then (for all I in 1 .. N => (if A (I) then B (I))),
     Post => Hits (A, N) <= Hits (B, N);

   procedure Hits_Mono (A, B : Flags; N : Natural) is
   begin
      for T in 1 .. N loop
         pragma Loop_Invariant (Hits (A, T) <= Hits (B, T));
      end loop;
   end Hits_Mono;

   function Count (Last, P : String) return Natural is
      Lo : Natural := 0;
      Hi : Natural := Last'Length;
   begin
      for J in reverse P'Range loop
         pragma Loop_Invariant (Lo = Bound (Last, P, J + 1, True));
         pragma Loop_Invariant (Hi = Bound (Last, P, J + 1, False));
         pragma Loop_Invariant (Lo <= Hi);
         Hits_Mono
           (Step_Flags (Last, P (J), Lo),
            Step_Flags (Last, P (J), Hi),
            Last'Length);
         Lo := Step (Last, P (J), Lo);
         Hi := Step (Last, P (J), Hi);
      end loop;
      return Hi - Lo;
   end Count;

   ---------------------------------------------------------------------------
   --  Counting lemmas
   ---------------------------------------------------------------------------

   --  How many of B (1 .. Through) are set where Mask is.
   function Hits_Masked (Mask, B : Flags; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else
         Hits_Masked (Mask, B, Through - 1)
         + (if Mask (Through) and then B (Through) then 1 else 0))
   with
     Ghost,
     Pre                =>
       Mask'First = 1
       and then B'First = 1
       and then Mask'Length = B'Length
       and then B'Length <= Max_Length
       and then Through <= B'Length,
     Post               => Hits_Masked'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   procedure Masked_Empty (Mask, B : Flags)
   with
     Ghost,
     Pre  =>
       Mask'First = 1
       and then B'First = 1
       and then Mask'Length = B'Length
       and then B'Length <= Max_Length
       and then (for all M of Mask => not M),
     Post => Hits_Masked (Mask, B, B'Length) = 0;

   procedure Masked_Empty (Mask, B : Flags) is
   begin
      for T in 1 .. B'Length loop
         pragma Loop_Invariant (Hits_Masked (Mask, B, T) = 0);
      end loop;
   end Masked_Empty;

   procedure Masked_Full (Mask, B : Flags)
   with
     Ghost,
     Pre  =>
       Mask'First = 1
       and then B'First = 1
       and then Mask'Length = B'Length
       and then B'Length <= Max_Length
       and then (for all M of Mask => M),
     Post => Hits_Masked (Mask, B, B'Length) = Hits (B, B'Length);

   procedure Masked_Full (Mask, B : Flags) is
   begin
      for T in 1 .. B'Length loop
         pragma Loop_Invariant (Hits_Masked (Mask, B, T) = Hits (B, T));
      end loop;
   end Masked_Full;

   procedure Masked_Mark (Before, After, B : Flags; Q : Positive)
   with
     Ghost,
     Pre  =>
       Before'First = 1
       and then After'First = 1
       and then B'First = 1
       and then Before'Length = B'Length
       and then After'Length = B'Length
       and then B'Length <= Max_Length
       and then Q in B'Range
       and then not Before (Q)
       and then After (Q)
       and then (for all I in B'Range =>
                   (if I /= Q then After (I) = Before (I))),
     Post =>
       Hits_Masked (After, B, B'Length)
       = Hits_Masked (Before, B, B'Length) + (if B (Q) then 1 else 0);

   procedure Masked_Mark (Before, After, B : Flags; Q : Positive) is
   begin
      for T in 1 .. B'Length loop
         pragma
           Loop_Invariant
             (Hits_Masked (After, B, T)
                = Hits_Masked (Before, B, T)
                  + (if Q <= T and then B (Q) then 1 else 0));
      end loop;
   end Masked_Mark;

   --  Counting is invariant under renumbering.
   procedure Count_Perm (A, B : Flags; Sigma : Mapping)
   with
     Ghost,
     Pre  =>
       Permutation (Sigma)
       and then A'First = 1
       and then B'First = 1
       and then A'Length = Sigma'Length
       and then B'Length = Sigma'Length
       and then (for all I in A'Range => A (I) = B (Sigma (I))),
     Post => Hits (A, A'Length) = Hits (B, B'Length);

   procedure Count_Perm (A, B : Flags; Sigma : Mapping) is
      N      : constant Natural := Sigma'Length;
      Seen   : Flags (1 .. N) := (others => False);
      Before : Flags (1 .. N) := (others => False);
      Inv    : constant Mapping := Permutations.Inverse (Sigma);
   begin
      Masked_Empty (Seen, B);
      for I in 1 .. N loop
         Before := Seen;
         pragma
           Assert
             (not Before (Sigma (I))
                or else (for some K in 1 .. I - 1 => Sigma (K) = Sigma (I)));
         Seen (Sigma (I)) := True;
         Masked_Mark (Before, Seen, B, Sigma (I));
         pragma Loop_Invariant (Hits (A, I) = Hits_Masked (Seen, B, N));
         pragma
           Loop_Invariant
             (for all Q in 1 .. N =>
                Seen (Q) = (for some K in 1 .. I => Sigma (K) = Q));
      end loop;
      for Q in 1 .. N loop
         pragma Assert (Inv (Q) in 1 .. N and then Sigma (Inv (Q)) = Q);
         pragma Assert (for some K in 1 .. N => Sigma (K) = Q);
         pragma Loop_Invariant (for all R in 1 .. Q => Seen (R));
      end loop;
      Masked_Full (Seen, B);
   end Count_Perm;

   --  A downward-closed set of rows is the rows up to its size.
   procedure Prefix_Set (D : Flags)
   with
     Ghost,
     Pre  =>
       D'First = 1
       and then D'Length <= Max_Length
       and then (for all I in D'Range =>
                   (for all J in I .. D'Last => (if D (J) then D (I)))),
     Post => (for all I in D'Range => D (I) = (I <= Hits (D, D'Length)));

   procedure Prefix_Set (D : Flags) is
   begin
      for T in 1 .. D'Length loop
         pragma
           Loop_Invariant (for all I in 1 .. T => D (I) = (I <= Hits (D, T)));
         pragma
           Loop_Invariant
             (Hits (D, T) = T
                or else (for all I in Hits (D, T) + 1 .. D'Last => not D (I)));
      end loop;
   end Prefix_Set;

   --  The rows between two bounds.
   procedure Interval (M : Flags; Lo, Hi : Natural)
   with
     Ghost,
     Pre  =>
       M'First = 1
       and then M'Length <= Max_Length
       and then Lo <= Hi
       and then Hi <= M'Length
       and then (for all I in M'Range => M (I) = (I <= Hi and then I > Lo)),
     Post => Hits (M, M'Length) = Hi - Lo;

   procedure Interval (M : Flags; Lo, Hi : Natural) is
   begin
      for T in 1 .. M'Length loop
         pragma
           Loop_Invariant
             (Hits (M, T)
                = (if T <= Lo then 0 elsif T <= Hi then T - Lo else Hi - Lo));
      end loop;
   end Interval;

   ---------------------------------------------------------------------------
   --  Rows against a pattern
   ---------------------------------------------------------------------------

   function Pattern_Fits (P : String; J : Positive; K : Natural) return Boolean
   is (P'First = 1
       and then P'Length <= 2 * Max_Length
       and then K <= P'Length
       and then J - 1 <= P'Length - K);

   --  R's first K letters are below P (J .. J + K - 1), or are at most that
   --  when not Strict.
   function Below_Pattern
     (S      : String;
      R      : Rotation;
      P      : String;
      J      : Positive;
      K      : Natural;
      Strict : Boolean) return Boolean
   is (if K = 0
       then not Strict
       else
         Letter (S, R, 0) < P (J)
         or else (Letter (S, R, 0) = P (J)
                  and then Below_Pattern
                             (S, Next_Rot (R), P, J + 1, K - 1, Strict)))
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (R, S'Length)
       and then Pattern_Fits (P, J, K),
     Subprogram_Variant => (Decreases => K);

   --  Below the pattern, and not strictly, is being the pattern.
   procedure Exact
     (S : String; R : Rotation; P : String; J : Positive; K : Natural)
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (R, S'Length)
       and then Pattern_Fits (P, J, K),
     Post               =>
       (Below_Pattern (S, R, P, J, K, False)
        and then not Below_Pattern (S, R, P, J, K, True))
       = (for all X in J .. J + K - 1 => Letter (S, R, X - J) = P (X)),
     Subprogram_Variant => (Decreases => K);

   procedure Exact
     (S : String; R : Rotation; P : String; J : Positive; K : Natural) is
   begin
      if K > 0 then
         Exact (S, Next_Rot (R), P, J + 1, K - 1);
         for X in J + 1 .. J + K - 1 loop
            Letter_Next (S, R, X - J - 1);
            pragma
              Loop_Invariant
                (for all Y in J + 1 .. X =>
                   Letter (S, R, Y - J) = Letter (S, Next_Rot (R), Y - J - 1));
         end loop;
      end if;
   end Exact;

   procedure Strict_Weak
     (S : String; R : Rotation; P : String; J : Positive; K : Natural)
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (R, S'Length)
       and then Pattern_Fits (P, J, K)
       and then Below_Pattern (S, R, P, J, K, True),
     Post               => Below_Pattern (S, R, P, J, K, False),
     Subprogram_Variant => (Decreases => K);

   procedure Strict_Weak
     (S : String; R : Rotation; P : String; J : Positive; K : Natural) is
   begin
      if K > 0 and then Letter (S, R, 0) = P (J) then
         Strict_Weak (S, Next_Rot (R), P, J + 1, K - 1);
      end if;
   end Strict_Weak;

   --  A row below another on K letters stays below any bound the other is.
   procedure Mono
     (S      : String;
      A, B   : Rotation;
      P      : String;
      J      : Positive;
      K      : Natural;
      Strict : Boolean)
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Pattern_Fits (P, J, K)
       and then LE (S, A, B, K)
       and then Below_Pattern (S, B, P, J, K, Strict),
     Post               => Below_Pattern (S, A, P, J, K, Strict),
     Subprogram_Variant => (Decreases => K);

   procedure Mono
     (S      : String;
      A, B   : Rotation;
      P      : String;
      J      : Positive;
      K      : Natural;
      Strict : Boolean) is
   begin
      if K > 0 then
         Order_Next (S, A, B, K - 1);
         if Letter (S, A, 0) = Letter (S, B, 0)
           and then Letter (S, B, 0) = P (J)
         then
            Mono (S, Next_Rot (A), Next_Rot (B), P, J + 1, K - 1, Strict);
         end if;
      end if;
   end Mono;

   procedure LE_Shorter (S : String; A, B : Rotation; H, K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then H <= 4 * Max_Length
       and then K <= H
       and then LE (S, A, B, H),
     Post => LE (S, A, B, K);

   procedure LE_Shorter (S : String; A, B : Rotation; H, K : Natural) is
   begin
      null;
   end LE_Shorter;

   ---------------------------------------------------------------------------
   --  Positions of a cycle table, and rows of a sorted one
   ---------------------------------------------------------------------------

   function Next_Pos (S : String; F : Table; Q : Positive) return Positive
   is (F (Q).First + Next_Rot (F (Q)).Offset)
   with
     Ghost,
     Pre  =>
       Supported (S) and then Doubling.Cycles (S, F) and then Q in F'Range,
     Post =>
       Next_Pos'Result in F'Range
       and then F (Next_Pos'Result) = Next_Rot (F (Q));

   function Prev_Pos (S : String; F : Table; Q : Positive) return Positive
   is (F (Q).First + Previous (F (Q)).Offset)
   with
     Ghost,
     Pre  =>
       Supported (S) and then Doubling.Cycles (S, F) and then Q in F'Range,
     Post =>
       Prev_Pos'Result in F'Range
       and then F (Prev_Pos'Result) = Previous (F (Q))
       and then Next_Pos (S, F, Prev_Pos'Result) = Q;

   --  The table hypotheses of Count_Rows.
   function Tabled
     (S : String; F, Rows : Table; Ties : Tie_Order; Last : String)
      return Boolean
   is (Doubling.Cycles (S, F)
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, F)
       and then Sorted (S, Rows, Ties)
       and then Last'First = 1
       and then Last'Length = S'Length
       and then (for all I in Last'Range =>
                   Last (I) = Letter (S, Rows (I), Rows (I).Length - 1)))
   with Ghost, Pre => Supported (S);

   --  Where each row starts in S.
   function Positions (S : String; Rows : Table) return Mapping
   is ([for I in 1 .. Rows'Length => Rows (I).First + Rows (I).Offset])
   with Ghost, Pre => Well_Formed (S, Rows);

   procedure Rows_At (S : String; F, Rows : Table)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Doubling.Cycles (S, F)
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, F),
     Post =>
       Permutation (Positions (S, Rows))
       and then Positions (S, Rows)'Length = S'Length
       and then (for all I in Rows'Range =>
                   Rows (I) = F (Positions (S, Rows) (I)));

   procedure Rows_At (S : String; F, Rows : Table) is
      Pos : constant Mapping := Positions (S, Rows);
   begin
      for I in Rows'Range loop
         pragma
           Assert
             (for some Q in F'Range => Rows (I) = F (Q) and then Q = Pos (I));
         pragma Loop_Invariant (for all J in 1 .. I => Rows (J) = F (Pos (J)));
      end loop;
   end Rows_At;

   ---------------------------------------------------------------------------
   --  One backward step
   ---------------------------------------------------------------------------

   function Characterized
     (S      : String;
      Rows   : Table;
      Last   : String;
      P      : String;
      J      : Positive;
      Strict : Boolean) return Boolean
   is (for all I in Rows'Range =>
         (I <= Bound (Last, P, J, Strict))
         = Below_Pattern (S, Rows (I), P, J, P'Length + 1 - J, Strict))
   with
     Ghost,
     Pre =>
       Well_Formed (S, Rows)
       and then Supported (Last)
       and then P'First = 1
       and then P'Length <= 2 * S'Length
       and then J <= P'Length + 1;

   procedure Step_Lemma
     (S       : String;
      F, Rows : Table;
      Ties    : Tie_Order;
      Last    : String;
      P       : String;
      J       : Positive;
      Strict  : Boolean)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Tabled (S, F, Rows, Ties, Last)
       and then P'First = 1
       and then P'Length <= 2 * S'Length
       and then J <= P'Length
       and then Characterized (S, Rows, Last, P, J + 1, Strict),
     Post => Characterized (S, Rows, Last, P, J, Strict);

   procedure Step_Lemma
     (S       : String;
      F, Rows : Table;
      Ties    : Tie_Order;
      Last    : String;
      P       : String;
      J       : Positive;
      Strict  : Boolean)
   is
      N     : constant Positive := S'Length;
      K     : constant Natural := P'Length - J;
      T     : constant Natural := Bound (Last, P, J + 1, Strict);
      C     : constant Character := P (J);
      A     : constant Flags := Step_Flags (Last, C, T);
      B     : constant Flags (1 .. N) :=
        [for Q in 1 .. N => Below_Pattern (S, F (Q), P, J, K + 1, Strict)];
      D     : constant Flags (1 .. N) :=
        [for I in 1 .. N => Below_Pattern (S, Rows (I), P, J, K + 1, Strict)];
      Pos   : constant Mapping := Positions (S, Rows);
      Prior : Mapping (1 .. N) := (others => 1);
   begin
      Rows_At (S, F, Rows);
      --  Row I ends in the letter before its start, and reading on from that
      --  letter is reading row I.
      for I in 1 .. N loop
         Prior (I) := Prev_Pos (S, F, Pos (I));
         Shift_Letter (S, Rows (I), 0);
         Letter_Direct (S, F (Prior (I)), 0);
         pragma Assert (F (Prior (I)) = Previous (Rows (I)));
         pragma Assert (Next_Rot (F (Prior (I))) = Rows (I));
         pragma Assert (Last (I) = Letter (S, F (Prior (I)), 0));
         pragma Assert (A (I) = B (Prior (I)));
         pragma
           Loop_Invariant
             (for all L in 1 .. I =>
                Prior (L) = Prev_Pos (S, F, Pos (L))
                and then A (L) = B (Prior (L)));
      end loop;
      pragma
        Assert
          (for all I in 1 .. N =>
             (for all L in 1 .. N =>
                (if Prior (I) = Prior (L)
                 then
                   Next_Pos (S, F, Prior (I)) = Next_Pos (S, F, Prior (L))
                   and then Pos (I) = Pos (L)
                   and then I = L)));
      pragma Assert (Permutation (Prior));
      Count_Perm (A, B, Prior);
      pragma Assert (for all I in 1 .. N => D (I) = B (Pos (I)));
      Count_Perm (D, B, Pos);
      --  Sorted rows fall below a bound in a prefix of the table.
      for I in 1 .. N loop
         for L in I .. N loop
            Key_Weakening (S, Rows (I), Rows (L), Ties);
            LE_Shorter (S, Rows (I), Rows (L), 2 * N, K + 1);
            if D (L) then
               Mono (S, Rows (I), Rows (L), P, J, K + 1, Strict);
            end if;
            pragma
              Loop_Invariant (for all M in I .. L => (if D (M) then D (I)));
         end loop;
         pragma
           Loop_Invariant
             (for all H in 1 .. I =>
                (for all M in H .. N => (if D (M) then D (H))));
      end loop;
      Prefix_Set (D);
      pragma Assert (Bound (Last, P, J, Strict) = Hits (A, N));
   end Step_Lemma;

   ---------------------------------------------------------------------------
   --  The theorems
   ---------------------------------------------------------------------------

   procedure Count_Rows
     (S : String; F, Rows : Table; Ties : Tie_Order; Last, P : String)
   is
      M : constant Natural := P'Length;
   begin
      if S'Length = 0 then
         pragma Assert (Count (Last, P) = 0);
         pragma Assert (Occurrences (S, F, P) = 0);
         return;
      end if;
      pragma Assert (Tabled (S, F, Rows, Ties, Last));
      pragma Assert (Characterized (S, Rows, Last, P, M + 1, True));
      pragma Assert (Characterized (S, Rows, Last, P, M + 1, False));
      for J in reverse 1 .. M loop
         Step_Lemma (S, F, Rows, Ties, Last, P, J, True);
         Step_Lemma (S, F, Rows, Ties, Last, P, J, False);
         pragma Loop_Invariant (Characterized (S, Rows, Last, P, J, True));
         pragma Loop_Invariant (Characterized (S, Rows, Last, P, J, False));
      end loop;
      declare
         N     : constant Positive := S'Length;
         Lo    : constant Natural := Bound (Last, P, 1, True);
         Hi    : constant Natural := Bound (Last, P, 1, False);
         Match : constant Flags (1 .. N) :=
           [for I in 1 .. N => Occurs (S, Rows (I), P)];
         Pos   : constant Mapping := Positions (S, Rows);
      begin
         pragma Assert (Count (Last, P) = Hi - Lo);
         for I in 1 .. N loop
            Exact (S, Rows (I), P, 1, M);
            pragma Assert (Match (I) = (I <= Hi and then I > Lo));
            pragma
              Loop_Invariant
                (for all L in 1 .. I => Match (L) = (L <= Hi and then L > Lo));
         end loop;
         Interval (Match, Lo, Hi);
         Rows_At (S, F, Rows);
         pragma
           Assert
             (for all I in 1 .. N =>
                Match (I) = Occurrence_Flags (S, F, P) (Pos (I)));
         Count_Perm (Match, Occurrence_Flags (S, F, P), Pos);
      end;
   end Count_Rows;

   procedure Classical_Count (S, P : String) is
      Rows : constant Table := Classical_Rows (S);
      Rots : constant Table := Rotations_Of (S);
      E    : constant Classical_Result := Classical_Encode (S);
   begin
      pragma Assert (Doubling.Cycles (S, Rots));
      for I in Rows'Range loop
         pragma Assert (for some Q in Rots'Range => Rows (I) = Rots (Q));
         pragma
           Loop_Invariant (for all L in 1 .. I => Rows (L).Length = S'Length);
      end loop;
      Count_Rows (S, Rots, Rows, Earlier_First, E.Last, P);
   end Classical_Count;

   procedure Bijective_Count (S, P : String) is
   begin
      Count_Rows
        (S,
         Lyndon_Factors (S),
         Bijective_Rows (S),
         Later_First,
         Bijective_Encode (S),
         P);
   end Bijective_Count;
end BWT.Search;
