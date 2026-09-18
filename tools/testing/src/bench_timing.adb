with Ada.Text_IO;

package body Bench_Timing is

   use Ada.Real_Time;

   -------------
   -- Started --
   -------------

   function Started return Stopwatch is
      --  Clock is a volatile function, so its result lands in an object
      --  before anything else touches it.
      Now : constant Time := Clock;
   begin
      return (Start => Now);
   end Started;

   -------------
   -- Elapsed --
   -------------

   function Elapsed (Since : Stopwatch) return Duration is
      Now : constant Time := Clock;
   begin
      return To_Duration (Now - Since.Start);
   end Elapsed;

   ------------
   -- Report --
   ------------

   procedure Report (Name : String; Total : Duration; Runs : Positive := 1) is
   begin
      Ada.Text_IO.Put_Line
        (Name & ": " & Duration'Image (Total / Runs * 1000.0) & " ms");
   end Report;

end Bench_Timing;
