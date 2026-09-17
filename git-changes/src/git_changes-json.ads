with Ada.Text_IO;

package Git_Changes.JSON is

   Schema_Version : constant Positive := 1;

   --  Write one schema-v1 document.  Every String originating outside the
   --  program is encoded byte-for-byte: JSON code point U+00XX represents
   --  input byte 16#XX#.  Include_Contents adds the available old/new blobs;
   --  content-loading failures stay local to their side and keep the document
   --  well formed.
   procedure Write
     (Repository       : Git_Changes.Repository;
      Changes          : Change_Set;
      Include_Contents : Boolean := False;
      Output           : Ada.Text_IO.File_Type := Ada.Text_IO.Current_Output);

end Git_Changes.JSON;
