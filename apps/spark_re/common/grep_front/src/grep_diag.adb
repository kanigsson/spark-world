with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;

--  Outside the proof boundary: the standard error and standard output files,
--  and the stream attribute that writes bytes without translating them.

package body Grep_Diag
  with SPARK_Mode => Off
is
   package IO renames Ada.Text_IO;

   Prefix : Unbounded_String;
   Failed : Boolean := False;

   -----------------
   -- Set_Program --
   -----------------

   procedure Set_Program (Name : String) is
   begin
      Prefix := To_Unbounded_String (Name);
   end Set_Program;

   -------------
   -- Program --
   -------------

   function Program return String
   is (To_String (Prefix));

   -----------
   -- Error --
   -----------

   procedure Error (Message : String) is
   begin
      IO.Put_Line (IO.Standard_Error, Program & ": " & Message);
      Note_Error;
   end Error;

   ----------
   -- Warn --
   ----------

   procedure Warn (Message : String) is
   begin
      IO.Put_Line (IO.Standard_Error, Program & ": " & Message);
   end Warn;

   ---------------
   -- Put_Error --
   ---------------

   procedure Put_Error (Text : String) is
   begin
      IO.Put (IO.Standard_Error, Text);
   end Put_Error;

   ----------------
   -- Note_Error --
   ----------------

   procedure Note_Error is
   begin
      Failed := True;
      Ada.Command_Line.Set_Exit_Status (2);
   end Note_Error;

   ---------------
   -- Had_Error --
   ---------------

   function Had_Error return Boolean
   is (Failed);

   -----------
   -- Write --
   -----------

   procedure Write (Value : String) is
   begin
      String'Write (IO.Text_Streams.Stream (IO.Standard_Output), Value);
   end Write;

end Grep_Diag;
