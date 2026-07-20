package body Inflate.Bodies with SPARK_Mode => On is

   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   procedure Lemma_Frame_Indices
     (Before, After : Byte_Array; Consumed : Natural)
   with
     Ghost,
     Pre  => Before'First = After'First
               and then Consumed in 1 .. Before'Length
               and then Consumed <= After'Length
               and then
             (for all I in 0 .. Consumed - 1 =>
                After (After'First + I) = Before (Before'First + I)),
     Post =>
       (for all I in Before'First .. Before'First + (Consumed - 1) =>
          After (I) = Before (I));

   procedure Lemma_Frame_Indices
     (Before, After : Byte_Array; Consumed : Natural) is null;

   procedure Lemma_Stored_Encoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array) is null;

   procedure Lemma_Empty_Reindex
     (Input : Byte_Array;
      CF    : Positive;
      CL    : Natural;
      Data  : Byte_Array;
      DF    : Positive;
      DL    : Natural)
   with
     Ghost,
     Pre  => CF <= CL
               and then CF >= Input'First
               and then CL <= Input'Last
               and then DL = DF - 1
               and then Model.Encodes_Stored
                 (Input, CF, CL, Data, DF, DL),
     Post => Model.Encodes_Stored
               (Input, CF, CL, Data, 1, 0),
     Subprogram_Variant => (Decreases => CL - CF);

   procedure Lemma_Empty_Reindex
     (Input : Byte_Array;
      CF    : Positive;
      CL    : Natural;
      Data  : Byte_Array;
      DF    : Positive;
      DL    : Natural)
   is
      Len : constant Natural := Model.Block_Length (Input, CF);
   begin
      pragma Assert (Len = 0);
      if Input (CF) = 0 then
         Lemma_Empty_Reindex
           (Input, CF + 5 + Len, CL, Data, DF + Len, DL);
      end if;
   end Lemma_Empty_Reindex;

   procedure Lemma_Stored_Empty_Encoding
     (Input       : Byte_Array;
      Consumed    : Natural;
      Before_Data : Byte_Array;
      DF          : Positive;
      DL          : Natural;
      Data        : Byte_Array)
   is
   begin
      Lemma_Empty_Reindex
        (Input, Input'First, Input'First + (Consumed - 1),
         Before_Data, DF, DL);
      Model.Lemma_Encodes_Frame
        (Input, Input,
         Input'First, Input'First + (Consumed - 1),
         Before_Data, Data, 1, 0);
      Lemma_Stored_Encoding (Input, Consumed, Data);
   end Lemma_Stored_Empty_Encoding;

   procedure Lemma_Fixed_Encoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array) is null;

   procedure Lemma_Dynamic_Encoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array)
   is
   begin
      Dynamic.Lemma_Encoding_Decodes (Input, Consumed, Data);
   end Lemma_Dynamic_Encoding;

   procedure Lemma_Dynamic_Decoding
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array) is null;

   procedure Lemma_Encoding_Recognized
     (Input    : Byte_Array;
      Consumed : Natural;
      Data     : Byte_Array)
   is
      DF : constant Positive :=
        (if Data'Length > 0 then Data'First else 1);
      DL : constant Natural :=
        (if Data'Length > 0 then Data'Last else 0);
   begin
      if Input'Length >= 5
        and then Model.Encodes_Stored
          (Input, Input'First, Input'First + (Consumed - 1),
           Data, DF, DL)
      then
         Model.Lemma_Encodes_End
           (Input, Input'First, Input'First + (Consumed - 1),
            Data, DF, DL, Input'Last);
      elsif Fixed.Is_Encoding (Input, Consumed, Data) then
         pragma Assert (Fixed.Is_Encoding (Input, Consumed, Data));
         Fixed.Lemma_Encoding_Analyzes (Input, Consumed, Data);
         --  A fixed block cannot also be a stored image: fixed BTYPE has its
         --  second stream bit set, whereas a stored image starts with a byte
         --  whose only possible set bit is BFINAL.
         pragma Assert
           (not (Input'Length >= 5
                 and then Model.Stored_Stream_End
                   (Input, Input'First, Input'Last) > 0));
      else
         pragma Assert (Dynamic.Decodes (Input, Consumed, Data));
         pragma Assert
           (not (Input'Length >= 5
                 and then Model.Stored_Stream_End
                   (Input, Input'First, Input'Last) > 0));
         pragma Assert (not Fixed.Analyze (Input).Valid);
      end if;
   end Lemma_Encoding_Recognized;

   procedure Lemma_Encoding_Frame
     (Before, After : Byte_Array;
      Consumed      : Natural;
      Data          : Byte_Array)
   is
      DF : constant Positive :=
        (if Data'Length > 0 then Data'First else 1);
      DL : constant Natural :=
        (if Data'Length > 0 then Data'Last else 0);
   begin
      if Before'Length >= 5
        and then Model.Encodes_Stored
          (Before, Before'First, Before'First + (Consumed - 1),
           Data, DF, DL)
      then
         Lemma_Frame_Indices (Before, After, Consumed);
         Model.Lemma_Encodes_Frame
           (Before, After,
            Before'First, Before'First + (Consumed - 1),
            Data, Data, DF, DL);
         if After'Length <= Fixed.Max_Stream_Bytes then
            pragma Assert (Fixed.Bit_Value (After, 2) = 0);
         end if;
      elsif Fixed.Is_Encoding (Before, Consumed, Data) then
         pragma Assert (Fixed.Is_Encoding (Before, Consumed, Data));
         Fixed.Lemma_Encoding_Frame (Before, After, Consumed, Data);
         pragma Assert (Fixed.Bit_Value (After, 1) = 1);
      else
         pragma Assert (Dynamic.Decodes (Before, Consumed, Data));
         Dynamic.Lemma_Decoding_Frame (Before, After, Consumed, Data);
      end if;
   end Lemma_Encoding_Frame;

   procedure Lemma_Encoding_Functional
     (Input       : Byte_Array;
      Consumed    : Natural;
      Left, Right : Byte_Array)
   is
      LF : constant Positive :=
        (if Left'Length > 0 then Left'First else 1);
      LL : constant Natural :=
        (if Left'Length > 0 then Left'Last else 0);
      RF : constant Positive :=
        (if Right'Length > 0 then Right'First else 1);
      RL : constant Natural :=
        (if Right'Length > 0 then Right'Last else 0);
   begin
      if Input'Length >= 5
        and then Model.Encodes_Stored
          (Input, Input'First, Input'First + (Consumed - 1),
           Left, LF, LL)
      then
         --  The fixed alternative is disjoint from the stored header, so the
         --  right-hand witness must use the same stored relation.
         if Input'Length <= Fixed.Max_Stream_Bytes then
            pragma Assert (Input (Input'First) <= 1);
            pragma Assert (Fixed.Bit_Value (Input, 1) = 0);
            pragma Assert (not Fixed.Fixed_Header (Input));
            pragma Assert (Fixed.Bit_Value (Input, 2) = 0);
         end if;
         pragma Assert
           (Model.Encodes_Stored
              (Input, Input'First, Input'First + (Consumed - 1),
               Right, RF, RL));
         Model.Lemma_Encodes_Functional
           (Input, Input'First, Input'First + (Consumed - 1),
            Left, LF, LL, Right, RF, RL);
         pragma Assert (not Dynamic.Decodes (Input, Consumed, Right));
      elsif Fixed.Is_Encoding (Input, Consumed, Left) then
         pragma Assert (Fixed.Is_Encoding (Input, Consumed, Left));
         pragma Assert
           (not (Input'Length >= 5
                 and then Model.Encodes_Stored
                   (Input, Input'First, Input'First + (Consumed - 1),
                    Right, RF, RL)));
         pragma Assert (Fixed.Bit_Value (Input, 1) = 1);
         pragma Assert (not Dynamic.Decodes (Input, Consumed, Right));
         pragma Assert (Fixed.Is_Encoding (Input, Consumed, Right));
         Fixed.Lemma_Encoding_Functional
           (Input, Consumed, Left, Right);
      else
         pragma Assert (Dynamic.Decodes (Input, Consumed, Left));
         pragma Assert (Fixed.Bit_Value (Input, 2) = 1);
         pragma Assert
           (not (Input'Length >= 5
                 and then Model.Encodes_Stored
                   (Input, Input'First, Input'First + (Consumed - 1),
                    Right, RF, RL)));
         pragma Assert (Fixed.Bit_Value (Input, 1) = 0);
         pragma Assert (not Fixed.Is_Encoding (Input, Consumed, Right));
         pragma Assert (Dynamic.Decodes (Input, Consumed, Right));
         Dynamic.Lemma_Decoding_Functional
           (Input, Consumed, Left, Right);
      end if;
   end Lemma_Encoding_Functional;

end Inflate.Bodies;
