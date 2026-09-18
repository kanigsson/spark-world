--  Ore.Images — the character images of the numbers this library's clients
--  print.
--
--  Every program in the repository that reports a count, a position or a byte
--  had written its own: `Natural'Image` followed by a slice that drops the
--  leading blank, in six places and three spellings, and a `"0123456789abcdef"`
--  table in four more. None of them stated what it produced, so a caller had
--  no fact to reason with and every one of them re-derived that the blank is
--  exactly one character wide.
--
--  This package is here under the library's own rule — what more than one
--  client turned out to need — and not to round out a standard library. It is
--  the physical layer's counterpart on the output side: the operations are
--  total on their preconditions, allocate nothing, and state what they return
--  character by character, so that a client's own contract can rest on it.
--
--  DESIGN: no context clauses, in keeping with the rest of the library, so
--  the bounds are derived from the target's own attributes rather than
--  written as constants that would be wrong on a target with a wider Integer.

package Ore.Images
  with Pure, SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Decimal
   ---------------------------------------------------------------------------

   --  'Width counts the sign position that 'Image occupies with a blank for a
   --  non-negative value; the image below never has one.
   Max_Decimal_Length : constant := Natural'Width - 1;

   subtype Decimal_Length is Positive range 1 .. Max_Decimal_Length;

   --  The decimal image with no leading blank: what every caller of 'Image in
   --  this repository was slicing by hand. Zero is "0"; nothing else carries a
   --  leading zero.
   --
   --  The bound on 'Last is what a caller needs to concatenate the image and
   --  still bound the result: a function result carries its own bounds, and a
   --  length alone leaves 'Last unknown, so "text " & Decimal (N) has no
   --  provable upper bound without it.
   function Decimal (Value : Natural) return String
   with
     Post =>
       Decimal'Result'Length in Decimal_Length
       and then Decimal'Result'Last <= Max_Decimal_Length
       and then (for all C of Decimal'Result => C in '0' .. '9')
       and then (Decimal'Result'Length = 1
                 or else Decimal'Result (Decimal'Result'First) /= '0');

   ---------------------------------------------------------------------------
   --  Hexadecimal
   ---------------------------------------------------------------------------

   type Letter_Case is (Lower_Case, Upper_Case);

   subtype Nibble is Natural range 0 .. 15;

   subtype Hex_Character is Character
   with
     Static_Predicate => Hex_Character in '0' .. '9' | 'a' .. 'f' | 'A' .. 'F';

   --  One hexadecimal digit. The table itself, which four clients carried.
   --  The equivalence is what a minimal-width image needs to know: a leading
   --  digit is '0' only when the value is zero.
   function Hex_Digit
     (Value : Nibble; Casing : Letter_Case := Lower_Case) return Hex_Character
   with Post => (Hex_Digit'Result = '0') = (Value = 0);

   --  A byte as exactly two digits, high nibble first — the fixed-width form
   --  that an escape sequence needs, where a minimal-width image would emit
   --  one digit for a byte below 16 and corrupt the escape.
   function Hex_Pair
     (Value : Byte; Casing : Letter_Case := Lower_Case) return String
   with
     Post =>
       Hex_Pair'Result'Length = 2
       and then (for all C of Hex_Pair'Result => C in Hex_Character);

   Max_Hex_Length : constant := (Natural'Size + 3) / 4;

   subtype Hex_Length is Positive range 1 .. Max_Hex_Length;

   --  The minimal-width hexadecimal image, for a value quoted to a reader
   --  rather than packed into a fixed-width escape. Zero is "0".
   function Hex
     (Value : Natural; Casing : Letter_Case := Lower_Case) return String
   with
     Post =>
       Hex'Result'Length in Hex_Length
       and then (for all C of Hex'Result => C in Hex_Character)
       and then (Hex'Result'Length = 1
                 or else Hex'Result (Hex'Result'First) /= '0');

end Ore.Images;
