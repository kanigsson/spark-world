--  A proof client for Ore.Bits: the header word every packed binary format
--  starts from, and the question a client asks about the size of a value.
--  Its purpose is not the header layout but whether a client can state and
--  prove what it needs with the vocabulary the package exports — in
--  particular whether a field survives the insert of the next one, and
--  whether a bit-wise fact can be turned back into a fact about the value.

with Ore;      use Ore;
with Ore.Bits; use Ore.Bits;

package Bit_Proofs
  with SPARK_Mode => On
is

   --  A header word: a 4-bit version, a 6-bit type and a 1-bit flag, packed
   --  from the bottom up, with the remaining bits left clear.
   Version_Offset : constant := 0;
   Version_Width  : constant := 4;
   Kind_Offset    : constant := 4;
   Kind_Width     : constant := 6;
   Flag_Offset    : constant := 10;
   Flag_Width     : constant := 1;

   --  The postcondition is the whole header read back: each field where it
   --  was put, and nothing set above them. Each insert has to preserve the
   --  fields already written, which is what the frame half of Insert's
   --  contract gives the caller.
   function Pack (Version : Word32; Kind : Word32; Flag : Word32) return Word32
   with
     Global => null,
     Pre    =>
       Version <= Low_Mask_32 (Version_Width)
       and then Kind <= Low_Mask_32 (Kind_Width)
       and then Flag <= Low_Mask_32 (Flag_Width),
     Post   =>
       Extract (Pack'Result, Version_Offset, Version_Width) = Version
       and then Extract (Pack'Result, Kind_Offset, Kind_Width) = Kind
       and then Extract (Pack'Result, Flag_Offset, Flag_Width) = Flag
       and then Extract (Pack'Result, Flag_Offset + Flag_Width, 21) = 0;

   --  How many bits it takes to hold Value: zero for a zero word, otherwise
   --  one past the position of its most significant set bit. The two
   --  postconditions are the pair a caller wants — everything above the width
   --  is gone, and the width is not one too many — and the first of them is a
   --  statement about the value, reached from a statement about bits.
   function Significant_Bits (Value : Word32) return Natural
   with
     Global => null,
     Post   =>
       Significant_Bits'Result <= 32
       and then Shift_Right (Value, Significant_Bits'Result) = 0
       and then
         (if Significant_Bits'Result > 0
          then Bit (Value, Significant_Bits'Result - 1));

   --  A code read out of a word, bounded the way a client's own contracts bound
   --  it: a code of Length bits is below 2 ** Length, in the arithmetic a code
   --  length is counted in. Extract gives the bound as a mask, in the arithmetic
   --  of the word; this is the crossing between the two, and the point of the
   --  test is the body — one call, where a client wrote a case with one branch
   --  per width because a concrete exponent was the only thing that closed it.
   procedure Lemma_Code_Bound (Value : Word32; Length : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Length <= 30,
     Post   => Natural (Extract (Value, 0, Length)) < 2 ** Length;

   --  The same crossing for a weight rather than a code: what a Kraft sum over
   --  code lengths adds, taken from the operation that produces it as a word.
   procedure Lemma_Weight_Value (Length : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Length <= 30,
     Post   => Natural (Power_Of_Two_32 (Length)) = 2 ** Length;

end Bit_Proofs;
