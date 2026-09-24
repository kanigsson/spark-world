with BWT.Factorizations;
with BWT.Lyndon_Order;
with BWT.Orders;
with BWT.Permutations;
with BWT.Ranks;
with BWT.Rotations;
with BWT.Words;

package body BWT.Bijective_Proofs
  with SPARK_Mode
is
   use BWT.Factorizations;
   use BWT.Lyndon_Order;
   use BWT.Ranks;
   use BWT.Rotations;
   use BWT.Words;

   function Pos (R : Rotation) return Natural
   is (R.First + R.Offset)
   with Pre => R.First <= Max_Length and then R.Offset <= Max_Length;

   --  The cyclic neighbours of a position within its factor.

   function Next_In (FR : Table; Q : Positive) return Positive
   is (if Q + 1 < FR (Q).First + FR (Q).Length then Q + 1 else FR (Q).First)
   with
     Pre =>
       Q in FR'Range
       and then FR'Last <= Max_Length
       and then FR (Q).First <= Max_Length
       and then FR (Q).Length <= Max_Length;

   function Prev_In (FR : Table; Q : Positive) return Positive
   is (if Q > FR (Q).First then Q - 1 else FR (Q).First + FR (Q).Length - 1)
   with
     Pre =>
       Q in FR'Range
       and then FR'Last <= Max_Length
       and then FR (Q).First <= Max_Length
       and then FR (Q).Length <= Max_Length;

   function Cyc_Fact (FR : Table; Q : Positive) return Boolean
   is (Q in FR'Range
       and then FR'Last <= Max_Length
       and then FR (Q).First <= Max_Length
       and then FR (Q).Length <= Max_Length
       and then Next_In (FR, Q) in FR'Range
       and then Prev_In (FR, Q) in FR'Range
       and then FR (Next_In (FR, Q)).First = FR (Q).First
       and then FR (Next_In (FR, Q)).Length = FR (Q).Length
       and then FR (Prev_In (FR, Q)).First = FR (Q).First
       and then FR (Prev_In (FR, Q)).Length = FR (Q).Length
       and then FR (Next_In (FR, Q)).First <= Max_Length
       and then FR (Next_In (FR, Q)).Length <= Max_Length
       and then FR (Prev_In (FR, Q)).First <= Max_Length
       and then FR (Prev_In (FR, Q)).Length <= Max_Length
       and then Prev_In (FR, Next_In (FR, Q)) = Q
       and then Next_In (FR, Prev_In (FR, Q)) = Q
       and then FR (Q).Offset < FR (Q).Length
       and then Previous (FR (Q)) = FR (Prev_In (FR, Q)));

   procedure Cyclic_At (S : String; FR : Table; Q : Positive)
   with
     Pre  => Factorization (S, FR) and then Q in FR'Range,
     Post => Cyc_Fact (FR, Q);

   procedure Cyclic_At (S : String; FR : Table; Q : Positive) is
   begin
      pragma Assert (FR (FR (Q).First).First = FR (Q).First);
      pragma
        Assert (FR (FR (Q).First + FR (Q).Length - 1).First = FR (Q).First);
   end Cyclic_At;

   procedure Cyclic_Facts (S : String; FR : Table)
   with
     Pre  => Factorization (S, FR),
     Post => (for all Q in FR'Range => Cyc_Fact (FR, Q));

   procedure Cyclic_Facts (S : String; FR : Table) is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Cyc_Fact);
   begin
      for Q in FR'Range loop
         Cyclic_At (S, FR, Q);
         pragma
           Loop_Invariant (for all P in FR'First .. Q => Cyc_Fact (FR, P));
      end loop;
   end Cyclic_Facts;

   function Find (R : Table; X : Rotation) return Positive
   with
     Pre  => (for some J in R'Range => X = R (J)),
     Post => Find'Result in R'Range and then R (Find'Result) = X;

   function Find (R : Table; X : Rotation) return Positive is
   begin
      for I in R'Range loop
         if R (I) = X then
            return I;
         end if;
         pragma Loop_Invariant (for all J in R'First .. I => R (J) /= X);
      end loop;
      return R'First;
   end Find;

   --  Where each factor rotation ended up in the sorted table.
   function Index_Of (FR, R : Table) return Mapping
   with
     Pre  =>
       FR'First = 1
       and then R'First = 1
       and then FR'Length = R'Length
       and then FR'Length <= Max_Length
       and then (for all Q in FR'Range =>
                   (for some J in R'Range => FR (Q) = R (J))),
     Post =>
       Index_Of'Result'First = 1
       and then Index_Of'Result'Length = FR'Length
       and then (for all Q in FR'Range =>
                   Index_Of'Result (Q) in R'Range
                   and then R (Index_Of'Result (Q)) = FR (Q));

   function Index_Of (FR, R : Table) return Mapping is
      Idx : Mapping (1 .. FR'Length) := (others => 1);
   begin
      for Q in FR'Range loop
         Idx (Q) := Find (R, FR (Q));
         pragma
           Loop_Invariant
             (for all P in 1 .. Q =>
                Idx (P) in R'Range and then R (Idx (P)) = FR (P));
      end loop;
      return Idx;
   end Index_Of;

   --  Each sorted row is the factor rotation starting where it starts.
   procedure Rows_Are_Factors (S : String; FR, R : Table)
   with
     Pre  =>
       Factorization (S, FR)
       and then R'First = 1
       and then R'Length = S'Length
       and then Same_Rows (R, FR),
     Post =>
       (for all I in R'Range =>
          Pos (R (I)) in FR'Range and then R (I) = FR (Pos (R (I))));

   procedure Rows_Are_Factors (S : String; FR, R : Table) is
   begin
      for I in R'Range loop
         declare
            J : constant Positive := Find (FR, R (I));
         begin
            pragma Assert (Pos (FR (J)) = J);
         end;
         pragma
           Loop_Invariant
             (for all K in 1 .. I =>
                Pos (R (K)) in FR'Range and then R (K) = FR (Pos (R (K))));
      end loop;
   end Rows_Are_Factors;

   --  The factor rotation starting at G is the least among all rotations up
   --  to the end of its factor.
   procedure Key_Min (S : String; FR : Table; G, Q : Positive)
   with
     Pre  =>
       Factorization (S, FR)
       and then G in FR'Range
       and then FR (G).Offset = 0
       and then Q in 1 .. G + FR (G).Length - 1,
     Post => Key_LE (S, FR (G), FR (Q), Later_First);

   procedure Key_Min (S : String; FR : Table; G, Q : Positive) is
      LG : constant Positive := FR (G).Length;
      A  : constant Rotation := FR (G);
      N2 : constant Natural := 2 * S'Length;
   begin
      pragma Assert (A = (G, LG, 0));
      pragma Assert (Lyndon (S, G, LG));
      if Q >= G then
         pragma Assert (FR (Q).First = G and then FR (Q).Length = LG);
         if Q = G then
            Key_Order (S, A, A, A, Later_First);
         else
            pragma Assert (FR (Q) = (G, LG, Q - G));
            Lyndon_Least (S, G, LG, Q - G);
            Order_Laws (S, A, FR (Q), A, N2);
            Key_Intro (S, A, FR (Q), Later_First);
         end if;
      else
         declare
            H  : constant Positive := FR (Q).First;
            LH : constant Positive := FR (Q).Length;
            B0 : constant Rotation := (H, LH, 0);
         begin
            pragma Assert (FR (H) = B0);
            pragma Assert (H < G);
            pragma Assert (Lyndon (S, H, LH));
            Chain_LE (S, FR, H, G);
            Lex_Total (S, G, LG, H, LH);
            if Lex_Less (S, G, LG, H, LH) then
               Lyndon_Omega (S, G, LG, H, LH);
            else
               Same_Word_Equal (S, G, H, LG);
            end if;
            Order_Laws (S, A, B0, A, N2);
            pragma Assert (LE (S, A, B0, N2));
            if Q > H then
               pragma Assert (FR (Q) = (H, LH, Q - H));
               Lyndon_Least (S, H, LH, Q - H);
               Order_Laws (S, B0, FR (Q), B0, N2);
            else
               pragma Assert (FR (Q) = B0);
               Order_Laws (S, B0, B0, B0, N2);
            end if;
            Order_Laws (S, A, B0, FR (Q), N2);
            Key_Intro (S, A, FR (Q), Later_First);
         end;
      end if;
   end Key_Min;

   --  The facts every step of the round trip shares.
   function Context (S : String; FR, R : Table; L : String) return Boolean
   is (S'Length > 0
       and then Factorization (S, FR)
       and then Well_Formed (S, R)
       and then Distinct (R)
       and then Sorted (S, R, Later_First)
       and then (for all K in R'Range =>
                   Pos (R (K)) in FR'Range and then R (K) = FR (Pos (R (K))))
       and then L'First = 1
       and then L'Length = S'Length
       and then (for all K in L'Range =>
                   L (K) = Letter (S, R (K), R (K).Length - 1)));

   --  Ranking by last letter orders the predecessor rotations strictly.
   procedure Prev_Less (S : String; FR, R : Table; L : String; I, J : Positive)
   with
     Pre  =>
       Context (S, FR, R, L)
       and then I in R'Range
       and then J in R'Range
       and then I /= J
       and then Ordered (L, I, J),
     Post => not Key_LE (S, Previous (R (J)), Previous (R (I)), Later_First);

   procedure Prev_Less (S : String; FR, R : Table; L : String; I, J : Positive)
   is
      A  : constant Rotation := R (I);
      B  : constant Rotation := R (J);
      PA : constant Rotation := Previous (A);
      PB : constant Rotation := Previous (B);
      N2 : constant Natural := 2 * S'Length;
   begin
      Shift_Letter (S, A, 0);
      Shift_Letter (S, B, 0);
      if L (I) < L (J) then
         Decide (S, PB, PA, 0, N2);
         if Key_LE (S, PB, PA, Later_First) then
            Key_Weakening (S, PB, PA, Later_First);
         end if;
      else
         pragma Assert (L (I) = L (J) and then I < J);
         pragma Assert (Key_LE (S, A, B, Later_First));
         Key_Weakening (S, A, B, Later_First);
         if Key_LE (S, PB, PA, Later_First) then
            Key_Weakening (S, PB, PA, Later_First);
            Unprepend (S, B, A);
            Order_Laws (S, A, B, A, N2);
            Prepend_Order (S, A, B);
            Order_Laws (S, PA, PB, PA, N2);
            Order_Laws (S, PB, PA, PB, N2);
            Key_Tie (S, A, B, Later_First);
            Key_Tie (S, PB, PA, Later_First);
            pragma Assert (Pos (A) /= Pos (B));
            pragma Assert (Pos (A) > Pos (B));
            if A.First = B.First then
               pragma Assert (FR (Pos (B)).Length = A.Length);
               Primitive (S, A.First, A.Length, A.Offset, B.Offset);
            end if;
            pragma Assert (A.First /= B.First);
            pragma
              Assert (if A.First <= Pos (B) then FR (Pos (B)).First = A.First);
            pragma Assert (A.First > Pos (B));
            pragma Assert (FR (A.First).First = A.First);
            pragma
              Assert
                (if A.First <= B.First + B.Length - 1
                   then FR (A.First).First = B.First);
            pragma Assert (A.First >= B.First + B.Length);
            pragma Assert (Pos (PA) > Pos (PB));
         end if;
      end if;
   end Prev_Less;

   --  The row of each row's predecessor rotation.
   function Pred_Index (FR, R : Table; Idx : Mapping) return Mapping
   with
     Pre  =>
       FR'First = 1
       and then FR'Length <= Max_Length
       and then R'First = 1
       and then R'Length = FR'Length
       and then Idx'First = 1
       and then Idx'Length = FR'Length
       and then (for all Q in FR'Range =>
                   FR (Q).First <= Max_Length
                   and then FR (Q).Length <= Max_Length
                   and then FR (Q).Offset < FR (Q).Length
                   and then Prev_In (FR, Q) in FR'Range
                   and then Previous (FR (Q)) = FR (Prev_In (FR, Q)))
       and then (for all Q in FR'Range =>
                   Idx (Q) in R'Range and then R (Idx (Q)) = FR (Q))
       and then (for all K in R'Range =>
                   R (K).First <= Max_Length
                   and then R (K).Offset <= Max_Length
                   and then Pos (R (K)) in FR'Range
                   and then R (K) = FR (Pos (R (K)))),
     Post =>
       Pred_Index'Result'First = 1
       and then Pred_Index'Result'Length = R'Length
       and then (for all K in R'Range =>
                   Pred_Index'Result (K) in R'Range
                   and then Pred_Index'Result (K)
                            = Idx (Prev_In (FR, Pos (R (K))))
                   and then R (Pred_Index'Result (K)) = Previous (R (K)));

   function Pred_Index (FR, R : Table; Idx : Mapping) return Mapping is
      P : Mapping (1 .. R'Length) := (others => 1);
   begin
      for K in P'Range loop
         P (K) := Idx (Prev_In (FR, Pos (R (K))));
         pragma
           Loop_Invariant
             (for all J in 1 .. K => P (J) = Idx (Prev_In (FR, Pos (R (J)))));
      end loop;
      for K in P'Range loop
         pragma Assert (P (K) in R'Range);
         pragma Assert (R (P (K)) = Previous (R (K)));
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                P (J) in R'Range and then R (P (J)) = Previous (R (J)));
      end loop;
      return P;
   end Pred_Index;

   --  The plain facts inside Context, for bodies that keep it opaque.
   procedure Unpack (S : String; FR, R : Table; L : String)
   with
     Pre  => Context (S, FR, R, L),
     Post =>
       Supported (S)
       and then S'Length > 0
       and then Supported (L)
       and then L'Length = S'Length
       and then FR'First = 1
       and then FR'Length = S'Length
       and then R'First = 1
       and then R'Length = S'Length
       and then (for all Q in FR'Range =>
                   FR (Q).First <= Max_Length
                   and then FR (Q).Length <= Max_Length
                   and then FR (Q).Offset < FR (Q).Length
                   and then Prev_In (FR, Q) in FR'Range
                   and then Previous (FR (Q)) = FR (Prev_In (FR, Q)))
       and then (for all K in R'Range =>
                   R (K).First <= Max_Length
                   and then R (K).Offset <= Max_Length
                   and then Pos (R (K)) in FR'Range
                   and then R (K) = FR (Pos (R (K))));

   procedure Unpack (S : String; FR, R : Table; L : String) is
   begin
      Cyclic_Facts (S, FR);
   end Unpack;

   --  Consecutive LF ranks have increasing predecessor rows.
   procedure Pair_Step
     (S : String; FR, R : Table; L : String; Map, P : Mapping; I, J : Positive)
   with
     Pre  =>
       Context (S, FR, R, L)
       and then P'First = 1
       and then P'Length = S'Length
       and then I in R'Range
       and then J in R'Range
       and then I /= J
       and then Ordered (L, I, J)
       and then P (I) in R'Range
       and then P (J) in R'Range
       and then R (P (I)) = Previous (R (I))
       and then R (P (J)) = Previous (R (J)),
     Post => P (I) < P (J);

   procedure Pair_Step
     (S : String; FR, R : Table; L : String; Map, P : Mapping; I, J : Positive)
   is
   begin
      Prev_Less (S, FR, R, L, I, J);
      pragma
        Assert
          (if P (J) <= P (I)
             then Key_LE (S, R (P (J)), R (P (I)), Later_First));
   end Pair_Step;

   function Compose (P, Inv : Mapping) return Mapping
   with
     Pre  =>
       P'First = 1
       and then Inv'First = 1
       and then P'Length = Inv'Length
       and then P'Length <= Max_Length
       and then (for all A in Inv'Range => Inv (A) in P'Range)
       and then (for all K in P'Range => P (K) in P'Range),
     Post =>
       Compose'Result'First = 1
       and then Compose'Result'Length = P'Length
       and then (for all A in Inv'Range =>
                   Compose'Result (A) = P (Inv (A))
                   and then Compose'Result (A) in P'Range);

   function Compose (P, Inv : Mapping) return Mapping is
      Q : Mapping (1 .. P'Length) := (others => 1);
   begin
      for A in Q'Range loop
         Q (A) := P (Inv (A));
         pragma
           Loop_Invariant
             (for all B in 1 .. A =>
                Q (B) = P (Inv (B)) and then Q (B) in P'Range);
      end loop;
      return Q;
   end Compose;

   procedure Get_Ordered (L : String; Map : Mapping; I, J : Positive)
   with
     Pre  =>
       Supported (L)
       and then Map'First = 1
       and then Map'Length = L'Length
       and then (for all A in L'Range =>
                   (for all B in L'Range =>
                      Ordered (L, A, B) = (Map (A) <= Map (B))))
       and then I in L'Range
       and then J in L'Range,
     Post => Ordered (L, I, J) = (Map (I) <= Map (J));

   procedure Get_Ordered (L : String; Map : Mapping; I, J : Positive) is null;

   --  The LF map is exact on the bijective table: it moves each row to the
   --  row of the rotation starting one position earlier in its factor.
   procedure Exact_LF
     (S : String; FR, R : Table; L : String; Map, Idx : Mapping)
   with
     Pre  =>
       Context (S, FR, R, L)
       and then Map'First = 1
       and then Map'Length = S'Length
       and then Permutation (Map)
       and then (for all A in L'Range =>
                   (for all B in L'Range =>
                      Ordered (L, A, B) = (Map (A) <= Map (B))))
       and then Idx'First = 1
       and then Idx'Length = S'Length
       and then (for all Q in FR'Range =>
                   Idx (Q) in R'Range and then R (Idx (Q)) = FR (Q)),
     Post =>
       (for all K in R'Range => Map (K) = Idx (Prev_In (FR, Pos (R (K)))));

   procedure Exact_LF
     (S : String; FR, R : Table; L : String; Map, Idx : Mapping)
   is
      N   : constant Positive := Map'Length;
      Inv : constant Mapping := Permutations.Inverse (Map);
   begin
      Unpack (S, FR, R, L);
      declare
         P : constant Mapping := Pred_Index (FR, R, Idx);
      begin
         for A in 1 .. N - 1 loop
            pragma
              Assert (Map (Inv (A)) = A and then Map (Inv (A + 1)) = A + 1);
            Get_Ordered (L, Map, Inv (A), Inv (A + 1));
            pragma Assert (Ordered (L, Inv (A), Inv (A + 1)));
            Pair_Step (S, FR, R, L, Map, P, Inv (A), Inv (A + 1));
            pragma
              Loop_Invariant
                (for all B in 1 .. A => P (Inv (B)) < P (Inv (B + 1)));
         end loop;
         declare
            Q : constant Mapping := Compose (P, Inv);
         begin
            Permutations.Increasing_Identity (Q);
            pragma Assert (for all K in 1 .. N => Q (Map (K)) = P (K));
         end;
      end;
   end Exact_LF;

   --  The facts about the order the round trip predicts.
   function Model
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping) return Boolean
   is (S'Length > 0
       and then Factorization (S, FR)
       and then Well_Formed (S, R)
       and then Distinct (R)
       and then Sorted (S, R, Later_First)
       and then (for all K in R'Range =>
                   Pos (R (K)) in FR'Range and then R (K) = FR (Pos (R (K))))
       and then Map'First = 1
       and then Map'Length = S'Length
       and then Idx'First = 1
       and then Idx'Length = S'Length
       and then (for all Q in FR'Range =>
                   Idx (Q) in R'Range and then R (Idx (Q)) = FR (Q))
       and then (for all K in R'Range =>
                   Map (K) = Idx (Prev_In (FR, Pos (R (K)))))
       and then W'First = 1
       and then W'Length = S'Length
       and then Inv'First = 1
       and then Inv'Length = S'Length
       and then (for all P in W'Range => W (P) = Idx (Next_In (FR, P)))
       and then (for all K in Inv'Range =>
                   Inv (K) = Prev_In (FR, Pos (R (K)))));

   --  No row before the one of the factor starting at G was written before
   --  position P, the position after that factor.
   procedure Model_Start
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping; P : Positive)
   with
     Pre  =>
       Model (S, FR, R, Map, Idx, W, Inv)
       and then P in 2 .. S'Length
       and then FR (P).First = P,
     Post => (for all Y in 1 .. W (P - 1) - 1 => Inv (Y) >= P);

   procedure Model_Start
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping; P : Positive)
   is
      G : constant Positive := FR (P - 1).First;
   begin
      Cyclic_Facts (S, FR);
      pragma Assert (FR (G).Offset = 0);
      pragma Assert (G + FR (G).Length = P);
      pragma Assert (Next_In (FR, P - 1) = G);
      pragma Assert (W (P - 1) = Idx (G));
      for Y in 1 .. Idx (G) - 1 loop
         declare
            X : constant Positive := Pos (R (Y));
         begin
            if Inv (Y) < P then
               pragma Assert (X < P);
               Key_Min (S, FR, G, X);
               pragma Assert (Key_LE (S, R (Y), R (Idx (G)), Later_First));
               Key_Antisym (S, FR (G), R (Y), Later_First);
               pragma Assert (R (Y) = R (Idx (G)));
            end if;
         end;
         pragma Loop_Invariant (for all Z in 1 .. Y => Inv (Z) >= P);
      end loop;
   end Model_Start;

   --  The decoder's rule for position P holds for the predicted order.
   procedure Model_At
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping; P : Positive)
   with
     Pre  => Model (S, FR, R, Map, Idx, W, Inv) and then P in 2 .. S'Length,
     Post => Orders.Rule (Map, W, Inv, P);

   procedure Model_At
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping; P : Positive) is
   begin
      Cyclic_Facts (S, FR);
      pragma Assert (Map (W (P)) = Idx (P));
      pragma Assert (Inv (Idx (P)) = Prev_In (FR, P));
      if P > FR (P).First then
         pragma Assert (Next_In (FR, P - 1) = P);
      else
         Model_Start (S, FR, R, Map, Idx, W, Inv, P);
      end if;
   end Model_At;

   procedure Rules (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping)
   with
     Pre  => Model (S, FR, R, Map, Idx, W, Inv),
     Post => (for all P in 2 .. S'Length => Orders.Rule (Map, W, Inv, P));

   procedure Rules (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping) is
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Orders.Rule);
   begin
      for P in 2 .. S'Length loop
         Model_At (S, FR, R, Map, Idx, W, Inv, P);
         pragma
           Loop_Invariant
             (for all Q in 2 .. P => Orders.Rule (Map, W, Inv, Q));
      end loop;
   end Rules;

   procedure Inverse_At
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping; K : Positive)
   with
     Pre  => Model (S, FR, R, Map, Idx, W, Inv) and then K in 1 .. S'Length,
     Post =>
       K in W'Range
       and then K in Inv'Range
       and then W (K) in Inv'Range
       and then Inv (K) in W'Range
       and then Inv (W (K)) = K
       and then W (Inv (K)) = K;

   procedure Inverse_At
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping; K : Positive) is
   begin
      Cyclic_At (S, FR, K);
      Cyclic_At (S, FR, Pos (R (K)));
      Cyclic_At (S, FR, Next_In (FR, K));
      pragma Assert (Idx (Pos (R (K))) = K);
      pragma Assert (Pos (R (Idx (Next_In (FR, K)))) = Next_In (FR, K));
   end Inverse_At;

   procedure Model_Inverse
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping)
   with
     Pre  => Model (S, FR, R, Map, Idx, W, Inv),
     Post =>
       (for all K in 1 .. S'Length =>
          K in W'Range
          and then K in Inv'Range
          and then W (K) in Inv'Range
          and then Inv (K) in W'Range
          and then Inv (W (K)) = K
          and then W (Inv (K)) = K);

   procedure Model_Inverse
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Model);
   begin
      for K in 1 .. S'Length loop
         Inverse_At (S, FR, R, Map, Idx, W, Inv, K);
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                J in W'Range
                and then J in Inv'Range
                and then W (J) in Inv'Range
                and then Inv (J) in W'Range
                and then Inv (W (J)) = J
                and then W (Inv (J)) = J);
      end loop;
   end Model_Inverse;

   --  The predicted order is the decoder's visiting order.
   procedure Model_Order
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping)
   with
     Pre  => Model (S, FR, R, Map, Idx, W, Inv),
     Post => Orders.Is_Order (Map, W, Inv);

   procedure Model_Order
     (S : String; FR, R : Table; Map, Idx, W, Inv : Mapping)
   is
      N : constant Positive := S'Length;
      G : constant Positive := FR (N).First;
   begin
      Cyclic_Facts (S, FR);
      Model_Inverse (S, FR, R, Map, Idx, W, Inv);
      --  The last factor's Lyndon rotation is the least row.
      pragma Assert (Next_In (FR, N) = G);
      pragma Assert (FR (G).Offset = 0);
      if Idx (G) > 1 then
         Key_Min (S, FR, G, Pos (R (1)));
         Key_Antisym (S, FR (G), R (1), Later_First);
         pragma Assert (R (1) = R (Idx (G)));
      end if;
      pragma Assert (W (N) = 1);
      pragma Assert (for all P in W'Range => W (P) in Inv'Range);
      pragma Assert (for all K in Inv'Range => Inv (K) in W'Range);
      Rules (S, FR, R, Map, Idx, W, Inv);
   end Model_Order;

   --  The letter before the rotation starting after Q is the letter at Q.
   procedure Last_Letter (S : String; FR : Table; Q : Positive)
   with
     Pre  => Factorization (S, FR) and then Q in FR'Range,
     Post =>
       Next_In (FR, Q) in FR'Range
       and then Letter
                  (S, FR (Next_In (FR, Q)), FR (Next_In (FR, Q)).Length - 1)
                = S (Q);

   procedure Last_Letter (S : String; FR : Table; Q : Positive) is
      X : Positive;
   begin
      Cyclic_Facts (S, FR);
      X := Next_In (FR, Q);
      if X = FR (Q).First then
         pragma Assert (FR (X).Offset = 0);
         Letter_Direct (S, FR (X), FR (X).Length - 1);
      else
         pragma Assert (FR (X).Offset >= 1);
         Letter_Wrap (S, FR (X), FR (X).Length - 1);
      end if;
   end Last_Letter;

   function Next_Rows (FR : Table; Idx : Mapping) return Mapping
   with
     Pre  =>
       FR'First = 1
       and then FR'Length <= Max_Length
       and then Idx'First = 1
       and then Idx'Length = FR'Length
       and then (for all Q in FR'Range =>
                   FR (Q).First <= Max_Length
                   and then FR (Q).Length <= Max_Length
                   and then Next_In (FR, Q) in FR'Range),
     Post =>
       Next_Rows'Result'First = 1
       and then Next_Rows'Result'Length = FR'Length
       and then (for all P in FR'Range =>
                   Next_Rows'Result (P) = Idx (Next_In (FR, P)));

   function Next_Rows (FR : Table; Idx : Mapping) return Mapping is
      W : Mapping (1 .. FR'Length) := (others => 1);
   begin
      for P in W'Range loop
         W (P) := Idx (Next_In (FR, P));
         pragma
           Loop_Invariant
             (for all Q in 1 .. P => W (Q) = Idx (Next_In (FR, Q)));
      end loop;
      return W;
   end Next_Rows;

   function Written_At (FR, R : Table) return Mapping
   with
     Pre  =>
       FR'First = 1
       and then FR'Length <= Max_Length
       and then R'First = 1
       and then R'Length = FR'Length
       and then (for all K in R'Range =>
                   R (K).First <= Max_Length
                   and then R (K).Offset <= Max_Length
                   and then Pos (R (K)) in FR'Range
                   and then FR (Pos (R (K))).First <= Max_Length
                   and then FR (Pos (R (K))).Length <= Max_Length),
     Post =>
       Written_At'Result'First = 1
       and then Written_At'Result'Length = R'Length
       and then (for all K in R'Range =>
                   Written_At'Result (K) = Prev_In (FR, Pos (R (K))));

   function Written_At (FR, R : Table) return Mapping is
      Inv : Mapping (1 .. R'Length) := (others => 1);
   begin
      for K in Inv'Range loop
         Inv (K) := Prev_In (FR, Pos (R (K)));
         pragma
           Loop_Invariant
             (for all J in 1 .. K => Inv (J) = Prev_In (FR, Pos (R (J))));
      end loop;
      return Inv;
   end Written_At;

   --  With the model order in hand, the decoder writes back S.
   procedure Decode_Model
     (S : String; FR, R : Table; L : String; Idx : Mapping)
   with
     Pre  =>
       Context (S, FR, R, L)
       and then Supported (L)
       and then Idx'First = 1
       and then Idx'Length = S'Length
       and then (for all Q in FR'Range =>
                   Idx (Q) in R'Range and then R (Idx (Q)) = FR (Q))
       and then (for all K in R'Range =>
                   LF (L) (K) = Idx (Prev_In (FR, Pos (R (K))))),
     Post => Bijective.Decode (L) = S;

   procedure Decode_Model
     (S : String; FR, R : Table; L : String; Idx : Mapping)
   is
      N   : constant Positive := S'Length;
      Map : constant Mapping := LF (L);
   begin
      Cyclic_Facts (S, FR);
      declare
         W     : constant Mapping := Next_Rows (FR, Idx);
         Inv   : constant Mapping := Written_At (FR, R);
         Order : constant Mapping := Bijective.Decode_Order (L);
         T     : constant String := Bijective.Decode (L);
      begin
         Model_Order (S, FR, R, Map, Idx, W, Inv);
         Orders.Order_Unique
           (Map, Order, Permutations.Inverse (Order), W, Inv);
         for P in 1 .. N loop
            Last_Letter (S, FR, P);
            pragma Assert (T (P) = L (Order (P)));
            pragma Assert (Order (P) = W (P));
            pragma Assert (R (W (P)) = FR (Next_In (FR, P)));
            pragma Assert (L (W (P)) = S (P));
            pragma Loop_Invariant (for all Q in 1 .. P => T (Q) = S (Q));
         end loop;
      end;
   end Decode_Model;

   procedure Round_Trip (S : String) is
   begin
      if S'Length = 0 then
         return;
      end if;
      declare
         N   : constant Positive := S'Length;
         FR  : constant Table := Bijective.Factor_Rotations (S);
         R   : constant Table := Bijective.Table_Of (S);
         L   : constant String := Bijective.Encode (S);
         Map : constant Mapping := LF (L);
         Idx : constant Mapping := Index_Of (FR, R);
      begin
         Rows_Are_Factors (S, FR, R);
         Cyclic_Facts (S, FR);
         Exact_LF (S, FR, R, L, Map, Idx);
         Decode_Model (S, FR, R, L, Idx);
      end;
   end Round_Trip;

   procedure LF_Exact (S : String) is
   begin
      if S'Length = 0 then
         return;
      end if;
      declare
         FR  : constant Table := Bijective.Factor_Rotations (S);
         R   : constant Table := Bijective.Table_Of (S);
         L   : constant String := Bijective.Encode (S);
         Map : constant Mapping := LF (L);
         Idx : constant Mapping := Index_Of (FR, R);
      begin
         Rows_Are_Factors (S, FR, R);
         Cyclic_Facts (S, FR);
         Exact_LF (S, FR, R, L, Map, Idx);
         for K in R'Range loop
            pragma Assert (Cyc_Fact (FR, Pos (R (K))));
            pragma Assert (R (Map (K)) = FR (Prev_In (FR, Pos (R (K)))));
            pragma Assert (FR (Prev_In (FR, Pos (R (K)))) = Previous (R (K)));
            pragma
              Loop_Invariant
                (for all J in 1 .. K => R (Map (J)) = Previous (R (J)));
         end loop;
      end;
   end LF_Exact;
end BWT.Bijective_Proofs;
