with Git_Changes.Backends;

package body Git_Changes.Contents is
   use Ada.Strings.Unbounded;

   procedure Load
     (Changes : Change_Set;
      File    : Positive;
      Which   : Side;
      Content : out Unbounded_String;
      Error   : out Error_Info)
   is
      Stored : constant Stored_File := Changes.Files (File);
      Args   : Git_Changes.Backends.Argument_Array (1 .. 3);
      Name   : Unbounded_String;
   begin
      Content := Null_Unbounded_String;
      Error := (others => <>);

      if Which = Old_Side and then Stored.Old_Object_Present then
         Args :=
           [To_Unbounded_String ("cat-file"),
            To_Unbounded_String ("blob"), Stored.Old_Object];
         Git_Changes.Backends.Run_Git
           (Root_Path (Changes.Repo), Args, Changes.Limits.Max_Content_Bytes,
            "load old content", Content, Error);
      elsif Which = New_Side
        and then Changes.New_State.Endpoint_Type = Worktree_Endpoint
        and then Stored.New_Path_Present
      then
         Name := Changes.Repo.Root;
         if Length (Name) > 0 and then Element (Name, Length (Name)) /= '/' then
            Append (Name, '/');
         end if;
         Append (Name, Stored.New_Path);
         Git_Changes.Backends.Read_File
           (To_String (Name), Changes.Limits.Max_Content_Bytes, Content, Error);
         if Success (Error)
           and then Length (Stored.Worktree_Fingerprint) > 0
           and then Git_Changes.Backends.Git_Blob_Id
             (Object_Format (Changes.Repo), To_String (Content))
             /= To_String (Stored.Worktree_Fingerprint)
         then
            Content := Null_Unbounded_String;
            Set_Error
              (Error, Content_Changed, "load content",
               "worktree content changed after capture");
         end if;
      elsif Which = New_Side and then Stored.New_Object_Present then
         Args :=
           [To_Unbounded_String ("cat-file"),
            To_Unbounded_String ("blob"), Stored.New_Object];
         Git_Changes.Backends.Run_Git
           (Root_Path (Changes.Repo), Args, Changes.Limits.Max_Content_Bytes,
            "load new content", Content, Error);
      else
         Set_Error
           (Error, Content_Unavailable, "load content",
            "the selected side has no available content");
      end if;
   end Load;

end Git_Changes.Contents;
