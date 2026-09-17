with Git_Changes.Backends;

package body Git_Changes.Revisions is
   use Ada.Strings.Unbounded;

   Query_Limit : constant Positive := 1024 * 1024;

   --  Every command runs literally: a revision or path byte string is never
   --  reinterpreted as a glob, whatever the repository's configuration.
   function Literal return Unbounded_String is
     (To_Unbounded_String ("--literal-pathspecs"));

   procedure Run
     (Repository : Git_Changes.Repository;
      Arguments  : Git_Changes.Backends.Argument_Array;
      Operation  : String;
      Output     : out Unbounded_String;
      Error      : out Error_Info) is
   begin
      Git_Changes.Backends.Run_Git
        (Root_Path (Repository), Arguments, Query_Limit, Operation, Output,
         Error);
   end Run;

   procedure Resolve_Expression
     (Repository : Git_Changes.Repository;
      Expression : String;
      Operation  : String;
      Identity   : out Unbounded_String;
      Error      : out Error_Info)
   is
      Output : Unbounded_String;
   begin
      Identity := Null_Unbounded_String;
      Run (Repository,
           [Literal,
            To_Unbounded_String ("rev-parse"),
            To_Unbounded_String ("--verify"),
            To_Unbounded_String ("--end-of-options"),
            To_Unbounded_String (Expression)],
           Operation, Output, Error);
      if not Success (Error) then
         Set_Error
           (Error, Unresolved_Revision, Operation, Detail (Error),
            Exit_Status (Error));
         return;
      end if;
      Identity :=
        To_Unbounded_String
          (Git_Changes.Backends.Trim_Line_End (To_String (Output)));
   end Resolve_Expression;

   procedure Resolve
     (Repository : Git_Changes.Repository;
      Expression : String;
      Identity   : out Unbounded_String;
      Error      : out Error_Info) is
   begin
      Resolve_Expression
        (Repository, Expression, "resolve revision", Identity, Error);
   end Resolve;

   procedure Resolve_Commit
     (Repository : Git_Changes.Repository;
      Expression : String;
      Identity   : out Unbounded_String;
      Error      : out Error_Info) is
   begin
      Resolve_Expression
        (Repository, Expression & "^{commit}", "resolve commit", Identity,
         Error);
   end Resolve_Commit;

   procedure First_Parent
     (Repository : Git_Changes.Repository;
      Revision   : String;
      Parent     : out Unbounded_String;
      Found      : out Boolean;
      Error      : out Error_Info)
   is
      Output : Unbounded_String;
   begin
      Parent := Null_Unbounded_String;
      Found := False;
      Run (Repository,
           [Literal,
            To_Unbounded_String ("rev-list"),
            To_Unbounded_String ("--parents"),
            To_Unbounded_String ("-n"),
            To_Unbounded_String ("1"),
            To_Unbounded_String ("--end-of-options"),
            To_Unbounded_String (Revision)],
           "list parents", Output, Error);
      if not Success (Error) then
         return;
      end if;
      --  The line is the commit followed by its parents, most recent lineage
      --  first; the token after the commit is the first parent.
      declare
         Line  : constant String :=
           Git_Changes.Backends.Trim_Line_End (To_String (Output));
         First : Natural := 0;
         Last  : Natural := Line'Last;
      begin
         for J in Line'Range loop
            if Line (J) = ' ' then
               First := J + 1;
               exit;
            end if;
         end loop;
         if First = 0 or else First > Line'Last then
            return;
         end if;
         for J in First .. Line'Last loop
            if Line (J) = ' ' then
               Last := J - 1;
               exit;
            end if;
         end loop;
         Parent := To_Unbounded_String (Line (First .. Last));
         Found := Length (Parent) > 0;
      end;
   end First_Parent;

   procedure Empty_Tree
     (Repository : Git_Changes.Repository;
      Identity   : out Unbounded_String;
      Error      : out Error_Info)
   is
      Output : Unbounded_String;
   begin
      Identity := Null_Unbounded_String;
      Run (Repository,
           [Literal,
            To_Unbounded_String ("hash-object"),
            To_Unbounded_String ("-t"),
            To_Unbounded_String ("tree"),
            To_Unbounded_String ("/dev/null")],
           "resolve empty tree", Output, Error);
      if not Success (Error) then
         return;
      end if;
      Identity :=
        To_Unbounded_String
          (Git_Changes.Backends.Trim_Line_End (To_String (Output)));
   end Empty_Tree;

end Git_Changes.Revisions;
