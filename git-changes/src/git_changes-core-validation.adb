package body Git_Changes.Core.Validation with SPARK_Mode is

   function Is_Octal_Mode (Value : String) return Boolean is
   begin
      if Value'Length /= 6 then
         return False;
      end if;
      for C of Value loop
         if C not in '0' .. '7' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Octal_Mode;

   function Is_Hex_Object_Id (Value : String) return Boolean is
   begin
      if Value'Length not in 40 | 64 then
         return False;
      end if;
      for C of Value loop
         if C not in '0' .. '9' and then
           C not in 'a' .. 'f' and then C not in 'A' .. 'F'
         then
            return False;
         end if;
      end loop;
      return True;
   end Is_Hex_Object_Id;

   function Is_All_Zero (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;
      for C of Value loop
         if C /= '0' then
            return False;
         end if;
      end loop;
      return True;
   end Is_All_Zero;

   function Line_Count (Content : String) return Natural is
      Result : Natural := 0;
   begin
      for J in Content'Range loop
         pragma Loop_Invariant (Result <= J - Content'First);
         if Content (J) = Character'Val (10) then
            Result := Result + 1;
         end if;
      end loop;
      if Content'Length > 0
        and then Content (Content'Last) /= Character'Val (10)
      then
         Result := Result + 1;
      end if;
      return Result;
   end Line_Count;

   procedure Parse_Natural
     (Value  : String;
      Result : out Natural;
      Valid  : out Boolean)
   is
      Accum : Natural := 0;
      Digit : Natural;
   begin
      Result := 0;
      Valid := False;
      if Value'Length = 0 then
         return;
      end if;

      for J in Value'Range loop
         if Value (J) not in '0' .. '9' then
            return;
         end if;
         Digit := Character'Pos (Value (J)) - Character'Pos ('0');
         if Accum > (Natural'Last - Digit) / 10 then
            return;
         end if;
         Accum := Accum * 10 + Digit;
      end loop;
      Result := Accum;
      Valid := True;
   end Parse_Natural;

   procedure Checked_Last
     (First  : Natural;
      Count  : Natural;
      Last   : out Natural;
      Valid  : out Boolean) is
   begin
      if Count = 0 then
         Last := First;
         Valid := True;
      elsif First > Natural'Last - (Count - 1) then
         Last := 0;
         Valid := False;
      else
         Last := First + (Count - 1);
         Valid := True;
      end if;
   end Checked_Last;

end Git_Changes.Core.Validation;
