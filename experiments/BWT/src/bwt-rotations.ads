package BWT.Rotations with SPARK_Mode is
   type Rotation is record
      First  : Positive := 1;
      Length : Positive := 1;
      Offset : Natural := 0;
   end record;
   type Table is array (Positive range <>) of Rotation;

   function Valid (R : Rotation; N : Natural) return Boolean is
     (R.First <= N and then R.Length <= N - R.First + 1
      and then R.Offset < R.Length);

   function Letter (S : String; R : Rotation; K : Natural) return Character
   with Pre => Supported (S) and then Valid (R, S'Length)
     and then K <= 4 * Max_Length,
     Annotate => (GNATprove, Hide_Info, "Expression_Function_Body");

   function Previous (R : Rotation) return Rotation is
     (R.First, R.Length, (if R.Offset = 0 then R.Length - 1 else R.Offset - 1))
   with Pre => R.Offset < R.Length,
     Post => Previous'Result.First = R.First
       and then Previous'Result.Length = R.Length
       and then Previous'Result.Offset < R.Length;

   procedure Previous_Injective (A, B : Rotation)
   with Ghost, Pre => A.Offset < A.Length and then B.Offset < B.Length,
     Post => ((Previous (A) = Previous (B)) = (A = B));

   procedure Shift_Letter (S : String; R : Rotation; K : Natural)
   with Ghost, Pre => Supported (S) and then Valid (R, S'Length)
     and then K <= 4 * Max_Length,
     Post => Letter (S, Previous (R), K) =
       (if K = 0 then Letter (S, R, R.Length - 1) else Letter (S, R, K - 1));

   function Equal_Prefix (S : String; A, B : Rotation; Size : Natural)
     return Boolean is
     (if Size = 0 then True else
        Equal_Prefix (S, A, B, Size - 1)
          and then Letter (S, A, Size - 1) = Letter (S, B, Size - 1))
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Size <= 4 * Max_Length,
     Post => Equal_Prefix'Result =
       (for all K in 1 .. Size => Letter (S, A, K - 1) = Letter (S, B, K - 1)),
     Subprogram_Variant => (Decreases => Size);

   function LE (S : String; A, B : Rotation; Size : Natural)
     return Boolean is
     (if Size = 0 then True else
        LE (S, A, B, Size - 1)
          and then (if Equal_Prefix (S, A, B, Size - 1)
                    then Letter (S, A, Size - 1) <= Letter (S, B, Size - 1)))
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Size <= 4 * Max_Length,
     Post => LE'Result =
       (for all K in 1 .. Size =>
         (if Equal_Prefix (S, A, B, K - 1)
          then Letter (S, A, K - 1) <= Letter (S, B, K - 1))),
     Subprogram_Variant => (Decreases => Size);

   procedure Equal_Same (S : String; A, B : Rotation; Size : Natural)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Size <= 4 * Max_Length
     and then A = B,
     Post => Equal_Prefix (S, A, B, Size);

   procedure Period (S : String; A : Rotation; K : Natural)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then K in A.Length .. 4 * Max_Length,
     Post => Letter (S, A, K) = Letter (S, A, K - A.Length);

   procedure Prefix_Letter (S : String; A, B : Rotation; Size, K : Natural)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Size <= 4 * Max_Length
     and then K < Size and then Equal_Prefix (S, A, B, Size),
     Post => Letter (S, A, K) = Letter (S, B, K),
     Subprogram_Variant => (Decreases => Size);

   procedure Order_Laws (S : String; A, B, C : Rotation; Size : Natural)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Valid (C, S'Length)
     and then Size <= 4 * Max_Length,
     Post => (LE (S, A, B, Size) or LE (S, B, A, Size))
       and then ((LE (S, A, B, Size) and LE (S, B, A, Size)) =
         Equal_Prefix (S, A, B, Size))
       and then (if LE (S, A, B, Size) and LE (S, B, C, Size)
                 then LE (S, A, C, Size));

   procedure Extend_Equality (S : String; A, B : Rotation; Size : Natural)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length)
     and then Size in A.Length + B.Length .. 4 * Max_Length
     and then Equal_Prefix (S, A, B, A.Length + B.Length),
     Post => Equal_Prefix (S, A, B, Size);

   function Less (S : String; A, B : Rotation) return Boolean
   with Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length),
     Post => Less'Result = not LE (S, B, A, 2 * S'Length);

   --  Rows whose periodic words agree are ordered by start position. The
   --  classical transform puts the earlier start first; the bijective one
   --  puts the later start first, which keeps every LF step exact.
   type Tie_Order is (Earlier_First, Later_First);

   function Tie_LE (A, B : Rotation; Ties : Tie_Order) return Boolean is
     (case Ties is
        when Earlier_First => A.First + A.Offset <= B.First + B.Offset,
        when Later_First => A.First + A.Offset >= B.First + B.Offset)
   with Pre => A.First <= Max_Length and then B.First <= Max_Length
     and then A.Offset <= Max_Length and then B.Offset <= Max_Length;

   function Key_LE
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
     return Boolean is
     (LE (S, A, B, 2 * S'Length)
       and then (if Equal_Prefix (S, A, B, 2 * S'Length)
                 then Tie_LE (A, B, Ties)))
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length),
     Annotate => (GNATprove, Hide_Info, "Expression_Function_Body");

   procedure Key_Order
     (S : String; A, B, C : Rotation; Ties : Tie_Order := Earlier_First)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Valid (C, S'Length),
     Post => (Key_LE (S, A, B, Ties) or Key_LE (S, B, A, Ties))
       and then (if Key_LE (S, A, B, Ties) and Key_LE (S, B, C, Ties)
                 then Key_LE (S, A, C, Ties));

   procedure Key_Weakening
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Key_LE (S, A, B, Ties),
     Post => LE (S, A, B, 2 * S'Length);

   procedure Equivalent_Order (S : String; A, B, C : Rotation)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then Valid (C, S'Length)
     and then Equal_Prefix (S, A, B, 2 * S'Length),
     Post => (LE (S, A, C, 2 * S'Length) = LE (S, B, C, 2 * S'Length))
       and then (LE (S, C, A, 2 * S'Length) = LE (S, C, B, 2 * S'Length))
       and then (Equal_Prefix (S, A, C, 2 * S'Length) =
         Equal_Prefix (S, B, C, 2 * S'Length));

   procedure Prepend_Order (S : String; A, B : Rotation)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length)
     and then (Letter (S, A, A.Length - 1) < Letter (S, B, B.Length - 1)
       or else (Letter (S, A, A.Length - 1) = Letter (S, B, B.Length - 1)
         and then LE (S, A, B, 2 * S'Length))),
     Post => LE (S, Previous (A), Previous (B), 2 * S'Length);

   procedure Shift_Equal (S : String; A, B : Rotation)
   with Ghost, Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length) and then A.Length = B.Length
     and then Equal_Prefix (S, A, B, 2 * S'Length),
     Post => Equal_Prefix (S, Previous (A), Previous (B), 2 * S'Length);

   procedure Classical_Character (S : String; Steps : Natural)
   with Ghost, Pre => Supported (S) and then Steps < S'Length,
     Post => Letter
       (S, (1, S'Length, (if Steps = 0 then 0 else S'Length - Steps)),
        S'Length - 1) = S (S'Length - Steps);

   function Key_Less
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
     return Boolean
   with Pre => Supported (S) and then Valid (A, S'Length)
     and then Valid (B, S'Length),
     Post => Key_Less'Result = not Key_LE (S, B, A, Ties);
end BWT.Rotations;
