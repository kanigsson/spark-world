--  Inflate.ZIP — walking and extracting ZIP archives (the PKWARE APPNOTE
--  format): end-of-central-directory lookup, central-directory iteration,
--  per-entry extraction with CRC and size verification.
--
--  Every offset and length here comes from the archive, so each one is
--  bounds-checked before use. Inconsistent input is reported through
--  Status_Type instead of being handled by raising an exception.
--
--  Scope: the classic 32-bit format, methods stored (0) and deflate (8) —
--  which is what `zip`, Python's zipfile and Java's jar emit by default.
--  ZIP64, encryption, multi-disk archives and other compression methods
--  are detected and reported as ZIP_Unsupported. Sizes in the central
--  directory are authoritative (entries written with data descriptors
--  decode fine); the local header is validated for structure.

package Inflate.ZIP
  with SPARK_Mode => On
is

   --  One central-directory entry. Name_First .. Name_Last slice the
   --  entry's name out of the archive buffer (a null range for an empty
   --  name); names ending in '/' are directories by convention.
   type Entry_Info is private;

   function Name_First (E : Entry_Info) return Positive;
   function Name_Last (E : Entry_Info) return Natural;
   function Method (E : Entry_Info) return Natural;
   function Flags (E : Entry_Info) return Natural;
   function CRC (E : Entry_Info) return Word32;
   function Compressed_Size (E : Entry_Info) return Word32;
   function Uncompressed_Size (E : Entry_Info) return Word32;

   --  Central-directory iteration state
   type Cursor is private;

   function Has_Next (C : Cursor) return Boolean;

   --  Locate the end-of-central-directory record (scanning back over a
   --  possible archive comment) and position a cursor on the first entry.
   --  Count is the total number of entries.
   procedure Open
     (Archive : in Byte_Array;
      C       : out Cursor;
      Count   : out Natural;
      Status  : out Status_Type)
   with Global => null;

   --  Read the entry under the cursor and advance. The name slice is
   --  guaranteed to lie within the archive.
   procedure Next
     (Archive : in Byte_Array;
      C       : in out Cursor;
      E       : out Entry_Info;
      Status  : out Status_Type)
   with
     Global => null,
     Pre    => Has_Next (C),
     Post   =>
       (if Status = OK
        then
          Name_First (E) >= Archive'First
          and then Name_Last (E) <= Archive'Last
          and then Name_Last (E) >= Name_First (E) - 1);

   --  Decompress one entry into Output and verify its CRC-32 and size.
   --  E is an opaque descriptor returned by Next. Its central-directory
   --  record and corresponding local header are re-validated against this
   --  archive. Status = OK means the entry decoded completely and matched
   --  its declared CRC and sizes.
   procedure Extract
     (Archive  : in Byte_Array;
      E        : in Entry_Info;
      Output   : in out Byte_Array;
      Produced : out Natural;
      Status   : out Status_Type)
   with Global => null, Post => Produced <= Output'Length;

private

   type Entry_Info is record
      Name_First_Value  : Positive := 1;
      Name_Last_Value   : Natural := 0;
      Method_Value      : Natural := 0;
      Flags_Value       : Natural := 0;
      CRC_Value         : Word32 := 0;
      Comp_Size_Value   : Word32 := 0;
      Uncomp_Size_Value : Word32 := 0;
      Local_Offset      : Word32 := 0;
      Central_Offset    : Natural := 0;
      Central_First     : Natural := 0;
      Central_Limit     : Natural := 0;
      End_Record_Offset : Natural := 0;
   end record;

   type Cursor is record
      Offset            : Natural := 0;
      Limit             : Natural := 0;
      First             : Natural := 0;
      End_Record_Offset : Natural := 0;
      Remaining         : Natural := 0;
   end record;

   function Name_First (E : Entry_Info) return Positive
   is (E.Name_First_Value);

   function Name_Last (E : Entry_Info) return Natural
   is (E.Name_Last_Value);

   function Method (E : Entry_Info) return Natural
   is (E.Method_Value);

   function Flags (E : Entry_Info) return Natural
   is (E.Flags_Value);

   function CRC (E : Entry_Info) return Word32
   is (E.CRC_Value);

   function Compressed_Size (E : Entry_Info) return Word32
   is (E.Comp_Size_Value);

   function Uncompressed_Size (E : Entry_Info) return Word32
   is (E.Uncomp_Size_Value);

   function Has_Next (C : Cursor) return Boolean
   is (C.Remaining > 0);

end Inflate.ZIP;
