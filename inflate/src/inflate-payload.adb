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
     Pre  => Before'Length <= Fixed.Max_Stream_Bytes
               and then After'Length <= Fixed.Max_Stream_Bytes
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
               and then Start + Data_Bits
                 (Literal_Lengths, Distances, Data, Count) <=
                   8 * After'Length
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

   procedure Lemma_Payload_Frame
     (Before, After  : Byte_Array;
      Start          : Natural;
      Literal_Lengths : Codebooks.Codebook;
      Distances      : Codebooks.Codebook;
      Data           : Byte_Array)
   is
      Payload_End : constant Natural :=
        Start + Data_Bits
          (Literal_Lengths, Distances, Data, Data'Length);
   begin
      Lemma_Last_Boundary (Data);
      Lemma_Encodes_Frame
        (Before, After, Start, Literal_Lengths, Distances,
         Data, Data'Length);
      Lemma_Prefix_Frame
        (Before, After, Payload_End,
         Codebooks.Length_Of (Literal_Lengths, 256));
   end Lemma_Payload_Frame;

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

   procedure Lemma_Token_Cost_From_Book_Fields
     (Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array;
      Position                          : Natural)
   with
     Ghost,
     Pre  => Data'Length <= Fixed.Max_Input
               and then Position < Data'Length
               and then Fixed.Token_Boundary (Data, Position)
               and then Before_Literals.Kind = Codebooks.Canonical
               and then After_Literals.Kind = Codebooks.Canonical
               and then Before_Distances.Kind = Codebooks.Canonical
               and then After_Distances.Kind = Codebooks.Canonical
               and then Before_Literals.Lengths = After_Literals.Lengths
               and then Before_Distances.Lengths = After_Distances.Lengths
               and then Covers
                 (Before_Literals, Before_Distances, Data)
               and then Covers
                 (After_Literals, After_Distances, Data)
               and then Codebooks.Lengths_At_Most (Before_Literals, 9)
               and then Codebooks.Lengths_At_Most (After_Literals, 9)
               and then Codebooks.Lengths_At_Most (Before_Distances, 9)
               and then Codebooks.Lengths_At_Most (After_Distances, 9),
     Post => Token_Bit_Cost
               (Before_Literals, Before_Distances, Data, Position) =
               Token_Bit_Cost
                 (After_Literals, After_Distances, Data, Position);

   procedure Lemma_Token_Cost_From_Book_Fields
     (Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array;
      Position                          : Natural)
   is
   begin
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Literals, After_Literals);
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Distances, After_Distances);
      pragma Assert
        (Token_Bit_Cost
           (Before_Literals, Before_Distances, Data, Position) =
         Token_Bit_Cost
           (After_Literals, After_Distances, Data, Position));
   end Lemma_Token_Cost_From_Book_Fields;

   procedure Lemma_Data_Bits_From_Book_Fields
     (Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array;
      Count                             : Natural)
   with
     Ghost,
     Pre  => Data'Length <= Fixed.Max_Input
               and then Count <= Data'Length
               and then Before_Literals.Kind = Codebooks.Canonical
               and then After_Literals.Kind = Codebooks.Canonical
               and then Before_Distances.Kind = Codebooks.Canonical
               and then After_Distances.Kind = Codebooks.Canonical
               and then Before_Literals.Lengths = After_Literals.Lengths
               and then Before_Distances.Lengths = After_Distances.Lengths
               and then Covers
                 (Before_Literals, Before_Distances, Data)
               and then Covers
                 (After_Literals, After_Distances, Data)
               and then Codebooks.Lengths_At_Most (Before_Literals, 9)
               and then Codebooks.Lengths_At_Most (After_Literals, 9)
               and then Codebooks.Lengths_At_Most (Before_Distances, 9)
               and then Codebooks.Lengths_At_Most (After_Distances, 9),
     Post => Data_Bits
               (Before_Literals, Before_Distances, Data, Count) =
               Data_Bits (After_Literals, After_Distances, Data, Count),
     Subprogram_Variant => (Decreases => Count);

   procedure Lemma_Data_Bits_From_Book_Fields
     (Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array;
      Count                             : Natural)
   is
   begin
      if Count > 0 then
         if Fixed.Token_Boundary (Data, Count) then
            Lemma_Data_Bits_From_Book_Fields
              (Before_Literals, Before_Distances,
               After_Literals, After_Distances,
               Data, Fixed.Plan_Start (Data, Count));
            Lemma_Token_Cost_From_Book_Fields
              (Before_Literals, Before_Distances,
               After_Literals, After_Distances,
               Data, Fixed.Plan_Start (Data, Count));
         else
            Lemma_Data_Bits_From_Book_Fields
              (Before_Literals, Before_Distances,
               After_Literals, After_Distances, Data, Count - 1);
         end if;
      end if;
   end Lemma_Data_Bits_From_Book_Fields;

   procedure Lemma_Token_Encoded_From_Book_Fields
     (Output                            : Byte_Array;
      Start                             : Natural;
      Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array;
      Position                          : Natural)
   with
     Ghost,
     Pre  => Output'Length <= Fixed.Max_Stream_Bytes
               and then Data'Length <= Fixed.Max_Input
               and then Position < Data'Length
               and then Fixed.Token_Boundary (Data, Position)
               and then Before_Literals.Kind = Codebooks.Canonical
               and then After_Literals.Kind = Codebooks.Canonical
               and then Before_Distances.Kind = Codebooks.Canonical
               and then After_Distances.Kind = Codebooks.Canonical
               and then Before_Literals.Lengths = After_Literals.Lengths
               and then Before_Literals.Counts = After_Literals.Counts
               and then Before_Distances.Lengths = After_Distances.Lengths
               and then Before_Distances.Counts = After_Distances.Counts
               and then Codebooks.Ready (Before_Literals)
               and then Codebooks.Ready (After_Literals)
               and then Codebooks.Ready (Before_Distances)
               and then Codebooks.Ready (After_Distances)
               and then Codebooks.Lengths_At_Most (Before_Literals, 9)
               and then Codebooks.Lengths_At_Most (After_Literals, 9)
               and then Codebooks.Lengths_At_Most (Before_Distances, 9)
               and then Codebooks.Lengths_At_Most (After_Distances, 9)
               and then Covers
                 (Before_Literals, Before_Distances, Data)
               and then Covers
                 (After_Literals, After_Distances, Data)
               and then Token_Encoded
                 (Output, Start,
                  Before_Literals, Before_Distances, Data, Position),
     Post => Token_Encoded
               (Output, Start,
                After_Literals, After_Distances, Data, Position);

   procedure Lemma_Token_Encoded_From_Book_Fields
     (Output                            : Byte_Array;
      Start                             : Natural;
      Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array;
      Position                          : Natural)
   is
      Token : constant Fixed.Symbol_Result :=
        Fixed.Selected_Token (Data, Position);
   begin
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Literals, After_Literals);
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Distances, After_Distances);
      Lemma_Data_Bits_From_Book_Fields
        (Before_Literals, Before_Distances,
         After_Literals, After_Distances, Data, Position);
      if Token.Kind = Fixed.Match then
         Codebooks.Lemma_Code_Of_From_Fields
           (Before_Literals, After_Literals,
            Length_Symbol (Token.Length));
         Codebooks.Lemma_Code_Of_From_Fields
           (Before_Distances, After_Distances,
            Distance_Symbol (Token.Distance));
      else
         Codebooks.Lemma_Code_Of_From_Fields
           (Before_Literals, After_Literals,
            Natural (Token.Value));
      end if;
      pragma Assert
        (Token_Encoded
           (Output, Start,
            After_Literals, After_Distances, Data, Position));
   end Lemma_Token_Encoded_From_Book_Fields;

   pragma Assertion_Policy (Ghost => Ignore);
   procedure Lemma_Covers_From_Lengths
     (Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array)
   is
   begin
      pragma Assert
        (Codebooks.Length_Of (After_Literals, 256) > 0);
      for I in 0 .. Data'Length - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              (if Fixed.Token_Boundary (Data, J)
               then
                 (if Fixed.Selected_Token (Data, J).Kind = Fixed.Match
                  then Codebooks.Length_Of
                         (After_Literals,
                          Length_Symbol
                            (Fixed.Selected_Token (Data, J).Length)) > 0
                       and then Codebooks.Length_Of
                         (After_Distances,
                          Distance_Symbol
                            (Fixed.Selected_Token (Data, J).Distance)) > 0
                  else Codebooks.Length_Of
                         (After_Literals,
                          Natural (Data (Data'First + J))) > 0)));
         if Fixed.Token_Boundary (Data, I) then
            if Fixed.Selected_Token (Data, I).Kind = Fixed.Match then
               pragma Assert
                 (Codebooks.Length_Of
                    (Before_Literals,
                     Length_Symbol
                       (Fixed.Selected_Token (Data, I).Length)) > 0);
               pragma Assert
                 (Codebooks.Length_Of
                    (Before_Distances,
                     Distance_Symbol
                       (Fixed.Selected_Token (Data, I).Distance)) > 0);
            else
               pragma Assert
                 (Codebooks.Length_Of
                    (Before_Literals,
                     Natural (Data (Data'First + I))) > 0);
            end if;
         end if;
      end loop;
   end Lemma_Covers_From_Lengths;

   procedure Lemma_Encoding_From_Book_Fields
     (Output                            : Byte_Array;
      Start                             : Natural;
      Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array)
   is
   begin
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Literals, After_Literals);
      Codebooks.Lemma_Length_Of_From_Fields
        (Before_Distances, After_Distances);
      Lemma_Data_Bits_From_Book_Fields
        (Before_Literals, Before_Distances,
         After_Literals, After_Distances, Data, Data'Length);
      for I in 0 .. Data'Length - 1 loop
         pragma Loop_Invariant
           (for all J in 0 .. I - 1 =>
              (if Fixed.Token_Boundary (Data, J)
               then Token_Encoded
                 (Output, Start,
                  After_Literals, After_Distances, Data, J)));
         if Fixed.Token_Boundary (Data, I) then
            pragma Assert
              (Token_Encoded
                 (Output, Start,
                  Before_Literals, Before_Distances, Data, I));
            Lemma_Token_Encoded_From_Book_Fields
              (Output, Start,
               Before_Literals, Before_Distances,
               After_Literals, After_Distances, Data, I);
         end if;
      end loop;
      pragma Assert
        (Encodes_Prefix
           (Output, Start,
            After_Literals, After_Distances, Data, Data'Length));
      Codebooks.Lemma_Code_Of_From_Fields
        (Before_Literals, After_Literals, 256);
   end Lemma_Encoding_From_Book_Fields;

   procedure Lemma_Data_Bits_Equal_From_Book_Fields
     (Before_Literals, Before_Distances : Codebooks.Codebook;
      After_Literals, After_Distances   : Codebooks.Codebook;
      Data                              : Byte_Array;
      Count                             : Natural)
   is
   begin
      Lemma_Data_Bits_From_Book_Fields
        (Before_Literals, Before_Distances,
         After_Literals, After_Distances, Data, Count);
   end Lemma_Data_Bits_Equal_From_Book_Fields;

end Inflate.Payload;
