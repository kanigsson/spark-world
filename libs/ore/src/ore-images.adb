package body Ore.Images
  with SPARK_Mode => On
is

   Lower_Digits : constant String := "0123456789abcdef";
   Upper_Digits : constant String := "0123456789ABCDEF";

   ---------------
   -- Hex_Digit --
   ---------------

   function Hex_Digit
     (Value : Nibble; Casing : Letter_Case := Lower_Case) return Hex_Character
   is (case Casing is
         when Lower_Case => Lower_Digits (Lower_Digits'First + Value),
         when Upper_Case => Upper_Digits (Upper_Digits'First + Value));

   --------------
   -- Hex_Pair --
   --------------

   function Hex_Pair
     (Value : Byte; Casing : Letter_Case := Lower_Case) return String
   is (Hex_Digit (Natural (Value) / 16, Casing)
       & Hex_Digit (Natural (Value) mod 16, Casing));

   -------------
   -- Decimal --
   -------------

   function Decimal (Value : Natural) return String is
      --  Filled from the right, so the digits land in order and the result is
      --  the tail actually written. Pre-filling with '0' makes "every
      --  character is a digit" hold from the start, so the loop carries it
      --  without a quantifier over the written part alone.
      Text  : String (1 .. Max_Decimal_Length) := (others => '0');
      First : Positive;
      Rest  : Natural := Value;
   begin
      --  The counter bounds the walk structurally; the invariant below says
      --  the bound is sufficient, so the loop always leaves through the exit
      --  and never runs out of positions. The comparison is widened because
      --  10 ** Max_Decimal_Length does not fit the type it bounds.
      pragma
        Assert (Long_Long_Integer (Natural'Last) < 10**Max_Decimal_Length);
      for I in reverse 1 .. Max_Decimal_Length loop
         pragma Loop_Invariant (Long_Long_Integer (Rest) < 10**I);
         pragma Loop_Invariant (for all C of Text => C in '0' .. '9');
         pragma Loop_Invariant (Rest > 0 or else I = Max_Decimal_Length);

         Text (I) := Character'Val (Character'Pos ('0') + Rest mod 10);
         First := I;
         Rest := Rest / 10;
         exit when Rest = 0;
      end loop;
      return Text (First .. Max_Decimal_Length);
   end Decimal;

   ---------
   -- Hex --
   ---------

   function Hex
     (Value : Natural; Casing : Letter_Case := Lower_Case) return String
   is
      Text  : String (1 .. Max_Hex_Length) := (others => '0');
      First : Positive;
      Rest  : Natural := Value;
   begin
      pragma Assert (Long_Long_Integer (Natural'Last) < 16**Max_Hex_Length);
      for I in reverse 1 .. Max_Hex_Length loop
         pragma Loop_Invariant (Long_Long_Integer (Rest) < 16**I);
         pragma Loop_Invariant (for all C of Text => C in Hex_Character);
         pragma Loop_Invariant (Rest > 0 or else I = Max_Hex_Length);

         Text (I) := Hex_Digit (Rest mod 16, Casing);
         First := I;
         Rest := Rest / 16;
         exit when Rest = 0;
      end loop;
      return Text (First .. Max_Hex_Length);
   end Hex;

end Ore.Images;
