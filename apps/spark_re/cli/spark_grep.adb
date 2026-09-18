with Ada.Command_Line;      use Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Grep_Diag;
with Grep_Front;
with Ore.Images;
with Regex;
with Spark_Cli;

procedure Spark_Grep is
   use type Regex.Compile_Status;
   use type Grep_Front.Pattern_Result;
   package IO renames Ada.Text_IO;
   package Files renames Ada.Streams.Stream_IO;
   package Front renames Grep_Front;

   --  Everything the recursive front end also decides is decided in Front,
   --  which states the option letters and the selection rule in contracts;
   --  what is left here is this program's own surface and its file handling.
   Opt          : Front.Settings;
   Pattern      : Front.Pattern_State;
   End_Options  : Boolean := False;
   File_Args    : array (1 .. Argument_Count) of Natural := [others => 0];
   File_Count   : Natural := 0;
   Code         : Regex.Program;
   Status       : Regex.Compile_Status;
   Any_Selected : Boolean := False;
   Index        : Positive := 1;

   procedure Help is
   begin
      IO.Put_Line ("Usage: spark-grep [OPTIONS] PATTERN [FILE ...]");
      IO.Put_Line
        ("Byte-oriented extended regex; stdin if no files or FILE is -.");
      IO.Put_Line
        ("-E extended regex (default), -F literal, -e PATTERN (one only)");
      IO.Put_Line
        ("-n record numbers, -v invert, -c count, -q quiet, -l file names");
      IO.Put_Line
        ("-h hide names, -H show names, -x whole record, -z NUL records");
      IO.Put_Line
        ("-- ends options; --help; --version. Unknown options are errors.");
      IO.Put_Line
        ("No locale/Unicode folding, recursion, backreferences or lookaround.");
      IO.Put_Line
        ("Limits: 65535 pattern bytes, 512 AST nodes, 4096 states, repeats <=255.");
      IO.Put_Line
        ("Exit: 0 selected records, 1 none, 2 error. Output records end in delimiter.");
   end Help;

   procedure Take_Pattern (Value : String) is
      Result : Front.Pattern_Result;
   begin
      Front.Set_Pattern (Pattern, Value, Result);
      if Result = Front.Already_Set then
         Grep_Diag.Error ("multiple patterns are not supported");
      end if;
   end Take_Pattern;

   procedure Process_Input is
      Work : Regex.Matcher (Regex.State_Count (Code));
      procedure Filter (Name : String; Standard : Boolean) is
         File           : Files.File_Type;
         Line, Selected : Natural := 0;
         Prefix         : constant Boolean :=
           Front.Show_Prefix (Opt, File_Count);
         procedure Record_Line (Record_Text : String; Stop : out Boolean) is
            Matches : Boolean;
            Action  : Front.Match_Action;
         begin
            if Opt.Whole then
               Regex.Full_Match_With (Code, Record_Text, Work, Matches);
            else
               Regex.Search_With (Code, Record_Text, Work, Matches);
            end if;
            Action := Front.Decide (Opt, Matches);
            Stop := Front.Halts (Action);
            Line := Line + 1;
            if Front.Selects (Action) then
               Any_Selected := True;
               Selected := Selected + 1;
            end if;
            case Action is
               when Front.Emit_Input_Name =>
                  Grep_Diag.Write (Name & ASCII.LF);

               when Front.Emit_Record     =>
                  Grep_Diag.Write
                    (Front.Match_Prefix
                       (Opt, Prefix, Name, Ore.Images.Decimal (Line)));
                  Grep_Diag.Write (Record_Text & Opt.Delimiter);

               when others                =>
                  null;
            end case;
         end Record_Line;
      begin
         if Standard then
            Spark_Cli.Read_Records
              (IO.Text_Streams.Stream (IO.Standard_Input),
               Opt.Delimiter,
               Record_Line'Access);
         else
            Files.Open (File, Files.In_File, Name);
            Spark_Cli.Read_Records
              (Files.Stream (File), Opt.Delimiter, Record_Line'Access);
            Files.Close (File);
         end if;
         if Front.Reports_Count (Opt) then
            Grep_Diag.Write
              (Front.Count_Line (Prefix, Name, Ore.Images.Decimal (Selected)));
         end if;
      exception
         when E : others =>
            if Files.Is_Open (File) then
               Files.Close (File);
            end if;
            Grep_Diag.Error
              (Name & ": " & Ada.Exceptions.Exception_Message (E));
      end Filter;
   begin
      Regex.Initialize (Work);
      if File_Count = 0 then
         Filter ("(standard input)", True);
      else
         for K in 1 .. File_Count loop
            declare
               Name : constant String := Argument (File_Args (K));
            begin
               Filter
                 ((if Name = "-" then "(standard input)" else Name),
                  Name = "-");
            end;
            exit when Opt.Quiet and then Any_Selected;
         end loop;
      end if;
   end Process_Input;

begin
   Grep_Diag.Set_Program ("spark-grep");
   while Index <= Argument_Count loop
      declare
         Arg : constant String := Argument (Index);
      begin
         case Front.Classify (Arg, End_Options) is
            when Front.End_Marker  =>
               End_Options := True;

            when Front.Long_Option =>
               if Arg = "--help" then
                  Help;
                  return;
               elsif Arg = "--version" then
                  IO.Put_Line ("spark-grep 0.1.0");
                  return;
               else
                  Grep_Diag.Error ("unknown option: " & Arg & " (see --help)");
               end if;

            when Front.Cluster     =>
               for K in Arg'First + 1 .. Arg'Last loop
                  declare
                     Outcome : Front.Letter_Result;
                  begin
                     Front.Apply_Letter (Opt, Arg (K), Outcome);
                     case Outcome is
                        when Front.Accepted    =>
                           null;

                        when Front.Needs_Value =>
                           if Front.Has_Inline_Value (Arg, K) then
                              Take_Pattern (Front.Inline_Value (Arg, K));
                           elsif Index < Argument_Count then
                              Index := Index + 1;
                              Take_Pattern (Argument (Index));
                           else
                              Grep_Diag.Error ("-e needs a pattern");
                           end if;
                           exit;

                        when Front.Unknown     =>
                           Grep_Diag.Error
                             ("unknown option: " & Arg & " (see --help)");
                           exit;
                     end case;
                  end;
               end loop;

            when Front.Operand     =>
               if Pattern.Present then
                  File_Count := File_Count + 1;
                  File_Args (File_Count) := Index;
               else
                  Take_Pattern (Arg);
               end if;
         end case;
      end;
      if Grep_Diag.Had_Error then
         return;
      end if;
      Index := Index + 1;
   end loop;
   if not Pattern.Present then
      Grep_Diag.Error ("missing pattern (see --help)");
      return;
   end if;
   if Opt.Fixed then
      Pattern.Text :=
        To_Unbounded_String (Front.Escape_Literal (To_String (Pattern.Text)));
   end if;
   Regex.Compile (To_String (Pattern.Text), Code, Status);
   if Status /= Regex.Success then
      Grep_Diag.Error ("pattern: " & Status'Image);
      return;
   end if;
   Process_Input;
   Set_Exit_Status (Front.Exit_Code (Grep_Diag.Had_Error, Any_Selected));
exception
   when E : others =>
      Grep_Diag.Error (Ada.Exceptions.Exception_Message (E));
end Spark_Grep;
