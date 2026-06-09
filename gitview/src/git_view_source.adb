--  NOT SPARK: subprocess and file-system glue, trusted behind the spec's
--  contracts.

with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;

package body Git_View_Source with SPARK_Mode => Off is

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

   --------------------------------------------------------------------------
   --  Run git with Args, capturing its stdout in a temporary file, and load
   --  that file into a fresh document. Doc is null when the subprocess could
   --  not be run or its output could not be read back; Code is git's exit
   --  status (-1 when it never ran). Err_To_Out folds the subprocess's
   --  stderr into the captured output — wanted while the alternate screen is
   --  up, where stray terminal writes would scribble over the interface.
   --------------------------------------------------------------------------
   procedure Capture
     (Args       : Argument_List;
      Err_To_Out : Boolean;
      Doc        : out Tui.Text.Doc_Ref;
      Code       : out Integer)
   is
      Git  : String_Access := Locate_Exec_On_Path ("git");
      FD   : File_Descriptor;
      Name : String_Access;
   begin
      Doc  := null;
      Code := -1;
      if Git = null then
         return;
      end if;

      Create_Temp_File (FD, Name);
      if FD = Invalid_FD or else Name = null then
         Free (Git);
         return;
      end if;

      Spawn (Git.all, Args, FD, Code, Err_To_Out);
      Close (FD);
      Free (Git);

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

   procedure Free_All (Args : in out Argument_List) is
   begin
      for A of Args loop
         Free (A);
      end loop;
   end Free_All;

   --  A one-line document carrying Msg, for the failure fallback.
   function Text_Document (Msg : String) return Tui.Text.Doc_Ref is
      Buf : Tui.Text.Buffer (1 .. Msg'Length);
   begin
      for I in Msg'Range loop
         Buf (Tui.Text.Byte_Index (I - Msg'First + 1)) :=
           Character'Pos (Msg (I));
      end loop;
      return Tui.Text.New_Document (Buf);
   end Text_Document;

   ---------------
   -- Available --
   ---------------

   function Available return Boolean is
      Git : String_Access := Locate_Exec_On_Path ("git");
   begin
      if Git = null then
         return False;
      end if;
      Free (Git);
      return True;
   end Available;

   --------------
   -- Load_Log --
   --------------

   procedure Load_Log (Doc : out Tui.Text.Doc_Ref; Ok : out Boolean) is
      --  The abbreviated id must stay the first space-terminated token of
      --  every line: the proved commit-id parser depends on it. No --graph
      --  for the same reason — its continuation lines carry no commit.
      Args : Argument_List :=
        (new String'("log"),
         new String'("--date=short"),
         new String'("--pretty=format:%h %ad %an %s"));
      Code : Integer;
   begin
      Capture (Args, Err_To_Out => False, Doc => Doc, Code => Code);
      Free_All (Args);
      if Code /= 0 and then Doc /= null then
         Tui.Text.Free (Doc);
      end if;
      Ok := Doc /= null;
   end Load_Log;

   ---------------
   -- Load_Diff --
   ---------------

   procedure Load_Diff
     (Id  : Git_View_Sha.Sha;
      Doc : in out Tui.Text.Doc_Ref;
      Ok  : out Boolean)
   is
      Args : Argument_List :=
        (new String'("show"),
         new String'(Git_View_Sha.Image (Id)));
      Code : Integer;
   begin
      Tui.Text.Free (Doc);   --  reclaim the replaced document (no-op on null)

      --  Fold stderr into the pane: the alternate screen is up by now, and
      --  git's own message in the diff pane beats a corrupted display.
      Capture (Args, Err_To_Out => True, Doc => Doc, Code => Code);
      Free_All (Args);
      Ok := Code = 0 and then Doc /= null;
      if Doc = null then
         Doc := Text_Document ("git show " & Git_View_Sha.Image (Id)
                               & " failed");
      end if;
   end Load_Diff;

end Git_View_Source;
