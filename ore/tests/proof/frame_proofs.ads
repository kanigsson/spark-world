--  A proof client for Ore.Byte_Buffers: the small tag/length/payload framing
--  every wire protocol starts from, written the way a real client would write
--  it. Its purpose is not the frame format but the question "can a client
--  state and prove what it needs with the vocabulary the package exports?" —
--  in particular whether facts established by one append survive the next.

with Ore;              use Ore;
with Ore.Byte_Buffers; use Ore.Byte_Buffers;

package Frame_Proofs
  with SPARK_Mode => On
is

   --  A frame is a tag byte, a little-endian 16-bit payload length, then the
   --  payload.
   Header_Size : constant := 3;

   Max_Payload : constant := 16#FFFF#;

   --  Append one frame. The postcondition is the whole frame read back out of
   --  the buffer: the tag where it was written, the length field loadable as
   --  the payload length, and the payload itself — all of which have to survive
   --  the appends that came after them.
   procedure Write_Frame (B : in out Buffer; Tag : Byte; Payload : Byte_Array)
   with
     Global => null,
     Pre    =>
       Payload'Length <= Max_Payload
       and then Header_Size <= Available (B)
       and then Payload'Length <= Available (B) - Header_Size,
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + Header_Size + Payload'Length
          and then Read_Position (B) = Read_Position (B)'Old
          and then Element (B, Length (B)'Old + 1) = Tag
          and then
            Load_16 (B, Length (B)'Old + 2, Little_Endian)
            = Word16 (Payload'Length),
        Static  =>
          Same_Prefix (B'Old, B, Length (B)'Old)
          and then Matches_At (B, Length (B)'Old + Header_Size + 1, Payload));

   --  Read one frame back. Read_Frame is the inverse of Write_Frame: the
   --  round-trip property is that a buffer holding a written frame yields the
   --  tag and payload that went in, which the two contracts together give the
   --  caller without either subprogram mentioning the other.
   procedure Read_Frame
     (B       : in out Buffer;
      Tag     : out Byte;
      Payload : in out Byte_Array;
      Size    : out Natural)
   with
     Global => null,
     Pre    => Unread (B) >= Header_Size,
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old
          and then
            Size
            = Natural (Load_16 (B, Read_Position (B)'Old + 2, Little_Endian))
          and then Tag = Element (B, Read_Position (B)'Old + 1)
          and then
            (if Size
               <= Natural'Min (Unread (B)'Old - Header_Size, Payload'Length)
             then
               Read_Position (B) = Read_Position (B)'Old + Header_Size + Size
             else Read_Position (B) = Read_Position (B)'Old + Header_Size),
        Static  =>
          Same_Prefix (B'Old, B, Length (B))
          and then
            (if Size
               <= Natural'Min (Unread (B)'Old - Header_Size, Payload'Length)
             then
               (for all K in 0 .. Size - 1 =>
                  Payload (Payload'First + K)
                  = Element
                      (B, Read_Position (B)'Old + Header_Size + 1 + K))));

   --  A run of Count copies of Value, produced by writing the first byte and
   --  letting a distance-one back-reference repeat it. This is the smallest
   --  interesting use of the overlapping copy: the proof obligation is that
   --  every appended byte equals Value even though all but the first were
   --  copied from a byte the same operation had just written.
   procedure Write_Run (B : in out Buffer; Value : Byte; Count : Positive)
   with
     Global => null,
     Pre    => Count <= Available (B) and then Count <= Max_Capacity,
     Post   =>
       (Runtime =>
          Length (B) = Length (B)'Old + Count
          and then Read_Position (B) = Read_Position (B)'Old,
        Static  =>
          Same_Prefix (B'Old, B, Length (B)'Old)
          and then
            (for all K in 1 .. Count =>
               Element (B, Length (B)'Old + K) = Value));

   --  Drain the unread bytes of Source into Target, compacting Target whenever
   --  it fills, until Source is exhausted or Target cannot take more. The
   --  loop is here for its termination and cursor arithmetic, which is what a
   --  streaming client actually has to get right.
   procedure Drain
     (Source : in out Buffer; Target : in out Buffer; Moved : out Natural)
   with
     Global => null,
     Post   =>
       Moved = Read_Position (Source) - Read_Position (Source)'Old
       and then Length (Source) = Length (Source)'Old
       and then Read_Position (Source) <= Length (Source);

end Frame_Proofs;
