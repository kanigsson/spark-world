with Ada.Directories;
with Ada.Strings.Unbounded;
with GNAT.OS_Lib;
with Git_Changes.Backends;

package body Git_Changes.Repositories is
   use Ada.Strings.Unbounded;

   function Available return Boolean is
      Found : GNAT.OS_Lib.String_Access :=
        GNAT.OS_Lib.Locate_Exec_On_Path ("git");
      use type GNAT.OS_Lib.String_Access;
   begin
      if Found = null then
         return False;
      end if;
      GNAT.OS_Lib.Free (Found);
      return True;
   end Available;

   procedure Query
     (Path      : String;
      Argument  : String;
      Operation : String;
      Output    : out Unbounded_String;
      Error     : out Error_Info) is
   begin
      Git_Changes.Backends.Run_Git
        (Path,
         [1 => To_Unbounded_String ("rev-parse"),
          2 => To_Unbounded_String (Argument)],
         1024 * 1024,
         Operation,
         Output,
         Error);
   end Query;

   procedure Open
     (Path : String; Item : out Repository; Error : out Error_Info)
   is
      Output        : Unbounded_String;
      Bare_Output   : Unbounded_String;
      Git_Output    : Unbounded_String;
      Format_Output : Unbounded_String;
      Local_Error   : Error_Info;
      Bare          : Boolean;
   begin
      Item := (others => <>);
      Error := (others => <>);
      Query
        (Path,
         "--is-bare-repository",
         "discover repository",
         Bare_Output,
         Local_Error);
      if not Success (Local_Error) then
         Set_Error
           (Error,
            Invalid_Repository,
            "discover repository",
            Detail (Local_Error),
            Exit_Status (Local_Error));
         return;
      end if;
      Bare :=
        Git_Changes.Backends.Trim_Line_End (To_String (Bare_Output)) = "true";

      Query
        (Path,
         "--absolute-git-dir",
         "resolve git directory",
         Git_Output,
         Error);
      if not Success (Error) then
         return;
      end if;
      Query
        (Path,
         "--show-object-format",
         "resolve object format",
         Format_Output,
         Error);
      if not Success (Error) then
         return;
      end if;

      if Bare then
         begin
            Output := To_Unbounded_String (Ada.Directories.Full_Name (Path));
         exception
            when others =>
               Set_Error
                 (Error,
                  Invalid_Repository,
                  "discover repository",
                  "invalid path");
               return;
         end;
      else
         Query (Path, "--show-toplevel", "resolve worktree", Output, Error);
         if not Success (Error) then
            return;
         end if;
      end if;

      Item :=
        (Opened             => True,
         Root               =>
           To_Unbounded_String
             (Git_Changes.Backends.Trim_Line_End (To_String (Output))),
         Git_Dir            =>
           To_Unbounded_String
             (Git_Changes.Backends.Trim_Line_End (To_String (Git_Output))),
         Object_Format_Name =>
           To_Unbounded_String
             (Git_Changes.Backends.Trim_Line_End (To_String (Format_Output))),
         Bare               => Bare);
   end Open;

end Git_Changes.Repositories;
