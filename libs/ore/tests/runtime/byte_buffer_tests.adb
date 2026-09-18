--  Runtime tests for Ore.Byte_Buffers. The contracts are checked as the test
--  runs (-gnata), so every call is also a test of the Runtime-level clauses;
--  what the assertions below add is the actual byte values, which a
--  postcondition about cursors and framing does not pin down for a reader.

with Ada.Text_IO;      use Ada.Text_IO;
with Test_Checks;      use Test_Checks;
with Ore;              use Ore;
with Ore.Byte_Buffers; use Ore.Byte_Buffers;

procedure Byte_Buffer_Tests is

   ---------------------------------------------------------------------------

   procedure Test_Append_And_Read is
      B     : Buffer (16);
      Value : Byte;
      Out_3 : Byte_Array (1 .. 3);
   begin
      Check
        (Is_Empty (B) and then Available (B) = 16, "fresh buffer is empty");

      Append (B, 16#AA#);
      Append (B, Byte_Array'(16#01#, 16#02#, 16#03#));
      Append_Fill (B, 16#FF#, 2);

      Check (Length (B) = 6, "length after appends");
      Check (Unread (B) = 6, "nothing consumed yet");
      Check (Element (B, 1) = 16#AA#, "first byte");
      Check (Element (B, 4) = 16#03#, "third appended byte");
      Check (Element (B, 6) = 16#FF#, "fill byte");

      Read (B, Value);
      Check (Value = 16#AA# and then Read_Position (B) = 1, "read one byte");

      Check (Peek (B) = 16#01#, "peek does not consume");
      Check (Peek (B, 2) = 16#03#, "peek at offset");

      Read (B, Out_3);
      Check (Out_3 = Byte_Array'(16#01#, 16#02#, 16#03#), "read three bytes");
      Check (Unread (B) = 2, "two bytes left");

      Consume (B, 2);
      Check (Unread (B) = 0 and then Length (B) = 6, "consume the rest");

      Rewind (B);
      Check (Unread (B) = 6, "rewind re-reads everything");

      Truncate (B, 3);
      Check (Length (B) = 3 and then Element (B, 3) = 16#02#, "truncate");

      Clear (B);
      Check (Is_Empty (B) and then Read_Position (B) = 0, "clear");
   end Test_Append_And_Read;

   ---------------------------------------------------------------------------

   procedure Test_Endian is
      B   : Buffer (32);
      W16 : Word16;
      W32 : Word32;
      W64 : Word64;
   begin
      Append_16 (B, 16#1234#, Little_Endian);
      Check
        (Element (B, 1) = 16#34# and then Element (B, 2) = 16#12#,
         "little-endian 16-bit layout");

      Append_16 (B, 16#1234#, Big_Endian);
      Check
        (Element (B, 3) = 16#12# and then Element (B, 4) = 16#34#,
         "big-endian 16-bit layout");

      Append_32 (B, 16#DEAD_BEEF#, Big_Endian);
      Check
        (Element (B, 5) = 16#DE# and then Element (B, 8) = 16#EF#,
         "big-endian 32-bit layout");

      Append_64 (B, 16#0102_0304_0506_0708#, Little_Endian);
      Check
        (Element (B, 9) = 16#08# and then Element (B, 16) = 16#01#,
         "little-endian 64-bit layout");

      Read_16 (B, W16, Little_Endian);
      Check (W16 = 16#1234#, "16-bit round trip, little endian");

      Read_16 (B, W16, Big_Endian);
      Check (W16 = 16#1234#, "16-bit round trip, big endian");

      Read_32 (B, W32, Big_Endian);
      Check (W32 = 16#DEAD_BEEF#, "32-bit round trip, big endian");

      Read_64 (B, W64, Little_Endian);
      Check
        (W64 = 16#0102_0304_0506_0708#, "64-bit round trip, little endian");

      Check (Unread (B) = 0, "everything read back");
   end Test_Endian;

   ---------------------------------------------------------------------------

   procedure Test_Transfers is
      B      : Buffer (4);
      Source : Buffer (8);
      Target : Buffer (3);
      Result : Transfer;
      Into   : Byte_Array (1 .. 4) := (others => 0);
   begin
      --  Put stops at the capacity and reports what it took.
      Put (B, Byte_Array'(1, 2, 3, 4, 5, 6), Result);
      Check
        (Result.Consumed = 4 and then Result.Produced = 4,
         "short put reports four bytes");
      Check (Length (B) = 4 and then Is_Full (B), "buffer filled");

      --  Get stops at the unread bytes and leaves the tail of Into alone.
      Consume (B, 2);
      Get (B, Into, Result);
      Check (Result.Consumed = 2, "short get reports two bytes");
      Check (Into = Byte_Array'(3, 4, 0, 0), "get leaves the tail alone");

      Append (Source, Byte_Array'(9, 8, 7, 6, 5));
      Move (Source, Target, Result);
      Check (Result.Produced = 3, "move stops at target capacity");
      Check
        (Element (Target, 1) = 9 and then Element (Target, 3) = 7,
         "moved bytes");
      Check (Unread (Source) = 2, "source advanced by what moved");
   end Test_Transfers;

   ---------------------------------------------------------------------------

   procedure Test_Spans is
      B      : Buffer (16);
      Target : Buffer (16);
      S      : Span;
   begin
      Append (B, Byte_Array'(10, 20, 30, 40, 50));
      Consume (B, 2);

      Check (Written_Span (B) = (First => 1, Past_Last => 6), "written span");
      Check (Unread_Span (B) = (First => 3, Past_Last => 6), "unread span");
      Check (Length (Unread_Span (B)) = 3, "unread span length");

      S := (First => 2, Past_Last => 5);
      Check (Slice (B, S) = Byte_Array'(20, 30, 40), "slice of a span");
      Check
        (Slice (B, (First => 3, Past_Last => 3))'Length = 0, "empty slice");

      Append_Slice (Target, B, S);
      Check
        (Length (Target) = 3 and then Element (Target, 2) = 30,
         "append a subview");
   end Test_Spans;

   ---------------------------------------------------------------------------

   procedure Test_Copies is
      B : Buffer (32);
   begin
      --  Distance one: a run of the preceding byte.
      Append (B, 16#5A#);
      Append_Copy (B, 1, 4);
      Check (Length (B) = 5, "run length");
      Check
        ((for all I in 1 .. 5 => Element (B, I) = 16#5A#),
         "distance-one copy repeats one byte");

      --  Disjoint copy: the source range ends before the destination starts.
      Clear (B);
      Append (B, Byte_Array'(1, 2, 3, 4));
      Append_Copy (B, 4, 4);
      Check
        (Slice (B, Written_Span (B)) = Byte_Array'(1, 2, 3, 4, 1, 2, 3, 4),
         "disjoint copy duplicates the window");

      --  Overlapping copy: the window repeats because the copy reads bytes it
      --  has just written.
      Clear (B);
      Append (B, Byte_Array'(7, 8));
      Append_Copy (B, 2, 5);
      Check
        (Slice (B, Written_Span (B)) = Byte_Array'(7, 8, 7, 8, 7, 8, 7),
         "overlapping copy repeats the window");

      --  Zero-length copies are legal and change nothing.
      Clear (B);
      Append (B, 1);
      Append_Copy (B, 1, 0);
      Check (Length (B) = 1, "empty copy");
   end Test_Copies;

   ---------------------------------------------------------------------------

   procedure Test_Compact is
      B : Buffer (8);
   begin
      Append (B, Byte_Array'(1, 2, 3, 4, 5, 6, 7, 8));
      Check (Available (B) = 0, "full");

      Consume (B, 5);
      Compact (B);
      Check (Read_Position (B) = 0, "compaction resets the read position");
      Check (Length (B) = 3 and then Available (B) = 5, "space reclaimed");
      Check
        (Slice (B, Written_Span (B)) = Byte_Array'(6, 7, 8),
         "unread bytes moved to the front");

      --  Compacting a buffer with nothing consumed is a no-op.
      Compact (B);
      Check (Length (B) = 3 and then Element (B, 1) = 6, "idempotent compact");
   end Test_Compact;

   ---------------------------------------------------------------------------

   procedure Test_Small_State_Spaces is
      Input : constant Byte_Array (1 .. 8) := (1, 2, 3, 4, 5, 6, 7, 8);
   begin
      --  Exercise every small capacity through a fill, partial consume,
      --  compaction and refill. This checks the cursor/content interaction at
      --  every boundary, including zero capacity.
      for Capacity in 0 .. 8 loop
         declare
            B        : Buffer (Capacity);
            Result   : Transfer;
            Consumed : constant Natural := Capacity / 2;
            Kept     : constant Natural := Capacity - Consumed;
         begin
            Put (B, Input, Result);
            Check
              (Result.Produced = Capacity and then Length (B) = Capacity,
               "small-state fill");

            Consume (B, Consumed);
            Compact (B);
            Check
              (Read_Position (B) = 0
               and then Length (B) = Kept
               and then (for all K in 1 .. Kept =>
                           Element (B, K) = Byte (Consumed + K)),
               "small-state compact");

            Append_Fill (B, 16#EE#, Consumed);
            Check
              (Length (B) = Capacity
               and then (for all K in Kept + 1 .. Capacity =>
                           Element (B, K) = 16#EE#),
               "small-state refill");
         end;
      end loop;

      --  Exhaust the overlap shapes for small back-references. Expected is
      --  updated front to back, independently of Append_Copy.
      for Base in 1 .. 6 loop
         for Distance in 1 .. Base loop
            for Count in 0 .. 8 - Base loop
               declare
                  B        : Buffer (8);
                  Expected : Byte_Array (1 .. 8) := (others => 0);
               begin
                  for I in 1 .. Base loop
                     Expected (I) := Byte (17 * I + Base);
                     Append (B, Expected (I));
                  end loop;

                  if Count > 0 then
                     for K in 0 .. Count - 1 loop
                        Expected (Base + 1 + K) :=
                          Expected (Base + 1 + K - Distance);
                     end loop;
                  end if;

                  Append_Copy (B, Distance, Count);
                  Check
                    (Length (B) = Base + Count
                     and then (for all I in 1 .. Base + Count =>
                                 Element (B, I) = Expected (I)),
                     "small-state back-reference");
               end;
            end loop;
         end loop;
      end loop;
   end Test_Small_State_Spaces;

   ---------------------------------------------------------------------------

   procedure Test_Endian_Edges is
      A      : Byte_Array (5 .. 20) := (others => 16#A5#);
      Before : Byte_Array (A'Range);
   begin
      for Order in Byte_Order loop
         A := (others => 16#A5#);
         Before := A;
         Store_16 (A, A'First, 16#1234#, Order);
         Check
           (Load_16 (A, A'First, Order) = 16#1234#
            and then (for all I in A'Range =>
                        (if I > A'First + 1 then A (I) = Before (I))),
            "16-bit store at first position");

         A := (others => 16#A5#);
         Before := A;
         Store_16 (A, A'Last - 1, 16#ABCD#, Order);
         Check
           (Load_16 (A, A'Last - 1, Order) = 16#ABCD#
            and then (for all I in A'Range =>
                        (if I < A'Last - 1 then A (I) = Before (I))),
            "16-bit store at last position");

         A := (others => 16#A5#);
         Before := A;
         Store_32 (A, A'First, 16#DEAD_BEEF#, Order);
         Check
           (Load_32 (A, A'First, Order) = 16#DEAD_BEEF#
            and then (for all I in A'Range =>
                        (if I > A'First + 3 then A (I) = Before (I))),
            "32-bit store at first position");

         A := (others => 16#A5#);
         Before := A;
         Store_32 (A, A'Last - 3, 16#7654_3210#, Order);
         Check
           (Load_32 (A, A'Last - 3, Order) = 16#7654_3210#
            and then (for all I in A'Range =>
                        (if I < A'Last - 3 then A (I) = Before (I))),
            "32-bit store at last position");

         A := (others => 16#A5#);
         Before := A;
         Store_64 (A, A'First, 16#0123_4567_89AB_CDEF#, Order);
         Check
           (Load_64 (A, A'First, Order) = 16#0123_4567_89AB_CDEF#
            and then (for all I in A'Range =>
                        (if I > A'First + 7 then A (I) = Before (I))),
            "64-bit store at first position");

         A := (others => 16#A5#);
         Before := A;
         Store_64 (A, A'Last - 7, 16#FEDC_BA98_7654_3210#, Order);
         Check
           (Load_64 (A, A'Last - 7, Order) = 16#FEDC_BA98_7654_3210#
            and then (for all I in A'Range =>
                        (if I < A'Last - 7 then A (I) = Before (I))),
            "64-bit store at last position");
      end loop;
   end Test_Endian_Edges;

   ---------------------------------------------------------------------------

   procedure Test_Degenerate is
      Empty_Buffer : Buffer (0);
      B            : Buffer (4);
      Result       : Transfer;
      Nothing      : Byte_Array (1 .. 0);
   begin
      Check
        (Is_Empty (Empty_Buffer) and then Is_Full (Empty_Buffer),
         "a zero-capacity buffer is both empty and full");

      Put (Empty_Buffer, Byte_Array'(1, 2), Result);
      Check (Result.Produced = 0, "put into a zero-capacity buffer");

      Append (B, Nothing);
      Check (Is_Empty (B), "appending nothing changes nothing");

      Append_Fill (B, 9, 0);
      Check (Is_Empty (B), "filling nothing changes nothing");
   end Test_Degenerate;

begin
   Start ("byte_buffer_tests");
   Test_Append_And_Read;
   Test_Endian;
   Test_Transfers;
   Test_Spans;
   Test_Copies;
   Test_Compact;
   Test_Small_State_Spaces;
   Test_Endian_Edges;
   Test_Degenerate;

   Report;
end Byte_Buffer_Tests;
