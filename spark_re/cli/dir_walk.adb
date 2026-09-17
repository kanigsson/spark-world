with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNAT.Directory_Operations;
with GNAT.OS_Lib;
with Gitignore;

package body Dir_Walk is

   package Dir_Ops renames GNAT.Directory_Operations;
   use type Gitignore.Decision;

   Ignore_File : constant String := ".gitignore";

   package Name_Vectors is new
     Ada.Containers.Vectors (Positive, Unbounded_String);

   package Name_Sorting is new Name_Vectors.Generic_Sorting ("<" => "<");

   type Ignore_Level is record
      Rules       : Gitignore.Rule_Set;
      Base_Length : Natural := 0;
      --  Length of the path of the directory holding the file, relative to
      --  Root. Only the length is ever needed, to cut the same prefix off
      --  the candidate path, and it is needed once per entry of the tree.
   end record;

   package Level_Vectors is new
     Ada.Containers.Vectors (Positive, Ignore_Level);

   ----------
   -- Walk --
   ----------

   procedure Walk
     (Root    : String;
      Opts    : Options;
      Display : String;
      Visit   : not null access procedure (Path : String; Stop : out Boolean);
      Warn    : not null access procedure (Message : String))
   is
      Levels  : Level_Vectors.Vector;
      Stopped : Boolean := False;

      Root_Resolved : constant String :=
        (if Opts.Follow_Links
         then GNAT.OS_Lib.Normalize_Pathname (Root, Resolve_Links => True)
         else "");
      --  When links are followed they are resolved one component at a time
      --  against an already resolved parent, so a starting point that itself
      --  lies behind a link is followed rather than refused. Refusing them
      --  instead needs no resolution at all, only the question of whether
      --  one entry is a link, which is asked once per candidate directory.

      function Ignored (Rel_Path : String; Is_Dir : Boolean) return Boolean is
         --  Nearer ignore files override more distant ones, and within one
         --  file the last applicable rule decides.
         Result : Boolean := False;
      begin
         for Level of Levels loop
            if Rel_Path'Length > Level.Base_Length then
               case Gitignore.Match
                      (Level.Rules,
                       Rel_Path
                         (Rel_Path'First + Level.Base_Length .. Rel_Path'Last),
                       Is_Dir)
               is
                  when Gitignore.Matched  =>
                     Result := True;

                  when Gitignore.Negated  =>
                     Result := False;

                  when Gitignore.No_Match =>
                     null;
               end case;
            end if;
         end loop;
         return Result;
      end Ignored;

      procedure Descend (Rel_Dir : String; Resolved : String; Depth : Natural)
      is
         --  Rel_Dir is relative to Root and is empty or ends in a separator.
         Physical    : constant String := Root & "/" & Rel_Dir;
         --  Always ends in a separator, so entry names append directly.
         Pushed      : Boolean := False;
         Entries     : Name_Vectors.Vector;
         Search      : Dir_Ops.Dir_Type;
         Name_Buffer : String (1 .. 1024);
         Last        : Natural;
      begin
         if Opts.Respect_Ignore
           and then GNAT.OS_Lib.Is_Regular_File (Physical & Ignore_File)
         then
            declare
               Level : Ignore_Level;
            begin
               Gitignore.Load (Level.Rules, Physical & Ignore_File, Warn);
               if not Gitignore.Is_Empty (Level.Rules) then
                  Level.Base_Length := Rel_Dir'Length;
                  Levels.Append (Level);
                  Pushed := True;
               end if;
            end;
         end if;

         --  Collect and sort first, because directory order is not specified
         --  and the tool's output has to be reproducible. Reading names alone
         --  asks the file system nothing about them, so the entries excluded
         --  by name never cost an enquiry at all.
         begin
            Dir_Ops.Open (Search, Physical);
            loop
               Dir_Ops.Read (Search, Name_Buffer, Last);
               exit when Last = 0;
               declare
                  Name : String renames Name_Buffer (1 .. Last);
               begin
                  if Name /= "."
                    and then Name /= ".."
                    and then (Opts.Hidden or else Name (1) /= '.')
                    and then not (Opts.Respect_Ignore and then Name = ".git")
                  then
                     Entries.Append (To_Unbounded_String (Name));
                  end if;
               end;
            end loop;
            Dir_Ops.Close (Search);
         exception
            when others =>
               --  The exception carries only where it was raised, so the
               --  diagnostic says what the tool was doing instead.
               if Dir_Ops.Is_Open (Search) then
                  Dir_Ops.Close (Search);
               end if;
               Warn (Physical & ": cannot be read");
         end;
         Name_Sorting.Sort (Entries);

         for Item of Entries loop
            exit when Stopped or else Depth >= Opts.Max_Depth;
            declare
               Name     : constant String := To_String (Item);
               Rel_Path : constant String := Rel_Dir & Name;
               Full     : constant String := Physical & Name;
            begin
               if GNAT.OS_Lib.Is_Directory (Full) then
                  --  The ignore decision comes first, so a pruned subtree
                  --  costs nothing beyond the rules themselves.
                  if not Ignored (Rel_Path, Is_Dir => True)
                    and then Depth + 1 < Opts.Max_Depth
                  then
                     if not Opts.Follow_Links then
                        if not GNAT.OS_Lib.Is_Symbolic_Link (Full) then
                           Descend (Rel_Path & "/", "", Depth + 1);
                        end if;
                     else
                        declare
                           Child : constant String :=
                             GNAT.OS_Lib.Normalize_Pathname
                               (Resolved & "/" & Name, Resolve_Links => True);
                        begin
                           if Child /= "" then
                              Descend (Rel_Path & "/", Child, Depth + 1);
                           end if;
                        end;
                     end if;
                  end if;
               elsif not Ignored (Rel_Path, Is_Dir => False)
                 and then GNAT.OS_Lib.Is_Regular_File (Full)
               then
                  --  Asked last, because the ignore rules reject far more
                  --  entries than the file system does and cost less.
                  Visit (Display & Rel_Path, Stopped);
               end if;
            end;
         end loop;

         if Pushed then
            Levels.Delete_Last;
         end if;
      end Descend;

   begin
      Descend ("", (if Root_Resolved = "" then Root else Root_Resolved), 0);
   end Walk;

end Dir_Walk;
