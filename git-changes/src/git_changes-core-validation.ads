package Git_Changes.Core.Validation with SPARK_Mode is
   function Is_Octal_Mode (Value : String) return Boolean;
   function Is_Hex_Object_Id (Value : String) return Boolean;
   function Is_All_Zero (Value : String) return Boolean;
   function Line_Count (Content : String) return Natural
     with Pre => Content'Length < Natural'Last,
       Post => Line_Count'Result <= Content'Length;

   procedure Parse_Natural
     (Value  : String;
      Result : out Natural;
      Valid  : out Boolean)
     with Post => (if Valid then Result <= Natural'Last);

   procedure Checked_Last
     (First  : Natural;
      Count  : Natural;
      Last   : out Natural;
      Valid  : out Boolean)
     with Post =>
       (if Valid then
          (if Count = 0 then Last = First
           else Last = First + (Count - 1)));
end Git_Changes.Core.Validation;
