--  Throwaway dogfooding demo. NOT part of the library and NOT SPARK.
--
--  Its only jobs are (1) to prove the public API is usable from ordinary Ada,
--  and (2) to make the step-one success criterion visible: render a frame,
--  change one cell, and watch the diff report exactly one change. The ANSI
--  escape handling here is deliberately the only terminal-aware code in the
--  whole crate; the real driver layer is a future, separate crate.

with Ada.Text_IO;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Tui.Surface;       use Tui.Surface;
with Tui.Surface.Diff;

procedure Demo_Surface is

   package TIO renames Ada.Text_IO;
   package Enc renames Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

   ESC : constant Character := Character'Val (16#1B#);

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Utf8 (G : Wide_Wide_Character) return String is
     (Enc.Encode ((1 => G)));

   procedure Goto_RC (R : Row_Index; C : Col_Index) is
   begin
      TIO.Put (ESC & "[" & Img (Integer (R)) & ";" & Img (Integer (C)) & "H");
   end Goto_RC;

   procedure Blit_Full (S : Surface) is
   begin
      TIO.Put (ESC & "[2J");   --  clear screen
      for R in Row_Index range 1 .. S.Rows loop
         Goto_RC (R, 1);
         for C in Col_Index range 1 .. S.Cols loop
            TIO.Put (Utf8 (Get (S, R, C).Glyph));
         end loop;
      end loop;
   end Blit_Full;

   procedure Blit_Changes (Changes : Diff.Change_Array; Count : Natural) is
   begin
      for I in 1 .. Count loop
         Goto_RC (Changes (I).Row, Changes (I).Column);
         TIO.Put (Utf8 (Changes (I).Value.Glyph));
      end loop;
   end Blit_Changes;

   procedure Put_String (S : in out Surface; R : Row_Index; C : Col_Index;
                         Text : String)
   is
      Col : Col_Count := C;
   begin
      for Ch of Text loop
         exit when Col > S.Cols;
         Set (S, R, Col,
              (Glyph => Wide_Wide_Character'Val (Character'Pos (Ch)),
               others => <>));
         Col := Col + 1;
      end loop;
   end Put_String;

   Rows : constant Row_Count := 6;
   Cols : constant Col_Count := 30;

   Prev : Surface := Blank (Rows, Cols);
   Cur  : Surface := Blank (Rows, Cols);

begin
   --  First frame.
   Put_String (Cur, 2, 3, "hello, surface");
   Blit_Full (Cur);

   --  Change exactly one cell, then diff against the previous frame.
   Prev := Cur;
   Set (Cur, 2, 3, (Glyph => 'H', others => <>));

   declare
      Buf : Diff.Change_Array (1 .. Diff.Cell_Count (Cur));
      N   : Natural;
   begin
      Diff.Compute (Prev, Cur, Buf, N);
      Blit_Changes (Buf, N);
      Goto_RC (Rows, 1);
      TIO.New_Line;
      TIO.Put_Line ("diff reported" & N'Image & " changed cell(s) (expected 1)");
   end;
end Demo_Surface;
