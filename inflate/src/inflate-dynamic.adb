package body Inflate.Dynamic with SPARK_Mode => On is

   function Is_Dummy
     (Frequencies : Frequency_Array;
      Active      : Symbol_Count;
      I           : Symbol_Index) return Boolean
   is
     (if Active = 0 then I <= 1
      elsif Active = 1
      then (if Frequencies (0) = 0 then I = 0 else I = 1)
      else False)
   with
     Pre => Frequencies'First = 0
              and then Frequencies'Length in 2 .. Max_Symbols
              and then I in Frequencies'Range;

   function Dummy_Count
     (Frequencies : Frequency_Array;
      Active      : Symbol_Count;
      Count       : Symbol_Count) return Symbol_Count
   is
     (if Active = 0 then Symbol_Count'Min (Count, 2)
      elsif Active = 1
      then
        (if (Frequencies (0) = 0 and then Count > 0)
           or else (Frequencies (0) > 0 and then Count > 1)
         then 1 else 0)
      else 0)
   with
     Ghost,
     Pre  => Frequencies'First = 0
               and then Frequencies'Length in 2 .. Max_Symbols
               and then Count <= Frequencies'Length,
     Post => Dummy_Count'Result <= 2;

   procedure Lemma_Active_Monotone
     (Frequencies : Frequency_Array;
      First, Last : Symbol_Count)
   with
     Ghost,
     Pre  => Frequencies'First = 0
               and then Last <= Frequencies'Length
               and then First <= Last,
     Post => Active_Count (Frequencies, First) <=
               Active_Count (Frequencies, Last),
     Subprogram_Variant => (Decreases => Last - First);

   procedure Lemma_Active_Monotone
     (Frequencies : Frequency_Array;
      First, Last : Symbol_Count)
   is
   begin
      if First < Last then
         Lemma_Active_Monotone (Frequencies, First, Last - 1);
      end if;
   end Lemma_Active_Monotone;

   procedure Lemma_Dummy_Inactive
     (Frequencies : Frequency_Array;
      Active      : Symbol_Count)
   with
     Ghost,
     Pre  => Frequencies'First = 0
               and then Frequencies'Length in 2 .. Max_Symbols
               and then Active =
                 Active_Count (Frequencies, Frequencies'Length),
     Post =>
       (if Active = 0
        then Frequencies (0) = 0 and then Frequencies (1) = 0
        elsif Active = 1 and then Frequencies (0) > 0
        then Frequencies (1) = 0);

   procedure Lemma_Dummy_Inactive
     (Frequencies : Frequency_Array;
      Active      : Symbol_Count)
   is
   begin
      if Active <= 1 then
         Lemma_Active_Monotone
           (Frequencies, 2, Frequencies'Length);
         if Active = 0 then
            pragma Assert (Frequencies (0) = 0);
            pragma Assert (Frequencies (1) = 0);
         elsif Frequencies (0) > 0 then
            pragma Assert (Frequencies (1) = 0);
         end if;
      end if;
   end Lemma_Dummy_Inactive;

   procedure Lemma_Dummy_Step
     (Frequencies : Frequency_Array;
      Active      : Symbol_Count;
      Count       : Symbol_Count)
   with
     Ghost,
     Pre  => Frequencies'First = 0
               and then Frequencies'Length in 2 .. Max_Symbols
               and then Count < Frequencies'Length,
     Post =>
       Dummy_Count (Frequencies, Active, Count + 1) =
         Dummy_Count (Frequencies, Active, Count)
           + (if Is_Dummy
                    (Frequencies, Active, Symbol_Index (Count))
              then 1 else 0);

   procedure Lemma_Dummy_Step
     (Frequencies : Frequency_Array;
      Active      : Symbol_Count;
      Count       : Symbol_Count) is null;

   procedure Lemma_Pow2_Complement (Length : Natural)
   with
     Ghost,
     Pre  => Length in 1 .. 9,
     Post => Pow2 (Length) * Pow2 (15 - Length) = Pow2 (15)
               and then
             (if Length > 1
              then Pow2 (16 - Length) = 2 * Pow2 (15 - Length));

   procedure Lemma_Pow2_Complement (Length : Natural) is
   begin
      case Length is
         when 1 .. 9 =>
            null;
         when others =>
            null;
      end case;
   end Lemma_Pow2_Complement;

   procedure Lemma_Model_Frame
     (Before, After : Code_Length_Array;
      Count         : Symbol_Count)
   with
     Ghost,
     Pre  => Before'First = 0
               and then After'First = 0
               and then Before'Last = After'Last
               and then Count <= Before'Length
               and then
             (for all I in 0 .. Count - 1 => Before (I) = After (I)),
     Post => Assigned_Count (After, Count) =
               Assigned_Count (Before, Count)
               and then Code_Space (After, Count) =
                          Code_Space (Before, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Model_Frame
     (Before, After : Code_Length_Array;
      Count         : Symbol_Count)
   is
   begin
      if Count > 0 then
         Lemma_Model_Frame (Before, After, Count - 1);
      end if;
   end Lemma_Model_Frame;

   procedure Set_Length
     (Lengths  : in out Code_Length_Array;
      Position : in     Symbol_Index;
      Value    : in     Code_Length)
   with
     Pre  => Lengths'First = 0
               and then Position in Lengths'Range
               and then Lengths (Position) = 0
               and then Value in 1 .. 9,
     Post => Lengths (Position) = Value
               and then
             (for all I in Lengths'Range =>
                (if I /= Position
                 then Lengths (I) = Lengths'Old (I)))
               and then Assigned_Count (Lengths, Position) =
                          Assigned_Count (Lengths'Old, Position)
               and then Code_Space (Lengths, Position) =
                          Code_Space (Lengths'Old, Position)
               and then Assigned_Count (Lengths, Position + 1) =
                          Assigned_Count (Lengths'Old, Position) + 1
               and then Code_Space (Lengths, Position + 1) =
                          Code_Space (Lengths'Old, Position)
                            + Pow2 (15 - Value)
   is
      Before : constant Code_Length_Array := Lengths with Ghost;
   begin
      Lengths (Position) := Value;
      Lemma_Model_Frame (Before, Lengths, Position);
   end Set_Length;

   procedure Build_Lengths
     (Frequencies : in     Frequency_Array;
      Lengths     :    out Code_Length_Array)
   is
      Active       : Symbol_Count := 0;
      Leaves       : Symbol_Count;
      Capacity     : Natural range 2 .. 512 := 2;
      Long_Length  : Natural range 1 .. 9 := 1;
      Short_Leaves : Symbol_Count;
      Seen         : Symbol_Count := 0;
      Short_Seen   : Symbol_Count := 0;
      Space_Units  : Natural range 0 .. 2 * Max_Symbols := 0;
      Space        : Natural := 0;
   begin
      Lengths := (others => 0);

      --  Count used symbols.  Frequencies are otherwise deliberately not
      --  compared: this is a valid balanced heuristic, not an optimal tree.
      for I in Frequencies'Range loop
         pragma Loop_Invariant
           (Active = Active_Count (Frequencies, Symbol_Count (I)));
         if Frequencies (I) > 0 then
            Active := Active + 1;
         end if;
      end loop;
      pragma Assert
        (Active = Active_Count (Frequencies, Frequencies'Length));

      Leaves := Symbol_Count'Max (2, Active);
      pragma Assert (Leaves = Required_Leaves (Frequencies));

      --  Find ceil(log2(Leaves)).  The largest DEFLATE alphabet has 286
      --  symbols, so the loop stops at capacity 512 and length 9.
      while Capacity < Leaves loop
         pragma Loop_Invariant (Capacity = Pow2 (Long_Length));
         pragma Loop_Invariant (Capacity < Leaves);
         pragma Loop_Invariant
           (if Long_Length > 1 then Capacity / 2 < Leaves);
         pragma Loop_Variant (Decreases => Leaves - Capacity);
         pragma Assert (Long_Length < 9);
         Capacity := Capacity * 2;
         Long_Length := Long_Length + 1;
      end loop;
      pragma Assert (Capacity = Pow2 (Long_Length));
      pragma Assert (Leaves <= Capacity);

      --  A complete balanced tree with Leaves leaves has
      --    Capacity - Leaves             leaves at Long_Length - 1, and
      --    2 * Leaves - Capacity         leaves at Long_Length.
      Short_Leaves := Capacity - Leaves;
      pragma Assert (Short_Leaves < Leaves);
      Lemma_Pow2_Complement (Long_Length);
      Lemma_Dummy_Inactive (Frequencies, Active);
      pragma Assert
        (Dummy_Count (Frequencies, Active, Frequencies'Length) =
           Leaves - Active);
      pragma Assert
        (Active
           + Dummy_Count (Frequencies, Active, Frequencies'Length) = Leaves);

      --  Select all active symbols.  For the degenerate zero/one-active
      --  cases, positions zero and one supply exactly the missing leaves.
      --  The first Short_Leaves selected symbols receive the shorter length.
      for I in Frequencies'Range loop
         pragma Loop_Invariant
           (Seen = Assigned_Count (Lengths, Symbol_Count (I)));
         pragma Loop_Invariant (Short_Seen = Symbol_Count'Min (Seen, Short_Leaves));
         pragma Loop_Invariant (Space_Units = Seen + Short_Seen);
         pragma Loop_Invariant (Space_Units <= Capacity);
         pragma Loop_Invariant
           (Code_Space (Lengths, Symbol_Count (I)) = Space);
         pragma Loop_Invariant
           (Space = Space_Units * Pow2 (15 - Long_Length));
         pragma Loop_Invariant (Seen <= Leaves);
         pragma Loop_Invariant (Short_Seen <= Short_Leaves);
         pragma Loop_Invariant
           (Seen = Active_Count (Frequencies, Symbol_Count (I))
              + Dummy_Count (Frequencies, Active, Symbol_Count (I)));
         pragma Loop_Invariant
           (for all J in Frequencies'First .. I - 1 =>
              (if Frequencies (J) > 0 then Lengths (J) > 0));
         pragma Loop_Invariant
           (for all J in Frequencies'First .. I - 1 => Lengths (J) <= 9);
         pragma Loop_Invariant
           (for all J in I .. Frequencies'Last => Lengths (J) = 0);

         Lemma_Active_Monotone
           (Frequencies, Symbol_Count (I), Frequencies'Length);
         Lemma_Active_Monotone
           (Frequencies, Symbol_Count (I) + 1, Frequencies'Length);
         Lemma_Dummy_Step (Frequencies, Active, Symbol_Count (I));
         pragma Assert
           (if Is_Dummy (Frequencies, Active, I)
            then Frequencies (I) = 0);

         if Frequencies (I) > 0
           or else Is_Dummy (Frequencies, Active, I)
         then
            pragma Assert
              (Active_Count (Frequencies, Symbol_Count (I) + 1)
                 + Dummy_Count
                     (Frequencies, Active, Symbol_Count (I) + 1) = Seen + 1);
            pragma Assert (Seen < Leaves);
            if Seen < Short_Leaves then
               pragma Assert (Long_Length > 1);
               Set_Length (Lengths, I, Long_Length - 1);
               pragma Assert
                 (Assigned_Count (Lengths, Symbol_Count (I) + 1) =
                    Assigned_Count (Lengths, Symbol_Count (I)) + 1);
               pragma Assert
                 (Code_Space (Lengths, Symbol_Count (I) + 1) =
                    Code_Space (Lengths, Symbol_Count (I))
                      + Pow2 (16 - Long_Length));
               pragma Assert
                 (Assigned_Count (Lengths, Symbol_Count (I) + 1) = Seen + 1);
               pragma Assert
                 (Code_Space (Lengths, Symbol_Count (I) + 1) =
                    (Space_Units + 2) * Pow2 (15 - Long_Length));
               Short_Seen := Short_Seen + 1;
               Space := Space + Pow2 (16 - Long_Length);
               Space_Units := Space_Units + 2;
               Seen := Seen + 1;
               pragma Assert
                 (Space = Space_Units * Pow2 (15 - Long_Length));
            else
               Set_Length (Lengths, I, Long_Length);
               pragma Assert
                 (Assigned_Count (Lengths, Symbol_Count (I) + 1) =
                    Assigned_Count (Lengths, Symbol_Count (I)) + 1);
               pragma Assert
                 (Code_Space (Lengths, Symbol_Count (I) + 1) =
                    Code_Space (Lengths, Symbol_Count (I))
                      + Pow2 (15 - Long_Length));
               pragma Assert
                 (Assigned_Count (Lengths, Symbol_Count (I) + 1) = Seen + 1);
               pragma Assert
                 (Code_Space (Lengths, Symbol_Count (I) + 1) =
                    (Space_Units + 1) * Pow2 (15 - Long_Length));
               Space := Space + Pow2 (15 - Long_Length);
               Space_Units := Space_Units + 1;
               Seen := Seen + 1;
               pragma Assert
                 (Space = Space_Units * Pow2 (15 - Long_Length));
            end if;
         else
            pragma Assert
              (Assigned_Count (Lengths, Symbol_Count (I) + 1) =
                 Assigned_Count (Lengths, Symbol_Count (I)));
            pragma Assert
              (Code_Space (Lengths, Symbol_Count (I) + 1) =
                 Code_Space (Lengths, Symbol_Count (I)));
            pragma Assert
              (Seen = Assigned_Count (Lengths, Symbol_Count (I) + 1));
            pragma Assert
              (Code_Space (Lengths, Symbol_Count (I) + 1) =
                 Space);
         end if;
         pragma Assert
           (Seen = Active_Count (Frequencies, Symbol_Count (I) + 1)
              + Dummy_Count
                  (Frequencies, Active, Symbol_Count (I) + 1));
      end loop;

      pragma Assert (Seen = Leaves);
      pragma Assert (Short_Seen = Short_Leaves);
      pragma Assert (Space_Units = Leaves + Short_Leaves);
      pragma Assert (Leaves + Short_Leaves = Capacity);
      pragma Assert (Space = Space_Units * Pow2 (15 - Long_Length));
      pragma Assert
        (Code_Space (Lengths, Lengths'Length) = Space);
      pragma Assert (Space = Capacity * Pow2 (15 - Long_Length));
      pragma Assert (Code_Space (Lengths, Lengths'Length) = Pow2 (15));
      pragma Assert
        (Assigned_Count (Lengths, Lengths'Length) = Leaves);
      pragma Assert
        (for all I in Frequencies'Range =>
           (if Frequencies (I) > 0 then Lengths (I) > 0));
      pragma Assert (for all I in Lengths'Range => Lengths (I) <= 9);
   end Build_Lengths;

   --------------------
   -- Build_Codebook --
   --------------------

   procedure Build_Codebook
     (Frequencies : in     Frequency_Array;
      Book        :    out Codebooks.Codebook;
      Success     :    out Boolean)
   is
      Lengths : Code_Length_Array (Frequencies'Range);
      Full    : Codebooks.Code_Length_Array := (others => 0);
   begin
      Build_Lengths (Frequencies, Lengths);
      for I in Lengths'Range loop
         pragma Loop_Invariant
           (for all J in Lengths'First .. I - 1 =>
              Full (J) = Lengths (J));
         pragma Loop_Invariant
           (for all J in I .. Codebooks.Symbol_Index'Last =>
              Full (J) = 0);
         Full (I) := Lengths (I);
      end loop;
      Codebooks.Build (Full, Book, Success);
   end Build_Codebook;

   -----------------------
   -- Serialize_Payload --
   -----------------------

   procedure Serialize_Payload
     (Data            : in     Byte_Array;
      Literal_Lengths : in     Codebooks.Codebook;
      Distances       : in     Codebooks.Codebook;
      Output          : in out Byte_Array;
      Start           : in     Natural;
      Next_Bit        :    out Natural)
   is
   begin
      Payload.Serialize
        (Data, Literal_Lengths, Distances, Output, Start, Next_Bit);
   end Serialize_Payload;

end Inflate.Dynamic;
