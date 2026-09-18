--  The assertion counter every test main in this repository had written.
--
--  There were twenty-one copies in two dialects. One counted failures, printed
--  a line per check and took its exit status from the count; the other raised
--  Program_Error at the first failure. They also disagreed on whether a passing
--  check prints anything and on the wording of the closing line, which is why
--  this package has three knobs rather than the one the difference looked like
--  from a distance.
--
--  Ordinary Ada on purpose, and it lives under tools/ for the same reason: it
--  is scaffolding that no program ships, nothing proves it, and a contract here
--  would state something about the test harness rather than about any library
--  under test. The code it checks is where the proofs are.

package Test_Checks is

   --  Call once, first, from a test main. Suite names the run in the closing
   --  line. Echo_Passes prints a line per passing check, which is what the
   --  behavioural suites want because the list of labels is what they are for.
   --  Stop_On_Fail raises at the first failure instead of carrying on, which
   --  suits a suite whose later cases assume the earlier ones held.
   procedure Start
     (Suite        : String;
      Echo_Passes  : Boolean := False;
      Stop_On_Fail : Boolean := False);

   procedure Check (Condition : Boolean; Message : String);

   --  For a suite whose cases are positional rather than named: the message is
   --  the check's own number, which is what those mains reported already.
   procedure Check (Condition : Boolean);

   --  The closing line and the exit status; the last statement of the main.
   --  A run that checked nothing at all fails, because a suite that silently
   --  stopped calling Check looks exactly like a suite that passed.
   procedure Report;

   function Performed return Natural;
   function Failures return Natural;

end Test_Checks;
