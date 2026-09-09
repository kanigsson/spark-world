--  NOT SPARK: repository access, trusted behind the spec's contracts.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Git_Changes;
with Git_Changes.History;
with Git_Changes.Repositories;

package body Git_View_Source.OS with SPARK_Mode => Off is

   package G renames Git_Changes;

   type Content_Buffer is access Tui.Text.Buffer;

   procedure Free is
     new Ada.Unchecked_Deallocation (Tui.Text.Buffer, Content_Buffer);

   --  The staging buffer is heap allocated: a document-sized stack object
   --  overflows on long histories and large diffs.
   function Document (Value : String) return Tui.Text.Doc_Ref is
      Raw : Content_Buffer := new Tui.Text.Buffer (1 .. Value'Length);
      Result : Tui.Text.Doc_Ref;
   begin
      for K in Raw.all'Range loop
         Raw (K) := Character'Pos (Value (Value'First + (K - 1)));
      end loop;
      Result := Tui.Text.New_Document (Raw.all);
      Free (Raw);
      return Result;
   end Document;

   --------------
   -- Find_Git --
   --------------

   function Find_Git return Boolean is (G.Repositories.Available);

   --  The history walk runs before the alternate screen goes up, so its
   --  failure is worth explaining where the user can still read it — the
   --  backend's own words, as they used to reach the terminal directly.
   procedure Report (Error : G.Error_Info) is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "git_view: " & G.Detail (Error));
   exception
      when others => null;
   end Report;

   --  Open the repository the process was started in. Every query needs it,
   --  and none of them may change the process working directory.
   procedure Open (Repo : out G.Repository; Ok : out Boolean) is
      Error : G.Error_Info;
   begin
      G.Repositories.Open (".", Repo, Error);
      Ok := G.Success (Error);
      if not Ok then
         Report (Error);
      end if;
   end Open;

   ------------------
   -- Load_History --
   ------------------

   procedure Load_History
     (From   : Revision;
      Filter : Filters;
      Doc    : out Tui.Text.Doc_Ref;
      Ok     : out Boolean)
   is
      Repo    : G.Repository;
      Error   : G.Error_Info;
      Walk    : G.History.Log;
      Query   : G.History.Filter;
      Opened  : Boolean;
      Text    : Unbounded_String;
   begin
      Doc := null;
      Open (Repo, Opened);
      if not Opened then
         Ok := False;
         return;
      end if;
      Query.All_Refs := Filter.All_Refs;
      Query.First_Parent := Filter.First_Parent;
      if From.Len > 0 then
         Query.Start := To_Unbounded_String (Image (From));
      end if;
      if Filter.Author.Len > 0 then
         Query.Author := To_Unbounded_String (Image (Filter.Author));
      end if;
      if Filter.Since.Len > 0 then
         Query.Since := To_Unbounded_String (Image (Filter.Since));
      end if;
      if Filter.Until_Date.Len > 0 then
         Query.Until_Date := To_Unbounded_String (Image (Filter.Until_Date));
      end if;
      if Filter.Message.Len > 0 then
         Query.Message := To_Unbounded_String (Image (Filter.Message));
      end if;
      if Filter.Path.Len > 0 then
         Query.Pathspec := To_Unbounded_String (Image (Filter.Path));
      end if;

      G.History.Load (Repo, Query, Result => Walk, Error => Error);
      if not G.Success (Error) then
         Report (Error);
         Ok := False;
         return;
      end if;
      --  The abbreviated id stays the first space-terminated token of every
      --  line, and no line is ever a continuation: the proved commit-id
      --  parser reads exactly one commit per line.
      for I in 1 .. G.History.Count (Walk) loop
         declare
            Refs : constant String := G.History.References (Walk, I);
         begin
            Append (Text, G.History.Abbreviated (Walk, I) & " "
                    & G.History.Commit_Date (Walk, I)
                    & (if Refs'Length = 0 then "" else " [" & Refs & "]")
                    & " " & G.History.Author (Walk, I)
                    & " " & G.History.Subject (Walk, I) & ASCII.LF);
         end;
      end loop;
      Doc := Document (To_String (Text));
      Ok := Doc /= null;
   exception
      when others =>
         Doc := null;
         Ok := False;
   end Load_History;

   -----------------
   -- Load_Commit --
   -----------------

   procedure Load_Commit
     (Id  : String;
      Doc : out Tui.Text.Doc_Ref;
      Ok  : out Boolean)
   is
      Repo   : G.Repository;
      Error  : G.Error_Info;
      Text   : Unbounded_String;
      Opened : Boolean;
   begin
      Doc := null;
      Ok := False;
      Open (Repo, Opened);
      if not Opened then
         return;
      end if;
      G.History.Show_Commit (Repo, Id, Text => Text, Error => Error);
      Ok := G.Success (Error);
      --  Whatever the backend printed belongs in the pane: its own message
      --  beats a blank diff, and the alternate screen is already up.
      if not Ok and then Length (Text) = 0 then
         Text := To_Unbounded_String (G.Detail (Error));
      end if;
      if Length (Text) > 0 then
         Doc := Document (To_String (Text));
      end if;
   exception
      when others =>
         Doc := null;
         Ok := False;
   end Load_Commit;

end Git_View_Source.OS;
