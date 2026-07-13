--  Command-line front end for the Inflate library.  File I/O and dynamic
--  allocation intentionally live here, outside the SPARK library.

with Ada.Command_Line;             use Ada.Command_Line;
with Ada.Exceptions;               use Ada.Exceptions;
with Ada.Streams;                  use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;                  use Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Interfaces;                   use Interfaces;

with Inflate;                      use Inflate;
with Inflate.GZip;
with Inflate.Raw;

procedure Inflate_CLI is

   type Byte_Array_Access is access Byte_Array;
   procedure Free is
     new Ada.Unchecked_Deallocation (Byte_Array, Byte_Array_Access);

   procedure Error (Message : String) is
   begin
      Put_Line (Standard_Error, "inflate: " & Message);
   end Error;

   procedure Usage (File : File_Type := Standard_Output) is
   begin
      Put_Line (File, "Usage: inflate compress INPUT OUTPUT");
      Put_Line (File, "       inflate decompress INPUT OUTPUT");
      Put_Line (File, "       inflate --help");
      New_Line (File);
      Put_Line
        (File,
         "Compress creates a gzip file using fixed Huffman coding and "
         & "verified run matches.");
      Put_Line (File, "Decompress accepts gzip files, including concatenated members.");
   end Usage;

   function Load (Name : String) return Byte_Array_Access is
      use Ada.Streams.Stream_IO;
      F : Ada.Streams.Stream_IO.File_Type;
   begin
      Open (F, In_File, Name);
      declare
         File_Length : constant Ada.Streams.Stream_IO.Count := Size (F);
      begin
         if File_Length > Ada.Streams.Stream_IO.Count (Buffer_Index'Last) then
            Close (F);
            raise Constraint_Error with "input file is too large";
         end if;

         declare
            Length : constant Natural := Natural (File_Length);
            Data   : Byte_Array_Access :=
              new Byte_Array (1 .. Length);
            Buffer : Stream_Element_Array
              (1 .. Stream_Element_Offset (Length));
            Last   : Stream_Element_Offset;
         begin
            if Length > 0 then
               Read (F, Buffer, Last);
               if Last /= Buffer'Last then
                  Close (F);
                  Free (Data);
                  raise Ada.Streams.Stream_IO.End_Error
                    with "short read from input file";
               end if;
               for I in Buffer'Range loop
                  Data (Natural (I)) := Byte (Buffer (I));
               end loop;
            end if;
            Close (F);
            return Data;
         end;
      end;
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise;
   end Load;

   procedure Save
     (Name : String; Data : Byte_Array; Length : Natural)
   is
      use Ada.Streams.Stream_IO;
      F      : Ada.Streams.Stream_IO.File_Type;
      Buffer : Stream_Element_Array
        (1 .. Stream_Element_Offset (Length));
   begin
      for I in Buffer'Range loop
         Buffer (I) := Stream_Element
           (Data (Data'First - 1 + Natural (I)));
      end loop;
      Create (F, Out_File, Name);
      if Length > 0 then
         Write (F, Buffer);
      end if;
      Close (F);
   exception
      when others =>
         if Is_Open (F) then
            Close (F);
         end if;
         raise;
   end Save;

   function LE32_At_End (Data : Byte_Array) return Word32 is
      P : constant Buffer_Index := Data'Last - 3;
   begin
      return Word32 (Data (P))
        or Shift_Left (Word32 (Data (P + 1)), 8)
        or Shift_Left (Word32 (Data (P + 2)), 16)
        or Shift_Left (Word32 (Data (P + 3)), 24);
   end LE32_At_End;

   procedure Compress_File (Input_Name, Output_Name : String) is
      Input : Byte_Array_Access := Load (Input_Name);
   begin
      if Input'Length > Inflate.Raw.Max_Compress_Input then
         Error ("input is too large to compress");
         Free (Input);
         Set_Exit_Status (Failure);
         return;
      end if;

      declare
         Output : Byte_Array_Access := new Byte_Array
           (1 .. Inflate.GZip.Compressed_Size (Input'Length));
         Produced : Natural;
      begin
         Inflate.GZip.Compress (Input.all, Output.all, Produced);
         Save (Output_Name, Output.all, Produced);
         Free (Output);
      end;
      Free (Input);
   end Compress_File;

   procedure Decompress_File (Input_Name, Output_Name : String) is
      Initial_Capacity_Limit : constant Natural := 8 * 1_024 * 1_024;
      Input    : Byte_Array_Access := Load (Input_Name);
      Output   : Byte_Array_Access;
      Capacity : Natural := 0;
      Produced : Natural;
      Status   : Status_Type;
   begin
      --  ISIZE, the last four bytes of a gzip member, is normally the exact
      --  answer.  For concatenated members it is only a useful first guess;
      --  retry with a larger one-shot buffer when necessary.
      if Input'Length >= 4 then
         declare
            Hint : constant Word32 := LE32_At_End (Input.all);
         begin
            if Hint <= Word32 (Buffer_Index'Last) then
               --  Do not let an untrusted trailer cause a huge allocation
               --  before the decoder has even validated the gzip header.
               Capacity := Natural'Min
                 (Natural (Hint), Initial_Capacity_Limit);
            end if;
         end;
      end if;

      loop
         Output := new Byte_Array (1 .. Capacity);
         Inflate.GZip.Decompress_All
           (Input.all, Output.all, Produced, Status);
         exit when Status /= Output_Too_Small;

         Free (Output);
         if Capacity = 0 then
            Capacity := Natural'Min (65_536, Buffer_Index'Last);
         elsif Capacity > Buffer_Index'Last / 2 then
            Error ("decompressed data is too large");
            Free (Input);
            Set_Exit_Status (Failure);
            return;
         else
            Capacity := Capacity * 2;
         end if;
      end loop;

      if Status /= OK then
         Error ("decompression failed: " & Status'Image);
         Free (Output);
         Free (Input);
         Set_Exit_Status (Failure);
         return;
      end if;

      Save (Output_Name, Output.all, Produced);
      Free (Output);
      Free (Input);
   end Decompress_File;

begin
   if Argument_Count = 1
     and then (Argument (1) = "--help" or else Argument (1) = "-h")
   then
      Usage;
   elsif Argument_Count /= 3 then
      Usage (Standard_Error);
      Set_Exit_Status (Failure);
   elsif Argument (1) = "compress" then
      Compress_File (Argument (2), Argument (3));
   elsif Argument (1) = "decompress" then
      Decompress_File (Argument (2), Argument (3));
   else
      Error ("unknown command '" & Argument (1) & "'");
      Usage (Standard_Error);
      Set_Exit_Status (Failure);
   end if;
exception
   when E : others =>
      Error (Exception_Message (E));
      Set_Exit_Status (Failure);
end Inflate_CLI;
