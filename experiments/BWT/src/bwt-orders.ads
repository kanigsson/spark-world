with BWT.Ranks;

--  The order in which the bijective decoder visits rows: W (P) is the row
--  whose letter lands at position P. Filling right to left, the decoder
--  follows Map from the row it just wrote while that leads somewhere new,
--  and otherwise starts again at the least row not yet written.

package BWT.Orders
  with SPARK_Mode, Ghost
is
   use BWT.Ranks;

   function Inverse_Pair (W, Inv : Mapping) return Boolean
   is (W'First = 1
       and then Inv'First = 1
       and then W'Length = Inv'Length
       and then W'Length <= Max_Length
       and then (for all P in W'Range => W (P) in Inv'Range)
       and then (for all I in Inv'Range => Inv (I) in W'Range)
       and then (for all P in W'Range => Inv (W (P)) = P)
       and then (for all I in Inv'Range => W (Inv (I)) = I));

   function Is_Order (Map, W, Inv : Mapping) return Boolean
   is (Inverse_Pair (W, Inv)
       and then Map'First = 1
       and then Map'Length = W'Length
       and then (for all I in Map'Range => Map (I) in Map'Range)
       and then (if W'Length > 0 then W (W'Last) = 1)
       and then (for all P in 2 .. W'Last =>
                   (if Inv (Map (W (P))) < P
                    then W (P - 1) = Map (W (P))
                    else (for all Y in 1 .. W (P - 1) - 1 => Inv (Y) >= P))));

   --  The visiting order is determined by Map alone.
   procedure Order_Unique (Map, W1, Inv1, W2, Inv2 : Mapping)
   with
     Pre  => Is_Order (Map, W1, Inv1) and then Is_Order (Map, W2, Inv2),
     Post => (for all P in W1'Range => W1 (P) = W2 (P));
end BWT.Orders;
