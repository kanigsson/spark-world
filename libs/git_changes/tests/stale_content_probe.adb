with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Git_Changes;
with Git_Changes.Contents;
with Git_Changes.Repositories;

procedure Stale_Content_Probe is
   use Ada.Command_Line;
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Git_Changes;

   Repo    : Repository;
   Changes : Change_Set;
   Error   : Error_Info;
   Content : Unbounded_String;
   Target  : Natural := 0;
   Mutated : File_Type;
begin
   if Argument_Count /= 2 then
      Set_Exit_Status (Failure);
      return;
   end if;
   Git_Changes.Repositories.Open (Argument (1), Repo, Error);
   if not Git_Changes.Success (Error) then
      Set_Exit_Status (Failure);
      return;
   end if;
   Capture
     (Repo, Tree_To_Worktree ("HEAD"), Changes => Changes, Error => Error);
   if not Git_Changes.Success (Error) then
      Set_Exit_Status (Failure);
      return;
   end if;
   for File in 1 .. File_Count (Changes) loop
      if Has_Path (Changes, File, New_Side)
        and then Path (Changes, File, New_Side) = Argument (2)
      then
         Target := File;
      end if;
   end loop;
   if Target = 0 or else not Content_Available (Changes, Target, New_Side) then
      Set_Exit_Status (Failure);
      return;
   end if;

   Create (Mutated, Out_File, Root_Path (Repo) & "/" & Argument (2));
   Put_Line (Mutated, "mutated after capture");
   Close (Mutated);
   Git_Changes.Contents.Load (Changes, Target, New_Side, Content, Error);
   Put_Line (Error_Code'Image (Code (Error)));
   if Code (Error) /= Content_Changed then
      Set_Exit_Status (Failure);
   end if;
end Stale_Content_Probe;
