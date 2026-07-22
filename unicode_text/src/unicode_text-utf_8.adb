package body Unicode_Text.UTF_8
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;

   function Valid_From (S : String; Byte_Offset : Natural) return Boolean
   is (Byte_Offset = S'Length
       or else
         (Valid_At (S, Byte_Offset)
          and then
            Valid_From (S, Byte_Offset + Sequence_Width_At (S, Byte_Offset))))
   with
     Pre                => Byte_Offset <= S'Length,
     Subprogram_Variant => (Decreases => S'Length - Byte_Offset);

   function Model_From (S : String; Byte_Offset : Natural) return Text
   is (if Byte_Offset = S'Length
       then Scalar_Sequences.Empty_Sequence
       else
         Scalar_Sequences.Add
           (Model_From
              (S, Byte_Offset + Natural (Decode_One (S, Byte_Offset).Width)),
            1,
            Decode_One (S, Byte_Offset).Value))
   with
     Ghost,
     Pre                =>
       Byte_Offset <= S'Length and then Valid_From (S, Byte_Offset),
     Post               =>
       Scalar_Sequences.Length (Model_From'Result)
       <= To_Big_Integer (S'Length - Byte_Offset),
     Subprogram_Variant => (Decreases => S'Length - Byte_Offset);

   function Encode_One (Value : Scalar_Value) return String is
   begin
      if Value <= 16#007F# then
         return [1 => Character'Val (Value)];
      elsif Value <= 16#07FF# then
         return
           [Character'Val (16#C0# + Value / 64),
            Character'Val (16#80# + Value mod 64)];
      elsif Value <= 16#FFFF# then
         return
           [Character'Val (16#E0# + Value / 4_096),
            Character'Val (16#80# + (Value / 64) mod 64),
            Character'Val (16#80# + Value mod 64)];
      else
         return
           [Character'Val (16#F0# + Value / 262_144),
            Character'Val (16#80# + (Value / 4_096) mod 64),
            Character'Val (16#80# + (Value / 64) mod 64),
            Character'Val (16#80# + Value mod 64)];
      end if;
   end Encode_One;

   function Decode_One (S : String; Byte_Offset : Natural) return Decoded_Unit
   is
      B0    : constant Octet := Octet_At (S, Byte_Offset);
      Width : constant Natural := Sequence_Width_At (S, Byte_Offset);
   begin
      if Width = 1 then
         return (Value => Scalar_Value (B0), Width => 1);
      elsif Width = 2 then
         declare
            B1 : constant Octet := Octet_At (S, Byte_Offset + 1);
            V  : constant Natural := (B0 - 16#C0#) * 64 + (B1 - 16#80#);
         begin
            pragma Assert (V in 16#80# .. 16#7FF#);
            return (Value => Scalar_Value (V), Width => 2);
         end;
      elsif Width = 3 then
         declare
            B1 : constant Octet := Octet_At (S, Byte_Offset + 1);
            B2 : constant Octet := Octet_At (S, Byte_Offset + 2);
            V  : constant Natural :=
              (B0 - 16#E0#) * 4_096 + (B1 - 16#80#) * 64 + (B2 - 16#80#);
         begin
            pragma Assert (V in 16#800# .. 16#D7FF# | 16#E000# .. 16#FFFF#);
            return (Value => Scalar_Value (V), Width => 3);
         end;
      else
         declare
            B1 : constant Octet := Octet_At (S, Byte_Offset + 1);
            B2 : constant Octet := Octet_At (S, Byte_Offset + 2);
            B3 : constant Octet := Octet_At (S, Byte_Offset + 3);
            V  : constant Natural :=
              (B0 - 16#F0#) * 262_144 + (B1 - 16#80#) * 4_096
              + (B2 - 16#80#) * 64
              + (B3 - 16#80#);
         begin
            pragma Assert (V in 16#1_0000# .. 16#10_FFFF#);
            return (Value => Scalar_Value (V), Width => 4);
         end;
      end if;
   end Decode_One;

   function Is_Valid_UTF_8 (S : String) return Boolean
   is (Valid_From (S, 0));

   function First_Error (S : String; Byte_Offset : Natural) return Natural
   is (if not Valid_At (S, Byte_Offset)
       then Byte_Offset
       else First_Error (S, Byte_Offset + Sequence_Width_At (S, Byte_Offset)))
   with
     Pre                =>
       Byte_Offset < S'Length and then not Valid_From (S, Byte_Offset),
     Post               =>
       First_Error'Result < S'Length
       and then not Valid_At (S, First_Error'Result),
     Subprogram_Variant => (Decreases => S'Length - Byte_Offset);

   function Validate (S : String) return Validation_Result is
   begin
      if Is_Valid_UTF_8 (S) then
         return (Valid => True, Error_Offset => S'Length);
      else
         return (Valid => False, Error_Offset => First_Error (S, 0));
      end if;
   end Validate;

   function Is_Encoding (S : String; Value : Text) return Boolean
   is (Value = Model_From (S, 0));

   function Model (S : String) return Text is
   begin
      return Model_From (S, 0);
   end Model;

   procedure Lemma_Encoding_Unique (S : String; Left, Right : Text) is null;

   procedure Lemma_Encode_Decode (Value : Scalar_Value) is
      Encoded : constant String := Encode_One (Value)
      with Ghost;
      Unit    : constant Decoded_Unit := Decode_One (Encoded, 0)
      with Ghost;
      Empty   : constant Text := Scalar_Sequences.Empty_Sequence
      with Ghost;
      One     : constant Text := Scalar_Sequences.Add (Empty, Value)
      with Ghost;
      Front   : constant Text := Scalar_Sequences.Add (Empty, 1, Value)
      with Ghost;
   begin
      pragma Assert (Valid_At (Encoded, 0));
      pragma Assert (Unit.Value = Value);
      pragma Assert (Unit.Width = Encoding_Width (Value));
      pragma Assert (Natural (Unit.Width) = Encoded'Length);
      pragma Assert (Model_From (Encoded, Encoded'Length) = Empty);
      pragma Assert (Model_From (Encoded, 0) = Front);
      pragma Assert (Is_Encoding (Encoded, Model (Encoded)));
      Lemma_Singleton_Placement (Value);
      pragma Assert (Model (Encoded) = One);
      Lemma_Add_Is_Append (Empty, Value);
   end Lemma_Encode_Decode;

end Unicode_Text.UTF_8;
