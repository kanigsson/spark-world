package Git_Changes.Backends is
   subtype Backend_String is Ada.Strings.Unbounded.Unbounded_String;

   type Argument_Array is
     array (Positive range <>) of Backend_String;

   procedure Run_Git
     (Working_Directory : String;
      Arguments         : Argument_Array;
      Max_Output_Bytes  : Positive;
      Operation         : String;
      Output            : out Backend_String;
      Error             : out Error_Info);

   procedure Read_File
     (Name              : String;
      Max_Content_Bytes : Positive;
      Content           : out Backend_String;
      Error             : out Error_Info);

   function Trim_Line_End (Value : String) return String;
   function Digest (Value : String) return String;
   function Git_Blob_Id (Object_Format, Content : String) return String;

end Git_Changes.Backends;
