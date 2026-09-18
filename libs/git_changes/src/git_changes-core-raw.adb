with Git_Changes.Core.Validation;

package body Git_Changes.Core.Raw
  with SPARK_Mode
is

   NUL : constant Character := Character'Val (0);

   procedure Find
     (Input    : String;
      From     : Positive;
      Target   : Character;
      Position : out Natural;
      Found    : out Boolean)
   with
     Pre  =>
       Input'First = 1
       and then Input'Last < Positive'Last
       and then From <= Input'Last + 1,
     Post =>
       (if Found
        then
          Position >= From
          and then Position <= Input'Last
          and then Input (Position) = Target
        else Position = 0)
   is
      J : Positive := From;
   begin
      Position := 0;
      Found := False;
      while J <= Input'Last loop
         pragma Loop_Invariant (J >= From);
         pragma Loop_Variant (Decreases => Input'Last - J + 1);
         if Input (J) = Target then
            Position := J;
            Found := True;
            return;
         end if;
         J := J + 1;
      end loop;
   end Find;

   procedure Parse_Next
     (Input  : String;
      Cursor : in out Positive;
      Item   : out Raw_Record;
      Result : out Parse_Result)
   is
      Initial       : constant Positive := Cursor;
      Pos           : Positive;
      Stop          : Natural;
      Found         : Boolean;
      Score         : Natural;
      Valid         : Boolean;
      Status_Length : Natural;

      procedure Token_To_Space (Token : out Slice; OK : out Boolean)
      with
        Pre  =>
          Input'First = 1
          and then Input'Last < Positive'Last
          and then Pos <= Input'Last + 1,
        Post =>
          Pos >= Pos'Old
          and then Pos <= Input'Last + 1
          and then (if OK
                    then
                      Token.Length > 0
                      and then Token.First >= Input'First
                      and then Token.First <= Input'Last
                      and then Token.Length <= Input'Last - Token.First + 1
                    else Pos = Pos'Old)
      is
         Space   : Natural;
         Located : Boolean;
      begin
         Token := (First => 1, Length => 0);
         OK := False;
         Find (Input, Pos, ' ', Space, Located);
         if not Located or else Space = Pos then
            return;
         end if;
         Token := (First => Pos, Length => Space - Pos);
         Pos := Space + 1;
         OK := True;
      end Token_To_Space;

      OK : Boolean;
   begin
      Item := (others => <>);
      Result := End_Of_Input;
      if Cursor > Input'Last then
         return;
      end if;
      if Input (Cursor) /= ':' then
         Result := Expected_Colon;
         return;
      end if;
      if Cursor = Input'Last then
         Result := Missing_Field;
         return;
      end if;
      Pos := Cursor + 1;

      Token_To_Space (Item.Old_Mode, OK);
      if not OK then
         Result := Missing_Field;
         return;
      end if;
      Token_To_Space (Item.New_Mode, OK);
      if not OK then
         Result := Missing_Field;
         return;
      end if;
      Token_To_Space (Item.Old_Object, OK);
      if not OK then
         Result := Missing_Field;
         return;
      end if;
      Token_To_Space (Item.New_Object, OK);
      if not OK then
         Result := Missing_Field;
         return;
      end if;

      if not Git_Changes.Core.Validation.Is_Octal_Mode
               (Value (Input, Item.Old_Mode))
        or else not Git_Changes.Core.Validation.Is_Octal_Mode
                      (Value (Input, Item.New_Mode))
      then
         Result := Invalid_Mode;
         return;
      end if;
      if not Git_Changes.Core.Validation.Is_Hex_Object_Id
               (Value (Input, Item.Old_Object))
        or else not Git_Changes.Core.Validation.Is_Hex_Object_Id
                      (Value (Input, Item.New_Object))
        or else Item.Old_Object.Length /= Item.New_Object.Length
      then
         Result := Invalid_Object_Id;
         return;
      end if;

      Find (Input, Pos, NUL, Stop, Found);
      if not Found or else Stop = Pos then
         Result := Invalid_Status;
         return;
      end if;
      Status_Length := Stop - Pos;
      case Input (Pos) is
         when 'A'    =>
            Item.Status := Status_Added;

         when 'C'    =>
            Item.Status := Status_Copied;

         when 'D'    =>
            Item.Status := Status_Deleted;

         when 'M'    =>
            Item.Status := Status_Modified;

         when 'R'    =>
            Item.Status := Status_Renamed;

         when 'T'    =>
            Item.Status := Status_Type_Changed;

         when 'U'    =>
            Item.Status := Status_Unmerged;

         when 'X'    =>
            Item.Status := Status_Unknown;

         when 'B'    =>
            Item.Status := Status_Broken_Pair;

         when others =>
            Result := Invalid_Status;
            return;
      end case;

      if Item.Status in Status_Copied | Status_Renamed then
         if Status_Length = 1 then
            Result := Invalid_Score;
            return;
         end if;
         Git_Changes.Core.Validation.Parse_Natural
           (Input (Pos + 1 .. Stop - 1), Score, Valid);
         if not Valid or else Score > 100 then
            Result := Invalid_Score;
            return;
         end if;
         Item.Score := Score;
         Item.Score_Present := True;
      elsif Item.Status = Status_Modified and then Status_Length > 1 then
         Git_Changes.Core.Validation.Parse_Natural
           (Input (Pos + 1 .. Stop - 1), Score, Valid);
         if not Valid or else Score > 100 then
            Result := Invalid_Score;
            return;
         end if;
         Item.Score := Score;
         Item.Score_Present := True;
      elsif Status_Length /= 1 then
         Result := Invalid_Status;
         return;
      end if;

      Pos := Stop + 1;
      Find (Input, Pos, NUL, Stop, Found);
      if not Found or else Stop = Pos then
         Result := Missing_Path;
         return;
      end if;
      Item.First_Path := (First => Pos, Length => Stop - Pos);
      Pos := Stop + 1;

      if Item.Status in Status_Copied | Status_Renamed then
         Find (Input, Pos, NUL, Stop, Found);
         if not Found or else Stop = Pos then
            Result := Missing_Second_Path;
            return;
         end if;
         Item.Second_Path := (First => Pos, Length => Stop - Pos);
         Item.Has_Second_Path := True;
         Pos := Stop + 1;
      end if;

      Cursor := Pos;
      Result := Parsed;
      pragma Assert (Cursor > Initial);
   end Parse_Next;

end Git_Changes.Core.Raw;
