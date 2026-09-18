with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Test_Checks is

   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   Suite_Name    : Unbounded_String := To_Unbounded_String ("tests");
   Echo          : Boolean := False;
   Stop          : Boolean := False;
   Check_Count   : Natural := 0;
   Failure_Count : Natural := 0;

   -----------
   -- Start --
   -----------

   procedure Start
     (Suite        : String;
      Echo_Passes  : Boolean := False;
      Stop_On_Fail : Boolean := False) is
   begin
      Suite_Name := To_Unbounded_String (Suite);
      Echo := Echo_Passes;
      Stop := Stop_On_Fail;
      Check_Count := 0;
      Failure_Count := 0;
   end Start;

   -----------
   -- Check --
   -----------

   procedure Check (Condition : Boolean; Message : String) is
   begin
      Check_Count := Check_Count + 1;
      if Condition then
         if Echo then
            Put_Line ("  ok   : " & Message);
         end if;
      else
         Failure_Count := Failure_Count + 1;
         Put_Line ("  FAIL : " & Message);
         if Stop then
            --  The message, not just the count: a suite that stops at the
            --  first failure does so because what follows would report
            --  consequences rather than causes.
            raise Program_Error with Message;
         end if;
      end if;
   end Check;

   procedure Check (Condition : Boolean) is
   begin
      Check (Condition, "check" & Natural'Image (Check_Count + 1));
   end Check;

   ------------
   -- Report --
   ------------

   procedure Report is
      Name : constant String := To_String (Suite_Name);
   begin
      --  A suite that echoed every check has just printed a wall of them; the
      --  blank line is what separates the run from its verdict.
      if Echo then
         New_Line;
      end if;
      if Check_Count = 0 then
         Put_Line (Name & ": no checks ran");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      elsif Failure_Count = 0 then
         Put_Line (Name & ":" & Check_Count'Image & " checks passed");
      else
         Put_Line
           (Name
            & ":"
            & Failure_Count'Image
            & " of"
            & Check_Count'Image
            & " checks FAILED");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end Report;

   function Performed return Natural
   is (Check_Count);
   function Failures return Natural
   is (Failure_Count);

end Test_Checks;
