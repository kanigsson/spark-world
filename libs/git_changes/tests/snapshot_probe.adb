--  Exercise the snapshot, history, and revision surfaces over a repository
--  supplied on the command line, printing one line per fact so a scenario
--  test can assert on them.

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Git_Changes;
with Git_Changes.History;
with Git_Changes.Repositories;
with Git_Changes.Revisions;
with Git_Changes.Snapshots;

procedure Snapshot_Probe is
   use Ada.Command_Line;
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Git_Changes;

   package S renames Git_Changes.Snapshots;
   package H renames Git_Changes.History;

   Repo  : Repository;
   Error : Error_Info;

   procedure Fail (Where : String) is
   begin
      Put_Line
        (Standard_Error,
         Where
         & ": "
         & Error_Code'Image (Code (Error))
         & ": "
         & Detail (Error));
      Set_Exit_Status (Failure);
   end Fail;
begin
   if Argument_Count /= 2 then
      Put_Line (Standard_Error, "usage: snapshot_probe REPOSITORY PATH");
      Set_Exit_Status (Failure);
      return;
   end if;
   Git_Changes.Repositories.Open (Argument (1), Repo, Error);
   if not Git_Changes.Success (Error) then
      Fail ("open");
      return;
   end if;
   Put_Line ("available=" & Git_Changes.Repositories.Available'Image);

   declare
      Head, Parent, Empty : Unbounded_String;
      Found               : Boolean;
   begin
      Git_Changes.Revisions.Resolve_Commit (Repo, "HEAD", Head, Error);
      if not Git_Changes.Success (Error) then
         Fail ("resolve");
         return;
      end if;
      Put_Line ("head=" & To_String (Head));
      Git_Changes.Revisions.First_Parent
        (Repo, To_String (Head), Parent, Found, Error);
      if not Git_Changes.Success (Error) then
         Fail ("first parent");
         return;
      end if;
      Put_Line ("parent=" & (if Found then To_String (Parent) else "none"));
      Git_Changes.Revisions.Empty_Tree (Repo, Empty, Error);
      if not Git_Changes.Success (Error) then
         Fail ("empty tree");
         return;
      end if;
      Put_Line ("empty-tree=" & To_String (Empty));

      for Which in Endpoint_Kind loop
         declare
            Snapshot  : constant S.Snapshot :=
              (case Which is
                 when Tree_Endpoint     => S.Tree (To_String (Head)),
                 when Index_Endpoint    => S.Index,
                 when Worktree_Endpoint => S.Worktree);
            Listing   : S.Inventory;
            Content   : Unbounded_String;
            Matches   : S.Match_List;
            Untracked : Natural := 0;
         begin
            S.List
              (Repo,
               Snapshot,
               Include_Untracked => True,
               Result            => Listing,
               Error             => Error);
            if not Git_Changes.Success (Error) then
               Fail ("list");
               return;
            end if;
            for J in 1 .. S.Count (Listing) loop
               if S.Is_Untracked (Listing, J) then
                  Untracked := Untracked + 1;
               end if;
            end loop;
            Put_Line
              (Endpoint_Kind'Image (Which)
               & " paths="
               & S.Count (Listing)'Image
               & " untracked="
               & Untracked'Image);
            S.Load
              (Repo,
               Snapshot,
               Argument (2),
               Content => Content,
               Error   => Error);
            if Git_Changes.Success (Error) then
               Put_Line
                 (Endpoint_Kind'Image (Which)
                  & " content="
                  & Length (Content)'Image);
            else
               Put_Line
                 (Endpoint_Kind'Image (Which)
                  & " content-error="
                  & Error_Code'Image (Code (Error)));
            end if;
            S.Search
              (Repo, Snapshot, "needle", Result => Matches, Error => Error);
            if not Git_Changes.Success (Error) then
               Fail ("search");
               return;
            end if;
            Put_Line
              (Endpoint_Kind'Image (Which)
               & " matches="
               & S.Count (Matches)'Image);
            for J in 1 .. S.Count (Matches) loop
               Put_Line
                 ("  match "
                  & S.Path (Matches, J)
                  & ":"
                  & S.Line (Matches, J)'Image
                  & ":"
                  & S.Text (Matches, J));
            end loop;
         end;
      end loop;
   end;

   declare
      Walk   : H.Log;
      Filter : H.Filter;
      Text   : Unbounded_String;
   begin
      Filter.Topological := True;
      H.Load (Repo, Filter, Result => Walk, Error => Error);
      if not Git_Changes.Success (Error) then
         Fail ("history");
         return;
      end if;
      Put_Line ("commits=" & H.Count (Walk)'Image);
      for J in 1 .. H.Count (Walk) loop
         Put_Line
           ("commit "
            & H.Abbreviated (Walk, J)
            & " "
            & H.Commit_Date (Walk, J)
            & " merge="
            & H.Is_Merge (Walk, J)'Image
            & " refs=["
            & H.References (Walk, J)
            & "]"
            & " author="
            & H.Author (Walk, J)
            & " parents=["
            & H.Parents (Walk, J)
            & "]"
            & " subject="
            & H.Subject (Walk, J));
      end loop;
      if H.Count (Walk) > 0 then
         H.Show_Commit
           (Repo, H.Commit_Id (Walk, 1), Text => Text, Error => Error);
         if not Git_Changes.Success (Error) then
            Fail ("show");
            return;
         end if;
         Put_Line ("patch-bytes=" & Length (Text)'Image);
         declare
            Who, When_Written, Message : Unbounded_String;
            Stop                       : Natural;
         begin
            H.Describe
              (Repo,
               H.Commit_Id (Walk, 1),
               Author  => Who,
               Date    => When_Written,
               Message => Message,
               Error   => Error);
            if not Git_Changes.Success (Error) then
               Fail ("describe");
               return;
            end if;
            Stop := Length (Message);
            for J in 1 .. Length (Message) loop
               if Element (Message, J) = Character'Val (10) then
                  Stop := J - 1;
                  exit;
               end if;
            end loop;
            Put_Line
              ("described="
               & To_String (Who)
               & "|"
               & To_String (When_Written)
               & "|"
               & Slice (Message, 1, Stop));
         end;
      end if;
      Filter.Pathspec := To_Unbounded_String (Argument (2));
      H.Load (Repo, Filter, Result => Walk, Error => Error);
      if not Git_Changes.Success (Error) then
         Fail ("scoped history");
         return;
      end if;
      Put_Line ("scoped-commits=" & H.Count (Walk)'Image);
   end;
end Snapshot_Probe;
