with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Git_Changes.Contents;

package body Git_Changes.JSON is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   Hex : constant array (Natural range 0 .. 15) of Character :=
     "0123456789abcdef";

   procedure Put_Quoted (Output : File_Type; Value : String) is
      Code : Natural;
   begin
      Put (Output, '"');
      for C of Value loop
         Code := Character'Pos (C);
         case C is
            when '"'                                  =>
               Put (Output, "\""");

            when '\'                                  =>
               Put (Output, "\\");

            when Character'Val (8)                    =>
               Put (Output, "\b");

            when Character'Val (9)                    =>
               Put (Output, "\t");

            when Character'Val (10)                   =>
               Put (Output, "\n");

            when Character'Val (12)                   =>
               Put (Output, "\f");

            when Character'Val (13)                   =>
               Put (Output, "\r");

            when ' ' .. '!' | '#' .. '[' | ']' .. '~' =>
               Put (Output, C);

            when others                               =>
               Put (Output, "\u00");
               Put (Output, Hex (Code / 16));
               Put (Output, Hex (Code mod 16));
         end case;
      end loop;
      Put (Output, '"');
   end Put_Quoted;

   procedure Put_Name (Output : File_Type; Name : String) is
   begin
      Put_Quoted (Output, Name);
      Put (Output, ':');
   end Put_Name;

   procedure Put_Boolean (Output : File_Type; Value : Boolean) is
   begin
      Put (Output, (if Value then "true" else "false"));
   end Put_Boolean;

   procedure Put_Natural (Output : File_Type; Value : Natural) is
      Image : constant String := Natural'Image (Value);
   begin
      Put (Output, Image (Image'First + 1 .. Image'Last));
   end Put_Natural;

   function Lower (Value : String) return String is
      Result : String := Value;
   begin
      for C of Result loop
         if C = '_' then
            C := '-';
         else
            C := Ada.Characters.Handling.To_Lower (C);
         end if;
      end loop;
      return Result;
   end Lower;

   procedure Put_Endpoint (Output : File_Type; Item : Endpoint_Info) is
   begin
      Put (Output, '{');
      Put_Name (Output, "kind");
      Put_Quoted (Output, Lower (Endpoint_Kind'Image (Kind (Item))));
      Put (Output, ',');
      Put_Name (Output, "requested");
      Put_Quoted (Output, Requested_Name (Item));
      Put (Output, ',');
      Put_Name (Output, "resolved");
      Put_Quoted (Output, Resolved_Identity (Item));
      Put (Output, '}');
   end Put_Endpoint;

   procedure Put_Content
     (Output : File_Type; Changes : Change_Set; File : Positive; Which : Side)
   is
      Value : Unbounded_String;
      Error : Error_Info;
   begin
      Git_Changes.Contents.Load (Changes, File, Which, Value, Error);
      if Success (Error) then
         Put_Quoted (Output, To_String (Value));
      else
         Put (Output, "null,");
         Put_Name (Output, "content_error");
         Put_Quoted (Output, Detail (Error));
      end if;
   end Put_Content;

   procedure Put_Side
     (Output           : File_Type;
      Changes          : Change_Set;
      File             : Positive;
      Which            : Side;
      Include_Contents : Boolean)
   is
      Present : constant Boolean := Has_Path (Changes, File, Which);
   begin
      if not Present then
         Put (Output, "null");
         return;
      end if;

      Put (Output, '{');
      Put_Name (Output, "path");
      Put_Quoted (Output, Path (Changes, File, Which));
      Put (Output, ',');
      Put_Name (Output, "mode");
      if Has_Mode (Changes, File, Which) then
         Put_Quoted (Output, Mode (Changes, File, Which));
      else
         Put (Output, "null");
      end if;
      Put (Output, ',');
      Put_Name (Output, "object_id");
      if Has_Object_Id (Changes, File, Which) then
         Put_Quoted (Output, Object_Id (Changes, File, Which));
      else
         Put (Output, "null");
      end if;
      Put (Output, ',');
      Put_Name (Output, "content_available");
      Put_Boolean (Output, Content_Available (Changes, File, Which));
      if Include_Contents then
         Put (Output, ',');
         Put_Name (Output, "content");
         if Content_Available (Changes, File, Which) then
            Put_Content (Output, Changes, File, Which);
         else
            Put (Output, "null");
         end if;
      end if;
      Put (Output, '}');
   end Put_Side;

   procedure Write
     (Repository       : Git_Changes.Repository;
      Changes          : Change_Set;
      Include_Contents : Boolean := False;
      Output           : File_Type := Current_Output) is
   begin
      Put (Output, '{');
      Put_Name (Output, "schema_version");
      Put_Natural (Output, Schema_Version);
      Put (Output, ',');
      Put_Name (Output, "byte_encoding");
      Put_Quoted (Output, "json-code-point-u00xx");
      Put (Output, ',');
      Put_Name (Output, "repository");
      Put (Output, '{');
      Put_Name (Output, "root");
      Put_Quoted (Output, Root_Path (Repository));
      Put (Output, ',');
      Put_Name (Output, "git_directory");
      Put_Quoted (Output, Git_Directory (Repository));
      Put (Output, ',');
      Put_Name (Output, "object_format");
      Put_Quoted (Output, Object_Format (Repository));
      Put (Output, ',');
      Put_Name (Output, "bare");
      Put_Boolean (Output, Is_Bare (Repository));
      Put (Output, "},");
      Put_Name (Output, "comparison");
      Put (Output, '{');
      Put_Name (Output, "kind");
      Put_Quoted
        (Output, Lower (Comparison_Kind'Image (Comparison_Used (Changes))));
      Put (Output, ',');
      Put_Name (Output, "old");
      Put_Endpoint (Output, Old_Endpoint (Changes));
      Put (Output, ',');
      Put_Name (Output, "new");
      Put_Endpoint (Output, New_Endpoint (Changes));
      Put (Output, "},");
      Put_Name (Output, "stale");
      Put_Boolean (Output, Is_Stale (Changes));
      Put (Output, ',');
      Put_Name (Output, "files");
      Put (Output, '[');
      for File in 1 .. File_Count (Changes) loop
         if File > 1 then
            Put (Output, ',');
         end if;
         Put (Output, '{');
         Put_Name (Output, "id");
         Put_Quoted (Output, File_Id (Changes, File));
         Put (Output, ',');
         Put_Name (Output, "kind");
         Put_Quoted
           (Output, Lower (Change_Kind'Image (File_Kind (Changes, File))));
         Put (Output, ',');
         Put_Name (Output, "old");
         Put_Side (Output, Changes, File, Old_Side, Include_Contents);
         Put (Output, ',');
         Put_Name (Output, "new");
         Put_Side (Output, Changes, File, New_Side, Include_Contents);
         Put (Output, ',');
         Put_Name (Output, "similarity");
         if Has_Similarity (Changes, File) then
            Put_Natural (Output, Similarity (Changes, File));
         else
            Put (Output, "null");
         end if;
         Put (Output, ',');
         Put_Name (Output, "binary");
         Put_Boolean (Output, Is_Binary (Changes, File));
         Put (Output, ',');
         Put_Name (Output, "submodule");
         Put_Boolean (Output, Is_Submodule (Changes, File));
         Put (Output, ',');
         Put_Name (Output, "diagnostic");
         Put_Quoted (Output, File_Diagnostic (Changes, File));
         Put (Output, ',');
         Put_Name (Output, "spans");
         Put (Output, '[');
         for Number in 1 .. Span_Count (Changes, File) loop
            declare
               Item : constant Changed_Span := Span (Changes, File, Number);
            begin
               if Number > 1 then
                  Put (Output, ',');
               end if;
               Put (Output, '{');
               Put_Name (Output, "id");
               Put_Quoted (Output, Span_Id (Changes, File, Number));
               Put (Output, ',');
               Put_Name (Output, "old");
               if Item.Old_Count = 0 then
                  Put (Output, "null");
               else
                  Put (Output, '{');
                  Put_Name (Output, "first");
                  Put_Natural (Output, Item.Old_First);
                  Put (Output, ',');
                  Put_Name (Output, "count");
                  Put_Natural (Output, Item.Old_Count);
                  Put (Output, '}');
               end if;
               Put (Output, ',');
               Put_Name (Output, "new");
               if Item.New_Count = 0 then
                  Put (Output, "null");
               else
                  Put (Output, '{');
                  Put_Name (Output, "first");
                  Put_Natural (Output, Item.New_First);
                  Put (Output, ',');
                  Put_Name (Output, "count");
                  Put_Natural (Output, Item.New_Count);
                  Put (Output, '}');
               end if;
               Put (Output, '}');
            end;
         end loop;
         Put (Output, "]}");
      end loop;
      Put_Line (Output, "]}");
   end Write;

end Git_Changes.JSON;
