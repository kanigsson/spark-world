package body BWT.Ranks with SPARK_Mode is
   function Rank (Last : String; Row : Positive; Through : Natural)
     return Natural is
     (if Through = 0 then 0
      else Rank (Last, Row, Through - 1)
        + (if Ordered (Last, Through, Row) then 1 else 0));

   procedure Strict_Ranks (Last : String; A, B : Positive) is
   begin
      for I in 0 .. Last'Length loop
         pragma Loop_Invariant (Rank (Last, A, I) <= Rank (Last, B, I));
         pragma Loop_Invariant
           (if I >= B then Rank (Last, A, I) < Rank (Last, B, I));
      end loop;
   end Strict_Ranks;

   function LF (Last : String) return Mapping is
      Map : Mapping (1 .. Last'Length) := (others => 1);
      Count : Natural;
   begin
      for I in Last'Range loop
         Count := 0;
         for J in Last'Range loop
            if Ordered (Last, J, I) then
               Count := Count + 1;
            end if;
            pragma Loop_Invariant (Count = Rank (Last, I, J));
         end loop;
         Map (I) := Count;
         pragma Loop_Invariant
           (for all P in 1 .. I => Map (P) = Rank (Last, P, Last'Length));
         pragma Loop_Invariant (for all P of Map => P in Map'Range);
      end loop;
      for I in Last'Range loop
         for J in Last'Range loop
            if I /= J then
               if Ordered (Last, I, J) then
                  Strict_Ranks (Last, I, J);
               else
                  Strict_Ranks (Last, J, I);
               end if;
            end if;
            pragma Loop_Invariant
              (for all K in 1 .. J =>
                (Ordered (Last, I, K) = (Map (I) <= Map (K)))
                and then (if I /= K then Map (I) /= Map (K)));
         end loop;
         pragma Loop_Invariant
           (for all P in 1 .. I => (for all Q in Last'Range =>
             (Ordered (Last, P, Q) = (Map (P) <= Map (Q)))
             and then (if P /= Q then Map (P) /= Map (Q))));
      end loop;
      return Map;
   end LF;

   procedure Walk_Step (Last : String; Primary : Positive; Steps : Natural) is
      pragma Annotate (GNATprove, Unhide_Info, "Expression_Function_Body", Walk);
   begin
      null;
   end Walk_Step;
end BWT.Ranks;
