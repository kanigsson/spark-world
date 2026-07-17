with Interfaces;

package body Inflate.Dynamic with SPARK_Mode => On is

   use Interfaces;

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

   --------------------
   -- Set_Stream_Bit --
   --------------------

   procedure Set_Stream_Bit
     (Output   : in out Byte_Array;
      Position : Natural;
      Value    : Natural)
   with
     Pre  => Output'Length <= Fixed.Max_Stream_Bytes
               and then Position < 8 * Output'Length
               and then Value <= 1,
     Post => Fixed.Bit_Value (Output, Position) = Value
               and then
             (for all P in 0 .. 8 * Output'Length - 1 =>
                (if P /= Position
                 then Fixed.Bit_Value (Output, P) =
                        Fixed.Bit_Value (Output'Old, P)))
   is
      Offset : constant Natural := Position / 8;
      Shift  : constant Natural := Position mod 8;
      Mask   : constant Byte := Shift_Left (Byte (1), Shift);
      P      : constant Buffer_Index := Output'First + Offset;
   begin
      if Value = 0 then
         Output (P) := Output (P) and not Mask;
      else
         Output (P) := Output (P) or Mask;
      end if;
   end Set_Stream_Bit;

   -----------------------
   -- Write_Length_Code --
   -----------------------

   procedure Write_Length_Code
     (Output : in out Byte_Array;
      Start  : Natural;
      Value  : Code_Length)
   with
     Pre  => Output'Length <= Fixed.Max_Stream_Bytes
               and then Start <= 8 * Output'Length
               and then 4 <= 8 * Output'Length - Start,
     Post => Length_Code_At (Output, Start, Value)
               and then
             (for all Position in 0 .. 8 * Output'Length - 1 =>
                (if Position < Start or else Position >= Start + 4
                 then Fixed.Bit_Value (Output, Position) =
                        Fixed.Bit_Value (Output'Old, Position)))
   is
   begin
      Set_Stream_Bit (Output, Start, Value / 8);
      Set_Stream_Bit (Output, Start + 1, (Value / 4) mod 2);
      Set_Stream_Bit (Output, Start + 2, (Value / 2) mod 2);
      Set_Stream_Bit (Output, Start + 3, Value mod 2);
   end Write_Length_Code;

   procedure Lemma_Header_Frame
     (Before, After  : Byte_Array;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook)
   with
     Ghost,
     Pre  => Before'Length <= Fixed.Max_Stream_Bytes
               and then After'Length <= Fixed.Max_Stream_Bytes
               and then Before'Length >= Header_Byte_Count
               and then After'Length >= Header_Byte_Count
               and then Books_Encodable (Literal_Lengths, Distances)
               and then Header_Encodes
                 (Before, Literal_Lengths, Distances)
               and then
             (for all Position in 0 .. Header_Bit_Count - 1 =>
                Fixed.Bit_Value (After, Position) =
                  Fixed.Bit_Value (Before, Position)),
     Post => Header_Encodes (After, Literal_Lengths, Distances);

   procedure Lemma_Header_Frame
     (Before, After  : Byte_Array;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook) is null;

   ------------------------------
   -- Books recovered from header --
   ------------------------------

   function Literal_Lengths_From_Header
     (Input : Byte_Array) return Codebooks.Code_Length_Array
   with
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Input'Length >= Header_Byte_Count,
     Post =>
       (for all I in 0 .. Literal_Length_Count - 1 =>
          Literal_Lengths_From_Header'Result (I) =
            Fixed.Prefix_Value
              (Input, Header_Prefix_Bits + 4 * I, 4))
       and then
       (for all I in Literal_Length_Count ..
          Codebooks.Symbol_Index'Last =>
            Literal_Lengths_From_Header'Result (I) = 0);

   function Literal_Lengths_From_Header
     (Input : Byte_Array) return Codebooks.Code_Length_Array
   is
      Result : Codebooks.Code_Length_Array := (others => 0);
   begin
      for I in 0 .. Literal_Length_Count - 1 loop
         Result (I) :=
           Fixed.Prefix_Value
             (Input, Header_Prefix_Bits + 4 * I, 4);
         pragma Loop_Invariant
           (for all J in 0 .. I =>
              Result (J) =
                Fixed.Prefix_Value
                  (Input, Header_Prefix_Bits + 4 * J, 4));
         pragma Loop_Invariant
           (for all J in I + 1 .. Codebooks.Symbol_Index'Last =>
              Result (J) = 0);
      end loop;
      return Result;
   end Literal_Lengths_From_Header;

   function Distance_Lengths_From_Header
     (Input : Byte_Array) return Codebooks.Code_Length_Array
   with
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Input'Length >= Header_Byte_Count,
     Post =>
       (for all I in 0 .. Distance_Count - 1 =>
          Distance_Lengths_From_Header'Result (I) =
            Fixed.Prefix_Value
              (Input,
               Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
               4))
       and then
       (for all I in Distance_Count .. Codebooks.Symbol_Index'Last =>
          Distance_Lengths_From_Header'Result (I) = 0);

   function Distance_Lengths_From_Header
     (Input : Byte_Array) return Codebooks.Code_Length_Array
   is
      Result : Codebooks.Code_Length_Array := (others => 0);
   begin
      for I in 0 .. Distance_Count - 1 loop
         Result (I) :=
           Fixed.Prefix_Value
             (Input,
              Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
              4);
         pragma Loop_Invariant
           (for all J in 0 .. I =>
              Result (J) =
                Fixed.Prefix_Value
                  (Input,
                   Header_Prefix_Bits
                     + 4 * (Literal_Length_Count + J),
                   4));
         pragma Loop_Invariant
           (for all J in I + 1 .. Codebooks.Symbol_Index'Last =>
              Result (J) = 0);
      end loop;
      return Result;
   end Distance_Lengths_From_Header;

   function Literal_Book_From_Header
     (Input : Byte_Array) return Codebooks.Codebook
   is
      Lengths : constant Codebooks.Code_Length_Array :=
        Literal_Lengths_From_Header (Input);
      Result : Codebooks.Codebook (Codebooks.Canonical) :=
        (Kind    => Codebooks.Canonical,
         Lengths => (others => 0),
         Counts  => (others => 0));
      Success : Boolean;
   begin
      Codebooks.Build (Lengths, Result, Success);
      pragma Assert (Success = Codebooks.Ready (Result));
      return Result;
   end Literal_Book_From_Header;

   function Distance_Book_From_Header
     (Input : Byte_Array) return Codebooks.Codebook
   is
      Lengths : constant Codebooks.Code_Length_Array :=
        Distance_Lengths_From_Header (Input);
      Result : Codebooks.Codebook (Codebooks.Canonical) :=
        (Kind    => Codebooks.Canonical,
         Lengths => (others => 0),
         Counts  => (others => 0));
      Success : Boolean;
   begin
      Codebooks.Build (Lengths, Result, Success);
      pragma Assert (Success = Codebooks.Ready (Result));
      return Result;
   end Distance_Book_From_Header;

   procedure Lemma_Length_Code_Value
     (Input : Byte_Array;
      Start : Natural;
      Value : Code_Length)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Start <= 8 * Input'Length
               and then 4 <= 8 * Input'Length - Start
               and then Length_Code_At (Input, Start, Value),
     Post => Fixed.Prefix_Value (Input, Start, 4) = Value;

   procedure Lemma_Length_Code_Value
     (Input : Byte_Array;
      Start : Natural;
      Value : Code_Length)
   is
   begin
      pragma Assert
        (Fixed.Prefix_Value (Input, Start, 1) =
           Fixed.Bit_Value (Input, Start));
      pragma Assert
        (Fixed.Prefix_Value (Input, Start, 2) =
           2 * Fixed.Bit_Value (Input, Start)
             + Fixed.Bit_Value (Input, Start + 1));
      pragma Assert
        (Fixed.Prefix_Value (Input, Start, 3) =
           4 * Fixed.Bit_Value (Input, Start)
             + 2 * Fixed.Bit_Value (Input, Start + 1)
             + Fixed.Bit_Value (Input, Start + 2));
   end Lemma_Length_Code_Value;

   procedure Lemma_Header_From_Book_Fields
     (Input : Byte_Array;
      Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Input'Length >= Header_Byte_Count
               and then Books_Encodable
                 (Before_Literals, Before_Distances)
               and then Books_Encodable
                 (After_Literals, After_Distances)
               and then Before_Literals.Lengths = After_Literals.Lengths
               and then Before_Distances.Lengths = After_Distances.Lengths
               and then Header_Encodes
                 (Input, Before_Literals, Before_Distances),
     Post => Header_Encodes
               (Input, After_Literals, After_Distances);

   procedure Lemma_Header_From_Book_Fields
     (Input : Byte_Array;
      Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook)
   is
   begin
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Literals, After_Literals);
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Distances, After_Distances);
      for I in 0 .. Literal_Length_Count - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Length_Code_At
                (Input, Header_Prefix_Bits + 4 * J,
                 Codebooks.Length_Of (After_Literals, J)));
         pragma Assert
           (Length_Code_At
              (Input, Header_Prefix_Bits + 4 * I,
               Codebooks.Length_Of (Before_Literals, I)));
         pragma Assert
           (Codebooks.Length_Of (Before_Literals, I) =
              Codebooks.Length_Of (After_Literals, I));
      end loop;
      for I in 0 .. Distance_Count - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Length_Code_At
                (Input,
                 Header_Prefix_Bits + 4 * (Literal_Length_Count + J),
                 Codebooks.Length_Of (After_Distances, J)));
         pragma Assert
           (Length_Code_At
              (Input,
               Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
               Codebooks.Length_Of (Before_Distances, I)));
         pragma Assert
           (Codebooks.Length_Of (Before_Distances, I) =
              Codebooks.Length_Of (After_Distances, I));
      end loop;
   end Lemma_Header_From_Book_Fields;

   --  The remaining assertions and loop annotations are proof-only and may
   --  mention ghost snapshots.  Keep them erased in checks-enabled focused
   --  builds just as they are in the shipping debug configuration.
   pragma Assertion_Policy
     (Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);
   procedure Lemma_Header_Books_Recovered
     (Input           : Byte_Array;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook)
   is
      Recovered_Literals : constant Codebooks.Codebook :=
        Literal_Book_From_Header (Input);
      Recovered_Distances : constant Codebooks.Codebook :=
        Distance_Book_From_Header (Input);
   begin
      for I in Codebooks.Symbol_Index loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Codebooks.Length_Of (Recovered_Literals, J) =
                Codebooks.Length_Of (Literal_Lengths, J));
         if I < Literal_Length_Count then
            pragma Assert
              (Length_Code_At
                 (Input, Header_Prefix_Bits + 4 * I,
                  Codebooks.Length_Of (Literal_Lengths, I)));
            Lemma_Length_Code_Value
              (Input, Header_Prefix_Bits + 4 * I,
               Codebooks.Length_Of (Literal_Lengths, I));
         else
            pragma Assert
              (Codebooks.Length_Of (Recovered_Literals, I) = 0);
            pragma Assert
              (Codebooks.Length_Of (Literal_Lengths, I) = 0);
         end if;
      end loop;
      Codebooks.Lemma_Canonical_Lengths_Equal
        (Recovered_Literals, Literal_Lengths);
      Codebooks.Lemma_Exact_Books_Equal
        (Recovered_Literals, Literal_Lengths);

      for I in Codebooks.Symbol_Index loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Codebooks.Length_Of (Recovered_Distances, J) =
                Codebooks.Length_Of (Distances, J));
         if I < Distance_Count then
            pragma Assert
              (Length_Code_At
                 (Input,
                  Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
                  Codebooks.Length_Of (Distances, I)));
            Lemma_Length_Code_Value
              (Input,
               Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
               Codebooks.Length_Of (Distances, I));
         else
            pragma Assert
              (Codebooks.Length_Of (Recovered_Distances, I) = 0);
            pragma Assert
              (Codebooks.Length_Of (Distances, I) = 0);
         end if;
      end loop;
      Codebooks.Lemma_Canonical_Lengths_Equal
        (Recovered_Distances, Distances);
      Codebooks.Lemma_Exact_Books_Equal
        (Recovered_Distances, Distances);
   end Lemma_Header_Books_Recovered;

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

   ----------------------
   -- Serialize_Header --
   ----------------------

   procedure Serialize_Header
     (Literal_Lengths : in     Codebooks.Codebook;
      Distances       : in     Codebooks.Codebook;
      Output          : in out Byte_Array;
      Next_Bit        :    out Natural)
   is
      Initial : constant Byte_Array := Output with Ghost;
   begin
      --  BFINAL=1, BTYPE=10, HLIT=29, HDIST=29, HCLEN=15, followed by
      --  nineteen three-bit code-length-code lengths.  Symbols 16, 17, and
      --  18 have length zero; symbols 0 .. 15 all have length four.
      for Position in 0 .. Header_Prefix_Bits - 1 loop
         pragma Loop_Invariant
           (for all P in 0 .. Position - 1 =>
              Fixed.Bit_Value (Output, P) = Expected_Header_Bit (P));
         pragma Loop_Invariant
           (for all P in Position .. 8 * Output'Length - 1 =>
              Fixed.Bit_Value (Output, P) =
                Fixed.Bit_Value (Initial, P));
         Set_Stream_Bit
           (Output, Position, Expected_Header_Bit (Position));
      end loop;

      pragma Assert
        (for all Position in 0 .. Header_Prefix_Bits - 1 =>
           Fixed.Bit_Value (Output, Position) =
             Expected_Header_Bit (Position));

      for I in 0 .. Literal_Length_Count - 1 loop
         pragma Loop_Invariant
           (for all Position in 0 .. Header_Prefix_Bits - 1 =>
              Fixed.Bit_Value (Output, Position) =
                Expected_Header_Bit (Position));
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Length_Code_At
                (Output, Header_Prefix_Bits + 4 * J,
                 Codebooks.Length_Of (Literal_Lengths, J)));
         pragma Loop_Invariant
           (for all P in Header_Prefix_Bits + 4 * I ..
              8 * Output'Length - 1 =>
                Fixed.Bit_Value (Output, P) =
                  Fixed.Bit_Value (Initial, P));
         Write_Length_Code
           (Output, Header_Prefix_Bits + 4 * I,
            Codebooks.Length_Of (Literal_Lengths, I));
      end loop;

      for I in 0 .. Distance_Count - 1 loop
         pragma Loop_Invariant
           (for all Position in 0 .. Header_Prefix_Bits - 1 =>
              Fixed.Bit_Value (Output, Position) =
                Expected_Header_Bit (Position));
         pragma Loop_Invariant
           (for all J in 0 .. Literal_Length_Count - 1 =>
              Length_Code_At
                (Output, Header_Prefix_Bits + 4 * J,
                 Codebooks.Length_Of (Literal_Lengths, J)));
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Length_Code_At
                (Output,
                 Header_Prefix_Bits
                   + 4 * (Literal_Length_Count + J),
                 Codebooks.Length_Of (Distances, J)));
         pragma Loop_Invariant
           (for all P in
              Header_Prefix_Bits
                + 4 * (Literal_Length_Count + I) ..
              8 * Output'Length - 1 =>
                Fixed.Bit_Value (Output, P) =
                  Fixed.Bit_Value (Initial, P));
         Write_Length_Code
           (Output,
            Header_Prefix_Bits + 4 * (Literal_Length_Count + I),
            Codebooks.Length_Of (Distances, I));
      end loop;

      Next_Bit := Header_Bit_Count;
   end Serialize_Header;

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

   --------------------
   -- Serialize_Body --
   --------------------

   procedure Serialize_Body
     (Data            : in     Byte_Array;
      Literal_Lengths : in     Codebooks.Codebook;
      Distances       : in     Codebooks.Codebook;
      Output          : in out Byte_Array;
      Produced        :    out Natural)
   is
      Header_End : Natural;
      Body_End   : Natural;
   begin
      Serialize_Header
        (Literal_Lengths, Distances, Output, Header_End);
      pragma Assert (Header_End = Header_Bit_Count);

      declare
         Header_Output : constant Byte_Array := Output with Ghost;
      begin
         Serialize_Payload
           (Data, Literal_Lengths, Distances,
            Output, Header_End, Body_End);
         pragma Assert
           (for all Position in 0 .. Header_Bit_Count - 1 =>
              Fixed.Bit_Value (Output, Position) =
                Fixed.Bit_Value (Header_Output, Position));
         Lemma_Header_Frame
           (Header_Output, Output, Literal_Lengths, Distances);
      end;

      Produced := (Body_End + 7) / 8;
      pragma Assert (Produced <= Max_Size (Data'Length));
   end Serialize_Body;

   pragma Assertion_Policy (Ghost => Ignore);
   procedure Lemma_Encoding_Uses_Header_Books
     (Input           : Byte_Array;
      Produced        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array)
   is
      procedure Lemma_Substitute_Encodable
        (Before_Literals, Before_Distances : Codebooks.Codebook;
         After_Literals, After_Distances   : Codebooks.Codebook)
      with
        Ghost,
        Pre  => Before_Literals.Kind = Codebooks.Canonical
                  and then After_Literals.Kind = Codebooks.Canonical
                  and then Before_Distances.Kind = Codebooks.Canonical
                  and then After_Distances.Kind = Codebooks.Canonical
                  and then Before_Literals.Lengths = After_Literals.Lengths
                  and then Before_Literals.Counts = After_Literals.Counts
                  and then Before_Distances.Lengths = After_Distances.Lengths
                  and then Before_Distances.Counts = After_Distances.Counts
                  and then Books_Encodable
                    (Before_Literals, Before_Distances),
        Post => Books_Encodable (After_Literals, After_Distances);

      procedure Lemma_Substitute_Encodable
        (Before_Literals, Before_Distances : Codebooks.Codebook;
         After_Literals, After_Distances   : Codebooks.Codebook)
      is
      begin
         Codebooks.Lemma_Ready_From_Fields
           (Before_Literals, After_Literals);
         Codebooks.Lemma_Ready_From_Fields
           (Before_Distances, After_Distances);
         Codebooks.Lemma_Lengths_At_Most_From_Fields
           (Before_Literals, After_Literals, 9);
         Codebooks.Lemma_Lengths_At_Most_From_Fields
           (Before_Distances, After_Distances, 9);
      end Lemma_Substitute_Encodable;

      procedure Lemma_Substitute_Covers
        (Before_Literals, Before_Distances : Codebooks.Codebook;
         After_Literals, After_Distances   : Codebooks.Codebook)
      with
        Ghost,
        Pre  => Data'Length <= Fixed.Max_Input
                  and then Before_Literals.Kind = Codebooks.Canonical
                  and then After_Literals.Kind = Codebooks.Canonical
                  and then Before_Distances.Kind = Codebooks.Canonical
                  and then After_Distances.Kind = Codebooks.Canonical
                  and then Before_Literals.Lengths = After_Literals.Lengths
                  and then Before_Literals.Counts = After_Literals.Counts
                  and then Before_Distances.Lengths = After_Distances.Lengths
                  and then Before_Distances.Counts = After_Distances.Counts
                  and then Payload.Covers
                    (Before_Literals, Before_Distances, Data),
        Post => Payload.Covers
                  (After_Literals, After_Distances, Data);

      procedure Lemma_Substitute_Covers
        (Before_Literals, Before_Distances : Codebooks.Codebook;
         After_Literals, After_Distances   : Codebooks.Codebook)
      is
      begin
         Codebooks.Lemma_Length_Of_From_Fields
           (Before_Literals, After_Literals);
         Codebooks.Lemma_Length_Of_From_Fields
           (Before_Distances, After_Distances);
         Payload.Lemma_Covers_From_Lengths
           (Before_Literals, Before_Distances,
            After_Literals, After_Distances, Data);
      end Lemma_Substitute_Covers;

      procedure Lemma_Substitute_Encoding
        (Before_Literals, Before_Distances : Codebooks.Codebook;
         After_Literals, After_Distances   : Codebooks.Codebook)
      with
        Ghost,
        Pre  => Input'Length <= Fixed.Max_Stream_Bytes
                  and then Input'Length >= Header_Byte_Count
                  and then Data'Length <= Max_Input
                  and then Before_Literals.Kind = Codebooks.Canonical
                  and then After_Literals.Kind = Codebooks.Canonical
                  and then Before_Distances.Kind = Codebooks.Canonical
                  and then After_Distances.Kind = Codebooks.Canonical
                  and then Before_Literals.Lengths = After_Literals.Lengths
                  and then Before_Literals.Counts = After_Literals.Counts
                  and then Before_Distances.Lengths = After_Distances.Lengths
                  and then Before_Distances.Counts = After_Distances.Counts
                  and then Books_Encodable
                    (Before_Literals, Before_Distances)
                  and then Books_Encodable
                    (After_Literals, After_Distances)
                  and then Payload.Covers
                    (Before_Literals, Before_Distances, Data)
                  and then Payload.Covers
                    (After_Literals, After_Distances, Data)
                  and then Is_Encoding
                    (Input, Produced,
                     Before_Literals, Before_Distances, Data),
        Post => Is_Encoding
                  (Input, Produced,
                   After_Literals, After_Distances, Data);

      procedure Lemma_Substitute_Encoding
        (Before_Literals, Before_Distances : Codebooks.Codebook;
         After_Literals, After_Distances   : Codebooks.Codebook)
      is
      begin
         Lemma_Header_From_Book_Fields
           (Input,
            Before_Literals, Before_Distances,
            After_Literals, After_Distances);
         Payload.Lemma_Encoding_From_Book_Fields
           (Input, Header_Bit_Count,
            Before_Literals, Before_Distances,
            After_Literals, After_Distances, Data);
         Payload.Lemma_Data_Bits_Equal_From_Book_Fields
           (Before_Literals, Before_Distances,
            After_Literals, After_Distances, Data, Data'Length);
         Codebooks.Lemma_Length_Of_From_Fields
           (Before_Literals, After_Literals);
      end Lemma_Substitute_Encoding;
   begin
      pragma Assert (Produced in 1 .. Input'Length);
      pragma Assert (Data'Length <= Max_Input);
      Lemma_Header_Books_Recovered
        (Input, Literal_Lengths, Distances);
      pragma Assert
        (Literal_Book_From_Header (Input) = Literal_Lengths);
      pragma Assert
        (Distance_Book_From_Header (Input) = Distances);
      Lemma_Substitute_Encodable
        (Literal_Lengths, Distances,
         Literal_Book_From_Header (Input),
         Distance_Book_From_Header (Input));
      Lemma_Substitute_Covers
        (Literal_Lengths, Distances,
         Literal_Book_From_Header (Input),
         Distance_Book_From_Header (Input));
      Lemma_Substitute_Encoding
        (Literal_Lengths, Distances,
         Literal_Book_From_Header (Input),
         Distance_Book_From_Header (Input));
   end Lemma_Encoding_Uses_Header_Books;

end Inflate.Dynamic;
