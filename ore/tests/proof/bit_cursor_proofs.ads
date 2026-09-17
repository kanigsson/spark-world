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

   --  A client's model of a code: the value of its first Length bits, as the
   --  recursion over the length. A compressed format defines a code this way —
   --  one bit at a time, the first bit read weighing most — so this is the form
   --  a decoder's own specifications are stated and proved through, and there
   --  are usually a great many of them.
   function Prefix_Value
     (Input : Byte_Array; Start : Natural; Length : Value_Count) return Natural
   is (if Length = 0
       then 0
       else
         2
         * Prefix_Value (Input, Start, Length - 1)
         + Bit_Value (Input, Start + Length - 1, Numbering))
   with
     Ghost              => Static,
     Global             => null,
     Pre                => Fits (Input, Start, Length),
     Post               =>
       Prefix_Value'Result < 2 ** Length
       and then Prefix_Value'Result <= Natural'Last / 2,
     Subprogram_Variant => (Decreases => Length);

   --  The library's field is this model, at every width. This is the theorem a
   --  client cannot do without and should not have to write: the induction is
   --  one step per bit, and the step is the recurrence the library states, so
   --  what is left here is the induction and nothing about bits at all.
   procedure Lemma_Prefix_Value
     (Input : Byte_Array; Start : Natural; Length : Value_Count)
   with
     Ghost              => Static,
     Global             => null,
     Pre                => Fits (Input, Start, Length),
     Post               =>
       Field_Value (Input, Start, Length, Numbering, High_Bit_First)
       = Prefix_Value (Input, Start, Length),
     Subprogram_Variant => (Decreases => Length);

   --  What a model that sums the bits of a fixed-width code computes, written
   --  out rather than as a recursion. It is the same number, which the theorem
   --  above gives without any reasoning about bits: before the recurrence was
   --  in the library, this needed the bits of the field, the bound of its mask
   --  and an integer decomposition, all written here.
   function Code_Sum (A : Byte_Array; Position : Natural) return Natural
   is (4 * Bit_Value (A, Position, Numbering)
       + 2 * Bit_Value (A, Position + 1, Numbering)
       + Bit_Value (A, Position + 2, Numbering))
   with
     Global => null,
     Pre    => Fits (A, Position, Code_Width),
     Post   => Code_Sum'Result <= 7;

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
