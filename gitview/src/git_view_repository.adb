with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Environment_Variables;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;
with Git_Changes;
with Git_Changes.Repositories;
with Git_Changes.Contents;
with Git_View_Source;
with Interfaces.C;

package body Git_View_Repository with SPARK_Mode => Off is
   package G renames Git_Changes;
   use type G.Change_Kind;
   use type M.Snapshot_Kind;
   use type M.Change_Lens;
   use type M.Tree_Visibility;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_IO.Count;
   LF : constant Character := ASCII.LF;
   NUL : constant Character := ASCII.NUL;
   Limit : constant := 64 * 1024 * 1024;
   Repository_Root : Unbounded_String;
   function Read_Link (Path : String) return String is
      use Interfaces.C;
      function C_Readlink (Name : char_array; Buffer : out char_array;
                           Size : size_t) return long
        with Import, Convention => C, External_Name => "readlink";
      Buffer : char_array (1 .. M.Max_Text);
      Count : constant long := C_Readlink (To_C (Path), Buffer, Buffer'Length);
   begin
      if Count < 0 then raise Program_Error with "cannot read symlink"; end if;
      return To_Ada (Buffer (1 .. size_t (Count)), Trim_Nul => False);
   end Read_Link;
   package Strings is new Ada.Containers.Vectors (Positive, Unbounded_String);
   package Targets is new Ada.Containers.Vectors (Positive, Row_Target);
   package Marks is new Ada.Containers.Vectors (Positive, Mark);
   package Paths is new Ada.Containers.Indefinite_Ordered_Sets (String);
   package Change_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Natural);
   type Buffer_Ref is access Tui.Text.Buffer;
   procedure Release is new Ada.Unchecked_Deallocation (Tui.Text.Buffer, Buffer_Ref);
   procedure Release is new Ada.Unchecked_Deallocation (Target_Array, Target_Ref);
   procedure Release is new Ada.Unchecked_Deallocation (Mark_Array, Mark_Ref);

   function Bounded (S : String) return M.Text is
   begin
      if S'Length > M.Max_Text then
         raise Constraint_Error with "path or revision exceeds 4096 bytes";
      end if;
      return M.To_Text (S);
   end Bounded;

   --  Read in chunks and accumulate on the heap: a whole file's worth of
   --  stack would overflow the loader task on large sources or long logs.
   function Read_File (Path : String) return String is
      use Ada.Streams;
      package IO renames Ada.Streams.Stream_IO;
      F : IO.File_Type;
      Result : Unbounded_String;
      Chunk : Stream_Element_Array (1 .. 64 * 1024);
      Last : Stream_Element_Offset;
   begin
      IO.Open (F, IO.In_File, Path);
      if IO.Size (F) > IO.Count (Limit) then
         IO.Close (F);
         raise Constraint_Error with "content exceeds 64 MiB limit";
      end if;
      loop
         IO.Read (F, Chunk, Last);
         exit when Last < Chunk'First;
         declare
            Text : String (1 .. Natural (Last));
         begin
            for I in Text'Range loop
               Text (I) := Character'Val (Chunk (Stream_Element_Offset (I)));
            end loop;
            Append (Result, Text);
         end;
         exit when Last < Chunk'Last;
      end loop;
      IO.Close (F);
      return To_String (Result);
   exception
      when others =>
         if IO.Is_Open (F) then IO.Close (F); end if;
         raise;
   end Read_File;

   function Args (A : String) return Strings.Vector is
      V : Strings.Vector;
   begin
      V.Append (To_Unbounded_String (A));
      return V;
   end Args;
   function "+" (V : Strings.Vector; S : String) return Strings.Vector is
      R : Strings.Vector := V;
   begin
      R.Append (To_Unbounded_String (S));
      return R;
   end "+";

   --  Capture files live in the temporary directory, never in the working
   --  tree: the checkout under inspection must not gain untracked files,
   --  which would show up in the very tree this adapter draws.
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
              Dir & "/git_view-"
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

   function Git (A : Strings.Vector; Allow_One : Boolean := False) return String is
      use GNAT.OS_Lib;
      Exe : GNAT.OS_Lib.String_Access := Locate_Exec_On_Path ("git");
      Name : Unbounded_String;
      FD : File_Descriptor;
      Code : Integer;
      Deleted : Boolean;
      Av : Argument_List (1 .. Natural (A.Length) + 5);
   begin
      if Exe = null then raise Program_Error with "git not found"; end if;
      Av (1) := new String'("--no-pager");
      Av (2) := new String'("--literal-pathspecs");
      Av (3) := new String'("-c");
      --  Disable terminal escapes in output even when the user's config
      --  enables colors. Repository commands still use separate argv entries.
      declare
         Full : Argument_List (1 .. Av'Length + 1);
      begin
         for I in 1 .. 3 loop Full (I) := Av (I); end loop;
         Full (4) := new String'("color.ui=false");
         Full (5) := new String'("-C");
         Full (6) := new String'((if Length (Repository_Root) = 0 then "." else To_String (Repository_Root)));
         for I in 1 .. Natural (A.Length) loop
            Full (I + 6) := new String'(To_String (A (I)));
         end loop;
         Create_Capture (FD, Name);
         if FD = Invalid_FD then
            raise Program_Error with "cannot create git capture";
         end if;
         Spawn (Exe.all, Full, FD, Code, True);
         Close (FD);
         for Item of Full loop Free (Item); end loop;
      end;
      Free (Exe);
      declare
         S : constant String := Read_File (To_String (Name));
      begin
         Delete_File (To_String (Name), Deleted);
         if Code /= 0 and then not (Allow_One and then Code = 1) then
            raise Program_Error with S;
         end if;
         return S;
      end;
   end Git;

   function Trim (S : String) return String is
     (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));
   function One_Line (S : String) return String is
     (if S'Length > 0 and then S (S'Last) = LF
      then S (S'First .. S'Last - 1) else S);

   function Split (S : String; Separator : Character) return Strings.Vector is
      R : Strings.Vector;
      First : Positive := S'First;
   begin
      for I in S'Range loop
         if S (I) = Separator then
            R.Append (To_Unbounded_String (S (First .. I - 1)));
            First := I + 1;
         end if;
      end loop;
      if First <= S'Last then
         R.Append (To_Unbounded_String (S (First .. S'Last)));
      end if;
      return R;
   end Split;

   --  Escape control bytes in labels only. Raw identities remain in Targets.
   function Label (S : String) return String is
      R : Unbounded_String;
   begin
      for C of S loop
         case C is
            when ASCII.LF => Append (R, "\n");
            when ASCII.CR => Append (R, "\r");
            when ASCII.HT => Append (R, "\t");
            when ASCII.ESC => Append (R, "\e");
            when others =>
               if Character'Pos (C) < 32 or else C = ASCII.DEL then
                  Append (R, '?');
               else Append (R, C); end if;
         end case;
      end loop;
      return To_String (R);
   end Label;

   --  The staging buffer is heap allocated: a document-sized stack object
   --  overflows the loader task on large sources and long histories.
   function Doc (S : String) return Tui.Text.Doc_Ref is
      B : Buffer_Ref := new Tui.Text.Buffer (1 .. S'Length);
      R : Tui.Text.Doc_Ref;
   begin
      for I in B.all'Range loop B (I) := Character'Pos (S (S'First + I - 1)); end loop;
      R := Tui.Text.New_Document (B.all);
      Release (B);
      return R;
   end Doc;

   procedure Free (F : in out Frame) is
   begin
      Tui.Text.Free (F.History); Tui.Text.Free (F.Tree); Tui.Text.Free (F.Source);
      Release (F.Commits); Release (F.Paths); Release (F.Marks);
   end Free;

   Cached_Changes : G.Change_Set;
   Cached_Base, Cached_Target : Unbounded_String;
   Cache_Valid : Boolean := False;
   Cached_Log_Key, Cached_Log : Unbounded_String;
   Cached_Tree_Key, Cached_Tree : Unbounded_String;
   Cached_Content_Key, Cached_Content : Unbounded_String;

   procedure Load (V : M.View_State; F : in out Frame) is
      Repo : G.Repository;
      Error : G.Error_Info;
      Target, Base, Root : Unbounded_String;
      Inventory : Paths.Set;
      Untracked_Paths : Paths.Set;
      Changes_By_Path : Change_Maps.Map;
      Tree_Rows, History_Rows : Targets.Vector;
      Source_Marks : Marks.Vector;
      H, T, S : Unbounded_String;
      Scope : Unbounded_String := To_Unbounded_String (M.Image (V.Scope));

      function Change (Path : String) return Natural is
      begin
         return (if Changes_By_Path.Contains (Path) then Changes_By_Path (Path) else 0);
      end Change;

      procedure Add_Row (Path, Display : String; Changed : Boolean;
                         Line : Tui.Text.Line_Number := 1) is
      begin
         Append (T, Display & LF);
         Tree_Rows.Append (Row_Target'(Bounded (Path), Line, Changed));
      end Add_Row;

      function Content (Path : String) return String is
      begin
         case V.Kind is
            when M.Commit =>
               declare
                  Key : constant Unbounded_String := Target & ":" & Path;
               begin
                  if Cached_Content_Key /= Key then
                     Cached_Content := To_Unbounded_String (Git (Args ("show") + To_String (Key)));
                     Cached_Content_Key := Key;
                  end if;
                  return To_String (Cached_Content);
               end;
            when M.Staging => return Git (Args ("show") + (":" & Path));
            when M.Worktree =>
               --  Never follow a symlink into a different file or outside the
               --  repository. Git's no-index reader returns symlink contents.
               if GNAT.OS_Lib.Is_Symbolic_Link (To_String (Root) & "/" & Path) then
                  return Read_Link (To_String (Root) & "/" & Path);
               end if;
               return Read_File (To_String (Root) & "/" & Path);
         end case;
      end Content;

      procedure Emit (Value : String; Kind : Mark := Normal) is
      begin
         Append (S, Value & LF);
         Source_Marks.Append (Kind);
      end Emit;

      procedure Render_Source is
         File : constant Natural := Change (To_String (Scope));
         Whole_Added : constant Boolean := Untracked_Paths.Contains (To_String (Scope));
         Old_Content, New_Content : Unbounded_String;
         Base_Only : Boolean := False;
         Old_Lines, New_Lines : Strings.Vector;

         function Near_Change (Line : Natural) return Boolean is
         begin
            for J in 1 .. G.Span_Count (Cached_Changes, File) loop
               declare
                  P : constant G.Changed_Span := G.Span (Cached_Changes, File, J);
               begin
                  if M.In_Context (Line, M.Deletion_Anchor (P.New_First, P.New_Count),
                                   P.New_Count) then return True; end if;
               end;
            end loop;
            return False;
         end Near_Change;
         Previous_Visible : Boolean := False;
         Span_Index : Positive := 1;
         Span_Total : Natural := 0;
      begin
         if Length (Scope) = 0 then Emit ("Select a file in the tree."); return; end if;
         if File > 0 then
            if G.Is_Submodule (Cached_Changes, File) then
               Emit ("[submodule] " & Label (To_String (Scope))); return;
            elsif G.Is_Binary (Cached_Changes, File) then
               Emit ("[binary file] " & Label (To_String (Scope))); return;
            end if;
            Base_Only := G.File_Kind (Cached_Changes, File) = G.Deleted;
            if G.Content_Available (Cached_Changes, File, G.Old_Side) then
               G.Contents.Load (Cached_Changes, File, G.Old_Side, Old_Content, Error);
               if not G.Success (Error) then raise Program_Error with G.Detail (Error); end if;
            end if;
            Span_Total := G.Span_Count (Cached_Changes, File);
         end if;
         if Base_Only then
            Emit ("[base-only deleted file] " & Label (To_String (Scope)), Ghost);
            for Line of Split (To_String (Old_Content), LF) loop
               Emit ("- [base] " & To_String (Line), Ghost);
            end loop;
            return;
         end if;
         if not Inventory.Contains (To_String (Scope)) then
            Emit ("[absent in snapshot] " & Label (To_String (Scope)));
            return;
         end if;
         New_Content := To_Unbounded_String (Content (To_String (Scope)));
         if Ada.Strings.Fixed.Index (To_String (New_Content), "" & NUL) > 0 then
            Emit ("[binary file] " & Label (To_String (Scope))); return;
         end if;
         Old_Lines := Split (To_String (Old_Content), LF);
         New_Lines := Split (To_String (New_Content), LF);
         for L in 1 .. Natural (New_Lines.Length) + 1 loop
            --  Spans are sorted; walk once, keeping the overlay linear in
            --  file size plus number of spans. Deletions may anchor at EOF.
            while Span_Index <= Span_Total loop
               declare
                  P : constant G.Changed_Span := G.Span (Cached_Changes, File, Span_Index);
                  Anchor : constant Natural := M.Deletion_Anchor (P.New_First, P.New_Count);
               begin
                  exit when Anchor >= L or else M.In_Range (L, P.New_First, P.New_Count);
                  Span_Index := Span_Index + 1;
               end;
            end loop;
            if V.Lens /= M.Plain and then Span_Index <= Span_Total then
               declare
                  P : constant G.Changed_Span := G.Span (Cached_Changes, File, Span_Index);
               begin
                  if M.Deletion_Anchor (P.New_First, P.New_Count) = L then
                     if V.Lens = M.Before_After then
                        Emit ("@@ -" & Trim (P.Old_First'Image) & "," & Trim (P.Old_Count'Image)
                              & " +" & Trim (P.New_First'Image) & "," & Trim (P.New_Count'Image)
                              & " @@", Hunk_Header);
                     end if;
                     for O in P.Old_First .. P.Old_First + P.Old_Count - 1 loop
                        if O in 1 .. Natural (Old_Lines.Length) then
                           Emit ("- [base] " & To_String (Old_Lines (O)), Ghost);
                        end if;
                     end loop;
                  end if;
               end;
            end if;
            if L <= Natural (New_Lines.Length) then
               declare
                  Added : constant Boolean := Whole_Added or else
                    (Span_Index <= Span_Total and then
                     M.In_Range (L, G.Span (Cached_Changes, File, Span_Index).New_First,
                                 G.Span (Cached_Changes, File, Span_Index).New_Count));
                  Visible : constant Boolean := V.Lens not in M.Hunks | M.Before_After
                    or else Whole_Added
                    or else (File > 0 and then Near_Change (L));
               begin
                  if Visible then
                     if not Previous_Visible and then V.Lens = M.Hunks then
                        Emit ("@@ snapshot line " & Trim (L'Image) & " @@", Hunk_Header);
                     end if;
                     if V.Lens = M.Plain then Emit (To_String (New_Lines (L)));
                     else
                        Emit ((if Added then "+ " else "  ") & Trim (L'Image)
                              & " | " & To_String (New_Lines (L)),
                              (if Added then Addition else Normal));
                     end if;
                  end if;
                  Previous_Visible := Visible;
               end;
            end if;
         end loop;
         if Length (S) = 0 then
            Emit ((if V.Lens in M.Hunks | M.Before_After then "[no textual hunks]"
                   else "[empty file]"));
         end if;
      end Render_Source;
   begin
      Free (F);
      G.Repositories.Open (".", Repo, Error);
      if not G.Success (Error) then raise Program_Error with G.Detail (Error); end if;
      Root := To_Unbounded_String (G.Root_Path (Repo));
      if Root /= Repository_Root then
         Cache_Valid := False;
         Cached_Log_Key := Null_Unbounded_String;
         Cached_Tree_Key := Null_Unbounded_String;
         Cached_Content_Key := Null_Unbounded_String;
      end if;
      Repository_Root := Root;
      --  Run relative to the repository root, even when launched in a subdir.
      --  This is worker-local policy: never change the process working dir.
      if V.Kind = M.Commit then
         Target := To_Unbounded_String (One_Line (Git (Args ("rev-parse") + "--verify"
           + "--end-of-options" + ((if V.Snapshot.Last = 0 then "HEAD"
                                    else M.Image (V.Snapshot)) & "^{commit}"))));
      else Target := To_Unbounded_String ((if V.Kind = M.Worktree then "worktree" else "index"));
      end if;
      if not V.Automatic_Base then Base := To_Unbounded_String (M.Image (V.Base));
      elsif V.Kind /= M.Commit then Base := To_Unbounded_String ("HEAD");
      else
         declare
            Parents : constant Strings.Vector := Split
              (One_Line (Git (Args ("rev-list") + "--parents" + "-n" + "1" + To_String (Target))), ' ');
         begin
            if Parents.Length > 1 then Base := Parents (2);
            else Base := To_Unbounded_String (One_Line (Git (Args ("hash-object") + "-t" + "tree" + "/dev/null")));
            end if;
         end;
      end if;
      if not Cache_Valid or else Cached_Base /= Base or else Cached_Target /= Target
        or else V.Kind /= M.Commit
      then
         declare
            Comparison : constant G.Comparison :=
              (case V.Kind is
                 when M.Commit => G.Tree_To_Tree (To_String (Base), To_String (Target)),
                 when M.Staging => G.Tree_To_Index (To_String (Base)),
                 when M.Worktree => G.Tree_To_Worktree (To_String (Base)));
         begin
            Cache_Valid := False;
            G.Capture (Repo, Comparison, Changes => Cached_Changes, Error => Error);
            if not G.Success (Error) then raise Program_Error with G.Detail (Error); end if;
            Cached_Base := Base; Cached_Target := Target; Cache_Valid := True;
         end;
      end if;
      for I in 1 .. G.File_Count (Cached_Changes) loop
         for Side in G.Side loop
            if G.Has_Path (Cached_Changes, I, Side) then
               Changes_By_Path.Include (G.Path (Cached_Changes, I, Side), I);
            end if;
         end loop;
      end loop;
      F.Resolved_Snapshot := Bounded (To_String (Target));
      F.Resolved_Base := Bounded (One_Line (Git (Args ("rev-parse") + "--verify"
                                               + "--end-of-options" + To_String (Base))));
      if G.Is_Stale (Cached_Changes) then F.Notice := Bounded ("comparison changed during capture; press r to refresh");
      else F.Notice := Bounded (""); end if;
      declare
         A : Strings.Vector := Args ("log") + "--topo-order" + "--date=short"
           + "--format=%H%x09%p%x09%h %ad %d %s";
         Key : Unbounded_String;
         Filter : Git_View_Source.Filters renames V.History_Filter;
      begin
         if Filter.All_Refs then A := A + "--all"; end if;
         if Filter.First_Parent then A := A + "--first-parent"; end if;
         if Filter.Author.Len > 0 then A := A + ("--author=" & Git_View_Source.Image (Filter.Author)); end if;
         if Filter.Since.Len > 0 then A := A + ("--since=" & Git_View_Source.Image (Filter.Since)); end if;
         if Filter.Until_Date.Len > 0 then A := A + ("--until=" & Git_View_Source.Image (Filter.Until_Date)); end if;
         if Filter.Message.Len > 0 then A := A + ("--grep=" & Git_View_Source.Image (Filter.Message)); end if;
         A := A + "--end-of-options";
         if V.History_Root.Len > 0 then A := A + Git_View_Source.Image (V.History_Root); end if;
         A := A + "--";
         if V.Path_Filter.Last > 0 then A := A + M.Image (V.Path_Filter);
         elsif Filter.Path.Len > 0 then A := A + Git_View_Source.Image (Filter.Path); end if;
         for Arg of A loop Append (Key, Arg & NUL); end loop;
         if Key /= Cached_Log_Key or else V.Kind /= M.Commit then
            Cached_Log := To_Unbounded_String (Git (A)); Cached_Log_Key := Key;
         end if;
         for Line of Split (To_String (Cached_Log), LF) loop
            declare
               Value : constant String := To_String (Line);
               Tab : constant Natural := Ada.Strings.Fixed.Index (Value, "" & ASCII.HT);
               Second_Tab : constant Natural := (if Tab > 0 then
                 Ada.Strings.Fixed.Index (Value, "" & ASCII.HT, Tab + 1) else 0);
            begin
               if Second_Tab > 0 then
                  History_Rows.Append (Row_Target'(Bounded (Value (1 .. Tab - 1)), 1, False));
                  Append (H, (if Ada.Strings.Fixed.Index (Value (Tab + 1 .. Second_Tab - 1), " ") > 0
                              then "M " else "* ")
                    & Label (Value (Second_Tab + 1 .. Value'Last))
                    & " [parents: " & Value (Tab + 1 .. Second_Tab - 1) & "]" & LF);
               end if;
            end;
         end loop;
      end;
      declare
         Raw : Unbounded_String;
      begin
         if V.Kind = M.Commit then
            if Target /= Cached_Tree_Key then
               Cached_Tree := To_Unbounded_String (Git (Args ("ls-tree") + "-r" + "--name-only" + "-z" + To_String (Target)));
               Cached_Tree_Key := Target;
            end if;
            Raw := Cached_Tree;
         else
            Raw := To_Unbounded_String (Git (Args ("ls-files") + "--cached" + "--full-name" + "-z"));
            if V.Kind = M.Worktree then
               declare
                  Untracked : constant String := Git (Args ("ls-files") + "--others" + "--exclude-standard" + "--full-name" + "-z");
               begin
                  Append (Raw, Untracked);
                  for Path of Split (Untracked, NUL) loop Untracked_Paths.Include (To_String (Path)); end loop;
               end;
            end if;
         end if;
         for Path of Split (To_String (Raw), NUL) loop
            Inventory.Include (To_String (Path));
         end loop;
      end;
      declare
         Displayed : Paths.Set := Inventory;
         Dirs : Paths.Set;
         Changed_Dirs : Paths.Set;
      begin
         for I in 1 .. G.File_Count (Cached_Changes) loop
            declare
               Which : constant G.Side := (if G.Has_Path (Cached_Changes, I, G.New_Side)
                                          then G.New_Side else G.Old_Side);
               Path : constant String := G.Path (Cached_Changes, I, Which);
            begin
               for J in Path'Range loop
                  if Path (J) = '/' then Changed_Dirs.Include (Path (1 .. J)); end if;
               end loop;
            end;
         end loop;
         for I in 1 .. G.File_Count (Cached_Changes) loop
            if G.File_Kind (Cached_Changes, I) = G.Deleted then
               Displayed.Include (G.Path (Cached_Changes, I, G.Old_Side));
               Inventory.Exclude (G.Path (Cached_Changes, I, G.Old_Side));
            end if;
         end loop;
         for Path of Displayed loop
            declare
               C : constant Natural := Change (Path);
               Untracked : constant Boolean := Untracked_Paths.Contains (Path);
               Badge : constant String := (if C = 0 then (if Untracked then "?" else " ")
                 else (case G.File_Kind (Cached_Changes, C) is
                   when G.Added => "A", when G.Deleted => "D", when G.Renamed => "R",
                   when G.Copied => "C", when G.Type_Changed => "T", when others => "M"));
            begin
               if V.Visibility = M.All_Files or else C > 0 or else Untracked then
                  if V.Visibility /= M.Changed_Only then
                     for I in Path'Range loop
                        if Path (I) = '/' and then not Dirs.Contains (Path (1 .. I)) then
                           Dirs.Include (Path (1 .. I));
                           Add_Row (Path (1 .. I),
                             (if Changed_Dirs.Contains (Path (1 .. I)) then "M " else "  ")
                             & Label (Path (1 .. I)), Changed_Dirs.Contains (Path (1 .. I)));
                        end if;
                     end loop;
                  end if;
                  Add_Row (Path, Badge & " " & Label (Path), C > 0 or else Untracked);
                  if Length (Scope) = 0 then Scope := To_Unbounded_String (Path); end if;
               end if;
            end;
         end loop;
      end;
      if V.Repository_Search.Last > 0 then
         T := Null_Unbounded_String; Tree_Rows.Clear;
         --  Search the actual snapshot, including unchanged tracked files.
         --  git grep's NUL path separator avoids ambiguity in path bytes.
         declare
            A : Strings.Vector := Args ("grep") + "-I" + "-n" + "-z" + "-F"
              + "-e" + M.Image (V.Repository_Search);
         begin
            if V.Kind = M.Commit then A := A + To_String (Target);
            elsif V.Kind = M.Staging then A := A + "--cached"; end if;
            A := A + "--";
            declare
               Raw : constant String := Git (A, True);
               Pos : Positive := 1;
            begin
               while Pos <= Raw'Last loop
                  declare
                     Sep : constant Natural := Ada.Strings.Fixed.Index (Raw, "" & NUL, Pos);
                     Num_End : Natural;
                     Last : Natural;
                  begin
                     exit when Sep = 0;
                     Num_End := Ada.Strings.Fixed.Index (Raw, "" & NUL, Sep + 1);
                     exit when Num_End = 0;
                     Last := Ada.Strings.Fixed.Index (Raw, "" & LF, Num_End + 1);
                     if Last = 0 then Last := Raw'Last + 1; end if;
                     declare
                        Path : constant String := Raw
                          (Pos + (if V.Kind = M.Commit then Length (Target) + 1 else 0) .. Sep - 1);
                        Line : constant Positive := Positive'Value (Raw (Sep + 1 .. Num_End - 1));
                     begin
                        Add_Row (Path, Label (Path) & ":" & Trim (Line'Image) & ": "
                          & Label (Raw (Num_End + 1 .. Last - 1)), Change (Path) > 0,
                          Tui.Text.Line_Number'Min (Line, Tui.Text.Line_Number'Last));
                     end;
                     Pos := Last + 1;
                  end;
               end loop;
            end;
         end;
         if Tree_Rows.Is_Empty then Append (T, "[no snapshot search matches]" & LF); end if;
      end if;
      F.Scope := Bounded (To_String (Scope));
      begin Render_Source;
      exception when E : others =>
         S := Null_Unbounded_String; Source_Marks.Clear;
         Emit ("[content unavailable] " & Label (Ada.Exceptions.Exception_Message (E)));
      end;
      F.History := Doc (To_String (H)); F.Tree := Doc (To_String (T)); F.Source := Doc (To_String (S));
      F.Commits := new Target_Array (1 .. Natural (History_Rows.Length));
      for I in F.Commits'Range loop F.Commits (I) := History_Rows (I); end loop;
      F.Paths := new Target_Array (1 .. Natural (Tree_Rows.Length));
      for I in F.Paths'Range loop F.Paths (I) := Tree_Rows (I); end loop;
      F.Marks := new Mark_Array (1 .. Natural (Source_Marks.Length));
      for I in F.Marks'Range loop F.Marks (I) := Source_Marks (I); end loop;
   exception
      when E : others =>
         Free (F);
         F.Notice := Bounded ("repository request failed");
         F.History := Doc (""); F.Tree := Doc ("");
         F.Source := Doc ("[git error] " & Label (Ada.Exceptions.Exception_Message (E)));
   end Load;

   type Generation is mod 2 ** 64;
   protected Mailbox is
      procedure Submit (V : M.View_State; Refresh : Boolean);
      procedure Take (V : out M.View_State; Id : out Generation; Have, Done, Refresh : out Boolean);
      procedure Publish (F : in out Frame; Id : Generation);
      procedure Receive (F : in out Frame; Ready : out Boolean);
      procedure Close;
   private
      Query : M.View_State;
      Serial : Generation := 0;
      Pending, Finished, Available : Boolean := False;
      Invalidate : Boolean := False;
      Result : Frame;
   end Mailbox;
   protected body Mailbox is
      procedure Submit (V : M.View_State; Refresh : Boolean) is
      begin
         Query := V; Serial := Serial + 1; Pending := True;
         Invalidate := Invalidate or else Refresh;
         Free (Result); Available := False;
      end Submit;
      procedure Take (V : out M.View_State; Id : out Generation; Have, Done, Refresh : out Boolean) is
      begin
         V := Query; Id := Serial; Have := Pending; Pending := False; Done := Finished;
         Refresh := Invalidate; Invalidate := False;
      end Take;
      procedure Publish (F : in out Frame; Id : Generation) is
      begin
         if Id = Serial and then not Finished then
            Free (Result); Result := F; F := (others => <>); Available := True;
         else Free (F); end if;
      end Publish;
      procedure Receive (F : in out Frame; Ready : out Boolean) is
      begin
         Ready := Available;
         if Ready then Free (F); F := Result; Result := (others => <>); Available := False; end if;
      end Receive;
      procedure Close is
      begin Finished := True; Free (Result); end Close;
   end Mailbox;
   task type Worker_Task;
   type Worker_Ref is access Worker_Task;
   Worker : Worker_Ref;
   task body Worker_Task is
      V : M.View_State;
      Id : Generation;
      Have, Done, Refresh : Boolean;
      F : Frame;
   begin
      loop
         Mailbox.Take (V, Id, Have, Done, Refresh);
         exit when Done;
         if Have then
            if Refresh then
               Cache_Valid := False;
               Cached_Log_Key := Null_Unbounded_String;
               Cached_Tree_Key := Null_Unbounded_String;
            end if;
            Load (V, F); Mailbox.Publish (F, Id);
         else delay 0.02; end if;
      end loop;
      Free (F);
   end Worker_Task;
   procedure Request (V : M.View_State; Refresh : Boolean := False) is
   begin
      if Worker = null then Worker := new Worker_Task; end if;
      Mailbox.Submit (V, Refresh);
   end Request;
   procedure Poll (F : in out Frame; Ready : out Boolean) is
   begin Mailbox.Receive (F, Ready); end Poll;
   procedure Stop is
   begin Mailbox.Close; end Stop;
end Git_View_Repository;
