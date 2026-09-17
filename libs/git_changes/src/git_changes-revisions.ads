with Ada.Strings.Unbounded;

--  Revision resolution: turning what a user typed, or what a caller holds,
--  into the object names a comparison endpoint needs. These are queries
--  about names, not about changed content, so they stay out of the change
--  set: a caller resolves first and captures afterwards.
package Git_Changes.Revisions is

   --  Resolve one revision expression to its object name. The expression is
   --  passed to Git after an end-of-options marker, so a name that looks
   --  like an option is still read as a revision.
   procedure Resolve
     (Repository : Git_Changes.Repository;
      Expression : String;
      Identity   : out Ada.Strings.Unbounded.Unbounded_String;
      Error      : out Error_Info)
     with Pre => Is_Open (Repository);

   --  As Resolve, but peel to the commit the expression names, so that a
   --  tag or an annotated ref yields something a tree comparison accepts.
   procedure Resolve_Commit
     (Repository : Git_Changes.Repository;
      Expression : String;
      Identity   : out Ada.Strings.Unbounded.Unbounded_String;
      Error      : out Error_Info)
     with Pre => Is_Open (Repository);

   --  The first parent of a commit. Found is False for a root commit, which
   --  is not an error: callers compare those against the empty tree.
   procedure First_Parent
     (Repository : Git_Changes.Repository;
      Revision   : String;
      Parent     : out Ada.Strings.Unbounded.Unbounded_String;
      Found      : out Boolean;
      Error      : out Error_Info)
     with Pre => Is_Open (Repository);

   --  The empty tree of this repository's object format: the old endpoint
   --  that makes a root commit's own content its whole change set.
   procedure Empty_Tree
     (Repository : Git_Changes.Repository;
      Identity   : out Ada.Strings.Unbounded.Unbounded_String;
      Error      : out Error_Info)
     with Pre => Is_Open (Repository);

end Git_Changes.Revisions;
