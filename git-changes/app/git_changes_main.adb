with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Git_Changes;
with Git_Changes.Repositories;

procedure Git_Changes_Main is
   use Ada.Command_Line;
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Git_Changes;

   function Escaped (Value : String) return String is
      Result : Unbounded_String;
      Hex    : constant array (Natural range 0 .. 15) of Character :=
        "0123456789ABCDEF";
      Code   : Natural;
   begin
      for C of Value loop
         Code := Character'Pos (C);
         if C = '\' then
            Append (Result, "\\");
         else
            case C is
               when Character'Val (9) => Append (Result, "\t");
               when Character'Val (10) => Append (Result, "\n");
               when Character'Val (13) => Append (Result, "\r");
               when ' ' .. '~' => Append (Result, C);
               when others =>
                  Append (Result, "\x");
                  Append (Result, Hex (Code / 16));
                  Append (Result, Hex (Code mod 16));
            end case;
         end if;
      end loop;
      return To_String (Result);
   end Escaped;

   function Kind_Code (Value : Change_Kind) return String is
     (case Value is
         when Added => "A",
         when Deleted => "D",
         when Modified => "M",
         when Renamed => "R",
         when Copied => "C",
         when Type_Changed => "T",
         when Unmerged => "U",
         when Broken_Pair => "B",
         when Unknown_Change => "X");

   procedure Usage is
   begin
      Put_Line (Standard_Error,
        "usage: git-changes [REPOSITORY [tree-tree OLD NEW|tree-index TREE|"
        & "index-worktree|tree-worktree TREE]]");
   end Usage;

   Repo       : Repository;
   Compared   : Comparison := Tree_To_Worktree ("HEAD");
   Changes    : Change_Set;
   Error      : Error_Info;
   Repo_Path  : Unbounded_String := To_Unbounded_String (".");
begin
   if Argument_Count >= 1 then
      Repo_Path := To_Unbounded_String (Argument (1));
   end if;
   if Argument_Count >= 2 then
      if Argument (2) = "tree-tree" and then Argument_Count = 4 then
         Compared := Tree_To_Tree (Argument (3), Argument (4));
      elsif Argument (2) = "tree-index" and then Argument_Count = 3 then
         Compared := Tree_To_Index (Argument (3));
      elsif Argument (2) = "index-worktree" and then Argument_Count = 2 then
         Compared := Index_To_Worktree;
      elsif Argument (2) = "tree-worktree" and then Argument_Count = 3 then
         Compared := Tree_To_Worktree (Argument (3));
      else
         Usage;
         Set_Exit_Status (Failure);
         return;
      end if;
   end if;

   Git_Changes.Repositories.Open (To_String (Repo_Path), Repo, Error);
   if not Git_Changes.Success (Error) then
      Put_Line
        (Standard_Error, Error_Code'Image (Code (Error)) & ": " & Detail (Error));
      Set_Exit_Status (Failure);
      return;
   end if;

   Capture (Repo, Compared, Changes => Changes, Error => Error);
   if not Git_Changes.Success (Error) then
      Put_Line
        (Standard_Error, Error_Code'Image (Code (Error)) & " during "
         & Operation (Error) & ": " & Detail (Error));
      Set_Exit_Status (Failure);
      return;
   end if;

   Put_Line ("repository " & Escaped (Root_Path (Repo)));
   Put_Line
     ("comparison " & Comparison_Kind'Image (Comparison_Used (Changes))
      & " old=" & Resolved_Identity (Old_Endpoint (Changes))
      & " new=" & Resolved_Identity (New_Endpoint (Changes)));
   Put_Line
     ("files" & File_Count (Changes)'Image
      & (if Is_Stale (Changes) then " stale" else " fresh"));

   for File in 1 .. File_Count (Changes) loop
      Put (Kind_Code (File_Kind (Changes, File)) & " ");
      if Has_Path (Changes, File, Old_Side) then
         Put (Escaped (Path (Changes, File, Old_Side)));
      else
         Put ("-");
      end if;
      Put (" -> ");
      if Has_Path (Changes, File, New_Side) then
         Put (Escaped (Path (Changes, File, New_Side)));
      else
         Put ("-");
      end if;
      Put (" id=" & File_Id (Changes, File));
      Put (" old-mode="
           & (if Has_Mode (Changes, File, Old_Side)
              then Mode (Changes, File, Old_Side) else "-"));
      Put (" new-mode="
           & (if Has_Mode (Changes, File, New_Side)
              then Mode (Changes, File, New_Side) else "-"));
      Put (" old-object="
           & (if Has_Object_Id (Changes, File, Old_Side)
              then Object_Id (Changes, File, Old_Side) else "-"));
      Put (" new-object="
           & (if Has_Object_Id (Changes, File, New_Side)
              then Object_Id (Changes, File, New_Side) else "-"));
      if Has_Similarity (Changes, File) then
         Put (" similarity=" & Similarity (Changes, File)'Image);
      end if;
      if Is_Binary (Changes, File) then Put (" binary"); end if;
      if Is_Submodule (Changes, File) then Put (" submodule"); end if;
      New_Line;
      for Number in 1 .. Span_Count (Changes, File) loop
         declare
            S : constant Changed_Span := Span (Changes, File, Number);
         begin
            Put_Line
              ("  @@ -" & S.Old_First'Image & "," & S.Old_Count'Image
               & " +" & S.New_First'Image & "," & S.New_Count'Image
               & " id=" & Span_Id (Changes, File, Number));
         end;
      end loop;
      if File_Diagnostic (Changes, File)'Length > 0 then
         Put_Line ("  diagnostic: " & File_Diagnostic (Changes, File));
      end if;
   end loop;
end Git_Changes_Main;
