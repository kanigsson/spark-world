package BWT
  with SPARK_Mode
is
   --  Reference implementation: byte strings, normalized to a first index of 1.
   --  The bound keeps arithmetic small; no byte is reserved as a sentinel.
   Max_Length : constant := 1_024;

   function Supported (S : String) return Boolean
   is (S'First = 1 and then S'Length <= Max_Length);

   --  The vocabulary of the specifications below. It lives here, not in a
   --  child, because the encoders' postconditions cannot name a child's
   --  declarations. A rotation reads the factor S (First .. First + Length - 1)
   --  periodically, starting at Offset.
   type Rotation is record
      First  : Positive := 1;
      Length : Positive := 1;
      Offset : Natural := 0;
   end record;
   type Table is array (Positive range <>) of Rotation;

   function Valid (R : Rotation; N : Natural) return Boolean
   is (R.First <= N
       and then R.Length <= N - R.First + 1
       and then R.Offset < R.Length);

   --  Letter K of R's periodic word: its factor read from Offset, forever.
   function Letter (S : String; R : Rotation; K : Natural) return Character
   is (S (R.First + (R.Offset + K) mod R.Length))
   with
     Pre      =>
       Supported (S) and then Valid (R, S'Length) and then K <= 4 * Max_Length,
     Annotate => (GNATprove, Hide_Info, "Expression_Function_Body");

   function Equal_Prefix
     (S : String; A, B : Rotation; Size : Natural) return Boolean
   is (if Size = 0
       then True
       else
         Equal_Prefix (S, A, B, Size - 1)
         and then Letter (S, A, Size - 1) = Letter (S, B, Size - 1))
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Size <= 4 * Max_Length,
     Post               =>
       Equal_Prefix'Result
       = (for all K in 1 .. Size =>
            Letter (S, A, K - 1) = Letter (S, B, K - 1)),
     Subprogram_Variant => (Decreases => Size);

   function LE (S : String; A, B : Rotation; Size : Natural) return Boolean
   is (if Size = 0
       then True
       else
         LE (S, A, B, Size - 1)
         and then (if Equal_Prefix (S, A, B, Size - 1)
                   then Letter (S, A, Size - 1) <= Letter (S, B, Size - 1)))
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Size <= 4 * Max_Length,
     Post               =>
       LE'Result
       = (for all K in 1 .. Size =>
            (if Equal_Prefix (S, A, B, K - 1)
             then Letter (S, A, K - 1) <= Letter (S, B, K - 1))),
     Subprogram_Variant => (Decreases => Size);

   --  Rows whose periodic words agree are ordered by start position. The
   --  classical transform puts the earlier start first; the bijective one
   --  puts the later start first, which keeps every LF step exact.
   type Tie_Order is (Earlier_First, Later_First);

   function Tie_LE (A, B : Rotation; Ties : Tie_Order) return Boolean
   is (case Ties is
         when Earlier_First => A.First + A.Offset <= B.First + B.Offset,
         when Later_First   => A.First + A.Offset >= B.First + B.Offset)
   with
     Pre =>
       A.First <= Max_Length
       and then B.First <= Max_Length
       and then A.Offset <= Max_Length
       and then B.Offset <= Max_Length;

   function Key_LE
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
      return Boolean
   is (LE (S, A, B, 2 * S'Length)
       and then (if Equal_Prefix (S, A, B, 2 * S'Length)
                 then Tie_LE (A, B, Ties)))
   with
     Ghost,
     Pre      =>
       Supported (S) and then Valid (A, S'Length) and then Valid (B, S'Length),
     Annotate => (GNATprove, Hide_Info, "Expression_Function_Body");

   function Well_Formed (S : String; Rows : Table) return Boolean
   is (Supported (S)
       and then Rows'First = 1
       and then Rows'Length = S'Length
       and then (for all R of Rows => Valid (R, S'Length)));

   function Same_Rows (A, B : Table) return Boolean
   is (A'First = B'First
       and then A'Last = B'Last
       and then (for all I in A'Range =>
                   (for some J in B'Range => A (I) = B (J)))
       and then (for all I in B'Range =>
                   (for some J in A'Range => B (I) = A (J))))
   with Ghost;

   function Distinct (Rows : Table) return Boolean
   is (for all I in Rows'Range =>
         (for all J in Rows'Range => (if I /= J then Rows (I) /= Rows (J))))
   with Ghost;

   function Sorted
     (S : String; Rows : Table; Ties : Tie_Order := Earlier_First)
      return Boolean
   is (for all I in Rows'Range =>
         (for all J in I .. Rows'Last => Key_LE (S, Rows (I), Rows (J), Ties)))
   with Ghost, Pre => Well_Formed (S, Rows);

   --  Functional specifications of both transforms. Each is the last column of
   --  a table of rotations sorted by periodic word, a fixed tie order breaking
   --  ties. Comparing 2 * S'Length letters decides the periodic order of any
   --  two rotations. A faster encoder is correct when it meets the same
   --  predicate.

   --  Every rotation of S, by start position.
   function Rotations_Of (S : String) return Table
   with
     Ghost,
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Rotations_Of'Result'First = 1
       and then Rotations_Of'Result'Length = S'Length
       and then (for all I in Rotations_Of'Result'Range =>
                   Rotations_Of'Result (I) = (1, S'Length, I - 1));

   function Classical_Rows (S : String) return Table
   with
     Ghost,
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Well_Formed (S, Classical_Rows'Result)
       and then Distinct (Classical_Rows'Result)
       and then Same_Rows (Classical_Rows'Result, Rotations_Of (S))
       and then Sorted (S, Classical_Rows'Result, Earlier_First);

   --  Primary is the row holding S itself.
   function Is_Classical_BWT
     (S, Last : String; Primary : Natural) return Boolean
   is (Last'First = 1
       and then Last'Length = S'Length
       and then (if S'Length = 0
                 then Primary = 0
                 else
                   Primary in 1 .. S'Length
                   and then Classical_Rows (S) (Primary).Offset = 0)
       and then (for all I in Last'Range =>
                   Last (I)
                   = Letter (S, Classical_Rows (S) (I), S'Length - 1)))
   with Ghost, Pre => Supported (S);

   --  Row P describes the factor that contains position P, rotated to start
   --  there. Each factor precedes its other rotations, which makes it a
   --  Lyndon word, and factors never increase along S.
   function Lyndon_Factorization (S : String; Factors : Table) return Boolean
   is (Factors'First = 1
       and then Factors'Length = S'Length
       and then (for all P in Factors'Range =>
                   Valid (Factors (P), S'Length)
                   and then Factors (P).First + Factors (P).Offset = P
                   and then (for all Q in
                               Factors (P).First
                               .. Factors (P).First + Factors (P).Length - 1 =>
                               Factors (Q).First = Factors (P).First
                               and then Factors (Q).Length
                                        = Factors (P).Length))
       and then (for all P in Factors'Range =>
                   (if Factors (P).Offset > 0
                    then
                      not LE
                            (S,
                             Factors (P),
                             (Factors (P).First, Factors (P).Length, 0),
                             2 * S'Length)))
       and then (for all P in 2 .. Factors'Last =>
                   (if Factors (P).Offset = 0
                    then
                      LE
                        (S,
                         Factors (P),
                         (Factors (P - 1).First, Factors (P - 1).Length, 0),
                         2 * S'Length))))
   with Ghost, Pre => Supported (S);

   function Lyndon_Factors (S : String) return Table
   with
     Ghost,
     Global => null,
     Pre    => Supported (S),
     Post   => Lyndon_Factorization (S, Lyndon_Factors'Result);

   function Bijective_Rows (S : String) return Table
   with
     Ghost,
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Well_Formed (S, Bijective_Rows'Result)
       and then Distinct (Bijective_Rows'Result)
       and then Same_Rows (Bijective_Rows'Result, Lyndon_Factors (S))
       and then Sorted (S, Bijective_Rows'Result, Later_First);

   function Is_Bijective_BWT (S, Last : String) return Boolean
   is (Last'First = 1
       and then Last'Length = S'Length
       and then (for all I in Last'Range =>
                   Last (I)
                   = Letter
                       (S,
                        Bijective_Rows (S) (I),
                        Bijective_Rows (S) (I).Length - 1)))
   with Ghost, Pre => Supported (S);

   --  The tables above are determined by the rows they hold and their order:
   --  any sorted arrangement of the same rows is the same table.

   procedure Classical_Rows_Unique (S : String; Rows : Table)
   with
     Ghost,
     Global => null,
     Pre    =>
       Supported (S)
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, Rotations_Of (S))
       and then Sorted (S, Rows, Earlier_First),
     Post   => Rows = Classical_Rows (S);

   procedure Bijective_Rows_Unique (S : String; Rows : Table)
   with
     Ghost,
     Global => null,
     Pre    =>
       Supported (S)
       and then Well_Formed (S, Rows)
       and then Distinct (Rows)
       and then Same_Rows (Rows, Lyndon_Factors (S))
       and then Sorted (S, Rows, Later_First),
     Post   => Rows = Bijective_Rows (S);

   type Classical_Result (Length : Natural) is record
      Last    : String (1 .. Length);
      Primary : Natural;
   end record;

   --  Mathematical LF orbit; shared by the decoder contract and roundtrip
   --  proof. It is ghost code and does not participate in decoding.
   function Walk
     (Last : String; Primary : Positive; Steps : Natural) return Positive
   with
     Ghost,
     Global => null,
     Pre    =>
       Supported (Last)
       and then Primary in Last'Range
       and then Steps <= Last'Length,
     Post   => Walk'Result in Last'Range;

   function Classical_Encode (S : String) return Classical_Result
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Classical_Encode'Result.Length = S'Length
       and then (if S'Length = 0
                 then Classical_Encode'Result.Primary = 0
                 else Classical_Encode'Result.Primary in 1 .. S'Length)
       and then (for all K in 0 .. S'Length - 1 =>
                   Classical_Encode'Result.Last
                     (Walk
                        (Classical_Encode'Result.Last,
                         Classical_Encode'Result.Primary,
                         K))
                   = S (S'Length - K))
       and then Is_Classical_BWT
                  (S,
                   Classical_Encode'Result.Last,
                   Classical_Encode'Result.Primary);

   --  Decoding is defined for every in-range primary index. The roundtrip law
   --  applies to pairs produced by Classical_Encode, not arbitrary pairs.
   function Classical_Decode (Last : String; Primary : Natural) return String
   with
     Global => null,
     Pre    =>
       Supported (Last)
       and then (if Last'Length = 0
                 then Primary = 0
                 else Primary in 1 .. Last'Length),
     Post   =>
       Supported (Classical_Decode'Result)
       and then Classical_Decode'Result'Length = Last'Length
       and then (for all K in 0 .. Last'Length - 1 =>
                   Classical_Decode'Result (Last'Length - K)
                   = Last (Walk (Last, Primary, K)));

   function Bijective_Encode (S : String) return String
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Supported (Bijective_Encode'Result)
       and then Bijective_Encode'Result'Length = S'Length
       and then Is_Bijective_BWT (S, Bijective_Encode'Result);

   function Bijective_Decode (Last : String) return String
   with
     Global => null,
     Pre    => Supported (Last),
     Post   =>
       Supported (Bijective_Decode'Result)
       and then Bijective_Decode'Result'Length = Last'Length;
private
   --  The bijective inverse laws are proved where the implementation is
   --  visible; BWT.Theorems states them against the public functions.

   procedure Prove_Bijective_Round_Trip (S : String)
   with
     Ghost,
     Global => null,
     Pre    => Supported (S),
     Post   => Bijective_Decode (Bijective_Encode (S)) = S;

   procedure Prove_Bijective_Onto (Last : String)
   with
     Ghost,
     Global => null,
     Pre    => Supported (Last),
     Post   => Bijective_Encode (Bijective_Decode (Last)) = Last;
end BWT;
