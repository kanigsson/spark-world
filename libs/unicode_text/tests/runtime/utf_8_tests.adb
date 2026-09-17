with Ada.Text_IO;        use Ada.Text_IO;
with Unicode_Text;       use Unicode_Text;
with Unicode_Text.UTF_8; use Unicode_Text.UTF_8;

procedure UTF_8_Tests is

   Checks : Natural := 0;

   function C (Value : Octet) return Character
   is (Character'Val (Value));

   procedure Check (Condition : Boolean; Message : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Check_Encoding
     (Value : Scalar_Value; Expected : String; Label : String)
   is
      Actual : constant String := Encode_One (Value);
      Unit   : Decoded_Unit;
   begin
      Check (Actual = Expected, Label & ": encoding");
      Check (Actual'First = 1, Label & ": lower bound");
      Check (Is_Valid_UTF_8 (Actual), Label & ": validity");
      Unit := Decode_One (Actual, 0);
      Check (Unit.Value = Value, Label & ": decoding");
      Check (Unit.Width = Encoding_Width (Value), Label & ": width");
   end Check_Encoding;

   procedure Check_Invalid (S : String; Offset : Natural; Label : String) is
      Result : constant Validation_Result := Validate (S);
   begin
      Check (not Is_Valid_UTF_8 (S), Label & ": accepted");
      Check (not Result.Valid, Label & ": validate accepted");
      Check (Result.Error_Offset = Offset, Label & ": error offset");
   end Check_Invalid;

   procedure Check_Valid (S : String; Label : String) is
      Result : constant Validation_Result := Validate (S);
   begin
      Check (Is_Valid_UTF_8 (S), Label & ": rejected");
      Check (Result.Valid, Label & ": validate rejected");
      Check (Result.Error_Offset = S'Length, Label & ": success offset");
   end Check_Valid;

begin
   --  Independent examples at every encoding boundary.
   Check_Encoding (16#0000#, [1 => C (16#00#)], "U+0000");
   Check_Encoding (16#007F#, [1 => C (16#7F#)], "U+007F");
   Check_Encoding (16#0080#, [C (16#C2#), C (16#80#)], "U+0080");
   Check_Encoding (16#07FF#, [C (16#DF#), C (16#BF#)], "U+07FF");
   Check_Encoding (16#0800#, [C (16#E0#), C (16#A0#), C (16#80#)], "U+0800");
   Check_Encoding (16#D7FF#, [C (16#ED#), C (16#9F#), C (16#BF#)], "U+D7FF");
   Check_Encoding (16#E000#, [C (16#EE#), C (16#80#), C (16#80#)], "U+E000");
   Check_Encoding (16#FFFF#, [C (16#EF#), C (16#BF#), C (16#BF#)], "U+FFFF");
   Check_Encoding
     (16#1_0000#, [C (16#F0#), C (16#90#), C (16#80#), C (16#80#)], "U+10000");
   Check_Encoding
     (16#10_FFFF#,
      [C (16#F4#), C (16#8F#), C (16#BF#), C (16#BF#)],
      "U+10FFFF");

   --  Exhaust every scalar value, not just a sample of each width.
   for Raw in Code_Point loop
      if Raw not in 16#D800# .. 16#DFFF# then
         declare
            Value   : constant Scalar_Value := Raw;
            Encoded : constant String := Encode_One (Value);
            Unit    : constant Decoded_Unit := Decode_One (Encoded, 0);
         begin
            Check (Is_Valid_UTF_8 (Encoded), "scalar validity");
            Check (Unit.Value = Value, "scalar round trip");
            Check (Unit.Width = Encoding_Width (Value), "scalar width");
            Check (Natural (Unit.Width) = Encoded'Length, "scalar length");
         end;
      end if;
   end loop;

   Check_Valid ("", "empty");
   Check_Valid ([C (0), 'A', C (16#C2#), C (16#80#), C (0)], "embedded zero");

   --  Every non-ASCII octet is invalid as a one-byte string.  This covers
   --  isolated continuations, truncated leads, C0/C1, and F5..FF.
   for B0 in Octet range 16#80# .. 16#FF# loop
      Check_Invalid ([1 => C (B0)], 0, "standalone non-ASCII octet");
   end loop;

   --  Exercise every possible second octet in each constrained lead class.
   for B1 in Octet loop
      declare
         E0 : constant String := [C (16#E0#), C (B1), C (16#80#)];
         ED : constant String := [C (16#ED#), C (B1), C (16#80#)];
         F0 : constant String := [C (16#F0#), C (B1), C (16#80#), C (16#80#)];
         F4 : constant String := [C (16#F4#), C (B1), C (16#80#), C (16#80#)];
      begin
         Check
           (Is_Valid_UTF_8 (E0) = (B1 in 16#A0# .. 16#BF#), "E0 second octet");
         Check
           (Is_Valid_UTF_8 (ED) = (B1 in 16#80# .. 16#9F#), "ED second octet");
         Check
           (Is_Valid_UTF_8 (F0) = (B1 in 16#90# .. 16#BF#), "F0 second octet");
         Check
           (Is_Valid_UTF_8 (F4) = (B1 in 16#80# .. 16#8F#), "F4 second octet");
      end;
   end loop;

   --  Exercise every possible octet in ordinary continuation positions.
   for Byte in Octet loop
      Check
        (Is_Valid_UTF_8 ([C (16#C2#), C (Byte)]) = (Byte in 16#80# .. 16#BF#),
         "two-byte continuation");
      Check
        (Is_Valid_UTF_8 ([C (16#E1#), C (16#80#), C (Byte)])
         = (Byte in 16#80# .. 16#BF#),
         "three-byte third octet");
      Check
        (Is_Valid_UTF_8 ([C (16#F1#), C (16#80#), C (Byte), C (16#80#)])
         = (Byte in 16#80# .. 16#BF#),
         "four-byte third octet");
      Check
        (Is_Valid_UTF_8 ([C (16#F1#), C (16#80#), C (16#80#), C (Byte)])
         = (Byte in 16#80# .. 16#BF#),
         "four-byte fourth octet");
   end loop;

   Check_Invalid ([C (16#C0#), C (16#80#)], 0, "overlong two-byte");
   Check_Invalid
     ([C (16#E0#), C (16#80#), C (16#80#)], 0, "overlong three-byte");
   Check_Invalid
     ([C (16#F0#), C (16#80#), C (16#80#), C (16#80#)],
      0,
      "overlong four-byte");
   Check_Invalid ([C (16#ED#), C (16#A0#), C (16#80#)], 0, "surrogate start");
   Check_Invalid ([C (16#ED#), C (16#BF#), C (16#BF#)], 0, "surrogate end");
   Check_Invalid
     ([C (16#F4#), C (16#90#), C (16#80#), C (16#80#)], 0, "above U+10FFFF");

   --  Truncation after every byte of a multibyte encoding.
   Check_Invalid ([1 => C (16#C2#)], 0, "truncated width 2");
   Check_Invalid ([1 => C (16#E0#)], 0, "truncated width 3 after lead");
   Check_Invalid
     ([C (16#E0#), C (16#A0#)], 0, "truncated width 3 after second");
   Check_Invalid ([1 => C (16#F0#)], 0, "truncated width 4 after lead");
   Check_Invalid
     ([C (16#F0#), C (16#90#)], 0, "truncated width 4 after second");
   Check_Invalid
     ([C (16#F0#), C (16#90#), C (16#80#)],
      0,
      "truncated width 4 after third");

   --  Error offsets point at the first sequence that cannot be decoded.
   Check_Invalid ("A" & C (16#80#), 1, "offset after ASCII");
   Check_Invalid
     ([C (16#C2#), C (16#80#), C (16#E0#), C (16#20#), C (16#80#)],
      2,
      "offset after multibyte");

   --  Ada bounds do not affect validation or decoding.
   declare
      Shifted : String (10 .. 14) :=
        [10 => 'A',
         11 => C (16#C2#),
         12 => C (16#80#),
         13 => C (16#E0#),
         14 => C (16#A0#)];
   begin
      Check_Invalid (Shifted, 3, "shifted invalid input");
      Shifted (13) := C (16#00#);
      Shifted (14) := 'Z';
      Check_Valid (Shifted, "shifted valid input");
      Check (Decode_One (Shifted, 1).Value = 16#80#, "shifted decoding");
   end;

   Put_Line ("UTF-8 runtime tests passed:" & Checks'Image & " checks");
end UTF_8_Tests;
