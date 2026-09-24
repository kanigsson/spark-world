package BWT.Rotations
  with SPARK_Mode
is
   function Previous (R : Rotation) return Rotation
   is (R.First,
       R.Length,
       (if R.Offset = 0 then R.Length - 1 else R.Offset - 1))
   with
     Pre  => R.Offset < R.Length,
     Post =>
       Previous'Result.First = R.First
       and then Previous'Result.Length = R.Length
       and then Previous'Result.Offset < R.Length;

   procedure Previous_Injective (A, B : Rotation)
   with
     Ghost,
     Pre  => A.Offset < A.Length and then B.Offset < B.Length,
     Post => ((Previous (A) = Previous (B)) = (A = B));

   procedure Shift_Letter (S : String; R : Rotation; K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S) and then Valid (R, S'Length) and then K <= 4 * Max_Length,
     Post =>
       Letter (S, Previous (R), K)
       = (if K = 0 then Letter (S, R, R.Length - 1) else Letter (S, R, K - 1));

   procedure Equal_Same (S : String; A, B : Rotation; Size : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Size <= 4 * Max_Length
       and then A = B,
     Post => Equal_Prefix (S, A, B, Size);

   procedure Period (S : String; A : Rotation; K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then K in A.Length .. 4 * Max_Length,
     Post => Letter (S, A, K) = Letter (S, A, K - A.Length);

   procedure Prefix_Letter (S : String; A, B : Rotation; Size, K : Natural)
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Size <= 4 * Max_Length
       and then K < Size
       and then Equal_Prefix (S, A, B, Size),
     Post               => Letter (S, A, K) = Letter (S, B, K),
     Subprogram_Variant => (Decreases => Size);

   procedure Order_Laws (S : String; A, B, C : Rotation; Size : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Valid (C, S'Length)
       and then Size <= 4 * Max_Length,
     Post =>
       (LE (S, A, B, Size) or LE (S, B, A, Size))
       and then ((LE (S, A, B, Size) and LE (S, B, A, Size))
                 = Equal_Prefix (S, A, B, Size))
       and then (if LE (S, A, B, Size) and LE (S, B, C, Size)
                 then LE (S, A, C, Size));

   procedure Extend_Equality (S : String; A, B : Rotation; Size : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Size in A.Length + B.Length .. 4 * Max_Length
       and then Equal_Prefix (S, A, B, A.Length + B.Length),
     Post => Equal_Prefix (S, A, B, Size);

   procedure Decide (S : String; A, B : Rotation; K, Size : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Size <= 4 * Max_Length
       and then K < Size
       and then Equal_Prefix (S, A, B, K)
       and then Letter (S, A, K) /= Letter (S, B, K),
     Post =>
       LE (S, A, B, Size) = (Letter (S, A, K) < Letter (S, B, K))
       and then not Equal_Prefix (S, A, B, Size);

   --  A letter before the rotation wraps around its factor.
   procedure Letter_Direct (S : String; R : Rotation; K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (R, S'Length)
       and then K <= 4 * Max_Length
       and then R.Offset + K < R.Length,
     Post => Letter (S, R, K) = S (R.First + R.Offset + K);

   --  A letter after the rotation has wrapped around once.
   procedure Letter_Wrap (S : String; R : Rotation; K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (R, S'Length)
       and then K <= 4 * Max_Length
       and then R.Offset + K in R.Length .. 2 * R.Length - 1,
     Post => Letter (S, R, K) = S (R.First + R.Offset + K - R.Length);

   --  Reading D letters further is reading from a rotation D letters on.
   function Advance (R : Rotation; D : Natural) return Rotation
   is (R.First,
       R.Length,
       (if R.Offset + D < R.Length
        then R.Offset + D
        else R.Offset + D - R.Length))
   with
     Pre =>
       R.Offset < R.Length
       and then D < R.Length
       and then R.Length <= Max_Length;

   procedure Letter_Advance (S : String; R : Rotation; D, K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (R, S'Length)
       and then D < R.Length
       and then D <= K
       and then K <= 4 * Max_Length,
     Post =>
       Valid (Advance (R, D), S'Length)
       and then Letter (S, R, K) = Letter (S, Advance (R, D), K - D);

   --  The rotation one letter on.
   function Next_Rot (R : Rotation) return Rotation
   is (R.First,
       R.Length,
       (if R.Offset + 1 < R.Length then R.Offset + 1 else 0))
   with Pre => R.Offset < R.Length and then R.Length <= Max_Length;

   procedure Letter_Next (S : String; R : Rotation; K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S) and then Valid (R, S'Length) and then K < 4 * Max_Length,
     Post =>
       Valid (Next_Rot (R), S'Length)
       and then Letter (S, R, K + 1) = Letter (S, Next_Rot (R), K);

   --  Comparing K + 1 letters is comparing the first, then K more.
   procedure Order_Next (S : String; A, B : Rotation; K : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then K < 4 * Max_Length,
     Post =>
       Equal_Prefix (S, A, B, K + 1)
       = (Letter (S, A, 0) = Letter (S, B, 0)
          and then Equal_Prefix (S, Next_Rot (A), Next_Rot (B), K))
       and then LE (S, A, B, K + 1)
                = (Letter (S, A, 0) < Letter (S, B, 0)
                   or else (Letter (S, A, 0) = Letter (S, B, 0)
                            and then LE (S, Next_Rot (A), Next_Rot (B), K)));

   --  Comparing H + M letters is comparing H, then M more from H letters on.
   procedure Order_Split (S : String; A, B : Rotation; H, M : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then H < A.Length
       and then H < B.Length
       and then M <= 4 * Max_Length - H,
     Post =>
       Equal_Prefix (S, A, B, H + M)
       = (Equal_Prefix (S, A, B, H)
          and then Equal_Prefix (S, Advance (A, H), Advance (B, H), M))
       and then LE (S, A, B, H + M)
                = ((LE (S, A, B, H) and then not Equal_Prefix (S, A, B, H))
                   or else (Equal_Prefix (S, A, B, H)
                            and then LE
                                       (S,
                                        Advance (A, H),
                                        Advance (B, H),
                                        M)));

   --  Rotations of one length compare alike on every horizon from H on, once
   --  H covers a mismatch or a whole period.
   procedure Settled (S : String; A, B : Rotation; H, Size : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then A.Length = B.Length
       and then H <= Size
       and then Size <= 4 * Max_Length
       and then (H >= A.Length or else not Equal_Prefix (S, A, B, H)),
     Post =>
       LE (S, A, B, H) = LE (S, A, B, Size)
       and then Equal_Prefix (S, A, B, H) = Equal_Prefix (S, A, B, Size);

   --  The first letter where two rotations differ, or Size.
   function Mismatch
     (S : String; A, B : Rotation; Size : Natural) return Natural
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Size <= 4 * Max_Length,
     Post =>
       Mismatch'Result <= Size
       and then Equal_Prefix (S, A, B, Mismatch'Result)
       and then Equal_Prefix (S, B, A, Mismatch'Result)
       and then (if Mismatch'Result < Size
                 then
                   Letter (S, A, Mismatch'Result)
                   /= Letter (S, B, Mismatch'Result)
                 else Equal_Prefix (S, A, B, Size));

   function Less (S : String; A, B : Rotation) return Boolean
   with
     Pre  =>
       Supported (S) and then Valid (A, S'Length) and then Valid (B, S'Length),
     Post => Less'Result = not LE (S, B, A, 2 * S'Length);

   procedure Key_Order
     (S : String; A, B, C : Rotation; Ties : Tie_Order := Earlier_First)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Valid (C, S'Length),
     Post =>
       (Key_LE (S, A, B, Ties) or Key_LE (S, B, A, Ties))
       and then (if Key_LE (S, A, B, Ties) and Key_LE (S, B, C, Ties)
                 then Key_LE (S, A, C, Ties));

   procedure Key_Weakening
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Key_LE (S, A, B, Ties),
     Post => LE (S, A, B, 2 * S'Length);

   procedure Key_Intro
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then LE (S, A, B, 2 * S'Length)
       and then (if Equal_Prefix (S, A, B, 2 * S'Length)
                 then Tie_LE (A, B, Ties)),
     Post => Key_LE (S, A, B, Ties);

   procedure Key_Tie
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Key_LE (S, A, B, Ties)
       and then Equal_Prefix (S, A, B, 2 * S'Length),
     Post => Tie_LE (A, B, Ties);

   procedure Key_Antisym
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Key_LE (S, A, B, Ties)
       and then Key_LE (S, B, A, Ties),
     Post =>
       Equal_Prefix (S, A, B, 2 * S'Length)
       and then A.First + A.Offset = B.First + B.Offset;

   procedure Equal_Prefix_Shorter (S : String; A, B : Rotation; H, K : Natural)
   with
     Ghost,
     Pre                =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then H <= 4 * Max_Length
       and then K <= H
       and then Equal_Prefix (S, A, B, H),
     Post               => Equal_Prefix (S, A, B, K),
     Subprogram_Variant => (Decreases => H);

   --  Rotations of one length that agree for a full period agree forever.
   procedure Same_Length_Extend
     (S : String; A, B : Rotation; H, Size : Natural)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then A.Length = B.Length
       and then H in A.Length .. 4 * Max_Length
       and then Size <= 4 * Max_Length
       and then Equal_Prefix (S, A, B, H),
     Post => Equal_Prefix (S, A, B, Size);

   procedure Equal_Horizon (S : String; A, B : Rotation)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then S'Length > 0
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Equal_Prefix (S, A, B, 2 * S'Length - 1),
     Post => Equal_Prefix (S, A, B, 2 * S'Length);

   --  Removing a shared first letter keeps the order.
   procedure Unprepend (S : String; A, B : Rotation)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then S'Length > 0
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Letter (S, A, A.Length - 1) = Letter (S, B, B.Length - 1)
       and then LE (S, Previous (A), Previous (B), 2 * S'Length),
     Post => LE (S, A, B, 2 * S'Length);

   procedure Equivalent_Order (S : String; A, B, C : Rotation)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then Valid (C, S'Length)
       and then Equal_Prefix (S, A, B, 2 * S'Length),
     Post =>
       (LE (S, A, C, 2 * S'Length) = LE (S, B, C, 2 * S'Length))
       and then (LE (S, C, A, 2 * S'Length) = LE (S, C, B, 2 * S'Length))
       and then (Equal_Prefix (S, A, C, 2 * S'Length)
                 = Equal_Prefix (S, B, C, 2 * S'Length));

   procedure Prepend_Order (S : String; A, B : Rotation)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then (Letter (S, A, A.Length - 1) < Letter (S, B, B.Length - 1)
                 or else (Letter (S, A, A.Length - 1)
                          = Letter (S, B, B.Length - 1)
                          and then LE (S, A, B, 2 * S'Length))),
     Post => LE (S, Previous (A), Previous (B), 2 * S'Length);

   procedure Shift_Equal (S : String; A, B : Rotation)
   with
     Ghost,
     Pre  =>
       Supported (S)
       and then Valid (A, S'Length)
       and then Valid (B, S'Length)
       and then A.Length = B.Length
       and then Equal_Prefix (S, A, B, 2 * S'Length),
     Post => Equal_Prefix (S, Previous (A), Previous (B), 2 * S'Length);

   procedure Classical_Character (S : String; Steps : Natural)
   with
     Ghost,
     Pre  => Supported (S) and then Steps < S'Length,
     Post =>
       Letter
         (S,
          (1, S'Length, (if Steps = 0 then 0 else S'Length - Steps)),
          S'Length - 1)
       = S (S'Length - Steps);

   function Key_Less
     (S : String; A, B : Rotation; Ties : Tie_Order := Earlier_First)
      return Boolean
   with
     Pre  =>
       Supported (S) and then Valid (A, S'Length) and then Valid (B, S'Length),
     Post => Key_Less'Result = not Key_LE (S, B, A, Ties);
end BWT.Rotations;
