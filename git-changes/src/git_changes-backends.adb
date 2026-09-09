with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with GNAT.OS_Lib;
with GNAT.SHA1;
with GNAT.SHA256;

package body Git_Changes.Backends is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Size;

   procedure Read_File
     (Name              : String;
      Max_Content_Bytes : Positive;
      Content           : out Unbounded_String;
      Error             : out Error_Info)
   is
      use Ada.Streams;
      package IO renames Ada.Streams.Stream_IO;
      use type IO.Count;
      File : IO.File_Type;
   begin
      Content := Null_Unbounded_String;
      Error := (others => <>);
      if not Ada.Directories.Exists (Name) then
         Set_Error (Error, Filesystem_Error, "read", "file does not exist: " & Name);
         return;
      end if;
      if Ada.Directories.Size (Name) > Ada.Directories.File_Size (Max_Content_Bytes)
      then
         Set_Error
           (Error, Resource_Limit, "read",
            "content exceeds configured limit: " & Name);
         return;
      end if;

      IO.Open (File, IO.In_File, Name);
      declare
         Current_Size : constant IO.Count := IO.Size (File);
         --  Read in chunks and accumulate on the heap: holding the whole
         --  file in stack objects overflows the caller's task stack on
         --  outputs and sources of a few megabytes.
         Chunk : Stream_Element_Array (1 .. 64 * 1024);
         Last  : Stream_Element_Offset;
         Total : IO.Count := 0;
      begin
         if Current_Size > IO.Count (Max_Content_Bytes) then
            IO.Close (File);
            Set_Error
              (Error, Resource_Limit, "read",
               "content grew beyond configured limit: " & Name);
            return;
         end if;
         loop
            IO.Read (File, Chunk, Last);
            exit when Last < Chunk'First;
            declare
               Text : String (1 .. Natural (Last));
            begin
               for J in Text'Range loop
                  Text (J) := Character'Val (Chunk (Stream_Element_Offset (J)));
               end loop;
               Append (Content, Text);
            end;
            Total := Total + IO.Count (Last);
            exit when Last < Chunk'Last;
         end loop;
         if Total < Current_Size then
            IO.Close (File);
            Content := Null_Unbounded_String;
            Set_Error (Error, Filesystem_Error, "read", "short read: " & Name);
            return;
         end if;
      end;
      IO.Close (File);
   exception
      when others =>
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         Set_Error (Error, Filesystem_Error, "read", "cannot read: " & Name);
   end Read_File;

   --  Capture files live in the temporary directory, never in the working
   --  tree: a repository under inspection must not gain untracked files
   --  just because it was queried.
   Capture_Serial : Natural := 0;
   procedure Create_Capture
     (FD : out GNAT.OS_Lib.File_Descriptor; Name : out Unbounded_String)
   is
      use GNAT.OS_Lib;
      Dir : constant String :=
        (if Ada.Environment_Variables.Exists ("TMPDIR")
         then Ada.Environment_Variables.Value ("TMPDIR") else "/tmp");
      Pid : constant Integer := Pid_To_Integer (Current_Process_Id);
   begin
      for Attempt in 1 .. 1_000 loop
         Capture_Serial := Capture_Serial + 1;
         declare
            Candidate : constant String :=
              Dir & "/git_changes-"
              & Ada.Strings.Fixed.Trim (Integer'Image (Pid), Ada.Strings.Both)
              & "-"
              & Ada.Strings.Fixed.Trim
                  (Natural'Image (Capture_Serial), Ada.Strings.Both)
              & ".tmp";
         begin
            --  Exclusive creation: a name already taken is simply skipped.
            FD := Create_New_File (Candidate, Binary);
            if FD /= Invalid_FD then
               Name := To_Unbounded_String (Candidate);
               return;
            end if;
         end;
      end loop;
      FD := Invalid_FD;
      Name := Null_Unbounded_String;
   end Create_Capture;

   procedure Run_Git
     (Working_Directory : String;
      Arguments         : Argument_Array;
      Max_Output_Bytes  : Positive;
      Operation         : String;
      Output            : out Unbounded_String;
      Error             : out Error_Info)
   is
      use GNAT.OS_Lib;
      Prefix_Count : constant Positive := 7;
      Args : Argument_List (1 .. Prefix_Count + Arguments'Length);
      FD   : File_Descriptor;
      Temp : Unbounded_String;
      Git  : GNAT.OS_Lib.String_Access := Locate_Exec_On_Path ("git");
      Spawned : Boolean;
      Status  : Integer := -1;
      Read_Error : Error_Info;
      Deleted : Boolean;

      procedure Release is
      begin
         for Arg of Args loop
            Free (Arg);
         end loop;
         Free (Git);
      end Release;
   begin
      Output := Null_Unbounded_String;
      Error := (others => <>);
      if Git = null then
         Set_Error (Error, Git_Command_Failed, Operation, "git executable not found", -1);
         return;
      end if;

      Args (1) := new String'("--no-pager");
      Args (2) := new String'("-c");
      Args (3) := new String'("color.ui=false");
      Args (4) := new String'("-c");
      Args (5) := new String'("core.quotepath=false");
      Args (6) := new String'("-C");
      Args (7) := new String'(Working_Directory);
      for J in Arguments'Range loop
         Args (Prefix_Count + (J - Arguments'First) + 1) :=
           new String'(To_String (Arguments (J)));
      end loop;

      Create_Capture (FD, Temp);
      if FD = Invalid_FD then
         Release;
         Set_Error (Error, Filesystem_Error, Operation, "cannot create temporary output");
         return;
      end if;
      Close (FD);
      Spawn
        (Program_Name => Git.all,
         Args         => Args,
         Output_File  => To_String (Temp),
         Success      => Spawned,
         Return_Code  => Status,
         Err_To_Out   => True);
      Release;

      if not Spawned then
         Delete_File (To_String (Temp), Deleted);
         Set_Error (Error, Git_Command_Failed, Operation, "could not execute git", -1);
         return;
      end if;

      Read_File (To_String (Temp), Max_Output_Bytes, Output, Read_Error);
      Delete_File (To_String (Temp), Deleted);
      if not Success (Read_Error) then
         Error := Read_Error;
         return;
      end if;
      if Status /= 0 then
         Set_Error
           (Error, Git_Command_Failed, Operation,
            Trim_Line_End (To_String (Output)), Status);
      end if;
   exception
      when others =>
         Set_Error (Error, Filesystem_Error, Operation, "backend process failure", Status);
   end Run_Git;

   function Trim_Line_End (Value : String) return String is
      Last : Integer := Value'Last;
   begin
      while Last >= Value'First
        and then Value (Last) in Character'Val (10) | Character'Val (13)
      loop
         Last := Last - 1;
      end loop;
      return Value (Value'First .. Last);
   end Trim_Line_End;

   function Digest (Value : String) return String is
      Result : constant GNAT.SHA256.Message_Digest := GNAT.SHA256.Digest (Value);
   begin
      return Result;
   end Digest;

   function Git_Blob_Id (Object_Format, Content : String) return String is
      Image : constant String := Natural'Image (Content'Length);
      Input : constant String :=
        "blob " & Image (Image'First + 1 .. Image'Last)
        & Character'Val (0) & Content;
   begin
      if Object_Format = "sha256" then
         declare
            Result : constant GNAT.SHA256.Message_Digest :=
              GNAT.SHA256.Digest (Input);
         begin
            return Result;
         end;
      else
         declare
            Result : constant GNAT.SHA1.Message_Digest := GNAT.SHA1.Digest (Input);
         begin
            return Result;
         end;
      end if;
   end Git_Blob_Id;

end Git_Changes.Backends;
