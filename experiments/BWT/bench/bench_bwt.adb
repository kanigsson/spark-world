--  Times the four transforms on inputs of several shapes and sizes. Each
--  measurement repeats until it has run for a while, and reports the mean.
--  Every result is checked once, so a broken build cannot report a speed.

with Ada.Command_Line;
with Ada.Text_IO;
with BWT;
with BWT.FM_Index;
with BWT.Search;
with Bench_Timing;

procedure Bench_BWT is
   use BWT;

   --  How long each measurement runs, at least.
   Budget : constant Duration := 0.2;

   type Shape is (Random, Text, Periodic, Constant_Byte);

   type Word is mod 2**32;

   function Input (Kind : Shape; N : Natural) return String is
      Result : String (1 .. N);
      Seed   : Word := 12_345;
      Prose  : constant String :=
        "it was the best of times, it was the worst of times, it was the "
        & "age of wisdom, it was the age of foolishness, ";
   begin
      for I in Result'Range loop
         case Kind is
            when Random        =>
               Seed := Seed * 1_103_515_245 + 12_345;
               Result (I) := Character'Val (Seed / 2**16 mod 256);

            when Text          =>
               Result (I) := Prose ((I - 1) mod Prose'Length + 1);

            when Periodic      =>
               Result (I) := Character'Val (Character'Pos ('a') + I mod 3);

            when Constant_Byte =>
               Result (I) := 'a';
         end case;
      end loop;
      return Result;
   end Input;

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

   --  Runs one transform once on S. The decoders take S as a last column:
   --  both accept any, so they need not wait for the encoders.
   procedure Run (Op : Transform; S : String) is
   begin
      case Op is
         when Classical_Encoding =>
            Sink := Sink + Classical_Encode (S).Primary;

         when Classical_Decoding =>
            Sink := Sink + Character'Pos (Classical_Decode (S, 1) (1));

         when Bijective_Encoding =>
            Sink := Sink + Character'Pos (Bijective_Encode (S) (1));

         when Bijective_Decoding =>
            Sink := Sink + Character'Pos (Bijective_Decode (S) (1));
      end case;
   end Run;

   --  Repeats Op until Budget has elapsed and reports the mean. Returns the
   --  mean, so that the caller can stop a series that has become too slow.
   function Timed (Name : String; Op : Transform; S : String) return Duration
   is
      Watch : constant Bench_Timing.Stopwatch := Bench_Timing.Started;
      Runs  : Positive := 1;
   begin
      loop
         Run (Op, S);
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report (Name, Bench_Timing.Elapsed (Watch), Runs);
      return Bench_Timing.Elapsed (Watch) / Runs;
   end Timed;

   --  A series stops growing once one run takes longer than this: every
   --  size is four times the last, and the encoders are up to cubic.
   Too_Slow : constant Duration := 0.25;

   Sizes   : constant array (Positive range <>) of Positive :=
     [1_024, 4_096, 16_384, 65_536, 262_144];
   Stopped : array (Shape, Transform) of Boolean :=
     [others => [others => False]];
begin
   for Kind in Shape loop
      for N of Sizes loop
         declare
            S     : constant String := Input (Kind, N);
            Label : constant String :=
              Shape'Image (Kind) & " n=" & Natural'Image (N) & " ";
         begin
            --  Round trips, while the encoders are still fast enough to try.
            if not Stopped (Kind, Classical_Encoding) then
               declare
                  C : constant Classical_Result := Classical_Encode (S);
               begin
                  Check
                    (Classical_Decode (C.Last, C.Primary) = S,
                     Label & "classical");
               end;
            end if;
            if not Stopped (Kind, Bijective_Encoding) then
               Check
                 (Bijective_Decode (Bijective_Encode (S)) = S,
                  Label & "bijective");
            end if;
            for Op in Transform loop
               if not Stopped (Kind, Op) then
                  Stopped (Kind, Op) :=
                    Timed (Label & Transform'Image (Op), Op, S) > Too_Slow;
               end if;
            end loop;
         end;
      end loop;
   end loop;
   --  Pattern counts on the classical column of the largest text: backward
   --  search with a scanned rank, against the index with rank checkpoints.
   declare
      S       : constant String := Input (Text, Sizes (Sizes'Last));
      Last    : constant String := Classical_Encode (S).Last;
      Idx     : constant FM_Index.Index := FM_Index.Build (Last);
      Pattern : constant String := "it was the age of";
      Watch   : Bench_Timing.Stopwatch := Bench_Timing.Started;
      Runs    : Positive := 1;
   begin
      Check
        (Search.Count (Last, Pattern) = FM_Index.Count (Idx, Pattern),
         "index count");
      loop
         Sink := Sink + FM_Index.Build (Last).Below ('a');
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report
        ("TEXT n=" & Natural'Image (S'Length) & " INDEX_BUILD",
         Bench_Timing.Elapsed (Watch),
         Runs);
      Watch := Bench_Timing.Started;
      Runs := 1;
      loop
         Sink := Sink + Search.Count (Last, Pattern);
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report
        ("TEXT n=" & Natural'Image (S'Length) & " COUNT_SCANNED_RANK",
         Bench_Timing.Elapsed (Watch),
         Runs);
      Watch := Bench_Timing.Started;
      Runs := 1;
      loop
         Sink := Sink + FM_Index.Count (Idx, Pattern);
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report
        ("TEXT n=" & Natural'Image (S'Length) & " COUNT_INDEX",
         Bench_Timing.Elapsed (Watch),
         Runs);
   end;
   --  Keeps the results live, so the optimiser cannot drop the work.
   if Sink = 0 then
      Ada.Text_IO.Put_Line ("(no work)");
   end if;
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Bench_BWT;
