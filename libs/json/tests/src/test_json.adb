--  Differential test harness for the SPARK json crate (full Ada; this is
--  the test edge, not part of the proved library).
--
--  Argument: a manifest file with one input path per line. For each input
--  the harness parses the whole document with JSON.Pull, decoding every
--  key/string payload through JSON.Strings and converting every number
--  through JSON.Numbers, and writes a canonical event dump to
--  "<input>.out":
--
--    OBJ / ENDOBJ / ARR / ENDARR
--    KEY <n> <n bytes>        decoded key
--    STR <n> <n bytes>        decoded string
--    INT <value>              integer token within Integer_64
--    FLT <value>              any other number, as Long_Float
--    BIG                      number beyond Long_Float's range
--    BOOL true / BOOL false
--    NULL
--    ACCEPT                   document complete
--    REJECT <status>          first violation found
--
--  The driver (run_tests.py) compares the dump against Python's json
--  module on the same bytes. The harness runs with assertions enabled, so
--  any propagated exception surfaces as a missing/short .out file.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces;

with JSON;         use JSON;
with JSON.Numbers;
with JSON.Pull;
with JSON.Strings;

procedure Test_JSON is

   use type Interfaces.Integer_64;

   type String_Access is access String;

   function Read_File (Path : String) return String_Access is
      use Ada.Streams.Stream_IO;
      F : File_Type;
      L : constant Natural :=
        Natural (Ada.Directories.Size (Path));
      R : constant String_Access := new String (1 .. L);
   begin
      Open (F, In_File, Path);
      String'Read (Stream (F), R.all);
      Close (F);
      return R;
   end Read_File;

   procedure Process (In_Path : String) is
      use Ada.Streams.Stream_IO;

      Doc   : constant String_Access := Read_File (In_Path);
      Out_F : File_Type;
      S     : Stream_Access;

      procedure W (Line : String) is
      begin
         String'Write (S, Line);
         Character'Write (S, ASCII.LF);
      end W;

      --  Decode a key/string payload and emit "<Tag> <n> <bytes>".
      --  Returns False on a decode failure (which the pull parser's
      --  validation should make impossible; the driver flags it).

      function Emit_Str
        (Tag : String; First : Positive; Last : Natural) return Boolean
      is
         Raw : String renames Doc.all (First .. Last);
         Buf : String (1 .. Raw'Length);
         Len : Natural;
         St  : Status_Type;
      begin
         JSON.Strings.Decode (Raw, Buf, Len, St);
         if St /= OK then
            W ("DECODEFAIL " & St'Image);
            return False;
         end if;
         String'Write (S, Tag & Natural'Image (Len) & " ");
         String'Write (S, Buf (1 .. Len));
         Character'Write (S, ASCII.LF);
         return True;
      end Emit_Str;

      procedure Emit_Number (First : Positive; Last : Natural;
                             Is_Int : Boolean)
      is
         Tok : String renames Doc.all (First .. Last);
         I   : Interfaces.Integer_64;
         F   : Long_Float;
         OK  : Boolean;
      begin
         if Is_Int then
            JSON.Numbers.To_Integer (Tok, I, OK);
            if OK then
               W ("INT " & I'Image);
               return;
            end if;
         end if;
         JSON.Numbers.To_Float (Tok, F, OK);
         if OK then
            W ("FLT " & Long_Float'Image (F));
         else
            W ("BIG");
         end if;
      end Emit_Number;

      P  : JSON.Pull.Parser;
      Ev : JSON.Pull.Event;
      St : Status_Type;
   begin
      Create (Out_F, Out_File, In_Path & ".out");
      S := Stream (Out_F);

      loop
         JSON.Pull.Next (Doc.all, P, Ev, St);
         if St /= OK then
            W ("REJECT " & St'Image);
            exit;
         end if;
         case Ev.Kind is
            when JSON.Pull.Object_Start =>
               W ("OBJ");
            when JSON.Pull.Object_End =>
               W ("ENDOBJ");
            when JSON.Pull.Array_Start =>
               W ("ARR");
            when JSON.Pull.Array_End =>
               W ("ENDARR");
            when JSON.Pull.Member_Key =>
               exit when not Emit_Str ("KEY", Ev.First, Ev.Last);
            when JSON.Pull.String_Value =>
               exit when not Emit_Str ("STR", Ev.First, Ev.Last);
            when JSON.Pull.Number_Value =>
               Emit_Number (Ev.First, Ev.Last, Ev.Is_Integer);
            when JSON.Pull.Boolean_Value =>
               W ((if Ev.Bool then "BOOL true" else "BOOL false"));
            when JSON.Pull.Null_Value =>
               W ("NULL");
            when JSON.Pull.Document_End =>
               W ("ACCEPT");
               exit;
         end case;
      end loop;

      Close (Out_F);
   end Process;

   Manifest : Ada.Text_IO.File_Type;
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      Ada.Text_IO.Put_Line ("usage: test_json <manifest>");
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   Ada.Text_IO.Open
     (Manifest, Ada.Text_IO.In_File, Ada.Command_Line.Argument (1));
   while not Ada.Text_IO.End_Of_File (Manifest) loop
      declare
         Line : constant String := Ada.Text_IO.Get_Line (Manifest);
      begin
         if Line'Length > 0 then
            Process (Line);
         end if;
      end;
   end loop;
   Ada.Text_IO.Close (Manifest);
end Test_JSON;
