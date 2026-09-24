with BWT.Counting;
with BWT.Doubling;
with BWT.FM_Index;
with BWT.Search;

--  FM-index "locate": the positions of a pattern's occurrences. Positions
--  whose offset in their factor is a multiple of Rate are sampled, so every
--  factor start is. Any other row walks LF back to a sampled row, at most
--  Rate - 1 steps, and adds the steps taken. The walk is exact wherever LF
--  is: on the bijective table always, and on the classical one when S is
--  primitive.

package BWT.Locate
  with SPARK_Mode
is
   use BWT.Counting;

   Rate : constant := 32;

   type Slot_Marks is array (Natural range <>) of Natural;
   type Places is array (Positive range <>) of Natural;

   --  Before (K) counts the sampled rows among 1 .. K * Block, and Value
   --  lists the sampled rows' positions in row order.
   type Locator
     (Length  : Natural;
      Blocks  : Natural;
      Samples : Natural)
   is record
      Idx     : FM_Index.Index (Length, Blocks);
      Sampled : Flags (1 .. Length);
      Before  : Slot_Marks (0 .. Blocks);
      Value   : Places (1 .. Samples);
   end record;

   function Valid (L : Locator) return Boolean
   is (FM_Index.Valid (L.Idx)
       and then L.Samples = Search.Hits (L.Sampled, L.Length)
       and then (for all K in 0 .. L.Blocks =>
                   L.Before (K) = Search.Hits (L.Sampled, K * FM_Index.Block))
       and then (for all I in 1 .. L.Length =>
                   (if L.Sampled (I)
                    then Search.Hits (L.Sampled, I) in 1 .. L.Samples))
       and then (for all V of L.Value => V <= L.Length))
   with Ghost;

   --  The sample of a sampled row: how many sampled rows reach up to it.
   function Slot (L : Locator; Row : Positive) return Natural
   with
     Pre  => Valid (L) and then Row in 1 .. L.Length,
     Post => Slot'Result = Search.Hits (L.Sampled, Row);

   --  The position of a row, from the first sampled row within Fuel LF
   --  steps; 0 if there is none.
   function Resolve
     (L : Locator; Row : Positive; Fuel : Natural) return Natural
   is (if L.Sampled (Row)
       then L.Value (Slot (L, Row))
       elsif Fuel = 0
       then 0
       else
         (declare
            Next : constant Natural :=
              Resolve (L, FM_Index.LF (L.Idx, Row), Fuel - 1);
          begin
            (if Next = 0 then 0 else Next + 1)))
   with
     Pre                =>
       Valid (L) and then Row in 1 .. L.Length and then Fuel <= Rate,
     Post               => Resolve'Result <= L.Length + Fuel,
     Subprogram_Variant => (Decreases => Fuel);

   --  The positions of the rows backward search finds for P.
   function Locate (L : Locator; P : String) return Places
   with
     Pre  =>
       Valid (L) and then P'First = 1 and then P'Length <= 2 * Max_Length,
     Post =>
       Locate'Result'First = 1
       and then Locate'Result'Length
                = Search.Bound (L.Idx.Last, P, 1, False)
                  - Search.Bound (L.Idx.Last, P, 1, True)
       and then (for all K in Locate'Result'Range =>
                   Locate'Result (K)
                   = Resolve
                       (L,
                        Search.Bound (L.Idx.Last, P, 1, True) + K,
                        Rate - 1));

   --  L indexes the table Rows of S: its column, samples and positions.
   function Describes (S : String; Rows : Table; L : Locator) return Boolean
   is (L.Length = S'Length
       and then (for all I in 1 .. L.Length =>
                   L.Idx.Last (I) = Letter (S, Rows (I), Rows (I).Length - 1))
       and then (for all I in 1 .. L.Length =>
                   L.Sampled (I) = (Rows (I).Offset mod Rate = 0))
       and then (for all I in 1 .. L.Length =>
                   (if L.Sampled (I)
                    then
                      L.Value (Search.Hits (L.Sampled, I))
                      = Rows (I).First + Rows (I).Offset)))
   with Ghost, Pre => Well_Formed (S, Rows) and then Valid (L);

   function Build (S : String; Rows : Table) return Locator
   with
     Pre  => Well_Formed (S, Rows),
     Post => Valid (Build'Result) and then Describes (S, Rows, Build'Result);

   --  Found lists every occurrence of P once: positions of S, each reading
   --  its factor periodically.
   function Reports
     (S : String; F : Table; P : String; Found : Places) return Boolean
   is (Found'Length = Search.Occurrences (S, F, P)
       and then (for all K in Found'Range =>
                   Found (K) in 1 .. S'Length
                   and then Search.Occurs (S, F (Found (K)), P))
       and then (for all K in Found'Range =>
                   (for all J in Found'Range =>
                      (if K /= J then Found (K) /= Found (J)))))
   with
     Ghost,
     Pre =>
       Supported (S)
       and then Doubling.Cycles (S, F)
       and then P'First = 1
       and then P'Length <= 2 * S'Length;

   --  Locate is exact on any sorted cycle table on which LF is exact.
   procedure Locate_Rows
     (S : String; F, Rows : Table; Ties : Tie_Order; L : Locator; P : String)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Doubling.Cycles (S, F)
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, F)
       and then Sorted (S, Rows, Ties)
       and then Valid (L)
       and then Describes (S, Rows, L)
       and then (for all K in 1 .. S'Length =>
                   Rows (Walk (L.Idx.Last, K, 1)) = Previous (Rows (K)))
       and then P'First = 1
       and then P'Length <= 2 * S'Length,
     Post => Reports (S, F, P, Locate (L, P));

   --  The circular occurrences of P in a primitive S.
   procedure Classical_Locate (S, P : String)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Primitive (S)
       and then P'First = 1
       and then P'Length <= 2 * S'Length,
     Post =>
       Doubling.Cycles (S, Rotations_Of (S))
       and then Reports
                  (S,
                   Rotations_Of (S),
                   P,
                   Locate (Build (S, Classical_Sorted (S)), P));

   --  The occurrences of P in the periodic words of S's Lyndon factors.
   procedure Bijective_Locate (S, P : String)
   with
     Ghost,
     Pre  =>
       Supported (S) and then P'First = 1 and then P'Length <= 2 * S'Length,
     Post =>
       Doubling.Cycles (S, Lyndon_Factors (S))
       and then Reports
                  (S,
                   Lyndon_Factors (S),
                   P,
                   Locate (Build (S, Bijective_Sorted (S)), P));
end BWT.Locate;
