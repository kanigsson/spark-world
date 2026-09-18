with Unicode_Text.UTF_8;

--  JSON.Pull — the pull-cursor parser: repeated calls to Next walk one
--  document and hand back one event at a time. Nothing is materialized;
--  string and number payloads are slices of the caller's input buffer, so
--  there is no limit on string lengths, member counts or document size
--  beyond the buffer itself.
--
--  Every byte of a hostile document is validated on the way through:
--  strings are checked for well-formed UTF-8 (overlong forms, surrogate
--  code points and out-of-range sequences are rejected) and for complete
--  escapes including surrogate pairs; numbers are checked against the RFC
--  grammar. A document that ends with Document_End and only OK statuses
--  conforms to RFC 8259.
--
--  Typical use:
--
--     P  : Pull.Parser;          --  default value = start of document
--     Ev : Pull.Event;
--     St : Status_Type;
--     loop
--        Pull.Next (Doc, P, Ev, St);
--        exit when St /= OK or else Ev.Kind = Pull.Document_End;
--        ...                     --  dispatch on Ev.Kind
--     end loop;
--
--  The Parser record is public so that its validity can be stated in
--  contracts; treat it as opaque and only read State.

package JSON.Pull
  with SPARK_Mode => On
is

   type Event_Kind is
     (Object_Start,    --  '{' consumed; expect keys
      Object_End,      --  '}' consumed
      Array_Start,     --  '[' consumed; expect values
      Array_End,       --  ']' consumed
      Member_Key,      --  key string plus its ':' consumed; payload = key
      String_Value,    --  payload = content between the quotes, undecoded
      Number_Value,    --  payload = the number token
      Boolean_Value,   --  Bool holds the value
      Null_Value,
      Document_End);   --  top-level value complete and input exhausted

   --  One parse event. First .. Last slice the payload out of the input
   --  buffer (a null range for an empty string): for Member_Key and
   --  String_Value the content between the quotes with escapes left
   --  undecoded — when Escaped is False that slice is the string itself,
   --  otherwise pass it through JSON.Strings.Decode; for Number_Value the
   --  whole token — Is_Integer means it has no fraction and no exponent,
   --  so JSON.Numbers.To_Integer applies.
   type Event is record
      Kind       : Event_Kind := Null_Value;
      First      : Positive := 1;
      Last       : Natural := 0;
      Bool       : Boolean := False;
      Escaped    : Boolean := False;
      Is_Integer : Boolean := False;
   end record;

   type Container is (In_Array, In_Object);
   type Container_Stack is array (1 .. Max_Depth) of Container;

   --  Where the grammar stands between events. Failed is absorbing: a
   --  parser that reported a non-OK status stays unusable.
   type State_Type is
     (Expect_Value,         --  top level, after ':', or after ',' in array
      Expect_Value_Or_End,  --  right after '[': first element or ']'
      Expect_First_Key,     --  right after '{': first key or '}'
      Expect_Key,           --  after ',' in object: key required
      Expect_Comma_Or_End,  --  after a value inside a container
      Expect_EOF,           --  after the top-level value
      Finished,             --  Document_End was delivered
      Failed);              --  a non-OK status was delivered

   type Parser is record
      Pos   : Natural := 0;   --  consumed characters (offset from 'First)
      Depth : Natural := 0;   --  open containers
      Stack : Container_Stack := [others => In_Array];
      State : State_Type := Expect_Value;
   end record;

   --  The structural invariant Next preserves: the depth is in range and
   --  matches what the state implies (inside-a-container states need an
   --  open container; the end states close them all).
   function Well_Formed (P : Parser) return Boolean
   is (P.Depth <= Max_Depth
       and then (case P.State is
                   when Expect_Value_Or_End
                      | Expect_First_Key
                      | Expect_Key
                      | Expect_Comma_Or_End   => P.Depth >= 1,
                   when Expect_EOF | Finished => P.Depth = 0,
                   when Expect_Value | Failed => True));

   --  Deliver the next event. On OK every payload slice lies within
   --  Input, and string/key payload bytes are valid UTF-8 even when they
   --  still contain JSON escapes. On any other status the parser moves to
   --  Failed and stays there. Every event except Document_End consumes at
   --  least one character, so a Next loop terminates — and Document_End
   --  is only delivered once every container is closed, so a loop that
   --  runs while a container is open advances on every step.
   procedure Next
     (Input  : in String;
      P      : in out Parser;
      Ev     : out Event;
      Status : out Status_Type)
   with
     Global => null,
     Pre    =>
       Input'Last < Positive'Last
       and then P.Pos <= Input'Length
       and then Well_Formed (P)
       and then P.State not in Finished | Failed,
     Post   =>
       P.Pos <= Input'Length
       and then P.Pos >= P.Pos'Old
       and then Well_Formed (P)
       and then (if Status = OK
                 then
                   P.State /= Failed
                   and then (P.State = Finished) = (Ev.Kind = Document_End)
                   and then (if Ev.Kind /= Document_End then P.Pos > P.Pos'Old)
                   and then (if Ev.Kind = Document_End then P.Depth'Old = 0)
                   and then (if Ev.Kind
                                in Member_Key | String_Value | Number_Value
                             then
                               Ev.First >= Input'First
                               and then Ev.Last <= Input'Last
                               and then Ev.First - 1 <= Ev.Last)
                   and then (if Ev.Kind in Member_Key | String_Value
                             then
                               Unicode_Text.UTF_8.Is_Valid_UTF_8
                                 (JSON.Payload (Input, Ev.First, Ev.Last)))
                 else P.State = Failed);

   --  Run the cursor over the whole document: Status = OK means Input is
   --  one RFC 8259 conformant JSON text (with valid UTF-8 and escapes
   --  throughout) within the nesting limit.
   procedure Validate (Input : in String; Status : out Status_Type)
   with Global => null, Pre => Input'Last < Positive'Last;

end JSON.Pull;
