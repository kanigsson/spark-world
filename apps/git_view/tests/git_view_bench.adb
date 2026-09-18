with Bench_Timing;

package body Git_View_Bench is

   -----------
   -- Timed --
   -----------

   procedure Timed
     (Name  : String;
      Runs  : Positive;
      View  : in out Git_View_Model.View_State;
      Frame : in out Git_View_Repository.Frame)
   is
      Total : Duration := 0.0;
   begin
      for Run in 1 .. Runs loop
         declare
            Watch : constant Bench_Timing.Stopwatch := Bench_Timing.Started;
         begin
            Git_View_Repository.Load (View, Frame);
            Total := Total + Bench_Timing.Elapsed (Watch);
         end;
      end loop;
      Bench_Timing.Report (Name, Total, Runs);
   end Timed;

end Git_View_Bench;
