with Git_Changes.Backends.Git_CLI;

package body Git_Changes is
   use Ada.Strings.Unbounded;

   function Is_Open (Item : Repository) return Boolean
   is (Item.Opened);
   function Root_Path (Item : Repository) return String
   is (To_String (Item.Root));
   function Git_Directory (Item : Repository) return String
   is (To_String (Item.Git_Dir));
   function Object_Format (Item : Repository) return String
   is (To_String (Item.Object_Format_Name));
   function Is_Bare (Item : Repository) return Boolean
   is (Item.Bare);

   function Kind (Item : Endpoint_Info) return Endpoint_Kind
   is (Item.Endpoint_Type);
   function Requested_Name (Item : Endpoint_Info) return String
   is (To_String (Item.Requested));
   function Resolved_Identity (Item : Endpoint_Info) return String
   is (To_String (Item.Resolved));

   function Tree_To_Tree (Old_Tree, New_Tree : String) return Comparison
   is (Comparison_Type => Tree_To_Tree_Comparison,
       Old_Revision    => To_Unbounded_String (Old_Tree),
       New_Revision    => To_Unbounded_String (New_Tree));
   function Tree_To_Index (Tree : String) return Comparison
   is (Comparison_Type => Tree_To_Index_Comparison,
       Old_Revision    => To_Unbounded_String (Tree),
       New_Revision    => Null_Unbounded_String);
   function Index_To_Worktree return Comparison
   is (Comparison_Type             => Index_To_Worktree_Comparison,
       Old_Revision | New_Revision => Null_Unbounded_String);
   function Tree_To_Worktree (Tree : String) return Comparison
   is (Comparison_Type => Tree_To_Worktree_Comparison,
       Old_Revision    => To_Unbounded_String (Tree),
       New_Revision    => Null_Unbounded_String);
   function Kind (Item : Comparison) return Comparison_Kind
   is (Item.Comparison_Type);

   function Code (Item : Error_Info) return Error_Code
   is (Item.Error_Type);
   function Operation (Item : Error_Info) return String
   is (To_String (Item.Op));
   function Detail (Item : Error_Info) return String
   is (To_String (Item.Message));
   function Exit_Status (Item : Error_Info) return Integer
   is (Item.Status);

   procedure Set_Error
     (Item    : out Error_Info;
      Kind    : Error_Code;
      Op      : String;
      Message : String;
      Status  : Integer := 0) is
   begin
      Item :=
        (Error_Type => Kind,
         Op         => To_Unbounded_String (Op),
         Message    => To_Unbounded_String (Message),
         Status     => Status);
   end Set_Error;

   procedure Capture
     (Repository : Git_Changes.Repository;
      Comparison : Git_Changes.Comparison;
      Options    : Capture_Options := Default_Options;
      Changes    : out Change_Set;
      Error      : out Error_Info) is
   begin
      Git_Changes.Backends.Git_CLI.Capture
        (Repository, Comparison, No_Pathspecs, Options, Changes, Error);
   end Capture;

   procedure Capture
     (Repository : Git_Changes.Repository;
      Comparison : Git_Changes.Comparison;
      Pathspecs  : Pathspec_Array;
      Options    : Capture_Options;
      Changes    : out Change_Set;
      Error      : out Error_Info) is
   begin
      Git_Changes.Backends.Git_CLI.Capture
        (Repository, Comparison, Pathspecs, Options, Changes, Error);
   end Capture;

   function Comparison_Used (Item : Change_Set) return Comparison_Kind
   is (Item.Compared.Comparison_Type);
   function Old_Endpoint (Item : Change_Set) return Endpoint_Info
   is (Item.Old_State);
   function New_Endpoint (Item : Change_Set) return Endpoint_Info
   is (Item.New_State);
   function Is_Stale (Item : Change_Set) return Boolean
   is (Item.Stale);
   function File_Count (Item : Change_Set) return Natural
   is (Natural (Item.Files.Length));

   function File_Kind (Item : Change_Set; File : Positive) return Change_Kind
   is (Item.Files (File).Delta_Kind);
   function File_Id (Item : Change_Set; File : Positive) return String
   is (To_String (Item.Files (File).Identifier));
   function Has_Path
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
   is (if Which = Old_Side
       then Item.Files (File).Old_Path_Present
       else Item.Files (File).New_Path_Present);
   function Path
     (Item : Change_Set; File : Positive; Which : Side) return Byte_String
   is (if Which = Old_Side
       then To_String (Item.Files (File).Old_Path)
       else To_String (Item.Files (File).New_Path));
   function Has_Mode
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
   is (if Which = Old_Side
       then Item.Files (File).Old_Mode_Present
       else Item.Files (File).New_Mode_Present);
   function Mode
     (Item : Change_Set; File : Positive; Which : Side) return String
   is (if Which = Old_Side
       then To_String (Item.Files (File).Old_Mode)
       else To_String (Item.Files (File).New_Mode));
   function Has_Object_Id
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
   is (if Which = Old_Side
       then Item.Files (File).Old_Object_Present
       else Item.Files (File).New_Object_Present);
   function Object_Id
     (Item : Change_Set; File : Positive; Which : Side) return String
   is (if Which = Old_Side
       then To_String (Item.Files (File).Old_Object)
       else To_String (Item.Files (File).New_Object));
   function Has_Similarity (Item : Change_Set; File : Positive) return Boolean
   is (Item.Files (File).Score_Present);
   function Similarity (Item : Change_Set; File : Positive) return Natural
   is (Item.Files (File).Score);
   function Is_Binary (Item : Change_Set; File : Positive) return Boolean
   is (Item.Files (File).Binary);
   function Is_Submodule (Item : Change_Set; File : Positive) return Boolean
   is (Item.Files (File).Submodule);
   function Content_Available
     (Item : Change_Set; File : Positive; Which : Side) return Boolean
   is (if Which = Old_Side
       then Item.Files (File).Old_Content
       else Item.Files (File).New_Content);
   function File_Diagnostic (Item : Change_Set; File : Positive) return String
   is (To_String (Item.Files (File).Diagnostic));
   function Span_Count (Item : Change_Set; File : Positive) return Natural
   is (Natural (Item.Files (File).Spans.Length));
   function Span
     (Item : Change_Set; File : Positive; Number : Positive)
      return Changed_Span
   is (Item.Files (File).Spans (Number).Value);
   function Span_Id
     (Item : Change_Set; File : Positive; Number : Positive) return String
   is (To_String (Item.Files (File).Spans (Number).Identifier));

end Git_Changes;
