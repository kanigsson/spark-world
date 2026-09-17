--  Tui.UTF8 — one proved UTF-8 decoder, shared by every crate that turns bytes
--  into code points.
--
--  The codec is deliberately CONTAINER-AGNOSTIC: it works on up to four bytes
--  (a lead byte and its possible continuations) plus a count of how many are
--  actually available, rather than on any particular buffer type. That frees it
--  from the byte-array and index vocabularies the consuming crates each define
--  for themselves — the pager's line buffer, the string crate's UTF8 — so a
--  single concrete, non-generic implementation serves them all: each caller
--  pulls the bytes out of its own buffer (a handful of reads it can already
--  prove in range) and hands them here.
--
--  Decoding is STRICT, per RFC 3629 and the Unicode well-formedness rules: only
--  shortest-form sequences, no surrogates, nothing above U+10FFFF. Ill-formed
--  or truncated input decodes to U+FFFD (the replacement character) advancing a
--  single byte — the lenient behaviour a display pager wants. A caller that
--  must instead REJECT malformed input keys off the Valid flag (or asks
--  Sequence_Length, which reports 0). All SPARK, proved free of run-time errors.

package Tui.UTF8 with Pure, SPARK_Mode => On is

   --  Substituted for any byte run that is not well-formed UTF-8.
   Replacement : constant Tui.Code_Point := 16#FFFD#;

   ---------------------------------------------------------------------------
   --  Scalar assembly. The raw bit value of a 2/3/4-byte sequence, given that
   --  the lead and continuation bytes are already in their expected ranges.
   --  Shared by the classifier below and by Decode, so both agree by
   --  construction on the number each sequence stands for. (A 4-byte sequence
   --  can name up to U+13FFFF; only the classifier's range test rejects the
   --  part above U+10FFFF, so Scalar_4's own bound is the wider one.)
   ---------------------------------------------------------------------------

   function Scalar_2 (B0, B1 : Tui.Byte) return Natural is
     ((Natural (B0) - 16#C0#) * 2 ** 6 + (Natural (B1) - 16#80#))
   with
     Pre  => Natural (B0) in 16#C2# .. 16#DF#
             and then Natural (B1) in 16#80# .. 16#BF#,
     Post => Scalar_2'Result <= 16#7FF#;

   function Scalar_3 (B0, B1, B2 : Tui.Byte) return Natural is
     ((Natural (B0) - 16#E0#) * 2 ** 12
      + (Natural (B1) - 16#80#) * 2 ** 6
      + (Natural (B2) - 16#80#))
   with
     Pre  => Natural (B0) in 16#E0# .. 16#EF#
             and then Natural (B1) in 16#80# .. 16#BF#
             and then Natural (B2) in 16#80# .. 16#BF#,
     Post => Scalar_3'Result <= 16#FFFF#;

   function Scalar_4 (B0, B1, B2, B3 : Tui.Byte) return Natural is
     ((Natural (B0) - 16#F0#) * 2 ** 18
      + (Natural (B1) - 16#80#) * 2 ** 12
      + (Natural (B2) - 16#80#) * 2 ** 6
      + (Natural (B3) - 16#80#))
   with
     Pre  => Natural (B0) in 16#F0# .. 16#F4#
             and then Natural (B1) in 16#80# .. 16#BF#
             and then Natural (B2) in 16#80# .. 16#BF#
             and then Natural (B3) in 16#80# .. 16#BF#,
     Post => Scalar_4'Result <= 16#13_FFFF#;

   --  Byte length (1 .. 4) of the well-formed UTF-8 sequence whose lead byte is
   --  B0, or 0 if B0 and the continuation bytes after it do not begin a
   --  shortest-form, non-surrogate, in-range sequence. Avail is how many bytes
   --  are actually available from B0 onward; B1 .. B3 are consulted only when
   --  Avail says they exist, so a caller may pass 0 for any that do not.
   --  Transparent (an expression function) so callers' proofs reason through it.
   function Sequence_Length
     (B0, B1, B2, B3 : Tui.Byte; Avail : Natural) return Natural
   is
     (if Avail = 0 then 0
      elsif Natural (B0) <= 16#7F# then 1
      elsif Natural (B0) in 16#C2# .. 16#DF#
        and then Avail >= 2
        and then Natural (B1) in 16#80# .. 16#BF#
      then 2
      elsif Natural (B0) in 16#E0# .. 16#EF#
        and then Avail >= 3
        and then Natural (B1) in 16#80# .. 16#BF#
        and then Natural (B2) in 16#80# .. 16#BF#
        and then Scalar_3 (B0, B1, B2) >= 16#800#
        and then Scalar_3 (B0, B1, B2) not in 16#D800# .. 16#DFFF#
      then 3
      elsif Natural (B0) in 16#F0# .. 16#F4#
        and then Avail >= 4
        and then Natural (B1) in 16#80# .. 16#BF#
        and then Natural (B2) in 16#80# .. 16#BF#
        and then Natural (B3) in 16#80# .. 16#BF#
        and then Scalar_4 (B0, B1, B2, B3) in 16#1_0000# .. 16#10_FFFF#
      then 4
      else 0)
   with
     Post => Sequence_Length'Result <= 4
             and then (if Sequence_Length'Result > 0
                       then Sequence_Length'Result <= Avail);

   --  Decode the one code point that starts at B0, given Avail (>= 1) bytes
   --  available from B0 onward and the next three bytes B1 .. B3 (or 0 where
   --  Avail says they are absent). On a well-formed sequence CP is its scalar
   --  value and Len (1 .. 4) its byte length. On ill-formed or truncated input
   --  CP is U+FFFD and Len is 1. Len never exceeds Avail, so a caller may always
   --  advance its cursor by Len. A caller that must REJECT (rather than display)
   --  malformed input tests Sequence_Length (..) > 0 first.
   procedure Decode
     (B0, B1, B2, B3 : Tui.Byte;
      Avail          : Positive;
      CP             : out Tui.Code_Point;
      Len            : out Positive)
   with
     Global => null,
     Post   => Len <= 4
               and then Len <= Avail
               and then (if Sequence_Length (B0, B1, B2, B3, Avail) = 0
                         then CP = Replacement and then Len = 1);

end Tui.UTF8;
