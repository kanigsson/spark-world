--  The clock and the closing line that a benchmark repeats.
--
--  Deliberately a stopwatch rather than a "time this N times" harness. The
--  work a benchmark times is its own -- one of them times a procedure whose
--  body is SPARK_Mode => Off, so a generic taking the work as a formal could
--  not be SPARK anyway, and the loop reads better where the work is.
--
--  Ada.Real_Time rather than Ada.Calendar: Calendar's clock is the wall clock,
--  which a time change or an NTP step moves underneath a running measurement,
--  and its arithmetic operators are SPARK_Mode => Off in the runtime. Real_Time
--  is monotonic, which is what "how long did this take" means.

with Ada.Real_Time;

package Bench_Timing is

   type Stopwatch is private;

   function Started return Stopwatch;

   function Elapsed (Since : Stopwatch) return Duration;

   --  "<name>: <ms> ms", the average over Runs -- the form every benchmark
   --  here already printed, with one rounding rule instead of several.
   procedure Report (Name : String; Total : Duration; Runs : Positive := 1);

private

   type Stopwatch is record
      Start : Ada.Real_Time.Time;
   end record;

end Bench_Timing;
