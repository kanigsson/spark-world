with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Spark_Cli;

package body Gitignore is

   use type Glob_Re.Compile_Status;

   Punctuation : constant String := "\.^$|?*+()[]{}";
   --  The bytes the pattern language treats as operators outside a class.
   --  Everything else stands for itself and must not be escaped, since the
   --  language rejects escapes it does not recognize.

   function Escaped (C : Character) return String
   is (if (for some P of Punctuation => P = C) then ['\', C] else [1 => C]);

   function Is_Empty (Self : Rule_Set) return Boolean
   is (Self.Screens.Is_Empty);

   ---------------
   -- To_Regex  --
   ---------------

   function To_Regex (Glob : String) return String is
      Result   : Unbounded_String;
      Index    : Integer := Glob'First;
      Anchored : Boolean := False;

      function Double_Star_At (K : Integer) return Boolean
      is (K + 1 <= Glob'Last
          and then Glob (K) = '*'
          and then Glob (K + 1) = '*');

      procedure Append_Class is
         --  Copy one bracket expression. The two languages agree on ranges,
         --  on a literal ']' in first position and on backslash escapes; only
         --  the negation marker and a stray '^' need rewriting.
         Body_Text : Unbounded_String;
         Negated   : Boolean := False;
         K         : Integer := Index + 1;
      begin
         if K <= Glob'Last and then (Glob (K) = '!' or else Glob (K) = '^')
         then
            Negated := True;
            K := K + 1;
         end if;
         if K <= Glob'Last and then Glob (K) = ']' then
            Append (Body_Text, "\]");
            K := K + 1;
         end if;
         while K <= Glob'Last and then Glob (K) /= ']' loop
            if Glob (K) = '\' and then K < Glob'Last then
               Append (Body_Text, '\');
               Append (Body_Text, Glob (K + 1));
               K := K + 2;
            else
               if Glob (K) in '\' | '^' then
                  Append (Body_Text, '\');
               end if;
               Append (Body_Text, Glob (K));
               K := K + 1;
            end if;
         end loop;
         if K > Glob'Last then
            --  Unterminated, so the bracket stands for itself.
            Append (Result, "\[");
            Index := Index + 1;
         else
            Append
              (Result,
               "["
               & (if Negated then "^" else "")
               & To_String (Body_Text)
               & "]");
            Index := K + 1;
         end if;
      end Append_Class;

   begin
      --  A separator anywhere but at the end ties the glob to the directory
      --  holding the ignore file; otherwise it may match at any depth below.
      for K in Glob'Range loop
         if Glob (K) = '/' and then K < Glob'Last then
            Anchored := True;
         end if;
      end loop;

      Append (Result, "^");
      if Glob'Length > 0 and then Glob (Glob'First) = '/' then
         Index := Glob'First + 1;
      elsif not Anchored then
         Append (Result, "(.*/)?");
      end if;

      while Index <= Glob'Last loop
         if Glob (Index) = '\' and then Index < Glob'Last then
            Append (Result, Escaped (Glob (Index + 1)));
            Index := Index + 2;

         elsif Glob (Index) = '/' and then Double_Star_At (Index + 1) then
            --  A whole "**" segment spans any number of directories, so it
            --  absorbs the separators around it rather than one of them.
            if Index + 3 > Glob'Last then
               Append (Result, "/.*");
               Index := Index + 3;
            elsif Glob (Index + 3) = '/' then
               Append (Result, "/(.*/)?");
               Index := Index + 4;
            else
               Append (Result, "/");
               Index := Index + 1;
            end if;

         elsif Index = Glob'First
           and then Double_Star_At (Index)
           and then (Index + 2 > Glob'Last or else Glob (Index + 2) = '/')
         then
            if Index + 2 > Glob'Last then
               Append (Result, ".*");
               Index := Index + 2;
            else
               Append (Result, "(.*/)?");
               Index := Index + 3;
            end if;

         elsif Glob (Index) = '*' then
            Append (Result, "[^/]*");
            Index := Index + 1;

         elsif Glob (Index) = '?' then
            Append (Result, "[^/]");
            Index := Index + 1;

         elsif Glob (Index) = '[' then
            Append_Class;

         else
            Append (Result, Escaped (Glob (Index)));
            Index := Index + 1;
         end if;
      end loop;

      Append (Result, "$");
      return To_String (Result);
   end To_Regex;

   -----------------------
   -- Required_Literals --
   -----------------------

   procedure Required_Literals (Glob : String; Head, Tail : out Literal) is
      --  Every translation anchors the pattern at both ends of the path, so
      --  a run of bytes the glob emits literally is a run the path must
      --  carry. The leading run constrains the path only when the glob is
      --  tied to the directory holding the ignore file; without that tie the
      --  translation admits any number of leading components. The scan
      --  mirrors the translation above: it need only agree on which bytes
      --  stand for themselves, and breaking a run too early costs
      --  selectivity rather than correctness.
      Anchored   : Boolean := False;
      Seen_Break : Boolean := False;
      Run        : Literal;
      Index      : Integer := Glob'First;

      function Double_Star_At (K : Integer) return Boolean
      is (K + 1 <= Glob'Last
          and then Glob (K) = '*'
          and then Glob (K + 1) = '*');

      procedure Add_Byte (C : Character) is
      begin
         --  The trailing run needs the latest bytes and the leading run the
         --  earliest, so each keeps the end of its own that matters.
         if Run.Len < Max_Literal then
            Run.Len := Run.Len + 1;
         else
            Run.Text (1 .. Max_Literal - 1) := Run.Text (2 .. Max_Literal);
         end if;
         Run.Text (Run.Len) := C;

         if not Seen_Break and then Head.Len < Max_Literal then
            Head.Len := Head.Len + 1;
            Head.Text (Head.Len) := C;
         end if;
      end Add_Byte;

      procedure Break_Run is
      begin
         Seen_Break := True;
         Run.Len := 0;
      end Break_Run;

      procedure Skip_Class is
         --  Consume a bracket expression exactly as the translation does, so
         --  that its body never reaches a run.
         K : Integer := Index + 1;
      begin
         if K <= Glob'Last and then (Glob (K) = '!' or else Glob (K) = '^')
         then
            K := K + 1;
         end if;
         if K <= Glob'Last and then Glob (K) = ']' then
            K := K + 1;
         end if;
         while K <= Glob'Last and then Glob (K) /= ']' loop
            if Glob (K) = '\' and then K < Glob'Last then
               K := K + 2;
            else
               K := K + 1;
            end if;
         end loop;
         if K > Glob'Last then
            --  Unterminated, so the bracket stands for itself.
            Add_Byte ('[');
            Index := Index + 1;
         else
            Break_Run;
            Index := K + 1;
         end if;
      end Skip_Class;

   begin
      Head := (Text => [others => ' '], Len => 0);
      Tail := (Text => [others => ' '], Len => 0);

      for K in Glob'Range loop
         if Glob (K) = '/' and then K < Glob'Last then
            Anchored := True;
         end if;
      end loop;

      if Glob'Length > 0 and then Glob (Glob'First) = '/' then
         Index := Glob'First + 1;
      end if;

      while Index <= Glob'Last loop
         if Glob (Index) = '\' and then Index < Glob'Last then
            Add_Byte (Glob (Index + 1));
            Index := Index + 2;

         elsif Glob (Index) = '/' and then Double_Star_At (Index + 1) then
            --  A whole "**" segment keeps the separator before it and makes
            --  everything after it optional, so the separator is required
            --  and nothing beyond it is, until the next literal byte.
            Add_Byte ('/');
            if Index + 3 > Glob'Last then
               Break_Run;
               Index := Index + 3;
            elsif Glob (Index + 3) = '/' then
               Break_Run;
               Index := Index + 4;
            else
               Index := Index + 1;
            end if;

         elsif Index = Glob'First
           and then Double_Star_At (Index)
           and then (Index + 2 > Glob'Last or else Glob (Index + 2) = '/')
         then
            --  A leading "**" segment absorbs its own separator, which is
            --  therefore not required of the path.
            Break_Run;
            Index := (if Index + 2 > Glob'Last then Index + 2 else Index + 3);

         elsif Glob (Index) in '*' | '?' then
            Break_Run;
            Index := Index + 1;

         elsif Glob (Index) = '[' then
            Skip_Class;

         else
            Add_Byte (Glob (Index));
            Index := Index + 1;
         end if;
      end loop;

      Tail := Run;
      if not Anchored
        and then not (Glob'Length > 0 and then Glob (Glob'First) = '/')
      then
         Head.Len := 0;
      end if;
   end Required_Literals;

   ---------
   -- Add --
   ---------

   procedure Add
     (Self    : in out Rule_Set;
      Pattern : String;
      Status  : out Glob_Re.Compile_Status)
   is
      Last     : Integer := Pattern'Last;
      First    : Integer := Pattern'First;
      Negated  : Boolean := False;
      Dir_Only : Boolean := False;
   begin
      Status := Glob_Re.Success;

      --  Unescaped trailing blanks are not part of the pattern.
      while Last >= First and then Pattern (Last) = ' ' loop
         declare
            Slashes : Natural := 0;
         begin
            while Last - Slashes - 1 >= First
              and then Pattern (Last - Slashes - 1) = '\'
            loop
               Slashes := Slashes + 1;
            end loop;
            exit when Slashes mod 2 = 1;
            Last := Last - 1;
         end;
      end loop;

      if First > Last or else Pattern (First) = '#' then
         return;
      end if;

      if Pattern (First) = '!' then
         Negated := True;
         First := First + 1;
      end if;

      if Last >= First and then Pattern (Last) = '/' then
         Dir_Only := True;
         Last := Last - 1;
      end if;

      if First > Last then
         return;
      end if;

      declare
         New_Screen : Screen :=
           (Negated => Negated, Dir_Only => Dir_Only, others => <>);
         New_Code   : Glob_Re.Program;
      begin
         Glob_Re.Compile
           (To_Regex (Pattern (First .. Last)), New_Code, Status);
         if Status = Glob_Re.Success then
            Required_Literals
              (Pattern (First .. Last), New_Screen.Head, New_Screen.Tail);
            Self.Screens.Append (New_Screen);
            Self.Codes.Append (New_Code);
            if New_Screen.Tail.Len >= 2 then
               Self.Tail_Pairs
                 (New_Screen.Tail.Text (New_Screen.Tail.Len - 1),
                  New_Screen.Tail.Text (New_Screen.Tail.Len)) :=
                 True;
            else
               Self.Open.Append (Self.Screens.Last_Index);
            end if;
         end if;
      end;
   end Add;

   ----------
   -- Load --
   ----------

   procedure Load
     (Self : in out Rule_Set;
      Path : String;
      Warn : not null access procedure (Message : String))
   is
      package Files renames Ada.Streams.Stream_IO;
      File   : Files.File_Type;
      Number : Natural := 0;

      procedure Rule_Line (Record_Text : String; Stop : out Boolean) is
         Last   : Integer := Record_Text'Last;
         Status : Glob_Re.Compile_Status;
      begin
         Stop := False;
         Number := Number + 1;
         if Last >= Record_Text'First and then Record_Text (Last) = ASCII.CR
         then
            Last := Last - 1;
         end if;
         Add (Self, Record_Text (Record_Text'First .. Last), Status);
         if Status /= Glob_Re.Success then
            Warn
              (Path
               & ":"
               & Number'Image
               & ": unsupported ignore pattern ("
               & Status'Image
               & ")");
         end if;
      end Rule_Line;

   begin
      Files.Open (File, Files.In_File, Path);
      Spark_Cli.Read_Records (Files.Stream (File), ASCII.LF, Rule_Line'Access);
      Files.Close (File);
   exception
      when E : others =>
         if Files.Is_Open (File) then
            Files.Close (File);
         end if;
         Warn (Path & ": " & Ada.Exceptions.Exception_Message (E));
   end Load;

   -----------
   -- Match --
   -----------

   function Match
     (Self : Rule_Set; Rel_Path : String; Is_Dir : Boolean) return Decision
   is
      function Carries_Literals (S : Screen) return Boolean
      is (Rel_Path'Length >= S.Head.Len
          and then Rel_Path'Length >= S.Tail.Len
          and then Rel_Path (Rel_Path'First .. Rel_Path'First + S.Head.Len - 1)
                   = S.Head.Text (1 .. S.Head.Len)
          and then Rel_Path (Rel_Path'Last - S.Tail.Len + 1 .. Rel_Path'Last)
                   = S.Tail.Text (1 .. S.Tail.Len));
      --  A necessary condition that costs two comparisons and rejects most
      --  paths outright, which keeps the automaton off the traversal's hot
      --  path. An empty run compares equal and constrains nothing.

      function Verdict (K : Positive) return Decision is
         S : Screen renames Self.Screens (K);
      begin
         if (Is_Dir or else not S.Dir_Only)
           and then Carries_Literals (S)
           and then Glob_Re.Full_Match (Self.Codes (K), Rel_Path)
         then
            return (if S.Negated then Negated else Matched);
         else
            return No_Match;
         end if;
      end Verdict;

   begin
      --  The last applicable rule decides, so the first one found from the
      --  end decides, and no earlier rule need be examined at all. Skipping
      --  a rule that cannot apply is sound whatever the order, so the byte
      --  screen may remove rules from anywhere in the sequence without
      --  disturbing which of the rest comes last.
      if Rel_Path'Length >= 2
        and then not Self.Tail_Pairs
                       (Rel_Path (Rel_Path'Last - 1), Rel_Path (Rel_Path'Last))
      then
         for K of reverse Self.Open loop
            declare
               Found : constant Decision := Verdict (K);
            begin
               if Found /= No_Match then
                  return Found;
               end if;
            end;
         end loop;
         return No_Match;
      end if;

      declare
         K : Natural := Self.Screens.Last_Index;
      begin
         for S of reverse Self.Screens loop
            --  Written out rather than called, because this is the innermost
            --  test of the whole traversal and a screen is far too large to
            --  hand over once per rule per path.
            if (Is_Dir or else not S.Dir_Only)
              and then Rel_Path'Length >= S.Head.Len
              and then Rel_Path'Length >= S.Tail.Len
              and then Rel_Path
                         (Rel_Path'First .. Rel_Path'First + S.Head.Len - 1)
                       = S.Head.Text (1 .. S.Head.Len)
              and then Rel_Path
                         (Rel_Path'Last - S.Tail.Len + 1 .. Rel_Path'Last)
                       = S.Tail.Text (1 .. S.Tail.Len)
              and then Glob_Re.Full_Match (Self.Codes (K), Rel_Path)
            then
               return (if S.Negated then Negated else Matched);
            end if;
            K := K - 1;
         end loop;
      end;
      return No_Match;
   end Match;

end Gitignore;
