with Fast; use Fast;

procedure Fast_Test with SPARK_Mode => On is
   Table : Huffman_Table :=
     (Counts  => (1 => 1, 2 => 2, others => 0),
      Symbols => (0 => 65, 1 => 66, 2 => 67, others => 0),
      Map     => (others => 0));
begin
   Build_Fast (Table);
   pragma
     Assert
       (for all J in Fast_Index =>
          Fast_Entry_Valid (Table.Counts, Table.Symbols, J, Table.Map (J)));
   for J in Fast_Index loop
      if Table.Map (J) /= 0 then
         Lemma_No_Shorter_Code (Table.Counts, J, Table.Map (J) mod 16);
         Lemma_Entry_Is_Reference
           (Table.Counts, Table.Symbols, J, Table.Map (J));
         pragma
           Assert
             (Reference_Entry (Table.Counts, Table.Symbols, J)
                = Table.Map (J));
      end if;
   end loop;
end Fast_Test;
