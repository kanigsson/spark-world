with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Git_Changes is

   package Strings renames Ada.Strings.Unbounded;
   subtype Byte_String is String;

   type Repository is private;
   function Is_Open (Item : Repository) return Boolean;
   function Root_Path (Item : Repository) return String
     with Pre => Is_Open (Item);
   function Git_Directory (Item : Repository) return String
     with Pre => Is_Open (Item);
   function Object_Format (Item : Repository) return String
     with Pre => Is_Open (Item);
   function Is_Bare (Item : Repository) return Boolean
     with Pre => Is_Open (Item);

   type Endpoint_Kind is (Tree_Endpoint, Index_Endpoint, Worktree_Endpoint);
   type Endpoint_Info is private;
   function Kind (Item : Endpoint_Info) return Endpoint_Kind;
   function Requested_Name (Item : Endpoint_Info) return String;
   function Resolved_Identity (Item : Endpoint_Info) return String;

   type Comparison_Kind is
     (Tree_To_Tree_Comparison,
      Tree_To_Index_Comparison,
      Index_To_Worktree_Comparison,
      Tree_To_Worktree_Comparison);
   type Comparison is private;
   function Tree_To_Tree (Old_Tree, New_Tree : String) return Comparison;
   function Tree_To_Index (Tree : String) return Comparison;
   function Index_To_Worktree return Comparison;
   function Tree_To_Worktree (Tree : String) return Comparison;
   function Kind (Item : Comparison) return Comparison_Kind;

   type Diff_Algorithm is (Myers, Minimal, Patience, Histogram);
   type Whitespace_Policy is
     (Keep_Whitespace, Ignore_All_Whitespace, Ignore_Whitespace_Changes,
      Ignore_End_Of_Line_Whitespace);
   type Stale_Policy is (Mark_Stale, Fail_If_Stale);

   type Capture_Options is record
      Detect_Renames    : Boolean := True;
      Detect_Copies     : Boolean := False;
      Similarity        : Natural range 0 .. 100 := 50;
      Algorithm         : Diff_Algorithm := Myers;
      Whitespace        : Whitespace_Policy := Keep_Whitespace;
      Max_Output_Bytes  : Positive := 16 * 1024 * 1024;
      Max_Content_Bytes : Positive := 64 * 1024 * 1024;
      Staleness         : Stale_Policy := Mark_Stale;
   end record;

   Default_Options : constant Capture_Options := (others => <>);
   type Pathspec_Array is
     array (Positive range <>) of Strings.Unbounded_String;
   No_Pathspecs : constant Pathspec_Array (1 .. 0) := [];

   type Error_Code is
     (No_Error,
      Invalid_Repository,
      Unsupported_Comparison,
      Unresolved_Revision,
      Git_Command_Failed,
      Malformed_Backend_Output,
      Unsupported_Delta,
      Content_Unavailable,
      Content_Changed,
      Resource_Limit,
      Foreign_Backend_Violation,
      Filesystem_Error);

   type Error_Info is private;
   function Code (Item : Error_Info) return Error_Code;
   function Operation (Item : Error_Info) return String;
   function Detail (Item : Error_Info) return String;
   function Exit_Status (Item : Error_Info) return Integer;
   function Success (Item : Error_Info) return Boolean is
     (Code (Item) = No_Error);

   type Change_Kind is
     (Added,
      Deleted,
      Modified,
      Renamed,
      Copied,
      Type_Changed,
      Unmerged,
      Broken_Pair,
      Unknown_Change);
   type Side is (Old_Side, New_Side);

   type Changed_Span is record
      Old_First : Natural := 1;
      Old_Count : Natural := 1;
      New_First : Natural := 1;
      New_Count : Natural := 1;
   end record
     with Dynamic_Predicate =>
       (Changed_Span.Old_Count > 0 or else Changed_Span.New_Count > 0)
       and then
       (if Changed_Span.Old_Count > 0 then Changed_Span.Old_First > 0)
       and then
       (if Changed_Span.New_Count > 0 then Changed_Span.New_First > 0);

   type Change_Set is private;

   procedure Capture
     (Repository : Git_Changes.Repository;
      Comparison : Git_Changes.Comparison;
      Options    : Capture_Options := Default_Options;
      Changes    : out Change_Set;
      Error      : out Error_Info);

   procedure Capture
     (Repository : Git_Changes.Repository;
      Comparison : Git_Changes.Comparison;
      Pathspecs  : Pathspec_Array;
      Options    : Capture_Options;
      Changes    : out Change_Set;
      Error      : out Error_Info);

   function Comparison_Used (Item : Change_Set) return Comparison_Kind;
   function Old_Endpoint (Item : Change_Set) return Endpoint_Info;
   function New_Endpoint (Item : Change_Set) return Endpoint_Info;
   function Is_Stale (Item : Change_Set) return Boolean;
   function File_Count (Item : Change_Set) return Natural;

   function File_Kind (Item : Change_Set; File : Positive) return Change_Kind
     with Pre => File <= File_Count (Item);
   function File_Id (Item : Change_Set; File : Positive) return String
     with Pre => File <= File_Count (Item);
   function Has_Path
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
     with Pre => File <= File_Count (Item);
   function Path
     (Item : Change_Set; File : Positive; Which : Side) return Byte_String
     with Pre => File <= File_Count (Item)
       and then Has_Path (Item, File, Which);
   function Has_Mode
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
     with Pre => File <= File_Count (Item);
   function Mode
     (Item : Change_Set; File : Positive; Which : Side) return String
     with Pre => File <= File_Count (Item)
       and then Has_Mode (Item, File, Which);
   function Has_Object_Id
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
     with Pre => File <= File_Count (Item);
   function Object_Id
     (Item : Change_Set; File : Positive; Which : Side) return String
     with Pre => File <= File_Count (Item)
       and then Has_Object_Id (Item, File, Which);
   function Has_Similarity (Item : Change_Set; File : Positive) return Boolean
     with Pre => File <= File_Count (Item);
   function Similarity (Item : Change_Set; File : Positive) return Natural
     with Pre => File <= File_Count (Item)
       and then Has_Similarity (Item, File);
   function Is_Binary (Item : Change_Set; File : Positive) return Boolean
     with Pre => File <= File_Count (Item);
   function Is_Submodule (Item : Change_Set; File : Positive) return Boolean
     with Pre => File <= File_Count (Item);
   function Content_Available
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
     with Pre => File <= File_Count (Item);
   function File_Diagnostic (Item : Change_Set; File : Positive) return String
     with Pre => File <= File_Count (Item);

   function Span_Count (Item : Change_Set; File : Positive) return Natural
     with Pre => File <= File_Count (Item);
   function Span
     (Item : Change_Set; File : Positive; Number : Positive)
      return Changed_Span
     with Pre => File <= File_Count (Item)
       and then Number <= Span_Count (Item, File);
   function Span_Id
     (Item : Change_Set; File : Positive; Number : Positive) return String
     with Pre => File <= File_Count (Item)
       and then Number <= Span_Count (Item, File);

