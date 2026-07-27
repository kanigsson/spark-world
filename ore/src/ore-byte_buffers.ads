--  Ore.Byte_Buffers — bounded byte buffers with produce/consume cursors.
--
--  A Buffer is a fixed-capacity array of octets plus two cursors: a write
--  position (how many bytes have been produced) and a read position (how many
--  of those have been consumed).  Producers append at the write position,
--  consumers take from the read position, and the invariant
--
--     0 <= Read_Position <= Length <= Capacity
--
--  holds at every point.  Nothing here raises to report a full or an empty
--  buffer: the checked operations carry preconditions, and the bulk
--  operations report how much they moved through a Transfer result.
--
--  WHAT THIS PACKAGE IS FOR.  Every codec, wire protocol and syscall shim
--  written in SPARK ends up re-deriving the same handful of facts about the
--  byte arrays it fills: that a write left the earlier bytes alone, that two
--  ranges hold equal content, that a multi-byte field reads back as the value
--  that was stored, and that a back-reference copy is well defined even where
--  source and destination overlap.  Those facts are the deliverable of this
--  package, not the cursor bookkeeping:
--
--    * Same_Prefix / Matches_At — what a produce operation preserves and what
--      it establishes; the framing and content vocabulary of the contracts.
--    * Equal_Ranges / Unchanged_Outside — the same two ideas on plain arrays,
--      for clients whose data is not in a Buffer.
--    * Load_16/32/64 and Store_16/32/64 — checked multi-byte access in either
--      byte order, with the store/load round trip as a postcondition.
--    * Copies_Back — the forward-copy equation of a back-reference, valid for
--      overlapping as well as disjoint copies.
--
--  MODEL.  Contents is the ghost model: the produced bytes as an ordinary
--  Byte_Array indexed from 1.  Contracts prefer element-wise statements over
--  it — the model is there so clients can state whole-buffer equalities, not
--  because the proofs need a separate mathematical sequence.
--
--  All ghost entities sit at the Static assertion level, so an
--  assertion-enabled build pays for the cheap Runtime clauses only, and never
--  copies a buffer to evaluate a 'Old.

