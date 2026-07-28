--  A proof client for Ore.Bit_Cursors: the block header and the
--  variable-length code that a bit-packed compressed format begins with,
--  written over an array the caller owns. Its purpose is not the format but
--  the questions a client of this layer asks — does a field survive the put of
--  the next one, do two orders coexist on one cursor, does the bit view reach
--  the arithmetic model a client's own specification is written in, and can a
--  client that writes its bytes by hand still state the array-level frame?

with Ore;              use Ore;
with Ore.Bits;         use Ore.Bits;
with Ore.Bit_Cursors;  use Ore.Bit_Cursors;
with Ore.Byte_Buffers; use Ore.Byte_Buffers;

package Bit_Cursor_Proofs
  with SPARK_Mode => On
is

   --  This client's stream numbers the bits of each byte from the least
   --  significant end, and packs its header fields low bit first and its codes
   --  high bit first — two orders alternating on one cursor.
   Numbering : constant Bit_Numbering := Lsb_First;

   Final_Width  : constant := 1;
   Kind_Width   : constant := 2;
   Header_Width : constant := Final_Width + Kind_Width;

   Code_Width : constant := 3;

   ---------------------------------------------------------------------------
   --  A header of two fields
   ---------------------------------------------------------------------------

   --  Put a final flag and a two-bit kind at the cursor. The postcondition
   --  reads both fields back, which is the property that has to survive: the
   --  put of the kind must leave the flag alone, and the client shows that
   --  from the frame of the second put and the frame lemma of a read.
   procedure Put_Header
     (Output   : in out Byte_Array;
      Position : in out Natural;
      Final    : Boolean;
      Kind     : Word32;
      Success  : out Boolean)
   with
     Global => null,
     Pre    => Kind <= Low_Mask_32 (Kind_Width),
     Post   =>
       (Runtime =>
          Success = Fits (Output, Position'Old, Header_Width)
          and then
            (if Success
             then
               Position = Position'Old + Header_Width
               and then
                 Bits_At
                   (Output,
                    Position'Old,
                    Final_Width,
                    Numbering,
                    Low_Bit_First)
                 = (if Final then 1 else 0)
               and then
                 Bits_At
                   (Output,
                    Position'Old + Final_Width,
                    Kind_Width,
                    Numbering,
                    Low_Bit_First)
                 = Kind
             else Position = Position'Old),
        Static  =>
          (if Success
           then
             Bits_Unchanged_Outside
               (Output'Old, Output, Position'Old, Header_Width, Numbering)
           else Output = Output'Old));

   --  Take the same two fields back. Together with Put_Header this is the
   --  round trip, and neither contract mentions the other.
   procedure Take_Header
     (Input    : Byte_Array;
      Position : in out Natural;
      Final    : out Boolean;
      Kind     : out Word32;
      Success  : out Boolean)
   with
     Global => null,
     Post   =>
       (Runtime =>
          Success = Fits (Input, Position'Old, Header_Width)
          and then
            (if Success
             then
               Position = Position'Old + Header_Width
               and then
                 (if Final then 1 else 0)
                 = Bits_At
                     (Input,
                      Position'Old,
                      Final_Width,
                      Numbering,
                      Low_Bit_First)
               and then
                 Kind
                 = Bits_At
                     (Input,
                      Position'Old + Final_Width,
                      Kind_Width,
                      Numbering,
                      Low_Bit_First)
             else Position = Position'Old));

   ---------------------------------------------------------------------------
   --  A code, and the arithmetic view of it
   ---------------------------------------------------------------------------

   --  What a model that sums the bits of a code computes: the first bit read
   --  weighs most, because a code is read from its most significant bit. This
   --  is the shape a client's own specification of a decoder is written in,
   --  and it is stated with Bit_Value rather than with Bit for that reason.
   function Code_Sum (A : Byte_Array; Position : Natural) return Natural
   is (4 * Bit_Value (A, Position, Numbering)
       + 2 * Bit_Value (A, Position + 1, Numbering)
       + Bit_Value (A, Position + 2, Numbering))
   with
     Global => null,
     Pre    => Fits (A, Position, Code_Width),
     Post   => Code_Sum'Result <= 7;

   --  The field the library assembles is the number the model sums. This is
   --  the step from the bit view to the value view across a whole field, and a
   --  client needs it exactly once, here, to connect its model to the take.
   procedure Lemma_Code_Sum (A : Byte_Array; Position : Natural)
   with
     Ghost  => Static,
     Global => null,
     Pre    => Fits (A, Position, Code_Width),
     Post   =>
       Natural (Bits_At (A, Position, Code_Width, Numbering, High_Bit_First))
       = Code_Sum (A, Position);

   ---------------------------------------------------------------------------
   --  A client that writes its own bytes
   ---------------------------------------------------------------------------

   --  The masked store a client already has, with the array-level frame stated
   --  anyway. The point is that the frame is inherited rather than proved
   --  here: what this body does is establish the two halves the lemma asks
   --  for — one byte changed, and one bit within it.
   procedure Put_Bit_By_Hand
     (Output : in out Byte_Array; Position : Natural; Value : Boolean)
   with
     Global => null,
     Pre    => Fits (Output, Position, 1),
     Post   =>
       (Runtime => Bit (Output, Position, Numbering) = Value,
        Static  =>
          Bits_Unchanged_Outside (Output'Old, Output, Position, 1, Numbering));

end Bit_Cursor_Proofs;
