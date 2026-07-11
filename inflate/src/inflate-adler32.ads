--  Inflate.Adler32 — the zlib checksum (RFC 1950 §8.2): two mod-65521 sums,
--  the low one over the bytes, the high one over the running low sums.

package Inflate.Adler32 with SPARK_Mode => On is

   use type Interfaces.Unsigned_32;

   pragma Assertion_Policy (Pre => Ignore, Post => Ignore, Ghost => Ignore);

   --  Direct mathematical model.  Each component is reduced modulo the
   --  Adler prime after every input byte; Fold states Update's result as the
   --  two standard running sums.
   Base : constant Word32 := 65_521;

   type Component is mod 65_521;

   type State is record
      A : Component;
      B : Component;
   end record;

   function Initial_State (Adler : Word32) return State
   with
     Global => null,
     Post   =>
       Word32 (Initial_State'Result.A) =
         (Adler and 16#FFFF#) mod Base
       and then Word32 (Initial_State'Result.B) =
         Interfaces.Shift_Right (Adler, 16) mod Base;

   function Model_Byte_Step (S : State; Value : Byte) return State
   with
     Global => null,
     Post   =>
       Model_Byte_Step'Result.A = S.A + Component (Value)
       and then Model_Byte_Step'Result.B =
         S.B + S.A + Component (Value);

   function Pack (S : State) return Word32
   with
     Global => null,
     Post   =>
       Pack'Result =
         (Interfaces.Shift_Left (Word32 (S.B), 16) or Word32 (S.A));

   function Fold
     (S : State; Data : Byte_Array; From : Positive; To : Natural)
      return State
   with
     Ghost,
     Global => null,
     Pre    => To <= Buffer_Index'Last
               and then From <= To + 1
               and then (if To >= From
                         then From >= Data'First and then To <= Data'Last),
     Subprogram_Variant => (Decreases => To - From);

   --  Continue a checksum over more data. Start from 1 (Compute does), feed
   --  consecutive slices, and the result equals the checksum of the whole.
   function Update (Adler : Word32; Data : Byte_Array) return Word32
   with
     Global => null,
     Post   =>
       Update'Result =
         Pack
           (Fold
              (Initial_State (Adler), Data,
               (if Data'Length > 0 then Data'First else 1),
               (if Data'Length > 0 then Data'Last else 0)));

   --  Adler-32 of Data, as the zlib container stores it.
   function Compute (Data : Byte_Array) return Word32 is (Update (1, Data))
   with Global => null;

end Inflate.Adler32;