package Ore.Byte_Buffers with SPARK_Mode => On is

   ---------------------------------------------------------------------------
   --  Proof vocabulary over plain byte arrays
   ---------------------------------------------------------------------------

   --  Count bytes from From_Left in Left equal Count bytes from From_Right in
   --  Right.  Bounds are part of the predicate rather than a precondition, and
   --  are written in subtraction form so no index arithmetic can overflow; an
   --  empty range is always equal.  This is the "same content, possibly at a
   --  different offset" relation that checksum, search and copy contracts need.
   function Equal_Ranges
     (Left, Right           : Byte_Array;
      From_Left, From_Right : Index;
      Count                 : Natural) return Boolean
   is
     (Count = 0
      or else
        (From_Left >= Left'First
         and then From_Left <= Left'Last
         and then Count - 1 <= Left'Last - From_Left
         and then From_Right >= Right'First
         and then From_Right <= Right'Last
         and then Count - 1 <= Right'Last - From_Right
         and then
           (for all K in 0 .. Count - 1 =>
              Left (From_Left + K) = Right (From_Right + K))))
   with Ghost => Static;

   --  After is Before outside the half-open window First .. Past_Last - 1:
   --  the frame condition of every operation that writes a bounded window of
   --  an array.  Both arrays must have the same bounds.
   function Unchanged_Outside
     (Before, After : Byte_Array;
      First         : Index;
      Past_Last     : Positive) return Boolean
   is
     (Before'First = After'First
      and then Before'Last = After'Last
      and then First <= Past_Last
      and then
        (for all I in Before'Range =>
           (if I < First or else I >= Past_Last then After (I) = Before (I))))
   with Ghost => Static;

   --  Equal content is transitive.  Stated with three independent offsets
   --  because the three ranges are typically in three different buffers.
   procedure Lemma_Equal_Ranges_Trans
     (Left, Middle, Right                : Byte_Array;
      From_Left, From_Middle, From_Right : Index;
      Count                              : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Equal_Ranges (Left, Middle, From_Left, From_Middle, Count)
       and then Equal_Ranges (Middle, Right, From_Middle, From_Right, Count),
     Post   => Equal_Ranges (Left, Right, From_Left, From_Right, Count);

   ---------------------------------------------------------------------------
   --  Checked multi-byte access and endian conversion
   ---------------------------------------------------------------------------

   --  The 2, 4 or 8 bytes at From, read as one value in the given order.  The
   --  preconditions are the bounds check — "the field fits" — in subtraction
   --  form.  These are expression functions on purpose: a client proving
   --  something about the bytes of a field it wrote by hand needs to see the
   --  arithmetic, not just a contract.
   function Load_16
     (A : Byte_Array; From : Index; Order : Byte_Order) return Word16
   is
     (case Order is
        when Little_Endian =>
          Word16 (A (From))
          + 2 ** 8 * Word16 (A (From + 1)),
        when Big_Endian    =>
          2 ** 8 * Word16 (A (From))
          + Word16 (A (From + 1)))
   with
     Global => null,
     Pre    => From >= A'First and then From <= A'Last
               and then A'Last - From >= 1;

   function Load_32
     (A : Byte_Array; From : Index; Order : Byte_Order) return Word32
   is
     (case Order is
        when Little_Endian =>
          Word32 (A (From))
          + 2 ** 8  * Word32 (A (From + 1))
          + 2 ** 16 * Word32 (A (From + 2))
          + 2 ** 24 * Word32 (A (From + 3)),
        when Big_Endian    =>
          2 ** 24 * Word32 (A (From))
          + 2 ** 16 * Word32 (A (From + 1))
          + 2 ** 8  * Word32 (A (From + 2))
          + Word32 (A (From + 3)))
   with
     Global => null,
     Pre    => From >= A'First and then From <= A'Last
               and then A'Last - From >= 3;

   function Load_64
     (A : Byte_Array; From : Index; Order : Byte_Order) return Word64
   is
     (case Order is
        when Little_Endian =>
          Word64 (A (From))
          + 2 ** 8  * Word64 (A (From + 1))
          + 2 ** 16 * Word64 (A (From + 2))
          + 2 ** 24 * Word64 (A (From + 3))
          + 2 ** 32 * Word64 (A (From + 4))
          + 2 ** 40 * Word64 (A (From + 5))
          + 2 ** 48 * Word64 (A (From + 6))
          + 2 ** 56 * Word64 (A (From + 7)),
        when Big_Endian    =>
          2 ** 56 * Word64 (A (From))
          + 2 ** 48 * Word64 (A (From + 1))
          + 2 ** 40 * Word64 (A (From + 2))
          + 2 ** 32 * Word64 (A (From + 3))
          + 2 ** 24 * Word64 (A (From + 4))
          + 2 ** 16 * Word64 (A (From + 5))
          + 2 ** 8  * Word64 (A (From + 6))
          + Word64 (A (From + 7)))
   with
     Global => null,
     Pre    => From >= A'First and then From <= A'Last
               and then A'Last - From >= 7;

   --  Write Value at From in the given order.  The postcondition is the round
   --  trip — the field reads back as the value stored — together with the
   --  frame condition that nothing outside the field moved.
   procedure Store_16
     (A     : in out Byte_Array;
      From  : Index;
      Value : Word16;
      Order : Byte_Order)
   with
     Global => null,
     Pre    => From >= A'First and then From <= A'Last
               and then A'Last - From >= 1,
     Post   =>
       (Runtime => Load_16 (A, From, Order) = Value,
        Static  => Unchanged_Outside (A'Old, A, From, From + 2));

   procedure Store_32
     (A     : in out Byte_Array;
      From  : Index;
      Value : Word32;
      Order : Byte_Order)
   with
     Global => null,
     Pre    => From >= A'First and then From <= A'Last
               and then A'Last - From >= 3,
     Post   =>
       (Runtime => Load_32 (A, From, Order) = Value,
        Static  => Unchanged_Outside (A'Old, A, From, From + 4));

   procedure Store_64
     (A     : in out Byte_Array;
      From  : Index;
      Value : Word64;
      Order : Byte_Order)
   with
     Global => null,
     Pre    => From >= A'First and then From <= A'Last
               and then A'Last - From >= 7,
     Post   =>
       (Runtime => Load_64 (A, From, Order) = Value,
        Static  => Unchanged_Outside (A'Old, A, From, From + 8));

   --  A load reads its own bytes and nothing else: equal fields load equal
   --  values, wherever they sit.  This is what carries a stored field across a
   --  copy into a larger frame, or relates a writer's field to a reader's.
   procedure Lemma_Load_16_Frame
     (Left, Right           : Byte_Array;
      From_Left, From_Right : Index;
      Order                 : Byte_Order)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       From_Left >= Left'First and then From_Left <= Left'Last
       and then Left'Last - From_Left >= 1
       and then From_Right >= Right'First and then From_Right <= Right'Last
       and then Right'Last - From_Right >= 1
       and then Equal_Ranges (Left, Right, From_Left, From_Right, 2),
     Post   =>
       Load_16 (Left, From_Left, Order) = Load_16 (Right, From_Right, Order);

   procedure Lemma_Load_32_Frame
     (Left, Right           : Byte_Array;
      From_Left, From_Right : Index;
      Order                 : Byte_Order)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       From_Left >= Left'First and then From_Left <= Left'Last
       and then Left'Last - From_Left >= 3
       and then From_Right >= Right'First and then From_Right <= Right'Last
       and then Right'Last - From_Right >= 3
       and then Equal_Ranges (Left, Right, From_Left, From_Right, 4),
     Post   =>
       Load_32 (Left, From_Left, Order) = Load_32 (Right, From_Right, Order);

   procedure Lemma_Load_64_Frame
     (Left, Right           : Byte_Array;
      From_Left, From_Right : Index;
      Order                 : Byte_Order)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       From_Left >= Left'First and then From_Left <= Left'Last
       and then Left'Last - From_Left >= 7
       and then From_Right >= Right'First and then From_Right <= Right'Last
       and then Right'Last - From_Right >= 7
       and then Equal_Ranges (Left, Right, From_Left, From_Right, 8),
     Post   =>
       Load_64 (Left, From_Left, Order) = Load_64 (Right, From_Right, Order);

   ---------------------------------------------------------------------------
   --  The buffer type
   ---------------------------------------------------------------------------

   subtype Capacity_Range is Natural range 0 .. Max_Capacity;

   --  Capacity is a discriminant rather than a generic formal so that one
   --  subprogram can serve buffers of every size.  A default-initialized
   --  buffer is empty and zero-filled: initialization is not left to the
   --  caller's discipline.
   type Buffer (Capacity : Capacity_Range) is private
   with Default_Initial_Condition => Is_Empty (Buffer);

   --  Bytes produced so far — the write position.
   function Length (B : Buffer) return Natural
   with Global => null, Post => Length'Result <= B.Capacity;

   --  Bytes consumed so far — the read position.  The next byte a consumer
   --  sees is at position Read_Position + 1.
   function Read_Position (B : Buffer) return Natural
   with Global => null, Post => Read_Position'Result <= Length (B);

   --  How many more bytes can be produced.
   function Available (B : Buffer) return Natural
   with Global => null, Post => Available'Result = B.Capacity - Length (B);

   --  How many produced bytes have not been consumed.
   function Unread (B : Buffer) return Natural
   with Global => null, Post => Unread'Result = Length (B) - Read_Position (B);

   function Is_Empty (B : Buffer) return Boolean
   with Global => null, Post => Is_Empty'Result = (Length (B) = 0);

   function Is_Full (B : Buffer) return Boolean
   with Global => null, Post => Is_Full'Result = (Available (B) = 0);

   --  The produced byte at a 1-based position.  Positions above the write
   --  position hold no data, whether or not storage exists for them.
   function Element (B : Buffer; Position : Positive) return Byte
   with Global => null, Pre => Position <= Length (B);

   --  The ghost model: the produced bytes, indexed from 1.
   function Contents (B : Buffer) return Byte_Array
   with
     Ghost  => Static,
     Global => null,
     Post   =>
       Contents'Result'First = 1
       and then Contents'Result'Length = Length (B)
       and then
         (for all Position in 1 .. Length (B) =>
            Contents'Result (Position) = Element (B, Position));

   ---------------------------------------------------------------------------
   --  Proof vocabulary over buffers
   ---------------------------------------------------------------------------

   --  Left and Right agree on their first Count produced bytes.  This is what
   --  a produce operation preserves: "the bytes already there did not move".
   function Same_Prefix (Left, Right : Buffer; Count : Natural) return Boolean
   is
     (Count <= Length (Left)
      and then Count <= Length (Right)
      and then
        (for all Position in 1 .. Count =>
           Element (Left, Position) = Element (Right, Position)))
   with Ghost => Static;

   --  The produced bytes of B starting at From are exactly Bytes.  This is
   --  what a produce operation establishes.  Like Equal_Ranges the bounds are
   --  part of the predicate, in subtraction form.
   function Matches_At
     (B     : Buffer;
      From  : Positive;
      Bytes : Byte_Array) return Boolean
   is
     (From <= Length (B) + 1
      and then Bytes'Length <= Length (B) - (From - 1)
      and then
        (for all K in 0 .. Bytes'Length - 1 =>
           Element (B, From + K) = Bytes (Bytes'First + K)))
   with Ghost => Static;

   --  After is Before with Count bytes appended by a back-reference Distance
   --  bytes long: the forward-copy equation of an LZ77-style match.  The first
   --  Distance appended bytes come from the pre-existing content; beyond that
   --  the copy reads bytes this very operation wrote, which is what makes a
   --  short distance repeat its window.  Disjoint copies are the special case
   --  Count <= Distance.
   function Copies_Back
     (Before, After : Buffer;
      Distance      : Positive;
      Count         : Natural) return Boolean
   is
     (Distance <= Length (Before)
      and then Count <= Max_Capacity
      and then Length (After) = Length (Before) + Count
      and then Same_Prefix (Before, After, Length (Before))
      and then
        (for all K in 0 .. Count - 1 =>
           Element (After, Length (Before) + 1 + K) =
             (if K < Distance
              then Element (Before, Length (Before) + 1 + K - Distance)
              else Element (After, Length (Before) + 1 + K - Distance))))
   with Ghost => Static;

   ---------------------------------------------------------------------------
   --  Multi-byte access within a buffer
   ---------------------------------------------------------------------------

   --  The field of produced bytes at From, read as one value.  Defined as the
   --  array-level load over the model, so the two views never disagree.
   function Load_16
     (B : Buffer; From : Positive; Order : Byte_Order) return Word16
   with
     Global => null,
     Pre    => From <= Length (B) and then Length (B) - From >= 1,
     Post   =>
       (Static => Load_16'Result = Load_16 (Contents (B), From, Order));

   function Load_32
     (B : Buffer; From : Positive; Order : Byte_Order) return Word32
   with
     Global => null,
     Pre    => From <= Length (B) and then Length (B) - From >= 3,
     Post   =>
       (Static => Load_32'Result = Load_32 (Contents (B), From, Order));

   function Load_64
     (B : Buffer; From : Positive; Order : Byte_Order) return Word64
   with
     Global => null,
     Pre    => From <= Length (B) and then Length (B) - From >= 7,
     Post   =>
       (Static => Load_64'Result = Load_64 (Contents (B), From, Order));

   ---------------------------------------------------------------------------
   --  Producing
   ---------------------------------------------------------------------------

   procedure Append (B : in out Buffer; Value : Byte)
   with
     Global => null,
     Pre    => Available (B) >= 1,
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + 1
          and then Read_Position (B) = Read_Position (B)'Old
          and then Element (B, Length (B)) = Value,
        Static  => Same_Prefix (B'Old, B, Length (B)'Old));

   procedure Append (B : in out Buffer; Bytes : Byte_Array)
   with
     Global => null,
     Pre    => Bytes'Length <= Available (B),
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + Bytes'Length
          and then Read_Position (B) = Read_Position (B)'Old,
        Static  =>
          Same_Prefix (B'Old, B, Length (B)'Old)
          and then Matches_At (B, Length (B)'Old + 1, Bytes));

   --  Append Count copies of Value.
   procedure Append_Fill (B : in out Buffer; Value : Byte; Count : Natural)
   with
     Global => null,
     Pre    => Count <= Available (B),
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + Count
          and then Read_Position (B) = Read_Position (B)'Old,
        Static  =>
          Same_Prefix (B'Old, B, Length (B)'Old)
          and then
            (for all K in 1 .. Count =>
               Element (B, Length (B)'Old + K) = Value));

   procedure Append_16
     (B : in out Buffer; Value : Word16; Order : Byte_Order)
   with
     Global => null,
     Pre    => Available (B) >= 2,
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + 2
          and then Read_Position (B) = Read_Position (B)'Old
          and then Load_16 (B, Length (B)'Old + 1, Order) = Value,
        Static  => Same_Prefix (B'Old, B, Length (B)'Old));

   procedure Append_32
     (B : in out Buffer; Value : Word32; Order : Byte_Order)
   with
     Global => null,
     Pre    => Available (B) >= 4,
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + 4
          and then Read_Position (B) = Read_Position (B)'Old
          and then Load_32 (B, Length (B)'Old + 1, Order) = Value,
        Static  => Same_Prefix (B'Old, B, Length (B)'Old));

   procedure Append_64
     (B : in out Buffer; Value : Word64; Order : Byte_Order)
   with
     Global => null,
     Pre    => Available (B) >= 8,
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + 8
          and then Read_Position (B) = Read_Position (B)'Old
          and then Load_64 (B, Length (B)'Old + 1, Order) = Value,
        Static  => Same_Prefix (B'Old, B, Length (B)'Old));

   --  How much a bulk operation moved.  Consumed and Produced coincide for a
   --  plain byte transfer; they are reported separately because the pair is
   --  the shape every filter and codec returns, and a caller that loops needs
   --  both halves to advance its own cursors.
   type Transfer is record
      Consumed : Natural := 0;   --  bytes taken from the source
      Produced : Natural := 0;   --  bytes written to the target
   end record;

   --  Append as much of Bytes as fits and report how much moved.  This is the
   --  form to use when a short transfer is normal rather than an error; the
   --  checked Append above is the form that must not lose data.
   procedure Put
     (B      : in out Buffer;
      Bytes  : Byte_Array;
      Result :    out Transfer)
   with
     Global => null,
     Post   =>
       (Runtime =>
          Result.Consumed = Natural'Min (Bytes'Length, Available (B)'Old)
          and then Result.Produced = Result.Consumed
          and then Length (B) = Length (B)'Old + Result.Produced
          and then Read_Position (B) = Read_Position (B)'Old,
        Static  =>
          Same_Prefix (B'Old, B, Length (B)'Old)
          and then
            (for all K in 0 .. Result.Consumed - 1 =>
               Element (B, Length (B)'Old + 1 + K) = Bytes (Bytes'First + K)));

   ---------------------------------------------------------------------------
   --  Consuming
   ---------------------------------------------------------------------------

   --  The unread byte at Offset, without consuming it.
   function Peek (B : Buffer; Offset : Natural := 0) return Byte
   with
     Global => null,
     Pre    => Offset < Unread (B),
     Post   => Peek'Result = Element (B, Read_Position (B) + 1 + Offset);

   --  Advance the read position without looking at the bytes.
   procedure Consume (B : in out Buffer; Count : Natural)
   with
     Global => null,
     Pre    => Count <= Unread (B),
     Post   =>
       (Runtime =>
          Read_Position (B) = Read_Position (B)'Old + Count
          and then Length (B) = Length (B)'Old,
        Static  => Same_Prefix (B'Old, B, Length (B)));

   procedure Read (B : in out Buffer; Value : out Byte)
   with
     Global => null,
     Pre    => Unread (B) >= 1,
     Post   =>
       (Runtime =>
          Read_Position (B) = Read_Position (B)'Old + 1
          and then Length (B) = Length (B)'Old
          and then Value = Element (B, Read_Position (B)),
        Static  => Same_Prefix (B'Old, B, Length (B)));

   --  Read exactly Into'Length bytes.  Fails its precondition rather than
   --  returning short, so Into is fully written.
   procedure Read (B : in out Buffer; Into : out Byte_Array)
   with
     Global => null,
     Pre    => Into'Length <= Unread (B),
     Post   =>
       (Runtime =>
          Read_Position (B) = Read_Position (B)'Old + Into'Length
          and then Length (B) = Length (B)'Old,
        Static  =>
          Same_Prefix (B'Old, B, Length (B))
          and then Matches_At (B, Read_Position (B)'Old + 1, Into));

   procedure Read_16
     (B : in out Buffer; Value : out Word16; Order : Byte_Order)
   with
     Global => null,
     Pre    => Unread (B) >= 2,
     Post   =>
       (Runtime =>
          Read_Position (B) = Read_Position (B)'Old + 2
          and then Length (B) = Length (B)'Old
          and then Value = Load_16 (B, Read_Position (B)'Old + 1, Order),
        Static  => Same_Prefix (B'Old, B, Length (B)));

   procedure Read_32
     (B : in out Buffer; Value : out Word32; Order : Byte_Order)
   with
     Global => null,
     Pre    => Unread (B) >= 4,
     Post   =>
       (Runtime =>
          Read_Position (B) = Read_Position (B)'Old + 4
          and then Length (B) = Length (B)'Old
          and then Value = Load_32 (B, Read_Position (B)'Old + 1, Order),
        Static  => Same_Prefix (B'Old, B, Length (B)));

   procedure Read_64
     (B : in out Buffer; Value : out Word64; Order : Byte_Order)
   with
     Global => null,
     Pre    => Unread (B) >= 8,
     Post   =>
       (Runtime =>
          Read_Position (B) = Read_Position (B)'Old + 8
          and then Length (B) = Length (B)'Old
          and then Value = Load_64 (B, Read_Position (B)'Old + 1, Order),
        Static  => Same_Prefix (B'Old, B, Length (B)));

   --  Take as many unread bytes as Into holds and report how much moved.
   --  Into is `in out` because a short transfer leaves its tail alone; pass an
   --  initialized array from SPARK code.
   procedure Get
     (B      : in out Buffer;
      Into   : in out Byte_Array;
      Result :    out Transfer)
   with
     Global => null,
     Post   =>
       (Runtime =>
          Result.Consumed = Natural'Min (Into'Length, Unread (B)'Old)
          and then Result.Produced = Result.Consumed
          and then Read_Position (B) = Read_Position (B)'Old + Result.Consumed
          and then Length (B) = Length (B)'Old,
        Static  =>
          Same_Prefix (B'Old, B, Length (B))
          and then
            (for all K in 0 .. Result.Produced - 1 =>
               Into (Into'First + K) =
                 Element (B, Read_Position (B)'Old + 1 + K))
          and then
            (for all K in Result.Produced .. Into'Length - 1 =>
               Into (Into'First + K) = Into'Old (Into'First + K)));

   --  Move unread bytes from Source into Target, as many as both allow.
   procedure Move
     (Source : in out Buffer;
      Target : in out Buffer;
      Result :    out Transfer)
   with
     Global => null,
     Post   =>
       (Runtime =>
          Result.Consumed =
            Natural'Min (Unread (Source)'Old, Available (Target)'Old)
          and then Result.Produced = Result.Consumed
          and then Read_Position (Source) =
                     Read_Position (Source)'Old + Result.Consumed
          and then Length (Source) = Length (Source)'Old
          and then Length (Target) = Length (Target)'Old + Result.Produced
          and then Read_Position (Target) = Read_Position (Target)'Old,
        Static  =>
          Same_Prefix (Source'Old, Source, Length (Source))
          and then Same_Prefix (Target'Old, Target, Length (Target)'Old)
          and then
            (for all K in 0 .. Result.Produced - 1 =>
               Element (Target, Length (Target)'Old + 1 + K) =
                 Element (Source, Read_Position (Source)'Old + 1 + K)));

   ---------------------------------------------------------------------------
   --  Cursor and content management
   ---------------------------------------------------------------------------

   --  Drop everything: both cursors return to zero.  Storage is not scrubbed;
   --  the bytes above the write position are not readable through Element.
   procedure Clear (B : in out Buffer)
   with
     Global => null,
     Post   => Length (B) = 0 and then Read_Position (B) = 0;

   --  Re-read from the beginning of the produced bytes.
   procedure Rewind (B : in out Buffer)
   with
     Global => null,
     Post   =>
       (Runtime => Read_Position (B) = 0 and then Length (B) = Length (B)'Old,
        Static  => Same_Prefix (B'Old, B, Length (B)));

   --  Move the write position back, discarding produced bytes that have not
   --  been consumed.
   procedure Truncate (B : in out Buffer; New_Length : Natural)
   with
     Global => null,
     Pre    => New_Length in Read_Position (B) .. Length (B),
     Post   =>
       (Runtime =>
          Length (B) = New_Length
          and then Read_Position (B) = Read_Position (B)'Old,
        Static  => Same_Prefix (B'Old, B, New_Length));

   --  Discard the consumed prefix, moving the unread bytes to the front.  The
   --  read position becomes zero and the freed space becomes available.  This
   --  is the operation that makes a buffer reusable in a streaming loop, and
   --  the reason a buffer needs an overlapping move at all.
   procedure Compact (B : in out Buffer)
   with
     Global => null,
     Post   =>
       (Runtime =>
          Read_Position (B) = 0 and then Length (B) = Unread (B)'Old,
        Static  =>
          (for all K in 1 .. Length (B) =>
             Element (B, K) = Element (B'Old, Read_Position (B'Old) + K)));

   ---------------------------------------------------------------------------
   --  Subviews
   ---------------------------------------------------------------------------

   --  A half-open range of produced positions.  Past_Last is one past the last
   --  byte, so an empty span has First = Past_Last and a span of the whole
   --  content ends at Length + 1 — which is why positions stop one short of
   --  Positive'Last.
   type Span is record
      First     : Index := 1;
      Past_Last : Index := 1;
   end record
   with Predicate => Span.First <= Span.Past_Last;

   function Length (S : Span) return Natural is (S.Past_Last - S.First);

   function Is_Valid_Span (B : Buffer; S : Span) return Boolean is
     (S.Past_Last <= Length (B) + 1);

   --  Everything produced.
   function Written_Span (B : Buffer) return Span
   with
     Global => null,
     Post   =>
       Written_Span'Result = (First => 1, Past_Last => Length (B) + 1)
       and then Is_Valid_Span (B, Written_Span'Result);

   --  Everything produced and not yet consumed.
   function Unread_Span (B : Buffer) return Span
   with
     Global => null,
     Post   =>
       Unread_Span'Result =
         (First => Read_Position (B) + 1, Past_Last => Length (B) + 1)
       and then Is_Valid_Span (B, Unread_Span'Result)
       and then Length (Unread_Span'Result) = Unread (B);

   --  A copy of the bytes a span designates.  This is a copy, not a view: a
   --  non-owning view type is a separate subject, and a Span together with its
   --  buffer already serves wherever a view would only be read.
   function Slice (B : Buffer; S : Span) return Byte_Array
   with
     Global => null,
     Pre    => Is_Valid_Span (B, S),
     Post   =>
       Slice'Result'First = 1
       and then Slice'Result'Length = Length (S)
       and then
         (for all K in 0 .. Length (S) - 1 =>
            Slice'Result (1 + K) = Element (B, S.First + K));

   --  Append a subview of one buffer to another without an intermediate array.
   procedure Append_Slice
     (Target : in out Buffer;
      Source : in     Buffer;
      S      : in     Span)
   with
     Global => null,
     Pre    =>
       Is_Valid_Span (Source, S) and then Length (S) <= Available (Target),
     Post   =>
       (Runtime =>
          Length (Target) = Length (Target)'Old + Length (S)
          and then Read_Position (Target) = Read_Position (Target)'Old,
        Static  =>
          Same_Prefix (Target'Old, Target, Length (Target)'Old)
          and then
            (for all K in 0 .. Length (S) - 1 =>
               Element (Target, Length (Target)'Old + 1 + K) =
                 Element (Source, S.First + K)));

   ---------------------------------------------------------------------------
   --  Copies
   ---------------------------------------------------------------------------

   --  Append Count bytes copied from Distance bytes back — a back-reference,
   --  the operation an LZ77-style decompressor performs after validating a
   --  (length, distance) pair.  Copying is forward and overlap is intended:
   --  when Distance < Count the window repeats, which is how run-length
   --  expansion is expressed.  See Copies_Back for the exact equation.
   procedure Append_Copy
     (B        : in out Buffer;
      Distance : Positive;
      Count    : Natural)
   with
     Global => null,
     Pre    => Distance <= Length (B) and then Count <= Available (B),
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + Count
          and then Read_Position (B) = Read_Position (B)'Old,
        Static  => Copies_Back (B'Old, B, Distance, Count));

   --  Where the copy does not reach into its own output, the equation is plain
   --  equality with the source range: the disjoint-copy reading of
   --  Copies_Back, for clients that never overlap and should not have to
   --  unfold the recurrence.
   procedure Lemma_Copies_Back_Disjoint
     (Before, After : Buffer;
      Distance      : Positive;
      Count         : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Count <= Distance
       and then Copies_Back (Before, After, Distance, Count),
     Post   =>
       (for all K in 0 .. Count - 1 =>
          Element (After, Length (Before) + 1 + K) =
            Element (Before, Length (Before) + 1 + K - Distance));

   --  A distance-one back-reference repeats one byte: every appended byte is
   --  the last byte of the content the copy started from.  This is run-length
   --  expansion, and the induction it needs — each copied byte is equal to the
   --  one before it, all the way back to the original — is done once here
   --  rather than in every client.
   procedure Lemma_Copies_Back_Run
     (Before, After : Buffer;
      Count         : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Length (Before) >= 1
       and then Copies_Back (Before, After, 1, Count),
     Post   =>
       (for all K in 1 .. Count =>
          Element (After, Length (Before) + K) =
            Element (Before, Length (Before)));

   ---------------------------------------------------------------------------
   --  Buffer lemmas
   ---------------------------------------------------------------------------

   --  Prefix preservation composes: what survived two produce operations in
   --  turn survived the pair.  A loop that appends once per iteration carries
   --  its invariant with this.
   procedure Lemma_Same_Prefix_Trans
     (First, Middle, Last : Buffer;
      Count               : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Same_Prefix (First, Middle, Count)
       and then Same_Prefix (Middle, Last, Count),
     Post   => Same_Prefix (First, Last, Count);

   --  A match established before a later produce operation still holds after
   --  it, provided the match lies inside the preserved prefix.  This is the
   --  framing lemma: it is what lets a client build a structure incrementally
   --  and keep the facts proved about the parts already written.
   procedure Lemma_Matches_At_Frame
     (Before, After : Buffer;
      From          : Positive;
      Bytes         : Byte_Array;
      Count         : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Same_Prefix (Before, After, Count)
       and then Matches_At (Before, From, Bytes)
       and then From <= Count + 1
       and then Bytes'Length <= Count - (From - 1),
     Post   => Matches_At (After, From, Bytes);

   --  Two matches that abut are one match on the concatenation.  Consecutive
   --  appends therefore describe the whole they produced, which is how a
   --  writer states its postcondition in terms of its output as a unit.
   procedure Lemma_Matches_At_Concat
     (B     : Buffer;
      From  : Positive;
      Left  : Byte_Array;
      Right : Byte_Array)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Matches_At (B, From, Left)
       and then Matches_At (B, From + Left'Length, Right),
     Post   =>
       (for all K in 0 .. Left'Length + Right'Length - 1 =>
          Element (B, From + K) =
            (if K < Left'Length
             then Left (Left'First + K)
             else Right (Right'First + (K - Left'Length))));

   --  Element-wise agreement over the whole content is model equality: a
   --  client that proved a prefix relation can state its result as one
   --  Contents equality.
   procedure Lemma_Contents_Equal (Left, Right : Buffer)
   with
     Ghost  => Static,
     Global => null,
     Pre    =>
       Length (Left) = Length (Right)
       and then Same_Prefix (Left, Right, Length (Left)),
     Post   => Contents (Left) = Contents (Right);

private

   type Buffer (Capacity : Capacity_Range) is record
      Data          : Byte_Array (1 .. Capacity) := (others => 0);
      Written       : Natural := 0;
      Read_Consumed : Natural := 0;
   end record
   with Predicate =>
     Buffer.Written <= Buffer.Capacity
     and then Buffer.Read_Consumed <= Buffer.Written;

   function Length (B : Buffer) return Natural is (B.Written);

   function Read_Position (B : Buffer) return Natural is (B.Read_Consumed);

   function Available (B : Buffer) return Natural is (B.Capacity - B.Written);

   function Unread (B : Buffer) return Natural is
     (B.Written - B.Read_Consumed);

   function Is_Empty (B : Buffer) return Boolean is (B.Written = 0);

   function Is_Full (B : Buffer) return Boolean is (B.Written = B.Capacity);

   function Element (B : Buffer; Position : Positive) return Byte is
     (B.Data (Position));

   function Load_16
     (B : Buffer; From : Positive; Order : Byte_Order) return Word16
   is (Load_16 (B.Data, From, Order));

   function Load_32
     (B : Buffer; From : Positive; Order : Byte_Order) return Word32
   is (Load_32 (B.Data, From, Order));

   function Load_64
     (B : Buffer; From : Positive; Order : Byte_Order) return Word64
   is (Load_64 (B.Data, From, Order));

   function Written_Span (B : Buffer) return Span is
     (First => 1, Past_Last => B.Written + 1);

   function Unread_Span (B : Buffer) return Span is
     (First => B.Read_Consumed + 1, Past_Last => B.Written + 1);

end Ore.Byte_Buffers;
