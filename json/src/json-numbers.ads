--  JSON.Numbers — converting a number token (the slice a Number_Value
--  event hands back) to a machine type. JSON numbers have arbitrary
--  precision; these are the fixed-width accessors, and out-of-range input
--  is a reported condition, never an exception. Callers that need the
--  digits themselves keep the token slice.
--
--  Both conversions revalidate the token against the RFC 8259 grammar, so
--  they are safe on slices that did not come from a Pull event.

with Interfaces;

package JSON.Numbers with SPARK_Mode => On is

   use type Interfaces.Integer_64;

   --  Exact conversion of an integer token (one with no fraction and no
   --  exponent — the Pull event's Is_Integer flag). OK is False when the
   --  token is not such an integer or does not fit Integer_64; the full
   --  Integer_64 range including 'First is accepted.
   procedure To_Integer
     (Token : in     String;
      Value :    out Interfaces.Integer_64;
      OK    :    out Boolean)
   with
     Global => null,
     Post   => (if not OK then Value = 0);

   --  Conversion of any number token to Long_Float. OK is False when the
   --  token is malformed or its magnitude is beyond roughly 1.0E308 (the
   --  conversion is conservative within the last decade below
   --  Long_Float'Last); magnitudes below the subnormal range flush to 0.0
   --  with OK True. The result is faithful to about 1.0E-13 relative error
   --  (one rounding per decimal-exponent step), and exact for integers up
   --  to 2**53 — line/column/count data converts exactly.
   procedure To_Float
     (Token : in     String;
      Value :    out Long_Float;
      OK    :    out Boolean)
   with
     Global => null,
     Post   => (if not OK then Value = 0.0);

end JSON.Numbers;
