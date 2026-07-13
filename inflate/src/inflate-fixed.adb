package body Inflate.Fixed with SPARK_Mode => On is

   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   use Interfaces;

   ------------------------
   -- Long_Literal_Count --
   ------------------------

   function Long_Literal_Count
     (Data : Byte_Array; Count : Natural) return Natural
   is
      Result : Natural := 0;
   begin
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant (Result <= I);
         pragma Loop_Invariant (Data_Bits (Data, I) = 8 * I + Result);
         if Data (Data'First + I) > 143 then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Long_Literal_Count;

   ------------------
   -- Prefix_Value --
   ------------------

   function Prefix_Value
     (Input : Byte_Array;
      Start : Natural;
      Length : Natural) return Natural
   is
   begin
      if Length = 0 then
         return 0;
      else
         return 2 * Prefix_Value (Input, Start, Length - 1)
           + Bit_Value (Input, Start + Length - 1);
      end if;
   end Prefix_Value;

   -----------------
   -- Next_Symbol --
   -----------------

   function Next_Symbol
     (Input : Byte_Array; Position : Natural) return Symbol_Result
   is
      Total : constant Natural := 8 * Input'Length;
      C     : Natural;
   begin
      if Total - Position < 7 then
         return (Truncated, 0, Position);
      end if;

      C := Prefix_Value (Input, Position, 7);
      if C <= 23 then
         if C = 0 then
            pragma Assert (Prefix_Value (Input, Position, 7) = 0);
            return (End_Of_Block, 0, Position + 7);
         else
            return (Other, 0, Position + 7);
         end if;
      end if;

      if Total - Position < 8 then
         return (Truncated, 0, Position);
      end if;
      C := Prefix_Value (Input, Position, 8);
      if C in 48 .. 191 then
         pragma Assert (Code_Length (Byte (C - 48)) = 8);
         pragma Assert (Code (Byte (C - 48)) = C);
         return (Literal, Byte (C - 48), Position + 8);
      elsif C in 192 .. 199 then
         return (Other, 0, Position + 8);
      end if;

      if Total - Position < 9 then
         return (Truncated, 0, Position);
      end if;
      C := Prefix_Value (Input, Position, 9);
      if C in 400 .. 511 then
         pragma Assert (Code_Length (Byte (C - 256)) = 9);
         pragma Assert (Code (Byte (C - 256)) = C);
         return (Literal, Byte (C - 256), Position + 9);
      else
         return (Other, 0, Position + 9);
      end if;
   end Next_Symbol;

   ----------
   -- Walk --
   ----------

   function Spec_Walk
     (Input : Byte_Array; Position : Natural) return Stream_Info
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      case S.Kind is
         when Literal =>
            declare
               Tail : constant Stream_Info := Spec_Walk (Input, S.Position);
            begin
               if Tail.Valid then
                  return (True, Tail.End_Bit, Tail.Decoded_Length + 1);
               else
                  return (False, 0, 0);
               end if;
            end;
         when End_Of_Block =>
            return (True, S.Position, 0);
         when Other | Truncated =>
            return (False, 0, 0);
      end case;
   end Spec_Walk;

   function Walk (Input : Byte_Array; Position : Natural) return Stream_Info is
      Start : constant Natural := Position;
      P     : Natural := Position;
      Count : Natural := 0;
      S     : Symbol_Result;
   begin
      loop
         pragma Loop_Invariant (P in Start .. 8 * Input'Length);
         pragma Loop_Invariant (Count <= (P - Start) / 8);
         pragma Loop_Invariant
           (if Spec_Walk (Input, P).Valid
            then Spec_Walk (Input, Start).Valid
                 and then Spec_Walk (Input, Start).End_Bit =
                            Spec_Walk (Input, P).End_Bit
                 and then Spec_Walk (Input, Start).Decoded_Length =
                            Count + Spec_Walk (Input, P).Decoded_Length
            else not Spec_Walk (Input, Start).Valid);
         pragma Loop_Variant (Increases => P);

         S := Next_Symbol (Input, P);
         case S.Kind is
            when Literal =>
               P := S.Position;
               Count := Count + 1;
            when End_Of_Block =>
               return (True, S.Position, Count);
            when Other | Truncated =>
               return (False, 0, 0);
         end case;
      end loop;
   end Walk;

   -------------
   -- Analyze --
   -------------

   function Analyze (Input : Byte_Array) return Stream_Info is
      Result : Stream_Info;
   begin
      if not Fixed_Header (Input) then
         return (False, 0, 0);
      end if;
      Result := Walk (Input, 3);
      if Result.Valid and then Result.Decoded_Length <= Max_Input then
         return Result;
      else
         return (False, 0, 0);
      end if;
   end Analyze;

   -------------------------------
   -- Lemma_Encoding_Analyzes --
   -------------------------------

   procedure Lemma_Prefix_Step
     (Input : Byte_Array; Start : Natural; Length : Positive)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Length <= 9
               and then Start <= 8 * Input'Length
               and then Length <= 8 * Input'Length - Start,
     Post => Prefix_Value (Input, Start, Length) =
               2 * Prefix_Value (Input, Start, Length - 1)
                 + Bit_Value (Input, Start + Length - 1);

   procedure Lemma_Half (Whole, Prefix, Bit : Natural)
   with
     Ghost,
     Pre  => Prefix <= 511
               and then Bit <= 1 and then Whole = 2 * Prefix + Bit,
     Post => Prefix = Whole / 2;

   procedure Lemma_Half (Whole, Prefix, Bit : Natural) is null;

   procedure Lemma_Code_Decodes
     (Input : Byte_Array; Position : Natural; B : Byte)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Position <= 8 * Input'Length
               and then Code_Length (B) <= 8 * Input'Length - Position
               and then Prefix_Value
                          (Input, Position, Code_Length (B)) = Code (B),
     Post => Next_Symbol (Input, Position).Kind = Literal
               and then Next_Symbol (Input, Position).Value = B
               and then Next_Symbol (Input, Position).Position =
                          Position + Code_Length (B);

   procedure Lemma_Code_Decodes
     (Input : Byte_Array; Position : Natural; B : Byte)
   is
   begin
      if B <= 143 then
         Lemma_Prefix_Step (Input, Position, 8);
         Lemma_Half
           (Code (B), Prefix_Value (Input, Position, 7),
            Bit_Value (Input, Position + 7));
         pragma Assert
           (Prefix_Value (Input, Position, 7) = Code (B) / 2);
         pragma Assert (Prefix_Value (Input, Position, 7) >= 24);
      else
         Lemma_Prefix_Step (Input, Position, 9);
         Lemma_Half
           (Code (B), Prefix_Value (Input, Position, 8),
            Bit_Value (Input, Position + 8));
         pragma Assert
           (Prefix_Value (Input, Position, 8) = Code (B) / 2);
         Lemma_Prefix_Step (Input, Position, 8);
         Lemma_Half
           (Prefix_Value (Input, Position, 8),
            Prefix_Value (Input, Position, 7),
            Bit_Value (Input, Position + 7));
         pragma Assert
           (Prefix_Value (Input, Position, 7) =
              Prefix_Value (Input, Position, 8) / 2);
         pragma Assert (Prefix_Value (Input, Position, 7) >= 100);
      end if;
   end Lemma_Code_Decodes;

   procedure Lemma_EOB_Decodes
     (Input : Byte_Array; Position : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Position <= 8 * Input'Length
               and then 7 <= 8 * Input'Length - Position
               and then Prefix_Value (Input, Position, 7) = 0,
     Post => Next_Symbol (Input, Position).Kind = End_Of_Block
               and then Next_Symbol (Input, Position).Position = Position + 7;

   procedure Lemma_EOB_Decodes
     (Input : Byte_Array; Position : Natural)
   is
   begin
      pragma Assert (Prefix_Value (Input, Position, 7) = 0);
   end Lemma_EOB_Decodes;

   procedure Lemma_Walk_Encoding
     (Input : Byte_Array;
      Data  : Byte_Array;
      Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Index <= Data'Length
               and then 3 + Data_Bits (Data, Index) <= 8 * Input'Length
               and then Encodes_Prefix (Input, Data, Data'Length)
               and then 3 + Data_Bits (Data, Data'Length) + 7 <=
                          8 * Input'Length
               and then Prefix_Value
                          (Input, 3 + Data_Bits (Data, Data'Length), 7) = 0,
     Post => Walk (Input, 3 + Data_Bits (Data, Index)).Valid
               and then Walk (Input, 3 + Data_Bits (Data, Index)).End_Bit =
                          3 + Data_Bits (Data, Data'Length) + 7
               and then Walk
                          (Input, 3 + Data_Bits (Data, Index)).Decoded_Length =
                            Data'Length - Index,
     Subprogram_Variant => (Decreases => Data'Length - Index);

   procedure Lemma_Walk_Encoding
     (Input : Byte_Array;
      Data  : Byte_Array;
      Index : Natural)
   is
      Position : constant Natural := 3 + Data_Bits (Data, Index);
   begin
      if Index < Data'Length then
         pragma Assert
           (3 + Data_Bits (Data, Index)
              + Code_Length (Data (Data'First + Index)) <=
            8 * Input'Length);
         pragma Assert
           (Prefix_Value
              (Input, Position,
               Code_Length (Data (Data'First + Index))) =
            Code (Data (Data'First + Index)));
         Lemma_Code_Decodes
           (Input, Position, Data (Data'First + Index));
         pragma Assert
           (3 + Data_Bits (Data, Index + 1) <= 8 * Input'Length);
         Lemma_Walk_Encoding (Input, Data, Index + 1);
      else
         Lemma_EOB_Decodes (Input, Position);
      end if;
   end Lemma_Walk_Encoding;

   procedure Lemma_Encoding_Analyzes
     (Input : Byte_Array; Consumed : Natural; Data : Byte_Array)
   is
      pragma Unreferenced (Consumed);
   begin
      Lemma_Walk_Encoding (Input, Data, 0);
   end Lemma_Encoding_Analyzes;

   -----------------
   -- Set_Stream_Bit --
   -----------------

   procedure Set_Stream_Bit
     (Output   : in out Byte_Array;
      Position : Natural;
      Value    : Natural)
   with
     Pre  => Output'Length <= Max_Stream_Bytes
               and then Position < 8 * Output'Length and then Value <= 1,
     Post => Bit_Value (Output, Position) = Value
               and then
             (for all P in 0 .. 8 * Output'Length - 1 =>
                (if P /= Position
                 then Bit_Value (Output, P) = Bit_Value (Output'Old, P)))
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

   procedure Lemma_Prefix_Step
     (Input : Byte_Array; Start : Natural; Length : Positive) is null;

   procedure Lemma_Prefix_Frame
     (Before, After : Byte_Array;
      Start         : Natural;
      Length        : Natural)
   with
     Ghost,
     Pre  => Before'Length <= Max_Stream_Bytes
               and then After'Length <= Max_Stream_Bytes
               and then Length <= 9
               and then Start <= 8 * Before'Length
               and then Length <= 8 * Before'Length - Start
               and then Start <= 8 * After'Length
               and then Length <= 8 * After'Length - Start
               and then
             (for all P in Start .. Start + Length - 1 =>
                Bit_Value (After, P) = Bit_Value (Before, P)),
     Post => Prefix_Value (After, Start, Length) =
               Prefix_Value (Before, Start, Length),
     Subprogram_Variant => (Decreases => Length);

   procedure Lemma_Prefix_Frame
     (Before, After : Byte_Array;
      Start         : Natural;
      Length        : Natural)
   is
   begin
      if Length > 0 then
         Lemma_Prefix_Frame (Before, After, Start, Length - 1);
      end if;
   end Lemma_Prefix_Frame;

   procedure Lemma_Byte_Frame
     (Before, After : Byte_Array; Consumed, Position : Natural)
   with
     Ghost,
     Pre  => Before'Length <= Max_Stream_Bytes
               and then After'Length <= Max_Stream_Bytes
               and then Consumed <= Before'Length
               and then Consumed <= After'Length
               and then Position < 8 * Consumed
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Bit_Value (After, Position) = Bit_Value (Before, Position);

   procedure Lemma_Byte_Frame
     (Before, After : Byte_Array; Consumed, Position : Natural) is null;

   procedure Lemma_Byte_Prefix_Frame
     (Before, After : Byte_Array;
      Consumed, Start, Length : Natural)
   with
     Ghost,
     Pre  => Before'Length <= Max_Stream_Bytes
               and then After'Length <= Max_Stream_Bytes
               and then Consumed <= Before'Length
               and then Consumed <= After'Length
               and then Start <= 8 * Consumed
               and then Length <= 8 * Consumed - Start
               and then Length <= 9
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Prefix_Value (After, Start, Length) =
               Prefix_Value (Before, Start, Length),
     Subprogram_Variant => (Decreases => Length);

   procedure Lemma_Byte_Prefix_Frame
     (Before, After : Byte_Array;
      Consumed, Start, Length : Natural)
   is
   begin
      if Length > 0 then
         Lemma_Byte_Prefix_Frame
           (Before, After, Consumed, Start, Length - 1);
         Lemma_Byte_Frame
           (Before, After, Consumed, Start + Length - 1);
      end if;
   end Lemma_Byte_Prefix_Frame;

   procedure Lemma_Data_Bits_Segment
     (Data : Byte_Array; Position, Count : Natural)
   with
     Ghost,
     Pre  => Data'Length <= Max_Input
               and then Position < Count
               and then Count <= Data'Length,
     Post => Data_Bits (Data, Position)
               + Code_Length (Data (Data'First + Position)) <=
             Data_Bits (Data, Count),
     Subprogram_Variant => (Decreases => Count - Position);

   ----------------------
   -- Encoding_Matches --
   ----------------------

   function Encoding_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array) return Boolean
   is
      Position : Natural := 3;
      S        : Symbol_Result;
   begin
      for I in 0 .. Data'Length - 1 loop
         pragma Loop_Invariant
           (Position = 3 + Data_Bits (Data, I));
         pragma Loop_Invariant (Encodes_Prefix (Input, Data, I));

         S := Next_Symbol (Input, Position);
         if S.Kind /= Literal
           or else S.Value /= Data (Data'First + I)
         then
            declare
               procedure Prove_Mismatch with Ghost;

               procedure Prove_Mismatch is
               begin
                  if 3 + Data_Bits (Data, Data'Length) + 7 <=
                       8 * Input'Length
                    and then Encodes_Prefix (Input, Data, Data'Length)
                  then
                     Lemma_Data_Bits_Segment (Data, I, Data'Length);
                     Lemma_Code_Decodes
                       (Input, Position, Data (Data'First + I));
                     pragma Assert (S.Kind = Literal);
                     pragma Assert (S.Value = Data (Data'First + I));
                  end if;
               end Prove_Mismatch;
            begin
               Prove_Mismatch;
               return False;
            end;
         end if;

         pragma Assert
           (Prefix_Value
              (Input, Position,
               Code_Length (Data (Data'First + I))) =
            Code (Data (Data'First + I)));
         Position := S.Position;
      end loop;

      pragma Assert
        (Position = 3 + Data_Bits (Data, Data'Length));
      S := Next_Symbol (Input, Position);
      if S.Kind /= End_Of_Block then
         return False;
      end if;

      return Consumed = (S.Position + 7) / 8;
   end Encoding_Matches;

   procedure Lemma_Encoding_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Consumed in 1 .. Input'Length
               and then Fixed_Header (Input)
               and then 3 + Data_Bits (Data, Data'Length) + 7 <=
                          8 * Input'Length
               and then Encodes_Prefix (Input, Data, Data'Length)
               and then Prefix_Value
                 (Input, 3 + Data_Bits (Data, Data'Length), 7) = 0
               and then Consumed =
                 (3 + Data_Bits (Data, Data'Length) + 7 + 7) / 8,
     Post => Encoding_Matches (Input, Consumed, Data);

   procedure Lemma_Encoding_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array) is null;

   procedure Lemma_Encoding_Frame
     (Before, After : Byte_Array; Consumed : Natural; Data : Byte_Array)
   is
   begin
      pragma Assert (Before (Before'First) = After (After'First));
      pragma Assert (Fixed_Header (After));
      for I in 0 .. Data'Length - 1 loop
         pragma Loop_Invariant (Encodes_Prefix (After, Data, I));
         Lemma_Data_Bits_Segment (Data, I, Data'Length);
         Lemma_Byte_Prefix_Frame
           (Before, After, Consumed, 3 + Data_Bits (Data, I),
            Code_Length (Data (Data'First + I)));
      end loop;
      Lemma_Byte_Prefix_Frame
        (Before, After, Consumed,
         3 + Data_Bits (Data, Data'Length), 7);
      pragma Assert
        (3 + Data_Bits (Data, Data'Length) + 7 <= 8 * After'Length);
      pragma Assert (Encodes_Prefix (After, Data, Data'Length));
      pragma Assert
        (Prefix_Value
           (After, 3 + Data_Bits (Data, Data'Length), 7) = 0);
      pragma Assert
        (Consumed =
           (3 + Data_Bits (Data, Data'Length) + 7 + 7) / 8);
      pragma Assert (Encoding_Matches (After, Consumed, Data));
   end Lemma_Encoding_Frame;

   procedure Lemma_Zero_Prefix
     (Input : Byte_Array; Start : Natural; Length : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Length <= 9
               and then Start <= 8 * Input'Length
               and then Length <= 8 * Input'Length - Start
               and then
             (for all P in Start .. Start + Length - 1 =>
                Bit_Value (Input, P) = 0),
     Post => Prefix_Value (Input, Start, Length) = 0,
     Subprogram_Variant => (Decreases => Length);

   procedure Lemma_Zero_Prefix
     (Input : Byte_Array; Start : Natural; Length : Natural)
   is
   begin
      if Length > 0 then
         Lemma_Zero_Prefix (Input, Start, Length - 1);
      end if;
   end Lemma_Zero_Prefix;

   procedure Lemma_Data_Bits_Segment
     (Data : Byte_Array; Position, Count : Natural)
   is
   begin
      if Position + 1 < Count then
         Lemma_Data_Bits_Segment (Data, Position, Count - 1);
      end if;
   end Lemma_Data_Bits_Segment;

   procedure Lemma_Data_Bits_Frame
     (Before, After : Byte_Array; Count : Natural)
   with
     Ghost,
     Pre  => Before'Length = After'Length
               and then Before'Length <= Max_Input
               and then Count <= Before'Length
               and then
             (for all I in 0 .. Count - 1 =>
                Before (Before'First + I) = After (After'First + I)),
     Post => Data_Bits (Before, Count) = Data_Bits (After, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Data_Bits_Frame
     (Before, After : Byte_Array; Count : Natural)
   is
   begin
      if Count > 0 then
         Lemma_Data_Bits_Frame (Before, After, Count - 1);
      end if;
   end Lemma_Data_Bits_Frame;

   procedure Lemma_Encoding_Functional
     (Input : Byte_Array; Consumed : Natural; Left, Right : Byte_Array)
   is
   begin
      Lemma_Encoding_Analyzes (Input, Consumed, Left);
      Lemma_Encoding_Analyzes (Input, Consumed, Right);
      pragma Assert (Left'Length = Right'Length);
      for I in 0 .. Left'Length - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              Left (Left'First + J) = Right (Right'First + J));
         Lemma_Data_Bits_Frame (Left, Right, I);
         declare
            Position : constant Natural := 3 + Data_Bits (Left, I);
         begin
            pragma Assert
              (Position + Code_Length (Left (Left'First + I)) <=
               8 * Input'Length);
            pragma Assert
              (3 + Data_Bits (Right, I)
                 + Code_Length (Right (Right'First + I)) <=
               8 * Input'Length);
            Lemma_Code_Decodes
              (Input, Position, Left (Left'First + I));
            Lemma_Code_Decodes
              (Input, Position, Right (Right'First + I));
            pragma Assert
              (Next_Symbol (Input, Position).Value = Left (Left'First + I));
            pragma Assert
              (Next_Symbol (Input, Position).Value = Right (Right'First + I));
         end;
      end loop;
   end Lemma_Encoding_Functional;

   procedure Lemma_Encoding_Prefix_Frame
     (Input : Byte_Array; Before, After : Byte_Array; Count : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Before'Length = After'Length
               and then Before'Length <= Max_Input
               and then Count <= Before'Length
               and then 3 + Data_Bits (Before, Count) <= 8 * Input'Length
               and then Encodes_Prefix (Input, Before, Count)
               and then
             (for all I in 0 .. Count - 1 =>
                Before (Before'First + I) = After (After'First + I)),
     Post => Data_Bits (Before, Count) = Data_Bits (After, Count)
               and then Encodes_Prefix (Input, After, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Encoding_Prefix_Frame
     (Input : Byte_Array; Before, After : Byte_Array; Count : Natural)
   is
   begin
      if Count > 0 then
         Lemma_Encoding_Prefix_Frame (Input, Before, After, Count - 1);
         pragma Assert
           (Prefix_Value
              (Input, 3 + Data_Bits (Before, Count - 1),
               Code_Length (Before (Before'First + Count - 1))) =
            Code (Before (Before'First + Count - 1)));
         pragma Assert
           (Before (Before'First + Count - 1) =
              After (After'First + Count - 1));
      end if;
      Lemma_Data_Bits_Frame (Before, After, Count);
   end Lemma_Encoding_Prefix_Frame;

   ----------------
   -- Write_Code --
   ----------------

   procedure Write_Code
     (Output : in out Byte_Array;
      Start  : Natural;
      Length : Positive;
      Value  : Natural)
   with
     Pre  => Output'Length <= Max_Stream_Bytes
               and then Length <= 9
               and then Start <= 8 * Output'Length
               and then Length <= 8 * Output'Length - Start
               and then Value < 2 ** Length,
     Post => Prefix_Value (Output, Start, Length) = Value
               and then
             (for all P in 0 .. 8 * Output'Length - 1 =>
                (if P < Start or else P >= Start + Length
                 then Bit_Value (Output, P) = Bit_Value (Output'Old, P))),
     Subprogram_Variant => (Decreases => Length)
   is
   begin
      if Length = 1 then
         Set_Stream_Bit (Output, Start, Value);
      else
         Write_Code (Output, Start, Length - 1, Value / 2);
         declare
            Before : constant Byte_Array := Output with Ghost;
         begin
            Set_Stream_Bit (Output, Start + Length - 1, Value mod 2);
            pragma Assert
              (for all P in Start .. Start + Length - 2 =>
                 Bit_Value (Output, P) = Bit_Value (Before, P));
            Lemma_Prefix_Frame (Before, Output, Start, Length - 1);
            Lemma_Prefix_Step (Output, Start, Length);
            pragma Assert (2 * (Value / 2) + Value mod 2 = Value);
         end;
      end if;
   end Write_Code;

   --------------
   -- Compress --
   --------------

   procedure Compress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural)
   is
      Size : constant Positive := Encoded_Size (Input);
      Bits : Natural := 3;
      Written : Natural := 0 with Ghost;
   begin
      Output (Output'First .. Output'First + Size - 1) := (others => 0);
      Set_Stream_Bit (Output, 0, 1);
      Set_Stream_Bit (Output, 1, 1);
      pragma Assert (Bit_Value (Output, 2) = 0);
      pragma Assert (Fixed_Header (Output));

      for I in 0 .. Input'Length - 1 loop
         pragma Loop_Invariant (Written = I);
         pragma Loop_Invariant (Bits = 3 + Data_Bits (Input, I));
         pragma Loop_Invariant
           (3 + Data_Bits (Input, Input'Length) + 7 <=
            8 * Output'Length);
         pragma Loop_Invariant (Encodes_Prefix (Output, Input, Written));
         pragma Loop_Invariant (Fixed_Header (Output));
         pragma Loop_Invariant
           (for all P in Bits .. 3 + Data_Bits (Input, Input'Length) + 6 =>
              Bit_Value (Output, P) = 0);
         declare
            B      : constant Byte := Input (Input'First + I);
            Before : constant Byte_Array := Output with Ghost;

            procedure Preserve_Previous_Codes with Ghost;

            procedure Preserve_Previous_Codes is
            begin
               --  Earlier codes occupy disjoint bit intervals and therefore
               --  survive this write (the same framing argument as M3).
               for J in 0 .. I - 1 loop
                  pragma Loop_Invariant
                    (Encodes_Prefix (Output, Input, J));
                  Lemma_Data_Bits_Segment (Input, J, I);
                  pragma Assert
                    (for all P in
                       3 + Data_Bits (Input, J) ..
                       3 + Data_Bits (Input, J)
                         + Code_Length (Input (Input'First + J)) - 1 =>
                       Bit_Value (Output, P) = Bit_Value (Before, P));
                  Lemma_Prefix_Frame
                    (Before, Output, 3 + Data_Bits (Input, J),
                     Code_Length (Input (Input'First + J)));
               end loop;
            end Preserve_Previous_Codes;
         begin
            Lemma_Data_Bits_Segment (Input, I, Input'Length);
            Write_Code (Output, Bits, Code_Length (B), Code (B));
            Preserve_Previous_Codes;
            pragma Assert (Encodes_Prefix (Output, Input, I));
            pragma Assert
              (Prefix_Value
                 (Output, 3 + Data_Bits (Input, I), Code_Length (B)) =
               Code (B));
            pragma Assert (Encodes_Prefix (Output, Input, I + 1));
            Bits := Bits + Code_Length (B);
            Written := Written + 1;
         end;
      end loop;
      pragma Assert (Written = Input'Length);
      pragma Assert (Encodes_Prefix (Output, Input, Written));

      --  The fixed end-of-block code is seven zero bits; the output was
      --  zero-initialized and no literal write reaches this interval.
      pragma Assert (Bits = 3 + Data_Bits (Input, Input'Length));
      pragma Assert
        (for all P in Bits .. Bits + 6 => Bit_Value (Output, P) = 0);
      Lemma_Zero_Prefix (Output, Bits, 7);
      Produced := Size;
      pragma Assert (Fixed_Header (Output));
      pragma Assert
        (Prefix_Value
           (Output, 3 + Data_Bits (Input, Input'Length), 7) = 0);
      pragma Assert
        (Produced =
           (3 + Data_Bits (Input, Input'Length) + 7 + 7) / 8);
      pragma Assert (Encoding_Matches (Output, Produced, Input));
   end Compress;

   ----------------
   -- Decompress --
   ----------------

   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Success  :    out Boolean)
   is
      Info     : constant Stream_Info := Analyze (Input);
      Position : Natural := 3;
      Count    : Natural := 0;
      S        : Symbol_Result;
   begin
      Consumed := 0;
      Produced := 0;
      Success  := False;
      if not Info.Valid or else Info.Decoded_Length > Output'Length then
         return;
      end if;
      declare
         Data : Byte_Array renames
           Output (Output'First .. Output'First - 1 + Info.Decoded_Length);
      begin
         loop
            pragma Loop_Invariant (Position in 3 .. Info.End_Bit);
            pragma Loop_Invariant (Count <= Info.Decoded_Length);
            pragma Loop_Invariant (Walk (Input, Position).Valid);
            pragma Loop_Invariant
              (Walk (Input, Position).End_Bit = Info.End_Bit);
            pragma Loop_Invariant
              (Count + Walk (Input, Position).Decoded_Length =
                 Info.Decoded_Length);
            pragma Loop_Invariant
              (Position = 3 + Data_Bits (Data, Count));
            pragma Loop_Invariant (Encodes_Prefix (Input, Data, Count));
            pragma Loop_Variant (Increases => Position);
            S := Next_Symbol (Input, Position);
            case S.Kind is
               when Literal =>
                  pragma Assert (Count < Info.Decoded_Length);
                  declare
                     Before : constant Byte_Array := Data with Ghost;
                  begin
                     Data (Data'First + Count) := S.Value;
                     pragma Assert
                       (for all I in 0 .. Count - 1 =>
                          Before (Before'First + I) =
                            Data (Data'First + I));
                     Lemma_Encoding_Prefix_Frame
                       (Input, Before, Data, Count);
                     pragma Assert
                       (Prefix_Value
                          (Input, Position, Code_Length (S.Value)) =
                            Code (S.Value));
                     pragma Assert
                       (Data (Data'First + Count) = S.Value);
                     pragma Assert
                       (Data_Bits (Data, Count + 1) =
                          Data_Bits (Data, Count)
                            + Code_Length (Data (Data'First + Count)));
                     pragma Assert
                       (Data_Bits (Data, Count + 1) =
                          Data_Bits (Data, Count) + Code_Length (S.Value));
                     pragma Assert
                       (S.Position = Position + Code_Length (S.Value));
                     Position := S.Position;
                     Count := Count + 1;
                  end;
               when End_Of_Block =>
                  pragma Assert (Count = Info.Decoded_Length);
                  pragma Assert (S.Position = Info.End_Bit);
                  pragma Assert (Data'Length <= Max_Input);
                  pragma Assert (Fixed_Header (Input));
                  pragma Assert
                    (3 + Data_Bits (Data, Data'Length) + 7 <=
                     8 * Input'Length);
                  pragma Assert (Encodes_Prefix (Input, Data, Data'Length));
                  pragma Assert
                    (Prefix_Value
                       (Input, 3 + Data_Bits (Data, Data'Length), 7) = 0);
                  pragma Assert
                    ((S.Position + 7) / 8 =
                       (3 + Data_Bits (Data, Data'Length) + 7 + 7) / 8);
                  pragma Assert
                    ((S.Position + 7) / 8 in 1 .. Input'Length);
                  Lemma_Encoding_Matches
                    (Input,
                     (3 + Data_Bits (Data, Data'Length) + 7 + 7) / 8,
                     Data);
                  Consumed := (S.Position + 7) / 8;
                  Produced := Count;
                  Success := True;
                  return;
               when Other | Truncated =>
                  pragma Assert (False);
            end case;
         end loop;
      end;
   end Decompress;

end Inflate.Fixed;
