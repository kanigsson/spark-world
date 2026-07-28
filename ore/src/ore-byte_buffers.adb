package body Ore.Byte_Buffers
  with SPARK_Mode => On
is

   --  The loop invariants and assertions below quantify over the produced
   --  bytes. Evaluating them once per appended byte would make an
   --  assertion-enabled build quadratic in buffer length, so they are
   --  proof-only; GNATprove verifies Ignore-policy assertions normally.
   pragma
     Assertion_Policy
       (Assert => Ignore, Loop_Invariant => Ignore, Ghost => Ignore);

   ---------------------------------------------------------------------------
   --  Plain byte arrays
   ---------------------------------------------------------------------------

   procedure Lemma_Equal_Ranges_Trans
     (Left, Middle, Right                : Byte_Array;
      From_Left, From_Middle, From_Right : Index;
      Count                              : Natural) is
   begin
      null;
   end Lemma_Equal_Ranges_Trans;

   procedure Store_16
     (A : in out Byte_Array; From : Index; Value : Word16; Order : Byte_Order)
   is
   begin
      case Order is
         when Little_Endian =>
            A (From) := Byte (Value mod 2 ** 8);
            A (From + 1) := Byte (Value / 2 ** 8);

         when Big_Endian    =>
            A (From) := Byte (Value / 2 ** 8);
            A (From + 1) := Byte (Value mod 2 ** 8);
      end case;
   end Store_16;

   procedure Store_32
     (A : in out Byte_Array; From : Index; Value : Word32; Order : Byte_Order)
   is
   begin
      case Order is
         when Little_Endian =>
            A (From) := Byte (Value mod 2 ** 8);
            A (From + 1) := Byte (Value / 2 ** 8 mod 2 ** 8);
            A (From + 2) := Byte (Value / 2 ** 16 mod 2 ** 8);
            A (From + 3) := Byte (Value / 2 ** 24);

         when Big_Endian    =>
            A (From) := Byte (Value / 2 ** 24);
            A (From + 1) := Byte (Value / 2 ** 16 mod 2 ** 8);
            A (From + 2) := Byte (Value / 2 ** 8 mod 2 ** 8);
            A (From + 3) := Byte (Value mod 2 ** 8);
      end case;
   end Store_32;

   procedure Store_64
     (A : in out Byte_Array; From : Index; Value : Word64; Order : Byte_Order)
   is
   begin
      case Order is
         when Little_Endian =>
            A (From) := Byte (Value mod 2 ** 8);
            A (From + 1) := Byte (Value / 2 ** 8 mod 2 ** 8);
            A (From + 2) := Byte (Value / 2 ** 16 mod 2 ** 8);
            A (From + 3) := Byte (Value / 2 ** 24 mod 2 ** 8);
            A (From + 4) := Byte (Value / 2 ** 32 mod 2 ** 8);
            A (From + 5) := Byte (Value / 2 ** 40 mod 2 ** 8);
            A (From + 6) := Byte (Value / 2 ** 48 mod 2 ** 8);
            A (From + 7) := Byte (Value / 2 ** 56);

         when Big_Endian    =>
            A (From) := Byte (Value / 2 ** 56);
            A (From + 1) := Byte (Value / 2 ** 48 mod 2 ** 8);
            A (From + 2) := Byte (Value / 2 ** 40 mod 2 ** 8);
            A (From + 3) := Byte (Value / 2 ** 32 mod 2 ** 8);
            A (From + 4) := Byte (Value / 2 ** 24 mod 2 ** 8);
            A (From + 5) := Byte (Value / 2 ** 16 mod 2 ** 8);
            A (From + 6) := Byte (Value / 2 ** 8 mod 2 ** 8);
            A (From + 7) := Byte (Value mod 2 ** 8);
      end case;
   end Store_64;

   procedure Lemma_Load_16_Frame
     (Left, Right           : Byte_Array;
      From_Left, From_Right : Index;
      Order                 : Byte_Order) is
   begin
      null;
   end Lemma_Load_16_Frame;

   procedure Lemma_Load_32_Frame
     (Left, Right           : Byte_Array;
      From_Left, From_Right : Index;
      Order                 : Byte_Order) is
   begin
      null;
   end Lemma_Load_32_Frame;

   procedure Lemma_Load_64_Frame
     (Left, Right           : Byte_Array;
      From_Left, From_Right : Index;
      Order                 : Byte_Order) is
   begin
      null;
   end Lemma_Load_64_Frame;

   ---------------------------------------------------------------------------
   --  Model
   ---------------------------------------------------------------------------

   function Contents (B : Buffer) return Byte_Array is
      Result : constant Byte_Array (1 .. B.Written) := B.Data (1 .. B.Written);
   begin
      return Result;
   end Contents;

   ---------------------------------------------------------------------------
   --  Producing
   ---------------------------------------------------------------------------

   procedure Append (B : in out Buffer; Value : Byte) is
      Base : constant Natural := B.Written;
   begin
      B.Data (Base + 1) := Value;
      B.Written := Base + 1;
   end Append;

   procedure Append (B : in out Buffer; Bytes : Byte_Array) is
      Base : constant Natural := B.Written;
   begin
      for K in 0 .. Bytes'Length - 1 loop
         B.Data (Base + 1 + K) := Bytes (Bytes'First + K);

         pragma Loop_Invariant (B.Written = Base);
         pragma
           Loop_Invariant
             (for all J in 1 .. Base => B.Data (J) = B.Data'Loop_Entry (J));
         pragma
           Loop_Invariant
             (for all J in 0 .. K =>
                B.Data (Base + 1 + J) = Bytes (Bytes'First + J));
      end loop;

      B.Written := Base + Bytes'Length;
   end Append;

   procedure Append_Fill (B : in out Buffer; Value : Byte; Count : Natural) is
      Base : constant Natural := B.Written;
   begin
      if Count > 0 then
         B.Data (Base + 1 .. Base + Count) := (others => Value);
      end if;

      B.Written := Base + Count;
   end Append_Fill;

   procedure Append_16 (B : in out Buffer; Value : Word16; Order : Byte_Order)
   is
      Base : constant Natural := B.Written;
   begin
      Store_16 (B.Data, Base + 1, Value, Order);
      B.Written := Base + 2;
   end Append_16;

   procedure Append_32 (B : in out Buffer; Value : Word32; Order : Byte_Order)
   is
      Base : constant Natural := B.Written;
   begin
      Store_32 (B.Data, Base + 1, Value, Order);
      B.Written := Base + 4;
   end Append_32;

   procedure Append_64 (B : in out Buffer; Value : Word64; Order : Byte_Order)
   is
      Base : constant Natural := B.Written;
   begin
      Store_64 (B.Data, Base + 1, Value, Order);
      B.Written := Base + 8;
   end Append_64;

   procedure Put (B : in out Buffer; Bytes : Byte_Array; Result : out Transfer)
   is
      Count : constant Natural :=
        Natural'Min (Bytes'Length, B.Capacity - B.Written);
   begin
      Append (B, Bytes (Bytes'First .. Bytes'First - 1 + Count));
      Result := (Consumed => Count, Produced => Count);
   end Put;

   ---------------------------------------------------------------------------
   --  Consuming
   ---------------------------------------------------------------------------

   function Peek (B : Buffer; Offset : Natural := 0) return Byte
   is (B.Data (B.Read_Consumed + 1 + Offset));

   procedure Consume (B : in out Buffer; Count : Natural) is
   begin
      B.Read_Consumed := B.Read_Consumed + Count;
   end Consume;

   procedure Read (B : in out Buffer; Value : out Byte) is
   begin
      Value := B.Data (B.Read_Consumed + 1);
      B.Read_Consumed := B.Read_Consumed + 1;
   end Read;

   procedure Read (B : in out Buffer; Into : out Byte_Array) is
      Base : constant Natural := B.Read_Consumed;
   begin
      --  One sliding assignment rather than a loop: Into is fully written, so
      --  no initialization obligation is left over for the caller to carry.
      Into := B.Data (Base + 1 .. Base + Into'Length);
      B.Read_Consumed := Base + Into'Length;
   end Read;

   procedure Read_16
     (B : in out Buffer; Value : out Word16; Order : Byte_Order)
   is
      Base : constant Natural := B.Read_Consumed;
   begin
      Value := Load_16 (B.Data, Base + 1, Order);
      B.Read_Consumed := Base + 2;
   end Read_16;

   procedure Read_32
     (B : in out Buffer; Value : out Word32; Order : Byte_Order)
   is
      Base : constant Natural := B.Read_Consumed;
   begin
      Value := Load_32 (B.Data, Base + 1, Order);
      B.Read_Consumed := Base + 4;
   end Read_32;

   procedure Read_64
     (B : in out Buffer; Value : out Word64; Order : Byte_Order)
   is
      Base : constant Natural := B.Read_Consumed;
   begin
      Value := Load_64 (B.Data, Base + 1, Order);
      B.Read_Consumed := Base + 8;
   end Read_64;

   procedure Get
     (B : in out Buffer; Into : in out Byte_Array; Result : out Transfer)
   is
      Base  : constant Natural := B.Read_Consumed;
      Count : constant Natural :=
        Natural'Min (Into'Length, B.Written - B.Read_Consumed);
   begin
      for K in 0 .. Count - 1 loop
         Into (Into'First + K) := B.Data (Base + 1 + K);

         pragma
           Loop_Invariant
             (for all J in 0 .. K =>
                Into (Into'First + J) = B.Data (Base + 1 + J));
         pragma
           Loop_Invariant
             (for all J in K + 1 .. Into'Length - 1 =>
                Into (Into'First + J) = Into'Loop_Entry (Into'First + J));
      end loop;

      B.Read_Consumed := Base + Count;
      Result := (Consumed => Count, Produced => Count);
   end Get;

   procedure Move
     (Source : in out Buffer; Target : in out Buffer; Result : out Transfer)
   is
      From_Base : constant Natural := Source.Read_Consumed;
      To_Base   : constant Natural := Target.Written;
      Count     : constant Natural :=
        Natural'Min
          (Source.Written - Source.Read_Consumed,
           Target.Capacity - Target.Written);
   begin
      for K in 0 .. Count - 1 loop
         Target.Data (To_Base + 1 + K) := Source.Data (From_Base + 1 + K);

         pragma Loop_Invariant (Target.Written = To_Base);
         pragma
           Loop_Invariant
             (for all J in 1 .. To_Base =>
                Target.Data (J) = Target.Data'Loop_Entry (J));
         pragma
           Loop_Invariant
             (for all J in 0 .. K =>
                Target.Data (To_Base + 1 + J)
                = Source.Data (From_Base + 1 + J));
      end loop;

      Target.Written := To_Base + Count;
      Source.Read_Consumed := From_Base + Count;
      Result := (Consumed => Count, Produced => Count);
   end Move;

   ---------------------------------------------------------------------------
   --  Cursor and content management
   ---------------------------------------------------------------------------

   procedure Clear (B : in out Buffer) is
   begin
      B.Read_Consumed := 0;
      B.Written := 0;
   end Clear;

   procedure Rewind (B : in out Buffer) is
   begin
      B.Read_Consumed := 0;
   end Rewind;

   procedure Truncate (B : in out Buffer; New_Length : Natural) is
   begin
      B.Written := New_Length;
   end Truncate;

   procedure Compact (B : in out Buffer) is
      Base  : constant Natural := B.Read_Consumed;
      Count : constant Natural := B.Written - B.Read_Consumed;
   begin
      --  A backward move: every destination index is below its source, so
      --  copying front to back never overwrites a byte still to be read.
      for K in 0 .. Count - 1 loop
         B.Data (1 + K) := B.Data (Base + 1 + K);

         pragma Loop_Invariant (B.Written = Base + Count);
         pragma Loop_Invariant (B.Read_Consumed = Base);
         pragma
           Loop_Invariant
             (for all J in 0 .. K =>
                B.Data (1 + J) = B.Data'Loop_Entry (Base + 1 + J));
         pragma
           Loop_Invariant
             (for all J in K + 1 .. Count - 1 =>
                B.Data (Base + 1 + J) = B.Data'Loop_Entry (Base + 1 + J));
      end loop;

      --  The read position drops first: with the write position still at its
      --  old value the record's own invariant holds at every step.
      B.Read_Consumed := 0;
      B.Written := Count;
   end Compact;

   ---------------------------------------------------------------------------
   --  Subviews
   ---------------------------------------------------------------------------

   function Slice (B : Buffer; S : Span) return Byte_Array is
      Result : constant Byte_Array (1 .. Length (S)) :=
        B.Data (S.First .. S.Past_Last - 1);
   begin
      return Result;
   end Slice;

   procedure Append_Slice
     (Target : in out Buffer; Source : in Buffer; S : in Span)
   is
      Base  : constant Natural := Target.Written;
      Count : constant Natural := Length (S);
   begin
      for K in 0 .. Count - 1 loop
         Target.Data (Base + 1 + K) := Source.Data (S.First + K);

         pragma Loop_Invariant (Target.Written = Base);
         pragma
           Loop_Invariant
             (for all J in 1 .. Base =>
                Target.Data (J) = Target.Data'Loop_Entry (J));
         pragma
           Loop_Invariant
             (for all J in 0 .. K =>
                Target.Data (Base + 1 + J) = Source.Data (S.First + J));
      end loop;

      Target.Written := Base + Count;
   end Append_Slice;

   ---------------------------------------------------------------------------
   --  Copies
   ---------------------------------------------------------------------------

   procedure Append_Copy
     (B : in out Buffer; Distance : Positive; Count : Natural)
   is
      Base   : constant Natural := B.Written;
      Before : constant Buffer := B
      with Ghost => Static;
   begin
      if Distance = 1 then
         --  The recurrence has period one: every appended byte is the byte
         --  immediately preceding the copy.
         if Count > 0 then
            B.Data (Base + 1 .. Base + Count) := (others => B.Data (Base));
         end if;
         B.Written := Base + Count;

         pragma
           Assert
             (Static =>
                (for all K in 1 .. Base => B.Data (K) = Before.Data (K)));
         pragma
           Assert
             (Static =>
                (for all K in 0 .. Count - 1 =>
                   B.Data (Base + 1 + K) = Before.Data (Base)));

      elsif Distance >= Count then
         --  The source range ends no later than the destination begins, so a
         --  single slice assignment is the disjoint window copy.
         if Count > 0 then
            B.Data (Base + 1 .. Base + Count) :=
              B.Data (Base + 1 - Distance .. Base + Count - Distance);
         end if;
         B.Written := Base + Count;

         pragma
           Assert
             (Static =>
                (for all K in 1 .. Base => B.Data (K) = Before.Data (K)));
         pragma
           Assert
             (Static =>
                (for all K in 0 .. Count - 1 =>
                   B.Data (Base + 1 + K)
                   = Before.Data (Base + 1 + K - Distance)));

      else
         --  Copying forward is essential: once K reaches Distance the source
         --  is a byte this very copy produced, which is what repeats the
         --  window.
         for K in 0 .. Count - 1 loop
            pragma Loop_Invariant (B.Written = Base);
            pragma
              Loop_Invariant
                (for all J in 1 .. Base => B.Data (J) = Before.Data (J));
            pragma
              Loop_Invariant
                (for all J in 0 .. K - 1 =>
                   B.Data (Base + 1 + J)
                   = (if J < Distance
                      then Before.Data (Base + 1 + J - Distance)
                      else B.Data (Base + 1 + J - Distance)));

            B.Data (Base + 1 + K) := B.Data (Base + 1 + K - Distance);

            if K < Distance then
               pragma Assert (Base + 1 + K - Distance <= Base);
               pragma
                 Assert
                   (Static =>
                      B.Data (Base + 1 + K - Distance)
                      = Before.Data (Base + 1 + K - Distance));
            else
               pragma Assert (Base + 1 + K - Distance > Base);
               pragma Assert (K - Distance < K);
            end if;
         end loop;

         B.Written := Base + Count;
      end if;

      pragma Assert (Static => Copies_Back (Before, B, Distance, Count));
   end Append_Copy;

   procedure Lemma_Copies_Back_Run (Before, After : Buffer; Count : Natural) is
      Last : constant Positive := Length (Before);
   begin
      --  Induction on the appended bytes: byte K is the byte at K - 1 (the
      --  copy distance is one), and byte 1 is the last original byte.
      for K in 1 .. Count loop
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Element (After, Last + J) = Element (Before, Last));
      end loop;
   end Lemma_Copies_Back_Run;

   procedure Lemma_Copies_Back_Disjoint
     (Before, After : Buffer; Distance : Positive; Count : Natural) is
   begin
      null;
   end Lemma_Copies_Back_Disjoint;

   ---------------------------------------------------------------------------
   --  Buffer lemmas
   ---------------------------------------------------------------------------

   procedure Lemma_Same_Prefix_Trans
     (First, Middle, Last : Buffer; Count : Natural) is
   begin
      null;
   end Lemma_Same_Prefix_Trans;

   procedure Lemma_Matches_At_Frame
     (Before, After : Buffer;
      From          : Positive;
      Bytes         : Byte_Array;
      Count         : Natural) is
   begin
      null;
   end Lemma_Matches_At_Frame;

   procedure Lemma_Matches_At_Concat
     (B : Buffer; From : Positive; Left : Byte_Array; Right : Byte_Array) is
   begin
      null;
   end Lemma_Matches_At_Concat;

   procedure Lemma_Contents_Equal (Left, Right : Buffer) is
   begin
      null;
   end Lemma_Contents_Equal;

end Ore.Byte_Buffers;
