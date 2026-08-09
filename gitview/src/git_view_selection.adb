package body Git_View_Selection with SPARK_Mode => On is

   procedure Ordered
     (A, B        : Position;
      First, Last : out Position)
   is
   begin
      if Before_Or_Equal (A, B) then
         First := A;
         Last  := B;
      else
         First := B;
         Last  := A;
      end if;
   end Ordered;

end Git_View_Selection;
