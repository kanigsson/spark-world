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
     Ghost => Static,
     Pre                =>
       Byte_Offset <= S'Length and then Valid_From (S, Byte_Offset),
     Post               =>
       (Static =>
          Scalar_Sequences.Length (Model_From'Result)
          <= To_Big_Integer (S'Length - Byte_Offset)),
     Subprogram_Variant => (Decreases => S'Length - Byte_Offset);

   function Length_From (S : String; Byte_Offset : Natural) return Natural
   is (if Byte_Offset = S'Length
       then 0
       else
         1
         + Length_From
             (S, Byte_Offset + Sequence_Width_At (S, Byte_Offset)))
   with
     Pre                =>
       Byte_Offset <= S'Length and then Valid_From (S, Byte_Offset),
     Post               =>
       (Runtime => Length_From'Result <= S'Length - Byte_Offset,
        Static  =>
          To_Big_Integer (Length_From'Result)
          = Scalar_Sequences.Length (Model_From (S, Byte_Offset))
          and then
            To_Big_Integer (S'Length - Byte_Offset)
            <= 4 * To_Big_Integer (Length_From'Result)),
     Subprogram_Variant => (Decreases => S'Length - Byte_Offset);

   function Element_From
     (S : String; Byte_Offset : Natural; Index : Positive)
      return Scalar_Value
   is (if Index = 1
       then Decode_One (S, Byte_Offset).Value
       else
         Element_From
           (S,
            Byte_Offset + Sequence_Width_At (S, Byte_Offset),
            Index - 1))
   with
     Pre                =>
       Byte_Offset < S'Length
       and then Valid_From (S, Byte_Offset)
       and then Index <= Length_From (S, Byte_Offset),
     Post               =>
       (Static =>
          Element_From'Result
          = Scalar_Sequences.Get
              (Model_From (S, Byte_Offset), To_Big_Integer (Index))),
     Subprogram_Variant => (Decreases => Index);

   function Character_At (S : String; Offset : Natural) return Character
   is (S (S'First + Offset))
   with Pre => Offset < S'Length;

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

   function Code_Point_Length (S : String) return Natural
   is (Length_From (S, 0));

   function Element
     (S : String; Index : Positive) return Scalar_Value
   is (Element_From (S, 0, Index));

   function First (S : String) return Cursor_Type
   is ((Offset => 0, Index => 1));

   function Is_Valid_Cursor
     (S : String; Cursor : Cursor_Type) return Boolean
   is (Is_Valid_UTF_8 (S)
       and then Cursor.Offset <= S'Length
       and then Valid_From (S, Cursor.Offset)
       and then
         Cursor_Index_Conversions.To_Big_Integer (Cursor.Index)
         <= Scalar_Sequences.Length (Model (S)) + 1
       and then
         Scalar_Sequences.Length (Model_From (S, Cursor.Offset))
         = Scalar_Sequences.Length (Model (S))
           - (Cursor_Index_Conversions.To_Big_Integer (Cursor.Index) - 1)
       and then
         Is_Slice
           (Source => Model (S),
            First  => Cursor_Index_Conversions.To_Big_Integer (Cursor.Index),
            Count  => Scalar_Sequences.Length (Model_From (S, Cursor.Offset)),
            Result => Model_From (S, Cursor.Offset)));

   function Has_Element (S : String; Cursor : Cursor_Type) return Boolean is
   begin
      if Cursor.Offset < S'Length then
         pragma Assert (Valid_At (S, Cursor.Offset));
         pragma Assert
           (Static =>
              Scalar_Sequences.Length (Model_From (S, Cursor.Offset)) > 0);
         pragma Assert
           (Static =>
              Cursor_Index_Conversions.To_Big_Integer (Cursor.Index)
              <= Scalar_Sequences.Length (Model (S)));
         return True;
      else
         pragma Assert (Cursor.Offset = S'Length);
         pragma Assert
           (Static =>
              Scalar_Sequences.Length (Model_From (S, Cursor.Offset)) = 0);
         pragma Assert
           (Static =>
              Cursor_Index_Conversions.To_Big_Integer (Cursor.Index)
              = Scalar_Sequences.Length (Model (S)) + 1);
         return False;
      end if;
   end Has_Element;

   procedure Next
     (S : String; Cursor : in out Cursor_Type; Value : out Scalar_Value)
   is
      Unit : constant Decoded_Unit := Decode_One (S, Cursor.Offset);
   begin
      Value := Unit.Value;
      Cursor.Offset := Cursor.Offset + Natural (Unit.Width);
      Cursor.Index := Cursor.Index + 1;
   end Next;

   function Is_Prefix (Prefix, Whole : String) return Boolean is
      Prefix_Length : constant Natural := Code_Point_Length (Prefix);
      Whole_Length  : constant Natural := Code_Point_Length (Whole);
   begin
      if Prefix_Length > Whole_Length then
         return False;
      end if;

      declare
         Prefix_Cursor : Cursor_Type := First (Prefix);
         Whole_Cursor  : Cursor_Type := First (Whole);
         Prefix_Value  : Scalar_Value;
         Whole_Value   : Scalar_Value;
      begin
         while Has_Element (Prefix, Prefix_Cursor) loop
            pragma Loop_Invariant
              (Static => Is_Valid_Cursor (Prefix, Prefix_Cursor));
            pragma Loop_Invariant
              (Static => Is_Valid_Cursor (Whole, Whole_Cursor));
            pragma Loop_Invariant
              (Model_Index (Prefix_Cursor) = Model_Index (Whole_Cursor));
            pragma Loop_Invariant
              (Static =>
                 (for all I in Model (Prefix) =>
                    (if I
                        < Cursor_Index_Conversions.To_Big_Integer
                            (Model_Index (Prefix_Cursor))
                     then
                       Scalar_Sequences.Get (Model (Prefix), I)
                       = Scalar_Sequences.Get (Model (Whole), I))));
            pragma Loop_Variant (Decreases => Prefix'Length - Byte_Offset (Prefix_Cursor));

            Next (Prefix, Prefix_Cursor, Prefix_Value);
            Next (Whole, Whole_Cursor, Whole_Value);
            if Prefix_Value /= Whole_Value then
               return False;
            end if;
         end loop;
         return True;
      end;
   end Is_Prefix;

   function Is_Suffix (Suffix, Whole : String) return Boolean is
      Suffix_Length : constant Natural := Code_Point_Length (Suffix);
      Whole_Length  : constant Natural := Code_Point_Length (Whole);
   begin
      if Suffix_Length > Whole_Length then
         return False;
      end if;

      declare
         Difference    : constant Natural := Whole_Length - Suffix_Length;
         Suffix_Cursor : Cursor_Type := First (Suffix);
         Whole_Cursor  : Cursor_Type := First (Whole);
         Suffix_Value  : Scalar_Value;
         Whole_Value   : Scalar_Value;
      begin
         if Difference > 0 then
            for Ignored in 1 .. Difference loop
               pragma Loop_Invariant
                 (Static => Is_Valid_Cursor (Whole, Whole_Cursor));
               pragma Loop_Invariant
                 (Model_Index (Whole_Cursor) = Cursor_Index (Ignored));
               declare
                  Ignored_Value : Scalar_Value;
               begin
                  Next (Whole, Whole_Cursor, Ignored_Value);
                  pragma Assert (Ignored_Value in Scalar_Value);
               end;
            end loop;
         end if;

         while Has_Element (Suffix, Suffix_Cursor) loop
            pragma Loop_Invariant
              (Static => Is_Valid_Cursor (Suffix, Suffix_Cursor));
            pragma Loop_Invariant
              (Static => Is_Valid_Cursor (Whole, Whole_Cursor));
            pragma Loop_Invariant
              (Cursor_Index_Conversions.To_Big_Integer
                 (Model_Index (Whole_Cursor))
               = Cursor_Index_Conversions.To_Big_Integer
                   (Model_Index (Suffix_Cursor))
                 + To_Big_Integer (Difference));
            pragma Loop_Invariant
              (Static =>
                 (for all I in Model (Suffix) =>
                    (if I
                        < Cursor_Index_Conversions.To_Big_Integer
                            (Model_Index (Suffix_Cursor))
                     then
                       Scalar_Sequences.Get (Model (Suffix), I)
                       = Scalar_Sequences.Get
                           (Model (Whole), To_Big_Integer (Difference) + I))));
            pragma Loop_Variant (Decreases => Suffix'Length - Byte_Offset (Suffix_Cursor));

            Next (Suffix, Suffix_Cursor, Suffix_Value);
            Next (Whole, Whole_Cursor, Whole_Value);
            if Suffix_Value /= Whole_Value then
               return False;
            end if;
         end loop;
         return True;
      end;
   end Is_Suffix;

   function Compare (Left, Right : String) return Comparison_Result is
      Left_Cursor  : Cursor_Type := First (Left);
      Right_Cursor : Cursor_Type := First (Right);
      Left_Value   : Scalar_Value;
      Right_Value  : Scalar_Value;
   begin
      while Has_Element (Left, Left_Cursor)
        and then Has_Element (Right, Right_Cursor)
      loop
         pragma Loop_Invariant
           (Static => Is_Valid_Cursor (Left, Left_Cursor));
         pragma Loop_Invariant
           (Static => Is_Valid_Cursor (Right, Right_Cursor));
         pragma Loop_Invariant
           (Model_Index (Left_Cursor) = Model_Index (Right_Cursor));
         pragma Loop_Invariant
           (Static =>
              (for all I in Model (Left) =>
                 (if I
                     < Cursor_Index_Conversions.To_Big_Integer
                         (Model_Index (Left_Cursor))
                  then
                    Scalar_Sequences.Get (Model (Left), I)
                    = Scalar_Sequences.Get (Model (Right), I))));
         pragma Loop_Variant (Decreases => Left'Length - Byte_Offset (Left_Cursor));

         declare
            Current_Index : constant Big_Positive :=
              Cursor_Index_Conversions.To_Big_Integer
                (Model_Index (Left_Cursor))
            with Ghost => Static;
         begin
            Next (Left, Left_Cursor, Left_Value);
            Next (Right, Right_Cursor, Right_Value);
            if Left_Value < Right_Value then
               pragma Assert
                 (Static =>
                    (for all J in Model (Left) =>
                       (if J < Current_Index
                        then
                          Scalar_Sequences.Get (Model (Left), J)
                          = Scalar_Sequences.Get (Model (Right), J))));
               pragma Assert
                 (Static =>
                    Scalar_Sequences.Get (Model (Left), Current_Index)
                    < Scalar_Sequences.Get (Model (Right), Current_Index));
               pragma Assert
                 (Static =>
                    Is_Lexicographically_Less (Model (Left), Model (Right)));
               return Less;
            elsif Left_Value > Right_Value then
               pragma Assert
                 (Static =>
                    Is_Lexicographically_Less (Model (Right), Model (Left)));
               return Greater;
            end if;
         end;
      end loop;

      if Has_Element (Right, Right_Cursor) then
         pragma Assert
           (Static =>
              Unicode_Text.Models.Is_Prefix (Model (Left), Model (Right)));
         pragma Assert
           (Static =>
              Scalar_Sequences.Length (Model (Left))
              < Scalar_Sequences.Length (Model (Right)));
         pragma Assert
           (Static =>
              Is_Lexicographically_Less (Model (Left), Model (Right)));
         return Less;
      elsif Has_Element (Left, Left_Cursor) then
         pragma Assert
           (Static =>
              Is_Lexicographically_Less (Model (Right), Model (Left)));
         return Greater;
      else
         return Equal;
      end if;
   end Compare;

   procedure Lemma_Decode_Encode_At (S : String; Offset : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    => Offset < S'Length and then Valid_At (S, Offset),
     Post   =>
       Decode_One (S, Offset).Width
       = Encoding_Width (Decode_One (S, Offset).Value)
       and then
         (for all I in Natural range
            0 .. Natural (Decode_One (S, Offset).Width) - 1 =>
              Octet_At (S, Offset + I)
              = Octet_At (Encode_One (Decode_One (S, Offset).Value), I))
       and then
         (for all I in Natural range
            0 .. Natural (Decode_One (S, Offset).Width) - 1 =>
              S (S'First + Offset + I)
              = Encode_One (Decode_One (S, Offset).Value) (1 + I))
   is
      Unit    : constant Decoded_Unit := Decode_One (S, Offset)
      with Ghost => Static;
      Encoded : constant String := Encode_One (Unit.Value)
      with Ghost => Static;
   begin
      case Unit.Width is
         when 1 =>
            pragma Assert (Static => Unit.Value <= 16#7F#);
            pragma Assert (Static => Unit.Width = Encoding_Width (Unit.Value));
            pragma Assert (Static => Octet_At (S, Offset) = Octet_At (Encoded, 0));
            pragma Assert (Static => S (S'First + Offset) = Encoded (1));
         when 2 =>
            pragma Assert (Static => Unit.Value in 16#80# .. 16#7FF#);
            pragma Assert (Static => Unit.Width = Encoding_Width (Unit.Value));
            pragma Assert (Static => Octet_At (S, Offset) = Octet_At (Encoded, 0));
            pragma Assert (Static => Octet_At (S, Offset + 1) = Octet_At (Encoded, 1));
            pragma Assert (Static => S (S'First + Offset) = Encoded (1));
            pragma Assert (Static => S (S'First + Offset + 1) = Encoded (2));
         when 3 =>
            pragma Assert
              (Static => Unit.Value in 16#800# .. 16#D7FF# | 16#E000# .. 16#FFFF#);
            pragma Assert (Static => Unit.Width = Encoding_Width (Unit.Value));
            pragma Assert (Static => Octet_At (S, Offset) = Octet_At (Encoded, 0));
            pragma Assert (Static => Octet_At (S, Offset + 1) = Octet_At (Encoded, 1));
            pragma Assert (Static => Octet_At (S, Offset + 2) = Octet_At (Encoded, 2));
            pragma Assert (Static => S (S'First + Offset) = Encoded (1));
            pragma Assert (Static => S (S'First + Offset + 1) = Encoded (2));
            pragma Assert (Static => S (S'First + Offset + 2) = Encoded (3));
         when 4 =>
            pragma Assert (Static => Unit.Value in 16#1_0000# .. 16#10_FFFF#);
            pragma Assert (Static => Unit.Width = Encoding_Width (Unit.Value));
            pragma Assert (Static => Octet_At (S, Offset) = Octet_At (Encoded, 0));
            pragma Assert (Static => Octet_At (S, Offset + 1) = Octet_At (Encoded, 1));
            pragma Assert (Static => Octet_At (S, Offset + 2) = Octet_At (Encoded, 2));
            pragma Assert (Static => Octet_At (S, Offset + 3) = Octet_At (Encoded, 3));
            pragma Assert (Static => S (S'First + Offset) = Encoded (1));
            pragma Assert (Static => S (S'First + Offset + 1) = Encoded (2));
            pragma Assert (Static => S (S'First + Offset + 2) = Encoded (3));
            pragma Assert (Static => S (S'First + Offset + 3) = Encoded (4));
      end case;
   end Lemma_Decode_Encode_At;

   procedure Lemma_Equal_Decoded_Bytes
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left_Offset < Left'Length
       and then Valid_At (Left, Left_Offset)
       and then Right_Offset < Right'Length
       and then Valid_At (Right, Right_Offset)
       and then
         Decode_One (Left, Left_Offset).Value
         = Decode_One (Right, Right_Offset).Value,
     Post   =>
       Decode_One (Left, Left_Offset).Width
       = Decode_One (Right, Right_Offset).Width
       and then
         Same_Bytes
           (Left,
            Left_Offset,
            Right,
            Right_Offset,
            Natural (Decode_One (Left, Left_Offset).Width))
   is
      Left_Unit  : constant Decoded_Unit :=
        Decode_One (Left, Left_Offset)
      with Ghost => Static;
      Right_Unit : constant Decoded_Unit :=
        Decode_One (Right, Right_Offset)
      with Ghost => Static;
   begin
      Lemma_Decode_Encode_At (Left, Left_Offset);
      Lemma_Decode_Encode_At (Right, Right_Offset);
      pragma Assert (Static => Left_Unit.Width = Right_Unit.Width);
      pragma Assert
        (Static =>
           (for all I in Natural range
              0 .. Natural (Left_Unit.Width) - 1 =>
                Left (Left'First + Left_Offset + I)
                = Right (Right'First + Right_Offset + I)));
      case Left_Unit.Width is
         when 1 =>
            pragma Assert
              (Static => Same_Bytes
                 (Left, Left_Offset, Right, Right_Offset, 1));
         when 2 =>
            pragma Assert
              (Static => Same_Bytes
                 (Left, Left_Offset, Right, Right_Offset, 2));
         when 3 =>
            pragma Assert
              (Static => Same_Bytes
                 (Left, Left_Offset, Right, Right_Offset, 3));
         when 4 =>
            pragma Assert
              (Static => Same_Bytes
                 (Left, Left_Offset, Right, Right_Offset, 4));
      end case;
   end Lemma_Equal_Decoded_Bytes;

   procedure Lemma_Same_Bytes_Reflexive
     (S : String; Offset, Count : Natural) is
   begin
      if Count > 0 then
         Lemma_Same_Bytes_Reflexive (S, Offset, Count - 1);
      end if;
   end Lemma_Same_Bytes_Reflexive;

   procedure Lemma_Same_Bytes_At
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      Count        : Natural;
      Index        : Natural) is
   begin
      if Index < Count - 1 then
         Lemma_Same_Bytes_At
           (Left,
            Left_Offset,
            Right,
            Right_Offset,
            Count - 1,
            Index);
      end if;
   end Lemma_Same_Bytes_At;

   procedure Lemma_Same_Bytes_Suffix
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      Count        : Natural;
      Dropped      : Natural) is
   begin
      if Dropped < Count then
         Lemma_Same_Bytes_Suffix
           (Left,
            Left_Offset,
            Right,
            Right_Offset,
            Count - 1,
            Dropped);
         Lemma_Same_Bytes_At
           (Left,
            Left_Offset,
            Right,
            Right_Offset,
            Count,
            Count - 1);
      end if;
   end Lemma_Same_Bytes_Suffix;

   procedure Lemma_Same_Bytes_Concatenation
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      First_Count  : Natural;
      Second_Count : Natural) is
   begin
      if Second_Count > 0 then
         Lemma_Same_Bytes_Concatenation
           (Left,
            Left_Offset,
            Right,
            Right_Offset,
            First_Count,
            Second_Count - 1);
      end if;
   end Lemma_Same_Bytes_Concatenation;

   procedure Lemma_Transfer_To_Prefixes
     (Left, Right : String; Prefix_Count, Count : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Prefix_Count <= Left'Length
       and then Prefix_Count <= Right'Length
       and then Count <= Prefix_Count
       and then Same_Bytes (Left, 0, Right, 0, Count),
     Post   =>
       Same_Bytes
         (Prefix_Bytes (Left, Prefix_Count),
          0,
          Prefix_Bytes (Right, Prefix_Count),
          0,
          Count),
     Subprogram_Variant => (Decreases => Count)
   is
   begin
      if Count > 0 then
         Lemma_Transfer_To_Prefixes
           (Left, Right, Prefix_Count, Count - 1);
      end if;
   end Lemma_Transfer_To_Prefixes;

   procedure Lemma_Same_Bytes_Prefixes
     (Left, Right : String; Count : Natural) is
   begin
      Lemma_Transfer_To_Prefixes (Left, Right, Count, Count);
   end Lemma_Same_Bytes_Prefixes;

   procedure Lemma_Same_Bytes_Whole_Equality
     (Left, Right : String) is
   begin
      if Left'Length = 0 then
         pragma Assert (Static => Left = Right);
      elsif Left'Length = 1 then
         pragma Assert (Static => Left (Left'First) = Right (Right'First));
         pragma Assert (Static => Left = Right);
      else
         declare
            Left_Prefix  : constant String :=
              Prefix_Bytes (Left, Left'Length - 1)
            with Ghost => Static;
            Right_Prefix : constant String :=
              Prefix_Bytes (Right, Right'Length - 1)
            with Ghost => Static;
         begin
            pragma Assert (Static => Left_Prefix'Length = Right_Prefix'Length);
            pragma Assert
              (Static => Same_Bytes (Left, 0, Right, 0, Left'Length - 1));
            Lemma_Same_Bytes_Prefixes (Left, Right, Left'Length - 1);
            Lemma_Same_Bytes_Whole_Equality (Left_Prefix, Right_Prefix);
            pragma Assert (Static => Left_Prefix = Right_Prefix);
            pragma Assert (Static => Left (Left'Last) = Right (Right'Last));
            pragma Assert (Static => Left = Right);
         end;
      end if;
   end Lemma_Same_Bytes_Whole_Equality;

   procedure Lemma_Equal_Strings_Decode
     (Left, Right : String; Offset : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left = Right
       and then Offset < Left'Length
       and then Valid_At (Left, Offset)
       and then Valid_At (Right, Offset),
     Post   => Decode_One (Left, Offset) = Decode_One (Right, Offset)
   is
      Width : constant Natural := Sequence_Width_At (Left, Offset)
      with Ghost => Static;
   begin
      pragma Assert (Static => Left'Length = Right'Length);
      pragma Assert
        (Static => Left (Left'First + Offset) = Right (Right'First + Offset));
      pragma Assert (Static => Octet_At (Left, Offset) = Octet_At (Right, Offset));
      if Width >= 2 then
         pragma Assert
           (Static => Left (Left'First + Offset + 1)
            = Right (Right'First + Offset + 1));
         pragma Assert
           (Static => Octet_At (Left, Offset + 1) = Octet_At (Right, Offset + 1));
      end if;
      if Width >= 3 then
         pragma Assert
           (Static => Left (Left'First + Offset + 2)
            = Right (Right'First + Offset + 2));
         pragma Assert
           (Static => Octet_At (Left, Offset + 2) = Octet_At (Right, Offset + 2));
      end if;
      if Width = 4 then
         pragma Assert
           (Static => Left (Left'First + Offset + 3)
            = Right (Right'First + Offset + 3));
         pragma Assert
           (Static => Octet_At (Left, Offset + 3) = Octet_At (Right, Offset + 3));
      end if;
      pragma Assert
        (Static => Sequence_Width_At (Left, Offset)
         = Sequence_Width_At (Right, Offset));
      pragma Assert (Static => Decode_One (Left, Offset) = Decode_One (Right, Offset));
   end Lemma_Equal_Strings_Decode;

   procedure Lemma_Equal_Strings_Model_From
     (Left, Right : String; Offset : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left = Right
       and then Offset <= Left'Length
       and then Valid_From (Left, Offset)
       and then Valid_From (Right, Offset),
     Post   => Model_From (Left, Offset) = Model_From (Right, Offset),
     Subprogram_Variant => (Decreases => Left'Length - Offset)
   is
   begin
      if Offset < Left'Length then
         Lemma_Equal_Strings_Decode (Left, Right, Offset);
         declare
            Width       : constant Natural := Sequence_Width_At (Left, Offset)
            with Ghost => Static;
            Next_Offset : constant Natural := Offset + Width
            with Ghost => Static;
         begin
            pragma Assert
              (Static => Width = Sequence_Width_At (Right, Offset));
            Lemma_Equal_Strings_Model_From (Left, Right, Next_Offset);
            pragma Assert
              (Static => Model_From (Left, Offset) = Model_From (Right, Offset));
         end;
      end if;
   end Lemma_Equal_Strings_Model_From;

   procedure Lemma_Same_Bytes_Decode
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural;
      Count        : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left_Offset < Left'Length
       and then Count <= Left'Length - Left_Offset
       and then Right_Offset < Right'Length
       and then Count <= Right'Length - Right_Offset
       and then Same_Bytes
                  (Left, Left_Offset, Right, Right_Offset, Count)
       and then Valid_At (Left, Left_Offset)
       and then Sequence_Width_At (Left, Left_Offset) <= Count,
     Post   =>
       Valid_At (Right, Right_Offset)
       and then
         Decode_One (Left, Left_Offset)
         = Decode_One (Right, Right_Offset)
   is
      Width : constant Natural := Sequence_Width_At (Left, Left_Offset)
      with Ghost => Static;
   begin
      pragma Assert (Static => Width in 1 .. 4);
      pragma Assert (Static => Width <= Count);
      Lemma_Same_Bytes_At
        (Left, Left_Offset, Right, Right_Offset, Count, 0);
      if Width >= 2 then
         Lemma_Same_Bytes_At
           (Left, Left_Offset, Right, Right_Offset, Count, 1);
      end if;
      if Width >= 3 then
         Lemma_Same_Bytes_At
           (Left, Left_Offset, Right, Right_Offset, Count, 2);
      end if;
      if Width = 4 then
         Lemma_Same_Bytes_At
           (Left, Left_Offset, Right, Right_Offset, Count, 3);
      end if;
      pragma Assert
        (Static => Sequence_Width_At (Right, Right_Offset) = Width);
      pragma Assert
        (Static => Decode_One (Left, Left_Offset)
         = Decode_One (Right, Right_Offset));
   end Lemma_Same_Bytes_Decode;

   procedure Lemma_Rebased_Model_From
     (Left         : String;
      Left_Offset  : Natural;
      Right        : String;
      Right_Offset : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Left_Offset <= Left'Length
       and then Right_Offset <= Right'Length
       and then Left'Length - Left_Offset = Right'Length - Right_Offset
       and then
         Same_Bytes
           (Left,
            Left_Offset,
            Right,
            Right_Offset,
            Left'Length - Left_Offset)
       and then Valid_From (Left, Left_Offset),
     Post   =>
       Valid_From (Right, Right_Offset)
       and then
         Model_From (Left, Left_Offset)
         = Model_From (Right, Right_Offset),
     Subprogram_Variant => (Decreases => Left'Length - Left_Offset)
   is
   begin
      if Left_Offset < Left'Length then
         declare
            Count : constant Natural := Left'Length - Left_Offset
            with Ghost => Static;
            Width : constant Natural :=
              Sequence_Width_At (Left, Left_Offset)
            with Ghost => Static;
         begin
            Lemma_Same_Bytes_Decode
              (Left, Left_Offset, Right, Right_Offset, Count);
            Lemma_Same_Bytes_Suffix
              (Left,
               Left_Offset,
               Right,
               Right_Offset,
               Count,
               Width);
            Lemma_Rebased_Model_From
              (Left,
               Left_Offset + Width,
               Right,
               Right_Offset + Width);
         end;
      end if;
   end Lemma_Rebased_Model_From;

   procedure Lemma_Concatenation_From
     (Left, Right, Result : String; Offset : Natural)
   with
     Ghost => Static,
     Global => null,
     Pre    =>
       Offset <= Left'Length
       and then Valid_From (Left, Offset)
       and then Is_Valid_UTF_8 (Right)
       and then Left'Length <= Natural'Last - Right'Length
       and then Is_Byte_Concatenation (Left, Right, Result),
     Post   =>
       Valid_From (Result, Offset)
       and then
         Is_Concatenation
           (Model_From (Left, Offset),
            Model (Right),
            Model_From (Result, Offset)),
     Subprogram_Variant => (Decreases => Left'Length - Offset)
   is
   begin
      if Offset = Left'Length then
         Lemma_Rebased_Model_From
           (Right, 0, Result, Left'Length);
         pragma Assert
           (Static => Scalar_Sequences.Length (Model_From (Left, Offset)) = 0);
         pragma Assert
           (Static => Model_From (Result, Offset) = Model (Right));
         pragma Assert
           (Static => Is_Concatenation
              (Model_From (Left, Offset),
               Model (Right),
               Model_From (Result, Offset)));
      else
         declare
            Count       : constant Natural := Left'Length - Offset
            with Ghost => Static;
            Width       : constant Natural :=
              Sequence_Width_At (Left, Offset)
            with Ghost => Static;
            Next_Offset : constant Natural := Offset + Width
            with Ghost => Static;
         begin
            Lemma_Same_Bytes_Suffix
              (Left,
               0,
               Result,
               0,
               Left'Length,
               Offset);
            Lemma_Same_Bytes_Decode
              (Left, Offset, Result, Offset, Count);
            Lemma_Concatenation_From
              (Left, Right, Result, Next_Offset);
            Lemma_Prepend_Concatenation
              (Decode_One (Left, Offset).Value,
               Model_From (Left, Next_Offset),
               Model (Right),
               Model_From (Result, Next_Offset));
            pragma Assert (Static => Valid_At (Result, Offset));
            pragma Assert (Static => Valid_From (Result, Next_Offset));
            pragma Assert (Static => Valid_From (Result, Offset));
         end;
      end if;
   end Lemma_Concatenation_From;

   procedure Lemma_Encoding_Injective
     (Left, Right : String; Value : Text)
   is
      Left_Cursor  : Cursor_Type := First (Left);
      Right_Cursor : Cursor_Type := First (Right);
      Left_Value   : Scalar_Value;
      Right_Value  : Scalar_Value;
   begin
      pragma Assert (Static => Model (Left) = Value);
      pragma Assert (Static => Model (Right) = Value);

      while Has_Element (Left, Left_Cursor) loop
         pragma Loop_Invariant (Static => Is_Valid_Cursor (Left, Left_Cursor));
         pragma Loop_Invariant (Static => Is_Valid_Cursor (Right, Right_Cursor));
         pragma Loop_Invariant
           (Static => Model_Index (Left_Cursor) = Model_Index (Right_Cursor));
         pragma Loop_Invariant
           (Static => Byte_Offset (Left_Cursor) = Byte_Offset (Right_Cursor));
         pragma Loop_Invariant
           (Static => Same_Bytes
              (Left, 0, Right, 0, Byte_Offset (Left_Cursor)));
         pragma Loop_Variant
           (Decreases => Left'Length - Byte_Offset (Left_Cursor));

         pragma Assert (Static => Has_Element (Right, Right_Cursor));
         declare
            Old_Offset : constant Natural := Byte_Offset (Left_Cursor)
            with Ghost => Static;
         begin
            pragma Assert (Static => Same_Bytes (Left, 0, Right, 0, Old_Offset));
            Next (Left, Left_Cursor, Left_Value);
            Next (Right, Right_Cursor, Right_Value);
            pragma Assert (Static => Left_Value = Right_Value);
            Lemma_Equal_Decoded_Bytes (Left, Old_Offset, Right, Old_Offset);
            pragma Assert
              (Static => Byte_Offset (Left_Cursor) = Byte_Offset (Right_Cursor));
            pragma Assert
              (Static => Byte_Offset (Left_Cursor) - Old_Offset
               = Natural (Decode_One (Left, Old_Offset).Width));
            pragma Assert
              (Static => Same_Bytes
                 (Left,
                  Old_Offset,
                  Right,
                  Old_Offset,
                  Byte_Offset (Left_Cursor) - Old_Offset));
            Lemma_Same_Bytes_Concatenation
              (Left,
               0,
               Right,
               0,
               Old_Offset,
               Byte_Offset (Left_Cursor) - Old_Offset);
         end;
      end loop;

      pragma Assert (Static => not Has_Element (Right, Right_Cursor));
      pragma Assert (Static => Left'Length = Right'Length);
      pragma Assert (Static => Byte_Offset (Left_Cursor) = Left'Length);
      pragma Assert (Static => Same_Bytes (Left, 0, Right, 0, Left'Length));
   end Lemma_Encoding_Injective;

   procedure Lemma_Equality (Left, Right : String) is
   begin
      if Left = Right then
         Lemma_Equal_Strings_Model_From (Left, Right, 0);
         pragma Assert (Static => Model (Left) = Model (Right));
         pragma Assert (Static => (Left = Right) = (Model (Left) = Model (Right)));
         return;
      end if;

      if Model (Left) /= Model (Right) then
         pragma Assert (Static => Left /= Right);
         pragma Assert (Static => (Left = Right) = (Model (Left) = Model (Right)));
         return;
      end if;

      Lemma_Encoding_Injective (Left, Right, Model (Left));
      Lemma_Same_Bytes_Whole_Equality (Left, Right);
      pragma Assert (Static => Left = Right);
      pragma Assert (Static => (Left = Right) = (Model (Left) = Model (Right)));
   end Lemma_Equality;

   procedure Lemma_Concatenation
     (Left, Right, Result : String) is
   begin
      Lemma_Concatenation_From (Left, Right, Result, 0);
   end Lemma_Concatenation;

   procedure Lemma_Prefix (Prefix, Whole : String) is null;

   procedure Lemma_Suffix (Suffix, Whole : String) is null;

   procedure Lemma_Comparison (Left, Right : String) is null;

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
      with Ghost => Static;
      Unit    : constant Decoded_Unit := Decode_One (Encoded, 0)
      with Ghost => Static;
      Empty   : constant Text := Scalar_Sequences.Empty_Sequence
      with Ghost => Static;
      One     : constant Text := [Value]
      with Ghost => Static;
      Front   : constant Text := Scalar_Sequences.Add (Empty, 1, Value)
      with Ghost => Static;
   begin
      pragma Assert (Static => Valid_At (Encoded, 0));
      pragma Assert (Static => Unit.Value = Value);
      pragma Assert (Static => Unit.Width = Encoding_Width (Value));
      pragma Assert (Static => Natural (Unit.Width) = Encoded'Length);
      pragma Assert (Static => Model_From (Encoded, Encoded'Length) = Empty);
      pragma Assert (Static => Model_From (Encoded, 0) = Front);
      pragma Assert (Static => Is_Encoding (Encoded, Model (Encoded)));
      pragma Assert (Static => Front = One);
      pragma Assert (Static => Model (Encoded) = One);
   end Lemma_Encode_Decode;

end Unicode_Text.UTF_8;
