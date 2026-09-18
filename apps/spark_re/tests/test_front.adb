with Ada.Command_Line;
with Grep_Front;
with Test_Checks;

--  The shared front end, tested directly rather than through the two CLIs.
--
--  Its postconditions already say what each option letter does, but a
--  contract proved in a release build is checked by nobody, and the letters
--  it must *not* accept are as load-bearing as the ones it must: each program
--  handles its own letters and reports the rest as errors, so a shared
--  routine that quietly accepted the union would take one program's
--  diagnostics away.

procedure Test_Front is
   use type Ada.Command_Line.Exit_Status;
   use type Grep_Front.Arg_Kind;
   use type Grep_Front.Letter_Result;
   use type Grep_Front.Match_Action;
   use type Grep_Front.Name_Display;
   use type Grep_Front.Pattern_Result;
   use type Grep_Front.Settings;
   package Front renames Grep_Front;
   use Test_Checks;

   Shared  : constant String := "EFnvcqlxhHz";
   --  The letters this package owns. Everything else is the caller's, and
   --  that includes the recursive program's -N, -L, -g and -j.
   Foreign : constant String := "NLgjiPwRA0-";

   function Applied (Letter : Character) return Front.Settings is
      Opt     : Front.Settings;
      Outcome : Front.Letter_Result;
   begin
      Front.Apply_Letter (Opt, Letter, Outcome);
      return Opt;
   end Applied;

   function Outcome_Of (Letter : Character) return Front.Letter_Result is
      Opt     : Front.Settings;
      Outcome : Front.Letter_Result;
   begin
      Front.Apply_Letter (Opt, Letter, Outcome);
      return Outcome;
   end Outcome_Of;

   Default : Front.Settings;
