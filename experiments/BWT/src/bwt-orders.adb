package body BWT.Orders
  with SPARK_Mode
is
   procedure Order_Unique (Map, W1, Inv1, W2, Inv2 : Mapping) is
      N : constant Natural := W1'Length;
   begin
      if N = 0 then
         return;
      end if;
      for P in reverse 2 .. N loop
         pragma Loop_Invariant (for all Q in P .. N => W1 (Q) = W2 (Q));
         --  Both orders have written the same rows at P .. N.
         pragma Assert
           (for all X in 1 .. N => (Inv1 (X) >= P) = (Inv2 (X) >= P));
         declare
            X : constant Positive := Map (W1 (P));
         begin
            if Inv1 (X) >= P then
               pragma Assert (Inv2 (W1 (P - 1)) < P);
               pragma Assert (Inv1 (W2 (P - 1)) < P);
               pragma Assert (W1 (P - 1) = W2 (P - 1));
            end if;
         end;
      end loop;
   end Order_Unique;
end BWT.Orders;
