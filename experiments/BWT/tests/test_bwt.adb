with BWT;
with Test_Checks;
with Ada.Command_Line;

procedure Test_BWT is
   use BWT;
   use Test_Checks;
   Contracts : constant Boolean := Ada.Command_Line.Argument_Count > 0;

   --  Small independent definition oracle: remove the least finite suffix
   --  repeatedly to obtain Lyndon factors; materialize periodic comparison
   --  keys and selection-sort them using Ada's built-in string comparison.
   --  Neither Duval nor the production rotation comparator is used here.
   function Reference (S : String; Bijective : Boolean) return Classical_Result
   is
      N      : constant Natural := S'Length;
      type Row_Entry is record
         Key  : String (1 .. 2 * N);
         Last : Character;
         Id   : Positive;
      end record;
      Rows   : array (1 .. N) of Row_Entry;
      Count  : Natural := 0;
      Finish : Natural := N;
      First  : Positive;
      Result : Classical_Result (N) := (N, (others => Character'First), 0);
   begin
      while Finish > 0 loop
         First := 1;
         if Bijective then
            for I in 2 .. Finish loop
               if S (I .. Finish) < S (First .. Finish) then
                  First := I;
               end if;
            end loop;
         end if;
         for Offset in 0 .. Finish - First loop
            Count := Count + 1;
            for K in Rows (Count).Key'Range loop
               Rows (Count).Key (K) :=
                 S (First + (Offset + K - 1) mod (Finish - First + 1));
            end loop;
            Rows (Count).Last :=
              S (First + (Offset + Finish - First) mod (Finish - First + 1));
            Rows (Count).Id := First + Offset;
         end loop;
         Finish := First - 1;
      end loop;
      for I in Rows'Range loop
         declare
            Best : Positive := I;
         begin
            for J in I + 1 .. N loop
               if Rows (J).Key < Rows (Best).Key
                 or else (Rows (J).Key = Rows (Best).Key
                          and then Rows (J).Id < Rows (Best).Id)
               then
                  Best := J;
               end if;
            end loop;
            declare
               Temp : constant Row_Entry := Rows (I);
            begin
               Rows (I) := Rows (Best);
               Rows (Best) := Temp;
            end;
            Result.Last (I) := Rows (I).Last;
            if Rows (I).Id = 1 then
               Result.Primary := I;
            end if;
         end;
      end loop;
      return Result;
   end Reference;

   procedure Exercise (S : String; Oracle : Boolean := True) is
      C : constant Classical_Result := Classical_Encode (S);
      B : constant String := Bijective_Encode (S);
   begin
      Check (Classical_Decode (C.Last, C.Primary) = S, "classical roundtrip");
      Check (Bijective_Decode (B) = S, "bijective roundtrip");
      Check (Bijective_Encode (Bijective_Decode (S)) = S, "bijective onto");
      if Oracle then
         Check (C = Reference (S, False), "classical definition");
         Check (B = Reference (S, True).Last, "bijective definition");
      end if;
   end Exercise;

   Alphabet : constant String :=
     Character'Val (0) & Character'Val (128) & Character'Val (255);
begin
   Start ("BWT", Stop_On_Fail => True);
   Check (Classical_Encode ("banana") = (6, "nnbaaa", 4), "banana BWT");
   Check (Bijective_Encode ("banana") = "annbaa", "banana BBWT");
   Check (Bijective_Encode ("babab") = "bbaab", "omega versus finite order");
   Exercise ("mississippi");
   Exercise ("abababab");
   Exercise ("zyxwvuts");
   for Length in 0 .. (if Contracts then 3 else 8) loop
      for Code in 0 .. 3**Length - 1 loop
         declare
            S     : String (1 .. Length);
            Value : Natural := Code;
         begin
            for I in S'Range loop
               S (I) := Alphabet (Value mod 3 + 1);
               Value := Value / 3;
            end loop;
            Exercise (S);
         end;
      end loop;
   end loop;
   if not Contracts then
      declare
         All_Bytes : String (1 .. 256);
         Long      : String (1 .. Max_Length) := (others => 'a');
      begin
         for I in All_Bytes'Range loop
            All_Bytes (I) := Character'Val (I - 1);
         end loop;
         Exercise (All_Bytes, Oracle => False);
         Exercise (Long, Oracle => False);
         for I in Long'Range loop
            Long (I) := Character'Val ((I * 137 + I / 7) mod 256);
         end loop;
         Exercise (Long, Oracle => False);
      end;
   end if;
   Report;
end Test_BWT;
