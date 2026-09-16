with Ada.Containers.Vectors;
with Spark_Re;
--  Gitignore rule sets for the recursive walker. Ordinary Ada, deliberately
--  outside the SPARK proof boundary: it reads files and uses dynamic storage.
--
--  Matching itself is delegated to the proved regex engine. Every glob is
--  translated into an equivalent anchored pattern over the whole candidate
--  path, so no second matching implementation exists to disagree with the
--  first. The translation is the only part that has to be trusted.

package Gitignore is

   --  Glob rules are short and expand to small automata, so they use a much
   --  smaller storage budget than the default instance. A compiled program is
   --  dominated by a per-instruction byte set and a rule set holds one program
   --  per rule, which makes the default budget far too large to hold per rule.
   --  This instantiation is not covered by the library proof run, as is true
   --  of all command line code.
   package Glob_Re is new Spark_Re (Max_Nodes => 128, Max_States => 512);

   type Decision is (No_Match, Matched, Negated);
   --  The verdict of a rule set: no rule applied, the last applicable rule
   --  selected the path, or the last applicable rule was a negation.

   type Rule_Set is private;

   function Is_Empty (Self : Rule_Set) return Boolean;

   procedure Add
     (Self    : in out Rule_Set;
      Pattern : String;
      Status  : out Glob_Re.Compile_Status);
   --  Append one gitignore-syntax rule, including a leading "!" negation and
   --  a trailing "/" directory restriction. Blank and comment lines are
   --  accepted and add nothing. A rule that exceeds the glob storage budget
   --  reports its status and is not added.

   procedure Load
     (Self : in out Rule_Set;
      Path : String;
      Warn : not null access procedure (Message : String));
   --  Append every rule of one ignore file, in file order. Rules that cannot
   --  be compiled are reported through Warn and skipped, so an exotic pattern
   --  costs precision rather than the whole traversal.

   function Match
     (Self : Rule_Set; Rel_Path : String; Is_Dir : Boolean) return Decision;
   --  Rel_Path is relative to the directory holding the ignore file and uses
   --  '/' separators, with no leading or trailing separator. The last rule
   --  that applies decides, and directory-only rules apply only when Is_Dir.

   function To_Regex (Glob : String) return String;
   --  The translation of one glob body, with negation and the directory
   --  marker already removed. Exposed so that it can be tested directly.

private

   Max_Literal : constant := 32;
   --  Literal runs longer than this are kept truncated. A shorter necessary
   --  condition rejects fewer paths but never rejects a path the rule
   --  accepts, so the bound costs speed rather than precision.

   type Literal is record
      Text : String (1 .. Max_Literal) := [others => ' '];
      Len  : Natural range 0 .. Max_Literal := 0;
   end record;
   --  A run of bytes every accepted path must carry, in a fixed buffer so
   --  that testing it allocates nothing. An empty run constrains nothing.

   type Screen is record
      Head     : Literal;
      --  Leading bytes required of an accepted path, empty unless the glob
      --  is tied to the directory holding the ignore file.
      Tail     : Literal;
      --  Trailing bytes required of an accepted path, since every
      --  translation ends the pattern at the end of the path.
      Negated  : Boolean := False;
      Dir_Only : Boolean := False;
   end record;

   package Screen_Vectors is new Ada.Containers.Vectors (Positive, Screen);
   package Code_Vectors is new
     Ada.Containers.Vectors (Positive, Glob_Re.Program, Glob_Re."=");
   package Index_Vectors is new Ada.Containers.Vectors (Positive, Positive);

   type Byte_Screen is array (Character, Character) of Boolean with Pack;
   --  Indexed by the last two bytes a rule requires. One byte is not enough
   --  on a real ignore file: a dozen suffix rules between them cover most of
   --  the alphabet, and every path then reaches the rules anyway.

   type Rule_Set is record
      Screens    : Screen_Vectors.Vector;
      Codes      : Code_Vectors.Vector;
      Open       : Index_Vectors.Vector;
      --  Rules whose required trailing run is shorter than the screen, in
      --  file order. They are the only ones that can apply to a path the
      --  screen rejects.
      Tail_Pairs : Byte_Screen := [others => [others => False]];
      --  A path ending in an unrecorded pair is beyond every screened rule,
      --  so a whole ignore file is usually dismissed on one lookup.
   end record;
   --  One rule per index in both vectors. They are kept apart because a
   --  compiled program is thousands of times the size of the bytes that
   --  decide whether it is worth running: walking the screens alone keeps
   --  the traversal's inner loop inside a few kilobytes, while walking
   --  whole rules would stream the automata past the processor once per
   --  entry of the tree.

end Gitignore;
