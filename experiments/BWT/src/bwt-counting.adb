package body BWT.Counting with SPARK_Mode is
   function Unseen (Seen : Flags; Through : Natural) return Natural is
     (if Through = 0 then 0
      else Unseen (Seen, Through - 1) + (if Seen (Through) then 0 else 1));

   procedure Marked (Before, After : Flags; Position : Positive) is
   begin
      for I in 0 .. Before'Length loop
         pragma Loop_Invariant
           (Unseen (Before, I) = Unseen (After, I)
             + (if Position <= I then 1 else 0));
      end loop;
   end Marked;

   procedure All_Clear (Seen : Flags) is
   begin
      for I in 0 .. Seen'Length loop
         pragma Loop_Invariant (Unseen (Seen, I) = I);
      end loop;
   end All_Clear;
end BWT.Counting;
