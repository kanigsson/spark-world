with Ada.Command_Line;      use Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with System.Multiprocessors;
with Dir_Walk;
with Gitignore;
with Regex;
with Spark_Cli;

--  A recursive front end over the same regex kernel as spark-grep: it finds
--  the files itself instead of being handed them, honouring gitignore files
--  the way ripgrep does. Like spark-grep it is deliberately a named subset,
--  not a drop-in replacement.

procedure Spark_Rg is
   use type Regex.Compile_Status;
   use type Gitignore.Decision;
   use type Ada.Directories.File_Kind;
   package IO renames Ada.Text_IO;
   package Files renames Ada.Streams.Stream_IO;

   Pattern                               : Unbounded_String;
   Have_Pattern, End_Options             : Boolean := False;
   Numbered                              : Boolean := True;
   Invert, Count_Only, Quiet, List_Files : Boolean := False;
   Hide_Name, Whole, Fixed               : Boolean := False;
   Scan_Binary                           : Boolean := False;
   Delimiter                             : Character := ASCII.LF;
   Walk_Options                          : Dir_Walk.Options;
   Globs                                 : Gitignore.Rule_Set;
   Have_Positive_Glob                    : Boolean := False;
   Path_Args                             :
     array (1 .. Argument_Count) of Natural := [others => 0];
   Path_Count                            : Natural := 0;
   Code                                  : Regex.Program;
   Status                                : Regex.Compile_Status;
   Any_Selected, Had_Error, Finished     : Boolean := False;
   Index                                 : Positive := 1;

   Default_Jobs : constant Positive :=
     Positive'Min (16, Positive (System.Multiprocessors.Number_Of_CPUs));
   --  Scanning scales with the core count until the file system rather than
   --  the processor sets the pace; past that a larger crew only contends.
   Jobs         : Positive := Default_Jobs;

   procedure Error (Message : String) is
   begin
      IO.Put_Line (IO.Standard_Error, "spark-rg: " & Message);
      Had_Error := True;
      Set_Exit_Status (2);
   end Error;

   procedure Warn (Message : String) is
   begin
      IO.Put_Line (IO.Standard_Error, "spark-rg: " & Message);
   end Warn;

   procedure Help is
   begin
      IO.Put_Line ("Usage: spark-rg [OPTIONS] PATTERN [PATH ...]");
      IO.Put_Line
        ("Recursive byte-oriented extended regex search; PATH defaults to '.'.");
      IO.Put_Line
        ("Directories are searched recursively, honouring .gitignore files.");
      IO.Put_Line
        ("-E extended regex (default), -F literal, -e PATTERN (one only)");
      IO.Put_Line
        ("-n record numbers (default), -N no numbers, -v invert, -x whole record");
      IO.Put_Line
        ("-c count, -q quiet, -l file names, -h hide names, -H show names");
      IO.Put_Line
        ("-z NUL records, -g GLOB filter paths (repeatable, !GLOB excludes)");
      IO.Put_Line
        ("--no-ignore, --hidden, -L/--follow, --max-depth N, --binary");
      IO.Put_Line
        ("-j N/--threads N search N files at once (default: cores, max 16)");
      IO.Put_Line
        ("-- ends options; --help; --version. Unknown options are errors.");
      IO.Put_Line ("No locale/Unicode folding, backreferences or lookaround.");
      IO.Put_Line
        ("Exit: 0 selected records, 1 none, 2 error. Output records end in delimiter.");
   end Help;

   procedure Set_Pattern (Value : String) is
   begin
      if Have_Pattern then
         Error ("multiple patterns are not supported");
      else
         Pattern := To_Unbounded_String (Value);
         Have_Pattern := True;
      end if;
   end Set_Pattern;

   procedure Add_Glob (Value : String) is
      Glob_Status : Gitignore.Glob_Re.Compile_Status;
   begin
      Gitignore.Add (Globs, Value, Glob_Status);
      if Glob_Status /= Gitignore.Glob_Re.Success then
         Error ("glob: " & Value & " (" & Glob_Status'Image & ")");
      elsif Value'Length = 0 or else Value (Value'First) /= '!' then
         Have_Positive_Glob := True;
      end if;
   end Add_Glob;

   function Image (N : Natural) return String is
      S : constant String := N'Image;
   begin
      return S (S'First + 1 .. S'Last);
   end Image;

   procedure Write (Value : String) is
   begin
      String'Write (IO.Text_Streams.Stream (IO.Standard_Output), Value);
   end Write;

   function Selected_By_Globs (Path : String) return Boolean is
      --  Explicit globs are matched against the path as it is reported. A
      --  negation always wins; otherwise positive globs, when any were given,
      --  restrict the search to what they select.
      Verdict : constant Gitignore.Decision :=
        Gitignore.Match (Globs, Path, Is_Dir => False);
   begin
      if Verdict = Gitignore.Negated then
         return False;
      elsif Have_Positive_Glob then
         return Verdict = Gitignore.Matched;
      else
         return True;
      end if;
   end Selected_By_Globs;

   function Looks_Binary (Name : String) return Boolean is
      --  The same heuristic as the usual tools: a NUL byte near the start.
      use Ada.Streams;
      File   : Files.File_Type;
      Buffer : Stream_Element_Array (1 .. 8_192);
      Last   : Stream_Element_Offset;
   begin
      Files.Open (File, Files.In_File, Name);
      Files.Read (File, Buffer, Last);
      Files.Close (File);
      return (for some K in 1 .. Last => Buffer (K) = 0);
   exception
      when others =>
         if Files.Is_Open (File) then
            Files.Close (File);
         end if;
         return False;
   end Looks_Binary;

   procedure Process_Input is
      --  What scanning one input produced, buffered rather than written, so
      --  that the work can happen away from the output stream and the result
      --  still reach it in traversal order.
      type Outcome is record
         Text     : Unbounded_String;
         Errors   : Unbounded_String;
         Selected : Boolean := False;
         Failed   : Boolean := False;
         Halt     : Boolean := False;
         --  The whole search is finished, which only a quiet run reports.
      end record;

      Slot_Count : constant := 64;
      --  Inputs in flight. It bounds memory rather than throughput: the
      --  queue only has to stay ahead of the workers, and a scan that
      --  outruns the traversal blocks until the oldest result is written.
      subtype Slot_Index is Natural range 0 .. Slot_Count - 1;

      type Slot is record
         Ready  : Boolean := False;
         Path   : Unbounded_String;
         Result : Outcome;
      end record;

      type Slot_Ring is array (Slot_Index) of Slot;

      protected Pipeline is
         --  One bounded ring carries paths out to the workers and results
         --  back, in the order the traversal produced them. Slots are filled,
         --  claimed and drained by three separate counters over the same
         --  ring, so a result is written only once every earlier one has
         --  been, whichever worker finished first.
         entry Enqueue (Path : String);
         entry Take
           (Index : out Slot_Index;
            Path  : out Unbounded_String;
            Done  : out Boolean);
         procedure Deposit (Index : Slot_Index; Result : Outcome);
         entry Collect (Result : out Outcome; Done : out Boolean);
         procedure Close;
         procedure Request_Halt;
         function Halted return Boolean;
         procedure Note_Failure (Message : String);
         function Failures return Unbounded_String;
      private
         Ring     : Slot_Ring;
         Head     : Natural := 0;
         --  Next result to write.
         Cursor   : Natural := 0;
         --  Next path to hand to a worker.
         Tail     : Natural := 0;
         --  Next slot to fill.
         Closed   : Boolean := False;
         Stopping : Boolean := False;
         Deferred : Unbounded_String;
      end Pipeline;

      protected body Pipeline is

         entry Enqueue (Path : String) when Tail - Head < Slot_Count is
         begin
            Ring (Tail mod Slot_Count).Ready := False;
            Ring (Tail mod Slot_Count).Path := To_Unbounded_String (Path);
            Ring (Tail mod Slot_Count).Result := (others => <>);
            Tail := Tail + 1;
         end Enqueue;

         entry Take
           (Index : out Slot_Index;
            Path  : out Unbounded_String;
            Done  : out Boolean)
           when Cursor < Tail or else Closed
         is
         begin
            if Cursor < Tail then
               Index := Cursor mod Slot_Count;
               Path := Ring (Index).Path;
               Cursor := Cursor + 1;
               Done := False;
            else
               Index := 0;
               Path := Null_Unbounded_String;
               Done := True;
            end if;
         end Take;

         procedure Deposit (Index : Slot_Index; Result : Outcome) is
         begin
            Ring (Index).Result := Result;
            Ring (Index).Ready := True;
         end Deposit;

         entry Collect (Result : out Outcome; Done : out Boolean)
           when(Head < Tail and then Ring (Head mod Slot_Count).Ready)
           or else (Closed and then Head = Tail)
         is
         begin
            if Head < Tail then
               Result := Ring (Head mod Slot_Count).Result;
               Ring (Head mod Slot_Count).Ready := False;
               Ring (Head mod Slot_Count).Result := (others => <>);
               Ring (Head mod Slot_Count).Path := Null_Unbounded_String;
               Head := Head + 1;
               Done := False;
            else
               Result := (others => <>);
               Done := True;
            end if;
         end Collect;

         procedure Close is
         begin
            Closed := True;
         end Close;

         procedure Request_Halt is
         begin
            Stopping := True;
         end Request_Halt;

         function Halted return Boolean
         is (Stopping);

         procedure Note_Failure (Message : String) is
         begin
            Append (Deferred, Message);
         end Note_Failure;

         function Failures return Unbounded_String
         is (Deferred);

      end Pipeline;

      function Uses_Standard_Input return Boolean is
      begin
         for K in 1 .. Path_Count loop
            if Argument (Path_Args (K)) = "-" then
               return True;
            end if;
         end loop;
         return False;
      end Uses_Standard_Input;

      ----------
      -- Scan --
      ----------

      procedure Scan
        (Name     : String;
         Standard : Boolean;
         Work     : in out Regex.Matcher;
         Result   : out Outcome)
      is
         File           : Files.File_Type;
         Line, Selected : Natural := 0;
         Prefix         : constant Boolean := not Hide_Name;

         procedure Record_Line (Record_Text : String; Halt : out Boolean) is
            Matches : Boolean;
         begin
            if Whole then
               Regex.Full_Match_With (Code, Record_Text, Work, Matches);
            else
               Regex.Search_With (Code, Record_Text, Work, Matches);
            end if;
            Halt := False;
            Line := Line + 1;
            if Matches /= Invert then
               Result.Selected := True;
               Selected := Selected + 1;
               if Quiet then
                  Halt := True;
               elsif List_Files then
                  Append (Result.Text, Name & ASCII.LF);
                  Halt := True;
               elsif not Count_Only then
                  if Prefix then
                     Append (Result.Text, Name & ":");
                  end if;
                  if Numbered then
                     Append (Result.Text, Image (Line) & ":");
                  end if;
                  Append (Result.Text, Record_Text & Delimiter);
               end if;
            end if;
         end Record_Line;

      begin
         Result := (others => <>);
         if Standard then
            Spark_Cli.Read_Records
              (IO.Text_Streams.Stream (IO.Standard_Input),
               Delimiter,
               Record_Line'Access);
         else
            if not Scan_Binary and then Looks_Binary (Name) then
               return;
            end if;
            Files.Open (File, Files.In_File, Name);
            Spark_Cli.Read_Records
              (Files.Stream (File), Delimiter, Record_Line'Access);
            Files.Close (File);
         end if;
         if Count_Only and then not Quiet and then not List_Files then
            if Prefix then
               Append (Result.Text, Name & ":");
            end if;
            Append (Result.Text, Image (Selected) & ASCII.LF);
         end if;
         Result.Halt := Quiet and then Result.Selected;
      exception
         when E : others =>
            if Files.Is_Open (File) then
               Files.Close (File);
            end if;
            Result.Failed := True;
            Append
              (Result.Errors,
               "spark-rg: "
               & Name
               & ": "
               & Ada.Exceptions.Exception_Message (E)
               & ASCII.LF);
      end Scan;

      ----------
      -- Emit --
      ----------

      procedure Emit (Result : Outcome) is
      begin
         if Length (Result.Errors) > 0 then
            IO.Put (IO.Standard_Error, To_String (Result.Errors));
         end if;
         if Result.Failed then
            Had_Error := True;
            Set_Exit_Status (2);
         end if;
         if Length (Result.Text) > 0 then
            Write (To_String (Result.Text));
         end if;
         if Result.Selected then
            Any_Selected := True;
         end if;
      end Emit;

      ---------------------
      -- Walk_Arguments  --
      ---------------------

      procedure Walk_Arguments
        (Visit : not null access procedure (Path : String; Stop : out Boolean);
         Fail  : not null access procedure (Message : String))
      is
         procedure Search_Argument (Name : String) is
            Stop : Boolean;
         begin
            if Ada.Directories.Exists (Name)
              and then Ada.Directories.Kind (Name) = Ada.Directories.Directory
            then
               --  Paths below a named directory are reported the way the user
               --  named it, and below "." with no prefix at all.
               Dir_Walk.Walk
                 (Root    => Name,
                  Opts    => Walk_Options,
                  Display =>
                    (if Name = "."
                     then ""
                     elsif Name (Name'Last) = '/'
                     then Name
                     else Name & "/"),
                  Visit   => Visit,
                  Warn    => Warn'Access);
               Finished := Quiet and then Any_Selected;
            else
               Visit (Name, Stop);
               Finished := Stop;
            end if;
         exception
            when E : others =>
               Fail (Name & ": " & Ada.Exceptions.Exception_Message (E));
         end Search_Argument;

      begin
         if Path_Count = 0 then
            Search_Argument (".");
         else
            for K in 1 .. Path_Count loop
               Search_Argument (Argument (Path_Args (K)));
               exit when Finished;
            end loop;
         end if;
      end Walk_Arguments;

      --------------------
      -- Run_Sequential --
      --------------------

      procedure Run_Sequential is
         Work : Regex.Matcher (Regex.State_Count (Code));

         procedure Visit (Path : String; Stop : out Boolean) is
            Result : Outcome;
         begin
            Stop := False;
            if Path = "-" then
               Scan
                 ("(standard input)",
                  Standard => True,
                  Work     => Work,
                  Result   => Result);
               Emit (Result);
               Stop := Result.Halt;
            elsif Selected_By_Globs (Path) then
               Scan (Path, Standard => False, Work => Work, Result => Result);
               Emit (Result);
               Stop := Result.Halt;
            end if;
         end Visit;

      begin
         Regex.Initialize (Work);
         Walk_Arguments (Visit'Access, Error'Access);
      end Run_Sequential;

      ------------------
      -- Run_Parallel --
      ------------------

      procedure Run_Parallel is
         --  The traversal fills the ring, the crew empties it and this task
         --  writes what comes back. Nothing here crosses into the library:
         --  a compiled Program is read-only, every entry point is free of
         --  global state, and each worker owns its own match workspace.
         task type Worker;
         task Producer;

         task body Worker is
            Work   : Regex.Matcher (Regex.State_Count (Code));
            Index  : Slot_Index;
            Path   : Unbounded_String;
            Done   : Boolean;
            Result : Outcome;
         begin
            Regex.Initialize (Work);
            loop
               Pipeline.Take (Index, Path, Done);
               exit when Done;
               begin
                  Scan
                    (To_String (Path),
                     Standard => False,
                     Work     => Work,
                     Result   => Result);
               exception
                  when E : others =>
                     --  A slot that is claimed must be filled, or the writer
                     --  waits for a result that never arrives.
                     Result := (others => <>);
                     Result.Failed := True;
                     Append
                       (Result.Errors,
                        "spark-rg: "
                        & To_String (Path)
                        & ": "
                        & Ada.Exceptions.Exception_Message (E)
                        & ASCII.LF);
               end;
               if Result.Halt then
                  Pipeline.Request_Halt;
               end if;
               Pipeline.Deposit (Index, Result);
            end loop;
         end Worker;

         task body Producer is
            procedure Visit (Path : String; Stop : out Boolean) is
            begin
               if Pipeline.Halted then
                  Stop := True;
               else
                  if Selected_By_Globs (Path) then
                     Pipeline.Enqueue (Path);
                  end if;
                  Stop := Pipeline.Halted;
               end if;
            end Visit;

            procedure Fail (Message : String) is
            begin
               Pipeline.Note_Failure ("spark-rg: " & Message & ASCII.LF);
            end Fail;

         begin
            Walk_Arguments (Visit'Access, Fail'Access);
            Pipeline.Close;
         exception
            when others =>
               Pipeline.Close;
         end Producer;

      begin
         declare
            Crew   : array (1 .. Jobs) of Worker;
            Result : Outcome;
            Done   : Boolean;
            pragma Unreferenced (Crew);
         begin
            loop
               Pipeline.Collect (Result, Done);
               exit when Done;
               Emit (Result);
            end loop;
         end;

         declare
            Deferred : constant String := To_String (Pipeline.Failures);
         begin
            if Deferred /= "" then
               IO.Put (IO.Standard_Error, Deferred);
               Had_Error := True;
               Set_Exit_Status (2);
            end if;
         end;
      end Run_Parallel;

   begin
      if Jobs = 1 or else Uses_Standard_Input then
         --  A single stream has no order to preserve and nothing to overlap.
         Run_Sequential;
      else
         Run_Parallel;
      end if;
   end Process_Input;
   function Next_Value (Option : String) return String is
   begin
      if Index < Argument_Count then
         Index := Index + 1;
         return Argument (Index);
      else
         Error (Option & " needs a value");
         return "";
      end if;
   end Next_Value;

begin
   while Index <= Argument_Count loop
      declare
         Arg : constant String := Argument (Index);
      begin
         if not End_Options and then Arg = "--" then
            End_Options := True;
         elsif not End_Options and then Arg = "--help" then
            Help;
            return;
         elsif not End_Options and then Arg = "--version" then
            IO.Put_Line ("spark-rg 0.1.0");
            return;
         elsif not End_Options and then Arg = "--no-ignore" then
            Walk_Options.Respect_Ignore := False;
         elsif not End_Options and then Arg = "--hidden" then
            Walk_Options.Hidden := True;
         elsif not End_Options and then Arg = "--follow" then
            Walk_Options.Follow_Links := True;
         elsif not End_Options and then Arg = "--binary" then
            Scan_Binary := True;
         elsif not End_Options and then Arg = "--threads" then
            declare
               Value : constant String := Next_Value ("--threads");
            begin
               if not Had_Error then
                  Jobs := Positive'Value (Value);
               end if;
            exception
               when others =>
                  Error ("--threads needs a positive number, not " & Value);
            end;
         elsif not End_Options and then Arg = "--max-depth" then
            declare
               Value : constant String := Next_Value ("--max-depth");
            begin
               if not Had_Error then
                  Walk_Options.Max_Depth := Natural'Value (Value);
               end if;
            exception
               when others =>
                  Error ("--max-depth needs a number, not " & Value);
            end;
         elsif not End_Options and then Arg'Length > 1 and then Arg (1) = '-'
         then
            for K in 2 .. Arg'Last loop
               case Arg (K) is
                  when 'E'             =>
                     Fixed := False;

                  when 'F'             =>
                     Fixed := True;

                  when 'n'             =>
                     Numbered := True;

                  when 'N'             =>
                     Numbered := False;

                  when 'v'             =>
                     Invert := True;

                  when 'c'             =>
                     Count_Only := True;

                  when 'q'             =>
                     Quiet := True;

                  when 'l'             =>
                     List_Files := True;

                  when 'h'             =>
                     --  Names are shown by default, since a recursive search
                     --  reports matches from many files.
                     Hide_Name := True;

                  when 'H'             =>
                     Hide_Name := False;

                  when 'x'             =>
                     Whole := True;

                  when 'z'             =>
                     Delimiter := ASCII.NUL;

                  when 'L'             =>
                     Walk_Options.Follow_Links := True;

                  when 'e' | 'g' | 'j' =>
                     declare
                        Letter : constant Character := Arg (K);
                        Value  : constant String :=
                          (if K < Arg'Last
                           then Arg (K + 1 .. Arg'Last)
                           else Next_Value (['-', Arg (K)]));
                     begin
                        if not Had_Error then
                           case Letter is
                              when 'g'    =>
                                 Add_Glob (Value);

                              when 'j'    =>
                                 begin
                                    Jobs := Positive'Value (Value);
                                 exception
                                    when others =>
                                       Error
                                         ("-j needs a positive number, not "
                                          & Value);
                                 end;

                              when others =>
                                 Set_Pattern (Value);
                           end case;
                        end if;
                     end;
                     exit;

                  when others          =>
                     Error ("unknown option: " & Arg & " (see --help)");
                     exit;
               end case;
            end loop;
         elsif not Have_Pattern then
            Set_Pattern (Arg);
         else
            Path_Count := Path_Count + 1;
            Path_Args (Path_Count) := Index;
         end if;
      end;
      if Had_Error then
         return;
      end if;
      Index := Index + 1;
   end loop;

   if not Have_Pattern then
      Error ("missing pattern (see --help)");
      return;
   end if;

   if Fixed then
      declare
         Escaped : Unbounded_String;
      begin
         for C of To_String (Pattern) loop
            if C
               in '\'
                | '.'
                | '^'
                | '$'
                | '|'
                | '?'
                | '*'
                | '+'
                | '('
                | ')'
                | '['
                | ']'
                | '{'
                | '}'
            then
               Append (Escaped, '\');
            end if;
            Append (Escaped, C);
         end loop;
         Pattern := Escaped;
      end;
   end if;

   Regex.Compile (To_String (Pattern), Code, Status);
   if Status /= Regex.Success then
      Error ("pattern: " & Status'Image);
      return;
   end if;

   Process_Input;
   if Had_Error then
      Set_Exit_Status (2);
   elsif Any_Selected then
      Set_Exit_Status (Success);
   else
      Set_Exit_Status (1);
   end if;
exception
   when E : others =>
      Error (Ada.Exceptions.Exception_Message (E));
end Spark_Rg;
