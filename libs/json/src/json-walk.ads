--  JSON.Walk — proved helpers for walking a document of known shape with
--  the pull cursor: open a container, iterate or find object members, read
--  a typed value, skip a value you don't want. A helper kit for clients
--  that validate a document against a compile-time-known schema, not a
--  schema engine: the client still owns the walk, these are its steps.
--
--  Every helper consumes whole events through JSON.Pull.Next, so the
--  cursor invariants carry over: payload slices lie within the input, and
--  every successful step strictly advances the cursor — a client loop
--  whose body takes at least one successful step per iteration provably
--  terminates (pragma Loop_Variant (Increases => P.Pos)).
--
--  Outcomes fold the two ways a walk can go wrong into one enumeration:
--  the bytes are not valid JSON at all (Bad_JSON), or they are valid JSON
--  that does not have the expected shape (Wrong_Shape) — a member of the
--  wrong type, a missing container, an integer beyond Integer_64. After a
--  non-OK outcome the cursor is not meant to be stepped further; clients
--  report and stop. Unknown members are the one expected mismatch:
--  iterate with Next_Member and Skip_Value what you don't recognise —
--  that is what keeps a reader forward-compatible.

with JSON.Pull;
with JSON.Strings;
with Interfaces;
with Unicode_Text.UTF_8;

package JSON.Walk
  with SPARK_Mode => On
is

   use type Interfaces.Integer_64;

   type Step_Status is
     (OK,            --  the expectation held; the cursor advanced
      Wrong_Shape,   --  valid JSON here, but not what the caller expected
      Bad_JSON);     --  the underlying parser rejected the document

   --  The condition under which a helper may take a step: the input is
   --  sliceable, the cursor is inside it, structurally sound, and neither
   --  finished nor failed. A default-initialised Parser on any input with
   --  Input'Last < Positive'Last is Ready; every OK outcome re-establishes
   --  Ready, so a walk only ever checks outcomes.
   function Ready (Input : String; P : JSON.Pull.Parser) return Boolean
   is (Input'Last < Positive'Last
       and then P.Pos <= Input'Length
       and then JSON.Pull.Well_Formed (P)
       and then P.State not in JSON.Pull.Finished | JSON.Pull.Failed);

   --  A payload slice of the input (a key or a string value), with the
   --  cursor's "needs JSON.Strings.Decode" flag. The default span is empty.
   type Span is record
      First   : Positive := 1;
      Last    : Natural := 0;
      Escaped : Boolean := False;
   end record;

   function Valid_Span (S : Span; Input : String) return Boolean
   is (S.First >= Input'First
       and then S.Last <= Input'Last
       and then S.First - 1 <= S.Last);

   function Payload (Input : String; S : Span) return String
   is (JSON.Payload (Input, S.First, S.Last))
   with Pre => Valid_Span (S, Input);

   function Valid_Text_Span (S : Span; Input : String) return Boolean
   is (Valid_Span (S, Input)
       and then Unicode_Text.UTF_8.Is_Valid_UTF_8 (Payload (Input, S)));

   --  Compare logical decoded key text. Unescaped payloads take the direct
   --  byte-equality fast path; escaped payloads are streamed scalar by
   --  scalar without a temporary decoded string. Name is application
   --  schema data and therefore must already be valid UTF-8.
   function Matches (Input : String; S : Span; Name : String) return Boolean
   is (if not S.Escaped
       then Payload (Input, S) = Name
       else JSON.Strings.Decoded_Equals (Payload (Input, S), Name))
   with
     Pre =>
       Input'Last < Positive'Last
       and then Valid_Text_Span (S, Input)
       and then Unicode_Text.UTF_8.Is_Valid_UTF_8 (Name);

   --  Expect the start of an object / array.
   procedure Open_Object
     (Input : in String; P : in out JSON.Pull.Parser; Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK then Ready (Input, P) and then P.Pos > P.Pos'Old);

   procedure Open_Array
     (Input : in String; P : in out JSON.Pull.Parser; Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK then Ready (Input, P) and then P.Pos > P.Pos'Old);

   --  Inside an object, after Open_Object or a consumed member value:
   --  deliver the next member's key (Done = False), or report the end of
   --  the object (Done = True). The caller dispatches on the key and
   --  either reads the value with a getter or discards it with Skip_Value
   --  — skipping unknown members is what keeps a reader compatible with
   --  documents that grew new members.
   procedure Next_Member
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Key    : out Span;
      Done   : out Boolean;
      Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK
        then
          Ready (Input, P)
          and then P.Pos > P.Pos'Old
          and then (if not Done then Valid_Text_Span (Key, Input)));

   --  Skip members until one named Name is found (Found = True, cursor
   --  standing before its value) or the object ends (Found = False, the
   --  whole object consumed). For picking a single member out of an
   --  object; when several members are wanted, one Next_Member loop that
   --  dispatches on the key reads them in whatever order they appear.
   procedure Find_Member
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Name   : in String;
      Found  : out Boolean;
      Status : out Step_Status)
   with
     Global => null,
     Pre    =>
       Ready (Input, P) and then Unicode_Text.UTF_8.Is_Valid_UTF_8 (Name),
     Post   =>
       (if Status = OK then Ready (Input, P) and then P.Pos > P.Pos'Old);

   --  Consume one whole value — a scalar, or a container with everything
   --  in it.
   procedure Skip_Value
     (Input : in String; P : in out JSON.Pull.Parser; Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK then Ready (Input, P) and then P.Pos > P.Pos'Old);

   --  Expect a string value; its payload comes back as a span (decode it
   --  with JSON.Strings.Decode when Value.Escaped).
   procedure Get_String
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Value  : out Span;
      Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK
        then
          Ready (Input, P)
          and then P.Pos > P.Pos'Old
          and then Valid_Text_Span (Value, Input));

   --  Expect an integer number (no fraction, no exponent) that fits
   --  Integer_64; anything else — including a too-large integer — is
   --  Wrong_Shape. Value is 0 unless Status = OK.
   procedure Get_Integer
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Value  : out Interfaces.Integer_64;
      Status : out Step_Status)
   with
     Global => null,
     Post   =>
       (if Status = OK
        then Ready (Input, P) and then P.Pos > P.Pos'Old
        else Value = 0),
     Pre    => Ready (Input, P);

   --  Expect true or false.
   procedure Get_Boolean
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Value  : out Boolean;
      Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK then Ready (Input, P) and then P.Pos > P.Pos'Old);

   --  Inside an array of objects: expect the start of the next element
   --  object (Done = False) or the end of the array (Done = True).
   procedure Next_Element_Object
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Done   : out Boolean;
      Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK then Ready (Input, P) and then P.Pos > P.Pos'Old);

   --  Inside an array of strings: deliver the next element (Done = False)
   --  or report the end of the array (Done = True).
   procedure Next_Element_String
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Value  : out Span;
      Done   : out Boolean;
      Status : out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P),
     Post   =>
       (if Status = OK
        then
          Ready (Input, P)
          and then P.Pos > P.Pos'Old
          and then (if not Done then Valid_Text_Span (Value, Input)));

end JSON.Walk;
