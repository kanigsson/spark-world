--  Times the four transforms on each file named on the command line, as
--  `make bench-corpora` does with the public corpora that
--  bench/fetch-corpora.sh downloads. Each measurement repeats until it has
--  run for a while and reports the mean. Every file is round-tripped once
--  first, so a broken build cannot report a speed.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with BWT;
with Bench_Timing;

procedure Bench_Corpora is
   use BWT;

   --  How long each measurement runs, at least. At 4 MiB one encoding
   --  already takes longer, so those are timed once.
   Budget : constant Duration := 0.2;

   type Text_Access is access String;

   function Read (Name : String) return Text_Access is
      use Ada.Streams.Stream_IO;
      File   : File_Type;
      Result : Text_Access;
   begin
      Open (File, In_File, Name);
      Result := new String (1 .. Natural (Size (File)));
      String'Read (Stream (File), Result.all);
      Close (File);
      return Result;
   end Read;

   Sink     : Natural := 0;
   Failures : Natural := 0;

   procedure Check (OK : Boolean; What : String) is
   begin
      if not OK then
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAILED: " & What);
      end if;
   end Check;

   type Transform is
     (Classical_Encoding,
      Classical_Decoding,
      Bijective_Encoding,
      Bijective_Decoding);

   --  Each decoder is timed on its own encoder's output, as in real use.
   procedure Run
     (Op : Transform; S : String; Classical : Classical_Result; Last : String)
   is
   begin
      case Op is
         when Classical_Encoding =>
            Sink := Sink + Classical_Encode (S).Primary;

         when Classical_Decoding =>
            Sink :=
              Sink
              + Character'Pos
                  (Classical_Decode (Classical.Last, Classical.Primary) (1));

         when Bijective_Encoding =>
            Sink := Sink + Character'Pos (Bijective_Encode (S) (1));

         when Bijective_Decoding =>
            Sink := Sink + Character'Pos (Bijective_Decode (Last) (1));
      end case;
   end Run;

begin
   for A in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Name : constant String := Ada.Command_Line.Argument (A);
         S    : constant Text_Access := Read (Name);
      begin
         if S'Length > 0 then
            declare
               --  "<size>/<file>", which is how fetch-corpora.sh lays them out.
               Label     : constant String :=
                 Ada.Directories.Simple_Name
                   (Ada.Directories.Containing_Directory (Name))
                 & "/"
                 & Ada.Directories.Simple_Name (Name)
                 & " ";
               Classical : constant Classical_Result :=
                 Classical_Encode (S.all);
               Last      : constant String := Bijective_Encode (S.all);
            begin
               Check
                 (Classical_Decode (Classical.Last, Classical.Primary) = S.all,
                  Label & "classical");
               Check (Bijective_Decode (Last) = S.all, Label & "bijective");
               for Op in Transform loop
                  declare
                     Watch : constant Bench_Timing.Stopwatch :=
                       Bench_Timing.Started;
                     Runs  : Positive := 1;
                  begin
                     loop
                        Run (Op, S.all, Classical, Last);
                        exit when Bench_Timing.Elapsed (Watch) >= Budget;
                        Runs := Runs + 1;
                     end loop;
                     Bench_Timing.Report
                       (Label & Transform'Image (Op),
                        Bench_Timing.Elapsed (Watch),
                        Runs);
                  end;
               end loop;
            end;
         end if;
      end;
   end loop;
   --  Keeps the results live, so the optimiser cannot drop the work.
   if Sink = 0 then
      Ada.Text_IO.Put_Line ("(no work)");
   end if;
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Bench_Corpora;
