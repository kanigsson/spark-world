--  Structural landmarks in git-show output. This scanner is independent of
--  pager search state, so file/hunk jumps never replace the user's pattern.

with Tui.Text;

package Git_View_Navigation
  with SPARK_Mode => On
is

   type Landmark is (File_Header, Hunk_Header);

   function Is_Landmark
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      N       : Tui.Text.Line_Number;
      Kind    : Landmark) return Boolean
   with
     Global => null,
     Pre    =>
       Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Index)
       and then N <= Tui.Text.Line_Count (Index);

   --  Find the first landmark strictly after/before From. On a miss Line is
   --  left at From, making the output valid even when no movement is possible.
   procedure Find
     (Content : Tui.Text.Buffer;
      Index   : Tui.Text.Index;
      From    : Tui.Text.Line_Number;
      Forward : Boolean;
      Kind    : Landmark;
      Found   : out Boolean;
      Line    : out Tui.Text.Line_Number)
   with
     Global => null,
     Pre    =>
       Content'First = 1
       and then Content'Last >= Tui.Text.Scanned_Bytes (Index)
       and then Tui.Text.Line_Count (Index) >= 1
       and then From <= Tui.Text.Line_Count (Index),
     Post   => (if Found then Line <= Tui.Text.Line_Count (Index));

end Git_View_Navigation;
