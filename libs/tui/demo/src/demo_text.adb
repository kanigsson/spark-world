--  Throwaway demo. NOT part of the library. Builds an in-memory multi-line
--  buffer (no file I/O — that's the driver's job), indexes it, and prints each
--  line with its byte span, so the line model is observable with no OS.

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Characters.Latin_1; use Ada.Characters.Latin_1;
with Tui.Text;               use Tui.Text;

procedure Demo_Text is

   --  Note the CRLF line, the empty line, and the unterminated final line.
   Content : constant Buffer :=
     To_Buffer
       ("first line"
        & LF
        & "second (CRLF)"
        & CR
        & LF
        & LF
        & "no newline at end");

   Idx : Index (1_000);

begin
   Scan (Idx, Content);   --  complete lines
   Seal (Idx, Content);   --  finalise the unterminated tail

   Put_Line
     ("scanned"
      & Scanned_Bytes (Idx)'Image
      & " bytes,"
      & Line_Count (Idx)'Image
      & " lines:");
   for N in 1 .. Line_Count (Idx) loop
      declare
         S : constant Span := Line_Span (Idx, N);
      begin
         Put_Line
           (N'Image
            & ": ["
            & S.Start'Image
            & " +"
            & S.Length'Image
            & " ] '"
            & To_String (Line (Idx, Content, N))
            & "'");
      end;
   end loop;
end Demo_Text;
