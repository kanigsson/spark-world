with Ada.Unchecked_Deallocation;

package body Tui.Text
  with SPARK_Mode => On
is

   ---------------
   -- To_Buffer --
   ---------------

   function To_Buffer (Item : String) return Buffer is
      Result : Buffer (1 .. Item'Length) := (others => 0);
   begin
      for I in Item'Range loop
         Result (1 + (I - Item'First)) := Byte (Character'Pos (Item (I)));

         pragma
           Loop_Invariant
             (for all J in 1 .. 1 + (I - Item'First) =>
                Result (J)
                = Byte (Character'Pos (Item (Item'First + (J - 1)))));
      end loop;
      return Result;
   end To_Buffer;

   ---------------
   -- To_String --
   ---------------

   function To_String (Item : Buffer) return String is
      Result : String (1 .. Item'Length) := (others => ' ');
   begin
      for I in Item'Range loop
         Result (1 + (I - Item'First)) := Character'Val (Integer (Item (I)));

         pragma
           Loop_Invariant
             (for all J in 1 .. 1 + (I - Item'First) =>
                Result (J)
                = Character'Val (Integer (Item (Item'First + (J - 1)))));
      end loop;
      return Result;
   end To_String;

   ----------
   -- Line --
   ----------

   function Line (Idx : Index; Buf : Buffer; N : Line_Number) return Buffer is
      S : constant Span := Idx.Spans (N);
   begin
      --  Start + Length <= Scanned + 1 <= Buf'Last + 1 (predicate + precond),
      --  so the high bound is at most Buf'Last; an empty line yields a null
      --  slice (Start .. Start - 1).
      return Buf (S.Start .. S.Start + S.Length - 1);
   end Line;

   --  A line record is appended in an order that keeps the index predicate true
   --  after every single statement: write the new span at the as-yet-unindexed
   --  slot Count+1, then advance Scanned, then bump Count to admit it. (A
   --  whole-record assignment would copy the entire Spans array per line.)
   procedure Append
     (Idx    : in out Index;
      Start  : Byte_Index;
      Length : Byte_Count;
      Upto   : Byte_Count)
   with
     Pre  =>
       Idx.Count < Idx.Capacity
       and then Start + Length <= Upto + 1
       and then Upto >= Idx.Scanned,
     Post => Idx.Count = Idx.Count'Old + 1 and then Idx.Scanned = Upto;
   procedure Append
     (Idx    : in out Index;
      Start  : Byte_Index;
      Length : Byte_Count;
      Upto   : Byte_Count) is
   begin
      Idx.Spans (Idx.Count + 1) := (Start => Start, Length => Length);
      Idx.Scanned := Upto;
      Idx.Count := Idx.Count + 1;
   end Append;

   ----------
   -- Scan --
   ----------

   procedure Scan (Idx : in out Index; Buf : Buffer) is
      Line_Start : Start_Range;
   begin
      if Idx.Scanned >= Buf'Last then
         return;                          --  nothing new to scan

      end if;

      Line_Start :=
        Idx.Scanned + 1;      --  invariant: = Idx.Scanned + 1 throughout

      for P in Byte_Index range Idx.Scanned + 1 .. Buf'Last loop

         if Buf (P) = LF then
            if Idx.Count = Idx.Capacity then
               Idx.Truncated := True;
               return;                     --  out of room; keep cursor put

            end if;

            declare
               CE : Byte_Count := P - 1;   --  last content byte (before LF)
            begin
               if CE >= Line_Start and then Buf (CE) = CR then
                  CE := CE - 1;            --  strip a CRLF's CR

               end if;
               --  CE + 1 >= Line_Start here, so the length is non-negative.
               Append
                 (Idx,
                  Start  => Line_Start,
                  Length => (CE + 1) - Line_Start,
                  Upto   => P);
            end;

            Line_Start := P + 1;           --  next line begins after the LF

         end if;

         pragma Loop_Invariant (Idx.Count <= Idx.Capacity);
         pragma Loop_Invariant (Idx.Scanned <= P);
         pragma Loop_Invariant (Line_Start = Idx.Scanned + 1);
         pragma
           Loop_Invariant
             (for all I in 1 .. Idx.Count =>
                Idx.Spans (I).Start + Idx.Spans (I).Length <= Idx.Scanned + 1);
      end loop;
   end Scan;

   ----------
   -- Seal --
   ----------

   procedure Seal (Idx : in out Index; Buf : Buffer) is
   begin
      if Idx.Scanned >= Buf'Last then
         return;                          --  no pending tail

      end if;
      if Idx.Count = Idx.Capacity then
         Idx.Truncated := True;
         return;
      end if;

      --  Pending tail is Buf (Scanned + 1 .. Buf'Last), recorded verbatim.
      Append
        (Idx,
         Start  => Idx.Scanned + 1,
         Length => (Buf'Last + 1) - (Idx.Scanned + 1),
         Upto   => Buf'Last);
   end Seal;

   ------------------
   -- New_Document --
   ------------------

   --  Build the line index over a freshly-filled Document. Bytes'First = 1 and
   --  Scanned_Bytes (Idx) <= Size = Bytes'Last hold from the predicate, so
   --  Scan's/Seal's preconditions are met; their postconditions re-establish
   --  the predicate on the way out.
   procedure Index_All (D : in out Document) with Global => null is
   begin
      Scan (D.Idx, D.Bytes);
      Seal (D.Idx, D.Bytes);
   end Index_All;

   procedure Dealloc is new Ada.Unchecked_Deallocation (Document, Doc_Ref);

   function New_Document (Content : Buffer) return Doc_Ref is
      Lines : Byte_Count :=
        0;   --  newline count; <= bytes seen, so <= Max_Bytes
   begin
      --  Size the index from the line count (newlines + 1), capped.
      for I in Content'Range loop
         if Content (I) = LF then
            Lines := Lines + 1;
         end if;
         pragma Loop_Invariant (Lines <= I - Content'First + 1);
      end loop;
      Lines := Natural'Min (Lines + 1, Max_Lines);

      --  Allocate fully initialised (SPARK forbids an uninitialised allocator):
      --  the buffer is filled from Content directly -- the one content copy, no
      --  prior zeroing -- and the index starts empty, then Index_All scans it.
      return
         R : constant Doc_Ref :=
           new Document'
             (Size     => Content'Length,
              Capacity => Line_Total (Lines),
              Bytes    => Content,
              Idx      =>
                (Capacity  => Line_Total (Lines),
                 Spans     => (others => (Start => 1, Length => 0)),
                 Count     => 0,
                 Scanned   => 0,
                 Truncated => False))
      do
         Index_All (R.all);
      end return;
   end New_Document;

   ----------
   -- Free --
   ----------

   procedure Free (R : in out Doc_Ref) is
   begin
      Dealloc (R);
   end Free;

end Tui.Text;
