with Unicode_Text;

--  JSON.Strings uses one hostile-input scalar iterator for both decoding
--  and equality. JSON escape syntax stays here; raw UTF-8 classification,
--  scalar decoding, and scalar encoding come from Unicode_Text.UTF_8.

package body JSON.Strings with SPARK_Mode => On is

   use type Unicode_Text.Scalar_Value;

   function Cur (Input : String; Pos : Natural) return Character is
     (Input (Input'First + Pos))
   with Pre => Pos < Input'Length;

   --  Four hex digits of a \u escape, as a code unit.

   procedure Hex4
     (Input  : in     String;
      Pos    : in out Natural;
      Code   :    out Natural;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Pos <= Input'Length,
     Post   =>
       Pos in Pos'Old .. Input'Length
       and then Code <= 16#FFFF#
       and then (if Status = OK then Pos = Pos'Old + 4);

   --  Decode one logical scalar from a JSON string payload. On success,
   --  the encoded scalar cannot be wider than the source spelling it
   --  consumed; this is the bound used by Decode's caller-buffer proof.

   procedure Next_Scalar
     (Input  : in     String;
      Pos    : in out Natural;
      Value  :    out Unicode_Text.Scalar_Value;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Pos < Input'Length,
     Post   =>
       Pos in Pos'Old .. Input'Length
       and then
         (if Status = OK
          then
            Pos > Pos'Old
            and then
              Natural (Unicode_Text.UTF_8.Encoding_Width (Value))
                <= Pos - Pos'Old);

   --  Append one complete canonical encoding. Out_Pos is advanced only
   --  after every byte has been written.

   procedure Append_Scalar
     (Output  : in out String;
      Out_Pos : in out Natural;
      Value   : in     Unicode_Text.Scalar_Value)
   with
     Global => null,
     Pre    =>
       Output'Last < Positive'Last
       and then Out_Pos <= Output'Length
       and then
         Natural (Unicode_Text.UTF_8.Encoding_Width (Value))
           <= Output'Length - Out_Pos,
     Post   =>
       Out_Pos
         = Out_Pos'Old
           + Natural (Unicode_Text.UTF_8.Encoding_Width (Value));

   ----------
   -- Hex4 --
   ----------

   procedure Hex4
     (Input  : in     String;
      Pos    : in out Natural;
      Code   :    out Natural;
      Status :    out Status_Type)
   is
      C : Character;
      V : Natural range 0 .. 15;
   begin
      Code := 0;
      if Input'Length - Pos < 4 then
         Status := Truncated;
         return;
      end if;
      for I in 1 .. 4 loop
         pragma Loop_Invariant (Pos = Pos'Loop_Entry + (I - 1));
         pragma Loop_Invariant
           (Code <= (case I is
                        when 1 => 0, when 2 => 15,
                        when 3 => 255, when 4 => 4_095));
         C := Cur (Input, Pos);
         case C is
            when '0' .. '9' =>
               V := Character'Pos (C) - Character'Pos ('0');
            when 'a' .. 'f' =>
               V := Character'Pos (C) - Character'Pos ('a') + 10;
            when 'A' .. 'F' =>
               V := Character'Pos (C) - Character'Pos ('A') + 10;
            when others =>
               Code   := 0;
               Status := Invalid_Escape;
               return;
         end case;
         Code := Code * 16 + V;
         Pos  := Pos + 1;
      end loop;
      Status := OK;
   end Hex4;

   -----------------
   -- Next_Scalar --
   -----------------

   procedure Next_Scalar
     (Input  : in     String;
      Pos    : in out Natural;
      Value  :    out Unicode_Text.Scalar_Value;
      Status :    out Status_Type)
   is
      C    : Character;
      High : Natural;
      Low  : Natural;
      Unit : Unicode_Text.UTF_8.Decoded_Unit;
   begin
      Value := 0;
      C := Cur (Input, Pos);

      if C = '\' then
         Pos := Pos + 1;
         if Pos >= Input'Length then
            Status := Truncated;
            return;
         end if;

         C   := Cur (Input, Pos);
         Pos := Pos + 1;
         case C is
            when '"' | '\' | '/' =>
               Value := Unicode_Text.Scalar_Value (Character'Pos (C));
            when 'b' =>
               Value := 8;
            when 'f' =>
               Value := 12;
            when 'n' =>
               Value := 10;
            when 'r' =>
               Value := 13;
            when 't' =>
               Value := 9;

            when 'u' =>
               Hex4 (Input, Pos, High, Status);
               if Status /= OK then
                  return;
               end if;

               if High in 16#D800# .. 16#DBFF# then
                  if Input'Length - Pos < 2 then
                     Status := Truncated;
                     return;
                  end if;
                  if Cur (Input, Pos) /= '\'
                    or else Cur (Input, Pos + 1) /= 'u'
                  then
                     Status := Invalid_Escape;
                     return;
                  end if;
                  Pos := Pos + 2;
                  Hex4 (Input, Pos, Low, Status);
                  if Status /= OK then
                     return;
                  end if;
                  if Low not in 16#DC00# .. 16#DFFF# then
                     Status := Invalid_Escape;
                     return;
                  end if;
                  Value :=
                    Unicode_Text.Scalar_Value
                      (16#10000#
                       + (High - 16#D800#) * 16#400#
                       + (Low - 16#DC00#));
               elsif High in 16#DC00# .. 16#DFFF# then
                  Status := Invalid_Escape;
                  return;
               else
                  Value := Unicode_Text.Scalar_Value (High);
               end if;

            when others =>
               Status := Invalid_Escape;
               return;
         end case;
         Status := OK;

      elsif Character'Pos (C) < 32 then
         Status := Invalid_String_Char;

      elsif Character'Pos (C) < 128 then
         Value  := Unicode_Text.Scalar_Value (Character'Pos (C));
         Pos    := Pos + 1;
         Status := OK;

      elsif not Unicode_Text.UTF_8.Valid_At (Input, Pos) then
         Status := Invalid_UTF8;

      else
         Unit   := Unicode_Text.UTF_8.Decode_One (Input, Pos);
         Value  := Unit.Value;
         Pos    := Pos + Natural (Unit.Width);
         Status := OK;
      end if;
   end Next_Scalar;

   -------------------
   -- Append_Scalar --
   -------------------

   procedure Append_Scalar
     (Output  : in out String;
      Out_Pos : in out Natural;
      Value   : in     Unicode_Text.Scalar_Value)
   is
      Encoded : constant String := Unicode_Text.UTF_8.Encode_One (Value);
   begin
      for Offset in 0 .. Encoded'Length - 1 loop
         Output (Output'First + Out_Pos + Offset) :=
           Encoded (Encoded'First + Offset);
      end loop;
      Out_Pos := Out_Pos + Encoded'Length;
   end Append_Scalar;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Input  : in     String;
      Output : in out String;
      Length :    out Natural;
      Status :    out Status_Type)
   is
      In_Pos  : Natural := 0;
      Out_Pos : Natural := 0;
      Value   : Unicode_Text.Scalar_Value;
      Check   : Unicode_Text.UTF_8.Validation_Result;
   begin
      Length := 0;

      while In_Pos < Input'Length loop
         pragma Loop_Invariant (In_Pos <= Input'Length);
         pragma Loop_Invariant (Out_Pos <= In_Pos);
         pragma Loop_Variant (Increases => In_Pos);

         declare
            Old_In : constant Natural := In_Pos;
         begin
            Next_Scalar (Input, In_Pos, Value, Status);
            if Status /= OK then
               return;
            end if;
            pragma Assert
              (Natural (Unicode_Text.UTF_8.Encoding_Width (Value))
                 <= In_Pos - Old_In);
         end;

         Append_Scalar (Output, Out_Pos, Value);
      end loop;

      Check :=
        Unicode_Text.UTF_8.Validate (Active_Prefix (Output, Out_Pos));
      if Check.Valid then
         Length := Out_Pos;
         Status := OK;
      else
         --  Every output unit came from Encode_One. Keep this defensive
         --  boundary so the public guarantee never relies on an assertion.
         Status := Invalid_UTF8;
      end if;
   end Decode;

   --------------------
   -- Decoded_Equals --
   --------------------

   function Decoded_Equals (Input, Expected : String) return Boolean is
      Pos          : Natural := 0;
      Expected_Pos : Natural := 0;
      Actual       : Unicode_Text.Scalar_Value;
      Wanted       : Unicode_Text.UTF_8.Decoded_Unit;
      Status       : Status_Type;
   begin
      while Pos < Input'Length loop
         pragma Loop_Invariant (Pos <= Input'Length);
         pragma Loop_Invariant (Expected_Pos <= Expected'Length);
         pragma Loop_Variant (Increases => Pos);

         if Expected_Pos >= Expected'Length then
            return False;
         end if;

         Next_Scalar (Input, Pos, Actual, Status);
         if Status /= OK then
            return False;
         end if;
         if not Unicode_Text.UTF_8.Valid_At (Expected, Expected_Pos) then
            return False;
         end if;
         Wanted := Unicode_Text.UTF_8.Decode_One (Expected, Expected_Pos);
         Expected_Pos := Expected_Pos + Natural (Wanted.Width);
         if Actual /= Wanted.Value then
            return False;
         end if;
      end loop;

      return Expected_Pos = Expected'Length;
   end Decoded_Equals;

end JSON.Strings;
