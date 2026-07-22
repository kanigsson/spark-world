with Ada.Text_IO;          use Ada.Text_IO;
with Unicode_Text;         use Unicode_Text;
with Unicode_Text.Bounded;
with Unicode_Text.UTF_8;

procedure Bounded_String_Tests is

   package Empty_Only is new Unicode_Text.Bounded (Capacity => 0);
   package Short_Text is new Unicode_Text.Bounded (Capacity => 3);
   package Roomy_Text is new Unicode_Text.Bounded (Capacity => 5);
   package Text is new Unicode_Text.Bounded (Capacity => 32);

   use type Empty_Only.Bounded_String;
   use type Text.Bounded_String;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   type Natural_Array is array (Integer range <>) of Natural;

   function Bytes (Values : Natural_Array) return String is
      Result : String (1 .. Values'Length);
   begin
      for I in Values'Range loop
         Result (I - Values'First + 1) := Character'Val (Values (I));
      end loop;
      return Result;
   end Bytes;

   Mixed : constant String :=
     Bytes
       ([16#00#, 16#7F#,
         16#C2#, 16#80#,
         16#DF#, 16#BF#,
         16#E0#, 16#A0#, 16#80#,
         16#ED#, 16#9F#, 16#BF#,
         16#EE#, 16#80#, 16#80#,
         16#F0#, 16#90#, 16#80#, 16#80#,
         16#F4#, 16#8F#, 16#BF#, 16#BF#]);

begin
   declare
      Left  : Empty_Only.Bounded_String := Empty_Only.Empty;
      Right : Empty_Only.Bounded_String;
   begin
      Check (Empty_Only.Max_Byte_Length = 0, "zero capacity");
      Check (Empty_Only.Is_Empty (Left), "explicit zero-capacity empty");
      Check (Empty_Only.Is_Empty (Right), "default zero-capacity empty");
      Check (Empty_Only.To_String (Left) = "", "zero-capacity conversion");
      Check (Left = Right, "zero-capacity equality");
      Empty_Only.Append (Left, "");
      Check (Empty_Only.Is_Empty (Left), "append empty at zero capacity");
   end;

   declare
      Too_Short : Short_Text.Bounded_String;
      Has_Room  : Roomy_Text.Bounded_String;
   begin
      Check
        (Natural (Unicode_Text.UTF_8.Encoding_Width (16#10_FFFF#))
         > Short_Text.Max_Byte_Length - Short_Text.Byte_Length (Too_Short),
         "one-short capacity is observable before append");
      Roomy_Text.Append (Has_Room, Scalar_Value'(16#10_FFFF#));
      Check (Roomy_Text.Byte_Length (Has_Room) = 4, "one-extra capacity");
   end;

   declare
      Source  : String (11 .. 10 + Mixed'Length);
      Value   : Text.Bounded_String;
      Copy    : Text.Bounded_String;
      Cursor  : Text.Cursor_Type;
      Seen    : Natural := 0;
      Current : Scalar_Value;
   begin
      Source := Mixed;
      Value := Text.To_Bounded_String (Source);
      Check (Text.Byte_Length (Value) = Mixed'Length, "construction length");
      Check (Text.Code_Point_Length (Value) = 9, "code-point length");
      Check (Text.To_String (Value) = Mixed, "construction bytes");
      Check (Text.Element (Value, 1) = 0, "first element");
      Check (Text.Element (Value, 9) = 16#10_FFFF#, "last element");

      Copy := Value;
      Check (Copy = Value, "copy equality");
      Text.Clear (Copy);
      Check (Text.Is_Empty (Copy), "clear");
      Check (Copy /= Value, "unused bytes do not affect equality");

      Text.Append (Copy, Scalar_Value'(0));
      declare
         Fresh : Text.Bounded_String;
      begin
         Text.Append (Fresh, Scalar_Value'(0));
         Check (Copy = Fresh, "equality ignores different unused storage");
      end;
      Text.Append (Copy, Scalar_Value'(16#7F#));
      Text.Append (Copy, Bytes ([16#C2#, 16#80#]));
      declare
         Tail : constant Text.Bounded_String :=
           Text.To_Bounded_String
             (Bytes
                ([16#DF#, 16#BF#,
                  16#E0#, 16#A0#, 16#80#,
                  16#ED#, 16#9F#, 16#BF#,
                  16#EE#, 16#80#, 16#80#,
                  16#F0#, 16#90#, 16#80#, 16#80#,
                  16#F4#, 16#8F#, 16#BF#, 16#BF#]));
      begin
         Text.Append (Copy, Tail);
      end;
      Check (Copy = Value, "all append forms");

      Cursor := Text.First (Copy);
      while Text.Has_Element (Copy, Cursor) loop
         Text.Next (Copy, Cursor, Current);
         Seen := Seen + 1;
         Check (Current = Text.Element (Copy, Seen), "iteration order");
      end loop;
      Check (Seen = Text.Code_Point_Length (Copy), "iteration count");
      Check
        (Text.Byte_Offset (Cursor) = Text.Byte_Length (Copy),
         "iteration ends at byte length");
   end;

   declare
      package Exact is new Unicode_Text.Bounded (Capacity => 4);
      Value : Exact.Bounded_String;
   begin
      Exact.Append (Value, Scalar_Value'(16#10_FFFF#));
      Check (Exact.Byte_Length (Value) = 4, "exact scalar capacity");
      Check
        (Exact.To_String (Value) = Bytes ([16#F4#, 16#8F#, 16#BF#, 16#BF#]),
         "exact scalar bytes");
   end;

   Put_Line ("bounded string tests passed");
end Bounded_String_Tests;
