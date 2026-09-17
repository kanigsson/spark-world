with Git_Changes.Core.Validation;

package body Git_Changes.Core.Hunks with SPARK_Mode is

   LF : constant Character := Character'Val (10);

   procedure Parse_Next
     (Input  : String;
      Cursor : in out Positive;
      Item   : out Hunk;
      Result : out Hunk_Result)
   is
      Pos        : Positive := Cursor;
      Line_Start : Positive;
      Line_End   : Natural;
      Valid      : Boolean;

      procedure Advance_To_Header is
      begin
         while Pos <= Input'Last loop
            pragma Loop_Invariant (Pos >= Cursor);
            pragma Loop_Variant (Decreases => Input'Last - Pos + 1);
            if (Pos = Input'First or else Input (Pos - 1) = LF)
              and then Input'Last >= 4
              and then Pos <= Input'Last - 3
              and then Input (Pos .. Pos + 3) = "@@ -"
            then
               return;
            end if;
            Pos := Pos + 1;
         end loop;
      end Advance_To_Header;

      procedure Decimal (Number : out Natural; OK : out Boolean) is
         First : constant Positive := Pos;
      begin
         Number := 0;
         OK := False;
         while Pos <= Line_End and then Input (Pos) in '0' .. '9' loop
            pragma Loop_Invariant (Pos >= First);
            pragma Loop_Variant (Decreases => Line_End - Pos + 1);
            Pos := Pos + 1;
         end loop;
         if Pos = First then
            return;
         end if;
         Git_Changes.Core.Validation.Parse_Natural
           (Input (First .. Pos - 1), Number, OK);
      end Decimal;

      procedure Range_After
        (Marker : Character; Lines : out Line_Range; OK : out Boolean)
      is
         First_Line : Natural;
         Count      : Natural := 1;
      begin
         Lines := (First => 0, Count => 0);
         OK := False;
         if Pos > Line_End or else Input (Pos) /= Marker then
            return;
         end if;
         Pos := Pos + 1;
         Decimal (First_Line, Valid);
         if not Valid then
            return;
         end if;
         if Pos <= Line_End and then Input (Pos) = ',' then
            Pos := Pos + 1;
            Decimal (Count, Valid);
            if not Valid then
               return;
            end if;
         end if;
         if Count > 0 and then First_Line = 0 then
            return;
         end if;
         Lines := (First => First_Line, Count => Count);
         OK := True;
      end Range_After;

      Old_Range : Line_Range;
      New_Range : Line_Range;
      OK        : Boolean;
   begin
      Item :=
        (Old_Lines => (First => 1, Count => 1),
         New_Lines => (First => 1, Count => 1));
      Result := No_More_Hunks;
      Advance_To_Header;
      if Pos > Input'Last then
         Cursor := Pos;
         return;
      end if;

      Line_Start := Pos;
      Line_End := Pos;
      while Line_End <= Input'Last and then Input (Line_End) /= LF loop
         pragma Loop_Invariant (Line_End >= Line_Start);
         pragma Loop_Variant (Decreases => Input'Last - Line_End + 1);
         Line_End := Line_End + 1;
      end loop;
      if Line_End > Input'Last then
         Line_End := Input'Last;
      else
         Line_End := Line_End - 1;
      end if;

      Pos := Line_Start + 3;
      Range_After ('-', Old_Range, OK);
      if not OK or else Pos > Line_End or else Input (Pos) /= ' ' then
         Cursor := Line_End + 1;
         Result := Malformed_Hunk;
         return;
      end if;
      Pos := Pos + 1;
      Range_After ('+', New_Range, OK);
      if not OK or else Line_End < 3 or else Pos > Line_End - 2
        or else Input (Pos .. Pos + 2) /= " @@"
        or else (Old_Range.Count = 0 and then New_Range.Count = 0)
      then
         Cursor := Line_End + 1;
         Result := Malformed_Hunk;
         return;
      end if;

      Item := (Old_Lines => Old_Range, New_Lines => New_Range);
      Cursor := Line_End + 1;
      Result := Hunk_Parsed;
   end Parse_Next;

end Git_Changes.Core.Hunks;
