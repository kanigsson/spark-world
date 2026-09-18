with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Whole-snapshot access: what a tree, the index, or the working tree
--  contains, and the bytes of any one path in it.
--
--  Contents answers for the files of a comparison; this package answers for
--  the files of a snapshot, changed or not. A reviewer reading a change
--  needs the definitions, callers, and tests that did not change, and those
--  are never in the change set.

package Git_Changes.Snapshots is

   --  Which state of the repository a query is about. A tree snapshot names
   --  any revision Git accepts; the index and the working tree name
   --  themselves.
   type Snapshot is private;
   function Tree (Revision : String) return Snapshot;
   function Index return Snapshot;
   function Worktree return Snapshot;
   function Kind (Item : Snapshot) return Endpoint_Kind;
   function Revision (Item : Snapshot) return String
   with Pre => Kind (Item) = Tree_Endpoint;

   --  The paths a snapshot contains, in Git's own order. Untracked paths
   --  appear only when they were asked for, and stay distinguishable: they
   --  are in the working tree but in no tree and no index.
   type Inventory is private;
   function Count (Item : Inventory) return Natural;
   function Path (Item : Inventory; Number : Positive) return Byte_String
   with Pre => Number <= Count (Item);
   function Is_Untracked (Item : Inventory; Number : Positive) return Boolean
   with Pre => Number <= Count (Item);

   --  List the snapshot's paths. Include_Untracked applies to a working-tree
   --  snapshot only, and honours the repository's ignore rules.
   procedure List
     (Repository        : Git_Changes.Repository;
      Snapshot          : Snapshots.Snapshot;
      Include_Untracked : Boolean := False;
      Options           : Capture_Options := Default_Options;
      Result            : out Inventory;
      Error             : out Error_Info)
   with Pre => Is_Open (Repository);

   --  The bytes of one path in the snapshot. A working-tree symbolic link
   --  yields its target rather than the bytes of whatever it points at: a
   --  read-only inspection must not follow a link out of the repository.
   procedure Load
     (Repository : Git_Changes.Repository;
      Snapshot   : Snapshots.Snapshot;
      Path       : Byte_String;
      Options    : Capture_Options := Default_Options;
      Content    : out Ada.Strings.Unbounded.Unbounded_String;
      Error      : out Error_Info)
   with Pre => Is_Open (Repository);

   --  A fixed-string content search over the snapshot, including files no
   --  comparison touched. Binary files are skipped.
   type Match_List is private;
   function Count (Item : Match_List) return Natural;
   function Path (Item : Match_List; Number : Positive) return Byte_String
   with Pre => Number <= Count (Item);
   function Line (Item : Match_List; Number : Positive) return Positive
   with Pre => Number <= Count (Item);
   function Text (Item : Match_List; Number : Positive) return Byte_String
   with Pre => Number <= Count (Item);

   procedure Search
     (Repository : Git_Changes.Repository;
      Snapshot   : Snapshots.Snapshot;
      Pattern    : Byte_String;
      Options    : Capture_Options := Default_Options;
      Result     : out Match_List;
      Error      : out Error_Info)
   with Pre => Is_Open (Repository);

private
   type Snapshot is record
      Snapshot_Type : Endpoint_Kind := Worktree_Endpoint;
      Named         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Listed_Path is record
      Name      : Ada.Strings.Unbounded.Unbounded_String;
      Untracked : Boolean := False;
   end record;
   package Path_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Listed_Path);
   type Inventory is record
      Paths : Path_Vectors.Vector;
   end record;

   type Located_Match is record
      Name   : Ada.Strings.Unbounded.Unbounded_String;
      Number : Positive := 1;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   package Match_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Located_Match);
   type Match_List is record
      Matches : Match_Vectors.Vector;
   end record;

end Git_Changes.Snapshots;
