package BWT.Ranks
  with SPARK_Mode
is
   type Mapping is array (Positive range <>) of Positive;

   function Ordered (Last : String; A, B : Positive) return Boolean
   is (Last (A) < Last (B) or else (Last (A) = Last (B) and then A <= B))
   with
     Pre => Supported (Last) and then A in Last'Range and then B in Last'Range;

   function Rank
     (Last : String; Row : Positive; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else
         Rank (Last, Row, Through - 1)
         + (if Ordered (Last, Through, Row) then 1 else 0))
   with
     Ghost,
     Pre                =>
       Supported (Last)
       and then Row in Last'Range
       and then Through <= Last'Length,
     Post               =>
       Rank'Result <= Through
       and then (if Through >= Row then Rank'Result >= 1),
     Subprogram_Variant => (Decreases => Through);

   procedure Strict_Ranks (Last : String; A, B : Positive)
   with
     Ghost,
     Pre  =>
       Supported (Last)
       and then A in Last'Range
       and then B in Last'Range
       and then A /= B
       and then Ordered (Last, A, B),
     Post => Rank (Last, A, Last'Length) < Rank (Last, B, Last'Length);

   function Permutation (Map : Mapping) return Boolean
   is (Map'First = 1
       and then Map'Length <= Max_Length
       and then (for all P of Map => P in Map'Range)
       and then (for all I in Map'Range =>
                   (for all J in Map'Range =>
                      (if I /= J then Map (I) /= Map (J)))))
   with Ghost;

   function LF (Last : String) return Mapping
   with
     Pre  => Supported (Last),
     Post =>
       LF'Result'First = 1
       and then LF'Result'Length = Last'Length
       and then Permutation (LF'Result)
       and then (for all I in Last'Range =>
                   LF'Result (I) = Rank (Last, I, Last'Length))
       and then (for all I in Last'Range =>
                   (for all J in Last'Range =>
                      (Ordered (Last, I, J)
                       = (LF'Result (I) <= LF'Result (J)))));

   --  The LF orbit from Primary. It is stated here, beside LF, so that every
   --  unit reasoning about decoding shares one definition.
   function Walk
     (Last : String; Primary : Positive; Steps : Natural) return Positive
   is (if Steps = 0
       then Primary
       else LF (Last) (Walk (Last, Primary, Steps - 1)))
   with
     Ghost,
     Pre                =>
       Supported (Last)
       and then Primary in Last'Range
       and then Steps <= Last'Length,
     Post               => Walk'Result in Last'Range,
     Subprogram_Variant => (Decreases => Steps),
     Annotate           => (GNATprove, Hide_Info, "Expression_Function_Body");

   --  The only unfolding of Walk that proofs need; keeping the body hidden
   --  elsewhere stops provers from unrolling the recursion indefinitely.
   procedure Walk_Step (Last : String; Primary : Positive; Steps : Natural)
   with
     Ghost,
     Pre  =>
       Supported (Last)
       and then Primary in Last'Range
       and then Steps < Last'Length,
     Post =>
       Walk (Last, Primary, 0) = Primary
       and then Walk (Last, Primary, Steps + 1)
                = LF (Last) (Walk (Last, Primary, Steps));
end BWT.Ranks;
