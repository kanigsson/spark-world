with BWT;
with BWT.Circular;
with BWT.FM_Index;
with BWT.Locate;
with BWT.Search;
with Test_Checks;
with Ada.Command_Line;

procedure Test_BWT is
   use BWT;
   use Test_Checks;
   Contracts : constant Boolean := Ada.Command_Line.Argument_Count > 0;
   Alphabet  : constant String :=
     Character'Val (0) & Character'Val (128) & Character'Val (255);

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

   --  Occurrences of P read periodically from every position of S, each in
   --  S itself (classical) or in its Lyndon factor (bijective). The factors
   --  come from least suffixes, as in Reference.
   function Naive_Count (S, P : String; Bijective : Boolean) return Natural is
      Result : Natural := 0;
      Finish : Natural := S'Length;
      First  : Positive;
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
         declare
            Size : constant Positive := Finish - First + 1;
            Hit  : Boolean;
         begin
            for Offset in 0 .. Size - 1 loop
               Hit := True;
               for K in P'Range loop
                  Hit :=
                    Hit and then S (First + (Offset + K - 1) mod Size) = P (K);
               end loop;
               if Hit then
                  Result := Result + 1;
               end if;
            end loop;
         end;
         Finish := First - 1;
      end loop;
      return Result;
   end Naive_Count;

   --  Whether Position starts an occurrence of P, as Naive_Count reads it.
   function Naive_At
     (S, P : String; Bijective : Boolean; Position : Positive) return Boolean
   is
      Finish : Natural := S'Length;
      First  : Positive;
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
         if Position >= First then
            declare
               Size : constant Positive := Finish - First + 1;
            begin
               for K in P'Range loop
                  if S (First + (Position - First + K - 1) mod Size) /= P (K)
                  then
                     return False;
                  end if;
               end loop;
               return True;
            end;
         end if;
         Finish := First - 1;
      end loop;
      return False;
   end Naive_At;

   function Primitive (S : String) return Boolean is
   begin
      for Shift in 1 .. S'Length - 1 loop
         if S (Shift + 1 .. S'Last) & S (1 .. Shift) = S then
            return False;
         end if;
      end loop;
      return True;
   end Primitive;

   --  Locate lists each occurrence once, and only occurrences.
   procedure Check_Locate
     (S, P : String; Rows : Table; Bijective : Boolean; Name : String)
   is
      Found : constant Locate.Places :=
        Locate.Locate (Locate.Build (S, Rows), P);
      Seen  : array (1 .. S'Length) of Boolean := (others => False);
      OK    : Boolean := Found'Length = Naive_Count (S, P, Bijective);
   begin
      for Position of Found loop
         if Position not in Seen'Range
           or else Seen (Position)
           or else not Naive_At (S, P, Bijective, Position)
         then
            OK := False;
         else
            Seen (Position) := True;
         end if;
      end loop;
      Check (OK, Name);
   end Check_Locate;

   --  Backward search on both last columns agrees with the naive count.
   procedure Search_All (S, C, B, P : String) is
   begin
      if P'Length <= 2 * S'Length then
         Check
           (Search.Count (C, P) = Naive_Count (S, P, False),
            "classical count");
         Check
           (Search.Count (B, P) = Naive_Count (S, P, True), "bijective count");
         Check
           (FM_Index.Count (FM_Index.Build (C), P) = Naive_Count (S, P, False),
            "classical index count");
         --  The locator's contracts, executed, would dominate the contracts
         --  run; the runtime build checks it.
         if Contracts then
            return;
         end if;
         Check_Locate (S, P, Bijective_Sorted (S), True, "bijective locate");
         if Primitive (S) then
            Check_Locate
              (S, P, Classical_Sorted (S), False, "classical locate");
         end if;
      end if;
   end Search_All;

   --  The least rotation against materialized rotations and Ada's string
   --  order, and the canonical form's independence of where S was cut.
   procedure Check_Circular (S : String) is
      N : constant Natural := S'Length;

      --  Normalized to a first index of 1, as the API requires.
      function Turn (T : String; O : Natural) return String is
         R : constant String :=
           T (T'First + O .. T'Last) & T (T'First .. T'First + O - 1);
      begin
         return Result : constant String (1 .. R'Length) := R;
      end Turn;

      Best : Natural := 0;
   begin
      if N = 0 then
         Check (Circular.Canonical (S) = "", "circular: empty");
         return;
      end if;
      for O in 1 .. N - 1 loop
         if Turn (S, O) < Turn (S, Best) then
            Best := O;
         end if;
      end loop;
      Check (Circular.Least_Rotation (S) = Best, "circular: least offset");
      Check (Circular.Canonical (S) = Turn (S, Best), "circular: canonical");
      for O in 0 .. N - 1 loop
         Check
           (Circular.Canonical (Turn (S, O)) = Turn (S, Best),
            "circular: rotation invariance");
      end loop;
   end Check_Circular;

   procedure Exercise (S : String; Oracle : Boolean := True) is
      C : constant Classical_Result := Classical_Encode (S);
      B : constant String := Bijective_Encode (S);
   begin
      Search_All (S, C.Last, B, S);
      Search_All (S, C.Last, B, S & S);
      if Oracle then
         for Size in 0 .. 2 loop
            for Code in 0 .. 3**Size - 1 loop
               declare
                  P     : String (1 .. Size);
                  Value : Natural := Code;
               begin
                  for I in P'Range loop
                     P (I) := Alphabet (Value mod 3 + 1);
                     Value := Value / 3;
                  end loop;
                  Search_All (S, C.Last, B, P);
               end;
            end loop;
         end loop;
      end if;
      Check (Classical_Decode (C.Last, C.Primary) = S, "classical roundtrip");
      Check (Bijective_Decode (B) = S, "bijective roundtrip");
      Check (Bijective_Encode (Bijective_Decode (S)) = S, "bijective onto");
      Check_Circular (S);
      if Oracle then
         Check (C = Reference (S, False), "classical definition");
         Check (B = Reference (S, True).Last, "bijective definition");
      end if;
   end Exercise;

begin
   Start ("BWT", Stop_On_Fail => True);
   Check (Classical_Encode ("banana") = (6, "nnbaaa", 4), "banana BWT");
   Check (Bijective_Encode ("banana") = "annbaa", "banana BBWT");
   Check (Bijective_Encode ("babab") = "bbaab", "omega versus finite order");
   Check (Search.Count ("nnbaaa", "ana") = 2, "banana: ana");
   Check (Search.Count ("nnbaaa", "nab") = 1, "banana: circular nab");
   Check (Search.Count ("nnbaaa", "x") = 0, "banana: absent letter");
   Check (Search.Count ("nnbaaa", "") = 6, "banana: empty pattern");
   Check (Circular.Canonical ("banana") = "abanan", "banana: least rotation");
   Check (Circular.Least_Rotation ("abab") = 0, "abab: earliest least offset");
   Check (Circular.Least_Rotation ("baabaa") = 1, "baabaa: periodic");
   declare
      Text : constant String := "mississippi";
      Last : constant String := Classical_Encode (Text).Last;
      procedure Try (P : String) is
      begin
         Check
           (Search.Count (Last, P) = Naive_Count (Text, P, False),
            "mississippi: " & P);
      end Try;
   begin
      Try ("ss");
      Try ("ssi");
      Try ("issi");
      Try ("ppi");
      Try ("ipm");
      Try (Text);
   end;
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
         --  Long, not maximal: the reference encoders are cubic on
         --  repetitive input, so a block of Max_Length would not finish.
         All_Bytes : String (1 .. 256);
         Long      : String (1 .. 1_024) := (others => 'a');
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
