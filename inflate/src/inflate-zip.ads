--  Inflate.ZIP — walking and extracting ZIP archives (the PKWARE APPNOTE
--  format): end-of-central-directory lookup, central-directory iteration,
--  per-entry extraction with CRC and size verification.
--
--  This is the container the firmware-update slot actually receives
--  (update bundles, OTA packages, .jar/.apk-shaped payloads): semi-hostile
--  bytes parsed before any signature check has succeeded. Every offset and
--  length here comes from the attacker; all of them are bounds-checked
--  against the archive, and every inconsistency is a Status_Type, never an
--  exception.
--
--  Scope: the classic 32-bit format, methods stored (0) and deflate (8) —
--  which is what `zip`, Python's zipfile and Java's jar emit by default.
--  ZIP64, encryption, multi-disk archives and other compression methods
--  are detected and reported as ZIP_Unsupported. Sizes in the central
--  directory are authoritative (entries written with data descriptors
--  decode fine); the local header is validated for structure.

package Inflate.ZIP with SPARK_Mode => On is

   --  One central-directory entry. Name_First .. Name_Last slice the
   --  entry's name out of the archive buffer (a null range for an empty
   --  name); names ending in '/' are directories by convention.
   type Entry_Info is record
      Name_First   : Positive;
      Name_Last    : Natural;
      Method       : Natural;   --  0 = stored, 8 = deflate, others rejected
      Flags        : Natural;   --  general-purpose bits (bit 0: encrypted)
      CRC          : Word32;
      Comp_Size    : Word32;
      Uncomp_Size  : Word32;
      Local_Offset : Word32;    --  of the entry's local header
   end record;

   --  Central-directory iteration state
   type Cursor is record
      Offset    : Natural;      --  next entry, as an offset from Archive'First
      Remaining : Natural;      --  entries still to read
   end record;

   function Has_Next (C : Cursor) return Boolean is (C.Remaining > 0);

   --  Locate the end-of-central-directory record (scanning back over a
   --  possible archive comment) and position a cursor on the first entry.
   --  Count is the total number of entries.
   procedure Open
     (Archive : in     Byte_Array;
      C       :    out Cursor;
      Count   :    out Natural;
      Status  :    out Status_Type)
   with
     Global => null,
     Post   => (if Status = OK then C.Offset <= Archive'Length);

   --  Read the entry under the cursor and advance. The name slice is
   --  guaranteed to lie within the archive.
   procedure Next
     (Archive : in     Byte_Array;
      C       : in out Cursor;
      E       :    out Entry_Info;
      Status  :    out Status_Type)
   with
     Global => null,
     Pre    => Has_Next (C) and then C.Offset <= Archive'Length,
     Post   =>
       (if Status = OK
        then C.Offset <= Archive'Length
             and then E.Name_First >= Archive'First
             and then E.Name_Last <= Archive'Last
             and then E.Name_Last >= E.Name_First - 1);

   --  Decompress one entry into Output and verify its CRC-32 and size.
   --  E need not be trusted: every field is re-validated against the
   --  archive. Status = OK means the entry decoded completely and matched
   --  its declared CRC and sizes.
   procedure Extract
     (Archive  : in     Byte_Array;
      E        : in     Entry_Info;
      Output   : in out Byte_Array;
      Produced :    out Natural;
      Status   :    out Status_Type)
   with
     Global => null,
     Post   => Produced <= Output'Length;

end Inflate.ZIP;
