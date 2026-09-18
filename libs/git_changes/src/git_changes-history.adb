with Git_Changes.Backends;

package body Git_Changes.History is
   use Ada.Strings.Unbounded;

   NUL : constant Character := Character'Val (0);
   HT  : constant Character := Character'Val (9);
   LF  : constant Character := Character'Val (10);

   Field_Count : constant := 7;

   --  One record per line, fields separated by tabs. Only the subject may
   --  contain a tab, and it is last, so the split is unambiguous.
   Format : constant String :=
     "--format=%H%x09%p%x09%h%x09%ad%x09%D%x09%an%x09%s";

   function Arg (Value : String) return Unbounded_String
   renames To_Unbounded_String;

   --  Every command runs literally: a revision or path byte string is never
   --  reinterpreted as a glob, whatever the repository's configuration.
   function Literal return Unbounded_String
   is (To_Unbounded_String ("--literal-pathspecs"));

   package Argument_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Unbounded_String);

   function Count (Item : Log) return Natural
   is (Natural (Item.Entries.Length));
   function Commit_Id (Item : Log; Number : Positive) return String
   is (To_String (Item.Entries (Number).Identity));
   function Parents (Item : Log; Number : Positive) return String
   is (To_String (Item.Entries (Number).Parent_List));
   function Abbreviated (Item : Log; Number : Positive) return String
   is (To_String (Item.Entries (Number).Short));
   function Commit_Date (Item : Log; Number : Positive) return String
   is (To_String (Item.Entries (Number).Date));
   function Author (Item : Log; Number : Positive) return Byte_String
   is (To_String (Item.Entries (Number).Wrote));
   function References (Item : Log; Number : Positive) return Byte_String
   is (To_String (Item.Entries (Number).Refs));
   function Subject (Item : Log; Number : Positive) return Byte_String
   is (To_String (Item.Entries (Number).Title));

   function Is_Merge (Item : Log; Number : Positive) return Boolean is
      Value : constant String := Parents (Item, Number);
   begin
      --  More than one parent, hence a separator between them.
      for C of Value loop
         if C = ' ' then
            return True;
         end if;
      end loop;
      return False;
   end Is_Merge;

   procedure Load
     (Repository : Git_Changes.Repository;
      Filter     : History.Filter := No_Filter;
      Options    : Capture_Options := Default_Options;
      Result     : out Log;
      Error      : out Error_Info)
   is
      Wanted : Argument_Vectors.Vector;
      Output : Unbounded_String;

      procedure Add (Value : String) is
      begin
         Wanted.Append (To_Unbounded_String (Value));
      end Add;
   begin
      Result := (Entries => Entry_Vectors.Empty_Vector);
      Wanted.Append (Literal);
      Add ("log");
      Add ("--date=short");
      Add ("--decorate=short");
      Add (Format);
      if Filter.Topological then
         Add ("--topo-order");
      end if;
      if Filter.All_Refs then
         Add ("--all");
      end if;
      if Filter.First_Parent then
         Add ("--first-parent");
      end if;
      if Length (Filter.Author) > 0 then
         Add ("--author=" & To_String (Filter.Author));
      end if;
      if Length (Filter.Since) > 0 then
         Add ("--since=" & To_String (Filter.Since));
      end if;
      if Length (Filter.Until_Date) > 0 then
         Add ("--until=" & To_String (Filter.Until_Date));
      end if;
      if Length (Filter.Message) > 0 then
         Add ("--grep=" & To_String (Filter.Message));
      end if;
      --  A revision can never be mistaken for an option, and a pathspec can
      --  never be mistaken for a revision.
      Add ("--end-of-options");
      if Length (Filter.Start) > 0 then
         Wanted.Append (Filter.Start);
      end if;
      Add ("--");
      if Length (Filter.Pathspec) > 0 then
         Wanted.Append (Filter.Pathspec);
      end if;

      declare
         Arguments :
           Git_Changes.Backends.Argument_Array (1 .. Natural (Wanted.Length));
      begin
         for J in Arguments'Range loop
            Arguments (J) := Wanted (J);
         end loop;
         Git_Changes.Backends.Run_Git
           (Root_Path (Repository),
            Arguments,
            Options.Max_Output_Bytes,
            "walk history",
            Output,
            Error);
      end;
      if not Success (Error) then
         return;
      end if;

      declare
         Raw   : constant String := To_String (Output);
         First : Positive := Raw'First;

         procedure Take (Line : String) is
            Bounds : array (1 .. Field_Count) of Natural := [others => 0];
            Found  : Natural := 0;
            Start  : constant Positive := Line'First;
         begin
            if Line'Length = 0 then
               return;
            end if;
            --  The first Field_Count - 1 tabs delimit the fields; whatever
            --  follows the last one is the subject, tabs included.
            for J in Line'Range loop
               exit when Found = Field_Count - 1;
               if Line (J) = HT then
                  Found := Found + 1;
                  Bounds (Found) := J;
               end if;
            end loop;
            if Found < Field_Count - 1 then
               return;
            end if;
            Result.Entries.Append
              (Log_Entry'
                 (Identity    =>
                    To_Unbounded_String (Line (Start .. Bounds (1) - 1)),
                  Parent_List =>
                    To_Unbounded_String
                      (Line (Bounds (1) + 1 .. Bounds (2) - 1)),
                  Short       =>
                    To_Unbounded_String
                      (Line (Bounds (2) + 1 .. Bounds (3) - 1)),
                  Date        =>
                    To_Unbounded_String
                      (Line (Bounds (3) + 1 .. Bounds (4) - 1)),
                  Refs        =>
                    To_Unbounded_String
                      (Line (Bounds (4) + 1 .. Bounds (5) - 1)),
                  Wrote       =>
                    To_Unbounded_String
                      (Line (Bounds (5) + 1 .. Bounds (6) - 1)),
                  Title       =>
                    To_Unbounded_String (Line (Bounds (6) + 1 .. Line'Last))));
         end Take;
      begin
         for J in Raw'Range loop
            if Raw (J) = LF then
               Take (Raw (First .. J - 1));
               First := J + 1;
            end if;
         end loop;
         if First <= Raw'Last then
            Take (Raw (First .. Raw'Last));
         end if;
      end;
   end Load;

   procedure Describe
     (Repository : Git_Changes.Repository;
      Revision   : String;
      Options    : Capture_Options := Default_Options;
      Author     : out Unbounded_String;
      Date       : out Unbounded_String;
      Message    : out Unbounded_String;
      Error      : out Error_Info)
   is
      --  NUL separates the fields because no author name, date or message
      --  can contain one: the message runs to the end of the output, so it
      --  keeps its own newlines without any escaping.
      Describe_Format : constant String := "--format=%an%x00%ad%x00%B";
      Output          : Unbounded_String;
      First, Second   : Natural := 0;
   begin
      Author := Null_Unbounded_String;
      Date := Null_Unbounded_String;
      Message := Null_Unbounded_String;
      Git_Changes.Backends.Run_Git
        (Root_Path (Repository),
         [Literal,
          Arg ("log"),
          Arg ("--max-count=1"),
          Arg ("--date=short"),
          Arg (Describe_Format),
          Arg ("--end-of-options"),
          Arg (Revision),
          Arg ("--")],
         Options.Max_Output_Bytes,
         "describe commit",
         Output,
         Error);
      if not Success (Error) then
         return;
      end if;
      declare
         Raw : constant String := To_String (Output);
      begin
         for J in Raw'Range loop
            if Raw (J) = NUL then
               if First = 0 then
                  First := J;
               else
                  Second := J;
                  exit;
               end if;
            end if;
         end loop;
         if Second = 0 then
            --  A revision Git described in a shape this parser does not
            --  know still yields its text, as the whole message.
            Message := Output;
            return;
         end if;
         Author := To_Unbounded_String (Raw (Raw'First .. First - 1));
         Date := To_Unbounded_String (Raw (First + 1 .. Second - 1));
         Message := To_Unbounded_String (Raw (Second + 1 .. Raw'Last));
      end;
   end Describe;

   procedure Show_Commit
     (Repository : Git_Changes.Repository;
      Revision   : String;
      Options    : Capture_Options := Default_Options;
      Text       : out Unbounded_String;
      Error      : out Error_Info) is
   begin
      Git_Changes.Backends.Run_Git
        (Root_Path (Repository),
         [Literal, Arg ("show"), Arg ("--end-of-options"), Arg (Revision)],
         Options.Max_Output_Bytes,
         "show commit",
         Text,
         Error);
   end Show_Commit;

end Git_Changes.History;
