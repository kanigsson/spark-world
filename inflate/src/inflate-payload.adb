with Interfaces;

package body Inflate.Payload with SPARK_Mode => On is

   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   use Interfaces;

   procedure Lemma_Prefix_Step
     (Input : Byte_Array; Start : Natural; Length : Positive)
   with
     Ghost,
     Pre  => Input'Length <= Fixed.Max_Stream_Bytes
               and then Length <= 9
               and then Start <= 8 * Input'Length
               and then Length <= 8 * Input'Length - Start,
     Post => Fixed.Prefix_Value (Input, Start, Length) =
               2 * Fixed.Prefix_Value (Input, Start, Length - 1)
                 + Fixed.Bit_Value (Input, Start + Length - 1);

   procedure Lemma_Prefix_Step
     (Input : Byte_Array; Start : Natural; Length : Positive) is null;

   procedure Lemma_Prefix_Frame
     (Before, After : Byte_Array;
      Start, Length : Natural)
   with
     Ghost,
     Pre  => Before'Length <= Fixed.Max_Stream_Bytes
               and then After'Length <= Fixed.Max_Stream_Bytes
               and then Length <= 9
               and then Start <= 8 * Before'Length
               and then Length <= 8 * Before'Length - Start
               and then Start <= 8 * After'Length
               and then Length <= 8 * After'Length - Start
               and then
             (for all Position in Start .. Start + Length - 1 =>
                Fixed.Bit_Value (After, Position) =
                  Fixed.Bit_Value (Before, Position)),
     Post => Fixed.Prefix_Value (After, Start, Length) =
               Fixed.Prefix_Value (Before, Start, Length),
     Subprogram_Variant => (Decreases => Length);

   procedure Lemma_Prefix_Frame
     (Before, After : Byte_Array;
      Start, Length : Natural)
   is
   begin
      if Length > 0 then
         Lemma_Prefix_Frame (Before, After, Start, Length - 1);
      end if;
   end Lemma_Prefix_Frame;

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

   procedure Write_Code
     (Output : in out Byte_Array;
      Start  : Natural;
      Length : Positive;
      Value  : Natural)
   with
     Pre  => Output'Length <= Fixed.Max_Stream_Bytes
               and then Length <= 9
               and then Start <= 8 * Output'Length
               and then Length <= 8 * Output'Length - Start
               and then Value < Codebooks.Pow2 (Length),
     Post => Fixed.Prefix_Value (Output, Start, Length) = Value
               and then
             (for all Position in 0 .. 8 * Output'Length - 1 =>
                (if Position < Start or else Position >= Start + Length
                 then Fixed.Bit_Value (Output, Position) =
                        Fixed.Bit_Value (Output'Old, Position))),
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
              (for all Position in Start .. Start + Length - 2 =>
                 Fixed.Bit_Value (Output, Position) =
                   Fixed.Bit_Value (Before, Position));
            Lemma_Prefix_Frame (Before, Output, Start, Length - 1);
            Lemma_Prefix_Step (Output, Start, Length);
            pragma Assert (2 * (Value / 2) + Value mod 2 = Value);
         end;
      end if;
   end Write_Code;

   procedure Lemma_Data_Bits_Next
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Position        : Natural)
   with
     Ghost,
     Pre  => Data'Length <= Fixed.Max_Input
               and then Position < Data'Length
               and then Fixed.Token_Boundary (Data, Position)
               and then Covers (Literal_Lengths, Distances, Data)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9),
     Post => Fixed.Token_Boundary
               (Data, Fixed.Next_Position (Data, Position))
               and then Data_Bits
                 (Literal_Lengths, Distances, Data,
                  Fixed.Next_Position (Data, Position)) =
                    Data_Bits
                      (Literal_Lengths, Distances, Data, Position)
                      + Token_Bit_Cost
                          (Literal_Lengths, Distances, Data, Position)
               and then
             (for all Count in Position + 1 ..
                Fixed.Next_Position (Data, Position) - 1 =>
                  not Fixed.Token_Boundary (Data, Count)
                    and then Data_Bits
                      (Literal_Lengths, Distances, Data, Count) =
                        Data_Bits
                          (Literal_Lengths, Distances, Data, Position));

   procedure Lemma_Data_Bits_Next
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Position        : Natural)
   is
      Next : constant Natural := Fixed.Next_Position (Data, Position);
   begin
      Fixed.Lemma_Encoding_Next (Data, Position);
      for Count in Position + 1 .. Next - 1 loop
         pragma Loop_Invariant
           (Data_Bits
              (Literal_Lengths, Distances, Data, Count - 1) =
                Data_Bits
                  (Literal_Lengths, Distances, Data, Position));
         pragma Assert (not Fixed.Token_Boundary (Data, Count));
         pragma Assert
           (Data_Bits (Literal_Lengths, Distances, Data, Count) =
              Data_Bits
                (Literal_Lengths, Distances, Data, Count - 1));
      end loop;
      pragma Assert (Fixed.Plan_Start (Data, Next) = Position);
   end Lemma_Data_Bits_Next;

   procedure Lemma_Data_Bits_Segment
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Position, Count : Natural)
   with
     Ghost,
     Pre  => Data'Length <= Fixed.Max_Input
               and then Position < Count
               and then Count <= Data'Length
               and then Fixed.Token_Boundary (Data, Position)
               and then Fixed.Token_Boundary (Data, Count)
               and then Covers (Literal_Lengths, Distances, Data)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9),
     Post => Fixed.Next_Position (Data, Position) <= Count
               and then Data_Bits
                 (Literal_Lengths, Distances, Data, Position)
                   + Token_Bit_Cost
                       (Literal_Lengths, Distances, Data, Position) <=
                 Data_Bits
                   (Literal_Lengths, Distances, Data, Count),
     Subprogram_Variant => (Decreases => Count - Position);

   procedure Lemma_Data_Bits_Segment
     (Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Position, Count : Natural)
   is
      Next : constant Natural := Fixed.Next_Position (Data, Position);
   begin
      pragma Assert (Next <= Count);
      Lemma_Data_Bits_Next
        (Literal_Lengths, Distances, Data, Position);
      if Next < Count then
         Lemma_Data_Bits_Segment
           (Literal_Lengths, Distances, Data, Next, Count);
      end if;
   end Lemma_Data_Bits_Segment;

   procedure Lemma_Last_Boundary (Data : Byte_Array)
   with
     Ghost,
     Pre  => Data'Length <= Fixed.Max_Input,
     Post => Fixed.Token_Boundary (Data, Data'Length);

   procedure Lemma_Last_Boundary (Data : Byte_Array)
   is
      Index : Natural := 0;
   begin
      while Index < Data'Length loop
         pragma Loop_Invariant (Index <= Data'Length);
         pragma Loop_Invariant (Fixed.Token_Boundary (Data, Index));
         pragma Loop_Variant (Decreases => Data'Length - Index);
         Fixed.Lemma_Encoding_Next (Data, Index);
         Index := Fixed.Next_Position (Data, Index);
      end loop;
   end Lemma_Last_Boundary;

   procedure Lemma_Encodes_Frame
     (Before, After  : Byte_Array;
      Start          : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances      : Codebooks.Codebook;
      Data           : Byte_Array;
      Count          : Natural)
   with
     Ghost,
     Pre  => Before'Length = After'Length
               and then Before'Length <= Fixed.Max_Stream_Bytes
               and then Data'Length <= Fixed.Max_Input
               and then Count <= Data'Length
               and then Fixed.Token_Boundary (Data, Count)
               and then Covers (Literal_Lengths, Distances, Data)
               and then Codebooks.Ready (Literal_Lengths)
               and then Codebooks.Ready (Distances)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9)
               and then Encodes_Prefix
                 (Before, Start, Literal_Lengths, Distances, Data, Count)
               and then
             (for all Position in 0 ..
                Start + Data_Bits
                  (Literal_Lengths, Distances, Data, Count) - 1 =>
                    Fixed.Bit_Value (After, Position) =
                      Fixed.Bit_Value (Before, Position)),
     Post => Encodes_Prefix
               (After, Start, Literal_Lengths, Distances, Data, Count);

   procedure Lemma_Encodes_Frame
     (Before, After  : Byte_Array;
      Start          : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances      : Codebooks.Codebook;
      Data           : Byte_Array;
      Count          : Natural)
   is
   begin
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              (if Fixed.Token_Boundary (Data, J)
               then Token_Encoded
                 (After, Start, Literal_Lengths, Distances, Data, J)));
         if Fixed.Token_Boundary (Data, I) then
            Lemma_Data_Bits_Segment
              (Literal_Lengths, Distances, Data, I, Count);
            pragma Assert
              (Token_Encoded
                 (Before, Start, Literal_Lengths, Distances, Data, I));
            declare
               Token : constant Fixed.Symbol_Result :=
                 Fixed.Selected_Token (Data, I);
               Position : constant Natural :=
                 Start + Data_Bits
                   (Literal_Lengths, Distances, Data, I);
            begin
               if Token.Kind = Fixed.Match then
                  Lemma_Prefix_Frame
                    (Before, After, Position,
                     Codebooks.Length_Of
                       (Literal_Lengths, Length_Symbol (Token.Length)));
                  Lemma_Prefix_Frame
                    (Before, After,
                     Position + Codebooks.Length_Of
                       (Literal_Lengths, Length_Symbol (Token.Length)),
                     Codebooks.Length_Of
                       (Distances, Distance_Symbol (Token.Distance)));
               else
                  Lemma_Prefix_Frame
                    (Before, After, Position,
                     Codebooks.Length_Of
                       (Literal_Lengths,
                        Natural (Data (Data'First + I))));
               end if;
               pragma Assert
                 (Token_Encoded
                    (After, Start, Literal_Lengths, Distances, Data, I));
            end;
         end if;
      end loop;
      pragma Assert
        (for all I in 0 .. Count - 1 =>
           (if Fixed.Token_Boundary (Data, I)
            then Token_Encoded
              (After, Start, Literal_Lengths, Distances, Data, I)));
   end Lemma_Encodes_Frame;

   procedure Lemma_Encodes_Add
     (Output          : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Index, New_Index : Natural)
   with
     Ghost,
     Pre  => Output'Length <= Fixed.Max_Stream_Bytes
               and then Data'Length <= Fixed.Max_Input
               and then Index < Data'Length
               and then Fixed.Token_Boundary (Data, Index)
               and then New_Index = Fixed.Next_Position (Data, Index)
               and then Covers (Literal_Lengths, Distances, Data)
               and then Codebooks.Ready (Literal_Lengths)
               and then Codebooks.Ready (Distances)
               and then Codebooks.Lengths_At_Most (Literal_Lengths, 9)
               and then Codebooks.Lengths_At_Most (Distances, 9)
               and then Encodes_Prefix
                 (Output, Start, Literal_Lengths, Distances, Data, Index)
               and then Token_Encoded
                 (Output, Start, Literal_Lengths, Distances, Data, Index),
     Post => Encodes_Prefix
               (Output, Start, Literal_Lengths, Distances, Data, New_Index);

   procedure Lemma_Encodes_Add
     (Output          : Byte_Array;
      Start           : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances       : Codebooks.Codebook;
      Data            : Byte_Array;
      Index, New_Index : Natural)
   is
   begin
      Lemma_Data_Bits_Next
        (Literal_Lengths, Distances, Data, Index);
      for I in Index .. New_Index - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I =>
              (if Fixed.Token_Boundary (Data, J)
               then Token_Encoded
                 (Output, Start, Literal_Lengths, Distances, Data, J)));
         null;
      end loop;
      pragma Assert
        (Fits_At
           (Output, Start,
            Data_Bits
              (Literal_Lengths, Distances, Data, New_Index), 0));
   end Lemma_Encodes_Add;

   procedure Serialize
     (Data            : in     Byte_Array;
      Literal_Lengths : in     Codebooks.Codebook;
      Distances       : in     Codebooks.Codebook;
      Output          : in out Byte_Array;
      Start           : in     Natural;
      Next_Bit        :    out Natural)
   is
      Bits  : Natural := Start;
      Index : Natural := 0;
      Initial : constant Byte_Array := Output with Ghost;
   begin
      Lemma_Last_Boundary (Data);
      while Index < Data'Length loop
         pragma Loop_Invariant (Index <= Data'Length);
         pragma Loop_Invariant (Fixed.Token_Boundary (Data, Index));
         pragma Loop_Invariant
           (Fixed.Token_Boundary (Data, Data'Length));
         pragma Loop_Invariant
           (Bits = Start + Data_Bits
              (Literal_Lengths, Distances, Data, Index));
         pragma Loop_Invariant
           (Fits_At
              (Output, Start,
               Data_Bits
                 (Literal_Lengths, Distances, Data, Data'Length),
               Codebooks.Length_Of (Literal_Lengths, 256)));
         pragma Loop_Invariant
           (Encodes_Prefix
              (Output, Start, Literal_Lengths, Distances, Data, Index));
         pragma Loop_Invariant
           (for all Position in 0 .. 8 * Output'Length - 1 =>
              (if Position < Start or else Position >= Bits
               then Fixed.Bit_Value (Output, Position) =
                      Fixed.Bit_Value (Initial, Position)));
         pragma Loop_Variant (Decreases => Data'Length - Index);
         declare
            Token     : constant Fixed.Symbol_Result :=
              Fixed.Selected_Token (Data, Index);
            Before    : constant Byte_Array := Output with Ghost;
            Old_Index : constant Natural := Index;
         begin
            Lemma_Data_Bits_Next
              (Literal_Lengths, Distances, Data, Index);
            Lemma_Data_Bits_Segment
              (Literal_Lengths, Distances, Data, Index, Data'Length);
            pragma Assert
              (Fits_At
                 (Output, Start,
                  Data_Bits
                    (Literal_Lengths, Distances, Data, Old_Index),
                  Token_Bit_Cost
                    (Literal_Lengths, Distances, Data, Old_Index)));
            if Token.Kind = Fixed.Match then
               declare
                  L_Symbol : constant Codebooks.Symbol_Index :=
                    Length_Symbol (Token.Length);
                  D_Symbol : constant Codebooks.Symbol_Index :=
                    Distance_Symbol (Token.Distance);
                  L_Length : constant Positive :=
                    Codebooks.Length_Of (Literal_Lengths, L_Symbol);
                  D_Length : constant Positive :=
                    Codebooks.Length_Of (Distances, D_Symbol);
               begin
                  pragma Assert
                    (L_Length + D_Length =
                       Token_Bit_Cost
                         (Literal_Lengths, Distances, Data, Old_Index));
                  Write_Code
                    (Output, Bits, L_Length,
                     Codebooks.Code_Of (Literal_Lengths, L_Symbol));
                  declare
                     Before_Distance : constant Byte_Array := Output with Ghost;
                  begin
                     Write_Code
                       (Output, Bits + L_Length, D_Length,
                        Codebooks.Code_Of (Distances, D_Symbol));
                     Lemma_Prefix_Frame
                       (Before_Distance, Output, Bits, L_Length);
                  end;
                  Lemma_Encodes_Frame
                    (Before, Output, Start, Literal_Lengths, Distances,
                     Data, Old_Index);
                  Lemma_Encodes_Add
                    (Output, Start, Literal_Lengths, Distances,
                     Data, Old_Index, Token.Position);
                  Bits := Bits + L_Length + D_Length;
                  Index := Token.Position;
               end;
            else
               declare
                  Symbol : constant Codebooks.Symbol_Index :=
                    Natural (Data (Data'First + Index));
                  Length : constant Positive :=
                    Codebooks.Length_Of (Literal_Lengths, Symbol);
               begin
                  pragma Assert
                    (Length = Token_Bit_Cost
                       (Literal_Lengths, Distances, Data, Old_Index));
                  Write_Code
                    (Output, Bits, Length,
                     Codebooks.Code_Of (Literal_Lengths, Symbol));
                  Lemma_Encodes_Frame
                    (Before, Output, Start, Literal_Lengths, Distances,
                     Data, Old_Index);
                  Lemma_Encodes_Add
                    (Output, Start, Literal_Lengths, Distances,
                     Data, Old_Index, Old_Index + 1);
                  Bits := Bits + Length;
                  Index := Index + 1;
               end;
            end if;
            pragma Assert
              (Bits = Start + Data_Bits
                 (Literal_Lengths, Distances, Data, Index));
            pragma Assert
              (for all Position in 0 .. 8 * Output'Length - 1 =>
                 (if Position < Start or else Position >= Bits
                  then Fixed.Bit_Value (Output, Position) =
                         Fixed.Bit_Value (Initial, Position)));
         end;
      end loop;

      pragma Assert (Index = Data'Length);
      declare
         Before_End : constant Byte_Array := Output with Ghost;
      begin
         Write_Code
           (Output, Bits, Codebooks.Length_Of (Literal_Lengths, 256),
            Codebooks.Code_Of (Literal_Lengths, 256));
         Lemma_Encodes_Frame
           (Before_End, Output, Start, Literal_Lengths, Distances,
            Data, Data'Length);
      end;
      Next_Bit := Bits + Codebooks.Length_Of (Literal_Lengths, 256);
      pragma Assert
        (for all Position in 0 .. 8 * Output'Length - 1 =>
           (if Position < Start or else Position >= Next_Bit
            then Fixed.Bit_Value (Output, Position) =
                   Fixed.Bit_Value (Initial, Position)));
   end Serialize;

end Inflate.Payload;