private
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Repository is record
      Opened        : Boolean := False;
      Root          : UString;
      Git_Dir       : UString;
      Object_Format_Name : UString;
      Bare          : Boolean := False;
   end record;

   type Endpoint_Info is record
      Endpoint_Type : Endpoint_Kind := Worktree_Endpoint;
      Requested     : UString;
      Resolved      : UString;
   end record;

   type Comparison is record
      Comparison_Type : Comparison_Kind := Tree_To_Worktree_Comparison;
      Old_Revision     : UString;
      New_Revision     : UString;
   end record;

   type Error_Info is record
      Error_Type : Error_Code := No_Error;
      Op         : UString;
      Message    : UString;
      Status     : Integer := 0;
   end record;

   type Stored_Span is record
      Value      : Changed_Span :=
        (Old_First => 1, Old_Count => 1, New_First => 1, New_Count => 1);
      Identifier : UString;
   end record;
   package Span_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Stored_Span);

   type Stored_File is record
      Identifier       : UString;
      Delta_Kind       : Change_Kind := Modified;
      Old_Path         : UString;
      New_Path         : UString;
      Old_Path_Present : Boolean := False;
      New_Path_Present : Boolean := False;
      Old_Mode         : UString;
      New_Mode         : UString;
      Old_Mode_Present : Boolean := False;
      New_Mode_Present : Boolean := False;
      Old_Object       : UString;
      New_Object       : UString;
      Old_Object_Present : Boolean := False;
      New_Object_Present : Boolean := False;
      Score            : Natural range 0 .. 100 := 0;
      Score_Present    : Boolean := False;
      Binary           : Boolean := False;
      Submodule        : Boolean := False;
      Old_Content      : Boolean := False;
      New_Content      : Boolean := False;
      Diagnostic       : UString;
      Worktree_Fingerprint : UString;
      Spans            : Span_Vectors.Vector;
   end record;
   package File_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Stored_File);

   type Change_Set is record
      Repo       : Repository;
      Compared   : Comparison;
      Old_State  : Endpoint_Info;
      New_State  : Endpoint_Info;
      Stale      : Boolean := False;
      Limits     : Capture_Options := Default_Options;
      Files      : File_Vectors.Vector;
   end record;

   procedure Set_Error
     (Item    : out Error_Info;
      Kind    : Error_Code;
      Op      : String;
      Message : String;
      Status  : Integer := 0);

end Git_Changes;
