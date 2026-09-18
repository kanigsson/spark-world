--  Tui.Text — a line index over an immutable byte buffer.
--
--  Given a buffer of bytes (a file slurped into memory, or content accumulated
--  from a pipe), this builds an index of line boundaries so a pager can ask for
--  "line N" in O(1) without rescanning. It stores OFFSETS, not copies: the
--  caller owns the buffer; the index just records where each line begins and
--  how long it is.
--
--  Scanning is incremental and append-aware. Feed the buffer to Scan; it
--  records every complete line (terminated by LF, with a preceding CR stripped)
--  and remembers how far it got. When more bytes are appended (a growing pipe),
--  call Scan again with the longer buffer and it resumes from where it left off.
--  A trailing partial line (bytes after the last LF, e.g. a file with no final
--  newline) is NOT recorded by Scan; call Seal at end-of-input to finalise it.
--
--  Line scanning is UTF-8-agnostic on purpose: the newline bytes (LF, CR) can
--  never occur inside a multibyte UTF-8 sequence, so splitting on them is
--  byte-safe regardless of encoding. Column width and tab handling are a
--  display concern owned by the width crate and the pager's layout, not here.
--
--  Everything is SPARK, proved free of run-time errors (see README). The index
--  carries an invariant that every recorded span lies within the scanned
--  prefix, which is what makes slicing a line out of the buffer provably safe.
--
--  Usage contract (not machine-checked): between successive Scan calls the
--  buffer must be append-only — the first Scanned_Bytes bytes must be
--  unchanged. Violating it does not break safety, only correctness.

package Tui.Text
  with SPARK_Mode => On
