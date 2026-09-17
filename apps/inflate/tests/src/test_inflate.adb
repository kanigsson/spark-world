--  Manifest-driven test harness (the thin, full-Ada edge around the SPARK
--  crate: file I/O and reporting live here, not in the library).
--
--  Each manifest line has five tab-separated fields:
--
--    mode      raw | zlib | gzip | gzip_all
--    input     path to the compressed bytes
--    expected  path to the expected output, or "-" if the decode must fail
--    out_cap   output buffer size to offer the decoder
--    consumed  expected Consumed value, or -1 to skip that check
--
--  Output: one PASS/FAIL line per case plus a summary; exit status 1 if
--  any case fails. A propagated exception is a FAIL of its own kind.

with Ada.Command_Line;          use Ada.Command_Line;
with Ada.Exceptions;            use Ada.Exceptions;
with Ada.Streams;               use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;               use Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Ore;
use type Ore.Word32;
use type Ore.Byte_Array;

with Inflate;                   use Inflate;
with Inflate.Adler32;
with Inflate.CRC32;
with Inflate.Raw;
with Inflate.ZLib;
with Inflate.GZip;
with Inflate.ZIP;
with Inflate.Model;

procedure Test_Inflate is

   type Byte_Array_Access is access Byte_Array;
   procedure Free is
     new Ada.Unchecked_Deallocation (Byte_Array, Byte_Array_Access);

   function Load (Name : String) return Byte_Array_Access is
      use Ada.Streams.Stream_IO;
      F : Ada.Streams.Stream_IO.File_Type;
   begin
      Open (F, In_File, Name);
      declare
         Len : constant Natural := Natural (Size (F));
         Buf : constant Byte_Array_Access := new Byte_Array (1 .. Len);
         SEA : Stream_Element_Array (1 .. Stream_Element_Offset (Len));
         Last : Stream_Element_Offset;
      begin
         if Len > 0 then
            Read (F, SEA, Last);
            for I in SEA'Range loop
               Buf (Natural (I)) := Byte (SEA (I));
            end loop;
         end if;
         Close (F);
         return Buf;
      end;
   end Load;

   procedure Save (Name : String; Data : Byte_Array) is
      use Ada.Streams.Stream_IO;
      F   : Ada.Streams.Stream_IO.File_Type;
      SEA : Stream_Element_Array
              (1 .. Stream_Element_Offset (Data'Length));
   begin
      for I in SEA'Range loop
         SEA (I) := Stream_Element
           (Data (Data'First - 1 + Natural (I)));
      end loop;
      Create (F, Out_File, Name);
      if Data'Length > 0 then
         Write (F, SEA);
      end if;
      Close (F);
   end Save;

   --  Fields of the current manifest line
   Line_Max : constant := 4096;

   Failures, Cases : Natural := 0;

   procedure Run_Case
     (Mode, In_Path, Exp_Path : String;
      Out_Cap                 : Natural;
      Exp_Consumed            : Integer)
   is
      Input    : Byte_Array_Access := Load (In_Path);
      Output   : Byte_Array_Access := new Byte_Array (1 .. Out_Cap);
      Expected : Byte_Array_Access :=
        (if Exp_Path = "-" or else Exp_Path = "?"
         then null else Load (Exp_Path));
      Consumed, Produced : Natural := 0;
      Status   : Status_Type;
      Label    : constant String := Mode & " " & In_Path;

      procedure Fail (Why : String) is
      begin
         Failures := Failures + 1;
         Put_Line ("FAIL " & Label & ": " & Why);
      end Fail;
   begin
      Cases := Cases + 1;

      if Mode = "raw" then
         Raw.Decompress (Input.all, Output.all, Consumed, Produced, Status);
      elsif Mode = "zlib" then
         ZLib.Decompress (Input.all, Output.all, Consumed, Produced, Status);
      elsif Mode = "gzip" then
         GZip.Decompress (Input.all, Output.all, Consumed, Produced, Status);
      elsif Mode = "gzip_all" then
         GZip.Decompress_All (Input.all, Output.all, Produced, Status);
         Consumed := Input'Length;
      elsif Mode = "zip" then
         --  Extract every entry, concatenating the contents
         declare
            C     : Inflate.ZIP.Cursor;
            E     : Inflate.ZIP.Entry_Info;
            Count : Natural;
            P     : Natural;
         begin
            Inflate.ZIP.Open (Input.all, C, Count, Status);
            while Status = OK and then Inflate.ZIP.Has_Next (C) loop
               Inflate.ZIP.Next (Input.all, C, E, Status);
               exit when Status /= OK;
               Inflate.ZIP.Extract
                 (Input.all, E,
                  Output (Produced + 1 .. Output'Last), P, Status);
               Produced := Produced + P;
            end loop;
            Consumed := Input'Length;
         end;
      elsif Mode = "compress" then
         --  The input file holds the data to compress. Compress, check
         --  the in-process round trip and the independent executable DEFLATE
         --  model, and drop the gzip member next to the input for the Python
         --  driver's differential check against C zlib.
         if Input'Length > Raw.Max_Compress_Input then
            Fail ("input too large for the compressor");
         else
            declare
               Comp : Byte_Array_Access := new Byte_Array
                 (1 .. GZip.Compressed_Size (Input'Length));
               Comp_Produced : Natural;
            begin
               GZip.Compress (Input.all, Comp.all, Comp_Produced);
               GZip.Decompress
                 (Comp.all, Output.all, Consumed, Produced, Status);
               if Status /= OK then
                  Fail ("round trip rejected with " & Status'Image);
               elsif Produced /= Input'Length
                 or else Output (1 .. Produced) /= Input.all
               then
                  Fail ("round trip differs (produced" & Produced'Image
                        & ")");
               elsif Consumed /= Comp_Produced then
                  Fail ("round trip consumed" & Consumed'Image
                        & ", expected" & Comp_Produced'Image);
               elsif not Model.Is_Decoding
                 (Comp (11 .. Comp_Produced), Input.all,
                  Comp_Produced - 18, Input'Length)
               then
                  Fail ("executable DEFLATE model does not hold");
               end if;
               Save (In_Path & ".gz", Comp (1 .. Comp_Produced));
               Free (Comp);
            end;
         end if;
         Free (Input);
         Free (Output);
         return;
      else
         Fail ("unknown mode");
         return;
      end if;

      if Exp_Path = "?" then
         null;  --  no expectation: the case only asserts "no exception"
      elsif Expected = null then
         if Status = OK then
            Fail ("accepted, expected an error (produced"
                  & Produced'Image & ")");
         end if;
      else
         if Status /= OK then
            Fail ("rejected with " & Status'Image & ", expected"
                  & Natural'Image (Expected'Length) & " bytes");
         elsif Produced /= Expected'Length
           or else Output (1 .. Produced) /= Expected.all
         then
            Fail ("output differs (produced" & Produced'Image
                  & ", expected" & Natural'Image (Expected'Length) & ")");
         elsif Exp_Consumed >= 0 and then Consumed /= Exp_Consumed then
            Fail ("consumed" & Consumed'Image & ", expected"
                  & Exp_Consumed'Image);
         end if;
      end if;

      Free (Input);
      Free (Output);
      Free (Expected);
   exception
      when E : others =>
         Failures := Failures + 1;
         Put_Line ("FAIL " & Label & ": EXCEPTION " & Exception_Name (E)
                   & ": " & Exception_Message (E));
   end Run_Case;

   Manifest : Ada.Text_IO.File_Type;
   CRC_Check_Input : constant Byte_Array (1 .. 9) :=
     (16#31#, 16#32#, 16#33#, 16#34#, 16#35#,
      16#36#, 16#37#, 16#38#, 16#39#);
begin
   if Argument_Count /= 1 then
      Put_Line ("usage: test_inflate MANIFEST");
      Set_Exit_Status (2);
      return;
   end if;

   --  CRC-32/ISO-HDLC's standard check value for ASCII "123456789" pins
   --  the reflected polynomial model's initialization and final XOR to the
   --  external convention, independently of gzip parsing.
   if Inflate.CRC32.Compute (CRC_Check_Input) /= 16#CBF4_3926# then
      Put_Line ("FAIL CRC-32 standard check vector");
      Set_Exit_Status (1);
      return;
   end if;

   --  The Adler-32 check value for the same conventional string pins the
   --  direct running-sums model to the externally specified checksum.
   if Inflate.Adler32.Compute (CRC_Check_Input) /= 16#091E_01DE# then
      Put_Line ("FAIL Adler-32 standard check vector");
      Set_Exit_Status (1);
      return;
   end if;

   if Inflate.Adler32.Update
        (Inflate.Adler32.Update (1, CRC_Check_Input (1 .. 4)),
         CRC_Check_Input (5 .. 9)) /= 16#091E_01DE#
   then
      Put_Line ("FAIL incremental Adler-32 check vector");
      Set_Exit_Status (1);
      return;
   end if;

   Open (Manifest, In_File, Argument (1));
   while not End_Of_File (Manifest) loop
      declare
         Line : constant String := Get_Line (Manifest);
         F    : array (1 .. 6) of Natural := (others => 0);
         N    : Natural := 0;
      begin
         if Line'Length > 0 and then Line (Line'First) /= '#' then
            if Line'Length > Line_Max then
               raise Constraint_Error with "manifest line too long";
            end if;
            --  Split on tabs: F(K) is the position after field K
            F (1) := Line'First - 1;
            N := 1;
            for I in Line'Range loop
               if Line (I) = ASCII.HT then
                  N := N + 1;
                  F (N) := I;
               end if;
            end loop;
            N := N + 1;
            F (N) := Line'Last + 1;
            if N /= 6 then
               raise Constraint_Error with "manifest line needs 5 fields";
            end if;
            Run_Case
              (Mode         => Line (F (1) + 1 .. F (2) - 1),
               In_Path      => Line (F (2) + 1 .. F (3) - 1),
               Exp_Path     => Line (F (3) + 1 .. F (4) - 1),
               Out_Cap      => Natural'Value (Line (F (4) + 1 .. F (5) - 1)),
               Exp_Consumed => Integer'Value (Line (F (5) + 1 .. F (6) - 1)));
         end if;
      end;
   end loop;
   Close (Manifest);

   Put_Line ("cases:" & Cases'Image & "  failures:" & Failures'Image);
   if Failures > 0 then
      Set_Exit_Status (1);
   end if;
end Test_Inflate;
