--  Times the four transforms on inputs of several shapes and sizes. Each
--  measurement repeats until it has run for a while, and reports the mean.
--  Every result is checked once, so a broken build cannot report a speed.

with Ada.Command_Line;
with Ada.Text_IO;
with BWT;
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

   --  Each Time_* repeats one transform until Budget has elapsed.

   procedure Time_Classical_Encode (Name, S : String) is
      Watch : constant Bench_Timing.Stopwatch := Bench_Timing.Started;
      Runs  : Positive := 1;
   begin
      loop
         Sink := Sink + Classical_Encode (S).Primary;
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report (Name, Bench_Timing.Elapsed (Watch), Runs);
   end Time_Classical_Encode;

   procedure Time_Classical_Decode (Name, Last : String; Primary : Natural) is
      Watch : constant Bench_Timing.Stopwatch := Bench_Timing.Started;
      Runs  : Positive := 1;
   begin
      loop
         Sink := Sink + Character'Pos (Classical_Decode (Last, Primary) (1));
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report (Name, Bench_Timing.Elapsed (Watch), Runs);
   end Time_Classical_Decode;

   procedure Time_Bijective_Encode (Name, S : String) is
      Watch : constant Bench_Timing.Stopwatch := Bench_Timing.Started;
      Runs  : Positive := 1;
   begin
      loop
         Sink := Sink + Character'Pos (Bijective_Encode (S) (1));
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report (Name, Bench_Timing.Elapsed (Watch), Runs);
   end Time_Bijective_Encode;

   procedure Time_Bijective_Decode (Name, Last : String) is
      Watch : constant Bench_Timing.Stopwatch := Bench_Timing.Started;
      Runs  : Positive := 1;
   begin
      loop
         Sink := Sink + Character'Pos (Bijective_Decode (Last) (1));
         exit when Bench_Timing.Elapsed (Watch) >= Budget;
         Runs := Runs + 1;
      end loop;
      Bench_Timing.Report (Name, Bench_Timing.Elapsed (Watch), Runs);
   end Time_Bijective_Decode;

   Sizes : constant array (Positive range <>) of Positive :=
     [128, 256, 512, Max_Length];
begin
   for Kind in Shape loop
      for N of Sizes loop
         declare
            S     : constant String := Input (Kind, N);
            C     : constant Classical_Result := Classical_Encode (S);
            B     : constant String := Bijective_Encode (S);
            Label : constant String :=
              Shape'Image (Kind) & " n=" & Natural'Image (N) & " ";
         begin
            Check
              (Classical_Decode (C.Last, C.Primary) = S, Label & "classical");
            Check (Bijective_Decode (B) = S, Label & "bijective");
            Time_Classical_Encode (Label & "classical encode", S);
            Time_Classical_Decode
              (Label & "classical decode", C.Last, C.Primary);
            Time_Bijective_Encode (Label & "bijective encode", S);
            Time_Bijective_Decode (Label & "bijective decode", B);
         end;
      end loop;
   end loop;
   --  Keeps the results live, so the optimiser cannot drop the work.
   if Sink = 0 then
      Ada.Text_IO.Put_Line ("(no work)");
   end if;
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Bench_BWT;
