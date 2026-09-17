--  Implementation notes
--
--  The decoder follows the shape of the reference implementation of RFC
--  1951 (zlib's puff): a little-endian bit reader over the input, canonical
--  Huffman tables represented as per-length symbol counts plus a symbol
--  array sorted by code, and bit-at-a-time decoding. That shape was chosen
--  because every quantity in it has small static bounds, which is what
--  makes absence of run-time errors provable.
--
--  Proof approach: the bit reader's state validity (cursor within input,
--  at most 7 buffered bits between calls) travels through pre- and
--  postconditions; loop termination rests on the total number of consumed
--  bits, which every code path strictly increases. Where a bound is a
--  consequence of a whole-table property that would need ghost summation
--  to prove (the symbol offsets of a constructed table never exceed the
--  table size), a defensive check turns the unreachable case into an error
--  status instead — the proof then needs only the check, and the behavior
--  on (impossible) violation is still defined.

with Inflate.LZ77;
with Inflate.Fixed;
with Inflate.Dynamic;

package body Inflate.Raw with SPARK_Mode => On is

   --  The proof machinery in this body — ghost snapshots of whole
   --  buffers, lemma invocations, and invariants that re-walk the
   --  recursive decode-model relation — costs time proportional to the
   --  data on every evaluation; executed as assertions it would make
   --  decoding quadratic. This policy keeps it out of assertion-enabled
   --  executables; GNATprove proves Ignore-policy assertions all the
   --  same, and the contracts in the spec remain executable.
   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   ---------------------------------------------------------------------
   --  Bit stream
   ---------------------------------------------------------------------

   --  Cursors into the caller's buffers plus up to 7 buffered bits.
   --  DEFLATE packs bits least-significant-first within bytes.
   type Stream_State is record
      Consumed : Natural;                --  input bytes taken so far
      Bit_Buf  : Word32;                 --  buffered bits, LSB next
      Bit_Cnt  : Natural range 0 .. 31;  --  valid bits in Bit_Buf
      Produced : Natural;                --  output bytes written so far
   end record;

   --  Total bits consumed; strictly increases on every decode path, which
   --  is what the loop variants measure. Refilling the buffer moves bits
   --  from the input to the buffer and leaves this unchanged.
   function Bit_Position (S : Stream_State) return Long_Long_Integer is
     (Long_Long_Integer (S.Consumed) * 8 - Long_Long_Integer (S.Bit_Cnt))
   with Ghost;

   --  The state is well-formed against a given input buffer: the cursor is
   --  within bounds and the buffer holds no more bits than were consumed
   --  (so whole buffered bytes can always be pushed back, which is how
   --  stored-block alignment and the final consumed count stay byte-exact).
   function Valid_In (Input : Byte_Array; S : Stream_State) return Boolean is
     (S.Consumed <= Input'Length and then Bit_Position (S) >= 0)
   with Ghost;

   subtype Bit_Request is Natural range 0 .. 16;

   --  The low N bits set, and the value of a field that wide: Ore's mask
   --  states both the bits it sets and the number it is, so the low-bit mask
   --  no longer needs a table beside it. Truncating to Natural is exact for
   --  every request width here, all of them well under 32.
   function Mask (N : Bit_Request) return Natural is
     (Natural (Bits.Low_Mask_32 (N)));

   --  2**N as a lookup table: the provers reason about a concrete array by
   --  case enumeration, where a variable exponent would need power-function
   --  lemmas they do not reliably find.
   Pow2 : constant array (Natural range 0 .. 16) of Natural :=
     (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192,
      16384, 32768, 65536);

   --  Take the next N bits of the stream, least significant first. Good is
   --  False iff the input ran out, in which case the state is unchanged.
   --
   --  The last two postconditions refine the two state shapes the
   --  stored-block decode path meets, enough to pin the values read from
   --  a block header: at a byte boundary with an empty buffer the value
   --  is the low bits of the next input byte, and a read satisfied from
   --  the buffer touches no input.
   procedure Get_Bits
     (Input : in     Byte_Array;
      S     : in out Stream_State;
      N     : in     Bit_Request;
      Value :    out Natural;
      Good    :    out Boolean)
   with
     Global => null,
     Pre    => Valid_In (Input, S),
     Post   =>
       S.Produced = S.Produced'Old
       and then (if Good
                 then Valid_In (Input, S)
                      and then Value <= Mask (N)
                      and then Bit_Position (S) =
                                 Bit_Position (S'Old) + Long_Long_Integer (N)
                 else S = S'Old
                      and then Long_Long_Integer (Input'Length) * 8 -
                                 Bit_Position (S'Old) < Long_Long_Integer (N))
       and then (if Good
                    and then S.Bit_Cnt'Old = 0
                    and then S.Bit_Buf'Old = 0
                    and then N in 1 .. 8
                 then S.Consumed = S.Consumed'Old + 1
                      and then S.Bit_Cnt = 8 - N
                      and then S.Consumed'Old < Input'Length
                      and then Word32 (Value) =
                                 (Word32 (Input (Input'First + S.Consumed'Old))
                                  and Bits.Low_Mask_32 (N))
                      and then S.Bit_Buf =
                                 Shift_Right
                                   (Word32
                                      (Input (Input'First + S.Consumed'Old)),
                                    N))
       and then (if Good and then N <= S.Bit_Cnt'Old
                 then S.Consumed = S.Consumed'Old
                      and then S.Bit_Cnt = S.Bit_Cnt'Old - N
                      and then Word32 (Value) =
                                 (S.Bit_Buf'Old and Bits.Low_Mask_32 (N))
                      and then S.Bit_Buf = Shift_Right (S.Bit_Buf'Old, N))
   is
      Buf : Word32 := S.Bit_Buf;
      Cnt : Natural range 0 .. 31 := S.Bit_Cnt;
      Pos : Natural := S.Consumed;
   begin
      while Cnt < N loop
         pragma Loop_Invariant (Pos in S.Consumed .. Input'Length);
         pragma Loop_Invariant (Cnt < N);
         pragma Loop_Invariant
           (Long_Long_Integer (Pos) * 8 - Long_Long_Integer (Cnt) =
              Bit_Position (S));
         --  In the byte-aligned case (N <= 8 fits in one byte) the loop
         --  body runs exactly once, so at the top nothing has happened yet.
         pragma Loop_Invariant
           (if S.Bit_Cnt = 0 and then S.Bit_Buf = 0 and then N <= 8
            then Cnt = 0 and then Buf = 0 and then Pos = S.Consumed);
         pragma Loop_Variant (Increases => Cnt);
         if Pos >= Input'Length then
            Value := 0;
            Good    := False;
            return;
         end if;
         Buf := Buf or
           Shift_Left (Word32 (Input (Input'First + Pos)), Cnt);
         Pos := Pos + 1;
         Cnt := Cnt + 8;
      end loop;
      Value := Natural (Buf and Bits.Low_Mask_32 (N));
      S.Bit_Buf  := Shift_Right (Buf, N);
      S.Bit_Cnt  := Cnt - N;
      S.Consumed := Pos;
      Good := True;
   end Get_Bits;

   ---------------------------------------------------------------------
   --  Canonical Huffman tables
   ---------------------------------------------------------------------

   Max_Symbols : constant := 288;  --  the fixed literal/length code's size

   subtype Code_Length     is Natural range 0 .. 15;
   subtype Code_Length_Pos is Code_Length range 1 .. 15;
   subtype Symbol_Count    is Natural range 0 .. Max_Symbols;
   subtype Symbol_Value    is Natural range 0 .. Max_Symbols - 1;

   type Length_Count_Array is array (Code_Length_Pos) of Symbol_Count;
   type Symbol_Map         is array (Symbol_Value) of Symbol_Value;

   --  Fast path: a single-level lookup over the next Fast_Bits stream bits.
   --  Each entry packs symbol * 16 + code length for codes no longer than
   --  Fast_Bits; 0 means "not resolvable here" (a longer code, or junk
   --  under an incomplete code) and falls back to the bit-by-bit decoder.
   --  Stream bits arrive least-significant-first, so entries are laid out
   --  by the *reversed* code: one code of length L owns every index whose
   --  low L bits equal its reversal.
   Fast_Bits : constant := 10;
   subtype Fast_Index is Natural range 0 .. 2 ** Fast_Bits - 1;
   type Fast_Map is array (Fast_Index) of Word16;

   --  Counts(L) is the number of codes of length L; Symbols lists the coded
   --  symbols ordered by code value, which for a canonical code means by
   --  (length, symbol). That pair fully determines the code. Fast is the
   --  derived lookup table; the bit-by-bit decoder uses only Counts and
   --  Symbols, and every fast-path answer is one that decoder would give.
   type Huffman_Table is record
      Counts  : Length_Count_Array;
      Symbols : Symbol_Map;
      Fast    : Fast_Map;
   end record;

   --  Code lengths as read from the stream. The index range accommodates
   --  the largest use: HLIT + HDIST combined lengths (up to 316).
   subtype Length_Index is Natural range 0 .. 319;
   type Code_Length_Array is array (Length_Index range <>) of Code_Length;

   --  The low L bits of V, reversed — a canonical code as the stream
   --  presents it to a least-significant-bit-first reader.
   function Bit_Reverse
     (V : Natural;
      L : Natural)
      return Fast_Index
   with
     Global => null,
     Pre    => L in 1 .. Fast_Bits
   is
      R : Fast_Index := 0;
   begin
      for I in 0 .. L - 1 loop
         pragma Loop_Invariant (R < Pow2 (I));
         R := R * 2 + (V / Pow2 (I)) mod 2;
      end loop;
      return R;
   end Bit_Reverse;

   --  Fill the fast lookup table from Counts/Symbols (see Fast_Map above).
   --  Walks the canonical codes shortest-first, exactly like the decoder;
   --  the defensive slot check mirrors the decoder's.
   procedure Build_Fast (Table : in out Huffman_Table)
   with
     Global => null
   is
      Code  : Natural := 0;  --  first code of the current length
      Index : Natural := 0;  --  its slot in Symbols
      Count : Symbol_Count;
      Step  : Natural;
      J     : Natural;
   begin
      Table.Fast := (others => 0);
      for Len in 1 .. Fast_Bits loop
         pragma Loop_Invariant (Code <= Pow2 (Len));
         pragma Loop_Invariant (Index <= Max_Symbols * Len);
         Count := Table.Counts (Len);
         exit when Count > Pow2 (Len) - Code;          --  defensive
         exit when Index > Max_Symbols - Count;        --  defensive
         for K in 0 .. Count - 1 loop
            Step := Pow2 (Len);
            J := Bit_Reverse (Code + K, Len);
            while J <= Fast_Index'Last loop
               pragma Loop_Variant (Increases => J);
               Table.Fast (J) := Word16
                 (Table.Symbols (Index + K) * 16 + Len);
               J := J + Step;
            end loop;
         end loop;
         Index := Index + Count;
         Code  := (Code + Count) * 2;
      end loop;
   end Build_Fast;

   --  Build the canonical table for the given code lengths (length 0 =
   --  symbol not coded). Valid is False iff the lengths over-subscribe the
   --  code space (or an internal bound would be exceeded, which cannot
   --  happen for in-range inputs); Complete tells whether they fill it
   --  exactly. Symbols are stored relative to Lengths'First. With_Fast
   --  controls whether the fast lookup table is derived too — worthwhile
   --  for the tables symbols are decoded from, not for the code-length
   --  code that only decodes a few hundred bits of header.
   procedure Construct
     (Lengths   : in     Code_Length_Array;
      Table     :    out Huffman_Table;
      Complete  :    out Boolean;
      Valid     :    out Boolean;
      With_Fast : in     Boolean := True)
   with
     Global => null,
     Pre    => Lengths'Length in 1 .. Max_Symbols
   is
      Offs : array (Code_Length_Pos) of Symbol_Count := (others => 0);
      Left : Integer range -Max_Symbols .. 2 ** 15;
   begin
      Table    := (Counts  => (others => 0),
                   Symbols => (others => 0),
                   Fast    => (others => 0));
      Complete := False;
      Valid    := False;

      for I in Lengths'Range loop
         pragma Loop_Invariant
           (for all L in Code_Length_Pos =>
              Table.Counts (L) <= I - Lengths'First);
         if Lengths (I) /= 0 then
            Table.Counts (Lengths (I)) := Table.Counts (Lengths (I)) + 1;
         end if;
      end loop;

      --  Reject an over-subscribed set of lengths (more codes of some
      --  length than the code space has room for).
      Left := 1;
      for Len in Code_Length_Pos loop
         pragma Loop_Invariant (Left in 0 .. 2 ** (Len - 1));
         Left := Left * 2 - Table.Counts (Len);
         if Left < 0 then
            return;
         end if;
      end loop;
      Complete := Left = 0;

      --  First slot in Symbols for each code length: lengths are laid out
      --  consecutively, shortest first. The bound check cannot fail (the
      --  counts sum to at most Lengths'Length), but proving that needs a
      --  ghost summation; checking it is free and keeps the proof local.
      for Len in 2 .. 15 loop
         if Offs (Len - 1) > Max_Symbols - Table.Counts (Len - 1) then
            return;
         end if;
         Offs (Len) := Offs (Len - 1) + Table.Counts (Len - 1);
      end loop;

      for I in Lengths'Range loop
         if Lengths (I) /= 0 then
            if Offs (Lengths (I)) > Symbol_Map'Last then
               return;
            end if;
            Table.Symbols (Offs (Lengths (I))) := I - Lengths'First;
            Offs (Lengths (I)) := Offs (Lengths (I)) + 1;
         end if;
      end loop;

      if With_Fast then
         Build_Fast (Table);
      end if;

      Valid := True;
   end Construct;

   --  Decode one symbol, reading one bit at a time. For each length the
   --  canonical code's first code value (First) and first symbol slot
   --  (Index) advance by the count of codes at that length; a code value
   --  inside the current length's window identifies a symbol.
   procedure Decode
     (Input  : in     Byte_Array;
      S      : in out Stream_State;
      Table  : in     Huffman_Table;
      Symbol :    out Symbol_Value;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Valid_In (Input, S),
     Post   =>
       S.Produced = S.Produced'Old
       and then Valid_In (Input, S)
       and then Bit_Position (S) >= Bit_Position (S'Old)
       and then (if Status = OK
                 then Bit_Position (S) > Bit_Position (S'Old))
   is
      Code  : Natural := 0;
      First : Natural := 0;
      Index : Natural := 0;
      Count : Symbol_Count;
      B     : Natural;
      Good    : Boolean;
   begin
      Symbol := 0;
      for Len in Code_Length_Pos loop
         pragma Loop_Invariant (Valid_In (Input, S));
         pragma Loop_Invariant (S.Produced = S.Produced'Loop_Entry);
         pragma Loop_Invariant
           (Bit_Position (S) =
              Bit_Position (S'Loop_Entry) + Long_Long_Integer (Len - 1));
         pragma Loop_Invariant (Code mod 2 = 0 and then Code < Pow2 (Len));
         pragma Loop_Invariant (First <= Code);
         pragma Loop_Invariant (Index <= Max_Symbols * Len);
         Get_Bits (Input, S, 1, B, Good);
         if not Good then
            Status := Truncated_Input;
            return;
         end if;
         Code  := Code + B;
         Count := Table.Counts (Len);
         if Code - First < Count then
            --  The slot bound holds for every table Construct accepts;
            --  checking it keeps the proof local (see Construct).
            if Index <= Symbol_Map'Last - (Code - First) then
               Symbol := Table.Symbols (Index + (Code - First));
               Status := OK;
            else
               Status := Invalid_Symbol;
            end if;
            return;
         end if;
         pragma Assert (Pow2 (Len) <= 32768);
         Index := Index + Count;
         First := (First + Count) * 2;
         Code  := Code * 2;
      end loop;
      --  No code is longer than 15 bits: the bits read do not match any
      --  coded symbol (possible only for an incomplete code).
      Status := Invalid_Symbol;
   end Decode;

   --  Decode one symbol through the fast table when the next Fast_Bits
   --  stream bits resolve it, falling back to the bit-by-bit decoder for
   --  long codes and near the end of the input. Semantically identical to
   --  Decode: the table is derived from the same Counts/Symbols.
   procedure Decode_Fast
     (Input  : in     Byte_Array;
      S      : in out Stream_State;
      Table  : in     Huffman_Table;
      Symbol :    out Symbol_Value;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Valid_In (Input, S),
     Post   =>
       S.Produced = S.Produced'Old
       and then Valid_In (Input, S)
       and then Bit_Position (S) >= Bit_Position (S'Old)
       and then (if Status = OK
                 then Bit_Position (S) > Bit_Position (S'Old))
   is
   begin
      --  Top up the buffer; moving bits from input to buffer leaves the
      --  bit position unchanged.
      while S.Bit_Cnt < 15 and then S.Consumed < Input'Length loop
         pragma Loop_Invariant (S.Consumed < Input'Length);
         pragma Loop_Invariant (Valid_In (Input, S));
         pragma Loop_Invariant (S.Produced = S.Produced'Loop_Entry);
         pragma Loop_Invariant (Bit_Position (S) = Bit_Position (S'Loop_Entry));
         pragma Loop_Variant (Increases => S.Bit_Cnt);
         S.Bit_Buf := S.Bit_Buf or
           Shift_Left (Word32 (Input (Input'First + S.Consumed)), S.Bit_Cnt);
         S.Consumed := S.Consumed + 1;
         S.Bit_Cnt  := S.Bit_Cnt + 8;
      end loop;

      if S.Bit_Cnt >= Fast_Bits then
         declare
            E   : constant Natural :=
              Natural (Table.Fast
                         (Natural (S.Bit_Buf and Word32 (Fast_Index'Last))));
            L   : constant Natural := E mod 16;
            Sym : constant Natural := E / 16;
         begin
            if L in 1 .. Fast_Bits and then Sym <= Symbol_Value'Last then
               S.Bit_Buf := Shift_Right (S.Bit_Buf, L);
               S.Bit_Cnt := S.Bit_Cnt - L;
               Symbol := Sym;
               Status := OK;
               return;
            end if;
         end;
      end if;

      Decode (Input, S, Table, Symbol, Status);
   end Decode_Fast;

   ---------------------------------------------------------------------
   --  Compressed blocks (fixed and dynamic codes share this loop)
   ---------------------------------------------------------------------

   --  Base values and extra-bit counts for length symbols 257 .. 285 and
   --  distance symbols 0 .. 29 (RFC 1951 §3.2.5).
   subtype Length_Sym_Index is Natural range 0 .. 28;
   Length_Base : constant array (Length_Sym_Index) of Natural :=
     (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43,
      51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
   Length_Extra : constant array (Length_Sym_Index) of Bit_Request :=
     (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4,
      4, 4, 5, 5, 5, 5, 0);

   subtype Dist_Sym_Index is Natural range 0 .. 29;
   Dist_Base : constant array (Dist_Sym_Index) of Natural :=
     (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257,
      385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
      16385, 24577);
   Dist_Extra : constant array (Dist_Sym_Index) of Bit_Request :=
     (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9,
      10, 10, 11, 11, 12, 12, 13, 13);

   --  Decode literal/length symbols until end-of-block, emitting literals
   --  and back-references into the output.
   procedure Codes
     (Input      : in     Byte_Array;
      Output     : in out Byte_Array;
      S          : in out Stream_State;
      Lit_Table  : in     Huffman_Table;
      Dist_Table : in     Huffman_Table;
      Status     :    out Status_Type)
   with
     Global => null,
     Pre    => Valid_In (Input, S) and then S.Produced <= Output'Length,
     Post   => Valid_In (Input, S) and then S.Produced <= Output'Length
               and then Bit_Position (S) >= Bit_Position (S'Old)
   is
      Symbol : Symbol_Value;
      DSym   : Symbol_Value;
      Extra  : Natural;
      Len    : Natural;
      Dist   : Natural;
      Good     : Boolean;
   begin
      loop
         pragma Loop_Invariant
           (Valid_In (Input, S) and then S.Produced <= Output'Length);
         pragma Loop_Invariant
           (Bit_Position (S) >= Bit_Position (S'Loop_Entry));
         pragma Loop_Variant (Increases => Bit_Position (S));

         Decode_Fast (Input, S, Lit_Table, Symbol, Status);
         if Status /= OK then
            return;
         end if;

         if Symbol < 256 then
            --  A literal byte
            if S.Produced >= Output'Length then
               Status := Output_Too_Small;
               return;
            end if;
            Output (Output'First + S.Produced) := Byte (Symbol);
            S.Produced := S.Produced + 1;

         elsif Symbol = 256 then
            --  End of block
            Status := OK;
            return;

         elsif Symbol <= 285 then
            --  A back-reference: length, then distance
            Get_Bits (Input, S, Length_Extra (Symbol - 257), Extra, Good);
            if not Good then
               Status := Truncated_Input;
               return;
            end if;
            Len := Length_Base (Symbol - 257) + Extra;

            Decode_Fast (Input, S, Dist_Table, DSym, Status);
            if Status /= OK then
               return;
            end if;
            if DSym > Dist_Sym_Index'Last then
               Status := Invalid_Distance_Symbol;
               return;
            end if;
            Get_Bits (Input, S, Dist_Extra (DSym), Extra, Good);
            if not Good then
               Status := Truncated_Input;
               return;
            end if;
            Dist := Dist_Base (DSym) + Extra;

            if Dist > S.Produced then
               Status := Distance_Too_Far;
               return;
            end if;
            if Len > Output'Length - S.Produced then
               Status := Output_Too_Small;
               return;
            end if;
            --  The match copy is factored into the M4 primitive whose
            --  postcondition is the LZ77 window equation, including overlap.
            Inflate.LZ77.Copy_Match (Output, S.Produced, Len, Dist);

         else
            --  285 < Symbol: reserved symbols 286/287
            Status := Invalid_Length_Symbol;
            return;
         end if;
      end loop;
   end Codes;

   ---------------------------------------------------------------------
   --  Stored (uncompressed) blocks
   ---------------------------------------------------------------------

   --  Contract vocabulary for Stored, phrased on the pre-call state: the
   --  byte offset (from Input'First) where the block's LEN field begins
   --  once whole buffered bytes are pushed back, the LEN value there, and
   --  the condition under which the block is well formed and fits.

   function Realigned (S : Stream_State) return Natural is
     (S.Consumed - S.Bit_Cnt / 8)
   with Ghost, Pre => S.Consumed >= S.Bit_Cnt / 8;

   function Stored_Len (Input : Byte_Array; P : Natural) return Natural is
     (Natural (Input (Input'First + P))
      + 256 * Natural (Input (Input'First + P + 1)))
   with Ghost, Pre => P <= Input'Length - 2;

   function Stored_Fits
     (Input : Byte_Array; P : Natural; Room : Natural) return Boolean
   is
     (Input'Length - P >= 4
      and then Natural (Input (Input'First + P + 2))
               + 256 * Natural (Input (Input'First + P + 3)) =
                 16#FFFF# - Stored_Len (Input, P)
      and then Stored_Len (Input, P) <= Input'Length - (P + 4)
      and then Stored_Len (Input, P) <= Room)
   with Ghost, Pre => P <= Input'Length;

   --  Decode one stored block. Success is exactly Stored_Fits on the
   --  pre-call state; on success the block is consumed to a byte
   --  boundary, its payload lands verbatim after the output already
   --  produced, and that earlier output is untouched — the facts the
   --  decode half of the round-trip theorem accumulates per block.
   procedure Stored
     (Input  : in     Byte_Array;
      Output : in out Byte_Array;
      S      : in out Stream_State;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Valid_In (Input, S) and then S.Produced <= Output'Length,
     Post   => Valid_In (Input, S) and then S.Produced <= Output'Length
               and then Bit_Position (S) >= Bit_Position (S'Old)
               and then S.Produced >= S.Produced'Old
               and then (Status = OK) =
                          Stored_Fits (Input, Realigned (S'Old),
                                       Output'Length - S.Produced'Old)
               and then (if Status = OK
                         then S.Bit_Cnt = 0
                           and then S.Bit_Buf = 0
                           and then S.Consumed =
                                      Realigned (S'Old) + 4
                                      + Stored_Len (Input, Realigned (S'Old))
                           and then S.Produced =
                                      S.Produced'Old
                                      + Stored_Len (Input, Realigned (S'Old))
                           and then (for all K in
                                       0 .. Stored_Len
                                              (Input, Realigned (S'Old)) - 1 =>
                                       Output (Output'First
                                               + (S.Produced'Old + K)) =
                                       Input (Input'First
                                              + (Realigned (S'Old) + 4 + K)))
                           and then (for all K in 0 .. S.Produced'Old - 1 =>
                                       Output (Output'First + K) =
                                       Output'Old (Output'First + K)))
   is
      Len, NLen : Natural;
   begin
      --  Stored blocks restart at a byte boundary. Whole bytes sitting in
      --  the bit buffer are pushed back to the input (the state invariant
      --  guarantees they fit), and the remaining sub-byte bits are the
      --  padding this block type discards.
      S.Consumed := S.Consumed - S.Bit_Cnt / 8;
      S.Bit_Buf  := 0;
      S.Bit_Cnt  := 0;

      if Input'Length - S.Consumed < 4 then
         Status := Truncated_Input;
         return;
      end if;
      Len := Natural (Input (Input'First + S.Consumed))
        + 256 * Natural (Input (Input'First + S.Consumed + 1));
      NLen := Natural (Input (Input'First + S.Consumed + 2))
        + 256 * Natural (Input (Input'First + S.Consumed + 3));
      S.Consumed := S.Consumed + 4;
      if NLen /= 16#FFFF# - Len then
         Status := Invalid_Stored_Length;
         return;
      end if;

      if Len > Input'Length - S.Consumed then
         Status := Truncated_Input;
         return;
      end if;
      if Len > Output'Length - S.Produced then
         Status := Output_Too_Small;
         return;
      end if;
      if Len > 0 then
         Output (Output'First + S.Produced ..
                 Output'First - 1 + S.Produced + Len) :=
           Input (Input'First + S.Consumed ..
                  Input'First - 1 + S.Consumed + Len);
         S.Produced := S.Produced + Len;
         S.Consumed := S.Consumed + Len;
      end if;
      Status := OK;
   end Stored;

   ---------------------------------------------------------------------
   --  Code tables for the two compressed block types
   ---------------------------------------------------------------------

   --  The fixed tables (RFC 1951 §3.2.6), built on demand from their
   --  defining lengths rather than cached, keeping the decoder stateless.
   --  The fixed distance code (30 codes of length 5) is deliberately
   --  incomplete; the two unused patterns decode to symbols 30/31 and are
   --  rejected as reserved.
   procedure Build_Fixed
     (Lit_Table  : out Huffman_Table;
      Dist_Table : out Huffman_Table;
      Valid      : out Boolean)
   with
     Global => null
   is
      Lit_Lengths : constant Code_Length_Array (0 .. 287) :=
        (0 .. 143 => 8, 144 .. 255 => 9, 256 .. 279 => 7, 280 .. 287 => 8);
      Dist_Lengths : constant Code_Length_Array (0 .. 29) := (others => 5);
      Complete_L, Complete_D, Valid_L, Valid_D : Boolean;
      pragma Warnings (Off, Complete_D,
                       Reason => "the fixed distance code is incomplete");
   begin
      Construct (Lit_Lengths, Lit_Table, Complete_L, Valid_L);
      Construct (Dist_Lengths, Dist_Table, Complete_D, Valid_D);
      Valid := Valid_L and then Valid_D and then Complete_L;
   end Build_Fixed;

   --  Read a dynamic block header (RFC 1951 §3.2.7): the code-length code,
   --  then the run-length-encoded literal/length and distance code lengths,
   --  then build both tables.
   procedure Dynamic_Header
     (Input      : in     Byte_Array;
      S          : in out Stream_State;
      Lit_Table  :    out Huffman_Table;
      Dist_Table :    out Huffman_Table;
      Status     :    out Status_Type)
   with
     Global => null,
     Pre    => Valid_In (Input, S),
     Post   =>
       Valid_In (Input, S)
       and then S.Produced = S.Produced'Old
       and then Bit_Position (S) >= Bit_Position (S'Old)
   is
      --  Order in which the code-length code's lengths are transmitted
      Order : constant array (0 .. 18) of Natural range 0 .. 18 :=
        (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);

      HLit, HDist, HCLen : Natural;
      CL_Lengths : Code_Length_Array (0 .. 18)  := (others => 0);
      Lengths    : Code_Length_Array (0 .. 315) := (others => 0);
      CL_Table   : Huffman_Table;
      B, I, Rep  : Natural;
      Prev       : Code_Length;
      Sym        : Symbol_Value;
      Good, Valid, Complete : Boolean;

      Empty : constant Huffman_Table :=
        (Counts  => (others => 0),
         Symbols => (others => 0),
         Fast    => (others => 0));
   begin
      Lit_Table  := Empty;
      Dist_Table := Empty;

      Get_Bits (Input, S, 5, B, Good);
      if not Good then
         Status := Truncated_Input;
         return;
      end if;
      HLit := 257 + B;
      Get_Bits (Input, S, 5, B, Good);
      if not Good then
         Status := Truncated_Input;
         return;
      end if;
      HDist := 1 + B;
      Get_Bits (Input, S, 4, B, Good);
      if not Good then
         Status := Truncated_Input;
         return;
      end if;
      HCLen := 4 + B;

      if HLit > 286 or else HDist > 30 then
         Status := Invalid_Header_Counts;
         return;
      end if;

      for J in 0 .. HCLen - 1 loop
         pragma Loop_Invariant (Valid_In (Input, S));
         pragma Loop_Invariant (S.Produced = S.Produced'Loop_Entry);
         pragma Loop_Invariant
           (Bit_Position (S) >= Bit_Position (S'Loop_Entry));
         Get_Bits (Input, S, 3, B, Good);
         if not Good then
            Status := Truncated_Input;
            return;
         end if;
         CL_Lengths (Order (J)) := B;
      end loop;

      Construct (CL_Lengths, CL_Table, Complete, Valid, With_Fast => False);
      if not Valid or else not Complete then
         Status := Invalid_Code_Lengths;
         return;
      end if;

      --  The HLit literal/length and HDist distance code lengths form one
      --  sequence, run-length encoded by symbols 16 (repeat previous),
      --  17 and 18 (runs of zero).
      I := 0;
      while I < HLit + HDist loop
         pragma Loop_Invariant (I <= 315);
         pragma Loop_Invariant (Valid_In (Input, S));
         pragma Loop_Invariant (S.Produced = S.Produced'Loop_Entry);
         pragma Loop_Invariant
           (Bit_Position (S) >= Bit_Position (S'Loop_Entry));
         pragma Loop_Variant (Increases => I);

         Decode (Input, S, CL_Table, Sym, Status);
         if Status /= OK then
            return;
         end if;

         if Sym <= 15 then
            Lengths (I) := Sym;
            I := I + 1;
         else
            case Sym is
               when 16 =>
                  if I = 0 then
                     Status := Invalid_Repeat;
                     return;
                  end if;
                  Prev := Lengths (I - 1);
                  Get_Bits (Input, S, 2, B, Good);
                  if not Good then
                     Status := Truncated_Input;
                     return;
                  end if;
                  Rep := 3 + B;
               when 17 =>
                  Prev := 0;
                  Get_Bits (Input, S, 3, B, Good);
                  if not Good then
                     Status := Truncated_Input;
                     return;
                  end if;
                  Rep := 3 + B;
               when 18 =>
                  Prev := 0;
                  Get_Bits (Input, S, 7, B, Good);
                  if not Good then
                     Status := Truncated_Input;
                     return;
                  end if;
                  Rep := 11 + B;
               when others =>
                  --  The code-length table is built over 19 symbols, so
                  --  this cannot decode; defensive, like the slot check.
                  Status := Invalid_Code_Lengths;
                  return;
            end case;
            if Rep > HLit + HDist - I then
               Status := Invalid_Repeat;
               return;
            end if;
            for K in 1 .. Rep loop
               pragma Loop_Invariant (I = I'Loop_Entry + (K - 1));
               Lengths (I) := Prev;
               I := I + 1;
            end loop;
         end if;
      end loop;

      --  Build the two tables. An incomplete code is tolerated only in
      --  the degenerate case where at most one symbol is coded (one code
      --  of length 1) — the same rule the reference implementations apply.
      Construct (Lengths (0 .. HLit - 1), Lit_Table, Complete, Valid);
      if not Valid
        or else (not Complete
                 and then not (for all L in 2 .. 15 =>
                                 Lit_Table.Counts (L) = 0))
      then
         Status := Invalid_Literal_Code;
         return;
      end if;

      Construct
        (Lengths (HLit .. HLit + HDist - 1), Dist_Table, Complete, Valid);
      if not Valid
        or else (not Complete
                 and then not (for all L in 2 .. 15 =>
                                 Dist_Table.Counts (L) = 0))
      then
         Status := Invalid_Distance_Code;
         return;
      end if;

      Status := OK;
   end Dynamic_Header;

   ---------------------------------------------------------------------
   --  The block loop
   ---------------------------------------------------------------------

   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   is
      S : Stream_State :=
        (Consumed => 0, Bit_Buf => 0, Bit_Cnt => 0, Produced => 0);
      BFinal, BType : Natural;
      Good, Valid     : Boolean;
      Fixed_Success, Dynamic_Success : Boolean;
      Lit_Table, Dist_Table : Huffman_Table;

      --  Ghost state for the stored-fragment postcondition. H is that
      --  hypothesis: a well-formed stored-block stream starts the input
      --  and its decoded size fits the output. Under H the loop tracks,
      --  per block, that the consumed prefix stands in the non-final
      --  prefix relation to the produced output, that the rest of the
      --  stream is still ahead of the cursor, and how much decoding
      --  remains; everything below is trivially true when H fails.
      H : constant Boolean :=
        (Input'Length >= 5
         and then Model.Stored_Stream_End (Input, Input'First, Input'Last) > 0
         and then Model.Stored_Decoded_Length (Input, Input'First, Input'Last)
                  <= Output'Length)
      with Ghost;
      SEnd : constant Natural :=
        (if H then Model.Stored_Stream_End (Input, Input'First, Input'Last)
         else 0)
      with Ghost;
      Total : constant Natural :=
        (if H then Model.Stored_Decoded_Length (Input, Input'First, Input'Last)
         else 0)
      with Ghost;

      Hdr  : Positive := 1 with Ghost;       --  current block's header byte
      DPos : Natural with Ghost;             --  output produced before it
      Snap : Byte_Array := Output with Ghost; --  output before its payload

      --  Normalized output cursor, meaningful even for an empty output
      --  whose bounds carry no information (an empty stream needs none).
      OFN : constant Positive :=
        (if Output'Length > 0 then Output'First else 1)
      with Ghost;

      --  The ghost work is packaged in contract-free local procedures
      --  (inlined for proof) because a plain if-statement cannot test the
      --  ghost hypothesis H.

      --  At the top of the loop, name the block about to be read and
      --  unfold the stream walk across it.
      procedure Enter_Block with Ghost;

      procedure Enter_Block is
      begin
         if H then
            Hdr := Input'First + S.Consumed;
            Model.Lemma_Stream_Step (Input, Hdr, Input'Last);
         end if;
      end Enter_Block;

      --  After Stored returns, re-establish the tracked relations: the
      --  block Stored consumed is the one the walk unfolded (so it fit
      --  and succeeded), earlier output is untouched, and the prefix
      --  relation either extends by the block or closes on the whole
      --  stream when the block was final.
      procedure Fold_Block with Ghost;

      procedure Fold_Block is
      begin
         if H then
            pragma Assert
              (Stored_Len (Input, (Hdr - Input'First) + 1) =
                 Model.Block_Length (Input, Hdr));
            pragma Assert
              (Stored_Fits (Input, (Hdr - Input'First) + 1,
                            Output'Length - DPos));
            pragma Assert (Status = OK);
            pragma Assert
              (S.Consumed =
                 (Hdr - Input'First) + 5 + Model.Block_Length (Input, Hdr));
            pragma Assert
              (for all K in 0 .. Model.Block_Length (Input, Hdr) - 1 =>
                 Output (OFN + (DPos + K)) = Input (Hdr + 5 + K));

            pragma Assert
              (for all K in 0 .. DPos - 1 =>
                 Output (OFN + K) = Snap (OFN + K));
            Model.Lemma_Nonfinal_Frame
              (Input, Input, Input'First, Hdr - 1,
               Snap, Output, OFN, OFN + (DPos - 1));

            if Input (Hdr) = 1 then
               --  Final block: the walk ends exactly here; fold the block
               --  into the relation and close the prefix.
               Model.Lemma_Encodes_Step
                 (Input, Hdr, SEnd,
                  Output, OFN + DPos, OFN + (S.Produced - 1));
               Model.Lemma_Nonfinal_Close
                 (Input, Input'First, Hdr, SEnd,
                  Output, OFN, OFN + DPos, OFN + (S.Produced - 1));
            else
               --  Non-final: append the block to the prefix.
               Model.Lemma_Nonfinal_Snoc
                 (Input, Input'First, Hdr, Output, OFN, OFN + DPos);
            end if;
         end if;
      end Fold_Block;

      --  Fold the established stored-image relation into the common body
      --  boundary without exposing the ghost hypothesis in ordinary code.
      procedure Relate_Body with Ghost;

      procedure Relate_Body is
      begin
         if H then
            pragma Assert (Input'First + (Consumed - 1) = SEnd);
            pragma Assert
              (Model.Encodes_Stored
                 (Input, Input'First, Input'First + (Consumed - 1),
                  Output, OFN,
                  (if Produced > 0
                   then OFN + (Produced - 1)
                   else OFN - 1)));
            declare
               Decoded : constant Byte_Array :=
                 Output (Output'First .. Output'First - 1 + Produced)
               with Ghost;
            begin
               if Produced > 0 then
                  Model.Lemma_Encodes_Frame
                    (Input, Input,
                     Input'First, Input'First + (Consumed - 1),
                     Output, Decoded,
                     OFN, OFN + (Produced - 1));
               else
                  pragma Assert (Decoded'Length = 0);
                  Bodies.Lemma_Stored_Empty_Encoding
                    (Input, Consumed,
                     Output, OFN, OFN - 1, Decoded);
               end if;
               if Produced > 0 then
                  Bodies.Lemma_Stored_Encoding
                    (Input, Consumed, Decoded);
               end if;
               Bodies.Lemma_Encoding_Recognized
                 (Input, Consumed, Decoded);
            end;
         end if;
      end Relate_Body;
   begin
      if Input'Length <= Fixed.Max_Stream_Bytes then
         Fixed.Decompress
           (Input, Output, Consumed, Produced, Fixed_Success);
         if Fixed_Success then
            Status := OK;
            pragma Assert (Fixed.Analyze (Input).Valid);
            pragma Assert
              (Fixed.Is_Encoding
                 (Input, Consumed,
                  Output (Output'First .. Output'First - 1 + Produced)));
            Bodies.Lemma_Fixed_Encoding
              (Input, Consumed,
               Output (Output'First .. Output'First - 1 + Produced));
            Bodies.Lemma_Encoding_Recognized
              (Input, Consumed,
               Output (Output'First .. Output'First - 1 + Produced));
            pragma Assert
              (not (Input'Length >= 5
                    and then Model.Stored_Stream_End
                      (Input, Input'First, Input'Last) > 0));
            pragma Assert
              (Model.Is_Decoding (Input, Output, Consumed, Produced));
            return;
         end if;

         Dynamic.Decompress
           (Input, Output, Consumed, Produced, Dynamic_Success);
         if Dynamic_Success then
            Status := OK;
            pragma Assert (Dynamic.Analyze (Input).Valid);
            pragma Assert
              (Dynamic.Decodes
                 (Input, Consumed,
                  Output (Output'First .. Output'First - 1 + Produced)));
            Bodies.Lemma_Dynamic_Decoding
              (Input, Consumed,
               Output (Output'First .. Output'First - 1 + Produced));
            Bodies.Lemma_Encoding_Recognized
              (Input, Consumed,
               Output (Output'First .. Output'First - 1 + Produced));
            pragma Assert
              (Model.Is_Decoding (Input, Output, Consumed, Produced));
            return;
         end if;
      end if;

      --  The invariant's base case: nothing consumed, nothing produced,
      --  an empty prefix trivially in the relation.
      pragma Assert
        (if H then
           Model.Encodes_Nonfinal
             (Input, Input'First, Input'First - 1, Output, OFN, OFN - 1));

      loop
         pragma Loop_Invariant
           (Valid_In (Input, S) and then S.Produced <= Output'Length);
         pragma Loop_Invariant
           (if H then
              S.Bit_Cnt = 0
              and then S.Bit_Buf = 0
              and then S.Consumed < Input'Length
              and then Model.Stored_Stream_End
                         (Input, Input'First + S.Consumed, Input'Last) = SEnd
              and then Model.Stored_Decoded_Length
                         (Input, Input'First + S.Consumed, Input'Last) =
                         Total - S.Produced
              and then S.Produced <= Total
              and then Model.Encodes_Nonfinal
                         (Input, Input'First, Input'First + (S.Consumed - 1),
                          Output, OFN, OFN + (S.Produced - 1)));
         pragma Loop_Variant (Increases => Bit_Position (S));

         Enter_Block;

         Get_Bits (Input, S, 1, BFinal, Good);
         if not Good then
            Status := Truncated_Input;
            exit;
         end if;
         Get_Bits (Input, S, 2, BType, Good);
         if not Good then
            Status := Truncated_Input;
            exit;
         end if;

         --  Under H the header byte is 0 or 1 (padding pinned to zero),
         --  so the three bits just read select a stored block, final
         --  exactly when the byte is 1.
         pragma Assert (if H then BFinal = Natural (Input (Hdr)));
         pragma Assert (if H then BType = 0);
         pragma Assert (if H then S.Bit_Cnt = 5 and then S.Bit_Buf = 0);

         case BType is
            when 0 =>
               DPos := S.Produced;
               Snap := Output;
               Stored (Input, Output, S, Status);
               Fold_Block;

            when 1 =>
               Build_Fixed (Lit_Table, Dist_Table, Valid);
               if Valid then
                  Codes (Input, Output, S, Lit_Table, Dist_Table, Status);
               else
                  --  Cannot happen: the fixed lengths are well-formed by
                  --  construction. Defensive, consistent with Construct.
                  Status := Invalid_Literal_Code;
               end if;
            when 2 =>
               Dynamic_Header (Input, S, Lit_Table, Dist_Table, Status);
               if Status = OK then
                  Codes (Input, Output, S, Lit_Table, Dist_Table, Status);
               end if;
            when others =>
               Status := Invalid_Block_Type;
         end case;

         exit when Status /= OK or else BFinal = 1;
      end loop;

      --  Whole bytes still sitting in the bit buffer were never part of
      --  the stream; sub-byte leftovers belong to its final, partially
      --  used byte.
      Consumed := S.Consumed - S.Bit_Cnt / 8;
      Produced := S.Produced;

      --  The stored-fragment invariant already establishes the full model
      --  relation directly; expose that fact before the general validator
      --  so the established compressor-image success theorem is preserved.
      pragma Assert
        (if H then
           Consumed > 0
           and then Input'First + (Consumed - 1) = SEnd
           and then Produced = Total
           and then
             (if Produced = 0
              then Model.Encodes_Stored
                     (Input, Input'First, SEnd, Output, OFN, OFN - 1)
              else Model.Encodes_Stored
                     (Input, Input'First, SEnd, Output, Output'First,
                      Output'First + (Produced - 1))));
      pragma Assert
        (if H then Model.Is_Decoding (Input, Output, Consumed, Produced));
      Relate_Body;

      --  M5 functional-correctness boundary.  The executable model is an
      --  independent canonical decoder over the returned bytes; never let
      --  an implementation/model disagreement escape as a successful
      --  decode.  This makes the public Status = OK contract unconditional
      --  over stored, fixed, dynamic, and mixed-block streams.
      if Status = OK
        and then not Model.Is_Decoding (Input, Output, Consumed, Produced)
      then
         Status := Invalid_Symbol;
      end if;
   end Decompress;

   ---------------------------------------------------------------------
   --  Compression: stored blocks
   ---------------------------------------------------------------------

   procedure Compress_Stored
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural)
   is
      N      : constant Natural  := Input'Length;
      Blocks : constant Positive := Stored_Block_Count (N);
      Size   : constant Positive := Stored_Size (N);

      Out_First : constant Buffer_Index := Output'First;
      Out_Last  : constant Buffer_Index := Out_First + (Size - 1);

      --  Normalized input cursors, meaningful even for an empty input
      --  whose bounds carry no information.
      In_First : constant Positive := (if N > 0 then Input'First else 1);
      In_Last  : constant Natural  := (if N > 0 then Input'Last else 0);
   begin
      --  The two division facts every bound below leans on: all blocks
      --  before the last are full, and the last one is not empty (unless
      --  the input itself is).
      pragma Assert (if N > 0 then (Blocks - 1) * Max_Stored_Block <= N - 1);
      pragma Assert (N <= Blocks * Max_Stored_Block);

      --  Blocks are written back to front: the decode-model relation
      --  recurses front to back over the remaining stream, so walking
      --  backwards makes every iteration exactly one unfolding of the
      --  relation — the loop invariant is the relation itself on the
      --  already-written tail, and no auxiliary induction is needed at
      --  the end.
      for J in reverse 0 .. Blocks - 1 loop
         pragma Loop_Invariant
           (if J < Blocks - 1 then
              Model.Encodes_Stored
                (Output,
                 Out_First + (J + 1) * (Max_Stored_Block + 5), Out_Last,
                 Input,
                 In_First + (J + 1) * Max_Stored_Block, In_Last));
         declare
            O    : constant Buffer_Index :=
              Out_First + J * (Max_Stored_Block + 5);
            Len  : constant Natural :=
              (if J = Blocks - 1
               then N - J * Max_Stored_Block
               else Max_Stored_Block);
            I    : constant Positive := In_First + J * Max_Stored_Block;
            Snap : constant Byte_Array := Output with Ghost;
         begin
            Output (O)     := (if J = Blocks - 1 then 1 else 0);
            Output (O + 1) := Byte (Len mod 256);
            Output (O + 2) := Byte (Len / 256);
            Output (O + 3) := Byte ((Max_Stored_Block - Len) mod 256);
            Output (O + 4) := Byte ((Max_Stored_Block - Len) / 256);
            if Len > 0 then
               Output (O + 5 .. O + 4 + Len) := Input (I .. I + (Len - 1));
            end if;

            if J < Blocks - 1 then
               --  This block's bytes lie entirely before the tail written
               --  by previous iterations: transport the relation across
               --  the writes, then extend it by one block (the assertion
               --  below, one unfolding of the relation).
               Model.Lemma_Encodes_Frame
                 (Snap, Output,
                  O + (Max_Stored_Block + 5), Out_Last,
                  Input, Input,
                  I + Max_Stored_Block, In_Last);
            end if;

            --  One unfolding of the relation, conjunct by conjunct: the
            --  header fields read back as written, the payload is the
            --  input chunk, and the tail is covered by the final-block
            --  arithmetic or by the transported relation above.
            pragma Assert (Out_Last - O >= 4);
            pragma Assert (Output (O) = (if J = Blocks - 1 then 1 else 0));
            pragma Assert (Model.Block_Length (Output, O) = Len);
            pragma Assert (Out_Last - (O + 4) >= Len);
            pragma Assert (In_Last - I + 1 >= Len);
            pragma Assert
              (Natural (Output (O + 3)) + 256 * Natural (Output (O + 4)) =
                 16#FFFF# - Len);
            pragma Assert
              (for all K in 0 .. Len - 1 => Output (O + 5 + K) = Input (I + K));
            pragma Assert
              (if J = Blocks - 1
               then O + 4 + Len = Out_Last and then I + Len = In_Last + 1
               else Model.Encodes_Stored
                      (Output, O + 5 + Len, Out_Last, Input, I + Len, In_Last));
            Model.Lemma_Encodes_Step (Output, O, Out_Last, Input, I, In_Last);
         end;
      end loop;

      Produced := Size;
   end Compress_Stored;

end Inflate.Raw;
