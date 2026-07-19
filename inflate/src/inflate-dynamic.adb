with Interfaces;

package body Inflate.Dynamic with SPARK_Mode => On is

   use Interfaces;
   use type Fixed.Symbol_Kind;

   --  Proof helpers are erased in the assertion-enabled focused executable,
   --  just as they are in the library's debug configuration.  Ordinary
   --  assertions in the harness remain enabled.
   pragma Assertion_Policy (Ghost => Ignore);

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
      pragma Unreferenced (Value);
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

   procedure Lemma_Byte_Frame
     (Before, After : Byte_Array; Consumed, Position : Natural)
   with
     Ghost,
     Pre  => Before'Length <= Fixed.Max_Stream_Bytes
               and then After'Length <= Fixed.Max_Stream_Bytes
               and then Consumed <= Before'Length
               and then Consumed <= After'Length
               and then Position < 8 * Consumed
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Fixed.Bit_Value (After, Position) =
               Fixed.Bit_Value (Before, Position);

   procedure Lemma_Byte_Frame
     (Before, After : Byte_Array; Consumed, Position : Natural) is null;

   procedure Lemma_Encoding_Frame
     (Before, After : Byte_Array;
      Produced      : Natural;
      Data          : Byte_Array)
   is
      Literal_Lengths : constant Codebooks.Codebook :=
        Literal_Book_From_Header (Before);
      Distances : constant Codebooks.Codebook :=
        Distance_Book_From_Header (Before);
      Encoding_End : constant Natural :=
        Header_Bit_Count
          + Payload.Data_Bits
              (Literal_Lengths, Distances, Data, Data'Length)
          + Codebooks.Length_Of (Literal_Lengths, 256);
   begin
      for Position in 0 .. Encoding_End - 1 loop
         pragma Loop_Invariant
           (for all P in 0 .. Position - 1 =>
              Fixed.Bit_Value (After, P) =
                Fixed.Bit_Value (Before, P));
         Lemma_Byte_Frame (Before, After, Produced, Position);
      end loop;

      Lemma_Header_Frame
        (Before, After, Literal_Lengths, Distances);
      Lemma_Header_Books_Recovered
        (After, Literal_Lengths, Distances);
      Payload.Lemma_Payload_Frame
        (Before, After, Header_Bit_Count,
         Literal_Lengths, Distances, Data);

      pragma Assert
        (Is_Encoding
           (After, Produced, Literal_Lengths, Distances, Data));
      Lemma_Encoding_Uses_Header_Books
        (After, Produced, Literal_Lengths, Distances, Data);
   end Lemma_Encoding_Frame;

   procedure Lemma_Pow2_Step (N : Codebooks.Code_Length_Pos)
   with
     Ghost,
     Pre  => N > 1,
     Post => Codebooks.Pow2 (N) = 2 * Codebooks.Pow2 (N - 1);

   procedure Lemma_Pow2_Step (N : Codebooks.Code_Length_Pos) is
   begin
      case N is
         when 1 .. 15 => null;
      end case;
   end Lemma_Pow2_Step;

   procedure Lemma_Div_Monotone (A, B : Natural; D : Positive)
   with
     Ghost,
     Pre  => A >= B,
     Post => A / D >= B / D;

   procedure Lemma_Div_Monotone
     (A, B : Natural; D : Positive) is null;

   procedure Lemma_Scaled_Div
     (A, B : Natural; D, Q : Positive)
   with
     Ghost,
     Pre  => A <= Codebooks.Pow2 (15)
               and then B <= Codebooks.Pow2 (15)
               and then D <= Codebooks.Pow2 (15)
               and then Q <= Codebooks.Pow2 (15)
               and then A >= 2 * B
               and then D = 2 * Q,
     Post => A / D >= B / Q;

   procedure Lemma_Scaled_Div
     (A, B : Natural; D, Q : Positive) is null;

   --  Canonical ranges at a longer length lie strictly after every code at
   --  a shorter length once both are viewed at that shorter width.
   procedure Lemma_First_Separated
     (Book        : Codebooks.Codebook;
      Short, Long : Codebooks.Code_Length_Pos)
   with
     Ghost,
     Pre  => Book.Kind = Codebooks.Canonical
               and then Codebooks.Ready (Book)
               and then Short < Long,
     Post => Codebooks.First_Code (Book.Counts, Long)
                 / Codebooks.Pow2 (Long - Short) >=
               Codebooks.First_Code (Book.Counts, Short)
                 + Book.Counts (Short),
     Subprogram_Variant => (Decreases => Long - Short);

   procedure Lemma_First_Separated
     (Book        : Codebooks.Codebook;
      Short, Long : Codebooks.Code_Length_Pos)
   is
   begin
      if Long > Short + 1 then
         Lemma_First_Separated (Book, Short, Long - 1);
         Lemma_Pow2_Step (Long - Short);
         pragma Assert
           (Codebooks.First_Code (Book.Counts, Long) >=
              2 * Codebooks.First_Code (Book.Counts, Long - 1));
         declare
            P : constant Natural :=
              Codebooks.First_Code (Book.Counts, Long - 1);
            Q : constant Positive := Codebooks.Pow2 (Long - Short - 1);
            A : constant Natural :=
              Codebooks.First_Code (Book.Counts, Long);
            D : constant Positive := Codebooks.Pow2 (Long - Short);
         begin
            pragma Assert (P <= Codebooks.Pow2 (Long - 1));
            pragma Assert (A <= Codebooks.Pow2 (Long));
            pragma Assert (D = 2 * Q);
            Lemma_Scaled_Div (A, P, D, Q);
         end;
      else
         pragma Assert (Long = Short + 1);
         pragma Assert
           (Codebooks.First_Code (Book.Counts, Long) =
              2 * (Codebooks.First_Code (Book.Counts, Short)
                     + Book.Counts (Short)));
      end if;
   end Lemma_First_Separated;

   procedure Lemma_Double_Div
     (P, B : Natural; Q : Positive)
   with
     Ghost,
     Pre  => P < Codebooks.Pow2 (15)
               and then B <= 1
               and then Q <= Codebooks.Pow2 (15),
     Post => (2 * P + B) / (2 * Q) = P / Q;

   procedure Lemma_Double_Div
     (P, B : Natural; Q : Positive) is null;

   procedure Lemma_Prefix_Shortens
     (Input       : Byte_Array;
      Start       : Natural;
      Short, Long : Codebooks.Code_Length_Pos)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Short < Long
               and then Long <= 9
               and then Start <= 8 * Input'Length
               and then Long <= 8 * Input'Length - Start,
     Post => Fixed.Prefix_Value (Input, Start, Short) =
               Fixed.Prefix_Value (Input, Start, Long)
                 / Codebooks.Pow2 (Long - Short),
     Subprogram_Variant => (Decreases => Long - Short);

   procedure Lemma_Prefix_Shortens
     (Input       : Byte_Array;
      Start       : Natural;
      Short, Long : Codebooks.Code_Length_Pos)
   is
   begin
      if Long > Short + 1 then
         Lemma_Prefix_Shortens (Input, Start, Short, Long - 1);
         Lemma_Pow2_Step (Long - Short);
         declare
            P : constant Natural :=
              Fixed.Prefix_Value (Input, Start, Long - 1);
            B : constant Natural :=
              Fixed.Bit_Value (Input, Start + Long - 1);
            Q : constant Positive := Codebooks.Pow2 (Long - Short - 1);
         begin
            pragma Assert (P < Codebooks.Pow2 (Long - 1));
            pragma Assert
              (Fixed.Prefix_Value (Input, Start, Long) = 2 * P + B);
            Lemma_Double_Div (P, B, Q);
         end;
      else
         pragma Assert (Long = Short + 1);
         pragma Assert
           (Fixed.Prefix_Value (Input, Start, Long) / 2 =
              Fixed.Prefix_Value (Input, Start, Short));
      end if;
   end Lemma_Prefix_Shortens;

   procedure Lemma_No_Shorter_Code
     (Input    : Byte_Array;
      Start    : Natural;
      Book     : Codebooks.Codebook;
      Expected : Codebooks.Symbol_Index;
      Short    : Codebooks.Code_Length_Pos)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Book.Kind = Codebooks.Canonical
               and then Codebooks.Ready (Book)
               and then Codebooks.Lengths_At_Most (Book, 9)
               and then Codebooks.Length_Of (Book, Expected) > 0
               and then Short < Codebooks.Length_Of (Book, Expected)
               and then Start <= 8 * Input'Length
               and then Codebooks.Length_Of (Book, Expected) <=
                          8 * Input'Length - Start
               and then Fixed.Prefix_Value
                 (Input, Start, Codebooks.Length_Of (Book, Expected)) =
                   Codebooks.Code_Of (Book, Expected),
     Post => Fixed.Prefix_Value (Input, Start, Short) <
               Codebooks.First_Code (Book.Counts, Short)
             or else Fixed.Prefix_Value (Input, Start, Short) >=
               Codebooks.First_Code (Book.Counts, Short)
                 + Book.Counts (Short);

   procedure Lemma_No_Shorter_Code
     (Input    : Byte_Array;
      Start    : Natural;
      Book     : Codebooks.Codebook;
      Expected : Codebooks.Symbol_Index;
      Short    : Codebooks.Code_Length_Pos)
   is
      Long : constant Codebooks.Code_Length_Pos :=
        Codebooks.Length_Of (Book, Expected);
   begin
      Lemma_Prefix_Shortens (Input, Start, Short, Long);
      Lemma_First_Separated (Book, Short, Long);
      pragma Assert
        (Codebooks.Code_Of (Book, Expected) >=
           Codebooks.First_Code (Book.Counts, Long));
      Lemma_Div_Monotone
        (Codebooks.Code_Of (Book, Expected),
         Codebooks.First_Code (Book.Counts, Long),
         Codebooks.Pow2 (Long - Short));
   end Lemma_No_Shorter_Code;

   procedure Lemma_Count_Step
     (Lengths : Codebooks.Code_Length_Array;
      Length  : Codebooks.Code_Length_Pos;
      Pos, Hi : Natural)
   with
     Ghost,
     Pre  => Pos < Hi
               and then Hi <= Codebooks.Symbol_Index'Last + 1
               and then Lengths (Pos) = Length,
     Post => Codebooks.Count_Length (Lengths, Length, Hi) >
               Codebooks.Count_Length (Lengths, Length, Pos),
     Subprogram_Variant => (Decreases => Hi - Pos);

   procedure Lemma_Count_Step
     (Lengths : Codebooks.Code_Length_Array;
      Length  : Codebooks.Code_Length_Pos;
      Pos, Hi : Natural)
   is
   begin
      if Hi > Pos + 1 then
         Lemma_Count_Step (Lengths, Length, Pos, Hi - 1);
      end if;
   end Lemma_Count_Step;

   procedure Lemma_Rank_Unique
     (Book : Codebooks.Codebook;
      A, B : Codebooks.Symbol_Index)
   with
     Ghost,
     Pre  => Book.Kind = Codebooks.Canonical
               and then Codebooks.Exact_Counts (Book)
               and then Codebooks.Length_Of (Book, A) > 0
               and then Codebooks.Length_Of (Book, B) =
                          Codebooks.Length_Of (Book, A)
               and then Codebooks.Rank_Of (Book, A) =
                          Codebooks.Rank_Of (Book, B),
     Post => A = B;

   procedure Lemma_Rank_Unique
     (Book : Codebooks.Codebook;
      A, B : Codebooks.Symbol_Index)
   is
      Length : constant Codebooks.Code_Length_Pos :=
        Codebooks.Length_Of (Book, A);
   begin
      if A < B then
         Lemma_Count_Step (Book.Lengths, Length, A, B);
      elsif B < A then
         Lemma_Count_Step (Book.Lengths, Length, B, A);
      end if;
   end Lemma_Rank_Unique;

   --  Prefix-freeness plus rank uniqueness: two canonical codewords starting
   --  at the same stream bit identify the same symbol.
   procedure Lemma_Codewords_Unique
     (Input : Byte_Array;
      Start : Natural;
      Book  : Codebooks.Codebook;
      A, B  : Codebooks.Symbol_Index)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Book.Kind = Codebooks.Canonical
               and then Codebooks.Ready (Book)
               and then Codebooks.Lengths_At_Most (Book, 9)
               and then Codebooks.Length_Of (Book, A) > 0
               and then Codebooks.Length_Of (Book, B) > 0
               and then Start <= 8 * Input'Length
               and then Codebooks.Length_Of (Book, A) <=
                          8 * Input'Length - Start
               and then Codebooks.Length_Of (Book, B) <=
                          8 * Input'Length - Start
               and then Fixed.Prefix_Value
                 (Input, Start, Codebooks.Length_Of (Book, A)) =
                   Codebooks.Code_Of (Book, A)
               and then Fixed.Prefix_Value
                 (Input, Start, Codebooks.Length_Of (Book, B)) =
                   Codebooks.Code_Of (Book, B),
     Post => A = B;

   procedure Lemma_Codewords_Unique
     (Input : Byte_Array;
      Start : Natural;
      Book  : Codebooks.Codebook;
      A, B  : Codebooks.Symbol_Index)
   is
      LA : constant Codebooks.Code_Length_Pos :=
        Codebooks.Length_Of (Book, A);
      LB : constant Codebooks.Code_Length_Pos :=
        Codebooks.Length_Of (Book, B);
   begin
      if LA < LB then
         Lemma_No_Shorter_Code (Input, Start, Book, B, LA);
         pragma Assert
           (Codebooks.Code_Of (Book, A) >=
              Codebooks.First_Code (Book.Counts, LA));
         pragma Assert
           (Codebooks.Code_Of (Book, A) <
              Codebooks.First_Code (Book.Counts, LA) + Book.Counts (LA));
         pragma Assert (False);
      elsif LB < LA then
         Lemma_No_Shorter_Code (Input, Start, Book, A, LB);
         pragma Assert
           (Codebooks.Code_Of (Book, B) >=
              Codebooks.First_Code (Book.Counts, LB));
         pragma Assert
           (Codebooks.Code_Of (Book, B) <
              Codebooks.First_Code (Book.Counts, LB) + Book.Counts (LB));
         pragma Assert (False);
      else
         pragma Assert
           (Codebooks.Code_Of (Book, A) = Codebooks.Code_Of (Book, B));
         pragma Assert
           (Codebooks.Rank_Of (Book, A) = Codebooks.Rank_Of (Book, B));
         Lemma_Rank_Unique (Book, A, B);
      end if;
   end Lemma_Codewords_Unique;

   -------------------
   -- Decode_Symbol --
   -------------------

   function Decode_Symbol
     (Input : Byte_Array;
      Start : Natural;
      Book  : Codebooks.Codebook) return Decoded_Symbol
   is
   begin
      for Symbol in Codebooks.Symbol_Index loop
         pragma Loop_Invariant
           (for all Earlier in 0 .. Symbol - 1 =>
              not Code_Matches (Input, Start, Book, Earlier));
         if Code_Matches (Input, Start, Book, Symbol) then
            return
              (Valid    => True,
               Symbol   => Symbol,
               Position => Start + Codebooks.Length_Of (Book, Symbol));
         end if;
      end loop;
      return (Valid => False, Symbol => 0, Position => Start);
   end Decode_Symbol;

   ---------------
   -- Spec_Walk --
   ---------------

   function Spec_Walk
     (Input           : Byte_Array;
      Position        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Decoded         : Natural) return Stream_Info
   is
      Literal_Code : constant Decoded_Symbol :=
        Decode_Symbol (Input, Position, Literal_Lengths);
   begin
      if not Literal_Code.Valid then
         return (False, 0, 0);
      elsif Literal_Code.Symbol <= 255 then
         if Decoded = Max_Input then
            return (False, 0, 0);
         end if;
         declare
            Tail : constant Stream_Info :=
              Spec_Walk
                (Input, Literal_Code.Position,
                 Literal_Lengths, Distances, Decoded + 1);
         begin
            if Tail.Valid then
               return (True, Tail.End_Bit, Tail.Decoded_Length + 1);
            else
               return (False, 0, 0);
            end if;
         end;
      elsif Literal_Code.Symbol = 256 then
         return (True, Literal_Code.Position, 0);
      elsif Literal_Code.Symbol in 257 .. 264 then
         declare
            Length : constant Natural := Literal_Code.Symbol - 254;
            Distance_Code : constant Decoded_Symbol :=
              Decode_Symbol (Input, Literal_Code.Position, Distances);
         begin
            if not Distance_Code.Valid
              or else Distance_Code.Symbol > 3
              or else Distance_Code.Symbol + 1 > Decoded
              or else Length > Max_Input - Decoded
            then
               return (False, 0, 0);
            end if;
            declare
               Tail : constant Stream_Info :=
                 Spec_Walk
                   (Input, Distance_Code.Position,
                    Literal_Lengths, Distances, Decoded + Length);
            begin
               if Tail.Valid then
                  return (True, Tail.End_Bit,
                          Tail.Decoded_Length + Length);
               else
                  return (False, 0, 0);
               end if;
            end;
         end;
      else
         return (False, 0, 0);
      end if;
   end Spec_Walk;

   procedure Lemma_Walk_Start
     (Input           : Byte_Array;
      Position        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Decoded         : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Position <= 8 * Input'Length
               and then Literal_Lengths.Kind = Codebooks.Canonical
               and then Distances.Kind = Codebooks.Canonical
               and then Codebooks.Ready (Literal_Lengths)
               and then Codebooks.Ready (Distances)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9)
               and then Decoded <= Max_Input,
     Post => Spec_Walk
               (Input, Position, Literal_Lengths, Distances, Decoded) =
               (if Spec_Walk
                  (Input, Position, Literal_Lengths, Distances, Decoded).Valid
                then
                  (True,
                   Spec_Walk
                     (Input, Position, Literal_Lengths, Distances, Decoded)
                       .End_Bit,
                   Spec_Walk
                     (Input, Position, Literal_Lengths, Distances, Decoded)
                       .Decoded_Length)
                else (False, 0, 0));

   procedure Lemma_Walk_Start
     (Input           : Byte_Array;
      Position        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Decoded         : Natural) is null;

   ----------
   -- Walk --
   ----------

   function Walk
     (Input           : Byte_Array;
      Position        : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Decoded         : Natural) return Stream_Info
   is
      Start : constant Natural := Position;
      P     : Natural := Position;
      Count : Natural := 0;
      Literal_Code, Distance_Code : Decoded_Symbol;
   begin
      Lemma_Walk_Start
        (Input, Start, Literal_Lengths, Distances, Decoded);
      loop
         pragma Loop_Invariant (P in Start .. 8 * Input'Length);
         pragma Loop_Invariant (Count <= Max_Input - Decoded);
         pragma Loop_Invariant
           (Spec_Walk
              (Input, Start, Literal_Lengths, Distances, Decoded) =
              (if Spec_Walk
                 (Input, P, Literal_Lengths, Distances, Decoded + Count).Valid
               then
                 (True,
                  Spec_Walk
                    (Input, P, Literal_Lengths, Distances, Decoded + Count)
                      .End_Bit,
                  Count
                    + Spec_Walk
                        (Input, P, Literal_Lengths, Distances,
                         Decoded + Count).Decoded_Length)
               else (False, 0, 0)));
         pragma Loop_Variant (Increases => P);

         Literal_Code := Decode_Symbol (Input, P, Literal_Lengths);
         if not Literal_Code.Valid then
            return (False, 0, 0);
         elsif Literal_Code.Symbol <= 255 then
            if Decoded + Count = Max_Input then
               return (False, 0, 0);
            end if;
            P := Literal_Code.Position;
            Count := Count + 1;
            pragma Assert
              (Spec_Walk
                 (Input, Start, Literal_Lengths, Distances, Decoded) =
                 (if Spec_Walk
                    (Input, P, Literal_Lengths, Distances, Decoded + Count)
                       .Valid
                  then
                    (True,
                     Spec_Walk
                       (Input, P, Literal_Lengths, Distances, Decoded + Count)
                         .End_Bit,
                     Count
                       + Spec_Walk
                           (Input, P, Literal_Lengths, Distances,
                            Decoded + Count).Decoded_Length)
                  else (False, 0, 0)));
         elsif Literal_Code.Symbol = 256 then
            return (True, Literal_Code.Position, Count);
         elsif Literal_Code.Symbol in 257 .. 264 then
            declare
               Length : constant Natural := Literal_Code.Symbol - 254;
            begin
               Distance_Code :=
                 Decode_Symbol (Input, Literal_Code.Position, Distances);
               if not Distance_Code.Valid
                 or else Distance_Code.Symbol > 3
                 or else Distance_Code.Symbol + 1 > Decoded + Count
                 or else Length > Max_Input - (Decoded + Count)
               then
                  return (False, 0, 0);
               end if;
               P := Distance_Code.Position;
               Count := Count + Length;
               pragma Assert
                 (Spec_Walk
                    (Input, Start, Literal_Lengths, Distances, Decoded) =
                    (if Spec_Walk
                       (Input, P, Literal_Lengths, Distances,
                        Decoded + Count).Valid
                     then
                       (True,
                        Spec_Walk
                          (Input, P, Literal_Lengths, Distances,
                           Decoded + Count).End_Bit,
                        Count
                          + Spec_Walk
                              (Input, P, Literal_Lengths, Distances,
                               Decoded + Count).Decoded_Length)
                     else (False, 0, 0)));
            end;
         else
            return (False, 0, 0);
         end if;
      end loop;
   end Walk;

   -------------
   -- Analyze --
   -------------

   function Analyze (Input : Byte_Array) return Stream_Info is
   begin
      if Input'Length < Header_Byte_Count then
         return (False, 0, 0);
      end if;
      declare
         Literal_Lengths : constant Codebooks.Codebook :=
           Literal_Book_From_Header (Input);
         Distances : constant Codebooks.Codebook :=
           Distance_Book_From_Header (Input);
      begin
         if not Books_Encodable (Literal_Lengths, Distances)
           or else not Header_Encodes
             (Input, Literal_Lengths, Distances)
         then
            return (False, 0, 0);
         end if;
         return Walk
           (Input, Header_Bit_Count,
            Literal_Lengths, Distances, 0);
      end;
   end Analyze;

   procedure Lemma_Codeword_Decodes
     (Input    : Byte_Array;
      Start    : Natural;
      Book     : Codebooks.Codebook;
      Expected : Codebooks.Symbol_Index)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Start <= 8 * Input'Length
               and then Book.Kind = Codebooks.Canonical
               and then Codebooks.Ready (Book)
               and then Codebooks.Lengths_At_Most (Book, 9)
               and then Code_Matches (Input, Start, Book, Expected),
     Post => Decode_Symbol (Input, Start, Book).Valid
               and then Decode_Symbol
                 (Input, Start, Book).Symbol = Expected
               and then Decode_Symbol
                 (Input, Start, Book).Position =
                   Start + Codebooks.Length_Of (Book, Expected);

   procedure Lemma_Codeword_Decodes
     (Input    : Byte_Array;
      Start    : Natural;
      Book     : Codebooks.Codebook;
      Expected : Codebooks.Symbol_Index)
   is
      Result : constant Decoded_Symbol := Decode_Symbol (Input, Start, Book);
   begin
      pragma Assert (Result.Valid);
      Lemma_Codewords_Unique
        (Input, Start, Book, Result.Symbol, Expected);
   end Lemma_Codeword_Decodes;

   procedure Lemma_Payload_Analyzes
     (Input           : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Index           : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Start <= 8 * Input'Length
               and then Literal_Lengths.Kind = Codebooks.Canonical
               and then Distances.Kind = Codebooks.Canonical
               and then Codebooks.Ready (Literal_Lengths)
               and then Codebooks.Ready (Distances)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9)
               and then Data'Length <= Max_Input
               and then Payload.Covers
                 (Literal_Lengths, Distances, Data)
               and then Payload.Is_Encoding
                 (Input, Start, Literal_Lengths, Distances, Data)
               and then Index <= Data'Length
               and then Fixed.Token_Boundary (Data, Index),
     Post => Spec_Walk
               (Input,
                Start + Payload.Data_Bits
                  (Literal_Lengths, Distances, Data, Index),
                Literal_Lengths, Distances, Index).Valid
               and then Spec_Walk
                 (Input,
                  Start + Payload.Data_Bits
                    (Literal_Lengths, Distances, Data, Index),
                  Literal_Lengths, Distances, Index).End_Bit =
                    Start + Payload.Data_Bits
                      (Literal_Lengths, Distances, Data, Data'Length)
                    + Codebooks.Length_Of (Literal_Lengths, 256)
               and then Spec_Walk
                 (Input,
                  Start + Payload.Data_Bits
                    (Literal_Lengths, Distances, Data, Index),
                  Literal_Lengths, Distances, Index).Decoded_Length =
                    Data'Length - Index,
     Subprogram_Variant => (Decreases => Data'Length - Index);

   procedure Lemma_Payload_Analyzes
     (Input           : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Index           : Natural)
   is
      Bit_Position : constant Natural :=
        Start + Payload.Data_Bits
          (Literal_Lengths, Distances, Data, Index);
   begin
      if Index = Data'Length then
         pragma Assert
           (Code_Matches
              (Input, Bit_Position, Literal_Lengths, 256));
         Lemma_Codeword_Decodes
           (Input, Bit_Position, Literal_Lengths, 256);
      else
         declare
            Token : constant Fixed.Symbol_Result :=
              Fixed.Selected_Token (Data, Index);
            Symbol : constant Codebooks.Symbol_Index :=
              (if Token.Kind = Fixed.Match
               then Payload.Length_Symbol (Token.Length)
               else Natural (Data (Data'First + Index)));
            Literal_Code : Decoded_Symbol;
         begin
            pragma Assert
              (Payload.Token_Encoded
                 (Input, Start, Literal_Lengths, Distances, Data, Index));
            pragma Assert
              (Code_Matches
                 (Input, Bit_Position, Literal_Lengths, Symbol));
            Lemma_Codeword_Decodes
              (Input, Bit_Position, Literal_Lengths, Symbol);
            Literal_Code :=
              Decode_Symbol (Input, Bit_Position, Literal_Lengths);

            if Token.Kind = Fixed.Match then
               declare
                  Distance_Symbol : constant Codebooks.Symbol_Index :=
                    Payload.Distance_Symbol (Token.Distance);
               begin
                  pragma Assert (Literal_Code.Symbol in 257 .. 264);
                  pragma Assert
                    (Code_Matches
                       (Input, Literal_Code.Position,
                        Distances, Distance_Symbol));
                  Lemma_Codeword_Decodes
                    (Input, Literal_Code.Position,
                     Distances, Distance_Symbol);
               end;
            else
               pragma Assert (Literal_Code.Symbol <= 255);
            end if;

            Payload.Lemma_Data_Bits_Advance
              (Literal_Lengths, Distances, Data, Index);
            Lemma_Payload_Analyzes
              (Input, Start, Literal_Lengths, Distances, Data,
               Fixed.Next_Position (Data, Index));
         end;
      end if;
   end Lemma_Payload_Analyzes;

   --------------------------------
   -- Lemma_Encoding_Analyzes --
   --------------------------------

   procedure Lemma_Encoding_Analyzes
     (Input    : Byte_Array;
      Produced : Natural;
      Data     : Byte_Array)
   is
      Literal_Lengths : constant Codebooks.Codebook :=
        Literal_Book_From_Header (Input);
      Distances : constant Codebooks.Codebook :=
        Distance_Book_From_Header (Input);
   begin
      pragma Unreferenced (Produced);
      pragma Assert (Fixed.Token_Boundary (Data, 0));
      Lemma_Payload_Analyzes
        (Input, Header_Bit_Count,
         Literal_Lengths, Distances, Data, 0);
      pragma Assert
        (Walk
           (Input, Header_Bit_Count,
            Literal_Lengths, Distances, 0).Valid);
      pragma Assert (Analyze (Input).Valid);
   end Lemma_Encoding_Analyzes;

   procedure Lemma_Prefix_Element_Equal
     (Left, Right : Byte_Array; Count, Index : Natural)
   with
     Ghost,
     Pre  => Count <= Left'Length
               and then Count <= Right'Length
               and then Index < Count
               and then
             (for all I in 0 .. Count - 1 =>
                Left (Left'First + I) = Right (Right'First + I)),
     Post => Left (Left'First + Index) = Right (Right'First + Index);

   procedure Lemma_Prefix_Element_Equal
     (Left, Right : Byte_Array; Count, Index : Natural) is null;

   procedure Lemma_Match_Functional
     (Left, Right : Byte_Array; Index, Length, Distance : Natural)
   with
     Ghost,
     Pre  => Left'Length <= Fixed.Max_Input
               and then Right'Length <= Fixed.Max_Input
               and then Length in 3 .. 10
               and then Distance in 1 .. 4
               and then Distance <= Index
               and then Length <= Left'Length - Index
               and then Length <= Right'Length - Index
               and then Fixed.Match_Applies
                 (Left, Index, Length, Distance)
               and then Fixed.Match_Applies
                 (Right, Index, Length, Distance)
               and then
             (for all I in 0 .. Index - 1 =>
                Left (Left'First + I) = Right (Right'First + I)),
     Post =>
       (for all K in 0 .. Length - 1 =>
          Left (Left'First + Index + K) =
            Right (Right'First + Index + K));

   procedure Lemma_Match_Functional
     (Left, Right : Byte_Array; Index, Length, Distance : Natural)
   is
   begin
      for K in 0 .. Length - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. K - 1 =>
              Left (Left'First + Index + J) =
                Right (Right'First + Index + J));
         if K < Distance then
            Lemma_Prefix_Element_Equal
              (Left, Right, Index, Index + K - Distance);
         else
            pragma Assert (K - Distance < K);
         end if;
         pragma Assert
           (Left (Left'First + Index + K) =
              Right (Right'First + Index + K));
      end loop;
   end Lemma_Match_Functional;

   procedure Lemma_Prefix_Extend_Match
     (Left, Right : Byte_Array; Index, Length : Natural)
   with
     Ghost,
     Pre  => Index <= Left'Length
               and then Index <= Right'Length
               and then Length in 3 .. 10
               and then Length <= Left'Length - Index
               and then Length <= Right'Length - Index
               and then
             (for all I in 0 .. Index - 1 =>
                Left (Left'First + I) = Right (Right'First + I))
               and then
             (for all K in 0 .. Length - 1 =>
                Left (Left'First + Index + K) =
                  Right (Right'First + Index + K)),
     Post =>
       (for all I in 0 .. Index + Length - 1 =>
          Left (Left'First + I) = Right (Right'First + I));

   procedure Lemma_Prefix_Extend_Match
     (Left, Right : Byte_Array; Index, Length : Natural)
   is
   begin
      for I in 0 .. Index + Length - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Left (Left'First + J) = Right (Right'First + J));
         if I < Index then
            pragma Assert
              (Left (Left'First + I) = Right (Right'First + I));
         else
            pragma Assert (I - Index < Length);
            pragma Assert
              (Left (Left'First + Index + (I - Index)) =
                 Right (Right'First + Index + (I - Index)));
         end if;
      end loop;
   end Lemma_Prefix_Extend_Match;

   procedure Lemma_Prefix_Extend
     (Left, Right : Byte_Array; Old_Count, New_Count : Natural)
   with
     Ghost,
     Pre  => Old_Count <= New_Count
               and then New_Count <= Left'Length
               and then New_Count <= Right'Length
               and then
             (for all I in 0 .. Old_Count - 1 =>
                Left (Left'First + I) = Right (Right'First + I))
               and then
             (for all I in Old_Count .. New_Count - 1 =>
                Left (Left'First + I) = Right (Right'First + I)),
     Post =>
       (for all I in 0 .. New_Count - 1 =>
          Left (Left'First + I) = Right (Right'First + I));

   procedure Lemma_Prefix_Extend
     (Left, Right : Byte_Array; Old_Count, New_Count : Natural)
   is
   begin
      for I in 0 .. New_Count - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Left (Left'First + J) = Right (Right'First + J));
         if I < Old_Count then
            pragma Assert
              (Left (Left'First + I) = Right (Right'First + I));
         else
            pragma Assert (I in Old_Count .. New_Count - 1);
         end if;
      end loop;
   end Lemma_Prefix_Extend;

   procedure Lemma_Payload_Functional
     (Input           : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Left, Right     : Byte_Array;
      Index           : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Literal_Lengths.Kind = Codebooks.Canonical
               and then Distances.Kind = Codebooks.Canonical
               and then Codebooks.Ready (Literal_Lengths)
               and then Codebooks.Ready (Distances)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9)
               and then Left'Length <= Fixed.Max_Input
               and then Right'Length <= Fixed.Max_Input
               and then Payload.Covers
                 (Literal_Lengths, Distances, Left)
               and then Payload.Covers
                 (Literal_Lengths, Distances, Right)
               and then Payload.Is_Encoding
                 (Input, Start, Literal_Lengths, Distances, Left)
               and then Payload.Is_Encoding
                 (Input, Start, Literal_Lengths, Distances, Right)
               and then Index <= Left'Length
               and then Index <= Right'Length
               and then Fixed.Token_Boundary (Left, Index)
               and then Fixed.Token_Boundary (Right, Index)
               and then Payload.Data_Bits
                 (Literal_Lengths, Distances, Left, Index) =
                   Payload.Data_Bits
                     (Literal_Lengths, Distances, Right, Index)
               and then
             (for all I in 0 .. Index - 1 =>
                Left (Left'First + I) = Right (Right'First + I)),
     Post => Left'Length = Right'Length
               and then
             (for all I in 0 .. Left'Length - 1 =>
                Left (Left'First + I) = Right (Right'First + I)),
     Subprogram_Variant =>
       (Decreases => Left'Length - Index + Right'Length - Index);

   procedure Lemma_Payload_Functional
     (Input           : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Left, Right     : Byte_Array;
      Index           : Natural)
   is
      Bit_Position : constant Natural :=
        Start + Payload.Data_Bits
          (Literal_Lengths, Distances, Left, Index);
   begin
      if Index = Left'Length then
         if Index = Right'Length then
            null;
         else
            declare
               Token : constant Fixed.Symbol_Result :=
                 Fixed.Selected_Token (Right, Index);
               Symbol : constant Codebooks.Symbol_Index :=
                 (if Token.Kind = Fixed.Match
                  then Payload.Length_Symbol (Token.Length)
                  else Natural (Right (Right'First + Index)));
            begin
               pragma Assert
                 (Payload.Token_Encoded
                    (Input, Start, Literal_Lengths, Distances,
                     Right, Index));
               Lemma_Codewords_Unique
                 (Input, Bit_Position, Literal_Lengths, 256, Symbol);
               pragma Assert (Symbol /= 256);
               pragma Assert (False);
            end;
         end if;
      elsif Index = Right'Length then
         declare
            Token : constant Fixed.Symbol_Result :=
              Fixed.Selected_Token (Left, Index);
            Symbol : constant Codebooks.Symbol_Index :=
              (if Token.Kind = Fixed.Match
               then Payload.Length_Symbol (Token.Length)
               else Natural (Left (Left'First + Index)));
         begin
            pragma Assert
              (Payload.Token_Encoded
                 (Input, Start, Literal_Lengths, Distances, Left, Index));
            Lemma_Codewords_Unique
              (Input, Bit_Position, Literal_Lengths, Symbol, 256);
            pragma Assert (Symbol /= 256);
            pragma Assert (False);
         end;
      else
         declare
            Left_Token : constant Fixed.Symbol_Result :=
              Fixed.Selected_Token (Left, Index);
            Right_Token : constant Fixed.Symbol_Result :=
              Fixed.Selected_Token (Right, Index);
            Left_Symbol : constant Codebooks.Symbol_Index :=
              (if Left_Token.Kind = Fixed.Match
               then Payload.Length_Symbol (Left_Token.Length)
               else Natural (Left (Left'First + Index)));
            Right_Symbol : constant Codebooks.Symbol_Index :=
              (if Right_Token.Kind = Fixed.Match
               then Payload.Length_Symbol (Right_Token.Length)
               else Natural (Right (Right'First + Index)));
         begin
            pragma Assert
              (Payload.Token_Encoded
                 (Input, Start, Literal_Lengths, Distances, Left, Index));
            pragma Assert
              (Payload.Token_Encoded
                 (Input, Start, Literal_Lengths, Distances, Right, Index));
            Lemma_Codewords_Unique
              (Input, Bit_Position, Literal_Lengths,
               Left_Symbol, Right_Symbol);

            if Left_Token.Kind = Fixed.Match then
               pragma Assert (Left_Symbol in 257 .. 264);
               pragma Assert (Right_Token.Kind = Fixed.Match);
               pragma Assert (Left_Token.Length = Right_Token.Length);
               declare
                  Literal_Length : constant Positive :=
                    Codebooks.Length_Of
                      (Literal_Lengths, Left_Symbol);
                  Left_Distance : constant Codebooks.Symbol_Index :=
                    Payload.Distance_Symbol (Left_Token.Distance);
                  Right_Distance : constant Codebooks.Symbol_Index :=
                    Payload.Distance_Symbol (Right_Token.Distance);
               begin
                  Lemma_Codewords_Unique
                    (Input, Bit_Position + Literal_Length, Distances,
                     Left_Distance, Right_Distance);
                  pragma Assert
                    (Left_Token.Distance = Right_Token.Distance);
                  Lemma_Match_Functional
                    (Left, Right, Index, Left_Token.Length,
                     Left_Token.Distance);
                  Lemma_Prefix_Extend_Match
                    (Left, Right, Index, Left_Token.Length);
               end;
            else
               pragma Assert (Left_Symbol <= 255);
               pragma Assert (Right_Token.Kind = Fixed.Literal);
               pragma Assert
                 (Left (Left'First + Index) =
                    Right (Right'First + Index));
               Lemma_Prefix_Extend (Left, Right, Index, Index + 1);
            end if;

            Payload.Lemma_Data_Bits_Advance
              (Literal_Lengths, Distances, Left, Index);
            Payload.Lemma_Data_Bits_Advance
              (Literal_Lengths, Distances, Right, Index);
            pragma Assert
              (Payload.Token_Bit_Cost
                 (Literal_Lengths, Distances, Left, Index) =
               Payload.Token_Bit_Cost
                 (Literal_Lengths, Distances, Right, Index));
            pragma Assert
              (Fixed.Next_Position (Left, Index) =
                 Fixed.Next_Position (Right, Index));
            Lemma_Payload_Functional
              (Input, Start, Literal_Lengths, Distances, Left, Right,
               Fixed.Next_Position (Left, Index));
         end;
      end if;
   end Lemma_Payload_Functional;

   procedure Lemma_Encoding_Functional
     (Input       : Byte_Array;
      Produced    : Natural;
      Left, Right : Byte_Array)
   is
      Literal_Lengths : constant Codebooks.Codebook :=
        Literal_Book_From_Header (Input);
      Distances : constant Codebooks.Codebook :=
        Distance_Book_From_Header (Input);
   begin
      pragma Assert (Produced in 1 .. Input'Length);
      pragma Assert (Left'Length <= Max_Input);
      pragma Assert (Right'Length <= Max_Input);
      pragma Assert (Left'Length <= Fixed.Max_Input);
      pragma Assert (Right'Length <= Fixed.Max_Input);
      pragma Assert
        (Payload.Data_Bits
           (Literal_Lengths, Distances, Left, 0) = 0);
      pragma Assert
        (Payload.Data_Bits
           (Literal_Lengths, Distances, Right, 0) = 0);
      Lemma_Payload_Functional
        (Input, Header_Bit_Count, Literal_Lengths, Distances,
         Left, Right, 0);
   end Lemma_Encoding_Functional;

end Inflate.Dynamic;
