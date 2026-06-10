--  NOT SPARK: subprocess and file-system glue, trusted behind the spec's
--  contracts.

with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;

package body Git_View_Source.OS with SPARK_Mode => Off is

   use GNAT.OS_Lib;

   type Content_Buffer is access Tui.Text.Buffer;

   procedure Free is
     new Ada.Unchecked_Deallocation (Tui.Text.Buffer, Content_Buffer);

   --------------------------------------------------------------------------
   --  Read an entire regular file straight into one heap buffer: Stream_IO
   --  reads into a Stream_Element_Array overlaid on the buffer, in place.
   --  Null if the file cannot be read.
   --------------------------------------------------------------------------
   function Read_File (Path : String) return Content_Buffer is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;
      F : File_Type;
   begin
      Open (F, In_File, Path);
      declare
         Len  : constant Natural := Natural (Size (F));
         Buf  : constant Content_Buffer := new Tui.Text.Buffer (1 .. Len);
         SEA  : Stream_Element_Array (1 .. Stream_Element_Offset (Len))
           with Import, Address => Buf.all'Address;
         Last : Stream_Element_Offset;
      begin
         if Len > 0 then
            Read (F, SEA, Last);
         end if;
         Close (F);
         return Buf;
      end;
   exception
      when others =>
         return null;
   end Read_File;

   --------------
   -- Find_Git --
   --------------

   function Find_Git return Boolean is
      Git : String_Access := Locate_Exec_On_Path ("git");
   begin
      if Git = null then
         return False;
      end if;
      Free (Git);
      return True;
   end Find_Git;

   -------------
   -- Capture --
   -------------

   procedure Capture
     (Args       : Argument_Vector;
      Err_To_Out : Boolean;
      Doc        : out Tui.Text.Doc_Ref;
      Code       : out Integer)
   is
      Git  : String_Access := Locate_Exec_On_Path ("git");
      FD   : File_Descriptor;
      Name : String_Access;
      Heap : Argument_List (1 .. Args'Length);
   begin
      Doc  := null;
      Code := -1;
      if Git = null then
         return;
      end if;

      --  The bounded arguments become the heap strings the spawn API wants.
      for I in Heap'Range loop
         declare
            A : Argument renames Args (Args'First + (I - 1));
         begin
            Heap (I) := new String'(A.Text (1 .. A.Len));
         end;
      end loop;

      Create_Temp_File (FD, Name);
      if FD = Invalid_FD or else Name = null then
         for H of Heap loop
            Free (H);
         end loop;
         Free (Git);
         return;
      end if;

      Spawn (Git.all, Heap, FD, Code, Err_To_Out);
      Close (FD);
      Free (Git);
      for H of Heap loop
         Free (H);
      end loop;

      declare
         Raw : Content_Buffer := Read_File (Name.all);
      begin
         if Raw /= null then
            Doc := Tui.Text.New_Document (Raw.all);
            Free (Raw);
         end if;
      end;

      declare
         Deleted : Boolean;
      begin
         Delete_File (Name.all, Deleted);
      end;
      Free (Name);
   end Capture;

end Git_View_Source.OS;
