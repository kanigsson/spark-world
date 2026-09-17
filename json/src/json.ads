--  JSON - shared types for the RFC 8259 parser.
--
--  This is the root of the crate: the status enumeration all layers report
--  through and the one deliberate capacity limit. The functionality lives
--  in the children:
--
--    JSON.Pull    — the pull-cursor parser: one event per call, slices
--                   into the caller's buffer, no materialization
--    JSON.Strings — decoding of string payloads (escapes, \uXXXX,
--                   surrogate pairs) into a caller buffer
--    JSON.Numbers — conversion of number tokens to Integer_64/Long_Float
--
--  DESIGN: everything works over a caller-provided String holding the
--  UTF-8 encoded document. No heap, no access types, no recursion, no OS,
--  and no package state. Malformed input is reported through Status_Type
--  instead of being handled by raising an exception.
--
--  The single hard limit is nesting depth (Max_Depth): the parser keeps an
--  explicit stack of container kinds, so depth is a fixed-size array, and
--  pathological nesting is rejected instead of exhausting the call stack —
--  the limit RFC 8259 section 9 explicitly permits. Everything else
--  (document size, string lengths, member counts) is bounded only by the
--  input buffer.

package JSON with Pure, SPARK_Mode => On is

   --  Containers may nest this deep; the document at depth Max_Depth + 1
   --  is rejected with Nesting_Too_Deep. Real-world JSON lives below
   --  depth 20; production parsers cap between 128 and 1000.
   Max_Depth : constant := 1024;

   --  Every way a parse step can end. OK means the event (or decode) is
   --  valid; everything else identifies the first violation encountered.
   type Status_Type is
     (OK,

      --  Document structure
      Truncated,             --  input ended inside a value or container
      Nesting_Too_Deep,      --  more than Max_Depth open containers
      Expected_Value,        --  byte cannot start a value
      Expected_Key,          --  object member must start with '"'
      Expected_Colon,        --  missing ':' after a member key
      Expected_Comma_Or_End, --  value not followed by ',' or the closer
      Trailing_Data,         --  bytes after the top-level value

      --  Tokens
      Invalid_Literal,       --  not exactly true / false / null
      Invalid_Number,        --  number token violates the RFC grammar
      Invalid_String_Char,   --  unescaped control character in a string
      Invalid_Escape,        --  malformed \ escape, or a lone surrogate
      Invalid_UTF8);         --  ill-formed UTF-8 (overlong, surrogate, ...)

   --  A bounds-safe view of a payload described by inclusive bounds.
   --  First .. Last may be the canonical null range First .. First - 1.
   function Payload
     (Buffer : String;
      First  : Positive;
      Last   : Natural) return String
   is (if Last < First then "" else Buffer (First .. Last))
   with
     Pre =>
       First >= Buffer'First
       and then Last <= Buffer'Last
       and then First - 1 <= Last;

end JSON;
