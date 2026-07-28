--  Ore — a SPARK library of proved building blocks for bounded, heap-free
--  systems code.
--
--  This root package carries only the *physical* types the whole hierarchy
--  shares: an octet, the machine words the endian operations move, and the
--  unconstrained byte array every buffer, view and algorithm is written
--  against. Logical models and proof vocabulary live with the operations they
--  describe, in the children:
--
--    Ore.Byte_Buffers — bounded byte buffers: produce/consume cursors,
--                       subviews, checked multi-byte access, copies.
--    Ore.Bits         — bit-level operations on the word types: shifts,
--                       rotates, masks, fields, counts, byte order.
--
--  DESIGN: no heap allocation, access-based design, tasking or direct OS
--  services. Every operation is bounded and total on its precondition; nothing
--  raises to report a full or an empty buffer. An assertion-enabled build may
--  still raise Assertion_Error when a precondition is violated. Contracts
--  speak about array elements rather than slices or functional sequences,
--  because that is what provers handle well at scale.
--
--  The word types are declared here rather than taken from Interfaces so that
--  a client writing `use Ore;` gets their operators, and so that the sources
--  need no context clause. Converting to or from Interfaces types is a plain
--  modular conversion where a client needs it. The endian layer decomposes
--  multi-byte values with multiplication and division by powers of two; the
--  shift and rotate instructions themselves are in Ore.Bits, which is where
--  contracts are stated bit by bit and need them.

package Ore
  with Pure, SPARK_Mode => On
is

   type Byte is mod 2 ** 8 with Size => 8;

   type Word16 is mod 2 ** 16 with Size => 16;
   type Word32 is mod 2 ** 32 with Size => 32;
   type Word64 is mod 2 ** 64 with Size => 64;

   --  Byte positions are 1-based and stop one short of Positive'Last, so that
   --  the position one past the end of any array — the natural "everything
   --  consumed" cursor and empty-span bound — is always computable without
   --  overflow.
   subtype Index is Positive range 1 .. Positive'Last - 1;

   type Byte_Array is array (Index range <>) of Byte;

   --  Which end of a multi-byte value a buffer stores first.
   type Byte_Order is (Little_Endian, Big_Endian);

   --  Largest capacity a bounded container of this library accepts. The cap
   --  is not a storage limit but an arithmetic one: it leaves room for bit
   --  positions (8 * Length) to stay inside Natural, so the bit-addressed
   --  layers can share these buffers without their own length ceiling.
   Max_Capacity : constant := 2 ** 27;

end Ore;
