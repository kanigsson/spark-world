with BWT.Counting;
with BWT.Doubling;

--  Backward search, the FM-index "count": how often a pattern occurs, from
--  the last column alone. Proved for the last column of any sorted cycle
--  table, and so for both transforms. On the classical transform it counts
--  circular occurrences in S. On the bijective one it counts occurrences in
--  the periodic words of the Lyndon factors.

package BWT.Search
  with SPARK_Mode
is
   use BWT.Counting;

   --  How many of F (1 .. Through) are set.
   function Hits (F : Flags; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else Hits (F, Through - 1) + (if F (Through) then 1 else 0))
   with
     Ghost,
     Pre                =>
       F'First = 1
       and then F'Length <= Max_Length
       and then Through <= F'Length,
     Post               => Hits'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   --  The rows that one backward step keeps below a bound T: those whose
   --  last letter is below C, and those ending in C at a row up to T.
   function Step_Flags (Last : String; C : Character; T : Natural) return Flags
   is ([for I in 1 .. Last'Length =>
          Last (I) < C or else (Last (I) = C and then I <= T)])
   with Ghost, Pre => Supported (Last);

   --  The bound after reading P (J .. P'Last) backwards. Strict bounds count
   --  the rows below the pattern, the others the rows up to it.
   function Bound
     (Last, P : String; J : Positive; Strict : Boolean) return Natural
   is (if J > P'Length
       then (if Strict then 0 else Last'Length)
       else
         Hits
           (Step_Flags (Last, P (J), Bound (Last, P, J + 1, Strict)),
            Last'Length))
   with
     Ghost,
     Pre                =>
       Supported (Last)
       and then P'First = 1
       and then P'Length <= 2 * Max_Length
       and then J <= P'Length + 1,
     Post               => Bound'Result <= Last'Length,
     Subprogram_Variant => (Decreases => P'Length + 1 - J);

   function Count (Last, P : String) return Natural
   with
     Pre  =>
       Supported (Last)
       and then P'First = 1
       and then P'Length <= 2 * Max_Length,
     Post =>
       Count'Result = Bound (Last, P, 1, False) - Bound (Last, P, 1, True);

   --  R's periodic word starts with P.
   function Occurs (S : String; R : Rotation; P : String) return Boolean
   is (for all K in P'Range => Letter (S, R, K - 1) = P (K))
   with
     Ghost,
     Pre =>
       Supported (S)
       and then Valid (R, S'Length)
       and then P'First = 1
       and then P'Length <= 2 * S'Length;

   function Occurrence_Flags (S : String; F : Table; P : String) return Flags
   is ([for Q in 1 .. S'Length => Occurs (S, F (Q), P)])
   with
     Ghost,
     Pre =>
       Supported (S)
       and then Doubling.Cycles (S, F)
       and then P'First = 1
       and then P'Length <= 2 * S'Length;

   --  How many positions start an occurrence of P, each reading its own
   --  factor periodically.
   function Occurrences (S : String; F : Table; P : String) return Natural
   is (Hits (Occurrence_Flags (S, F, P), S'Length))
   with
     Ghost,
     Pre =>
       Supported (S)
       and then Doubling.Cycles (S, F)
       and then P'First = 1
       and then P'Length <= 2 * S'Length;

   --  On the last column of any sorted cycle table, the rows between the
   --  two bounds are those whose words start with P.
   procedure Matching_Rows
     (S : String; F, Rows : Table; Ties : Tie_Order; Last, P : String)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Doubling.Cycles (S, F)
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, F)
       and then Sorted (S, Rows, Ties)
       and then Last'First = 1
       and then Last'Length = S'Length
       and then (for all I in Last'Range =>
                   Last (I) = Letter (S, Rows (I), Rows (I).Length - 1))
       and then P'First = 1
       and then P'Length <= 2 * S'Length,
     Post =>
       (for all I in Rows'Range =>
          Occurs (S, Rows (I), P)
          = (I > Bound (Last, P, 1, True)
             and then I <= Bound (Last, P, 1, False)));

   --  Count is exact on the last column of any sorted cycle table.
   procedure Count_Rows
     (S : String; F, Rows : Table; Ties : Tie_Order; Last, P : String)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Doubling.Cycles (S, F)
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, F)
       and then Sorted (S, Rows, Ties)
       and then Last'First = 1
       and then Last'Length = S'Length
       and then (for all I in Last'Range =>
                   Last (I) = Letter (S, Rows (I), Rows (I).Length - 1))
       and then P'First = 1
       and then P'Length <= 2 * S'Length,
     Post => Count (Last, P) = Occurrences (S, F, P);

   --  Circular occurrences of P in S.
   procedure Classical_Count (S, P : String)
   with
     Ghost,
     Pre  =>
       Supported (S) and then P'First = 1 and then P'Length <= 2 * S'Length,
     Post =>
       Doubling.Cycles (S, Rotations_Of (S))
       and then Count (Classical_Encode (S).Last, P)
                = Occurrences (S, Rotations_Of (S), P);

   --  Occurrences of P in the periodic words of S's Lyndon factors.
   procedure Bijective_Count (S, P : String)
   with
     Ghost,
     Pre  =>
       Supported (S) and then P'First = 1 and then P'Length <= 2 * S'Length,
     Post =>
       Doubling.Cycles (S, Lyndon_Factors (S))
       and then Count (Bijective_Encode (S), P)
                = Occurrences (S, Lyndon_Factors (S), P);
end BWT.Search;
