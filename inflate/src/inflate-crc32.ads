--  Inflate.CRC32 — the CRC-32 used by gzip and ZIP (polynomial 0xEDB88320,
--  reflected, init and final XOR 0xFFFFFFFF; ISO 3309 / ITU-T V.42).
--
--  Table-driven, one byte per step; the table is computed at elaboration
--  from the polynomial rather than transcribed, so there is nothing to
--  mistype. All arithmetic is modular — proof of absence of run-time
--  errors is direct.

package Inflate.CRC32 with SPARK_Mode => On is

   --  The specification functions below are used while the lookup table is
   --  elaborated.  Keep their contracts proof-only so assertion-enabled
   --  builds do not create elaboration-order calls through postconditions.
   --  GNATprove still proves assertions under the Ignore policy.
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore, Ghost => Ignore);

   --  Reflected representation of the CRC-32 generator polynomial
   --
   --    x**32 + x**26 + x**23 + x**22 + x**16 + x**12
   --          + x**11 + x**10 + x**8 + x**7 + x**5 + x**4 + x**2 + x + 1.
   --
   --  Polynomial_Bit_Step is one division step in GF(2), least-significant
   --  coefficient first.  Polynomial_Byte_Remainder applies exactly eight
   --  such steps.  These functions are the table-independent mathematical
   --  specification; the body merely caches their 256 byte remainders.
   Reflected_Generator : constant Word32 := 16#EDB8_8320#;

   function Polynomial_Bit_Step (Remainder : Word32) return Word32
   with
     Global => null,
     Post   =>
       Polynomial_Bit_Step'Result =
         (if (Remainder and 1) /= 0
          then Shift_Right (Remainder, 1) xor Reflected_Generator
          else Shift_Right (Remainder, 1));

   function Polynomial_Bits_2 (Remainder : Word32) return Word32
   with
     Global => null,
     Post   =>
       Polynomial_Bits_2'Result =
         Polynomial_Bit_Step (Polynomial_Bit_Step (Remainder));

   function Polynomial_Bits_4 (Remainder : Word32) return Word32
   with
     Global => null,
     Post   =>
       Polynomial_Bits_4'Result =
         Polynomial_Bits_2 (Polynomial_Bits_2 (Remainder));

   function Polynomial_Bits_8 (Remainder : Word32) return Word32
   with
     Global => null,
     Post   =>
       Polynomial_Bits_8'Result =
         Polynomial_Bits_4 (Polynomial_Bits_4 (Remainder));

   function Polynomial_Byte_Remainder (B : Byte) return Word32
   with
     Global => null,
     Post   =>
       Polynomial_Byte_Remainder'Result = Polynomial_Bits_8 (Word32 (B));

   function Polynomial_Byte_Step (Remainder : Word32; B : Byte)
      return Word32
   with
     Global => null,
     Post   =>
       Polynomial_Byte_Step'Result =
         Polynomial_Bits_8 (Remainder xor Word32 (B));

   --  The functional model of the computation: the CRC state folded over
   --  the data bytes one at a time, front to back, with explicit cursors.
   --  Its recursion is as deep as the data is long, so the policy pragma
   --  below keeps the contracts referring to it — and the ghost entities
   --  themselves — from being evaluated at run time even in builds with
   --  assertions on; GNATprove still proves Ignore-policy assertions, so
   --  nothing is lost from the proof.
   --
   --  Fold is defined in terms of Polynomial_Byte_Step, not the lookup table.
   --  Thus Update's postcondition connects the optimized implementation to
   --  the polynomial specification rather than to a second table walk.
   function Fold
     (C : Word32; Data : Byte_Array; From : Positive; To : Natural)
      return Word32
   with
     Ghost,
     Global => null,
     Pre    => To <= Buffer_Index'Last
               and then From <= To + 1
               and then (if To >= From
                         then From >= Data'First and then To <= Data'Last),
     Subprogram_Variant => (Decreases => To - From);

   --  Continue a CRC over more data. Start from 0 (Compute does), feed
   --  consecutive slices, and the result equals the CRC of the whole.
   function Update (CRC : Word32; Data : Byte_Array) return Word32
   with
     Global => null,
     Post   =>
       Update'Result =
         (Fold (CRC xor 16#FFFF_FFFF#, Data,
                (if Data'Length > 0 then Data'First else 1),
                (if Data'Length > 0 then Data'Last else 0))
          xor 16#FFFF_FFFF#);

   --  CRC-32 of Data, as gzip and ZIP store it.
   function Compute (Data : Byte_Array) return Word32 is (Update (0, Data))
   with Global => null;

   --  The CRC depends only on the byte sequence, not on where it sits in
   --  a buffer: two ranges with equal content have equal CRCs. This is
   --  what lets a round-trip argument equate the checksum a compressor
   --  stored (over its input) with the one the decoder recomputes (over
   --  its own output buffer).
   procedure Lemma_Update_Content
     (CRC : Word32; D1 : Byte_Array; D2 : Byte_Array)
   with
     Ghost,
     Global => null,
     Pre  => D1'Length = D2'Length
             and then (for all K in 0 .. D1'Length - 1 =>
                         D2 (D2'First + K) = D1 (D1'First + K)),
     Post => Update (CRC, D2) = Update (CRC, D1);

end Inflate.CRC32;
