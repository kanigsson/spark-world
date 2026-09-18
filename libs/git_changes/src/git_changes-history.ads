with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Commit history: the walk that tells a caller which snapshots exist and
--  how they are related, and the patch text of a single commit.
--
--  The fields are returned separately rather than as a preformatted line.
--  How a history reads on screen is the caller's decision; which commits it
--  contains is Git's.

package Git_Changes.History is

   --  A read-only history query. An empty text field means that filter is
   --  absent. Start names the revision to walk back from; empty means the
   --  current branch. Pathspec restricts the walk to commits touching one
   --  path, which is how history is scoped to a file or a subtree.
   type Filter is record
      Start        : Ada.Strings.Unbounded.Unbounded_String;
      Author       : Ada.Strings.Unbounded.Unbounded_String;
      Since        : Ada.Strings.Unbounded.Unbounded_String;
      Until_Date   : Ada.Strings.Unbounded.Unbounded_String;
      Message      : Ada.Strings.Unbounded.Unbounded_String;
      Pathspec     : Ada.Strings.Unbounded.Unbounded_String;
      All_Refs     : Boolean := False;
      First_Parent : Boolean := False;
      Topological  : Boolean := False;
   end record;

   No_Filter : constant Filter;

   type Log is private;
   function Count (Item : Log) return Natural;
   --  The full object name of the commit.
   function Commit_Id (Item : Log; Number : Positive) return String
   with Pre => Number <= Count (Item);
   --  The commit's parents, space separated in Git's order; empty for a
   --  root commit.
   function Parents (Item : Log; Number : Positive) return String
   with Pre => Number <= Count (Item);
   function Is_Merge (Item : Log; Number : Positive) return Boolean
   with Pre => Number <= Count (Item);
   function Abbreviated (Item : Log; Number : Positive) return String
   with Pre => Number <= Count (Item);
   --  Author date in ISO short form.
   function Commit_Date (Item : Log; Number : Positive) return String
   with Pre => Number <= Count (Item);
   function Author (Item : Log; Number : Positive) return Byte_String
   with Pre => Number <= Count (Item);
   --  Ref names pointing at this commit, comma separated; empty when none.
   function References (Item : Log; Number : Positive) return Byte_String
   with Pre => Number <= Count (Item);
   function Subject (Item : Log; Number : Positive) return Byte_String
   with Pre => Number <= Count (Item);

   procedure Load
     (Repository : Git_Changes.Repository;
      Filter     : History.Filter := No_Filter;
      Options    : Capture_Options := Default_Options;
      Result     : out Log;
      Error      : out Error_Info)
   with Pre => Is_Open (Repository);

   --  The message of one commit, with the author and date that identify
   --  it. The message is whatever Git stored, subject line first and body
   --  after it; how it reads on screen is the caller's decision. Empty
   --  outputs when the revision cannot be described, with Error saying so.
   procedure Describe
     (Repository : Git_Changes.Repository;
      Revision   : String;
      Options    : Capture_Options := Default_Options;
      Author     : out Ada.Strings.Unbounded.Unbounded_String;
      Date       : out Ada.Strings.Unbounded.Unbounded_String;
      Message    : out Ada.Strings.Unbounded.Unbounded_String;
      Error      : out Error_Info)
   with Pre => Is_Open (Repository);

   --  The patch text of one commit, as Git renders it. Text holds whatever
   --  Git wrote even when Error reports failure, so a caller can show the
   --  message it produced instead of inventing one.
   procedure Show_Commit
     (Repository : Git_Changes.Repository;
      Revision   : String;
      Options    : Capture_Options := Default_Options;
      Text       : out Ada.Strings.Unbounded.Unbounded_String;
      Error      : out Error_Info)
   with Pre => Is_Open (Repository);

private
   No_Filter : constant Filter := (others => <>);

   type Log_Entry is record
      Identity    : Ada.Strings.Unbounded.Unbounded_String;
      Parent_List : Ada.Strings.Unbounded.Unbounded_String;
      Short       : Ada.Strings.Unbounded.Unbounded_String;
      Date        : Ada.Strings.Unbounded.Unbounded_String;
      Refs        : Ada.Strings.Unbounded.Unbounded_String;
      Wrote       : Ada.Strings.Unbounded.Unbounded_String;
      Title       : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   package Entry_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Log_Entry);
   type Log is record
      Entries : Entry_Vectors.Vector;
   end record;

end Git_Changes.History;
