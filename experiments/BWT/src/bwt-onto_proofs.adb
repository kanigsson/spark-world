with BWT.Factorizations;
with BWT.Lyndon_Order;
with BWT.Orders;
with BWT.Permutations;
with BWT.Ranks;
with BWT.Rotations;
with BWT.Sorting;
with BWT.Words;

package body BWT.Onto_Proofs
  with SPARK_Mode
is
   use BWT.Factorizations;
   use BWT.Lyndon_Order;
   use BWT.Ranks;
   use BWT.Rotations;
   use BWT.Words;

   ---------------------------------------------------------------------------
   --  Rows ordered by first letter, then by their successors

   --  Row I reads the periodic word of Rot (I), which starts with F (I) and
   --  continues with the word of row Psi (I). Rows are ordered by first
   --  letter, and rows with equal first letters by their successors.
   function Row_Model
     (T : String; Rot : Table; Psi : Mapping; F : String) return Boolean
   is (Supported (T)
       and then T'Length > 0
       and then Rot'First = 1
       and then Rot'Length = T'Length
       and then Psi'First = 1
       and then Psi'Length = T'Length
       and then F'First = 1
       and then F'Length = T'Length
       and then (for all I in Rot'Range => Valid (Rot (I), T'Length))
       and then (for all I in Psi'Range => Psi (I) in Psi'Range)
       and then (for all I in Rot'Range => Letter (T, Rot (I), 0) = F (I))
       and then (for all I in Rot'Range => Next_Rot (Rot (I)) = Rot (Psi (I)))
       and then (for all I in Rot'Range =>
                   (for all J in I + 1 .. Rot'Last =>
                      F (I) <= F (J)
                      and then (if F (I) = F (J) then Psi (I) < Psi (J)))));

   function Ordered_Upto (T : String; Rot : Table; K : Natural) return Boolean
   is (Supported (T)
       and then K <= 4 * Max_Length
       and then Rot'Last <= Max_Length
       and then (for all I in Rot'Range =>
                   Valid (Rot (I), T'Length)
                   and then (for all J in I + 1 .. Rot'Last =>
                               Valid (Rot (J), T'Length)
                               and then LE (T, Rot (I), Rot (J), K))));

   procedure Pair_Next
     (T : String; Rot : Table; Psi : Mapping; F : String; I, J, K : Natural)
   with
     Pre  =>
       Row_Model (T, Rot, Psi, F)
       and then K < 2 * T'Length
       and then I in Rot'Range
       and then J in I + 1 .. Rot'Last
       and then Ordered_Upto (T, Rot, K),
     Post => LE (T, Rot (I), Rot (J), K + 1);

   procedure Pair_Next
     (T : String; Rot : Table; Psi : Mapping; F : String; I, J, K : Natural) is
   begin
      Order_Next (T, Rot (I), Rot (J), K);
      if F (I) = F (J) then
         pragma Assert (LE (T, Rot (Psi (I)), Rot (Psi (J)), K));
      end if;
   end Pair_Next;

   --  Rows are in periodic order.
   procedure Monotone (T : String; Rot : Table; Psi : Mapping; F : String)
   with
     Pre  => Row_Model (T, Rot, Psi, F),
     Post => Ordered_Upto (T, Rot, 2 * T'Length);

   procedure Monotone (T : String; Rot : Table; Psi : Mapping; F : String) is
   begin
      for K in 0 .. 2 * T'Length - 1 loop
         pragma Loop_Invariant (Ordered_Upto (T, Rot, K));
         for I in Rot'Range loop
            for J in I + 1 .. Rot'Last loop
               Pair_Next (T, Rot, Psi, F, I, J, K);
               pragma
                 Loop_Invariant
                   (for all Q in I + 1 .. J =>
                      LE (T, Rot (I), Rot (Q), K + 1));
            end loop;
            pragma
              Loop_Invariant
                (for all P in 1 .. I =>
                   Valid (Rot (P), T'Length)
                   and then (for all Q in P + 1 .. Rot'Last =>
                               Valid (Rot (Q), T'Length)
                               and then LE (T, Rot (P), Rot (Q), K + 1)));
         end loop;
      end loop;
   end Monotone;

   --  The row reached after D forward steps.
   function Fwd (Psi : Mapping; I : Positive; D : Natural) return Positive
   is (if D = 0 then I else Psi (Fwd (Psi, I, D - 1)))
   with
     Pre                =>
       Psi'First = 1
       and then Psi'Length <= Max_Length
       and then I in Psi'Range
       and then (for all K in Psi'Range => Psi (K) in Psi'Range)
       and then D <= 4 * Max_Length,
     Post               => Fwd'Result in Psi'Range,
     Subprogram_Variant => (Decreases => D),
     Annotate           => (GNATprove, Hide_Info, "Expression_Function_Body");

   procedure Fwd_Step (Psi : Mapping; I : Positive; D : Natural)
   with
     Pre  =>
       Psi'First = 1
       and then Psi'Length <= Max_Length
       and then I in Psi'Range
       and then (for all K in Psi'Range => Psi (K) in Psi'Range)
       and then D < 4 * Max_Length,
     Post =>
       Fwd (Psi, I, 0) = I
       and then Fwd (Psi, I, D + 1) = Psi (Fwd (Psi, I, D));

   procedure Fwd_Step (Psi : Mapping; I : Positive; D : Natural) is
      pragma
        Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Fwd);
   begin
      null;
   end Fwd_Step;

   --  Rows that agree for D letters stay in order for D steps.
   procedure Preserve
     (T : String; Rot : Table; Psi : Mapping; F : String; I, J, D : Natural)
   with
     Pre  =>
       Row_Model (T, Rot, Psi, F)
       and then I in Rot'Range
       and then J in I + 1 .. Rot'Last
       and then D <= 2 * T'Length
       and then Equal_Prefix (T, Rot (I), Rot (J), D),
     Post => Fwd (Psi, I, D) < Fwd (Psi, J, D);

   procedure Preserve
     (T : String; Rot : Table; Psi : Mapping; F : String; I, J, D : Natural) is
   begin
      Fwd_Step (Psi, I, 0);
      Fwd_Step (Psi, J, 0);
      for K in 0 .. D - 1 loop
         pragma Loop_Invariant (Fwd (Psi, I, K) < Fwd (Psi, J, K));
         pragma
           Loop_Invariant
             (Equal_Prefix
                (T, Rot (Fwd (Psi, I, K)), Rot (Fwd (Psi, J, K)), D - K));
         declare
            A : constant Positive := Fwd (Psi, I, K);
            B : constant Positive := Fwd (Psi, J, K);
         begin
            Order_Next (T, Rot (A), Rot (B), D - K - 1);
            pragma Assert (F (A) = F (B));
            pragma Assert (Psi (A) < Psi (B));
            Fwd_Step (Psi, I, K);
            Fwd_Step (Psi, J, K);
         end;
      end loop;
   end Preserve;

   ---------------------------------------------------------------------------
   --  The blocks the decoder writes

   --  Position P continues the block of P - 1: the decoder reached the row it
   --  wrote at P - 1 by following Map from the row at P.
   function Cont (Map, W, IW : Mapping; P : Positive) return Boolean
   is (IW (Map (W (P))) < P)
   with Pre => Orders.Is_Order (Map, W, IW) and then P in W'Range;

   function Block_Starts (Map, W, IW : Mapping) return Mapping
   with
     Pre  => Orders.Is_Order (Map, W, IW),
     Post =>
       Block_Starts'Result'First = 1
       and then Block_Starts'Result'Length = W'Length
       and then (for all P in W'Range => Block_Starts'Result (P) in 1 .. P)
       and then (if W'Length > 0 then Block_Starts'Result (1) = 1)
       and then (for all P in 2 .. W'Last =>
                   Block_Starts'Result (P)
                   = (if Cont (Map, W, IW, P)
                      then Block_Starts'Result (P - 1)
                      else P));

   function Block_Starts (Map, W, IW : Mapping) return Mapping is
      BS : Mapping (1 .. W'Length) := (others => 1);
   begin
      for P in 2 .. W'Last loop
         BS (P) := (if Cont (Map, W, IW, P) then BS (P - 1) else P);
         pragma Loop_Invariant (for all Q in 1 .. P => BS (Q) in 1 .. Q);
         pragma Loop_Invariant (BS (1) = 1);
         pragma
           Loop_Invariant
             (for all Q in 2 .. P =>
                BS (Q) = (if Cont (Map, W, IW, Q) then BS (Q - 1) else Q));
      end loop;
      return BS;
   end Block_Starts;

   function Block_Ends (Map, W, IW : Mapping) return Mapping
   with
     Pre  => Orders.Is_Order (Map, W, IW),
     Post =>
       Block_Ends'Result'First = 1
       and then Block_Ends'Result'Length = W'Length
       and then (for all P in W'Range => Block_Ends'Result (P) in P .. W'Last)
       and then (if W'Length > 0 then Block_Ends'Result (W'Last) = W'Last)
       and then (for all P in 1 .. W'Length - 1 =>
                   Block_Ends'Result (P)
                   = (if Cont (Map, W, IW, P + 1)
                      then Block_Ends'Result (P + 1)
                      else P));

   function Block_Ends (Map, W, IW : Mapping) return Mapping is
      N  : constant Natural := W'Length;
      BE : Mapping (1 .. N) := (others => 1);
   begin
      if N = 0 then
         return BE;
      end if;
      BE (N) := N;
      for P in reverse 1 .. N - 1 loop
         BE (P) := (if Cont (Map, W, IW, P + 1) then BE (P + 1) else P);
         pragma Loop_Invariant (for all Q in P .. N => BE (Q) in Q .. N);
         pragma Loop_Invariant (BE (N) = N);
         pragma
           Loop_Invariant
             (for all Q in P .. N - 1 =>
                BE (Q) = (if Cont (Map, W, IW, Q + 1) then BE (Q + 1) else Q));
      end loop;
      return BE;
   end Block_Ends;

   --  Positions of one block agree on where it starts and ends.
   function Intervals (BS, BE : Mapping) return Boolean
   is (BS'First = 1
       and then BE'First = 1
       and then BS'Length = BE'Length
       and then BS'Length <= Max_Length
       and then (for all P in BS'Range =>
                   BS (P) in 1 .. P and then BE (P) in P .. BS'Last)
       and then (for all P in BS'Range =>
                   (for all Q in BS (P) .. BE (P) =>
                      BS (Q) = BS (P) and then BE (Q) = BE (P))));

   function Blocks (Map, W, IW, BS, BE : Mapping) return Boolean
   is (Orders.Is_Order (Map, W, IW)
       and then Permutation (Map)
       and then W'Length > 0
       and then BS'Length = W'Length
       and then Intervals (BS, BE)
       and then (for all P in 2 .. W'Last =>
                   Cont (Map, W, IW, P) = (P > BS (P))));

   procedure Block_Facts (Map, W, IW : Mapping)
   with
     Pre  =>
       Orders.Is_Order (Map, W, IW)
       and then Permutation (Map)
       and then W'Length > 0,
     Post =>
       Blocks (Map, W, IW, Block_Starts (Map, W, IW), Block_Ends (Map, W, IW));

   procedure Block_Facts (Map, W, IW : Mapping) is
      N  : constant Positive := W'Length;
      BS : constant Mapping := Block_Starts (Map, W, IW);
      BE : constant Mapping := Block_Ends (Map, W, IW);
   begin
      --  Every position after a block start continues it.
      for P in 1 .. N loop
         pragma
           Loop_Invariant
             (for all Q in 1 .. P - 1 =>
                (for all X in BS (Q) + 1 .. Q =>
                   Cont (Map, W, IW, X) and then BS (X) = BS (Q)));
         pragma
           Assert
             (for all X in BS (P) + 1 .. P =>
                Cont (Map, W, IW, X) and then BS (X) = BS (P));
      end loop;
      for P in reverse 1 .. N loop
         pragma
           Loop_Invariant
             (for all Q in P + 1 .. N =>
                (for all X in Q + 1 .. BE (Q) =>
                   Cont (Map, W, IW, X) and then BE (X) = BE (Q)));
         pragma
           Assert
             (for all X in P + 1 .. BE (P) =>
                Cont (Map, W, IW, X) and then BE (X) = BE (P));
      end loop;
      --  Continuing positions share both ends.
      for P in 2 .. N loop
         pragma
           Assert
             (if Cont (Map, W, IW, P)
                then BS (P) = BS (P - 1) and then BE (P - 1) = BE (P));
         pragma
           Loop_Invariant
             (for all Q in 2 .. P =>
                (if Cont (Map, W, IW, Q)
                 then BS (Q) = BS (Q - 1) and then BE (Q - 1) = BE (Q)));
      end loop;
      for P in 1 .. N loop
         for Q in P .. BE (P) loop
            pragma
              Loop_Invariant
                (for all X in P .. Q =>
                   BS (X) = BS (P) and then BE (X) = BE (P));
            if Q < BE (P) then
               pragma Assert (Cont (Map, W, IW, Q + 1));
            end if;
         end loop;
         for Q in reverse BS (P) .. P loop
            pragma
              Loop_Invariant
                (for all X in Q .. P =>
                   BS (X) = BS (P) and then BE (X) = BE (P));
            if Q > BS (P) then
               pragma Assert (Cont (Map, W, IW, Q));
            end if;
         end loop;
         pragma
           Assert
             (for all Q in BS (P) .. BE (P) =>
                BS (Q) = BS (P) and then BE (Q) = BE (P));
         pragma
           Loop_Invariant
             (for all X in 1 .. P =>
                (for all Q in BS (X) .. BE (X) =>
                   BS (Q) = BS (X) and then BE (Q) = BE (X)));
      end loop;
   end Block_Facts;

   function Cyc_Prev (BS, BE : Mapping; P : Positive) return Positive
   is (if P > BS (P) then P - 1 else BE (P))
   with Pre => P in BS'Range and then P in BE'Range;

   function Cyc_Next (BS, BE : Mapping; P : Positive) return Positive
   is (if P < BE (P) then P + 1 else BS (P))
   with Pre => P in BS'Range and then P in BE'Range;

   --  Following Map from the row at a block's start leads back to the row at
   --  its end: each block is one whole LF cycle.
   procedure Closure (Map, W, IW, BS, BE : Mapping)
   with
     Pre  => Blocks (Map, W, IW, BS, BE),
     Post =>
       (for all P in W'Range =>
          Cyc_Prev (BS, BE, P) in W'Range
          and then Map (W (P)) = W (Cyc_Prev (BS, BE, P)));

   procedure Closure (Map, W, IW, BS, BE : Mapping) is
      N : constant Positive := W'Length;
   begin
      for P in reverse 1 .. N loop
         if P > BS (P) then
            pragma Assert (Cont (Map, W, IW, P));
            Orders.Get_Rule (Map, W, IW, P);
            pragma Assert (W (P - 1) = Map (W (P)));
         else
            declare
               Q : constant Positive := IW (Map (W (P)));
            begin
               pragma Assert (P = 1 or else not Cont (Map, W, IW, P));
               pragma Assert (Q >= P);
               if Q < BE (P) then
                  pragma Assert (BS (Q + 1) = BS (P));
                  pragma Assert (Cont (Map, W, IW, Q + 1));
                  pragma Assert (Map (W (Q + 1)) = Map (W (P)));
                  pragma Assert (W (Q + 1) = W (P));
               elsif Q > BE (P) then
                  pragma Assert (BE (BE (P)) = BE (P));
                  pragma
                    Assert (if BS (Q) <= BE (P) then BE (BE (P)) = BE (Q));
                  pragma Assert (BS (Q) > BE (P));
                  if Q < BE (Q) then
                     pragma Assert (Cont (Map, W, IW, Q + 1));
                     pragma Assert (Map (W (Q + 1)) = Map (W (P)));
                     pragma Assert (W (Q + 1) = W (P));
                  else
                     pragma Assert (BS (BS (Q)) = BS (Q));
                     pragma Assert (BE (BS (Q)) = BE (Q));
                     pragma Assert (Cyc_Prev (BS, BE, BS (Q)) = Q);
                     pragma Assert (Map (W (BS (Q))) = W (Q));
                     pragma Assert (W (Q) = Map (W (P)));
                     pragma Assert (W (BS (Q)) = W (P));
                  end if;
               end if;
               pragma Assert (Q = BE (P));
            end;
         end if;
         pragma
           Loop_Invariant
             (for all X in P .. N => Map (W (X)) = W (Cyc_Prev (BS, BE, X)));
      end loop;
   end Closure;

   --  The row written last in a block is less than every row written at or
   --  before that block.
   procedure Block_Min (Map, W, IW, BS, BE : Mapping)
   with
     Pre  => Blocks (Map, W, IW, BS, BE),
     Post =>
       (for all P in W'Range =>
          (for all Y in 1 .. W (BE (P)) - 1 => IW (Y) > BE (P)));

   procedure Block_Min (Map, W, IW, BS, BE : Mapping) is
   begin
      for P in W'Range loop
         if BE (P) < W'Last then
            pragma Assert (BE (BE (P)) = BE (P));
            pragma
              Assert
                (if BS (BE (P) + 1) < BE (P) + 1
                   then BE (BE (P)) = BE (BE (P) + 1));
            pragma Assert (BS (BE (P) + 1) = BE (P) + 1);
            pragma Assert (not Cont (Map, W, IW, BE (P) + 1));
            Orders.Get_Rule (Map, W, IW, BE (P) + 1);
            pragma
              Assert (for all Y in 1 .. W (BE (P)) - 1 => IW (Y) > BE (P));
         else
            pragma Assert (W (BE (P)) = 1);
         end if;
         pragma
           Loop_Invariant
             (for all Q in 1 .. P =>
                (for all Y in 1 .. W (BE (Q)) - 1 => IW (Y) > BE (Q)));
      end loop;
   end Block_Min;

   ---------------------------------------------------------------------------
   --  The decoded text, laid out as blocks and rows

   function Ctx
     (L, T : String; Map, Psi, W, IW, BS, BE : Mapping) return Boolean
   is (Blocks (Map, W, IW, BS, BE)
       and then Supported (L)
       and then Supported (T)
       and then L'Length = W'Length
       and then T'Length = W'Length
       and then Psi'First = 1
       and then Psi'Length = W'Length
       and then (for all I in Psi'Range =>
                   Psi (I) in Psi'Range
                   and then Map (Psi (I)) = I
                   and then Psi (Map (I)) = I)
       and then (for all P in W'Range => T (P) = L (W (P)))
       and then (for all P in W'Range =>
                   Cyc_Prev (BS, BE, P) in W'Range
                   and then Map (W (P)) = W (Cyc_Prev (BS, BE, P)))
       and then (for all P in W'Range =>
                   (for all Y in 1 .. W (BE (P)) - 1 => IW (Y) > BE (P)))
       and then (for all A in L'Range =>
                   (for all B in L'Range =>
                      Ordered (L, A, B) = (Map (A) <= Map (B)))));

   --  The block rotation starting at each position.
   function Block_Table (BS, BE : Mapping) return Table
   with
     Pre  =>
       BS'First = 1
       and then BE'First = 1
       and then BS'Length = BE'Length
       and then BS'Length <= Max_Length
       and then (for all P in BS'Range =>
                   BS (P) in 1 .. P and then BE (P) in P .. BS'Last),
     Post =>
       Block_Table'Result'First = 1
       and then Block_Table'Result'Length = BS'Length
       and then (for all P in BS'Range =>
                   Block_Table'Result (P)
                   = (BS (P), BE (P) - BS (P) + 1, P - BS (P)));

   function Block_Table (BS, BE : Mapping) return Table is
      BT : Table (1 .. BS'Length) := (others => (1, 1, 0));
   begin
      for P in BT'Range loop
         BT (P) := (BS (P), BE (P) - BS (P) + 1, P - BS (P));
         pragma
           Loop_Invariant
             (for all Q in 1 .. P =>
                BT (Q) = (BS (Q), BE (Q) - BS (Q) + 1, Q - BS (Q)));
      end loop;
      return BT;
   end Block_Table;

   --  Where each row's rotation starts: the row at position P is Map (W (P)).
   function Row_Positions (Psi, IW : Mapping) return Mapping
   with
     Pre  =>
       Psi'First = 1
       and then IW'First = 1
       and then Psi'Length = IW'Length
       and then Psi'Length <= Max_Length
       and then (for all I in Psi'Range => Psi (I) in IW'Range)
       and then (for all I in IW'Range => IW (I) in IW'Range),
     Post =>
       Row_Positions'Result'First = 1
       and then Row_Positions'Result'Length = Psi'Length
       and then (for all I in Psi'Range =>
                   Row_Positions'Result (I) = IW (Psi (I)));

   function Row_Positions (Psi, IW : Mapping) return Mapping is
      IRA : Mapping (1 .. Psi'Length) := (others => 1);
   begin
      for I in IRA'Range loop
         IRA (I) := IW (Psi (I));
         pragma Loop_Invariant (for all J in 1 .. I => IRA (J) = IW (Psi (J)));
      end loop;
      return IRA;
   end Row_Positions;

   function Row_Table (BT : Table; IRA : Mapping) return Table
   with
     Pre  =>
       BT'First = 1
       and then IRA'First = 1
       and then IRA'Length = BT'Length
       and then BT'Length <= Max_Length
       and then (for all I in IRA'Range => IRA (I) in BT'Range),
     Post =>
       Row_Table'Result'First = 1
       and then Row_Table'Result'Length = BT'Length
       and then (for all I in IRA'Range =>
                   Row_Table'Result (I) = BT (IRA (I)));

   function Row_Table (BT : Table; IRA : Mapping) return Table is
      Rot : Table (1 .. BT'Length) := (others => (1, 1, 0));
   begin
      for I in Rot'Range loop
         Rot (I) := BT (IRA (I));
         pragma Loop_Invariant (for all J in 1 .. I => Rot (J) = BT (IRA (J)));
      end loop;
      return Rot;
   end Row_Table;

   --  The first letter of each row.
   function First_Column (L : String; Psi : Mapping) return String
   with
     Pre  =>
       Supported (L)
       and then Psi'First = 1
       and then Psi'Length = L'Length
       and then (for all I in Psi'Range => Psi (I) in L'Range),
     Post =>
       First_Column'Result'First = 1
       and then First_Column'Result'Length = L'Length
       and then (for all I in Psi'Range =>
                   First_Column'Result (I) = L (Psi (I)));

   function First_Column (L : String; Psi : Mapping) return String is
      F : String (1 .. L'Length) := (others => Character'First);
   begin
      for I in F'Range loop
         F (I) := L (Psi (I));
         pragma Loop_Invariant (for all J in 1 .. I => F (J) = L (Psi (J)));
      end loop;
      return F;
   end First_Column;

   function Layout
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String) return Boolean
   is (Ctx (L, T, Map, Psi, W, IW, BS, BE)
       and then BT'First = 1
       and then BT'Length = W'Length
       and then (for all P in BT'Range =>
                   BT (P) = (BS (P), BE (P) - BS (P) + 1, P - BS (P)))
       and then IRA'First = 1
       and then IRA'Length = W'Length
       and then (for all I in IRA'Range => IRA (I) = IW (Psi (I)))
       and then Rot'First = 1
       and then Rot'Length = W'Length
       and then (for all I in Rot'Range => Rot (I) = BT (IRA (I)))
       and then F'First = 1
       and then F'Length = W'Length
       and then (for all I in F'Range => F (I) = L (Psi (I))));

   function Table_Fact
     (T : String; BS, BE : Mapping; BT : Table; P : Positive) return Boolean
   is (Supported (T)
       and then P in BT'Range
       and then P in BS'Range
       and then P in BE'Range
       and then Cyc_Next (BS, BE, P) in BS'Range
       and then Cyc_Next (BS, BE, P) in BE'Range
       and then Cyc_Next (BS, BE, P) in BT'Range
       and then BS (Cyc_Next (BS, BE, P)) = BS (P)
       and then BE (Cyc_Next (BS, BE, P)) = BE (P)
       and then Cyc_Prev (BS, BE, P) in BS'Range
       and then Cyc_Prev (BS, BE, P) in T'Range
       and then BS (Cyc_Prev (BS, BE, P)) = BS (P)
       and then Cyc_Prev (BS, BE, Cyc_Next (BS, BE, P)) = P
       and then BS (P) in 1 .. P
       and then BE (P) in P .. BS'Last
       and then BE (P) <= Max_Length
       and then BT (P) = (BS (P), BE (P) - BS (P) + 1, P - BS (P))
       and then Valid (BT (P), T'Length)
       and then BT (P).First + BT (P).Offset = P
       and then Next_Rot (BT (P)) = BT (Cyc_Next (BS, BE, P))
       and then P in T'Range
       and then Letter (T, BT (P), 0) = T (P)
       and then Letter (T, BT (P), BT (P).Length - 1)
                = T (Cyc_Prev (BS, BE, P)));

   --  One block rotation.
   procedure Table_At (T : String; BS, BE : Mapping; BT : Table; P : Positive)
   with
     Pre  =>
       Supported (T)
       and then Intervals (BS, BE)
       and then BS'Length = T'Length
       and then BT'First = 1
       and then BT'Length = T'Length
       and then P in BT'Range
       and then (for all Q in BT'Range =>
                   BT (Q) = (BS (Q), BE (Q) - BS (Q) + 1, Q - BS (Q))),
     Post => Table_Fact (T, BS, BE, BT, P);

   procedure Table_At (T : String; BS, BE : Mapping; BT : Table; P : Positive)
   is
   begin
      Letter_Direct (T, BT (P), 0);
      if P = BS (P) then
         Letter_Direct (T, BT (P), BT (P).Length - 1);
      else
         Letter_Wrap (T, BT (P), BT (P).Length - 1);
      end if;
      pragma Assert (BS (Cyc_Next (BS, BE, P)) = BS (P));
      pragma Assert (BE (Cyc_Next (BS, BE, P)) = BE (P));
      pragma
        Assert
          (BT (Cyc_Next (BS, BE, P))
             = (BS (P), BE (P) - BS (P) + 1, Cyc_Next (BS, BE, P) - BS (P)));
   end Table_At;

   function Table_Facts
     (T : String; BS, BE : Mapping; BT : Table) return Boolean
   is (for all P in BT'Range => Table_Fact (T, BS, BE, BT, P));

   procedure All_Table (T : String; BS, BE : Mapping; BT : Table)
   with
     Pre  =>
       Supported (T)
       and then Intervals (BS, BE)
       and then BS'Length = T'Length
       and then BT'First = 1
       and then BT'Length = T'Length
       and then (for all P in BT'Range =>
                   BT (P) = (BS (P), BE (P) - BS (P) + 1, P - BS (P))),
     Post => Table_Facts (T, BS, BE, BT);

   procedure All_Table (T : String; BS, BE : Mapping; BT : Table) is
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Fact);
   begin
      for P in BT'Range loop
         Table_At (T, BS, BE, BT, P);
         pragma
           Loop_Invariant
             (for all Q in 1 .. P => Table_Fact (T, BS, BE, BT, Q));
      end loop;
   end All_Table;

   --  Rows against positions, for the permutations the decoder builds.
   function Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA : Mapping) return Boolean
   is (Orders.Inverse_Pair (W, IW)
       and then W'Length > 0
       and then Intervals (BS, BE)
       and then BS'Length = W'Length
       and then Map'First = 1
       and then Map'Length = W'Length
       and then Psi'First = 1
       and then Psi'Length = W'Length
       and then (for all I in Psi'Range =>
                   Psi (I) in Psi'Range
                   and then Map (I) in Map'Range
                   and then Map (Psi (I)) = I
                   and then Psi (Map (I)) = I)
       and then (for all P in W'Range =>
                   Cyc_Next (BS, BE, P) in W'Range
                   and then Cyc_Prev (BS, BE, P) in W'Range
                   and then Cyc_Prev (BS, BE, Cyc_Next (BS, BE, P)) = P)
       and then (for all P in W'Range =>
                   Map (W (P)) = W (Cyc_Prev (BS, BE, P)))
       and then IRA'First = 1
       and then IRA'Length = W'Length
       and then (for all I in IRA'Range => IRA (I) = IW (Psi (I))));

   function Row_Fact
     (Map, Psi, W, IW, BS, BE, IRA : Mapping; I : Positive) return Boolean
   is (I in IRA'Range
       and then I in W'Range
       and then I in IW'Range
       and then I in Psi'Range
       and then IRA (I) in W'Range
       and then W (IRA (I)) in Map'Range
       and then Map (W (IRA (I))) = I
       and then W (IRA (I)) = Psi (I)
       and then W (I) in Map'Range
       and then Map (W (I)) in IRA'Range
       and then IRA (Map (W (I))) = I
       and then IW (I) in BS'Range
       and then IW (I) in BE'Range
       and then IRA (I) = Cyc_Next (BS, BE, IW (I))
       and then Psi (I) in IRA'Range
       and then IRA (I) in BS'Range
       and then IRA (I) in BE'Range
       and then IRA (Psi (I)) = Cyc_Next (BS, BE, IRA (I)));

   procedure Row_At (Map, Psi, W, IW, BS, BE, IRA : Mapping; I : Positive)
   with
     Pre  => Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA) and then I in IRA'Range,
     Post => Row_Fact (Map, Psi, W, IW, BS, BE, IRA, I);

   procedure Row_At (Map, Psi, W, IW, BS, BE, IRA : Mapping; I : Positive) is
      C : constant Positive := Cyc_Next (BS, BE, IW (I));
      D : constant Positive := Cyc_Next (BS, BE, IW (Psi (I)));
   begin
      pragma Assert (Map (W (C)) = W (IW (I)));
      pragma Assert (W (C) = Psi (I));
      pragma Assert (IRA (I) = C);
      pragma Assert (Map (W (D)) = W (IW (Psi (I))));
      pragma Assert (W (D) = Psi (Psi (I)));
      pragma Assert (IRA (Psi (I)) = D);
      pragma Assert (IW (Psi (I)) = IRA (I));
   end Row_At;

   function Row_Facts (Map, Psi, W, IW, BS, BE, IRA : Mapping) return Boolean
   is (for all I in IRA'Range => Row_Fact (Map, Psi, W, IW, BS, BE, IRA, I));

   procedure All_Rows (Map, Psi, W, IW, BS, BE, IRA : Mapping)
   with
     Pre  => Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA),
     Post => Row_Facts (Map, Psi, W, IW, BS, BE, IRA);

   procedure All_Rows (Map, Psi, W, IW, BS, BE, IRA : Mapping) is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Fact);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
   begin
      for I in IRA'Range loop
         Row_At (Map, Psi, W, IW, BS, BE, IRA, I);
         pragma
           Loop_Invariant
             (for all J in IRA'First .. I =>
                Row_Fact (Map, Psi, W, IW, BS, BE, IRA, J));
      end loop;
   end All_Rows;

   --  The first column is sorted, stably by where each row came from.
   procedure First_Sorted (L : String; Map, Psi : Mapping; F : String)
   with
     Pre  =>
       Supported (L)
       and then L'Length > 0
       and then Map'First = 1
       and then Map'Length = L'Length
       and then Psi'First = 1
       and then Psi'Length = L'Length
       and then (for all I in Psi'Range =>
                   Psi (I) in Psi'Range
                   and then Map (I) in Map'Range
                   and then Map (Psi (I)) = I)
       and then (for all A in L'Range =>
                   (for all B in L'Range =>
                      Ordered (L, A, B) = (Map (A) <= Map (B))))
       and then F'First = 1
       and then F'Length = L'Length
       and then (for all I in F'Range => F (I) = L (Psi (I))),
     Post =>
       (for all I in F'Range =>
          (for all J in I + 1 .. F'Last =>
             F (I) <= F (J)
             and then (if F (I) = F (J) then Psi (I) < Psi (J))));

   procedure First_Sorted (L : String; Map, Psi : Mapping; F : String) is
   begin
      for I in F'Range loop
         for J in I + 1 .. F'Last loop
            pragma Assert (Ordered (L, Psi (I), Psi (J)));
            pragma Assert (Psi (I) /= Psi (J));
            pragma
              Loop_Invariant
                (for all Q in I + 1 .. J =>
                   F (I) <= F (Q)
                   and then (if F (I) = F (Q) then Psi (I) < Psi (Q)));
         end loop;
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                (for all Q in P + 1 .. F'Last =>
                   F (P) <= F (Q)
                   and then (if F (P) = F (Q) then Psi (P) < Psi (Q))));
      end loop;
   end First_Sorted;

   procedure Get_Table (T : String; BS, BE : Mapping; BT : Table; P : Positive)
   with
     Pre  => Table_Facts (T, BS, BE, BT) and then P in BT'Range,
     Post => Table_Fact (T, BS, BE, BT, P);

   procedure Get_Table (T : String; BS, BE : Mapping; BT : Table; P : Positive)
   is
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Fact);
   begin
      null;
   end Get_Table;

   procedure Get_Row (Map, Psi, W, IW, BS, BE, IRA : Mapping; I : Positive)
   with
     Pre  => Row_Facts (Map, Psi, W, IW, BS, BE, IRA) and then I in IRA'Range,
     Post => Row_Fact (Map, Psi, W, IW, BS, BE, IRA, I);

   procedure Get_Row (Map, Psi, W, IW, BS, BE, IRA : Mapping; I : Positive) is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Fact);
   begin
      null;
   end Get_Row;

   procedure Get_Ctx (Map, Psi, W, IW, BS, BE, IRA : Mapping; I : Positive)
   with
     Pre  => Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA) and then I in Psi'Range,
     Post =>
       Psi'First = 1
       and then Psi'Length = W'Length
       and then W'First = 1
       and then Psi (I) in Psi'Range
       and then Map'First = 1
       and then Map'Length = W'Length
       and then Map (Psi (I)) = I;

   procedure Get_Ctx (Map, Psi, W, IW, BS, BE, IRA : Mapping; I : Positive)
   is null;

   --  Row I's rotation starts with its first letter and continues as the
   --  rotation of row Psi (I).
   procedure Rows_Model
     (T                    : String;
      BS, BE               : Mapping;
      BT                   : Table;
      Map, Psi, W, IW, IRA : Mapping;
      Rot                  : Table;
      L, F                 : String)
   with
     Pre  =>
       Supported (T)
       and then Supported (L)
       and then T'Length > 0
       and then T'Length = W'Length
       and then L'Length = W'Length
       and then W'First = 1
       and then Psi'First = 1
       and then Psi'Length = W'Length
       and then IRA'First = 1
       and then IRA'Length = W'Length
       and then Intervals (BS, BE)
       and then BS'Length = T'Length
       and then BT'First = 1
       and then BT'Length = T'Length
       and then Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA)
       and then Table_Facts (T, BS, BE, BT)
       and then Row_Facts (Map, Psi, W, IW, BS, BE, IRA)
       and then (for all P in W'Range =>
                   W (P) in L'Range and then T (P) = L (W (P)))
       and then Rot'First = 1
       and then Rot'Length = W'Length
       and then (for all I in Rot'Range =>
                   IRA (I) in BT'Range and then Rot (I) = BT (IRA (I)))
       and then F'First = 1
       and then F'Length = W'Length
       and then (for all I in F'Range =>
                   Psi (I) in L'Range and then F (I) = L (Psi (I)))
       and then (for all I in F'Range =>
                   (for all J in I + 1 .. F'Last =>
                      F (I) <= F (J)
                      and then (if F (I) = F (J) then Psi (I) < Psi (J)))),
     Post => Row_Model (T, Rot, Psi, F);

   procedure Rows_Model
     (T                    : String;
      BS, BE               : Mapping;
      BT                   : Table;
      Map, Psi, W, IW, IRA : Mapping;
      Rot                  : Table;
      L, F                 : String)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
   begin
      for I in Rot'Range loop
         Get_Row (Map, Psi, W, IW, BS, BE, IRA, I);
         Get_Ctx (Map, Psi, W, IW, BS, BE, IRA, I);
         Get_Table (T, BS, BE, BT, IRA (I));
         pragma Assert (W (IRA (I)) = Psi (I));
         pragma Assert (Letter (T, Rot (I), 0) = F (I));
         pragma Assert (Cyc_Next (BS, BE, IRA (I)) = IRA (Psi (I)));
         pragma Assert (Next_Rot (Rot (I)) = BT (Cyc_Next (BS, BE, IRA (I))));
         pragma Assert (Rot (Psi (I)) = BT (IRA (Psi (I))));
         pragma Assert (Next_Rot (Rot (I)) = Rot (Psi (I)));
         pragma
           Loop_Invariant
             (for all J in 1 .. I =>
                Valid (Rot (J), T'Length)
                and then Psi (J) in Psi'Range
                and then Letter (T, Rot (J), 0) = F (J)
                and then Next_Rot (Rot (J)) = Rot (Psi (J)));
      end loop;
   end Rows_Model;

   procedure Get_Rows_Ctx
     (Map, Psi, W, IW, BS, BE, IRA : Mapping; P : Positive)
   with
     Pre  =>
       Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA)
       and then W'First = 1
       and then P in 1 .. W'Length,
     Post =>
       Psi'First = 1
       and then Psi'Length = W'Length
       and then Psi'Length <= Max_Length
       and then (for all K in Psi'Range => Psi (K) in Psi'Range)
       and then Cyc_Prev (BS, BE, P) in W'Range
       and then W (P) in Map'Range
       and then W (P) in IW'Range
       and then IW (W (P)) = P
       and then Map (W (P)) = W (Cyc_Prev (BS, BE, P));

   procedure Get_Rows_Ctx
     (Map, Psi, W, IW, BS, BE, IRA : Mapping; P : Positive)
   is null;

   ---------------------------------------------------------------------------
   --  The row layout is sorted, blocks and all

   function Onto_Ctx
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String) return Boolean
   is (Supported (L)
       and then Supported (T)
       and then T'Length > 0
       and then L'Length = T'Length
       and then W'First = 1
       and then W'Length = T'Length
       and then IW'First = 1
       and then IW'Length = T'Length
       and then Intervals (BS, BE)
       and then BS'Length = T'Length
       and then BT'First = 1
       and then BT'Length = T'Length
       and then IRA'First = 1
       and then IRA'Length = T'Length
       and then Rot'First = 1
       and then Rot'Length = T'Length
       and then (for all I in Rot'Range =>
                   IRA (I) in BT'Range and then Rot (I) = BT (IRA (I)))
       and then Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA)
       and then Table_Facts (T, BS, BE, BT)
       and then Row_Facts (Map, Psi, W, IW, BS, BE, IRA)
       and then Row_Model (T, Rot, Psi, F)
       and then (for all P in W'Range =>
                   W (P) in L'Range and then T (P) = L (W (P)))
       and then (for all P in W'Range =>
                   (for all Y in 1 .. W (BE (P)) - 1 => IW (Y) > BE (P))));

   procedure Get_Min
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      P, Y                    : Positive)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then P in W'Range
       and then Y < W (BE (P)),
     Post => IW (Y) > BE (P);

   procedure Get_Min
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      P, Y                    : Positive)
   is null;

   --  Rows with equal periodic words sit in blocks from right to left.
   procedure Tie
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      I, J                    : Positive)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then I in Rot'Range
       and then J in I + 1 .. Rot'Last
       and then Valid (Rot (I), T'Length)
       and then Valid (Rot (J), T'Length)
       and then Equal_Prefix (T, Rot (I), Rot (J), 2 * T'Length),
     Post => IRA (I) > IRA (J);

   procedure Tie
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      I, J                    : Positive)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
      Q : constant Positive := IRA (J);
      D : constant Positive := BE (Q) - Q + 1;
   begin
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, 1);
      Equal_Prefix_Shorter (T, Rot (I), Rot (J), 2 * T'Length, D);
      Preserve (T, Rot, Psi, F, I, J, D);
      Get_Row (Map, Psi, W, IW, BS, BE, IRA, I);
      Fwd_Step (Psi, I, 0);
      Fwd_Step (Psi, J, 0);
      for K in 0 .. D loop
         pragma
           Loop_Invariant
             (IRA (Fwd (Psi, J, K)) = (if K < D then Q + K else BS (Q)));
         pragma
           Loop_Invariant
             (IRA (Fwd (Psi, I, K)) in BT'Range
                and then BS (IRA (Fwd (Psi, I, K))) = BS (IRA (I)));
         if K < D then
            declare
               A : constant Positive := Fwd (Psi, I, K);
               B : constant Positive := Fwd (Psi, J, K);
            begin
               Get_Row (Map, Psi, W, IW, BS, BE, IRA, A);
               Get_Row (Map, Psi, W, IW, BS, BE, IRA, B);
               Get_Table (T, BS, BE, BT, IRA (A));
               Get_Table (T, BS, BE, BT, IRA (B));
               Fwd_Step (Psi, I, K);
               Fwd_Step (Psi, J, K);
               pragma
                 Assert (BE (Q + K) = BE (Q) and then BS (Q + K) = BS (Q));
            end;
         end if;
      end loop;
      declare
         A : constant Positive := Fwd (Psi, I, D);
         B : constant Positive := Fwd (Psi, J, D);
      begin
         --  After D steps row J's rotation reaches the start of its block,
         --  where the least row of that block sits.
         Get_Row (Map, Psi, W, IW, BS, BE, IRA, B);
         Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, BS (Q));
         pragma Assert (BS (BS (Q)) = BS (Q) and then BE (BS (Q)) = BE (Q));
         pragma Assert (B = W (BE (Q)));
         pragma Assert (A < W (BE (Q)));
         Get_Min (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, Q, A);
         Get_Row (Map, Psi, W, IW, BS, BE, IRA, A);
         Get_Table (T, BS, BE, BT, IW (A));
         pragma Assert (BS (IRA (A)) = BS (IW (A)));
         pragma Assert (BE (BE (Q)) = BE (Q));
         pragma
           Assert (if BS (IW (A)) <= BE (Q) then BE (BE (Q)) = BE (IW (A)));
         pragma Assert (BS (IW (A)) > BE (Q));
      end;
   end Tie;

   function Key_Sorted (T : String; Rot : Table) return Boolean
   is (Supported (T)
       and then Rot'Last <= Max_Length
       and then (for all I in Rot'Range =>
                   Valid (Rot (I), T'Length)
                   and then (for all J in I + 1 .. Rot'Last =>
                               Valid (Rot (J), T'Length)
                               and then Key_LE
                                          (T,
                                           Rot (I),
                                           Rot (J),
                                           Later_First))));

   procedure Key_Pair
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      I, J                    : Positive)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then Ordered_Upto (T, Rot, 2 * T'Length)
       and then I in Rot'Range
       and then J in I + 1 .. Rot'Last,
     Post =>
       Valid (Rot (I), T'Length)
       and then Valid (Rot (J), T'Length)
       and then Key_LE (T, Rot (I), Rot (J), Later_First);

   procedure Key_Pair
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      I, J                    : Positive)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
   begin
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, 1);
      Get_Row (Map, Psi, W, IW, BS, BE, IRA, I);
      Get_Row (Map, Psi, W, IW, BS, BE, IRA, J);
      Get_Table (T, BS, BE, BT, IRA (I));
      Get_Table (T, BS, BE, BT, IRA (J));
      pragma Assert (LE (T, Rot (I), Rot (J), 2 * T'Length));
      if Equal_Prefix (T, Rot (I), Rot (J), 2 * T'Length) then
         Tie (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, I, J);
         pragma Assert (Tie_LE (Rot (I), Rot (J), Later_First));
      end if;
      Key_Intro (T, Rot (I), Rot (J), Later_First);
   end Key_Pair;

   procedure Rows_Sorted
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String)
   with
     Pre  =>
       Supported (T)
       and then T'Length > 0
       and then Rot'First = 1
       and then Rot'Length = T'Length
       and then Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then Ordered_Upto (T, Rot, 2 * T'Length),
     Post => Key_Sorted (T, Rot);

   procedure Get_Valid
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      I                       : Positive)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then I in 1 .. T'Length,
     Post =>
       Supported (T)
       and then Rot'First = 1
       and then Rot'Length = T'Length
       and then Rot'Last <= Max_Length
       and then Valid (Rot (I), T'Length);

   procedure Get_Valid
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      I                       : Positive)
   is null;

   procedure Rows_Sorted
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Onto_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Ordered_Upto);
   begin
      Get_Valid (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, 1);
      for I in Rot'Range loop
         Get_Valid (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, I);
         for J in I + 1 .. Rot'Last loop
            Key_Pair (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, I, J);
            pragma
              Loop_Invariant
                (for all Q in I + 1 .. J =>
                   Valid (Rot (Q), T'Length)
                   and then Key_LE (T, Rot (I), Rot (Q), Later_First));
         end loop;
         pragma
           Loop_Invariant
             (for all P in 1 .. I =>
                Valid (Rot (P), T'Length)
                and then (for all Q in P + 1 .. Rot'Last =>
                            Valid (Rot (Q), T'Length)
                            and then Key_LE
                                       (T, Rot (P), Rot (Q), Later_First)));
      end loop;
   end Rows_Sorted;

   --  Each block is a Lyndon word.
   procedure Block_Lyndon
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      P                       : Positive)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then Key_Sorted (T, Rot)
       and then P in BS'Range
       and then BS (P) = P,
     Post =>
       In_Word (T, P, BE (P) - P + 1) and then Lyndon (T, P, BE (P) - P + 1);

   procedure Block_Lyndon
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      P                       : Positive)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
      Len : constant Positive := BE (P) - P + 1;
   begin
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, P);
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, BE (P));
      Get_Table (T, BS, BE, BT, P);
      for O in 1 .. Len - 1 loop
         Get_Row (Map, Psi, W, IW, BS, BE, IRA, P);
         Get_Row (Map, Psi, W, IW, BS, BE, IRA, P + O);
         Get_Table (T, BS, BE, BT, P + O);
         Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, P + O);
         Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, P + O - 1);
         declare
            S1 : constant Positive := Map (W (P));
            R1 : constant Positive := Map (W (P + O));
         begin
            pragma Assert (BS (P + O) = P and then BE (P + O) = BE (P));
            pragma Assert (IRA (S1) = P and then IRA (R1) = P + O);
            pragma Assert (Rot (S1) = (P, Len, 0));
            pragma Assert (Rot (R1) = (P, Len, O));
            pragma Assert (S1 = W (BE (P)));
            pragma Assert (R1 = W (P + O - 1));
            if R1 < S1 then
               Get_Min (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, P, R1);
            end if;
            pragma Assert (R1 /= S1);
            pragma Assert (S1 < R1);
            pragma Assert (Key_LE (T, Rot (S1), Rot (R1), Later_First));
            Key_Weakening (T, Rot (S1), Rot (R1), Later_First);
            if LE (T, Rot (R1), Rot (S1), 2 * T'Length) then
               Order_Laws (T, Rot (S1), Rot (R1), Rot (S1), 2 * T'Length);
               Key_Tie (T, Rot (S1), Rot (R1), Later_First);
            end if;
            pragma Assert (Omega_Less (T, (P, Len, 0), (P, Len, O)));
         end;
         pragma
           Loop_Invariant
             (for all Q in 1 .. O => Omega_Less (T, (P, Len, 0), (P, Len, Q)));
      end loop;
      Least_Lyndon (T, P, Len);
   end Block_Lyndon;

   --  Blocks do not increase from left to right.
   procedure Block_Next
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      P                       : Positive)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then Key_Sorted (T, Rot)
       and then P in BS'Range
       and then BS (P) = P
       and then BE (P) < BS'Last
       and then In_Word (T, P, BE (P) - P + 1)
       and then Lyndon (T, P, BE (P) - P + 1)
       and then BE (P) + 1 in BE'Range
       and then In_Word (T, BE (P) + 1, BE (BE (P) + 1) - BE (P))
       and then Lyndon (T, BE (P) + 1, BE (BE (P) + 1) - BE (P)),
     Post =>
       BS (BE (P) + 1) = BE (P) + 1
       and then Lex_LE
                  (T, BE (P) + 1, BE (BE (P) + 1) - BE (P), P, BE (P) - P + 1);

   procedure Block_Next
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      P                       : Positive)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
      E    : constant Positive := BE (P) + 1;
      LenP : constant Positive := BE (P) - P + 1;
   begin
      pragma Assert (BE (BE (P)) = BE (P));
      pragma Assert (if BS (E) < E then BE (BE (P)) = BE (E));
      pragma Assert (BS (E) = E);
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, P);
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, E);
      declare
         LenE : constant Positive := BE (E) - E + 1;
         S1   : constant Positive := Map (W (P));
         S2   : constant Positive := Map (W (E));
      begin
         Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, BE (P));
         Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, BE (E));
         Get_Row (Map, Psi, W, IW, BS, BE, IRA, P);
         Get_Row (Map, Psi, W, IW, BS, BE, IRA, E);
         Get_Table (T, BS, BE, BT, P);
         Get_Table (T, BS, BE, BT, E);
         pragma Assert (IRA (S1) = P and then IRA (S2) = E);
         pragma Assert (Rot (S1) = (P, LenP, 0));
         pragma Assert (Rot (S2) = (E, LenE, 0));
         pragma Assert (S1 = W (BE (P)));
         pragma Assert (S2 = W (BE (E)));
         if S1 < S2 then
            Get_Min (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, E, S1);
         end if;
         pragma Assert (S1 /= S2);
         pragma Assert (S2 < S1);
         pragma Assert (Key_LE (T, Rot (S2), Rot (S1), Later_First));
         Key_Weakening (T, Rot (S2), Rot (S1), Later_First);
         if Lex_Less (T, P, LenP, E, LenE) then
            Lyndon_Omega (T, P, LenP, E, LenE);
         end if;
      end;
   end Block_Next;

   --  The blocks are the text's nonincreasing Lyndon factorization.
   procedure Blocks_Factorize
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then Key_Sorted (T, Rot),
     Post => Factorization (T, BT);

   procedure Blocks_Factorize
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
      N : constant Positive := T'Length;
   begin
      for P in 1 .. N loop
         if BS (P) = P then
            Block_Lyndon (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, P);
         end if;
         pragma
           Loop_Invariant
             (for all Q in 1 .. P =>
                (if BS (Q) = Q
                 then
                   In_Word (T, Q, BE (Q) - Q + 1)
                   and then Lyndon (T, Q, BE (Q) - Q + 1)));
      end loop;
      for P in 1 .. N loop
         if BS (P) = P and then BE (P) < N then
            pragma Assert (BE (BE (P)) = BE (P));
            pragma
              Assert
                (if BS (BE (P) + 1) < BE (P) + 1
                   then BE (BE (P)) = BE (BE (P) + 1));
            pragma Assert (BS (BE (P) + 1) = BE (P) + 1);
            Block_Next (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, P);
         end if;
         pragma
           Loop_Invariant
             (for all Q in 1 .. P =>
                (if BS (Q) = Q and then BE (Q) < N
                 then
                   BS (BE (Q) + 1) = BE (Q) + 1
                   and then Lex_LE
                              (T,
                               BE (Q) + 1,
                               BE (BE (Q) + 1) - BE (Q),
                               Q,
                               BE (Q) - Q + 1)));
      end loop;
      for P in 1 .. N loop
         Get_Table (T, BS, BE, BT, P);
         pragma Assert (BS (BS (P)) = BS (P) and then BE (BS (P)) = BE (P));
         pragma
           Loop_Invariant
             (for all Q in 1 .. P =>
                Valid (BT (Q), N)
                and then BT (Q).First + BT (Q).Offset = Q
                and then BT (Q) = (BS (Q), BE (Q) - BS (Q) + 1, Q - BS (Q)));
      end loop;
      pragma
        Assert
          (for all P in 1 .. N =>
             Valid (BT (P), N)
             and then BT (P).First + BT (P).Offset = P
             and then BT (P).First + BT (P).Length <= N + 1);
      pragma
        Assert
          (for all P in 1 .. N =>
             (for all Q in BT (P).First .. BT (P).First + BT (P).Length - 1 =>
                BT (Q).First = BT (P).First
                and then BT (Q).Length = BT (P).Length));
      for P in 1 .. N loop
         pragma Assert (BS (BS (P)) = BS (P) and then BE (BS (P)) = BE (P));
         pragma Assert (BT (P).First = BS (P));
         pragma Assert (BT (P).Length = BE (BS (P)) - BS (P) + 1);
         pragma Assert (Lyndon (T, BT (P).First, BT (P).Length));
         if BE (P) < N then
            pragma Assert (BT (P).First + BT (P).Length = BE (BS (P)) + 1);
            Get_Table (T, BS, BE, BT, BE (P) + 1);
            pragma Assert (BS (BE (BS (P)) + 1) = BE (BS (P)) + 1);
            pragma Assert (BT (BE (P) + 1).Offset = 0);
            pragma
              Assert
                (BT (BE (P) + 1).Length = BE (BE (BS (P)) + 1) - BE (BS (P)));
         end if;
         pragma
           Loop_Invariant
             (for all Q in 1 .. P =>
                Lyndon (T, BT (Q).First, BT (Q).Length)
                and then (if BT (Q).First + BT (Q).Length < N + 1
                          then
                            BT (BT (Q).First + BT (Q).Length).Offset = 0
                            and then Lex_LE
                                       (T,
                                        BT (Q).First + BT (Q).Length,
                                        BT (BT (Q).First + BT (Q).Length)
                                          .Length,
                                        BT (Q).First,
                                        BT (Q).Length)));
      end loop;
      pragma
        Assert
          (for all P in 1 .. N => Lyndon (T, BT (P).First, BT (P).Length));
      pragma
        Assert
          (for all P in 1 .. N =>
             (if BT (P).First + BT (P).Length < N + 1
              then
                BT (BT (P).First + BT (P).Length).Offset = 0
                and then Lex_LE
                           (T,
                            BT (P).First + BT (P).Length,
                            BT (BT (P).First + BT (P).Length).Length,
                            BT (P).First,
                            BT (P).Length)));
      Intro (T, BT);
   end Blocks_Factorize;

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

   --  Sorting the text's rotations reproduces the row layout exactly.
   procedure Sorted_Equal
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      RT                      : Table)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then Key_Sorted (T, Rot)
       and then Sorting.Well_Formed (T, RT)
       and then Sorting.Distinct (RT)
       and then Sorting.Sorted (T, RT, Later_First)
       and then Sorting.Same_Rows (RT, BT),
     Post => (for all I in RT'Range => RT (I) = Rot (I));

   procedure Sorted_Equal
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F                       : String;
      RT                      : Table)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
      N : constant Positive := T'Length;
   begin
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, 1);
      for I in 1 .. N loop
         pragma Loop_Invariant (for all K in 1 .. I - 1 => RT (K) = Rot (K));
         declare
            X : constant Positive := Find (BT, RT (I));
         begin
            Get_Table (T, BS, BE, BT, X);
            Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, X);
            declare
               J : constant Positive := Map (W (X));
            begin
               Get_Row (Map, Psi, W, IW, BS, BE, IRA, X);
               pragma Assert (IRA (J) = X);
               pragma Assert (Rot (J) = RT (I));
               pragma Assert (if J < I then RT (J) = RT (I));
               pragma Assert (J >= I);
               Get_Row (Map, Psi, W, IW, BS, BE, IRA, I);
               declare
                  M : constant Positive := Find (RT, Rot (I));
               begin
                  if M < I then
                     pragma Assert (Rot (M) = Rot (I));
                     Get_Row (Map, Psi, W, IW, BS, BE, IRA, M);
                     Get_Table (T, BS, BE, BT, IRA (M));
                     Get_Table (T, BS, BE, BT, IRA (I));
                     pragma Assert (IRA (M) = IRA (I));
                  end if;
                  pragma Assert (M >= I);
                  if I < J then
                     pragma Assert (Key_LE (T, Rot (I), Rot (J), Later_First));
                  else
                     pragma Assert (RT (I) = Rot (I));
                  end if;
                  if I < M then
                     pragma Assert (Key_LE (T, RT (I), RT (M), Later_First));
                  end if;
                  if I < J and then I < M then
                     Key_Antisym (T, Rot (I), RT (I), Later_First);
                     Get_Table (T, BS, BE, BT, IRA (I));
                     pragma Assert (RT (I) = BT (X));
                     pragma Assert (X = IRA (I));
                  elsif I < J then
                     pragma Assert (RT (I) = Rot (I));
                  end if;
                  pragma Assert (RT (I) = Rot (I));
               end;
            end;
         end;
      end loop;
   end Sorted_Equal;

   procedure Same_Rows_Transfer (A, B, C : Table)
   with
     Pre  =>
       Sorting.Same_Rows (A, B)
       and then C'First = B'First
       and then C'Last = B'Last
       and then (for all P in B'Range => B (P) = C (P)),
     Post => Sorting.Same_Rows (A, C);

   procedure Same_Rows_Transfer (A, B, C : Table) is
   begin
      for I in A'Range loop
         declare
            J : constant Positive := Find (B, A (I));
         begin
            pragma Assert (A (I) = C (J));
         end;
         pragma
           Loop_Invariant
             (for all K in A'First .. I =>
                (for some J in C'Range => A (K) = C (J)));
      end loop;
      for I in C'Range loop
         declare
            J : constant Positive := Find (A, B (I));
         begin
            pragma Assert (C (I) = A (J));
         end;
         pragma
           Loop_Invariant
             (for all K in C'First .. I =>
                (for some J in A'Range => C (K) = A (J)));
      end loop;
   end Same_Rows_Transfer;

   procedure Table_Cyc (T : String; BS, BE : Mapping; BT : Table)
   with
     Pre  =>
       Table_Facts (T, BS, BE, BT)
       and then BT'First = 1
       and then BS'First = 1
       and then BS'Length = BT'Length
       and then BE'First = 1
       and then BE'Length = BT'Length,
     Post =>
       (for all P in BT'Range =>
          Cyc_Next (BS, BE, P) in BT'Range
          and then Cyc_Prev (BS, BE, P) in BT'Range
          and then Cyc_Prev (BS, BE, Cyc_Next (BS, BE, P)) = P);

   procedure Table_Cyc (T : String; BS, BE : Mapping; BT : Table) is
   begin
      for P in BT'Range loop
         Get_Table (T, BS, BE, BT, P);
         pragma
           Loop_Invariant
             (for all Q in BT'First .. P =>
                Cyc_Next (BS, BE, Q) in BT'Range
                and then Cyc_Prev (BS, BE, Q) in BT'Range
                and then Cyc_Prev (BS, BE, Cyc_Next (BS, BE, Q)) = Q);
      end loop;
   end Table_Cyc;

   --  The transform's letter for row I is the letter the row came from.
   procedure Final_At
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F, E                    : String;
      I                       : Positive)
   with
     Pre  =>
       Onto_Ctx (L, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F)
       and then I in 1 .. T'Length
       and then I in E'Range
       and then Valid (Rot (I), T'Length)
       and then E (I) = Letter (T, Rot (I), Rot (I).Length - 1),
     Post => E (I) = L (I);

   procedure Final_At
     (L, T                    : String;
      Map, Psi, W, IW, BS, BE : Mapping;
      BT                      : Table;
      IRA                     : Mapping;
      Rot                     : Table;
      F, E                    : String;
      I                       : Positive)
   is
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Rows_Ctx);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
   begin
      Get_Row (Map, Psi, W, IW, BS, BE, IRA, I);
      Get_Table (T, BS, BE, BT, IRA (I));
      Get_Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA, IRA (I));
      pragma Assert (Rot (I) = BT (IRA (I)));
      pragma Assert (E (I) = T (Cyc_Prev (BS, BE, IRA (I))));
      pragma Assert (W (Cyc_Prev (BS, BE, IRA (I))) = Map (W (IRA (I))));
   end Final_At;

   procedure Onto (Last : String) is
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Table_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Facts);
      pragma
        Annotate (GNATprove, Hide_Info, "Expression_Function_Body", Row_Model);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Ordered_Upto);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Key_Sorted);
      pragma
        Annotate
          (GNATprove, Hide_Info, "Expression_Function_Body", Factorization);
      pragma
        Annotate
          (GNATprove,
           Hide_Info,
           "Expression_Function_Body",
           Sorting.Same_Rows);
   begin
      if Last'Length = 0 then
         return;
      end if;
      declare
         N   : constant Positive := Last'Length;
         Map : constant Mapping := LF (Last);
         Psi : constant Mapping := Permutations.Inverse (Map);
         W   : constant Mapping := Bijective.Decode_Order (Last);
         IW  : constant Mapping := Permutations.Inverse (W);
         T   : constant String := Bijective.Decode (Last);
      begin
         pragma Assert (Orders.Is_Order (Map, W, IW));
         Block_Facts (Map, W, IW);
         declare
            BS : constant Mapping := Block_Starts (Map, W, IW);
            BE : constant Mapping := Block_Ends (Map, W, IW);
         begin
            Closure (Map, W, IW, BS, BE);
            Block_Min (Map, W, IW, BS, BE);
            declare
               BT  : constant Table := Block_Table (BS, BE);
               IRA : constant Mapping := Row_Positions (Psi, IW);
               Rot : constant Table := Row_Table (BT, IRA);
               F   : constant String := First_Column (Last, Psi);
            begin
               All_Table (T, BS, BE, BT);
               Table_Cyc (T, BS, BE, BT);
               pragma Assert (Rows_Ctx (Map, Psi, W, IW, BS, BE, IRA));
               All_Rows (Map, Psi, W, IW, BS, BE, IRA);
               First_Sorted (Last, Map, Psi, F);
               Rows_Model (T, BS, BE, BT, Map, Psi, W, IW, IRA, Rot, Last, F);
               Monotone (T, Rot, Psi, F);
               pragma
                 Assert
                   (Onto_Ctx
                      (Last, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F));
               Rows_Sorted (Last, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F);
               Blocks_Factorize
                 (Last, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F);
               declare
                  FR : constant Table := Bijective.Factor_Rotations (T);
                  RT : constant Table := Bijective.Table_Of (T);
                  E  : constant String := Bijective.Encode (T);
               begin
                  Unique (T, FR, BT);
                  Bounds (T, FR);
                  Same_Rows_Transfer (RT, FR, BT);
                  Sorted_Equal
                    (Last, T, Map, Psi, W, IW, BS, BE, BT, IRA, Rot, F, RT);
                  for I in 1 .. N loop
                     pragma Assert (RT (I) = Rot (I));
                     pragma Assert (Valid (Rot (I), N));
                     pragma
                       Assert
                         (E (I) = Letter (T, Rot (I), Rot (I).Length - 1));
                     Final_At
                       (Last,
                        T,
                        Map,
                        Psi,
                        W,
                        IW,
                        BS,
                        BE,
                        BT,
                        IRA,
                        Rot,
                        F,
                        E,
                        I);
                     pragma
                       Loop_Invariant
                         (for all K in 1 .. I => E (K) = Last (K));
                  end loop;
               end;
            end;
         end;
      end;
   end Onto;
end BWT.Onto_Proofs;
