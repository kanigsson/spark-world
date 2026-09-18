--  The diagnostic and record-output channels of spark-grep and spark-rg.
--
--  This is a SPARK specification over an ordinary Ada body, the shape the
--  repository already uses at a syscall boundary: naming the standard error
--  file takes a unit out of SPARK, and so does writing bytes through a stream
--  attribute, but a caller only needs to know which state each operation
--  touches. Hiding both behind this spec is what lets the code that decides
--  what to report be SPARK.
--
--  The program name is state, set once at start-up. It was the only
--  difference between the two programs' error reporting.

package Grep_Diag
  with SPARK_Mode => On, Abstract_State => Channel, Initializes => Channel
is

   procedure Set_Program (Name : String)
   with Global => (In_Out => Channel), Always_Terminates;

   function Program return String
   with Global => Channel;

   --  An error: reported, recorded, and the exit status set. Recording it is
   --  what makes the status survive later output.
   --
   --  The exit status is part of this state rather than named separately: the
   --  pinned runtime's Ada.Command_Line carries no abstract state to name,
   --  unlike the development one, and a contract that depends on which
   --  runtime is installed is worse than one that keeps the status here.
   procedure Error (Message : String)
   with Global => (In_Out => Channel), Always_Terminates;

   --  A condition worth reporting that does not fail the run: an unreadable
   --  subtree does not end a recursive search.
   procedure Warn (Message : String)
   with Global => (In_Out => Channel), Always_Terminates;

   --  Diagnostics composed elsewhere, already prefixed and terminated,
   --  written through as they are. A parallel search reports a file's errors
   --  when its results are written rather than when it was scanned.
   procedure Put_Error (Text : String)
   with Global => (In_Out => Channel), Always_Terminates;

   --  Record the failure of a diagnostic that was already written.
   procedure Note_Error
   with Global => (In_Out => Channel), Always_Terminates;

   function Had_Error return Boolean
   with Global => Channel;

   --  Records, as bytes: no line-terminator translation, since a record ends
   --  in the delimiter the caller chose and may contain anything else.
   procedure Write (Value : String)
   with Global => (In_Out => Channel), Always_Terminates;

end Grep_Diag;
