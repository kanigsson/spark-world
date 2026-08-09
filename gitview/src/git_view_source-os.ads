--  Git_View_Source.OS — the subprocess syscall core, as small as it gets.
--
--  The parent draws the proved/trusted seam at its spec; this private child
--  narrows the trusted side further: only the mechanics that genuinely need
--  the OS live behind it — locate the executable, spawn it with its output
--  captured into a temporary file, read that file back into a document. The
--  BODY is SPARK_Mode => Off by design; everything that can be decided in
--  proved code (which arguments to pass, what an exit code means, what to
--  show on failure) stays in the parent's proved body.
--
--  Arguments cross the boundary as bounded records rather than heap strings,
--  so the proved side never touches an access-to-string.

private package Git_View_Source.OS with SPARK_Mode => On is

   Max_Argument_Length : constant := 255;

   subtype Argument_Length is Natural range 0 .. Max_Argument_Length;

   type Argument is record
      Len  : Argument_Length := 0;
      Text : String (1 .. Max_Argument_Length) := (others => ' ');
   end record;

   type Argument_Vector is array (Positive range <>) of Argument;

   --  True when a git executable can be found on PATH.
   function Find_Git return Boolean with Global => null;

   --  Run git with Args, capturing its stdout in a temporary file, and load
   --  that file into a fresh document. Doc is null when the subprocess could
   --  not be run or its output could not be read back; Code is git's exit
   --  status (-1 when it never ran). Err_To_Out folds the subprocess's
   --  stderr into the captured output — wanted while the alternate screen is
   --  up, where stray terminal writes would scribble over the interface.
   procedure Capture
     (Args       : Argument_Vector;
      Err_To_Out : Boolean;
      Doc        : out Tui.Text.Doc_Ref;
      Code       : out Integer)
   with Global => null;

end Git_View_Source.OS;