begin
   Start ("front-end unit checks");

   --  Letters
   for Letter of Shared loop
      Check (Outcome_Of (Letter) = Front.Accepted, "accepts -" & Letter);
      --  -E selects what a fresh setting already says, since its job is to
      --  undo an earlier -F rather than to turn anything on.
      if Letter /= 'E' then
         Check
           (Applied (Letter) /= Default, "-" & Letter & " changes something");
      end if;
   end loop;
   declare
      Opt     : Front.Settings;
      Outcome : Front.Letter_Result;
   begin
      Front.Apply_Letter (Opt, 'F', Outcome);
      Front.Apply_Letter (Opt, 'E', Outcome);
      Check (Opt = Default, "-E undoes an earlier -F");
   end;
   Check (Outcome_Of ('e') = Front.Needs_Value, "-e asks for a value");
   for Letter of Foreign loop
      Check (Outcome_Of (Letter) = Front.Unknown, "rejects -" & Letter);
      Check (Applied (Letter) = Default, "-" & Letter & " changes nothing");
   end loop;
   Check (Applied ('F').Fixed, "-F selects a literal pattern");
   Check (not Applied ('E').Fixed, "-E selects a regex");
   Check (Applied ('n').Numbered, "-n numbers records");
   Check (Applied ('v').Invert, "-v inverts");
   Check (Applied ('c').Count_Only, "-c counts");
   Check (Applied ('q').Quiet, "-q is quiet");
   Check (Applied ('l').List_Files, "-l lists inputs");
   Check (Applied ('x').Whole, "-x matches whole records");
   Check (Applied ('h').Names = Front.Never, "-h hides names");
   Check (Applied ('H').Names = Front.Always, "-H shows names");
   Check (Applied ('z').Delimiter = ASCII.NUL, "-z frames on NUL");

   --  Arguments
   Check
     (Front.Classify ("--", False) = Front.End_Marker, """--"" ends options");
   Check
     (Front.Classify ("--", True) = Front.Operand,
      """--"" after -- is a path");
   Check
     (Front.Classify ("-", False) = Front.Operand, """-"" is standard input");
   Check
     (Front.Classify ("", False) = Front.Operand,
      "the empty pattern is an operand");
   Check (Front.Classify ("-nH", False) = Front.Cluster, "-nH is a cluster");
   Check
     (Front.Classify ("--help", False) = Front.Long_Option,
      "--help is a long option");
   Check
     (Front.Classify ("--help", True) = Front.Operand,
      "--help after -- is a path");
   Check
     (Front.Classify ("a.*b", False) = Front.Operand,
      "a pattern is an operand");
   Check (not Front.Has_Inline_Value ("-e", 2), "-e alone carries no value");
   Check (Front.Has_Inline_Value ("-eab", 2), "-eab carries one");
   Check (Front.Inline_Value ("-eab", 2) = "ab", "and the value is the rest");

   --  The pattern is taken once
   declare
      State : Front.Pattern_State;
      Taken : Front.Pattern_Result;
   begin
      Check (not State.Present, "no pattern to begin with");
      Front.Set_Pattern (State, "first", Taken);
      Check (Taken = Front.Taken, "the first pattern is taken");
      Check (Front.Unbounded.To_String (State.Text) = "first", "and kept");
      Front.Set_Pattern (State, "second", Taken);
      Check (Taken = Front.Already_Set, "the second is refused");
      Check
        (Front.Unbounded.To_String (State.Text) = "first",
         "and does not replace the first");
   end;

   --  Selection
   declare
      Plain   : Front.Settings;
      Inverse : constant Front.Settings := Applied ('v');
      Silent  : constant Front.Settings := Applied ('q');
      Listing : constant Front.Settings := Applied ('l');
      Tally   : constant Front.Settings := Applied ('c');
   begin
      Check
        (Front.Decide (Plain, True) = Front.Emit_Record, "a match is written");
      Check (Front.Decide (Plain, False) = Front.Ignore, "a miss is not");
      Check
        (Front.Decide (Inverse, False) = Front.Emit_Record,
         "-v writes the misses");
      Check
        (Front.Decide (Inverse, True) = Front.Ignore,
         "-v ignores the matches");
      Check
        (Front.Decide (Silent, True) = Front.Halt_Quiet,
         "-q stops at the first match");
      Check
        (Front.Decide (Listing, True) = Front.Emit_Input_Name,
         "-l names the input");
      Check (Front.Decide (Tally, True) = Front.Tally_Only, "-c only counts");
      Check (Front.Halts (Front.Decide (Silent, True)), "-q halts");
      Check
        (Front.Halts (Front.Decide (Listing, True)), "-l halts on an input");
      Check
        (not Front.Halts (Front.Decide (Plain, True)),
         "a written record does not");
      Check
        (Front.Selects (Front.Decide (Tally, True)),
         "a counted record is selected");
      Check
        (not Front.Selects (Front.Decide (Plain, False)),
         "a miss is not selected");
      Check (Front.Reports_Count (Tally), "-c reports a count");
      Check (not Front.Reports_Count (Plain), "without -c there is none");
   end;

   --  Names and prefixes
   declare
      Auto   : Front.Settings;
      Shown  : constant Front.Settings := Applied ('H');
      Hidden : constant Front.Settings := Applied ('h');
      Number : constant Front.Settings := Applied ('n');
   begin
      Check
        (not Front.Show_Prefix (Auto, 1), "one named input needs no prefix");
      Check (Front.Show_Prefix (Auto, 2), "two do");
      Check (Front.Show_Prefix (Shown, 1), "-H names one anyway");
      Check (not Front.Show_Prefix (Hidden, 9), "-h names none");
      Check
        (Front.Match_Prefix (Auto, False, "f", "7") = "",
         "no name, no number, no prefix");
      Check
        (Front.Match_Prefix (Auto, True, "f", "7") = "f:", "the name alone");
      Check
        (Front.Match_Prefix (Number, False, "f", "7") = "7:",
         "the number alone");
      Check
        (Front.Match_Prefix (Number, True, "f", "7") = "f:7:",
         "name then number");
      Check (Front.Name_Prefix (True, "f") = "f:", "the count line's name");
      Check (Front.Name_Prefix (False, "f") = "", "or none");
      Check
        (Front.Count_Line (True, "f", "3") = "f:3" & ASCII.LF,
         "the count line");
      Check
        (Front.Count_Line (False, "f", "0") = "0" & ASCII.LF,
         "a zero count is reported");
      --  An image is the tail of a buffer, not a one-based string; passing a
      --  literal alone would never exercise that.
      declare
         Buffer : constant String (1 .. 10) := "0000000042";
      begin
         Check
           (Front.Match_Prefix (Number, True, "f", Buffer (9 .. 10)) = "f:42:",
            "an image that does not start at one");
         Check
           (Front.Count_Line (True, "f", Buffer (9 .. 10)) = "f:42" & ASCII.LF,
            "and the same for a count");
      end;
   end;

   --  Literal patterns
   Check
     (Front.Escape_Literal ("") = "", "an empty literal escapes to nothing");
   Check (Front.Escape_Literal ("abc") = "abc", "plain bytes pass through");
   Check (Front.Escape_Literal ("a.b") = "a\.b", "a metacharacter is escaped");
   Check (Front.Escape_Literal ("\") = "\\", "so is a backslash");
   Check
     (Front.Escape_Literal ("\.^$|?*+()[]{}") = "\\\.\^\$\|\?\*\+\(\)\[\]\{\}",
      "every metacharacter, and only those");
   Check
     (Front.Escape_Literal ("a-b_c:d,e/f") = "a-b_c:d,e/f",
      "punctuation the engine does not read is left alone");

   --  Exit status
   Check (Front.Exit_Code (False, True) = 0, "something selected");
   Check (Front.Exit_Code (False, False) = 1, "nothing selected");
   Check (Front.Exit_Code (True, False) = 2, "an error");
   Check (Front.Exit_Code (True, True) = 2, "an error outranks a selection");

   Report;
end Test_Front;
