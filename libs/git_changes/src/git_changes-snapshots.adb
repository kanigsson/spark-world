with GNAT.OS_Lib;
with Git_Changes.Backends;
with Interfaces.C;

package body Git_Changes.Snapshots is
   use Ada.Strings.Unbounded;
   use type Git_Changes.Backends.Argument_Array;

   NUL : constant Character := Character'Val (0);
   LF  : constant Character := Character'Val (10);

   --  Every command runs literally: a revision or path byte string is never
   --  reinterpreted as a glob, whatever the repository's configuration.
   function Literal return Unbounded_String is
     (To_Unbounded_String ("--literal-pathspecs"));

   function Arg (Value : String) return Unbounded_String
     renames To_Unbounded_String;

   function Tree (Revision : String) return Snapshot is
     ((Snapshot_Type => Tree_Endpoint,
       Named => To_Unbounded_String (Revision)));
   function Index return Snapshot is
     ((Snapshot_Type => Index_Endpoint, Named => Null_Unbounded_String));
   function Worktree return Snapshot is
     ((Snapshot_Type => Worktree_Endpoint, Named => Null_Unbounded_String));
   function Kind (Item : Snapshot) return Endpoint_Kind is
     (Item.Snapshot_Type);
   function Revision (Item : Snapshot) return String is
     (To_String (Item.Named));

   function Count (Item : Inventory) return Natural is
     (Natural (Item.Paths.Length));
   function Path (Item : Inventory; Number : Positive) return Byte_String is
     (To_String (Item.Paths (Number).Name));
   function Is_Untracked
     (Item : Inventory; Number : Positive) return Boolean is
     (Item.Paths (Number).Untracked);

   function Count (Item : Match_List) return Natural is
     (Natural (Item.Matches.Length));
   function Path (Item : Match_List; Number : Positive) return Byte_String is
     (To_String (Item.Matches (Number).Name));
   function Line (Item : Match_List; Number : Positive) return Positive is
     (Item.Matches (Number).Number);
   function Text (Item : Match_List; Number : Positive) return Byte_String is
     (To_String (Item.Matches (Number).Value));

   --  Collect the NUL-terminated entries of a Git listing. A trailing
   --  unterminated remnant is dropped rather than guessed at.
   procedure Each_Entry
     (Raw       : String;
      Untracked : Boolean;
      Result    : in out Inventory)
   is
      First : Positive := Raw'First;
   begin
      for J in Raw'Range loop
         if Raw (J) = NUL then
            if J > First then
               Result.Paths.Append
                 (Listed_Path'
                    (Name => To_Unbounded_String (Raw (First .. J - 1)),
                     Untracked => Untracked));
            end if;
            First := J + 1;
         end if;
      end loop;
   end Each_Entry;

   procedure List
     (Repository        : Git_Changes.Repository;
      Snapshot          : Snapshots.Snapshot;
      Include_Untracked : Boolean := False;
      Options           : Capture_Options := Default_Options;
      Result            : out Inventory;
      Error             : out Error_Info)
   is
      Output : Unbounded_String;
   begin
      Result := (Paths => Path_Vectors.Empty_Vector);
      case Snapshot.Snapshot_Type is
         when Tree_Endpoint =>
            Git_Changes.Backends.Run_Git
              (Root_Path (Repository),
               [Literal, Arg ("ls-tree"), Arg ("-r"), Arg ("--name-only"),
                Arg ("-z"), Arg ("--full-tree"), Arg ("--end-of-options"),
                Snapshot.Named],
               Options.Max_Output_Bytes, "list tree", Output, Error);
            if not Success (Error) then
               return;
            end if;
            Each_Entry (To_String (Output), False, Result);
         when Index_Endpoint | Worktree_Endpoint =>
            Git_Changes.Backends.Run_Git
              (Root_Path (Repository),
               [Literal, Arg ("ls-files"), Arg ("--cached"),
                Arg ("--full-name"), Arg ("-z")],
               Options.Max_Output_Bytes, "list index", Output, Error);
            if not Success (Error) then
               return;
            end if;
            Each_Entry (To_String (Output), False, Result);
            if Include_Untracked
              and then Snapshot.Snapshot_Type = Worktree_Endpoint
            then
               Git_Changes.Backends.Run_Git
                 (Root_Path (Repository),
                  [Literal, Arg ("ls-files"), Arg ("--others"),
                   Arg ("--exclude-standard"), Arg ("--full-name"),
                   Arg ("-z")],
                  Options.Max_Output_Bytes, "list untracked", Output, Error);
               if not Success (Error) then
                  Result := (Paths => Path_Vectors.Empty_Vector);
                  return;
               end if;
               Each_Entry (To_String (Output), True, Result);
            end if;
      end case;
   end List;

   --  Read a symbolic link's target. The link is not followed: the target
   --  text is the content a read-only view of the working tree shows.
   procedure Read_Link
     (Name    : String;
      Content : out Unbounded_String;
      Error   : out Error_Info)
   is
      use Interfaces.C;
      function C_Readlink
        (Path : char_array; Buffer : out char_array; Size : size_t)
         return long
        with Import, Convention => C, External_Name => "readlink";
      Buffer : char_array (1 .. 4096);
      Result : constant long :=
        C_Readlink (To_C (Name), Buffer, Buffer'Length);
   begin
      Content := Null_Unbounded_String;
      Error := (others => <>);
      if Result < 0 then
         Set_Error
           (Error, Filesystem_Error, "load content",
            "cannot read symbolic link: " & Name);
         return;
      end if;
      if size_t (Result) >= Buffer'Length then
         Set_Error
           (Error, Resource_Limit, "load content",
            "symbolic link target too long: " & Name);
         return;
      end if;
      Content :=
        To_Unbounded_String
          (To_Ada (Buffer (1 .. size_t (Result)), Trim_Nul => False));
   end Read_Link;

   procedure Load
     (Repository : Git_Changes.Repository;
      Snapshot   : Snapshots.Snapshot;
      Path       : Byte_String;
      Options    : Capture_Options := Default_Options;
      Content    : out Unbounded_String;
      Error      : out Error_Info) is
   begin
      Content := Null_Unbounded_String;
      Error := (others => <>);
      case Snapshot.Snapshot_Type is
         when Tree_Endpoint | Index_Endpoint =>
            --  cat-file takes one object name: the snapshot and the path
            --  join into it, so no separate pathspec can be misread.
            declare
               Object : constant String :=
                 (if Snapshot.Snapshot_Type = Tree_Endpoint
                  then To_String (Snapshot.Named) & ":" & Path
                  else ":" & Path);
            begin
               Git_Changes.Backends.Run_Git
                 (Root_Path (Repository),
                  [Literal, Arg ("cat-file"), Arg ("blob"), Arg (Object)],
                  Options.Max_Content_Bytes, "load content", Content, Error);
               if not Success (Error) then
                  Set_Error
                    (Error, Content_Unavailable, "load content",
                     Detail (Error), Exit_Status (Error));
                  Content := Null_Unbounded_String;
               end if;
            end;
         when Worktree_Endpoint =>
            declare
               Name : constant String := Root_Path (Repository) & "/" & Path;
            begin
               if GNAT.OS_Lib.Is_Symbolic_Link (Name) then
                  Read_Link (Name, Content, Error);
               else
                  Git_Changes.Backends.Read_File
                    (Name, Options.Max_Content_Bytes, Content, Error);
               end if;
            end;
      end case;
   end Load;

   procedure Search
     (Repository : Git_Changes.Repository;
      Snapshot   : Snapshots.Snapshot;
      Pattern    : Byte_String;
      Options    : Capture_Options := Default_Options;
      Result     : out Match_List;
      Error      : out Error_Info)
   is
      Output : Unbounded_String;
      Prefix : constant String :=
        (if Snapshot.Snapshot_Type = Tree_Endpoint
         then To_String (Snapshot.Named) & ":" else "");
   begin
      Result := (Matches => Match_Vectors.Empty_Vector);
      declare
         Head : constant Git_Changes.Backends.Argument_Array :=
           [Literal, Arg ("grep"), Arg ("-I"), Arg ("-n"), Arg ("-z"),
            Arg ("-F"), Arg ("-e"), Arg (Pattern)];
         Stop : constant Git_Changes.Backends.Argument_Array :=
           [1 => Arg ("--")];
      begin
         case Snapshot.Snapshot_Type is
            when Tree_Endpoint =>
               Git_Changes.Backends.Run_Git
                 (Root_Path (Repository), Head & [Snapshot.Named] & Stop,
                  Options.Max_Output_Bytes, "search snapshot", Output, Error);
            when Index_Endpoint =>
               Git_Changes.Backends.Run_Git
                 (Root_Path (Repository), Head & [Arg ("--cached")] & Stop,
                  Options.Max_Output_Bytes, "search snapshot", Output, Error);
            when Worktree_Endpoint =>
               Git_Changes.Backends.Run_Git
                 (Root_Path (Repository), Head & Stop,
                  Options.Max_Output_Bytes, "search snapshot", Output, Error);
         end case;
      end;
      --  git grep reports "no match" as exit status 1 with no output. That
      --  is an answer, not a failure.
      if Code (Error) = Git_Command_Failed
        and then Exit_Status (Error) = 1
        and then Length (Output) = 0
      then
         Error := (others => <>);
         return;
      end if;
      if not Success (Error) then
         return;
      end if;
      --  Each match is path NUL line NUL text LF; only the text may hold
      --  arbitrary bytes, so both separators are found before it is read.
      declare
         Raw : constant String := To_String (Output);
         Pos : Positive := Raw'First;
      begin
         while Pos <= Raw'Last loop
            declare
               Name_End : Natural := 0;
               Line_End : Natural := 0;
               Text_End : Natural := 0;
            begin
               for J in Pos .. Raw'Last loop
                  if Raw (J) = NUL then
                     Name_End := J;
                     exit;
                  end if;
               end loop;
               exit when Name_End = 0;
               for J in Name_End + 1 .. Raw'Last loop
                  if Raw (J) = NUL then
                     Line_End := J;
                     exit;
                  end if;
               end loop;
               exit when Line_End = 0;
               Text_End := Raw'Last + 1;
               for J in Line_End + 1 .. Raw'Last loop
                  if Raw (J) = LF then
                     Text_End := J;
                     exit;
                  end if;
               end loop;
               declare
                  Name : constant String := Raw (Pos .. Name_End - 1);
                  Digits_Text : constant String :=
                    Raw (Name_End + 1 .. Line_End - 1);
                  Number : Positive := 1;
                  Valid : Boolean := Digits_Text'Length > 0;
               begin
                  for C of Digits_Text loop
                     Valid := Valid and then C in '0' .. '9';
                  end loop;
                  if Valid then
                     Number := Positive'Value (Digits_Text);
                     Result.Matches.Append
                       (Located_Match'(Name => To_Unbounded_String
                           (if Prefix'Length > 0
                              and then Name'Length > Prefix'Length
                              and then Name (Name'First .. Name'First
                                             + Prefix'Length - 1) = Prefix
                            then Name (Name'First + Prefix'Length .. Name'Last)
                            else Name),
                         Number => Number,
                         Value => To_Unbounded_String
                           (Raw (Line_End + 1 .. Text_End - 1))));
                  end if;
               end;
               Pos := Text_End + 1;
            end;
         end loop;
      end;
   end Search;

end Git_Changes.Snapshots;
