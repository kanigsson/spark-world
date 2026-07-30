with Inflate.Codebooks;
with Inflate.Payload;

package body Inflate.Fixed with SPARK_Mode => On is

   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   ---------------------
   -- Matching_Length --
   ---------------------

   function Matching_Length
     (Data : Byte_Array; Position, Distance : Natural) return Natural
   with
     Pre  => Data'Length <= Max_Input
               and then Position < Data'Length
               and then Distance in 1 .. 4
               and then Distance <= Position,
     Post => Matching_Length'Result <= 10
               and then Matching_Length'Result <= Data'Length - Position
               and then
             (for all K in 0 .. Matching_Length'Result - 1 =>
                Data (Data'First + Position + K) =
                  Data (Data'First + Position + K - Distance));

   function Matching_Length
     (Data : Byte_Array; Position, Distance : Natural) return Natural
   is
      Result : Natural := 0;
   begin
      while Result < 10
        and then Result < Data'Length - Position
        and then Data (Data'First + Position + Result) =
          Data (Data'First + Position + Result - Distance)
      loop
         pragma Loop_Invariant (Result <= 10);
         pragma Loop_Invariant (Result <= Data'Length - Position);
         pragma Loop_Invariant
           (for all K in 0 .. Result - 1 =>
              Data (Data'First + Position + K) =
                Data (Data'First + Position + K - Distance));
         pragma Loop_Variant (Increases => Result);
         Result := Result + 1;
      end loop;
      return Result;
   end Matching_Length;

   --------------------
   -- Selected_Token --
   --------------------

   function Selected_Token
     (Data : Byte_Array; Position : Natural) return Symbol_Result
   is
      Best_Length   : Natural := 0;
      Best_Distance : Natural := 0;
   begin
      for Distance in 1 .. 4 loop
         pragma Loop_Invariant (Best_Length <= 10);
         pragma Loop_Invariant (Best_Length <= Data'Length - Position);
         pragma Loop_Invariant
           (if Best_Length >= 3
            then Best_Distance in 1 .. 4
                 and then Best_Distance <= Position
                 and then Match_Applies
                   (Data, Position, Best_Length, Best_Distance));
         if Distance <= Position then
            declare
               Length : constant Natural :=
                 Matching_Length (Data, Position, Distance);
            begin
               if Length >= 3 and then Length > Best_Length then
                  Best_Length := Length;
                  Best_Distance := Distance;
               end if;
            end;
         end if;
      end loop;

      if Best_Length >= 3 then
         return
           (Match, 0, Best_Length, Best_Distance, Position + Best_Length);
      else
         return
           (Literal, Data (Data'First + Position), 1, 0, Position + 1);
      end if;
   end Selected_Token;

   -----------------------
   -- Encoded_Bit_Count --
   -----------------------

   function Encoded_Bit_Count (Data : Byte_Array) return Natural is
      Result : Natural := 0;
      Index  : Natural := 0;
   begin
      while Index < Data'Length loop
         pragma Loop_Invariant (Index <= Data'Length);
         pragma Loop_Invariant (Result = Data_Bits (Data, Index));
         pragma Loop_Invariant (Result <= 9 * Index);
         pragma Loop_Invariant (Token_Boundary (Data, Index));
         pragma Loop_Variant (Decreases => Data'Length - Index);
         declare
            Next : constant Natural := Next_Position (Data, Index);
         begin
            Lemma_Encoding_Next (Data, Index);
            Result := Result + Token_Bit_Cost (Data, Index);
            Index := Next;
         end;
      end loop;
      return Result;
   end Encoded_Bit_Count;

   ------------------
   -- Prefix_Value --
   ------------------

   function Prefix_Value
     (Input : Byte_Array;
      Start : Natural;
      Length : Natural) return Natural
   is
   begin
      --  The bound this function states is the bound Ore states on its field,
      --  in the same arithmetic: nothing has to be carried across the word
      --  type to get it.
      if Length = 0 then
         return 0;
      end if;

      declare
         Prefix : constant Natural := Prefix_Value (Input, Start, Length - 1);
      begin
         --  The recursion is the value the encoders' contracts are written
         --  in; Ore's is the same equation about its own field. Taking both
         --  steps here is what proves the two are one function, and it is the
         --  step no client can take from a bit-wise specification alone.
         Bit_Cursors.Lemma_Field_Value_Recursion
           (Input, Start, Length,
            Bit_Cursors.Lsb_First, Bit_Cursors.High_Bit_First);

         return Prefix * 2 + Bit_Value (Input, Start + Length - 1);
      end;
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
         return (Truncated, 0, 0, 0, Position);
      end if;

      C := Prefix_Value (Input, Position, 7);
      if C <= 23 then
         if C = 0 then
            pragma Assert (Prefix_Value (Input, Position, 7) = 0);
            return (End_Of_Block, 0, 0, 0, Position + 7);
         elsif C in 1 .. 8 then
            if Total - Position < 12 then
               return (Truncated, 0, 0, 0, Position);
            elsif Prefix_Value (Input, Position + 7, 5) <= 3 then
               return
                 (Match, 0, C + 2,
                  Prefix_Value (Input, Position + 7, 5) + 1,
                  Position + 12);
            else
               return (Other, 0, 0, 0, Position + 12);
            end if;
         else
            return (Other, 0, 0, 0, Position + 7);
         end if;
      end if;

      if Total - Position < 8 then
         return (Truncated, 0, 0, 0, Position);
      end if;
      C := Prefix_Value (Input, Position, 8);
      if C in 48 .. 191 then
         pragma Assert (Code_Length (Byte (C - 48)) = 8);
         pragma Assert (Code (Byte (C - 48)) = C);
         return (Literal, Byte (C - 48), 1, 0, Position + 8);
      elsif C in 192 .. 199 then
         return (Other, 0, 0, 0, Position + 8);
      end if;

      if Total - Position < 9 then
         return (Truncated, 0, 0, 0, Position);
      end if;
      C := Prefix_Value (Input, Position, 9);
      if C in 400 .. 511 then
         pragma Assert (Code_Length (Byte (C - 256)) = 9);
         pragma Assert (Code (Byte (C - 256)) = C);
         return (Literal, Byte (C - 256), 1, 0, Position + 9);
      else
         return (Other, 0, 0, 0, Position + 9);
      end if;
   end Next_Symbol;

   ----------
   -- Walk --
   ----------

   function Spec_Walk
     (Input : Byte_Array; Position, Decoded : Natural) return Stream_Info
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      case S.Kind is
         when Literal =>
            if Decoded = Max_Input then
               return (False, 0, 0);
            else
               declare
                  Tail : constant Stream_Info :=
                    Spec_Walk (Input, S.Position, Decoded + 1);
               begin
                  if Tail.Valid then
                     return (True, Tail.End_Bit, Tail.Decoded_Length + 1);
                  else
                     return (False, 0, 0);
                  end if;
               end;
            end if;
         when Match =>
            if S.Distance > Decoded
              or else S.Length > Max_Input - Decoded
            then
               return (False, 0, 0);
            else
               declare
                  Tail : constant Stream_Info :=
                    Spec_Walk (Input, S.Position, Decoded + S.Length);
               begin
                  if Tail.Valid then
                     return
                       (True, Tail.End_Bit, Tail.Decoded_Length + S.Length);
                  else
                     return (False, 0, 0);
                  end if;
               end;
            end if;
         when End_Of_Block =>
            return (True, S.Position, 0);
         when Other | Truncated =>
            return (False, 0, 0);
      end case;
   end Spec_Walk;

   function Walk
     (Input : Byte_Array; Position, Decoded : Natural) return Stream_Info
   is
      Start : constant Natural := Position;
      P     : Natural := Position;
      Count : Natural := 0;
      S     : Symbol_Result;
   begin
      loop
         pragma Loop_Invariant (P in Start .. 8 * Input'Length);
         pragma Loop_Invariant (Count <= Max_Input - Decoded);
         pragma Loop_Invariant
           (Spec_Walk (Input, Start, Decoded) =
              (if Spec_Walk (Input, P, Decoded + Count).Valid
               then (True,
                     Spec_Walk (Input, P, Decoded + Count).End_Bit,
                     Count
                       + Spec_Walk (Input, P, Decoded + Count)
                           .Decoded_Length)
               else (False, 0, 0)));
         pragma Loop_Variant (Increases => P);

         S := Next_Symbol (Input, P);
         case S.Kind is
            when Literal =>
               if Decoded + Count = Max_Input then
                  return (False, 0, 0);
               end if;
               P := S.Position;
               Count := Count + 1;
               pragma Assert
                 (Spec_Walk (Input, Start, Decoded) =
                    (if Spec_Walk (Input, P, Decoded + Count).Valid
                     then (True,
                           Spec_Walk (Input, P, Decoded + Count).End_Bit,
                           Count
                             + Spec_Walk (Input, P, Decoded + Count)
                                 .Decoded_Length)
                     else (False, 0, 0)));
            when Match =>
               if S.Distance > Decoded + Count
                 or else S.Length > Max_Input - (Decoded + Count)
               then
                  return (False, 0, 0);
               end if;
               P := S.Position;
               Count := Count + S.Length;
               pragma Assert
                 (Spec_Walk (Input, Start, Decoded) =
                    (if Spec_Walk (Input, P, Decoded + Count).Valid
                     then (True,
                           Spec_Walk (Input, P, Decoded + Count).End_Bit,
                           Count
                             + Spec_Walk (Input, P, Decoded + Count)
                                 .Decoded_Length)
                     else (False, 0, 0)));
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
      Result := Walk (Input, 3, 0);
      if Result.Valid then
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

   procedure Lemma_Match_Decodes
     (Input : Byte_Array; Position, Length, Distance : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Position <= 8 * Input'Length
               and then Length in 3 .. 10
               and then Distance in 1 .. 4
               and then 12 <= 8 * Input'Length - Position
               and then Prefix_Value (Input, Position, 7) = Length - 2
               and then Prefix_Value (Input, Position + 7, 5) = Distance - 1,
     Post => Next_Symbol (Input, Position).Kind = Match
               and then Next_Symbol (Input, Position).Length = Length
               and then Next_Symbol (Input, Position).Distance = Distance
               and then Next_Symbol (Input, Position).Position = Position + 12;

   procedure Lemma_Match_Decodes
     (Input : Byte_Array; Position, Length, Distance : Natural) is null;

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

   procedure Lemma_Matches_Walk
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Consumed in 1 .. Input'Length
               and then Position <= 8 * Consumed
               and then Index <= Data'Length
               and then Spec_Matches
                 (Input, Consumed, Data, Position, Index),
     Post => Walk (Input, Position, Index).Valid
               and then Walk (Input, Position, Index).End_Bit <= 8 * Consumed
               and then (Walk (Input, Position, Index).End_Bit + 7) / 8 =
                          Consumed
               and then Walk (Input, Position, Index).Decoded_Length =
                          Data'Length - Index,
     Subprogram_Variant => (Decreases => 8 * Consumed - Position);

   procedure Lemma_Matches_Walk
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index : Natural)
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      pragma Assert (S.Position <= 8 * Consumed);
      if Index = Data'Length then
         pragma Assert (S.Kind = End_Of_Block);
      elsif S.Kind = Literal then
         Lemma_Matches_Walk
           (Input, Consumed, Data, S.Position, Index + 1);
      else
         pragma Assert (S.Kind = Match);
         pragma Assert (S.Distance <= Index);
         pragma Assert (S.Length <= Data'Length - Index);
         Lemma_Matches_Walk
           (Input, Consumed, Data, S.Position, Index + S.Length);
      end if;
   end Lemma_Matches_Walk;

   procedure Lemma_Encoding_Analyzes
     (Input : Byte_Array; Consumed : Natural; Data : Byte_Array)
   is
   begin
      pragma Assert (Spec_Matches (Input, Consumed, Data, 3, 0));
      Lemma_Matches_Walk (Input, Consumed, Data, 3, 0);
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
   begin
      --  Ore's single-bit store, in the numbering DEFLATE reads its stream
      --  in. Its postcondition is the bit that changed together with the
      --  frame over every other bit position of the array, which is the
      --  frame stated above; the step from the byte written to the bit
      --  positions it moved is made there rather than here.
      Bit_Cursors.Set_Bit
        (Output, Position, Value = 1, Bit_Cursors.Lsb_First);
   end Set_Stream_Bit;

   procedure Lemma_Prefix_Step
     (Input : Byte_Array; Start : Natural; Length : Positive) is null;

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
               and then Count <= Data'Length
               and then Token_Boundary (Data, Position)
               and then Token_Boundary (Data, Count),
     Post => Next_Position (Data, Position) <= Count
               and then Data_Bits (Data, Position)
                 + Token_Bit_Cost (Data, Position) <=
               Data_Bits (Data, Count),
     Subprogram_Variant => (Decreases => Count - Position);

   ----------------------
   -- Encoding_Matches --
   ----------------------

   function Spec_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index : Natural) return Boolean
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      if S.Position > 8 * Consumed then
         return False;
      elsif Index = Data'Length then
         return S.Kind = End_Of_Block
           and then Consumed = (S.Position + 7) / 8;
      else
         case S.Kind is
            when Literal =>
               return S.Value = Data (Data'First + Index)
                 and then Spec_Matches
                   (Input, Consumed, Data, S.Position, Index + 1);
            when Match =>
               return Match_Applies
                 (Data, Index, S.Length, S.Distance)
                 and then Spec_Matches
                   (Input, Consumed, Data,
                    S.Position, Index + S.Length);
            when End_Of_Block | Other | Truncated =>
               return False;
         end case;
      end if;
   end Spec_Matches;

   function Encoding_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array) return Boolean
   is
      Position : Natural := 3;
      Index    : Natural := 0;
      S        : Symbol_Result;
   begin
      while Index < Data'Length loop
         pragma Loop_Invariant (Position <= 8 * Consumed);
         pragma Loop_Invariant (Index <= Data'Length);
         pragma Loop_Invariant
           (Spec_Matches (Input, Consumed, Data, 3, 0) =
              Spec_Matches (Input, Consumed, Data, Position, Index));
         pragma Loop_Variant (Decreases => Data'Length - Index);
         S := Next_Symbol (Input, Position);
         if S.Position > 8 * Consumed then
            return False;
         end if;
         case S.Kind is
            when Literal =>
               if S.Value /= Data (Data'First + Index) then
                  return False;
               end if;
               Position := S.Position;
               Index := Index + 1;
            when Match =>
               if not Match_Applies
                 (Data, Index, S.Length, S.Distance)
               then
                  return False;
               end if;
               Position := S.Position;
               Index := Index + S.Length;
            when End_Of_Block | Other | Truncated =>
               return False;
         end case;
      end loop;

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

   procedure Lemma_Encoding_Next
     (Data : Byte_Array; Index : Natural)
   is
      S : constant Symbol_Result := Selected_Token (Data, Index);
   begin
      for Offset in 1 .. S.Length loop
         if Offset = 1 then
            pragma Assert (Plan_Remaining (Data, Index) = 0);
            pragma Assert (Token_Boundary (Data, Index));
         else
            pragma Assert
              (Plan_Remaining (Data, Index + Offset - 1) =
                 S.Length - Offset + 1);
            pragma Assert
              (Plan_Remaining (Data, Index + Offset - 1) > 0);
         end if;
         pragma Assert
           (Plan_Remaining (Data, Index + Offset) = S.Length - Offset);
         pragma Assert
           (Plan_Start (Data, Index + Offset) = Index);
         if Offset < S.Length then
            pragma Assert
              (not Token_Boundary (Data, Index + Offset));
            pragma Assert
              (Data_Bits (Data, Index + Offset) = Data_Bits (Data, Index));
         else
            pragma Assert
              (Token_Boundary (Data, Index + Offset));
            pragma Assert
              (Data_Bits (Data, Index + Offset) =
                 Data_Bits (Data, Index) + Token_Bit_Cost (Data, Index));
         end if;
         pragma Loop_Invariant
           (Plan_Remaining (Data, Index + Offset) = S.Length - Offset);
         pragma Loop_Invariant
           (Plan_Start (Data, Index + Offset) = Index);
         pragma Loop_Invariant
           (if Offset < S.Length
            then Data_Bits (Data, Index + Offset) = Data_Bits (Data, Index)
            else Data_Bits (Data, Index + Offset) =
              Data_Bits (Data, Index) + Token_Bit_Cost (Data, Index));
         pragma Loop_Invariant
           (for all Count in Index + 1 .. Index + Offset =>
              (if Count < Index + S.Length
               then not Token_Boundary (Data, Count)
                    and then Data_Bits (Data, Count) =
                      Data_Bits (Data, Index)));
      end loop;
      pragma Assert
        (Plan_Start (Data, Next_Position (Data, Index)) = Index);
   end Lemma_Encoding_Next;

   procedure Lemma_Compressor_Spec
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Consumed in 1 .. Input'Length
               and then Index <= Data'Length
               and then Token_Boundary (Data, Index)
               and then Encodes_Prefix (Input, Data, Data'Length)
               and then 3 + Data_Bits (Data, Data'Length) + 7 <=
                          8 * Input'Length
               and then Prefix_Value
                 (Input, 3 + Data_Bits (Data, Data'Length), 7) = 0
               and then Consumed =
                 (3 + Data_Bits (Data, Data'Length) + 7 + 7) / 8,
     Post => Spec_Matches
       (Input, Consumed, Data, 3 + Data_Bits (Data, Index), Index),
     Subprogram_Variant => (Decreases => Data'Length - Index);

   procedure Lemma_Compressor_Spec
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Index : Natural)
   is
      Position : constant Natural := 3 + Data_Bits (Data, Index);
      S        : Symbol_Result;
   begin
      if Index = Data'Length then
         Lemma_EOB_Decodes (Input, Position);
         pragma Assert
           (Spec_Matches (Input, Consumed, Data, Position, Index));
      else
         S := Selected_Token (Data, Index);
         Lemma_Encoding_Next (Data, Index);
         Lemma_Data_Bits_Segment (Data, Index, Data'Length);
         if S.Kind = Match then
            Lemma_Match_Decodes
              (Input, Position, S.Length, S.Distance);
            Lemma_Compressor_Spec
              (Input, Consumed, Data, S.Position);
            pragma Assert
              (Spec_Matches
                 (Input, Consumed, Data, Position + 12, S.Position));
         else
            Lemma_Code_Decodes
              (Input, Position, S.Value);
            Lemma_Compressor_Spec
              (Input, Consumed, Data, S.Position);
            pragma Assert
              (Spec_Matches
                 (Input, Consumed, Data,
                  Position + Code_Length (S.Value), S.Position));
         end if;
      end if;
   end Lemma_Compressor_Spec;

   procedure Lemma_Encoding_Matches
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array)
   is
   begin
      Lemma_Compressor_Spec (Input, Consumed, Data, 0);
      pragma Assert (Spec_Matches (Input, Consumed, Data, 3, 0));
      pragma Assert (Encoding_Matches (Input, Consumed, Data));
   end Lemma_Encoding_Matches;

   procedure Lemma_Next_Frame
     (Before, After : Byte_Array; Consumed, Position : Natural)
   with
     Ghost,
     Pre  => Before'Length <= Max_Stream_Bytes
               and then After'Length <= Max_Stream_Bytes
               and then Consumed <= Before'Length
               and then Consumed <= After'Length
               and then Position <= 8 * Consumed
               and then Next_Symbol (Before, Position).Kind in
                          Literal | Match | End_Of_Block
               and then Next_Symbol (Before, Position).Position <=
                          8 * Consumed
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Next_Symbol (After, Position) =
               Next_Symbol (Before, Position);

   procedure Lemma_Next_Frame
     (Before, After : Byte_Array; Consumed, Position : Natural)
   is
      S : constant Symbol_Result := Next_Symbol (Before, Position);
   begin
      case S.Kind is
         when Literal =>
            Lemma_Byte_Prefix_Frame
              (Before, After, Consumed, Position, Code_Length (S.Value));
            Lemma_Code_Decodes (After, Position, S.Value);
            pragma Assert (Next_Symbol (After, Position) = S);
         when Match =>
            Lemma_Byte_Prefix_Frame
              (Before, After, Consumed, Position, 7);
            Lemma_Byte_Prefix_Frame
              (Before, After, Consumed, Position + 7, 5);
            Lemma_Match_Decodes
              (After, Position, S.Length, S.Distance);
            pragma Assert (Next_Symbol (After, Position) = S);
         when End_Of_Block =>
            Lemma_Byte_Prefix_Frame
              (Before, After, Consumed, Position, 7);
            Lemma_EOB_Decodes (After, Position);
            pragma Assert (Next_Symbol (After, Position) = S);
         when Other | Truncated =>
            pragma Assert (False);
      end case;
   end Lemma_Next_Frame;

   procedure Lemma_Spec_Frame
     (Before, After : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index : Natural)
   with
     Ghost,
     Pre  => Before'Length <= Max_Stream_Bytes
               and then After'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Consumed in 1 .. Before'Length
               and then Consumed <= After'Length
               and then Position <= 8 * Consumed
               and then Index <= Data'Length
               and then Spec_Matches
                 (Before, Consumed, Data, Position, Index)
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Spec_Matches
               (After, Consumed, Data, Position, Index),
     Subprogram_Variant => (Decreases => Data'Length - Index,
                            Decreases => 8 * Consumed - Position);

   procedure Lemma_Spec_Frame
     (Before, After : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index : Natural)
   is
      S : constant Symbol_Result := Next_Symbol (Before, Position);
   begin
      pragma Assert (S.Position <= 8 * Consumed);
      if Index = Data'Length then
         pragma Assert (S.Kind = End_Of_Block);
         Lemma_Next_Frame (Before, After, Consumed, Position);
      else
         pragma Assert (S.Kind in Literal | Match);
         Lemma_Next_Frame (Before, After, Consumed, Position);
         if S.Kind = Literal then
            Lemma_Spec_Frame
              (Before, After, Consumed, Data, S.Position, Index + 1);
         else
            pragma Assert (S.Length <= Data'Length - Index);
            Lemma_Spec_Frame
              (Before, After, Consumed, Data,
               S.Position, Index + S.Length);
         end if;
      end if;
   end Lemma_Spec_Frame;

   procedure Lemma_Encoding_Frame
     (Before, After : Byte_Array; Consumed : Natural; Data : Byte_Array)
   is
   begin
      pragma Assert
        (Spec_Matches (Before, Consumed, Data, 3, 0));
      Lemma_Spec_Frame (Before, After, Consumed, Data, 3, 0);
      pragma Assert
        (Spec_Matches (After, Consumed, Data, 3, 0));
      pragma Assert (Encoding_Matches (After, Consumed, Data));
   end Lemma_Encoding_Frame;

   procedure Lemma_Data_Bits_Segment
     (Data : Byte_Array; Position, Count : Natural)
   is
      Next : constant Natural := Next_Position (Data, Position);
   begin
      pragma Assert (Next <= Count);
      Lemma_Encoding_Next (Data, Position);
      pragma Assert
        (Data_Bits (Data, Next) =
           Data_Bits (Data, Position)
             + Token_Bit_Cost (Data, Position));
      if Next < Count then
         Lemma_Data_Bits_Segment (Data, Next, Count);
      end if;
   end Lemma_Data_Bits_Segment;

   procedure Lemma_Spec_Functional
     (Input : Byte_Array;
      Consumed : Natural;
      Left, Right : Byte_Array;
      Position, Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Left'Length <= Max_Input
               and then Right'Length <= Max_Input
               and then Consumed in 1 .. Input'Length
               and then Position <= 8 * Consumed
               and then Index <= Left'Length
               and then Index <= Right'Length
               and then Spec_Matches
                 (Input, Consumed, Left, Position, Index)
               and then Spec_Matches
                 (Input, Consumed, Right, Position, Index)
               and then
             (for all I in 0 .. Index - 1 =>
                Left (Left'First + I) = Right (Right'First + I)),
     Post => Left'Length = Right'Length
               and then
             (for all I in 0 .. Left'Length - 1 =>
                Left (Left'First + I) = Right (Right'First + I)),
     Subprogram_Variant => (Decreases => 8 * Consumed - Position);

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
     Pre  => Left'Length <= Max_Input
               and then Right'Length <= Max_Input
               and then Length in 3 .. 10
               and then Distance in 1 .. 4
               and then Distance <= Index
               and then Length <= Left'Length - Index
               and then Length <= Right'Length - Index
               and then Match_Applies (Left, Index, Length, Distance)
               and then Match_Applies (Right, Index, Length, Distance)
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

   procedure Lemma_Spec_Functional
     (Input : Byte_Array;
      Consumed : Natural;
      Left, Right : Byte_Array;
      Position, Index : Natural)
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      pragma Assert (S.Position <= 8 * Consumed);
      if Index = Left'Length then
         pragma Assert (S.Kind = End_Of_Block);
         pragma Assert (Index = Right'Length);
      elsif S.Kind = Literal then
         pragma Assert (Index < Right'Length);
         pragma Assert
           (Left (Left'First + Index) = S.Value
              and then Right (Right'First + Index) = S.Value);
         Lemma_Spec_Functional
           (Input, Consumed, Left, Right, S.Position, Index + 1);
      else
         pragma Assert (S.Kind = Match);
         pragma Assert (S.Distance <= Index);
         pragma Assert (S.Length <= Left'Length - Index);
         pragma Assert (S.Length <= Right'Length - Index);
         Lemma_Match_Functional
           (Left, Right, Index, S.Length, S.Distance);
         Lemma_Prefix_Extend_Match (Left, Right, Index, S.Length);
         pragma Assert
           (for all I in 0 .. Index + S.Length - 1 =>
              Left (Left'First + I) = Right (Right'First + I));
         Lemma_Spec_Functional
           (Input, Consumed, Left, Right,
            S.Position, Index + S.Length);
      end if;
   end Lemma_Spec_Functional;

   procedure Lemma_Encoding_Functional
     (Input : Byte_Array; Consumed : Natural; Left, Right : Byte_Array)
   is
   begin
      pragma Assert (Spec_Matches (Input, Consumed, Left, 3, 0));
      pragma Assert (Spec_Matches (Input, Consumed, Right, 3, 0));
      Lemma_Spec_Functional
        (Input, Consumed, Left, Right, 3, 0);
   end Lemma_Encoding_Functional;

   procedure Lemma_Shared_Data_Bits
     (Data : Byte_Array; Count : Natural)
   with
     Ghost,
     Pre  => Data'Length <= Max_Input and then Count <= Data'Length,
     Post => Inflate.Payload.Data_Bits
               (Inflate.Codebooks.Fixed_Literal_Length_Book,
                Inflate.Codebooks.Fixed_Distance_Book,
                Data, Count) = Data_Bits (Data, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Shared_Data_Bits
     (Data : Byte_Array; Count : Natural)
   is
   begin
      if Count > 0 then
         if Token_Boundary (Data, Count) then
            Lemma_Shared_Data_Bits (Data, Plan_Start (Data, Count));
            declare
               Start : constant Natural := Plan_Start (Data, Count);
               Token : constant Symbol_Result := Selected_Token (Data, Start);
            begin
               if Token.Kind = Match then
                  pragma Assert
                    (Inflate.Payload.Token_Bit_Cost
                       (Inflate.Codebooks.Fixed_Literal_Length_Book,
                        Inflate.Codebooks.Fixed_Distance_Book,
                        Data, Start) = 12);
               else
                  pragma Assert
                    (Inflate.Payload.Token_Bit_Cost
                       (Inflate.Codebooks.Fixed_Literal_Length_Book,
                        Inflate.Codebooks.Fixed_Distance_Book,
                        Data, Start) = Code_Length (Token.Value));
               end if;
            end;
         else
            Lemma_Shared_Data_Bits (Data, Count - 1);
         end if;
      end if;
   end Lemma_Shared_Data_Bits;

   procedure Lemma_Shared_Encoding
     (Output : Byte_Array; Data : Byte_Array)
   with
     Ghost,
     Pre  => Output'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Inflate.Payload.Is_Encoding
                 (Output, 3,
                  Inflate.Codebooks.Fixed_Literal_Length_Book,
                  Inflate.Codebooks.Fixed_Distance_Book,
                  Data),
     Post => Encodes_Prefix (Output, Data, Data'Length)
               and then Prefix_Value
                 (Output, 3 + Data_Bits (Data, Data'Length), 7) = 0;

   procedure Lemma_Shared_Encoding
     (Output : Byte_Array; Data : Byte_Array)
   is
   begin
      for I in 0 .. Data'Length - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              (if Token_Boundary (Data, J)
                    and then Selected_Token (Data, J).Kind = Match
               then 3 + Data_Bits (Data, J) + 12 <= 8 * Output'Length
                    and then Prefix_Value
                      (Output, 3 + Data_Bits (Data, J), 7) =
                        Selected_Token (Data, J).Length - 2
                    and then Prefix_Value
                      (Output, 3 + Data_Bits (Data, J) + 7, 5) =
                        Selected_Token (Data, J).Distance - 1
               elsif Token_Boundary (Data, J)
               then 3 + Data_Bits (Data, J)
                      + Code_Length (Data (Data'First + J)) <=
                        8 * Output'Length
                    and then Prefix_Value
                      (Output, 3 + Data_Bits (Data, J),
                       Code_Length (Data (Data'First + J))) =
                         Code (Data (Data'First + J))));
         Lemma_Shared_Data_Bits (Data, I);
         if Token_Boundary (Data, I) then
            pragma Assert
              (Inflate.Payload.Token_Encoded
                 (Output, 3,
                  Inflate.Codebooks.Fixed_Literal_Length_Book,
                  Inflate.Codebooks.Fixed_Distance_Book, Data, I));
            declare
               Token : constant Symbol_Result := Selected_Token (Data, I);
            begin
               if Token.Kind = Match then
                  pragma Assert
                    (Inflate.Codebooks.Length_Of
                       (Inflate.Codebooks.Fixed_Literal_Length_Book,
                        Inflate.Payload.Length_Symbol (Token.Length)) = 7);
                  pragma Assert
                    (Inflate.Codebooks.Code_Of
                       (Inflate.Codebooks.Fixed_Literal_Length_Book,
                        Inflate.Payload.Length_Symbol (Token.Length)) =
                           Token.Length - 2);
                  pragma Assert
                    (Inflate.Codebooks.Length_Of
                       (Inflate.Codebooks.Fixed_Distance_Book,
                        Inflate.Payload.Distance_Symbol
                          (Token.Distance)) = 5);
                  pragma Assert
                    (Inflate.Codebooks.Code_Of
                       (Inflate.Codebooks.Fixed_Distance_Book,
                        Inflate.Payload.Distance_Symbol (Token.Distance)) =
                           Token.Distance - 1);
                  pragma Assert
                    (3 + Data_Bits (Data, I) + 12 <=
                       8 * Output'Length);
                  pragma Assert
                    (Prefix_Value
                       (Output, 3 + Data_Bits (Data, I), 7) =
                         Token.Length - 2);
                  pragma Assert
                    (Prefix_Value
                       (Output, 3 + Data_Bits (Data, I) + 7, 5) =
                         Token.Distance - 1);
               else
                  pragma Assert
                    (Token.Value = Data (Data'First + I));
                  pragma Assert
                    (Inflate.Codebooks.Length_Of
                       (Inflate.Codebooks.Fixed_Literal_Length_Book,
                        Natural (Token.Value)) = Code_Length (Token.Value));
                  pragma Assert
                    (Inflate.Codebooks.Code_Of
                       (Inflate.Codebooks.Fixed_Literal_Length_Book,
                        Natural (Token.Value)) = Code (Token.Value));
                  pragma Assert
                    (3 + Data_Bits (Data, I) + Code_Length (Token.Value) <=
                       8 * Output'Length);
                  pragma Assert
                    (Prefix_Value
                       (Output, 3 + Data_Bits (Data, I),
                        Code_Length (Token.Value)) = Code (Token.Value));
               end if;
            end;
         end if;
      end loop;
      Lemma_Shared_Data_Bits (Data, Data'Length);
      pragma Assert
        (3 + Data_Bits (Data, Data'Length) <= 8 * Output'Length);
      pragma Assert (Encodes_Prefix (Output, Data, Data'Length));
      pragma Assert
        (Inflate.Codebooks.Length_Of
           (Inflate.Codebooks.Fixed_Literal_Length_Book, 256) = 7);
      pragma Assert
        (Inflate.Codebooks.Code_Of
           (Inflate.Codebooks.Fixed_Literal_Length_Book, 256) = 0);
   end Lemma_Shared_Encoding;

   --------------
   -- Compress --
   --------------

   procedure Compress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural)
   is
      Size : constant Positive := Encoded_Size (Input);
      Bits : Natural;
   begin
      Output (Output'First .. Output'First + Size - 1) := (others => 0);
      Set_Stream_Bit (Output, 0, 1);
      Set_Stream_Bit (Output, 1, 1);
      pragma Assert (Bit_Value (Output, 2) = 0);
      pragma Assert (Fixed_Header (Output));
      Lemma_Shared_Data_Bits (Input, Input'Length);
      pragma Assert
        (Inflate.Payload.Covers
           (Inflate.Codebooks.Fixed_Literal_Length_Book,
            Inflate.Codebooks.Fixed_Distance_Book, Input));
      Inflate.Payload.Serialize
        (Input,
         Inflate.Codebooks.Fixed_Literal_Length_Book,
         Inflate.Codebooks.Fixed_Distance_Book,
         Output, 3, Bits);
      pragma Assert
        (Bits = 3 + Data_Bits (Input, Input'Length) + 7);
      Lemma_Shared_Encoding (Output, Input);
      Produced := Size;
      pragma Assert (Fixed_Header (Output));
      pragma Assert
        (Prefix_Value
           (Output, 3 + Data_Bits (Input, Input'Length), 7) = 0);
      pragma Assert
        (Produced =
           (3 + Data_Bits (Input, Input'Length) + 7 + 7) / 8);
      Lemma_Encoding_Matches (Output, Produced, Input);
      pragma Assert (Encoding_Matches (Output, Produced, Input));
   end Compress;

   function Prefix_Matches
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural) return Boolean
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Position <= End_Position
               and then End_Position <= 8 * Input'Length
               and then Index <= End_Index
               and then End_Index <= Data'Length,
     Contract_Cases =>
       (Position = End_Position or else Index = End_Index =>
          Prefix_Matches'Result =
            (Position = End_Position and then Index = End_Index),
        Position < End_Position
          and then Index < End_Index
          and then Next_Symbol (Input, Position).Kind = Literal =>
          Prefix_Matches'Result =
            (Next_Symbol (Input, Position).Position <= End_Position
             and then Next_Symbol (Input, Position).Value =
                        Data (Data'First + Index)
             and then Prefix_Matches
               (Input, Data,
                Next_Symbol (Input, Position).Position, Index + 1,
                End_Position, End_Index)),
        Position < End_Position
          and then Index < End_Index
          and then Next_Symbol (Input, Position).Kind = Match =>
          Prefix_Matches'Result =
            (Next_Symbol (Input, Position).Position <= End_Position
             and then Next_Symbol (Input, Position).Length <=
                        End_Index - Index
             and then Match_Applies
               (Data, Index,
                Next_Symbol (Input, Position).Length,
                Next_Symbol (Input, Position).Distance)
             and then Prefix_Matches
               (Input, Data,
                Next_Symbol (Input, Position).Position,
                Index + Next_Symbol (Input, Position).Length,
                End_Position, End_Index)),
        others => not Prefix_Matches'Result),
     Subprogram_Variant => (Decreases => End_Position - Position);

   function Prefix_Matches
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural) return Boolean
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      if Position = End_Position or else Index = End_Index then
         return Position = End_Position and then Index = End_Index;
      end if;
      case S.Kind is
         when Literal =>
            return S.Position <= End_Position
              and then S.Value = Data (Data'First + Index)
              and then Prefix_Matches
                (Input, Data, S.Position, Index + 1,
                 End_Position, End_Index);
         when Match =>
            return S.Position <= End_Position
              and then S.Length <= End_Index - Index
              and then Match_Applies
                (Data, Index, S.Length, S.Distance)
              and then Prefix_Matches
                (Input, Data, S.Position, Index + S.Length,
                 End_Position, End_Index);
         when End_Of_Block | Other | Truncated =>
            return False;
      end case;
   end Prefix_Matches;

   function One_Token_Matches
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural) return Boolean
   with
     Ghost,
     Pre => Input'Length <= Max_Stream_Bytes
              and then Data'Length <= Max_Input
              and then Position <= 8 * Input'Length
              and then Index < End_Index
              and then End_Index <= Data'Length
              and then End_Position <= 8 * Input'Length,
     Contract_Cases =>
       (Next_Symbol (Input, Position).Kind = Literal =>
          One_Token_Matches'Result =
            (End_Position = Next_Symbol (Input, Position).Position
             and then End_Index = Index + 1
             and then Data (Data'First + Index) =
                        Next_Symbol (Input, Position).Value),
        Next_Symbol (Input, Position).Kind = Match =>
          One_Token_Matches'Result =
            (End_Position = Next_Symbol (Input, Position).Position
             and then End_Index =
                        Index + Next_Symbol (Input, Position).Length
             and then Match_Applies
               (Data, Index,
                Next_Symbol (Input, Position).Length,
                Next_Symbol (Input, Position).Distance)),
        others => not One_Token_Matches'Result);

   function One_Token_Matches
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural) return Boolean
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      if S.Kind = Literal then
         return End_Position = S.Position
           and then End_Index = Index + 1
           and then Data (Data'First + Index) = S.Value;
      elsif S.Kind = Match then
         return End_Position = S.Position
           and then End_Index = Index + S.Length
           and then Match_Applies
             (Data, Index, S.Length, S.Distance);
      else
         return False;
      end if;
   end One_Token_Matches;

   procedure Lemma_One_Match_Token
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Position <= 8 * Input'Length
               and then Index < End_Index
               and then End_Index <= Data'Length
               and then End_Position <= 8 * Input'Length
               and then Next_Symbol (Input, Position).Kind = Match
               and then End_Position =
                          Next_Symbol (Input, Position).Position
               and then End_Index =
                          Index + Next_Symbol (Input, Position).Length
               and then Match_Applies
                 (Data, Index,
                  Next_Symbol (Input, Position).Length,
                  Next_Symbol (Input, Position).Distance),
     Post => One_Token_Matches
       (Input, Data, Position, Index, End_Position, End_Index);

   procedure Lemma_One_Match_Token
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural) is null;

   procedure Lemma_Array_Prefix_Element
     (Before, After : Byte_Array; Count, Position : Natural)
   with
     Ghost,
     Pre  => Before'Length = After'Length
               and then Count <= Before'Length
               and then Position < Count
               and then
             (for all I in 0 .. Count - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => After (After'First + Position) =
               Before (Before'First + Position);

   procedure Lemma_Array_Prefix_Element
     (Before, After : Byte_Array; Count, Position : Natural) is null;

   procedure Lemma_Match_Frame
     (Before, After : Byte_Array;
      Count, Index, Length, Distance : Natural)
   with
     Ghost,
     Pre  => Before'Length = After'Length
               and then Count <= Before'Length
               and then Length in 3 .. 10
               and then Distance in 1 .. 4
               and then Distance <= Index
               and then Index <= Count
               and then Length <= Count - Index
               and then Match_Applies (Before, Index, Length, Distance)
               and then
             (for all I in 0 .. Count - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Match_Applies (After, Index, Length, Distance);

   procedure Lemma_Match_Frame
     (Before, After : Byte_Array;
      Count, Index, Length, Distance : Natural)
   is
   begin
      for K in 0 .. Length - 1 loop
         Lemma_Array_Prefix_Element
           (Before, After, Count, Index + K - Distance);
         Lemma_Array_Prefix_Element
           (Before, After, Count, Index + K);
         pragma Assert
           (After (After'First + Index + K) =
              After (After'First + Index + K - Distance));
      end loop;
   end Lemma_Match_Frame;

   procedure Lemma_Prefix_Data_Frame
     (Input : Byte_Array;
      Before, After : Byte_Array;
      Position, Index, End_Position, End_Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Before'Length = After'Length
               and then Before'Length <= Max_Input
               and then Position <= End_Position
               and then End_Position <= 8 * Input'Length
               and then Index <= End_Index
               and then End_Index <= Before'Length
               and then Prefix_Matches
                 (Input, Before, Position, Index, End_Position, End_Index)
               and then
             (for all I in 0 .. End_Index - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Prefix_Matches
       (Input, After, Position, Index, End_Position, End_Index),
     Subprogram_Variant => (Decreases => End_Position - Position);

   procedure Lemma_Prefix_Data_Frame
     (Input : Byte_Array;
      Before, After : Byte_Array;
      Position, Index, End_Position, End_Index : Natural)
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      if Position = End_Position then
         pragma Assert (Index = End_Index);
      elsif S.Kind = Literal then
         pragma Assert
           (After (After'First + Index) = Before (Before'First + Index));
         Lemma_Prefix_Data_Frame
           (Input, Before, After, S.Position, Index + 1,
            End_Position, End_Index);
         pragma Assert
           (Prefix_Matches
              (Input, After, S.Position, Index + 1,
               End_Position, End_Index));
      else
         pragma Assert (S.Kind = Match);
         pragma Assert (S.Distance <= Index);
         pragma Assert (S.Length <= End_Index - Index);
         Lemma_Match_Frame
           (Before, After, End_Index, Index, S.Length, S.Distance);
         Lemma_Prefix_Data_Frame
           (Input, Before, After, S.Position, Index + S.Length,
            End_Position, End_Index);
         pragma Assert
           (Prefix_Matches
              (Input, After, S.Position, Index + S.Length,
               End_Position, End_Index));
      end if;
      pragma Assert
        (Prefix_Matches
           (Input, After, Position, Index, End_Position, End_Index));
   end Lemma_Prefix_Data_Frame;

   procedure Lemma_Prefix_Snoc
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, Old_Position, Old_Index,
      New_Position, New_Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Position <= Old_Position
               and then Old_Position < New_Position
               and then New_Position <= 8 * Input'Length
               and then Index <= Old_Index
               and then Old_Index < New_Index
               and then New_Index <= Data'Length
               and then Prefix_Matches
                 (Input, Data, Position, Index, Old_Position, Old_Index)
               and then One_Token_Matches
                 (Input, Data, Old_Position, Old_Index,
                  New_Position, New_Index),
     Post => Prefix_Matches
       (Input, Data, Position, Index, New_Position, New_Index),
     Subprogram_Variant => (Decreases => Old_Position - Position);

   procedure Lemma_Prefix_Snoc
     (Input : Byte_Array;
      Data : Byte_Array;
      Position, Index, Old_Position, Old_Index,
      New_Position, New_Index : Natural)
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      if Position = Old_Position then
         pragma Assert (Index = Old_Index);
         pragma Assert
           (Prefix_Matches
              (Input, Data, Position, Index, New_Position, New_Index));
      elsif S.Kind = Literal then
         Lemma_Prefix_Snoc
           (Input, Data, S.Position, Index + 1,
            Old_Position, Old_Index, New_Position, New_Index);
      else
         pragma Assert (S.Kind = Match);
         pragma Assert (Index + S.Length <= Old_Index);
         Lemma_Prefix_Snoc
           (Input, Data, S.Position, Index + S.Length,
            Old_Position, Old_Index, New_Position, New_Index);
      end if;
   end Lemma_Prefix_Snoc;

   procedure Lemma_Prefix_Extend
     (Input : Byte_Array;
      Before, After : Byte_Array;
      Position, Index, Old_Position, Old_Index,
      New_Position, New_Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Before'Length = After'Length
               and then Before'Length <= Max_Input
               and then Position <= Old_Position
               and then Old_Position < New_Position
               and then New_Position <= 8 * Input'Length
               and then Index <= Old_Index
               and then Old_Index < New_Index
               and then New_Index <= Before'Length
               and then Prefix_Matches
                 (Input, Before, Position, Index, Old_Position, Old_Index)
               and then One_Token_Matches
                 (Input, After, Old_Position, Old_Index,
                  New_Position, New_Index)
               and then
             (for all I in 0 .. Old_Index - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post => Prefix_Matches
       (Input, After, Position, Index, New_Position, New_Index);

   procedure Lemma_Prefix_Extend
     (Input : Byte_Array;
      Before, After : Byte_Array;
      Position, Index, Old_Position, Old_Index,
      New_Position, New_Index : Natural)
   is
   begin
      Lemma_Prefix_Data_Frame
        (Input, Before, After, Position, Index,
         Old_Position, Old_Index);
      Lemma_Prefix_Snoc
        (Input, After, Position, Index,
         Old_Position, Old_Index, New_Position, New_Index);
   end Lemma_Prefix_Extend;

   procedure Lemma_Prefix_Close
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural)
   with
     Ghost,
     Pre  => Input'Length <= Max_Stream_Bytes
               and then Data'Length <= Max_Input
               and then Consumed in 1 .. Input'Length
               and then Position <= End_Position
               and then End_Position <= 8 * Consumed
               and then Index <= End_Index
               and then End_Index = Data'Length
               and then Prefix_Matches
                 (Input, Data, Position, Index, End_Position, End_Index)
               and then Next_Symbol (Input, End_Position).Kind = End_Of_Block
               and then Consumed =
                 (Next_Symbol (Input, End_Position).Position + 7) / 8,
     Post => Spec_Matches
       (Input, Consumed, Data, Position, Index),
     Subprogram_Variant => (Decreases => End_Position - Position);

   procedure Lemma_Prefix_Close
     (Input : Byte_Array;
      Consumed : Natural;
      Data : Byte_Array;
      Position, Index, End_Position, End_Index : Natural)
   is
      S : constant Symbol_Result := Next_Symbol (Input, Position);
   begin
      if Position = End_Position then
         pragma Assert (Index = End_Index);
      elsif S.Kind = Literal then
         Lemma_Prefix_Close
           (Input, Consumed, Data, S.Position, Index + 1,
            End_Position, End_Index);
      else
         pragma Assert (S.Kind = Match);
         Lemma_Prefix_Close
           (Input, Consumed, Data, S.Position, Index + S.Length,
            End_Position, End_Index);
      end if;
   end Lemma_Prefix_Close;

   -------------------------
   -- Copy_Selected_Match --
   -------------------------

   --  Execute the bounded match shapes admitted by Next_Symbol and expose
   --  the same forward-copy window equation used by the M4 copy primitive.
   procedure Copy_Selected_Match
     (Data     : in out Byte_Array;
      Produced : in out Natural;
      Length   : in     Natural;
      Distance : in     Natural)
   with
     Pre  => Data'Length <= Max_Input
               and then Produced <= Data'Length
               and then Length in 3 .. 10
               and then Distance in 1 .. 4
               and then Distance <= Produced
               and then Length <= Data'Length - Produced,
     Post => Produced = Produced'Old + Length
               and then
             (for all I in 0 .. Produced'Old - 1 =>
                Data (Data'First + I) = Data'Old (Data'First + I))
               and then Match_Applies
                 (Data, Produced'Old, Length, Distance)
   is
      First  : constant Buffer_Index := Data'First;
      P      : constant Natural := Produced;
      Before : constant Byte_Array := Data with Ghost;
   begin
      for K in 0 .. Length - 1 loop
         pragma Loop_Invariant
           (for all I in 0 .. P - 1 =>
              Data (First + I) = Before (First + I));
         pragma Loop_Invariant
           (for all J in 0 .. K - 1 =>
              Data (First + P + J) =
                Data (First + P + J - Distance));
         Data (First + P + K) :=
           Data (First + P + K - Distance);
      end loop;
      Produced := P + Length;
      pragma Assert (Match_Applies (Data, P, Length, Distance));
   end Copy_Selected_Match;

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
            pragma Loop_Invariant
              (Spec_Walk (Input, Position, Count).Valid);
            pragma Loop_Invariant
              (Spec_Walk (Input, Position, Count).End_Bit = Info.End_Bit);
            pragma Loop_Invariant
              (Count + Spec_Walk (Input, Position, Count).Decoded_Length =
                 Info.Decoded_Length);
            pragma Loop_Invariant
              (Prefix_Matches (Input, Data, 3, 0, Position, Count));
            pragma Loop_Variant (Increases => Position);
            S := Next_Symbol (Input, Position);
            case S.Kind is
               when Literal =>
                  pragma Assert (Count < Info.Decoded_Length);
                  pragma Assert
                    (Spec_Walk (Input, S.Position, Count + 1).Valid);
                  pragma Assert
                    (Spec_Walk (Input, S.Position, Count + 1).End_Bit =
                       Info.End_Bit);
                  pragma Assert
                    (Count + 1
                       + Spec_Walk (Input, S.Position, Count + 1)
                           .Decoded_Length = Info.Decoded_Length);
                  declare
                     Before       : constant Byte_Array := Data with Ghost;
                     Old_Position : constant Natural := Position;
                     Old_Count    : constant Natural := Count;
                  begin
                     Data (Data'First + Count) := S.Value;
                     Position := S.Position;
                     Count := Count + 1;
                     pragma Assert
                       (for all I in 0 .. Old_Count - 1 =>
                          Data (Data'First + I) =
                            Before (Before'First + I));
                     pragma Assert
                       (One_Token_Matches
                          (Input, Data, Old_Position, Old_Count,
                           Position, Count));
                     Lemma_Prefix_Extend
                       (Input, Before, Data, 3, 0,
                        Old_Position, Old_Count, Position, Count);
                  end;
               when Match =>
                  pragma Assert (S.Distance <= Count);
                  pragma Assert
                    (S.Length <= Info.Decoded_Length - Count);
                  pragma Assert
                    (Spec_Walk
                       (Input, S.Position, Count + S.Length).Valid);
                  pragma Assert
                    (Spec_Walk
                       (Input, S.Position, Count + S.Length).End_Bit =
                         Info.End_Bit);
                  pragma Assert
                    (Count + S.Length
                       + Spec_Walk
                           (Input, S.Position, Count + S.Length)
                           .Decoded_Length = Info.Decoded_Length);
                  declare
                     Before       : constant Byte_Array := Data with Ghost;
                     Old_Position : constant Natural := Position;
                     Old_Count    : constant Natural := Count;
                  begin
                     Copy_Selected_Match
                       (Data, Count, S.Length, S.Distance);
                     Position := S.Position;
                     pragma Assert
                       (for all I in 0 .. Old_Count - 1 =>
                          Data (Data'First + I) =
                            Before (Before'First + I));
                     pragma Assert
                       (Match_Applies
                          (Data, Old_Count, S.Length, S.Distance));
                     pragma Assert (S.Kind = Match);
                     pragma Assert (Position = S.Position);
                     pragma Assert (Count = Old_Count + S.Length);
                     pragma Assert
                       (Next_Symbol (Input, Old_Position) = S);
                     pragma Assert
                       (Position =
                          Next_Symbol (Input, Old_Position).Position);
                     pragma Assert
                       (Count = Old_Count
                          + Next_Symbol (Input, Old_Position).Length);
                     pragma Assert
                       (Match_Applies
                          (Data, Old_Count,
                           Next_Symbol (Input, Old_Position).Length,
                           Next_Symbol (Input, Old_Position).Distance));
                     Lemma_One_Match_Token
                       (Input, Data, Old_Position, Old_Count,
                        Position, Count);
                     pragma Assert
                       (One_Token_Matches
                          (Input, Data, Old_Position, Old_Count,
                           Position, Count));
                     Lemma_Prefix_Extend
                       (Input, Before, Data, 3, 0,
                        Old_Position, Old_Count, Position, Count);
                  end;
               when End_Of_Block =>
                  pragma Assert (Count = Info.Decoded_Length);
                  pragma Assert (S.Position = Info.End_Bit);
                  Consumed := (S.Position + 7) / 8;
                  Produced := Count;
                  Lemma_Prefix_Close
                    (Input, Consumed, Data, 3, 0, Position, Count);
                  pragma Assert
                    (Spec_Matches (Input, Consumed, Data, 3, 0));
                  pragma Assert (Encoding_Matches (Input, Consumed, Data));
                  Success := True;
                  return;
               when Other | Truncated =>
                  pragma Assert (False);
            end case;
         end loop;
      end;
   end Decompress;

end Inflate.Fixed;
