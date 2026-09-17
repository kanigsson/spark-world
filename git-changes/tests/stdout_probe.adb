--  Does a query leave the caller's standard output alone?
--
--  The library captures a git command's output for itself. Doing that by
--  pointing THIS process's standard output at the capture file -- which is
--  what GNAT.OS_Lib's Output_File spawn does -- is invisible in a
--  single-threaded program and destructive in every other one: whatever
--  another task writes while a query runs disappears into the capture file.
--  A terminal client loses the frame it was drawing, and what was on screen
--  stays there.
--
--  So: a writer task prints numbered lines to standard output while the main
--  task runs queries. The harness counts them. Every line must arrive.

with Ada.Command_Line;
with Ada.Text_IO;
with Git_Changes;
with Git_Changes.Repositories;
with Git_Changes.Revisions;
with Ada.Strings.Unbounded;

procedure Stdout_Probe is
   use Ada.Command_Line;
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use Git_Changes;

   Lines : constant := 2_000;

   task Writer;

   task body Writer is
   begin
      for I in 1 .. Lines loop
         Put_Line ("mark" & I'Image);
         Flush;
      end loop;
   end Writer;

   Repo    : Repository;
   Changes : Change_Set;
   Error   : Error_Info;
   Options : constant Capture_Options := Default_Options;
   Head    : Unbounded_String;
begin
   if Argument_Count /= 1 then
      Put_Line (Standard_Error, "usage: stdout_probe <repository>");
      Set_Exit_Status (Failure);
      return;
   end if;
   Git_Changes.Repositories.Open (Argument (1), Repo, Error);
   if not Git_Changes.Success (Error) then
      Put_Line (Standard_Error, "open: " & Detail (Error));
      Set_Exit_Status (Failure);
      return;
   end if;
   --  Enough queries to keep a capture open for most of the writer's run.
   for Pass in 1 .. 20 loop
      Git_Changes.Revisions.Resolve (Repo, "HEAD", Head, Error);
      exit when not Git_Changes.Success (Error);
      Git_Changes.Capture
        (Repo, Tree_To_Worktree (To_String (Head)), Options, Changes, Error);
      exit when not Git_Changes.Success (Error);
   end loop;
   if not Git_Changes.Success (Error) then
      Put_Line (Standard_Error, "query: " & Detail (Error));
      Set_Exit_Status (Failure);
   end if;
end Stdout_Probe;
