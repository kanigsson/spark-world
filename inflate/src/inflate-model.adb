package body Inflate.Model with SPARK_Mode => On is

   ------------------------
   -- Lemma_Encodes_Step --
   ------------------------

   procedure Lemma_Encodes_Step
     (C : Byte_Array; CF : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; DL : Natural)
   is null;

   --------------------------
   -- Lemma_Encodes_Frame --
   --------------------------

   procedure Lemma_Encodes_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; D2 : Byte_Array; DF : Positive; DL : Natural)
   is
      Len : constant Natural := Block_Length (C1, CF);
   begin
      pragma Assert (Block_Length (C2, CF) = Len);
      if C1 (CF) /= 1 then
         --  Not the final block: the tail relation transfers by induction
         --  on the remaining stream, then this block's own fields transfer
         --  byte for byte.
         Lemma_Encodes_Frame
           (C1, C2, CF + 5 + Len, CL, D1, D2, DF + Len, DL);
      end if;
   end Lemma_Encodes_Frame;

   --------------------------
   -- Lemma_Nonfinal_Frame --
   --------------------------

   procedure Lemma_Nonfinal_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; D2 : Byte_Array; DF : Positive; DL : Natural)
   is
   begin
      if CF <= CL then
         --  A non-empty prefix: the head block's fields transfer byte for
         --  byte, the rest by induction on the remaining prefix.
         declare
            Len : constant Natural := Block_Length (C1, CF);
         begin
            pragma Assert (Block_Length (C2, CF) = Len);
            Lemma_Nonfinal_Frame
              (C1, C2, CF + 5 + Len, CL, D1, D2, DF + Len, DL);
         end;
      end if;
   end Lemma_Nonfinal_Frame;

   ------------------------
   -- Lemma_Stream_Frame --
   ------------------------

   procedure Lemma_Stream_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; Last : Natural)
   is
   begin
      if Last - CF >= 4
        and then C1 (CF) <= 1
        and then Natural (C1 (CF + 3)) + 256 * Natural (C1 (CF + 4)) =
                   16#FFFF# - Block_Length (C1, CF)
        and then Last - (CF + 4) >= Block_Length (C1, CF)
      then
         --  A block starts here in both buffers (same bytes); the rest of
         --  the walk transfers by induction.
         pragma Assert (Block_Length (C2, CF) = Block_Length (C1, CF));
         Lemma_Stream_Frame (C1, C2, CF + 5 + Block_Length (C1, CF), Last);
      end if;
   end Lemma_Stream_Frame;

   -----------------------
   -- Lemma_Stream_Step --
   -----------------------

   procedure Lemma_Stream_Step
     (C : Byte_Array; CF : Positive; Last : Natural)
   is null;

   -------------------------
   -- Lemma_Nonfinal_Snoc --
   -------------------------

   procedure Lemma_Nonfinal_Snoc
     (C : Byte_Array; CF : Positive; M : Positive;
      D : Byte_Array; DF : Positive; N : Positive)
   is
      Len : constant Natural := Block_Length (C, M);
   begin
      if CF = M then
         --  Empty prefix: the result is the single appended block followed
         --  by an empty rest, one unfolding of the definition.
         pragma Assert (DF = N);
         pragma Assert
           (Encodes_Nonfinal
              (C, M + 5 + Len, M + 4 + Len, D, N + Len, N + (Len - 1)));
         pragma Assert
           (Encodes_Nonfinal (C, CF, M + 4 + Len, D, DF, N + (Len - 1)));
      else
         --  Peel the prefix's head block and recurse on the shorter
         --  prefix; the head block conjuncts are unchanged, so the whole
         --  refolds around the recursive result.
         declare
            Head : constant Natural := Block_Length (C, CF);
         begin
            Lemma_Nonfinal_Snoc (C, CF + 5 + Head, M, D, DF + Head, N);
            pragma Assert
              (Encodes_Nonfinal (C, CF, M + 4 + Len, D, DF, N + (Len - 1)));
         end;
      end if;
   end Lemma_Nonfinal_Snoc;

   --------------------------
   -- Lemma_Nonfinal_Close --
   --------------------------

   procedure Lemma_Nonfinal_Close
     (C : Byte_Array; CF : Positive; M : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; N : Positive; DL : Natural)
   is
   begin
      if CF = M then
         pragma Assert (DF = N);
      else
         --  Peel the prefix's head block, recurse, and refold: the head is
         --  non-final, so the full relation at CF is the head conjuncts
         --  plus the relation on the rest, which the recursion provides.
         declare
            Head : constant Natural := Block_Length (C, CF);
         begin
            Lemma_Nonfinal_Close
              (C, CF + 5 + Head, M, CL, D, DF + Head, N, DL);
            Lemma_Encodes_Step (C, CF, CL, D, DF, DL);
         end;
      end if;
   end Lemma_Nonfinal_Close;

   -----------------------
   -- Lemma_Encodes_End --
   -----------------------

   procedure Lemma_Encodes_End
     (C : Byte_Array; CF : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; DL : Natural;
      Last : Natural)
   is
      Len : constant Natural := Block_Length (C, CF);
   begin
      if C (CF) /= 1 then
         Lemma_Encodes_End (C, CF + 5 + Len, CL, D, DF + Len, DL, Last);
      end if;
   end Lemma_Encodes_End;

   ------------------------------
   -- Lemma_Encodes_Functional --
   ------------------------------

   procedure Lemma_Encodes_Functional
     (C  : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; DF1 : Positive; DL1 : Natural;
      D2 : Byte_Array; DF2 : Positive; DL2 : Natural)
   is
      Len : constant Natural := Block_Length (C, CF);
   begin
      if C (CF) = 1 then
         --  Single final block: both decoded ranges are exactly the
         --  payload, equal to the same compressed bytes.
         pragma Assert
           (for all K in 0 .. DL1 - DF1 => D1 (DF1 + K) = C (CF + 5 + K));
      else
         Lemma_Encodes_Functional
           (C, CF + 5 + Len, CL,
            D1, DF1 + Len, DL1,
            D2, DF2 + Len, DL2);
         --  Head payload bytes agree through the compressed stream, tail
         --  bytes by induction; every offset falls in one of the two. The
         --  identity assertion rewrites tail indices into the shifted form
         --  the induction hypothesis quantifies over.
         pragma Assert
           (for all K in 0 .. DL1 - DF1 =>
              (if K < Len then D1 (DF1 + K) = D2 (DF2 + K)));
         pragma Assert
           (for all K in Len .. DL1 - DF1 =>
              D1 (DF1 + K) = D1 ((DF1 + Len) + (K - Len))
              and then D2 (DF2 + K) = D2 ((DF2 + Len) + (K - Len)));
         pragma Assert
           (for all K in 0 .. DL1 - DF1 =>
              (if K >= Len then D1 (DF1 + K) = D2 (DF2 + K)));
      end if;
   end Lemma_Encodes_Functional;

   ---------------------------------------------------------------------
   --  Full DEFLATE decode model
   ---------------------------------------------------------------------

   subtype Model_Bit_Request is Natural range 0 .. 13;
   subtype Model_Code_Length is Natural range 0 .. 15;
   type Model_Length_Array is
     array (Natural range <>) of Model_Code_Length;

   subtype Model_Symbol_Count is Natural range 0 .. 288;
   type Model_Count_Array is
     array (Positive range 1 .. 15) of Model_Symbol_Count;
   subtype Model_Symbol is Natural range 0 .. 287;
   type Model_Symbol_Array is
     array (Natural range 0 .. 287) of Model_Symbol;

   Model_Pow2 : constant array (Natural range 0 .. 15) of Natural :=
     (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192,
      16384, 32768);

   type Model_Huffman_Table is record
      Counts  : Model_Count_Array;
      Symbols : Model_Symbol_Array;
      Size    : Natural range 0 .. 288;
      Usable  : Boolean;
   end record;

   type Bits_Result is record
      Good     : Boolean;
      Value    : Natural;
      Position : Long_Long_Integer;
   end record;

   type Symbol_Result is record
      Good     : Boolean;
      Symbol   : Natural;
      Position : Long_Long_Integer;
   end record;

   function Total_Bits (Input : Byte_Array) return Long_Long_Integer is
     (Long_Long_Integer (Input'Length) * 8)
   with Post => Total_Bits'Result in
                  0 .. Long_Long_Integer (Buffer_Index'Last) * 8;

   function Read_Bits
     (Input    : Byte_Array;
      Position : Long_Long_Integer;
      Count    : Model_Bit_Request) return Bits_Result
   with
     Pre  => Position in 0 .. Total_Bits (Input),
     Post =>
       (if Read_Bits'Result.Good
        then Read_Bits'Result.Position = Position + Long_Long_Integer (Count)
             and then Read_Bits'Result.Position <= Total_Bits (Input)
             and then Read_Bits'Result.Value < 2 ** Count
        else Read_Bits'Result.Position = Position)
   is
      P      : Long_Long_Integer := Position;
      Value  : Natural := 0;
      Factor : Natural := 1;
      Offset : Natural;
      Bit    : Natural;
   begin
      if Total_Bits (Input) - Position < Long_Long_Integer (Count) then
         return (Good => False, Value => 0, Position => Position);
      end if;

      for I in 1 .. Count loop
         pragma Loop_Invariant (P = Position + Long_Long_Integer (I - 1));
         pragma Loop_Invariant (P < Total_Bits (Input));
         pragma Loop_Invariant (Factor = Model_Pow2 (I - 1));
         pragma Loop_Invariant (Value < Factor);
         Offset := Natural (P / 8);
         Bit := Natural
           (Interfaces.Shift_Right
              (Input (Input'First + Offset), Natural (P mod 8)) and 1);
         Value := Value + Bit * Factor;
         Factor := Factor * 2;
         P := P + 1;
      end loop;
      return (Good => True, Value => Value, Position => P);
   end Read_Bits;

   function Count_Of
     (Lengths : Model_Length_Array;
      Length  : Positive) return Natural
   with
     Pre  => Lengths'Length <= 316,
     Post => Count_Of'Result <= Lengths'Length
   is
      Result : Natural range 0 .. 316 := 0;
   begin
      for I in Lengths'Range loop
         pragma Loop_Invariant (Result <= I - Lengths'First);
         if Lengths (I) = Length then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Count_Of;

   function Build_Model_Table
     (Lengths : Model_Length_Array) return Model_Huffman_Table
   with Pre => Lengths'Length in 1 .. 288
   is
      Result : Model_Huffman_Table :=
        (Counts => (others => 0), Symbols => (others => 0), Size => 0,
         Usable => True);
      Offsets : Model_Count_Array := (others => 0);
   begin
      for I in Lengths'Range loop
         pragma Loop_Invariant (Result.Size <= I - Lengths'First);
         if Lengths (I) /= 0 then
            if Result.Counts (Lengths (I)) = 288 then
               Result.Usable := False;
               return Result;
            end if;
            Result.Counts (Lengths (I)) :=
              Result.Counts (Lengths (I)) + 1;
            Result.Size := Result.Size + 1;
         end if;
      end loop;
      for Length in 2 .. 15 loop
         pragma Loop_Invariant
           (for all L in 1 .. Length - 1 => Offsets (L) <= Result.Size);
         if Offsets (Length - 1) >
              Result.Size - Result.Counts (Length - 1)
         then
            Result.Usable := False;
            return Result;
         end if;
         Offsets (Length) :=
           Offsets (Length - 1) + Result.Counts (Length - 1);
      end loop;
      for I in Lengths'Range loop
         pragma Loop_Invariant
           (for all Length in 1 .. 15 => Offsets (Length) <= Result.Size);
         if Lengths (I) /= 0 then
            if Offsets (Lengths (I)) >= Result.Size then
               Result.Usable := False;
               return Result;
            end if;
            Result.Symbols (Offsets (Lengths (I))) := I - Lengths'First;
            Offsets (Lengths (I)) := Offsets (Lengths (I)) + 1;
         end if;
      end loop;
      return Result;
   end Build_Model_Table;

   function Decode_Symbol
      (Input    : Byte_Array;
      Position : Long_Long_Integer;
      Table    : Model_Huffman_Table) return Symbol_Result
   with
     Pre  => Position in 0 .. Total_Bits (Input)
             and then Table.Usable,
     Post =>
       Decode_Symbol'Result.Position in Position .. Total_Bits (Input)
       and then (if Decode_Symbol'Result.Good
                 then Decode_Symbol'Result.Position > Position
                      and then Decode_Symbol'Result.Symbol <= 287
                 else Decode_Symbol'Result.Position = Position)
   is
      P     : Long_Long_Integer := Position;
      Code  : Natural := 0;
      First : Natural := 0;
      Index : Natural := 0;
      Count : Natural;
      B     : Bits_Result;
   begin
      for Length in 1 .. 15 loop
         pragma Loop_Invariant (P in Position .. Total_Bits (Input));
         pragma Loop_Invariant (Code < 2 ** (Length - 1));
         pragma Loop_Invariant (First <= Code);
         pragma Loop_Invariant (Index <= 288 * (Length - 1));
         B := Read_Bits (Input, P, 1);
         if not B.Good then
            return (Good => False, Symbol => 0, Position => Position);
         end if;
         P := B.Position;
         Code := Code * 2 + B.Value;
         First := First * 2;
         Count := Table.Counts (Length);
         if Code >= First and then Code - First < Count then
            if Index > 287 - (Code - First) then
               return (Good => False, Symbol => 0, Position => Position);
            end if;
            return
              (Good     => True,
               Symbol   => Table.Symbols (Index + (Code - First)),
               Position => P);
         end if;
         if Index > Natural'Last - Count then
            return (Good => False, Symbol => 0, Position => Position);
         end if;
         Index := Index + Count;
         First := First + Count;
      end loop;
      return (Good => False, Symbol => 0, Position => Position);
   end Decode_Symbol;

   function Lengths_Valid
     (Lengths         : Model_Length_Array;
      Require_Complete : Boolean) return Boolean
   with Pre => Lengths'Length <= 288
   is
      Left  : Natural range 0 .. 32_768 := 1;
      Slots : Natural range 0 .. 65_536;
      Count : Natural range 0 .. 288;
   begin
      for Length in 1 .. 15 loop
         pragma Loop_Invariant (Left in 0 .. 2 ** (Length - 1));
         Slots := Left * 2;
         Count := Count_Of (Lengths, Length);
         if Count > Slots then
            return False;
         end if;
         Left := Slots - Count;
      end loop;
      if Require_Complete then
         return Left = 0;
      else
         return Left = 0
           or else (for all Length in 2 .. 15 =>
                      Count_Of (Lengths, Length) = 0);
      end if;
   end Lengths_Valid;

   subtype Model_Length is Natural range 0 .. 65_535;
   subtype Model_Distance is Natural range 0 .. 32_768;
   subtype Model_Length_Base is Natural range 3 .. 258;
   subtype Model_Dist_Base is Natural range 1 .. 24_577;
   type Length_Base_Array is
     array (Natural range 0 .. 28) of Model_Length_Base;
   type Dist_Base_Array is
     array (Natural range 0 .. 29) of Model_Dist_Base;

   Length_Base : constant Length_Base_Array :=
     (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43,
      51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
   Length_Extra : constant array (Natural range 0 .. 28) of Model_Bit_Request :=
     (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
      4, 4, 4, 4, 5, 5, 5, 5, 0);
   Dist_Base : constant Dist_Base_Array :=
     (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257,
      385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
      16385, 24577);
   Dist_Extra : constant array (Natural range 0 .. 29) of Model_Bit_Request :=
     (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
      9, 9, 10, 10, 11, 11, 12, 12, 13, 13);

   function General_Decoding
     (Input    : Byte_Array;
      Output   : Byte_Array;
      Consumed : Natural;
      Produced : Natural) return Boolean
   with
     Pre => Consumed <= Input'Length and then Produced <= Output'Length
   is
      Position : Long_Long_Integer := 0;
      Out_Pos  : Natural := 0;
      Header, Extra : Bits_Result;
      Decoded : Symbol_Result;
      BFinal, BType : Natural;
      Final : Boolean := False;
      Block_Start : Long_Long_Integer;
      Code_Start  : Long_Long_Integer;

      Lit_Lengths  : Model_Length_Array (0 .. 287) := (others => 0);
      Dist_Lengths : Model_Length_Array (0 .. 31) := (others => 0);
      CL_Lengths   : Model_Length_Array (0 .. 18) := (others => 0);
      Combined     : Model_Length_Array (0 .. 315) := (others => 0);
      Lit_Table    : Model_Huffman_Table;
      Dist_Table   : Model_Huffman_Table;
      CL_Table     : Model_Huffman_Table;

      Order : constant array (Natural range 0 .. 18) of Natural :=
        (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);

      HLit, HDist, HCLen : Natural;
      I, Rep : Natural;
      Previous : Model_Code_Length;
      Length   : Model_Length;
      Distance : Model_Distance;
   begin
      while not Final loop
         pragma Loop_Invariant (Position in 0 .. Total_Bits (Input));
         pragma Loop_Invariant (Out_Pos <= Produced);
         pragma Loop_Variant (Increases => Position);

         Block_Start := Position;

         Header := Read_Bits (Input, Position, 1);
         if not Header.Good then
            return False;
         end if;
         BFinal := Header.Value;
         Position := Header.Position;
         Header := Read_Bits (Input, Position, 2);
         if not Header.Good then
            return False;
         end if;
         BType := Header.Value;
         Position := Header.Position;
         Final := BFinal = 1;

         if BType = 0 then
            Position := ((Position + 7) / 8) * 8;
            if Total_Bits (Input) - Position < 32 then
               return False;
            end if;
            Header := Read_Bits (Input, Position, 8);
            if not Header.Good or else Header.Value > 255 then
               return False;
            end if;
            declare
               L0 : constant Natural range 0 .. 255 := Header.Value;
            begin
               Position := Header.Position;
               Header := Read_Bits (Input, Position, 8);
               if not Header.Good or else Header.Value > 255 then
                  return False;
               end if;
               Length := L0 + 256 * Header.Value;
            end;
            Position := Header.Position;
            Header := Read_Bits (Input, Position, 8);
            if not Header.Good or else Header.Value > 255 then
               return False;
            end if;
            declare
               N0 : constant Natural range 0 .. 255 := Header.Value;
               NLen : Natural range 0 .. 65_535;
            begin
               Position := Header.Position;
               Header := Read_Bits (Input, Position, 8);
               if not Header.Good or else Header.Value > 255 then
                  return False;
               end if;
               NLen := N0 + 256 * Header.Value;
               Position := Header.Position;
               if NLen /= 16#FFFF# - Length then
                  return False;
               end if;
            end;
            if Long_Long_Integer (Length) >
                 (Total_Bits (Input) - Position) / 8
              or else Length > Produced - Out_Pos
            then
               return False;
            end if;
            for K in 0 .. Length - 1 loop
               pragma Loop_Invariant (K <= Length);
               declare
                  Offset : constant Natural := Natural (Position / 8) + K;
               begin
                  if Output (Output'First + Out_Pos + K) /=
                       Input (Input'First + Offset)
                  then
                     return False;
                  end if;
               end;
            end loop;
            Position := Position + Long_Long_Integer (Length) * 8;
            Out_Pos := Out_Pos + Length;

         elsif BType = 1 or else BType = 2 then
            Lit_Lengths := (others => 0);
            Dist_Lengths := (others => 0);

            if BType = 1 then
               Lit_Lengths (0 .. 143) := (others => 8);
               Lit_Lengths (144 .. 255) := (others => 9);
               Lit_Lengths (256 .. 279) := (others => 7);
               Lit_Lengths (280 .. 287) := (others => 8);
               Dist_Lengths (0 .. 29) := (others => 5);
            else
               Header := Read_Bits (Input, Position, 5);
               if not Header.Good then return False; end if;
               HLit := 257 + Header.Value;
               Position := Header.Position;
               Header := Read_Bits (Input, Position, 5);
               if not Header.Good then return False; end if;
               HDist := 1 + Header.Value;
               Position := Header.Position;
               Header := Read_Bits (Input, Position, 4);
               if not Header.Good then return False; end if;
               HCLen := 4 + Header.Value;
               Position := Header.Position;
               if HLit > 286 or else HDist > 30 then
                  return False;
               end if;

               CL_Lengths := (others => 0);
               for J in 0 .. HCLen - 1 loop
                  pragma Loop_Invariant (Position in 0 .. Total_Bits (Input));
                  Header := Read_Bits (Input, Position, 3);
                  if not Header.Good then return False; end if;
                  CL_Lengths (Order (J)) := Header.Value;
                  Position := Header.Position;
               end loop;
               if not Lengths_Valid (CL_Lengths, True) then
                  return False;
               end if;
               CL_Table := Build_Model_Table (CL_Lengths);
               if not CL_Table.Usable then
                  return False;
               end if;

               Combined := (others => 0);
               I := 0;
               while I < HLit + HDist loop
                  pragma Loop_Invariant (I <= HLit + HDist);
                  pragma Loop_Invariant (Position in 0 .. Total_Bits (Input));
                  pragma Loop_Variant
                    (Decreases => Total_Bits (Input) - Position);
                  Decoded := Decode_Symbol (Input, Position, CL_Table);
                  if not Decoded.Good then return False; end if;
                  Position := Decoded.Position;
                  if Decoded.Symbol <= 15 then
                     Combined (I) := Decoded.Symbol;
                     I := I + 1;
                  else
                     case Decoded.Symbol is
                        when 16 =>
                           if I = 0 then return False; end if;
                           Previous := Combined (I - 1);
                           Extra := Read_Bits (Input, Position, 2);
                           if not Extra.Good then return False; end if;
                           Rep := 3 + Extra.Value;
                        when 17 =>
                           Previous := 0;
                           Extra := Read_Bits (Input, Position, 3);
                           if not Extra.Good then return False; end if;
                           Rep := 3 + Extra.Value;
                        when 18 =>
                           Previous := 0;
                           Extra := Read_Bits (Input, Position, 7);
                           if not Extra.Good then return False; end if;
                           Rep := 11 + Extra.Value;
                        when others =>
                           return False;
                     end case;
                     Position := Extra.Position;
                     if Rep > HLit + HDist - I then
                        return False;
                     end if;
                     for K in 1 .. Rep loop
                        pragma Loop_Invariant
                          (I = I'Loop_Entry + (K - 1));
                        Combined (I) := Previous;
                        I := I + 1;
                     end loop;
                  end if;
               end loop;

               Lit_Lengths (0 .. HLit - 1) := Combined (0 .. HLit - 1);
               Dist_Lengths (0 .. HDist - 1) :=
                 Combined (HLit .. HLit + HDist - 1);
               if not Lengths_Valid
                        (Lit_Lengths (0 .. HLit - 1), False)
                 or else not Lengths_Valid
                               (Dist_Lengths (0 .. HDist - 1), False)
               then
                  return False;
               end if;
            end if;

            Lit_Table := Build_Model_Table (Lit_Lengths);
            Dist_Table := Build_Model_Table (Dist_Lengths);
            if not Lit_Table.Usable or else not Dist_Table.Usable then
               return False;
            end if;

            loop
               pragma Loop_Invariant (Position in 0 .. Total_Bits (Input));
               pragma Loop_Invariant (Out_Pos <= Produced);
               pragma Loop_Variant (Increases => Position);
               Code_Start := Position;
               Decoded := Decode_Symbol (Input, Position, Lit_Table);
               if not Decoded.Good then return False; end if;
               Position := Decoded.Position;

               if Decoded.Symbol < 256 then
                  if Out_Pos >= Produced
                    or else Output (Output'First + Out_Pos) /=
                              Byte (Decoded.Symbol)
                  then
                     return False;
                  end if;
                  Out_Pos := Out_Pos + 1;
               elsif Decoded.Symbol = 256 then
                  exit;
               elsif Decoded.Symbol <= 285 then
                  Extra := Read_Bits
                    (Input, Position, Length_Extra (Decoded.Symbol - 257));
                  if not Extra.Good then return False; end if;
                  if Extra.Value > 31 then return False; end if;
                  declare
                     Extra_Length : constant Natural range 0 .. 31 :=
                       Extra.Value;
                  begin
                     Length :=
                       Length_Base (Decoded.Symbol - 257) + Extra_Length;
                  end;
                  Position := Extra.Position;
                  if Position not in 0 .. Total_Bits (Input) then
                     return False;
                  end if;

                  Decoded := Decode_Symbol (Input, Position, Dist_Table);
                  if not Decoded.Good or else Decoded.Symbol > 29 then
                     return False;
                  end if;
                  Position := Decoded.Position;
                  Extra := Read_Bits
                    (Input, Position, Dist_Extra (Decoded.Symbol));
                  if not Extra.Good then return False; end if;
                  if Extra.Value > 8_191 then return False; end if;
                  declare
                     Extra_Distance : constant Natural range 0 .. 8_191 :=
                       Extra.Value;
                  begin
                     Distance :=
                       Dist_Base (Decoded.Symbol) + Extra_Distance;
                  end;
                  Position := Extra.Position;
                  if Distance > Out_Pos or else Length > Produced - Out_Pos then
                     return False;
                  end if;
                  for K in 0 .. Length - 1 loop
                     pragma Loop_Invariant (K <= Length);
                     if Output (Output'First + Out_Pos + K) /=
                          Output (Output'First + Out_Pos + K - Distance)
                     then
                        return False;
                     end if;
                  end loop;
                  Out_Pos := Out_Pos + Length;
               else
                  return False;
               end if;
               if Position <= Code_Start then
                  return False;
               end if;
            end loop;
         else
            return False;
         end if;
         if Position <= Block_Start then
            return False;
         end if;
      end loop;

      return Out_Pos = Produced
        and then Long_Long_Integer (Consumed) = (Position + 7) / 8;
   end General_Decoding;

   function Is_Decoding
     (Input    : Byte_Array;
      Output   : Byte_Array;
      Consumed : Natural;
      Produced : Natural) return Boolean
   is
      OFN : constant Positive :=
        (if Output'Length > 0 then Output'First else 1);
   begin
      --  Keep the ordinary runtime path iterative.  The recursive stored
      --  relation remains a proof fallback for the established compressor
      --  image, but a valid stored stream is accepted by General_Decoding
      --  before any recursive model function is evaluated.
      if General_Decoding (Input, Output, Consumed, Produced) then
         return True;
      elsif Input'Length <= Fixed.Max_Stream_Bytes then
         declare
            Info : constant Fixed.Stream_Info := Fixed.Analyze (Input);
         begin
            if Info.Valid
              and then Info.Decoded_Length <= Output'Length
              and then Consumed = (Info.End_Bit + 7) / 8
              and then Produced = Info.Decoded_Length
              and then Fixed.Is_Encoding
                (Input, Consumed,
                 Output (Output'First .. Output'First - 1 + Produced))
            then
               return True;
            end if;
         end;
         if Dynamic.Decodes
           (Input, Consumed,
            Output (Output'First .. Output'First - 1 + Produced))
         then
            return True;
         end if;
      end if;

      if Input'Length >= 5 then
         declare
            Stored_End : constant Natural :=
              Stored_Stream_End (Input, Input'First, Input'Last);
         begin
            return
              Stored_End > 0
              and then Consumed > 0
              and then Input'First + (Consumed - 1) = Stored_End
              and then Stored_Decoded_Length
                         (Input, Input'First, Input'Last) = Produced
              and then
                (if Produced = 0
                 then Encodes_Stored
                        (Input, Input'First, Stored_End,
                         Output, OFN, OFN - 1)
                 else Encodes_Stored
                        (Input, Input'First, Stored_End, Output, OFN,
                         OFN + (Produced - 1)));
         end;
      end if;
      return False;
   end Is_Decoding;

end Inflate.Model;
