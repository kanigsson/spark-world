--  Throwaway demo. NOT part of the library. Prints the width classification of
--  a handful of representative code points, so the lookup is observable.

with Ada.Text_IO; use Ada.Text_IO;
with Ore.Images;
with Tui.Width;   use Tui.Width;

procedure Demo_Width is

   procedure Show (CP : Code_Point; Note : String) is
   begin
      Put_Line
        ("U+"
         & Ore.Images.Hex (CP, Ore.Images.Upper_Case)
         & " width="
         & Char_Width (CP)'Image
         & "   "
         & Note);
   end Show;

begin
   Put_Line ("tables well-formed: " & Tables_Well_Formed'Image);
   New_Line;
   Show (Character'Pos ('A'), "Latin A");
   Show (16#00E9#, "e-acute (precomposed)");
   Show (16#0301#, "combining acute (zero-width)");
   Show (16#1B#, "ESC (control)");
   Show (16#4E00#, "CJK 'one' (wide)");
   Show (16#3042#, "hiragana A (wide)");
   Show (16#FF21#, "fullwidth A (wide)");
   Show (16#1F600#, "grinning face emoji (wide)");
   Show (16#200D#, "zero-width joiner");
end Demo_Width;
