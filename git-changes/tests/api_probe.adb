with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Git_Changes;
with Git_Changes.Contents;
with Git_Changes.Repositories;

procedure Api_Probe is
   use Ada.Command_Line;
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Git_Changes;

   Repo    : Repository;
   Changes : Change_Set;
   Error   : Error_Info;
   Options : Capture_Options := Default_Options;

   procedure Fail (Where : String) is
   begin
      Put_Line (Standard_Error, Where & ": " & Error_Code'Image (Code (Error))
                & ": " & Detail (Error));
      Set_Exit_Status (Failure);
   end Fail;

   procedure Show_Content (File : Positive; Which : Side) is
      Content : Unbounded_String;
   begin
      if Content_Available (Changes, File, Which) then
         Git_Changes.Contents.Load (Changes, File, Which, Content, Error);
         if not Git_Changes.Success (Error) then
            Fail ("content");
            return;
         end if;
         Put (" " & (if Which = Old_Side then "old=" else "new=")
              & Length (Content)'Image);
      end if;
   end Show_Content;
begin
   if Argument_Count not in 1 .. 2 then
      Put_Line (Standard_Error, "usage: api_probe REPOSITORY [PATHSPEC]");
      Set_Exit_Status (Failure);
      return;
   end if;
   Git_Changes.Repositories.Open (Argument (1), Repo, Error);
   if not Git_Changes.Success (Error) then
      Fail ("open");
      return;
   end if;
   Options.Detect_Copies := True;
   if Argument_Count = 2 then
      Capture
        (Repo, Tree_To_Worktree ("HEAD"),
         Pathspecs => [1 => To_Unbounded_String (Argument (2))],
         Options => Options, Changes => Changes, Error => Error);
   else
      Capture
        (Repo, Tree_To_Worktree ("HEAD"), Options, Changes, Error);
   end if;
   if not Git_Changes.Success (Error) then
      Fail ("capture");
      return;
   end if;
   Put_Line ("count=" & File_Count (Changes)'Image);
   for File in 1 .. File_Count (Changes) loop
      Put (Change_Kind'Image (File_Kind (Changes, File)));
      if Has_Path (Changes, File, Old_Side) then
         Put (" old-path=" & Path (Changes, File, Old_Side));
      end if;
      if Has_Path (Changes, File, New_Side) then
         Put (" new-path=" & Path (Changes, File, New_Side));
      end if;
      Show_Content (File, Old_Side);
      Show_Content (File, New_Side);
      New_Line;
   end loop;
end Api_Probe;
