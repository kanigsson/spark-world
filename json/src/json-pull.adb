--  JSON.Pull body. All scanning works on an offset Pos counting consumed
--  characters from Input'First; the current character is
--  Input (Input'First + Pos). Each helper carries the bounds and progress
--  facts the caller needs, so the proof decomposes per scanner.

package body JSON.Pull with SPARK_Mode => On is

   -----------------------
   -- Character classes --
   -----------------------

   function Is_WS (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.LF or else C = ASCII.CR);

   function Is_Digit (C : Character) return Boolean is (C in '0' .. '9');

   function Is_Hex (C : Character) return Boolean is
     (C in '0' .. '9' | 'a' .. 'f' | 'A' .. 'F');

   --  The character under the cursor

   function Cur (Input : String; Pos : Natural) return Character is
     (Input (Input'First + Pos))
   with Pre => Pos < Input'Length;

   --  True at end of input or before a character that may follow a
   --  complete scalar token (whitespace, separator, or a closer). A
   --  number or literal must stop at one of these; anything else makes
   --  the token itself malformed ("01", "truex", "1.2.3").

   function At_Delimiter (Input : String; Pos : Natural) return Boolean is
     (Pos >= Input'Length
      or else Is_WS (Cur (Input, Pos))
      or else Cur (Input, Pos) in ',' | ']' | '}')
   with Pre => Pos <= Input'Length;

   --------------
   -- Scanners --
   --------------

   procedure Skip_WS (Input : String; Pos : in out Natural)
   with
     Global => null,
     Pre    => Pos <= Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then (Pos = Input'Length
                         or else not Is_WS (Cur (Input, Pos)));

   procedure Skip_Digits (Input : String; Pos : in out Natural)
   with
     Global => null,
     Pre    => Pos <= Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then (Pos = Input'Length
                         or else not Is_Digit (Cur (Input, Pos)));

   --  Four hex digits of a \u escape, as a code unit

   procedure Scan_Hex4
     (Input  : in     String;
      Pos    : in out Natural;
      Code   :    out Natural;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Pos <= Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then Code <= 16#FFFF#
               and then (if Status = OK then Pos = Pos'Old + 4);

   --  The rest of an escape sequence, after the backslash

   procedure Scan_Escape
     (Input  : in     String;
      Pos    : in out Natural;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Pos <= Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then (if Status = OK then Pos > Pos'Old);

   --  One continuation byte, constrained to Lo .. Hi

   procedure Take_Cont
     (Input  : in     String;
      Pos    : in out Natural;
      Lo, Hi : in     Natural;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Lo <= Hi and then Hi <= 255 and then Pos <= Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then (if Status = OK then Pos = Pos'Old + 1);

   --  One multi-byte UTF-8 sequence, from its lead byte. Rejects stray
   --  continuation bytes, overlong forms, surrogates and > U+10FFFF.

   procedure Scan_UTF8
     (Input  : in     String;
      Pos    : in out Natural;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Pos < Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then (if Status = OK then Pos > Pos'Old);

   --  A whole string token, from its opening quote. On OK the cursor is
   --  past the closing quote and First .. Last slice the content.

   procedure Scan_String
     (Input   : in     String;
      Pos     : in out Natural;
      First   :    out Positive;
      Last    :    out Natural;
      Escaped :    out Boolean;
      Status  :    out Status_Type)
   with
     Global => null,
     Pre    => Pos < Input'Length and then Cur (Input, Pos) = '"',
     Post   => Pos in Pos'Old + 1 .. Input'Length
               and then (if Status = OK
                         then First >= Input'First
                              and then Last <= Input'Last
                              and then First - 1 <= Last);

   --  A whole number token, from its '-' or first digit

   procedure Scan_Number
     (Input  : in     String;
      Pos    : in out Natural;
      Is_Int :    out Boolean;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Pos < Input'Length
               and then (Cur (Input, Pos) = '-'
                         or else Is_Digit (Cur (Input, Pos))),
     Post   => Pos in Pos'Old + 1 .. Input'Length;

   --  true / false / null, from its first character

   procedure Scan_Literal
     (Input  : in     String;
      Pos    : in out Natural;
      Word   : in     String;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Word'Length in 1 .. 5
               and then Pos <= Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then (if Status = OK then Pos = Pos'Old + Word'Length);

   --  One value, from its first (non-whitespace) character: pushes on
   --  '{' / '[', scans scalars, and leaves the grammar state at what
   --  follows the value (or the container's first element).

   procedure Do_Value
     (Input  : in     String;
      P      : in out Parser;
      Ev     :    out Event;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Input'Last < Positive'Last
               and then P.Pos < Input'Length
               and then P.Depth <= Max_Depth,
     Post   => P.Pos in P.Pos'Old .. Input'Length
               and then P.Depth <= Max_Depth
               and then (if Status = OK
                         then P.Pos > P.Pos'Old
                              and then Well_Formed (P)
                              and then Ev.Kind in Object_Start | Array_Start
                                | String_Value | Number_Value
                                | Boolean_Value | Null_Value
                              and then (if Ev.Kind in Object_Start | Array_Start
                                        then P.State in Expect_First_Key
                                                      | Expect_Value_Or_End
                                        else P.State in Expect_Comma_Or_End
                                                      | Expect_EOF)
                              and then (if Ev.Kind in String_Value | Number_Value
                                        then Ev.First >= Input'First
                                             and then Ev.Last <= Input'Last
                                             and then Ev.First - 1 <= Ev.Last));

   --  One object member key and its ':', from the key's opening quote
   --  (or earlier whitespace already skipped by the caller)

   procedure Do_Key
     (Input  : in     String;
      P      : in out Parser;
      Ev     :    out Event;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Input'Last < Positive'Last
               and then P.Pos <= Input'Length
               and then P.Depth in 1 .. Max_Depth,
     Post   => P.Pos in P.Pos'Old .. Input'Length
               and then P.Depth = P.Depth'Old
               and then (if Status = OK
                         then P.Pos > P.Pos'Old
                              and then P.State = Expect_Value
                              and then Ev.Kind = Member_Key
                              and then Ev.First >= Input'First
                              and then Ev.Last <= Input'Last
                              and then Ev.First - 1 <= Ev.Last);

   -------------
   -- Skip_WS --
   -------------

   procedure Skip_WS (Input : String; Pos : in out Natural) is
   begin
      while Pos < Input'Length and then Is_WS (Cur (Input, Pos)) loop
         Pos := Pos + 1;
         pragma Loop_Invariant (Pos in Pos'Loop_Entry .. Input'Length);
         pragma Loop_Variant (Increases => Pos);
      end loop;
   end Skip_WS;

   -----------------
   -- Skip_Digits --
   -----------------

   procedure Skip_Digits (Input : String; Pos : in out Natural) is
   begin
      while Pos < Input'Length and then Is_Digit (Cur (Input, Pos)) loop
         Pos := Pos + 1;
         pragma Loop_Invariant (Pos in Pos'Loop_Entry .. Input'Length);
         pragma Loop_Variant (Increases => Pos);
      end loop;
   end Skip_Digits;

   ---------------
   -- Scan_Hex4 --
   ---------------

   procedure Scan_Hex4
     (Input  : in     String;
      Pos    : in out Natural;
      Code   :    out Natural;
      Status :    out Status_Type)
   is
      C : Character;
      V : Natural range 0 .. 15;
   begin
      Code := 0;
      if Input'Length - Pos < 4 then
         Status := Truncated;
         return;
      end if;
      for I in 1 .. 4 loop
         pragma Loop_Invariant (Pos = Pos'Loop_Entry + (I - 1));
         pragma Loop_Invariant
           (Code <= (case I is
                        when 1 => 0, when 2 => 15,
                        when 3 => 255, when 4 => 4095));
         C := Cur (Input, Pos);
         if not Is_Hex (C) then
            Code   := 0;
            Status := Invalid_Escape;
            return;
         end if;
         case C is
            when '0' .. '9' =>
               V := Character'Pos (C) - Character'Pos ('0');
            when 'a' .. 'f' =>
               V := (Character'Pos (C) - Character'Pos ('a')) + 10;
            when 'A' .. 'F' =>
               V := (Character'Pos (C) - Character'Pos ('A')) + 10;
            when others =>
               V := 0;  --  excluded by the Is_Hex test above
         end case;
         Code := Code * 16 + V;
         Pos  := Pos + 1;
      end loop;
      Status := OK;
   end Scan_Hex4;

   -----------------
   -- Scan_Escape --
   -----------------

   procedure Scan_Escape
     (Input  : in     String;
      Pos    : in out Natural;
      Status :    out Status_Type)
   is
      C    : Character;
      High : Natural;
      Low  : Natural;
   begin
      if Pos >= Input'Length then
         Status := Truncated;
         return;
      end if;
      C   := Cur (Input, Pos);
      Pos := Pos + 1;
      case C is
         when '"' | '\' | '/' | 'b' | 'f' | 'n' | 'r' | 't' =>
            Status := OK;

         when 'u' =>
            Scan_Hex4 (Input, Pos, High, Status);
            if Status /= OK then
               return;
            end if;
            if High in 16#D800# .. 16#DBFF# then
               --  High surrogate: only valid as the first half of a
               --  \uXXXX\uXXXX pair encoding one supplementary character
               if Input'Length - Pos < 2 then
                  Status := Truncated;
                  return;
               end if;
               if Cur (Input, Pos) /= '\'
                 or else Cur (Input, Pos + 1) /= 'u'
               then
                  Status := Invalid_Escape;
                  return;
               end if;
               Pos := Pos + 2;
               Scan_Hex4 (Input, Pos, Low, Status);
               if Status /= OK then
                  return;
               end if;
               if Low not in 16#DC00# .. 16#DFFF# then
                  Status := Invalid_Escape;
               end if;
            elsif High in 16#DC00# .. 16#DFFF# then
               --  A lone low surrogate never encodes a character
               Status := Invalid_Escape;
            end if;

         when others =>
            Status := Invalid_Escape;
      end case;
   end Scan_Escape;

   ---------------
   -- Take_Cont --
   ---------------

   procedure Take_Cont
     (Input  : in     String;
      Pos    : in out Natural;
      Lo, Hi : in     Natural;
      Status :    out Status_Type)
   is
      B : Natural;
   begin
      if Pos >= Input'Length then
         Status := Truncated;
         return;
      end if;
      B := Character'Pos (Cur (Input, Pos));
      if B in Lo .. Hi then
         Pos    := Pos + 1;
         Status := OK;
      else
         Status := Invalid_UTF8;
      end if;
   end Take_Cont;

   ---------------
   -- Scan_UTF8 --
   ---------------

   procedure Scan_UTF8
     (Input  : in     String;
      Pos    : in out Natural;
      Status :    out Status_Type)
   is
      B0   : constant Natural := Character'Pos (Cur (Input, Pos));
      Rest : Natural;
   begin
      Pos := Pos + 1;

      --  The lead byte decides the length and the constraint on the
      --  first continuation byte; the remaining continuation bytes are
      --  plain 80 .. BF. The tightened first-byte ranges exclude
      --  overlong forms (C0/C1, E0 80 .., F0 80 ..), surrogates
      --  (ED A0 ..) and anything above U+10FFFF (F4 90 .., F5 ..).

      if B0 in 16#C2# .. 16#DF# then
         Take_Cont (Input, Pos, 16#80#, 16#BF#, Status);
         Rest := 0;
      elsif B0 = 16#E0# then
         Take_Cont (Input, Pos, 16#A0#, 16#BF#, Status);
         Rest := 1;
      elsif B0 in 16#E1# .. 16#EC# or else B0 in 16#EE# .. 16#EF# then
         Take_Cont (Input, Pos, 16#80#, 16#BF#, Status);
         Rest := 1;
      elsif B0 = 16#ED# then
         Take_Cont (Input, Pos, 16#80#, 16#9F#, Status);
         Rest := 1;
      elsif B0 = 16#F0# then
         Take_Cont (Input, Pos, 16#90#, 16#BF#, Status);
         Rest := 2;
      elsif B0 in 16#F1# .. 16#F3# then
         Take_Cont (Input, Pos, 16#80#, 16#BF#, Status);
         Rest := 2;
      elsif B0 = 16#F4# then
         Take_Cont (Input, Pos, 16#80#, 16#8F#, Status);
         Rest := 2;
      else
         Status := Invalid_UTF8;
         return;
      end if;

      for I in 1 .. Rest loop
         pragma Loop_Invariant (Pos in Pos'Loop_Entry .. Input'Length);
         exit when Status /= OK;
         Take_Cont (Input, Pos, 16#80#, 16#BF#, Status);
      end loop;
   end Scan_UTF8;

   -----------------
   -- Scan_String --
   -----------------

   procedure Scan_String
     (Input   : in     String;
      Pos     : in out Natural;
      First   :    out Positive;
      Last    :    out Natural;
      Escaped :    out Boolean;
      Status  :    out Status_Type)
   is
      Content : constant Natural := Pos + 1;  --  offset of the content
      C       : Character;
   begin
      First   := Input'First;
      Last    := Input'First - 1;
      Escaped := False;
      Pos     := Pos + 1;  --  the opening quote

      loop
         pragma Loop_Invariant (Pos in Content .. Input'Length);
         pragma Loop_Variant (Increases => Pos);
         if Pos >= Input'Length then
            Status := Truncated;
            return;
         end if;
         C := Cur (Input, Pos);
         if C = '"' then
            First  := Input'First + Content;
            Last   := Input'First + (Pos - 1);
            Pos    := Pos + 1;
            Status := OK;
            return;
         elsif C = '\' then
            Escaped := True;
            Pos     := Pos + 1;
            Scan_Escape (Input, Pos, Status);
            if Status /= OK then
               return;
            end if;
         elsif Character'Pos (C) < 32 then
            --  Control characters must be escaped (RFC 8259, section 7)
            Status := Invalid_String_Char;
            return;
         elsif Character'Pos (C) < 128 then
            Pos := Pos + 1;
         else
            Scan_UTF8 (Input, Pos, Status);
            if Status /= OK then
               return;
            end if;
         end if;
      end loop;
   end Scan_String;

   -----------------
   -- Scan_Number --
   -----------------

   procedure Scan_Number
     (Input  : in     String;
      Pos    : in out Natural;
      Is_Int :    out Boolean;
      Status :    out Status_Type)
   is
   begin
      Is_Int := True;

      --  Optional minus, then int = 0 / digit1-9 *DIGIT

      if Cur (Input, Pos) = '-' then
         Pos := Pos + 1;
         if Pos >= Input'Length then
            Status := Truncated;
            return;
         elsif not Is_Digit (Cur (Input, Pos)) then
            Status := Invalid_Number;
            return;
         end if;
      end if;
      if Cur (Input, Pos) = '0' then
         Pos := Pos + 1;
         --  A leading zero stands alone; "01" fails the delimiter test
      else
         Skip_Digits (Input, Pos);
      end if;

      --  Optional frac = '.' 1*DIGIT

      if Pos < Input'Length and then Cur (Input, Pos) = '.' then
         Is_Int := False;
         Pos    := Pos + 1;
         if Pos >= Input'Length then
            Status := Truncated;
            return;
         elsif not Is_Digit (Cur (Input, Pos)) then
            Status := Invalid_Number;
            return;
         end if;
         Skip_Digits (Input, Pos);
      end if;

      --  Optional exp = ('e' / 'E') [sign] 1*DIGIT

      if Pos < Input'Length
        and then Cur (Input, Pos) in 'e' | 'E'
      then
         Is_Int := False;
         Pos    := Pos + 1;
         if Pos < Input'Length and then Cur (Input, Pos) in '+' | '-' then
            Pos := Pos + 1;
         end if;
         if Pos >= Input'Length then
            Status := Truncated;
            return;
         elsif not Is_Digit (Cur (Input, Pos)) then
            Status := Invalid_Number;
            return;
         end if;
         Skip_Digits (Input, Pos);
      end if;

      Status := (if At_Delimiter (Input, Pos) then OK else Invalid_Number);
   end Scan_Number;

   ------------------
   -- Scan_Literal --
   ------------------

   procedure Scan_Literal
     (Input  : in     String;
      Pos    : in out Natural;
      Word   : in     String;
      Status :    out Status_Type)
   is
   begin
      if Input'Length - Pos < Word'Length then
         --  Cannot even hold the word: ran off the end of the document
         Status := Truncated;
         return;
      end if;
      for I in 0 .. Word'Length - 1 loop
         if Input (Input'First + (Pos + I)) /= Word (Word'First + I) then
            Status := Invalid_Literal;
            return;
         end if;
      end loop;
      Pos := Pos + Word'Length;
      Status := (if At_Delimiter (Input, Pos) then OK else Invalid_Literal);
   end Scan_Literal;

   --------------
   -- Do_Value --
   --------------

   procedure Do_Value
     (Input  : in     String;
      P      : in out Parser;
      Ev     :    out Event;
      Status :    out Status_Type)
   is
      C      : constant Character := Cur (Input, P.Pos);
      First  : Positive;
      Last   : Natural;
      Esc    : Boolean;
      Is_Int : Boolean;
      Start  : constant Natural := P.Pos;
   begin
      Ev     := (Kind => Null_Value, First => 1, Last => 0, others => False);
      Status := OK;

      case C is
         when '{' =>
            if P.Depth >= Max_Depth then
               Status := Nesting_Too_Deep;
               return;
            end if;
            P.Depth           := P.Depth + 1;
            P.Stack (P.Depth) := In_Object;
            P.Pos             := P.Pos + 1;
            P.State           := Expect_First_Key;
            Ev.Kind           := Object_Start;

         when '[' =>
            if P.Depth >= Max_Depth then
               Status := Nesting_Too_Deep;
               return;
            end if;
            P.Depth           := P.Depth + 1;
            P.Stack (P.Depth) := In_Array;
            P.Pos             := P.Pos + 1;
            P.State           := Expect_Value_Or_End;
            Ev.Kind           := Array_Start;

         when '"' =>
            Scan_String (Input, P.Pos, First, Last, Esc, Status);
            if Status /= OK then
               return;
            end if;
            Ev := (Kind => String_Value, First => First, Last => Last,
                   Bool => False, Escaped => Esc, Is_Integer => False);
            P.State :=
              (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);

         when '-' | '0' .. '9' =>
            Scan_Number (Input, P.Pos, Is_Int, Status);
            if Status /= OK then
               return;
            end if;
            Ev := (Kind => Number_Value,
                   First => Input'First + Start,
                   Last => Input'First + (P.Pos - 1),
                   Bool => False, Escaped => False, Is_Integer => Is_Int);
            P.State :=
              (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);

         when 't' =>
            Scan_Literal (Input, P.Pos, "true", Status);
            if Status /= OK then
               return;
            end if;
            Ev.Kind := Boolean_Value;
            Ev.Bool := True;
            P.State :=
              (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);

         when 'f' =>
            Scan_Literal (Input, P.Pos, "false", Status);
            if Status /= OK then
               return;
            end if;
            Ev.Kind := Boolean_Value;
            P.State :=
              (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);

         when 'n' =>
            Scan_Literal (Input, P.Pos, "null", Status);
            if Status /= OK then
               return;
            end if;
            Ev.Kind := Null_Value;
            P.State :=
              (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);

         when others =>
            Status := Expected_Value;
      end case;
   end Do_Value;

   ------------
   -- Do_Key --
   ------------

   procedure Do_Key
     (Input  : in     String;
      P      : in out Parser;
      Ev     :    out Event;
      Status :    out Status_Type)
   is
      First : Positive;
      Last  : Natural;
      Esc   : Boolean;
   begin
      Ev := (Kind => Null_Value, First => 1, Last => 0, others => False);

      if P.Pos >= Input'Length then
         Status := Truncated;
         return;
      end if;
      if Cur (Input, P.Pos) /= '"' then
         Status := Expected_Key;
         return;
      end if;
      Scan_String (Input, P.Pos, First, Last, Esc, Status);
      if Status /= OK then
         return;
      end if;
      Skip_WS (Input, P.Pos);
      if P.Pos >= Input'Length then
         Status := Truncated;
         return;
      end if;
      if Cur (Input, P.Pos) /= ':' then
         Status := Expected_Colon;
         return;
      end if;
      P.Pos   := P.Pos + 1;
      P.State := Expect_Value;
      Ev := (Kind => Member_Key, First => First, Last => Last,
             Bool => False, Escaped => Esc, Is_Integer => False);
      Status := OK;
   end Do_Key;

   ----------
   -- Next --
   ----------

   procedure Next
     (Input  : in     String;
      P      : in out Parser;
      Ev     :    out Event;
      Status :    out Status_Type)
   is
   begin
      Ev     := (Kind => Null_Value, First => 1, Last => 0, others => False);
      Status := OK;

      Skip_WS (Input, P.Pos);

      case P.State is
         when Expect_Value =>
            if P.Pos >= Input'Length then
               Status := Truncated;
            else
               Do_Value (Input, P, Ev, Status);
            end if;

         when Expect_Value_Or_End =>
            if P.Pos >= Input'Length then
               Status := Truncated;
            elsif Cur (Input, P.Pos) = ']' then
               P.Pos   := P.Pos + 1;
               P.Depth := P.Depth - 1;
               P.State :=
                 (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);
               Ev.Kind := Array_End;
            else
               Do_Value (Input, P, Ev, Status);
            end if;

         when Expect_First_Key =>
            if P.Pos >= Input'Length then
               Status := Truncated;
            elsif Cur (Input, P.Pos) = '}' then
               P.Pos   := P.Pos + 1;
               P.Depth := P.Depth - 1;
               P.State :=
                 (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);
               Ev.Kind := Object_End;
            else
               Do_Key (Input, P, Ev, Status);
            end if;

         when Expect_Key =>
            Do_Key (Input, P, Ev, Status);

         when Expect_Comma_Or_End =>
            if P.Pos >= Input'Length then
               Status := Truncated;
            elsif Cur (Input, P.Pos) = ',' then
               P.Pos := P.Pos + 1;
               Skip_WS (Input, P.Pos);
               if P.Stack (P.Depth) = In_Object then
                  Do_Key (Input, P, Ev, Status);
               elsif P.Pos >= Input'Length then
                  Status := Truncated;
               else
                  Do_Value (Input, P, Ev, Status);
               end if;
            elsif Cur (Input, P.Pos) = '}'
              and then P.Stack (P.Depth) = In_Object
            then
               P.Pos   := P.Pos + 1;
               P.Depth := P.Depth - 1;
               P.State :=
                 (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);
               Ev.Kind := Object_End;
            elsif Cur (Input, P.Pos) = ']'
              and then P.Stack (P.Depth) = In_Array
            then
               P.Pos   := P.Pos + 1;
               P.Depth := P.Depth - 1;
               P.State :=
                 (if P.Depth = 0 then Expect_EOF else Expect_Comma_Or_End);
               Ev.Kind := Array_End;
            else
               Status := Expected_Comma_Or_End;
            end if;

         when Expect_EOF =>
            if P.Pos >= Input'Length then
               Ev.Kind := Document_End;
               P.State := Finished;
            else
               Status := Trailing_Data;
            end if;

         when Finished | Failed =>
            raise Program_Error;  --  excluded by the precondition
      end case;

      if Status /= OK then
         P.State := Failed;
      end if;
   end Next;

   --------------
   -- Validate --
   --------------

   procedure Validate
     (Input  : in     String;
      Status :    out Status_Type)
   is
      P  : Parser;
      Ev : Event;
   begin
      loop
         Next (Input, P, Ev, Status);
         exit when Status /= OK or else Ev.Kind = Document_End;
         pragma Loop_Invariant
           (P.Pos <= Input'Length
            and then Well_Formed (P)
            and then P.State not in Finished | Failed);
         pragma Loop_Variant (Increases => P.Pos);
      end loop;
   end Validate;

end JSON.Pull;
