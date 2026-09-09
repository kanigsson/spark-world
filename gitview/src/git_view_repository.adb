with Ada.Calendar;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Git_Changes;
with Git_Changes.Contents;
with Git_Changes.History;
with Git_Changes.Repositories;
with Git_Changes.Revisions;
with Git_Changes.Snapshots;
with Git_View_Source;

package body Git_View_Repository with SPARK_Mode => Off is
   package G renames Git_Changes;
   use type G.Change_Kind;
   use type M.Snapshot_Kind;
   use type M.Change_Lens;
   use type M.Tree_Visibility;
   use type Ada.Containers.Count_Type;
   LF : constant Character := ASCII.LF;
   NUL : constant Character := ASCII.NUL;
   Repository_Root : Unbounded_String;
   --  Listings, histories, and search results of a large repository run well
   --  past the library's default output limit; content keeps its default.
   Query_Options : constant G.Capture_Options :=
     (Max_Output_Bytes => 64 * 1024 * 1024, others => <>);
   package Strings is new Ada.Containers.Vectors (Positive, Unbounded_String);
   package Targets is new Ada.Containers.Vectors (Positive, Row_Target);
   package Marks is new Ada.Containers.Vectors (Positive, Mark);
   package Paths is new Ada.Containers.Indefinite_Ordered_Sets (String);
   package Change_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Natural);
   type Buffer_Ref is access Tui.Text.Buffer;
   procedure Release is new Ada.Unchecked_Deallocation (Tui.Text.Buffer, Buffer_Ref);
   procedure Release is new Ada.Unchecked_Deallocation (Target_Array, Target_Ref);
   procedure Release is new Ada.Unchecked_Deallocation (Mark_Array, Mark_Ref);

   --  Every repository query reports failure the same way; the frame builder
   --  turns the exception into a notice rather than checking each call.
   procedure Check (Error : G.Error_Info) is
   begin
      if not G.Success (Error) then
         raise Program_Error with G.Detail (Error);
      end if;
   end Check;

   function Bounded (S : String) return M.Text is
   begin
      if S'Length > M.Max_Text then
         raise Constraint_Error with "path or revision exceeds 4096 bytes";
      end if;
      return M.To_Text (S);
   end Bounded;

   function Trim (S : String) return String is
     (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));

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

   --  Commit dates occupy a fixed six columns so that the subject always
   --  starts at the same place: day and month within the current year, month
   --  and abbreviated year before it. An unexpected shape is passed through.
   Current_Year : constant Natural :=
     Natural (Ada.Calendar.Year (Ada.Calendar.Clock));
   Month_Names : constant array (1 .. 12) of String (1 .. 3) :=
     ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
   function Compact_Date (S : String) return String is
      F : constant Natural := S'First;
      Year, Month : Natural;
   begin
      if S'Length /= 10 or else S (F + 4) /= '-' or else S (F + 7) /= '-' then
         return S;
      end if;
      Year := Natural'Value (S (F .. F + 3));
      Month := Natural'Value (S (F + 5 .. F + 6));
      if Month not in Month_Names'Range then
         return S;
      elsif Year = Current_Year then
         return Month_Names (Month) & " " & S (F + 8 .. F + 9);
      else
         return Month_Names (Month) & "'" & S (F + 2 .. F + 3);
      end if;
   exception
      when others => return S;
   end Compact_Date;

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
   Cached_Log_Key : Unbounded_String;
   Cached_Log : G.History.Log;
   Cached_Tree_Key : Unbounded_String;
   Cached_Tree : G.Snapshots.Inventory;
   Cached_Content_Key, Cached_Content : Unbounded_String;

   procedure Load (V : M.View_State; F : in out Frame) is
      Repo : G.Repository;
      Error : G.Error_Info;
      Target, Base, Root : Unbounded_String;
      --  Which state of the repository every path and content query is
      --  about; the comparison endpoints are derived from the same choice.
      Shot : G.Snapshots.Snapshot;
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
         Value : Unbounded_String;
         Local : G.Error_Info;
      begin
         --  A commit snapshot never changes under the reader, so the file
         --  last drawn is worth keeping: scrolling one file re-asks for it.
         if V.Kind = M.Commit then
            declare
               Key : constant Unbounded_String := Target & ":" & Path;
            begin
               if Cached_Content_Key /= Key then
                  G.Snapshots.Load (Repo, Shot, Path, Query_Options,
                                    Content => Value, Error => Local);
                  Check (Local);
                  Cached_Content := Value;
                  Cached_Content_Key := Key;
               end if;
               return To_String (Cached_Content);
            end;
         end if;
         G.Snapshots.Load (Repo, Shot, Path, Query_Options, Content => Value,
                           Error => Local);
         Check (Local);
         return To_String (Value);
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
               Check (Error);
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
      Check (Error);
      Root := To_Unbounded_String (G.Root_Path (Repo));
      if Root /= Repository_Root then
         Cache_Valid := False;
         Cached_Log_Key := Null_Unbounded_String;
         Cached_Tree_Key := Null_Unbounded_String;
         Cached_Content_Key := Null_Unbounded_String;
      end if;
      Repository_Root := Root;
      --  Every query runs relative to the repository root, even when the
      --  program was launched in a subdirectory: the handle carries the
      --  root, so the process working directory is never changed.
      if V.Kind = M.Commit then
         G.Revisions.Resolve_Commit
           (Repo, (if V.Snapshot.Last = 0 then "HEAD" else M.Image (V.Snapshot)),
            Target, Error);
         Check (Error);
         Shot := G.Snapshots.Tree (To_String (Target));
      elsif V.Kind = M.Worktree then
         Target := To_Unbounded_String ("worktree");
         Shot := G.Snapshots.Worktree;
      else
         Target := To_Unbounded_String ("index");
         Shot := G.Snapshots.Index;
      end if;
      if not V.Automatic_Base then Base := To_Unbounded_String (M.Image (V.Base));
      elsif V.Kind /= M.Commit then Base := To_Unbounded_String ("HEAD");
      else
         --  A root commit has no parent to compare against; the empty tree
         --  makes its own content the whole change.
         declare
            Found : Boolean;
         begin
            G.Revisions.First_Parent (Repo, To_String (Target), Base, Found, Error);
            Check (Error);
            if not Found then
               G.Revisions.Empty_Tree (Repo, Base, Error);
               Check (Error);
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
            Check (Error);
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
      declare
         Identity : Unbounded_String;
      begin
         G.Revisions.Resolve (Repo, To_String (Base), Identity, Error);
         Check (Error);
         F.Resolved_Base := Bounded (To_String (Identity));
      end;
      if G.Is_Stale (Cached_Changes) then F.Notice := Bounded ("comparison changed during capture; press r to refresh");
      else F.Notice := Bounded (""); end if;
      declare
         Filter : G.History.Filter;
         Source : Git_View_Source.Filters renames V.History_Filter;
         Key : Unbounded_String;
      begin
         Filter.Topological := True;
         Filter.All_Refs := Source.All_Refs;
         Filter.First_Parent := Source.First_Parent;
         if Source.Author.Len > 0 then
            Filter.Author := To_Unbounded_String (Git_View_Source.Image (Source.Author));
         end if;
         if Source.Since.Len > 0 then
            Filter.Since := To_Unbounded_String (Git_View_Source.Image (Source.Since));
         end if;
         if Source.Until_Date.Len > 0 then
            Filter.Until_Date := To_Unbounded_String (Git_View_Source.Image (Source.Until_Date));
         end if;
         if Source.Message.Len > 0 then
            Filter.Message := To_Unbounded_String (Git_View_Source.Image (Source.Message));
         end if;
         if V.History_Root.Len > 0 then
            Filter.Start := To_Unbounded_String (Git_View_Source.Image (V.History_Root));
         end if;
         if V.Path_Filter.Last > 0 then
            Filter.Pathspec := To_Unbounded_String (M.Image (V.Path_Filter));
         elsif Source.Path.Len > 0 then
            Filter.Pathspec := To_Unbounded_String (Git_View_Source.Image (Source.Path));
         end if;
         --  A walk is worth reusing only while every input to it is the one
         --  it was made with; NUL cannot occur in any of them.
         Key := Filter.Start & NUL & Filter.Author & NUL & Filter.Since & NUL
           & Filter.Until_Date & NUL & Filter.Message & NUL & Filter.Pathspec
           & NUL & Filter.All_Refs'Image & Filter.First_Parent'Image;
         if Key /= Cached_Log_Key or else V.Kind /= M.Commit then
            G.History.Load (Repo, Filter, Query_Options,
                            Result => Cached_Log, Error => Error);
            Check (Error);
            Cached_Log_Key := Key;
         end if;
         for I in 1 .. G.History.Count (Cached_Log) loop
            declare
               Refs : constant String := G.History.References (Cached_Log, I);
            begin
               History_Rows.Append
                 (Row_Target'(Bounded (G.History.Commit_Id (Cached_Log, I)), 1, False));
               --  The subject is the field the reader scans for, so it comes
               --  before the decorations: refs are long, rare, and repeated on
               --  the status line, and are the right thing to lose first when
               --  the pane is narrow.
               Append (H, (if G.History.Is_Merge (Cached_Log, I) then "M " else "  ")
                 & Label (G.History.Abbreviated (Cached_Log, I) & " "
                          & Compact_Date (G.History.Commit_Date (Cached_Log, I))
                          & " " & G.History.Subject (Cached_Log, I)
                          & (if Refs'Length = 0 then "" else " (" & Refs & ")"))
                 & " [parents: " & G.History.Parents (Cached_Log, I) & "]" & LF);
            end;
         end loop;
      end;
      declare
         Listing : G.Snapshots.Inventory;
      begin
         if V.Kind = M.Commit then
            if Target /= Cached_Tree_Key then
               G.Snapshots.List (Repo, Shot, Options => Query_Options,
                                 Result => Cached_Tree, Error => Error);
               Check (Error);
               Cached_Tree_Key := Target;
            end if;
            Listing := Cached_Tree;
         else
            G.Snapshots.List (Repo, Shot, Include_Untracked => V.Kind = M.Worktree,
                              Options => Query_Options, Result => Listing,
                              Error => Error);
            Check (Error);
         end if;
         for I in 1 .. G.Snapshots.Count (Listing) loop
            Inventory.Include (G.Snapshots.Path (Listing, I));
            if G.Snapshots.Is_Untracked (Listing, I) then
               Untracked_Paths.Include (G.Snapshots.Path (Listing, I));
            end if;
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
         declare
            Matches : G.Snapshots.Match_List;
         begin
            G.Snapshots.Search (Repo, Shot, M.Image (V.Repository_Search),
                                Query_Options, Result => Matches,
                                Error => Error);
            Check (Error);
            for I in 1 .. G.Snapshots.Count (Matches) loop
               declare
                  Path : constant String := G.Snapshots.Path (Matches, I);
                  Line : constant Positive := G.Snapshots.Line (Matches, I);
               begin
                  Add_Row (Path, Label (Path) & ":" & Trim (Line'Image) & ": "
                    & Label (G.Snapshots.Text (Matches, I)), Change (Path) > 0,
                    Tui.Text.Line_Number'Min (Line, Tui.Text.Line_Number'Last));
               end;
            end loop;
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
