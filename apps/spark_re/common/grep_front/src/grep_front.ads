with Ada.Command_Line;
with Ada.Strings.Unbounded;

--  What spark-grep and spark-rg both decide, as opposed to what they do.
--
--  The two programs are one regex kernel behind two front ends, and the front
--  ends had drifted into two copies of the same option letters, the same
--  record-selection rule, the same record prefix and the same literal escape.
--  Everything here takes values and returns values, which is what lets it be
--  SPARK: the diagnostic and output channels are not, since naming the
--  standard error file takes a unit out of SPARK, and they live behind their
--  own boundary instead.
--
--  The option letters are specified rather than described: Apply_Letter's
--  postcondition says which letters exist, what each one changes and that it
--  changes nothing else. Two programs cannot drift apart on a rule the prover
--  checks, and a letter one program alone accepts is handled by that program,
--  so a shared "accept the union" parser is deliberately not what this is.

package Grep_Front
  with SPARK_Mode => On
is

   package Unbounded renames Ada.Strings.Unbounded;

   ---------------------------------------------------------------------------
   --  Settings
   ---------------------------------------------------------------------------

   --  Whether a selected record carries the name of the input it came from.
   --  The two programs agree on -h and -H and differ only in the default:
   --  one names inputs when it was given more than one, the other always,
   --  because a recursive search reports matches from many files.
   type Name_Display is (Auto, Never, Always);

   --  Scalars only, so that the whole record can be compared in a contract
   --  and copied for 'Old without dragging a string along. The pattern is
   --  separate for that reason.
   type Settings is record
      Numbered   : Boolean := False;
      Invert     : Boolean := False;
      Count_Only : Boolean := False;
      Quiet      : Boolean := False;
      List_Files : Boolean := False;
      Whole      : Boolean := False;
      Fixed      : Boolean := False;
      Names      : Name_Display := Auto;
      Delimiter  : Character := ASCII.LF;
   end record;

   function Show_Prefix (Opt : Settings; Named_Inputs : Natural) return Boolean
   is (case Opt.Names is
         when Always => True,
         when Never  => False,
         when Auto   => Named_Inputs > 1);

   ---------------------------------------------------------------------------
   --  Arguments
   ---------------------------------------------------------------------------

   --  "-" alone is an operand, so that it can name standard input, and so is
   --  everything after "--".
   type Arg_Kind is (End_Marker, Long_Option, Cluster, Operand);

   function Classify (Arg : String; End_Options : Boolean) return Arg_Kind
   is (if End_Options
       then Operand
       elsif Arg = "--"
       then End_Marker
       elsif Arg'Length > 1 and then Arg (Arg'First) = '-'
       then (if Arg (Arg'First + 1) = '-' then Long_Option else Cluster)
       else Operand);

   type Letter_Result is (Accepted, Needs_Value, Unknown);

   procedure Apply_Letter
     (Opt : in out Settings; Letter : Character; Outcome : out Letter_Result)
   with
     Global => null,
     Post   =>
       (case Letter is
          when 'E'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Fixed => False),
          when 'F'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Fixed => True),
          when 'n'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Numbered => True),
          when 'v'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Invert => True),
          when 'c'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Count_Only => True),
          when 'q'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Quiet => True),
          when 'l'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta List_Files => True),
          when 'x'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Whole => True),
          when 'h'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Names => Never),
          when 'H'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Names => Always),
          when 'z'    =>
            Outcome = Accepted
            and then Opt = (Opt'Old with delta Delimiter => ASCII.NUL),
          when 'e'    => Outcome = Needs_Value and then Opt = Opt'Old,
          when others => Outcome = Unknown and then Opt = Opt'Old);

   --  A letter that takes a value takes the rest of its cluster when there is
   --  one, and the next argument otherwise. Only the first half is a decision
   --  about text; consuming an argument belongs to the caller's loop.
   function Has_Inline_Value (Cluster : String; K : Positive) return Boolean
   is (K in Cluster'Range and then K < Cluster'Last)
   with Pre => Cluster'Last < Positive'Last;

   function Inline_Value (Cluster : String; K : Positive) return String
   is (Cluster (K + 1 .. Cluster'Last))
   with
     Pre  =>
       Cluster'Last < Positive'Last and then Has_Inline_Value (Cluster, K),
     Post => Inline_Value'Result'Length = Cluster'Last - K;

   ---------------------------------------------------------------------------
   --  The pattern
   ---------------------------------------------------------------------------

   --  Neither program accepts a second pattern, however it was spelled.
   type Pattern_State is record
      Text    : Unbounded.Unbounded_String;
      Present : Boolean := False;
   end record;

   type Pattern_Result is (Taken, Already_Set);

   procedure Set_Pattern
     (Self : in out Pattern_State; Value : String; Result : out Pattern_Result)
   with
     Global => null,
     Post   =>
       (if Self'Old.Present
        then Result = Already_Set and then Self = Self'Old
        else
          Result = Taken
          and then Self.Present
          and then Unbounded.To_String (Self.Text) = Value);

   ---------------------------------------------------------------------------
   --  Literal patterns
   ---------------------------------------------------------------------------

   function Is_Meta (C : Character) return Boolean
   is (C
       in '\'
        | '.'
        | '^'
        | '$'
        | '|'
        | '?'
        | '*'
        | '+'
        | '('
        | ')'
        | '['
        | ']'
        | '{'
        | '}');

   --  The bound is arithmetic, not policy: an escaped literal is at most twice
   --  as long as the literal. How long a pattern the engine will accept is the
   --  caller's business, and the caller is where the two meet.
   Max_Literal : constant := Natural'Last / 2 - 1;

   --  Counted from the end, so that the escape below unfolds it one character
   --  per iteration in the direction its loop runs. Counted from the front it
   --  would need an induction the provers do not find.
   function Meta_Count (Literal : String) return Natural
   with
     Ghost,
     Global             => null,
     Subprogram_Variant => (Decreases => Literal'Length),
     Post               => Meta_Count'Result <= Literal'Length;

   --  -F: the literal as an extended regex that matches exactly itself.
   function Escape_Literal (Literal : String) return String
   with
     Global => null,
     Pre    => Literal'Length <= Max_Literal,
     Post   =>
       Escape_Literal'Result'Length = Literal'Length + Meta_Count (Literal)
       and then Escape_Literal'Result'First = 1;

   ---------------------------------------------------------------------------
   --  What to do with a record
   ---------------------------------------------------------------------------

   --  The selection rule both programs wrote as the same chain of ifs. A
   --  record that is selected is counted whatever is then done with it, which
   --  is why Selects is not "the record is written".
   type Match_Action is
     (Ignore, Halt_Quiet, Emit_Input_Name, Tally_Only, Emit_Record);

   function Decide (Opt : Settings; Matched : Boolean) return Match_Action
   is (if Matched = Opt.Invert
       then Ignore
       elsif Opt.Quiet
       then Halt_Quiet
       elsif Opt.List_Files
       then Emit_Input_Name
       elsif Opt.Count_Only
       then Tally_Only
       else Emit_Record);

   function Selects (Action : Match_Action) return Boolean
   is (Action /= Ignore);

   --  Nothing further from this input can change the answer.
   function Halts (Action : Match_Action) return Boolean
   is (Action in Halt_Quiet | Emit_Input_Name);

   --  The numbers a record's prefix carries arrive as images rather than as
   --  values, and the image library is the caller's business. That is not
   --  only layering: a project that withs a proved library gets that
   --  library's units in its own proof run, whatever switch is passed, so a
   --  dependency here would put thousands of someone else's goals, and their
   --  open checks, in front of this crate's own.
   --
   --  Note what the images below are *not* required to be: one-based. An
   --  image is naturally the tail of a fixed buffer, so its first index is
   --  wherever the digits began, and a precondition demanding otherwise would
   --  be one no caller could meet. Only the name is one-based, because a
   --  caller holds it as a whole string.
   function Name_Prefix (Prefix : Boolean; Name : String) return String
   is (if Prefix then Name & ":" else "")
   with
     Global => null,
     Pre    => Name'First = 1 and then Name'Last < Natural'Last,
     Post   =>
       Name_Prefix'Result'First = 1
       and then (Name_Prefix'Result'Length = 0) = (not Prefix);

   --  "name:" then "line:", in that order, as both programs wrote them.
   --
   --  Nothing is said about where the result sits: concatenation takes its
   --  bounds from the right operand when the left one is empty, so a
   --  one-based result is not something this can promise.
   function Match_Prefix
     (Opt : Settings; Prefix : Boolean; Name : String; Line : String)
      return String
   is (Name_Prefix (Prefix, Name) & (if Opt.Numbered then Line & ":" else ""))
   with
     Global => null,
     Pre    =>
       Name'First = 1
       and then Line'Last < Positive'Last
       and then Name'Length <= Natural'Last - Line'Length - 2,
     Post   =>
       (Match_Prefix'Result'Length = 0)
       = (not Prefix and then not Opt.Numbered);

   --  Whether the run reports a count per input instead of records. Both
   --  programs wrote this precedence out by hand, and it is not the same
   --  question as what to do with a record that matched: a count is reported
   --  even when nothing matched.
   function Reports_Count (Opt : Settings) return Boolean
   is (Opt.Count_Only and then not Opt.Quiet and then not Opt.List_Files);

   --  The count line -c reports for one input. It ends in a newline whatever
   --  the record delimiter is, as both programs already had it: the count is
   --  a report about the input, not a record from it.
   function Count_Line
     (Prefix : Boolean; Name : String; Count : String) return String
   is (Name_Prefix (Prefix, Name) & Count & ASCII.LF)
   with
     Global => null,
     Pre    =>
       Name'First = 1
       and then Count'Last < Positive'Last
       and then Name'Length <= Natural'Last - Count'Length - 2,
     Post   =>
       Count_Line'Result'Length
       = Count'Length + 1 + (if Prefix then Name'Length + 1 else 0);

   ---------------------------------------------------------------------------
   --  Exit status
   ---------------------------------------------------------------------------

   --  Both programs: 0 when something was selected, 1 when nothing was, 2 on
   --  any error, whether or not anything was selected before it.
   function Exit_Code
     (Had_Error, Any_Selected : Boolean) return Ada.Command_Line.Exit_Status
   is (if Had_Error then 2 elsif Any_Selected then 0 else 1);

end Grep_Front;