is

   subtype Byte is Tui.Byte;

   --  Generous caps that keep all offset/area arithmetic inside 32-bit Integer.
   Max_Bytes : constant := 2**30 - 1;   --  ~1 GiB of buffered content
   Max_Lines : constant := 2**24 - 1;   --  ~16 M lines

   subtype Byte_Count is
     Natural range 0 .. Max_Bytes;       --  a length / cursor
   subtype Byte_Index is
     Natural range 1 .. Max_Bytes;       --  a 1-based position
   subtype Line_Total is Natural range 0 .. Max_Lines;       --  a line count
   subtype Line_Number is
     Natural range 1 .. Max_Lines;      --  a 1-based line id

   type Buffer is array (Byte_Index range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Conversions
   ---------------------------------------------------------------------------

   --  Every input this library takes is a Buffer, so it says how to build one.
   --  The mapping is byte for byte: no encoding is applied or assumed, which
   --  is what a caller holding bytes in a String wants and what the UTF-8
   --  layer above expects to receive.

   function To_Buffer (Item : String) return Buffer
   with
     Pre  => Item'Length <= Max_Bytes,
     Post =>
       To_Buffer'Result'Length = Item'Length
       and then (for all I in 1 .. Item'Length =>
                   To_Buffer'Result (I)
                   = Byte (Character'Pos (Item (Item'First + (I - 1)))));

   function To_String (Item : Buffer) return String
   with
     Post =>
       To_String'Result'Length = Item'Length
       and then To_String'Result'First = 1
       and then (for all I in 1 .. Item'Length =>
                   To_String'Result (I)
                   = Character'Val (Integer (Item (Item'First + (I - 1)))));

   --  Where one line's content lives in the buffer, excluding its terminator.
   --  An empty line has Length = 0 (Start still points at a valid position).
   type Span is record
      Start  : Byte_Index;
      Length : Byte_Count;
   end record;

   --  The index. Capacity bounds how many lines it can hold; pick it to suit
   --  the expected input. Default-initialised to empty: `Idx : Index (10_000);`.
   type Index (Capacity : Line_Total) is private;

   ---------------------------------------------------------------------------
   --  Queries
   ---------------------------------------------------------------------------

   --  Number of complete (and sealed) lines recorded so far.
   function Line_Count (Idx : Index) return Line_Total;

   --  Number of bytes consumed into recorded lines; the un-recorded tail is
   --  Buffer (Scanned_Bytes + 1 .. Buffer'Last).
   function Scanned_Bytes (Idx : Index) return Byte_Count;

   --  True if input was dropped because Capacity was reached.
   function Truncated (Idx : Index) return Boolean;

   --  Byte range of line N (1-based), excluding its terminator. O(1).
   --  The result is guaranteed to lie within the scanned prefix, so a client
   --  can slice it out of a buffer that covers Scanned_Bytes without a bounds
   --  check of its own.
   function Line_Span (Idx : Index; N : Line_Number) return Span
   with
     Pre  => N <= Line_Count (Idx),
     Post =>
       Line_Span'Result.Start + Line_Span'Result.Length
       <= Scanned_Bytes (Idx) + 1;

   --  The bytes of line N, sliced out of the buffer the index was built over.
   function Line (Idx : Index; Buf : Buffer; N : Line_Number) return Buffer
   with
     Pre  =>
       N <= Line_Count (Idx)
       and then Buf'First = 1
       and then Buf'Last >= Scanned_Bytes (Idx),
     Post => Line'Result'Length = Line_Span (Idx, N).Length;

   ---------------------------------------------------------------------------
   --  Building the index
   ---------------------------------------------------------------------------

   --  Record every complete line (LF-terminated) found from the current scan
   --  cursor to the end of Buf, advancing the cursor. Idempotent on a buffer
   --  that has not grown. Stops and sets Truncated if Capacity is reached.
   procedure Scan (Idx : in out Index; Buf : Buffer)
   with
     Global => null,
     Pre    => Buf'First = 1 and then Buf'Last >= Scanned_Bytes (Idx),
     Post   => Scanned_Bytes (Idx) <= Buf'Last;

   --  Finalise a trailing partial line (bytes after the last LF) as the last
   --  line. Use at end-of-input. No-op if there is no pending tail.
   procedure Seal (Idx : in out Index; Buf : Buffer)
   with
     Global => null,
     Pre    => Buf'First = 1 and then Buf'Last >= Scanned_Bytes (Idx),
     Post   => Scanned_Bytes (Idx) <= Buf'Last;

   ---------------------------------------------------------------------------
   --  Document — a buffer bundled with the index built over it
   ---------------------------------------------------------------------------

   --  A byte buffer and its line index kept together, with the invariant that
   --  the index never scans past the buffer (Scanned_Bytes (Idx) <= Size, and
   --  Bytes'First = 1 by construction). That is exactly the engine's content
   --  contract (Content'First = 1 and Content'Last >= Scanned_Bytes (Index)),
   --  so a host that hands the engine a Document's Bytes and Idx discharges
   --  that precondition from the predicate -- no per-call recheck, no trust.
   --
   --  It lives here, in Index's own unit, deliberately: not just nesting an
   --  Index but also allocating or declaring an access to a predicated
   --  discriminated type trips a GNATprove front-end crash when done from
   --  another unit (reproduced and reported separately). So the type, its
   --  owning reference, and the allocate/free primitives all stay here; a host
   --  only holds the reference and reads the fields, which is crash-free. The
   --  natural home anyway -- "a buffer plus the index built over it".
   type Document
     (Size     : Byte_Count;
      Capacity : Line_Total)
   is record
      Bytes : Buffer (1 .. Size);
      Idx   : Index (Capacity);
   end record
   with Dynamic_Predicate => Scanned_Bytes (Document.Idx) <= Document.Size;

   --  An owning reference to a heap Document (the size is a run-time value).
   type Doc_Ref is access Document;

   --  Allocate a Document over Content -- copied in once -- and build its line
   --  index, so the buffer-fits invariant holds on the result. Never null.
   function New_Document (Content : Buffer) return Doc_Ref
   with
     Global => null,
     Pre    => Content'First = 1,
     Post   => New_Document'Result /= null;

   --  Reclaim a Document. No-op on null; leaves R null.
   procedure Free (R : in out Doc_Ref)
   with Global => null, Post => R = null;

private

   LF : constant Byte := 16#0A#;
   CR : constant Byte := 16#0D#;

   --  Line starts may transiently sit one past the last byte (the empty tail
   --  after a final LF), so they need a slightly wider range than Byte_Index.
   subtype Start_Range is Natural range 1 .. Max_Bytes + 1;

   type Span_Array is array (Line_Number range <>) of Span;

   type Index (Capacity : Line_Total) is record
      Spans     : Span_Array (1 .. Capacity);
      Count     : Line_Total := 0;
      Scanned   : Byte_Count := 0;
      Truncated : Boolean := False;
   end record
   with
     Dynamic_Predicate =>
       Index.Count <= Index.Capacity
       and then (for all I in 1 .. Index.Count =>
                   Index.Spans (I).Start + Index.Spans (I).Length
                   <= Index.Scanned + 1);

   function Line_Count (Idx : Index) return Line_Total
   is (Idx.Count);
   function Scanned_Bytes (Idx : Index) return Byte_Count
   is (Idx.Scanned);
   function Truncated (Idx : Index) return Boolean
   is (Idx.Truncated);
   function Line_Span (Idx : Index; N : Line_Number) return Span
   is (Idx.Spans (N));

end Tui.Text;
