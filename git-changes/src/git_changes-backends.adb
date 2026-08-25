with Ada.Directories;
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
         Length : Natural;
      begin
         if Current_Size > IO.Count (Max_Content_Bytes) then
            IO.Close (File);
            Set_Error
              (Error, Resource_Limit, "read",
               "content grew beyond configured limit: " & Name);
            return;
         end if;
         Length := Natural (Current_Size);
         declare
         Bytes  : Stream_Element_Array (1 .. Stream_Element_Offset (Length));
         Last   : Stream_Element_Offset;
         Text   : String (1 .. Length);
         begin
         if Length > 0 then
            IO.Read (File, Bytes, Last);
            if Last /= Bytes'Last then
               IO.Close (File);
               Set_Error (Error, Filesystem_Error, "read", "short read: " & Name);
               return;
            end if;
            for J in Text'Range loop
               Text (J) := Character'Val (Bytes (Stream_Element_Offset (J)));
            end loop;
         end if;
         Content := To_Unbounded_String (Text);
         end;
      end;
      IO.Close (File);
   exception
      when others =>
         if IO.Is_Open (File) then
            IO.Close (File);
         end if;
         Set_Error (Error, Filesystem_Error, "read", "cannot read: " & Name);
   end Read_File;

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
      Temp : GNAT.OS_Lib.String_Access;
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

      Create_Temp_File (FD, Temp);
      if FD = Invalid_FD or else Temp = null then
         Release;
         Set_Error (Error, Filesystem_Error, Operation, "cannot create temporary output");
         return;
      end if;
      Close (FD);
      Spawn
        (Program_Name => Git.all,
         Args         => Args,
         Output_File  => Temp.all,
         Success      => Spawned,
         Return_Code  => Status,
         Err_To_Out   => True);
      Release;

      if not Spawned then
         Delete_File (Temp.all, Deleted);
         Free (Temp);
         Set_Error (Error, Git_Command_Failed, Operation, "could not execute git", -1);
         return;
      end if;

      Read_File (Temp.all, Max_Output_Bytes, Output, Read_Error);
      Delete_File (Temp.all, Deleted);
      Free (Temp);
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
