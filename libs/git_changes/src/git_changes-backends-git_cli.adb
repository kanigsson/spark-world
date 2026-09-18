with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Git_Changes.Core.Hunks;
with Git_Changes.Core.Raw;
with Git_Changes.Core.Validation;

package body Git_Changes.Backends.Git_CLI is
   use Ada.Strings.Unbounded;
   package Raw renames Git_Changes.Core.Raw;
   package Hunks renames Git_Changes.Core.Hunks;
   use type Raw.Parse_Result;
   use type Raw.Raw_Status;
   use type Hunks.Hunk_Result;

   package Argument_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Unbounded_String);

   procedure Append (Args : in out Argument_Vectors.Vector; Value : String) is
   begin
      Args.Append (To_Unbounded_String (Value));
   end Append;

   function Number_Image (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Number_Image;

   procedure Execute
     (Repo      : Repository;
      Args      : Argument_Vectors.Vector;
      Limit     : Positive;
      Operation : String;
      Output    : out Unbounded_String;
      Error     : out Error_Info)
   is
      Values : Argument_Array (1 .. Positive (Args.Length));
   begin
      for J in Values'Range loop
         Values (J) := Args (J);
      end loop;
      Run_Git (Root_Path (Repo), Values, Limit, Operation, Output, Error);
   end Execute;

   function Algorithm_Name (Value : Diff_Algorithm) return String
   is (case Value is
         when Myers     => "myers",
         when Minimal   => "minimal",
         when Patience  => "patience",
         when Histogram => "histogram");

   procedure Append_Comparison
     (Args : in out Argument_Vectors.Vector; Compared : Comparison) is
   begin
      case Compared.Comparison_Type is
         when Tree_To_Tree_Comparison      =>
            Append (Args, To_String (Compared.Old_Revision));
            Append (Args, To_String (Compared.New_Revision));

         when Tree_To_Index_Comparison     =>
            Append (Args, "--cached");
            Append (Args, To_String (Compared.Old_Revision));

         when Index_To_Worktree_Comparison =>
            null;

         when Tree_To_Worktree_Comparison  =>
            Append (Args, To_String (Compared.Old_Revision));
      end case;
   end Append_Comparison;

   procedure Append_Diff_Policy
     (Args : in out Argument_Vectors.Vector; Options : Capture_Options) is
   begin
      Append (Args, "--diff-algorithm=" & Algorithm_Name (Options.Algorithm));
      case Options.Whitespace is
         when Keep_Whitespace               =>
            null;

         when Ignore_All_Whitespace         =>
            Append (Args, "--ignore-all-space");

         when Ignore_Whitespace_Changes     =>
            Append (Args, "--ignore-space-change");

         when Ignore_End_Of_Line_Whitespace =>
            Append (Args, "--ignore-space-at-eol");
      end case;

      if Options.Detect_Copies then
         Append
           (Args, "--find-renames=" & Number_Image (Options.Similarity) & "%");
         Append
           (Args, "--find-copies=" & Number_Image (Options.Similarity) & "%");
         Append (Args, "--find-copies-harder");
      elsif Options.Detect_Renames then
         Append
           (Args, "--find-renames=" & Number_Image (Options.Similarity) & "%");
      else
         Append (Args, "--no-renames");
      end if;
   end Append_Diff_Policy;

   procedure Resolve_Tree
     (Repo     : Repository;
      Revision : String;
      Identity : out Unbounded_String;
      Error    : out Error_Info)
   is
      Args   : Argument_Vectors.Vector;
      Output : Unbounded_String;
   begin
      Append (Args, "rev-parse");
      Append (Args, "--verify");
      Append (Args, "--end-of-options");
      Append (Args, Revision & "^{tree}");
      Execute (Repo, Args, 1024 * 1024, "resolve revision", Output, Error);
      if Success (Error) then
         Identity := To_Unbounded_String (Trim_Line_End (To_String (Output)));
      else
         Set_Error
           (Error,
            Unresolved_Revision,
            "resolve revision",
            Detail (Error),
            Exit_Status (Error));
      end if;
   end Resolve_Tree;

   procedure Index_Fingerprint
     (Repo    : Repository;
      Options : Capture_Options;
      Value   : out Unbounded_String;
      Error   : out Error_Info)
   is
      Args    : Argument_Vectors.Vector;
      Output  : Unbounded_String;
      Content : Unbounded_String;
   begin
      Append (Args, "rev-parse");
      Append (Args, "--path-format=absolute");
      Append (Args, "--git-path");
      Append (Args, "index");
      Execute (Repo, Args, 1024 * 1024, "locate index", Output, Error);
      if not Success (Error) then
         return;
      end if;
      Read_File
        (Trim_Line_End (To_String (Output)),
         Options.Max_Content_Bytes,
         Content,
         Error);
      if Code (Error) = Filesystem_Error then
         Value := To_Unbounded_String ("missing-index");
         Error := (others => <>);
      elsif Success (Error) then
         Value := To_Unbounded_String (Digest (To_String (Content)));
      end if;
   end Index_Fingerprint;

   procedure Worktree_Fingerprint
     (Repo    : Repository;
      Name    : String;
      Options : Capture_Options;
      Value   : out Unbounded_String;
      Present : out Boolean)
   is
      Args   : Argument_Vectors.Vector;
      Output : Unbounded_String;
      Error  : Error_Info;
   begin
      Value := Null_Unbounded_String;
      Present := False;
      Append (Args, "hash-object");
      Append (Args, "--no-filters");
      Append (Args, "--");
      Append (Args, Name);
      Execute
        (Repo,
         Args,
         Options.Max_Output_Bytes,
         "fingerprint worktree",
         Output,
         Error);
      if Success (Error) then
         Value := To_Unbounded_String (Trim_Line_End (To_String (Output)));
         Present := Length (Value) > 0;
      end if;
   end Worktree_Fingerprint;

   procedure Start_Endpoints
     (Repo       : Repository;
      Compared   : Comparison;
      Options    : Capture_Options;
      Old_State  : out Endpoint_Info;
      New_State  : out Endpoint_Info;
      Index_Hash : out Unbounded_String;
      Error      : out Error_Info)
   is
      Tree_Id : Unbounded_String;
   begin
      Old_State := (others => <>);
      New_State := (others => <>);
      Index_Hash := Null_Unbounded_String;
      Error := (others => <>);
      case Compared.Comparison_Type is
         when Tree_To_Tree_Comparison      =>
            Resolve_Tree
              (Repo, To_String (Compared.Old_Revision), Tree_Id, Error);
            if not Success (Error) then
               return;
            end if;
            Old_State := (Tree_Endpoint, Compared.Old_Revision, Tree_Id);
            Resolve_Tree
              (Repo, To_String (Compared.New_Revision), Tree_Id, Error);
            if not Success (Error) then
               return;
            end if;
            New_State := (Tree_Endpoint, Compared.New_Revision, Tree_Id);

         when Tree_To_Index_Comparison     =>
            Resolve_Tree
              (Repo, To_String (Compared.Old_Revision), Tree_Id, Error);
            if not Success (Error) then
               return;
            end if;
            Old_State := (Tree_Endpoint, Compared.Old_Revision, Tree_Id);
            Index_Fingerprint (Repo, Options, Index_Hash, Error);
            if not Success (Error) then
               return;
            end if;
            New_State :=
              (Index_Endpoint, To_Unbounded_String ("index"), Index_Hash);

         when Index_To_Worktree_Comparison =>
            Index_Fingerprint (Repo, Options, Index_Hash, Error);
            if not Success (Error) then
               return;
            end if;
            Old_State :=
              (Index_Endpoint, To_Unbounded_String ("index"), Index_Hash);
            New_State :=
              (Worktree_Endpoint,
               To_Unbounded_String ("worktree"),
               Null_Unbounded_String);

         when Tree_To_Worktree_Comparison  =>
            Resolve_Tree
              (Repo, To_String (Compared.Old_Revision), Tree_Id, Error);
            if not Success (Error) then
               return;
            end if;
            Old_State := (Tree_Endpoint, Compared.Old_Revision, Tree_Id);
            Index_Fingerprint (Repo, Options, Index_Hash, Error);
            if not Success (Error) then
               return;
            end if;
            New_State :=
              (Worktree_Endpoint,
               To_Unbounded_String ("worktree"),
               Null_Unbounded_String);
      end case;
   end Start_Endpoints;

   function To_Kind (Value : Raw.Raw_Status) return Change_Kind
   is (case Value is
         when Raw.Status_Added        => Added,
         when Raw.Status_Copied       => Copied,
         when Raw.Status_Deleted      => Deleted,
         when Raw.Status_Modified     => Modified,
         when Raw.Status_Renamed      => Renamed,
         when Raw.Status_Type_Changed => Type_Changed,
         when Raw.Status_Unmerged     => Unmerged,
         when Raw.Status_Broken_Pair  => Broken_Pair,
         when Raw.Status_Unknown      => Unknown_Change);

   function Comparison_Key (Changes : Change_Set) return String
   is (Comparison_Kind'Image (Changes.Compared.Comparison_Type)
       & Character'Val (0)
       & To_String (Changes.Old_State.Resolved)
       & Character'Val (0)
       & To_String (Changes.New_State.Resolved));

   procedure Populate_File
     (Input   : String;
      Parsed  : Raw.Raw_Record;
      Changes : Change_Set;
      File    : out Stored_File)
   is
      Old_Mode    : constant String := Raw.Value (Input, Parsed.Old_Mode);
      New_Mode    : constant String := Raw.Value (Input, Parsed.New_Mode);
      Old_Obj     : constant String := Raw.Value (Input, Parsed.Old_Object);
      New_Obj     : constant String := Raw.Value (Input, Parsed.New_Object);
      First_Path  : constant String := Raw.Value (Input, Parsed.First_Path);
      Second_Path : constant String :=
        (if Parsed.Has_Second_Path
         then Raw.Value (Input, Parsed.Second_Path)
         else "");
      Zero_Old    : constant Boolean :=
        Git_Changes.Core.Validation.Is_All_Zero (Old_Obj);
      Zero_New    : constant Boolean :=
        Git_Changes.Core.Validation.Is_All_Zero (New_Obj);
   begin
      File := (others => <>);
      File.Delta_Kind := To_Kind (Parsed.Status);
      File.Old_Mode := To_Unbounded_String (Old_Mode);
      File.New_Mode := To_Unbounded_String (New_Mode);
      File.Old_Mode_Present := Old_Mode /= "000000";
      File.New_Mode_Present := New_Mode /= "000000";
      File.Old_Object := To_Unbounded_String (Old_Obj);
      File.New_Object := To_Unbounded_String (New_Obj);
      File.Old_Object_Present := not Zero_Old;
      File.New_Object_Present := not Zero_New;
      File.Score := Parsed.Score;
      File.Score_Present := Parsed.Score_Present;
      File.Submodule := Old_Mode = "160000" or else New_Mode = "160000";

      case Parsed.Status is
         when Raw.Status_Added                       =>
            File.New_Path := To_Unbounded_String (First_Path);
            File.New_Path_Present := True;

         when Raw.Status_Deleted                     =>
            File.Old_Path := To_Unbounded_String (First_Path);
            File.Old_Path_Present := True;

         when Raw.Status_Copied | Raw.Status_Renamed =>
            File.Old_Path := To_Unbounded_String (First_Path);
            File.New_Path := To_Unbounded_String (Second_Path);
            File.Old_Path_Present := True;
            File.New_Path_Present := True;

         when others                                 =>
            File.Old_Path := To_Unbounded_String (First_Path);
            File.New_Path := To_Unbounded_String (First_Path);
            File.Old_Path_Present := True;
            File.New_Path_Present := True;
      end case;

      File.Old_Content :=
        File.Old_Mode_Present
        and then File.Old_Object_Present
        and then not File.Submodule;
      File.New_Content :=
        File.New_Mode_Present
        and then (File.New_Object_Present
                  or else Kind (Changes.New_State) = Worktree_Endpoint)
        and then not File.Submodule;
   end Populate_File;

   procedure Append_File_Paths
     (Args : in out Argument_Vectors.Vector; File : Stored_File) is
   begin
      Append (Args, "--");
      if File.Old_Path_Present then
         Append (Args, To_String (File.Old_Path));
      end if;
      if File.New_Path_Present
        and then (not File.Old_Path_Present
                  or else File.New_Path /= File.Old_Path)
      then
         Append (Args, To_String (File.New_Path));
      end if;
   end Append_File_Paths;

   procedure Base_File_Diff
     (Args     : in out Argument_Vectors.Vector;
      Compared : Comparison;
      Options  : Capture_Options) is
   begin
      Append (Args, "diff");
      Append (Args, "--no-color");
      Append (Args, "--no-ext-diff");
      Append (Args, "--no-textconv");
      Append_Diff_Policy (Args, Options);
      Append_Comparison (Args, Compared);
   end Base_File_Diff;

   procedure Analyze_File
     (Repo     : Repository;
      Compared : Comparison;
      Options  : Capture_Options;
      File     : in out Stored_File;
      Error    : out Error_Info)
   is
      Args       : Argument_Vectors.Vector;
      Output     : Unbounded_String;
      Cursor     : Positive := 1;
      Header     : Hunks.Hunk;
      Result     : Hunks.Hunk_Result;
      Old_Last   : Natural := 0;
      New_Last   : Natural := 0;
      Range_Last : Natural;
      Valid      : Boolean;
      Item       : Stored_Span;

      procedure Select_Copy_Chunk
        (Whole : String; Selected : out Unbounded_String)
      is
         Raw_Cursor : Positive := 1;
         Raw_Item   : Raw.Raw_Record;
         Raw_Result : Raw.Parse_Result;
         Ordinal    : Natural := 0;
         Target     : Natural := 0;
         Scan       : Positive;
         Chunk_No   : Natural := 0;
         First      : Natural := 0;
         Last       : Natural := 0;
      begin
         Selected := Null_Unbounded_String;
         while Raw_Cursor <= Whole'Last and then Whole (Raw_Cursor) = ':' loop
            Raw.Parse_Next (Whole, Raw_Cursor, Raw_Item, Raw_Result);
            if Raw_Result /= Raw.Parsed then
               Set_Error
                 (Error,
                  Malformed_Backend_Output,
                  "correlate copy patch",
                  "malformed raw prefix in patch output");
               return;
            end if;
            Ordinal := Ordinal + 1;
            if Raw_Item.Status = Raw.Status_Copied then
               Target := Ordinal;
            end if;
         end loop;
         if Target = 0 then
            Set_Error
              (Error,
               Foreign_Backend_Violation,
               "correlate copy patch",
               "copy delta disappeared from path-scoped patch");
            return;
         end if;

         Scan := Raw_Cursor;
         while Scan <= Whole'Last loop
            if (Scan = Whole'First
                or else Whole (Scan - 1) = Character'Val (10)
                or else Whole (Scan - 1) = Character'Val (0))
              and then Whole'Last >= 11
              and then Scan <= Whole'Last - 10
              and then Whole (Scan .. Scan + 10) = "diff --git "
            then
               Chunk_No := Chunk_No + 1;
               if Chunk_No = Target then
                  First := Scan;
               elsif Chunk_No = Target + 1 then
                  Last := Scan - 1;
                  exit;
               end if;
            end if;
            Scan := Scan + 1;
         end loop;
         if First = 0 then
            Set_Error
              (Error,
               Foreign_Backend_Violation,
               "correlate copy patch",
               "copy patch chunk is missing");
            return;
         end if;
         if Last = 0 then
            Last := Whole'Last;
         end if;
         Selected := To_Unbounded_String (Whole (First .. Last));
      end Select_Copy_Chunk;

      procedure Validate_Content_Bounds
        (Which     : Side;
         Available : Boolean;
         Object    : Unbounded_String;
         Name      : Unbounded_String)
      is
         Content    : Unbounded_String;
         Load_Error : Error_Info;
         Git_Args   : Argument_Vectors.Vector;
         Lines      : Natural;
         Last_Line  : Natural;
         In_Range   : Boolean;
      begin
         if not Available or else File.Spans.Is_Empty then
            return;
         end if;
         if Length (Object) > 0 then
            Append (Git_Args, "cat-file");
            Append (Git_Args, "blob");
            Append (Git_Args, To_String (Object));
            Execute
              (Repo,
               Git_Args,
               Options.Max_Content_Bytes,
               "validate content bounds",
               Content,
               Load_Error);
         elsif Which = New_Side and then To_String (File.New_Mode) /= "120000"
         then
            declare
               Full_Name : Unbounded_String :=
                 To_Unbounded_String (Root_Path (Repo));
            begin
               if Length (Full_Name) > 0
                 and then Element (Full_Name, Length (Full_Name)) /= '/'
               then
                  Ada.Strings.Unbounded.Append (Full_Name, '/');
               end if;
               Ada.Strings.Unbounded.Append (Full_Name, Name);
               Read_File
                 (To_String (Full_Name),
                  Options.Max_Content_Bytes,
                  Content,
                  Load_Error);
            end;
         else
            return;
         end if;
         if not Success (Load_Error) then
            Error := Load_Error;
            return;
         end if;
         if Length (Content) = Natural'Last then
            Set_Error
              (Error,
               Resource_Limit,
               "validate content bounds",
               "content is too large for line accounting");
            return;
         end if;
         Lines := Git_Changes.Core.Validation.Line_Count (To_String (Content));
         for S of File.Spans loop
            declare
               R     : constant Changed_Span := S.Value;
               First : constant Natural :=
                 (if Which = Old_Side then R.Old_First else R.New_First);
               Count : constant Natural :=
                 (if Which = Old_Side then R.Old_Count else R.New_Count);
            begin
               if Count > 0 then
                  Git_Changes.Core.Validation.Checked_Last
                    (First, Count, Last_Line, In_Range);
                  if not In_Range or else Last_Line > Lines then
                     Set_Error
                       (Error,
                        Foreign_Backend_Violation,
                        "validate content bounds",
                        "Git hunk range exceeds captured content for "
                        & To_String (Name));
                     return;
                  end if;
               end if;
            end;
         end loop;
      end Validate_Content_Bounds;
   begin
      Error := (others => <>);
      if File.Submodule or else File.Delta_Kind in Unmerged | Broken_Pair then
         return;
      end if;

      Base_File_Diff (Args, Compared, Options);
      Append (Args, "--numstat");
      Append (Args, "-z");
      Append_File_Paths (Args, File);
      Execute
        (Repo,
         Args,
         Options.Max_Output_Bytes,
         "classify content",
         Output,
         Error);
      if not Success (Error) then
         return;
      end if;
      File.Binary :=
        Ada.Strings.Fixed.Index
          (To_String (Output),
           "-" & Character'Val (9) & "-" & Character'Val (9))
        > 0;
      if File.Binary then
         return;
      end if;

      Args.Clear;
      Base_File_Diff (Args, Compared, Options);
      Append (Args, "--unified=0");
      if File.Delta_Kind = Copied then
         Append (Args, "--raw");
         Append (Args, "-z");
         Append (Args, "--no-abbrev");
         Append (Args, "--patch");
      end if;
      Append_File_Paths (Args, File);
      Execute
        (Repo,
         Args,
         Options.Max_Output_Bytes,
         "load changed spans",
         Output,
         Error);
      if not Success (Error) then
         return;
      end if;

      declare
         Patch_Output : Unbounded_String := Output;
      begin
         if File.Delta_Kind = Copied then
            Select_Copy_Chunk (To_String (Output), Patch_Output);
            if not Success (Error) then
               return;
            end if;
         end if;
         declare
            Patch : constant String := To_String (Patch_Output);
         begin
            while Cursor <= Patch'Last loop
               Hunks.Parse_Next (Patch, Cursor, Header, Result);
               exit when Result = Hunks.No_More_Hunks;
               if Result = Hunks.Malformed_Hunk then
                  Set_Error
                    (Error,
                     Malformed_Backend_Output,
                     "parse hunk",
                     "malformed zero-context hunk header");
                  return;
               end if;

               if Header.Old_Lines.Count > 0 then
                  Git_Changes.Core.Validation.Checked_Last
                    (Header.Old_Lines.First,
                     Header.Old_Lines.Count,
                     Range_Last,
                     Valid);
                  if not Valid
                    or else (Old_Last > 0
                             and then Header.Old_Lines.First <= Old_Last)
                  then
                     Set_Error
                       (Error,
                        Foreign_Backend_Violation,
                        "validate hunk",
                        "overlapping or overflowing old range");
                     return;
                  end if;
                  Old_Last := Range_Last;
               end if;
               if Header.New_Lines.Count > 0 then
                  Git_Changes.Core.Validation.Checked_Last
                    (Header.New_Lines.First,
                     Header.New_Lines.Count,
                     Range_Last,
                     Valid);
                  if not Valid
                    or else (New_Last > 0
                             and then Header.New_Lines.First <= New_Last)
                  then
                     Set_Error
                       (Error,
                        Foreign_Backend_Violation,
                        "validate hunk",
                        "overlapping or overflowing new range");
                     return;
                  end if;
                  New_Last := Range_Last;
               end if;

               Item.Value :=
                 (Old_First => Header.Old_Lines.First,
                  Old_Count => Header.Old_Lines.Count,
                  New_First => Header.New_Lines.First,
                  New_Count => Header.New_Lines.Count);
               File.Spans.Append (Item);
            end loop;
         end;
      end;
      Validate_Content_Bounds
        (Old_Side,
         File.Old_Content,
         (if File.Old_Object_Present
          then File.Old_Object
          else Null_Unbounded_String),
         File.Old_Path);
      if not Success (Error) then
         return;
      end if;
      Validate_Content_Bounds
        (New_Side,
         File.New_Content,
         (if File.New_Object_Present
            and then Compared.Comparison_Type
                     not in Index_To_Worktree_Comparison
                          | Tree_To_Worktree_Comparison
          then File.New_Object
          else Null_Unbounded_String),
         File.New_Path);
   end Analyze_File;

   function Sort_Key (File : Stored_File) return String
   is (if File.New_Path_Present
       then To_String (File.New_Path)
       else To_String (File.Old_Path));
   function Before (Left, Right : Stored_File) return Boolean
   is (Sort_Key (Left) < Sort_Key (Right)
       or else (Sort_Key (Left) = Sort_Key (Right)
                and then To_String (Left.Old_Path)
                         < To_String (Right.Old_Path)));
   package Sorting is new File_Vectors.Generic_Sorting ("<" => Before);

   procedure Finalize_Identities (Changes : in out Change_Set) is
      Sep            : constant Character := Character'Val (0);
      Worktree_Input : Unbounded_String;
   begin
      if Changes.New_State.Endpoint_Type = Worktree_Endpoint then
         for File of Changes.Files loop
            Ada.Strings.Unbounded.Append
              (Worktree_Input, To_String (File.Worktree_Fingerprint));
            Ada.Strings.Unbounded.Append (Worktree_Input, Sep);
         end loop;
         Changes.New_State.Resolved :=
           To_Unbounded_String (Digest (To_String (Worktree_Input)));
      end if;

      for File of Changes.Files loop
         declare
            Input : constant String :=
              Comparison_Key (Changes)
              & Sep
              & Change_Kind'Image (File.Delta_Kind)
              & Sep
              & To_String (File.Old_Path)
              & Sep
              & To_String (File.New_Path)
              & Sep
              & To_String (File.Old_Mode)
              & Sep
              & To_String (File.New_Mode)
              & Sep
              & To_String (File.Old_Object)
              & Sep
              & To_String (File.New_Object)
              & Sep
              & To_String (File.Worktree_Fingerprint);
         begin
            File.Identifier := To_Unbounded_String (Digest (Input));
            for Span of File.Spans loop
               Span.Identifier :=
                 To_Unbounded_String
                   (Digest
                      (To_String (File.Identifier)
                       & Sep
                       & Span.Value.Old_First'Image
                       & ":"
                       & Span.Value.Old_Count'Image
                       & Sep
                       & Span.Value.New_First'Image
                       & ":"
                       & Span.Value.New_Count'Image));
            end loop;
         end;
      end loop;
   end Finalize_Identities;

   procedure Capture
     (Repository : Git_Changes.Repository;
      Comparison : Git_Changes.Comparison;
      Pathspecs  : Pathspec_Array;
      Options    : Capture_Options;
      Changes    : out Change_Set;
      Error      : out Error_Info)
   is
      Args         : Argument_Vectors.Vector;
      Output       : Unbounded_String;
      Cursor       : Positive := 1;
      Parsed       : Raw.Raw_Record;
      Result       : Raw.Parse_Result;
      File         : Stored_File;
      Index_Before : Unbounded_String;
      Index_After  : Unbounded_String;
      Local_Error  : Error_Info;
      Fingerprint  : Unbounded_String;
      Present      : Boolean;
   begin
      Changes :=
        (Repo     => Repository,
         Compared => Comparison,
         Limits   => Options,
         others   => <>);
      Error := (others => <>);
      if not Is_Open (Repository) then
         Set_Error
           (Error, Invalid_Repository, "capture", "repository is not open");
         return;
      end if;
      if Repository.Bare
        and then Comparison.Comparison_Type /= Tree_To_Tree_Comparison
      then
         Set_Error
           (Error,
            Unsupported_Comparison,
            "capture",
            "bare repositories support only tree-to-tree comparison");
         return;
      end if;

      Start_Endpoints
        (Repository,
         Comparison,
         Options,
         Changes.Old_State,
         Changes.New_State,
         Index_Before,
         Error);
      if not Success (Error) then
         return;
      end if;

      Append (Args, "diff");
      Append (Args, "--raw");
      Append (Args, "-z");
      Append (Args, "--no-abbrev");
      Append (Args, "--no-color");
      Append (Args, "--no-ext-diff");
      Append (Args, "--no-textconv");
      Append_Diff_Policy (Args, Options);
      Append_Comparison (Args, Comparison);
      Append (Args, "--");
      for Pathspec of Pathspecs loop
         Args.Append (Pathspec);
      end loop;
      Execute
        (Repository,
         Args,
         Options.Max_Output_Bytes,
         "capture file inventory",
         Output,
         Error);
      if not Success (Error) then
         return;
      end if;

      declare
         Raw_Output : constant String := To_String (Output);
      begin
         while Cursor <= Raw_Output'Last loop
            Raw.Parse_Next (Raw_Output, Cursor, Parsed, Result);
            if Result /= Raw.Parsed then
               Set_Error
                 (Error,
                  Malformed_Backend_Output,
                  "parse raw inventory",
                  Raw.Parse_Result'Image (Result) & " at byte" & Cursor'Image);
               return;
            end if;
            Populate_File (Raw_Output, Parsed, Changes, File);
            Changes.Files.Append (File);
         end loop;
      end;

      Sorting.Sort (Changes.Files);
      for J in 1 .. Natural (Changes.Files.Length) loop
         File := Changes.Files (J);
         if Changes.New_State.Endpoint_Type = Worktree_Endpoint
           and then (File.New_Path_Present or else File.Old_Path_Present)
         then
            Worktree_Fingerprint
              (Repository,
               (if File.New_Path_Present
                then To_String (File.New_Path)
                else To_String (File.Old_Path)),
               Options,
               Fingerprint,
               Present);
            if Present then
               File.Worktree_Fingerprint := Fingerprint;
               File.New_Content :=
                 not File.Submodule
                 and then To_String (File.New_Mode) /= "120000";
               if To_String (File.New_Mode) = "120000" then
                  File.Diagnostic :=
                    To_Unbounded_String
                      ("worktree symlink content is outside the portable adapter");
               end if;
            elsif not File.New_Path_Present then
               File.Worktree_Fingerprint := To_Unbounded_String ("absent");
               File.New_Content := False;
            else
               File.New_Content := False;
               File.Diagnostic :=
                 To_Unbounded_String
                   ("worktree content unavailable during capture");
               if not File.Submodule then
                  Changes.Stale := True;
               end if;
            end if;
         end if;
         Analyze_File (Repository, Comparison, Options, File, Local_Error);
         if not Success (Local_Error) then
            Error := Local_Error;
            return;
         end if;
         Changes.Files.Replace_Element (J, File);
      end loop;

      if Comparison.Comparison_Type
         in Tree_To_Index_Comparison
          | Index_To_Worktree_Comparison
          | Tree_To_Worktree_Comparison
      then
         Index_Fingerprint (Repository, Options, Index_After, Error);
         if not Success (Error) then
            return;
         end if;
         Changes.Stale := Changes.Stale or else Index_After /= Index_Before;
      end if;

      if Changes.New_State.Endpoint_Type = Worktree_Endpoint then
         for J in 1 .. Natural (Changes.Files.Length) loop
            File := Changes.Files (J);
            if Length (File.Worktree_Fingerprint) > 0 then
               Worktree_Fingerprint
                 (Repository,
                  (if File.New_Path_Present
                   then To_String (File.New_Path)
                   else To_String (File.Old_Path)),
                  Options,
                  Fingerprint,
                  Present);
               if (File.Worktree_Fingerprint = To_Unbounded_String ("absent")
                   and then Present)
                 or else (File.Worktree_Fingerprint
                          /= To_Unbounded_String ("absent")
                          and then (not Present
                                    or else Fingerprint
                                            /= File.Worktree_Fingerprint))
               then
                  Changes.Stale := True;
               end if;
            end if;
         end loop;
      end if;

      if Changes.Stale and then Options.Staleness = Fail_If_Stale then
         Set_Error
           (Error,
            Content_Changed,
            "capture",
            "index or worktree changed during capture");
         return;
      end if;
      Finalize_Identities (Changes);
   end Capture;

end Git_Changes.Backends.Git_CLI;
