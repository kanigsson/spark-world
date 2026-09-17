package Git_Changes.Core.Raw with SPARK_Mode is

   type Slice is record
      First  : Positive := 1;
      Length : Natural := 0;
   end record;

   function Last (Item : Slice) return Natural is
     (if Item.Length = 0 then Item.First - 1
      else Item.First + (Item.Length - 1))
     with Pre => Item.Length = 0
       or else Item.First <= Natural'Last - (Item.Length - 1);

   function Value (Input : String; Item : Slice) return String is
     (Input (Item.First .. Last (Item)))
     with Pre => Item.Length > 0
       and then Item.First >= Input'First
       and then Item.First <= Input'Last
       and then Item.Length <= Input'Last - Item.First + 1;

   type Raw_Status is
     (Status_Added,
      Status_Copied,
      Status_Deleted,
      Status_Modified,
      Status_Renamed,
      Status_Type_Changed,
      Status_Unmerged,
      Status_Unknown,
      Status_Broken_Pair);

   type Raw_Record is record
      Old_Mode         : Slice;
      New_Mode         : Slice;
      Old_Object       : Slice;
      New_Object       : Slice;
      Status           : Raw_Status := Status_Unknown;
      Score            : Natural range 0 .. 100 := 0;
      Score_Present    : Boolean := False;
      First_Path       : Slice;
      Second_Path      : Slice;
      Has_Second_Path  : Boolean := False;
   end record;

   type Parse_Result is
     (Parsed,
      End_Of_Input,
      Expected_Colon,
      Missing_Field,
      Invalid_Mode,
      Invalid_Object_Id,
      Invalid_Status,
      Invalid_Score,
      Missing_Path,
      Missing_Second_Path,
      Trailing_Data);

   procedure Parse_Next
     (Input  : String;
      Cursor : in out Positive;
      Item   : out Raw_Record;
      Result : out Parse_Result)
     with Pre => Input'First = 1
       and then Input'Last < Positive'Last
       and then Cursor <= Input'Last + 1,
       Post => Cursor >= Cursor'Old;

end Git_Changes.Core.Raw;
