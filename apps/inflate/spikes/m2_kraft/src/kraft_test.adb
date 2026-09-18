--  Executable sanity check for the spike: with -gnata every contract and
--  ghost assertion is evaluated at run time, so a passing run confirms
--  the proved contracts are non-vacuous on real inputs.

with Ada.Text_IO; use Ada.Text_IO;
with Kraft;       use Kraft;

procedure Kraft_Test is
   Counts   : Length_Count_Array;
   Symbols  : Symbol_Map;
   Complete : Boolean;
   Valid    : Boolean;

   --  The fixed literal/length code of RFC 1951 (288 symbols): complete.
   Fixed_Lit : Code_Length_Array (0 .. 287);

   --  The code-length code shape: a small complete code.
   Small : constant Code_Length_Array (0 .. 3) := (1, 2, 3, 3);

   --  Over-subscribed: three codes of length 1.
   Bad : constant Code_Length_Array (0 .. 2) := (1, 1, 1);

   --  Incomplete: one code of length 2.
   Incomplete : constant Code_Length_Array (0 .. 0) := (0 => 2);

   Sym   : Symbol_Value;
   Found : Boolean;
begin
   for I in Fixed_Lit'Range loop
      Fixed_Lit (I) :=
        (if I <= 143
         then 8
         elsif I <= 255
         then 9
         elsif I <= 279
         then 7
         else 8);
   end loop;

   Construct (Fixed_Lit, Counts, Symbols, Complete, Valid);
   pragma Assert (Valid and Complete);
   Put_Line
     ("fixed literal code: valid="
      & Valid'Image
      & " complete="
      & Complete'Image);

   --  Decode a few codes of the fixed literal table: 8 zero bits are the
   --  code for symbol 0 (canonical: shortest codes first, 7-bit codes
   --  cover 256..279, the first 8-bit code is symbol 0 at 00110000).
   Decode_Sim ((1 .. 15 => 0), Counts, Symbols, Sym, Found);
   pragma Assert (Found and Sym = 256);
   Put_Line ("all-zero bits decode to symbol" & Sym'Image);

   Construct (Small, Counts, Symbols, Complete, Valid);
   pragma Assert (Valid and Complete);
   Put_Line
     ("small code: valid=" & Valid'Image & " complete=" & Complete'Image);

   Construct (Bad, Counts, Symbols, Complete, Valid);
   pragma Assert (not Valid and not Complete);
   Put_Line
     ("over-subscribed code: valid="
      & Valid'Image
      & " complete="
      & Complete'Image);

   Construct (Incomplete, Counts, Symbols, Complete, Valid);
   pragma Assert (Valid and not Complete);
   Put_Line
     ("incomplete code: valid=" & Valid'Image & " complete=" & Complete'Image);

   Put_Line ("all runtime checks passed");
end Kraft_Test;
