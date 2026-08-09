--  OSC 52 clipboard edge. Selection ordering and bounds are established by
--  proved app logic; allocation and terminal emission stay in the body at the
--  same trusted edge as the terminal driver.

with Tui.Text;
with Git_View_Selection;

package Git_View_Clipboard with SPARK_Mode => On is

   Max_Copy_Bytes : constant := 65_536;

   procedure Copy
     (Content   : Tui.Text.Buffer;
      Idx       : Tui.Text.Index;
      A, B      : Git_View_Selection.Position;
      Truncated : out Boolean)
   with Global => null,
        Pre    => A.Line <= Tui.Text.Line_Count (Idx)
                  and then B.Line <= Tui.Text.Line_Count (Idx)
                  and then Content'First = 1
                  and then Content'Last >= Tui.Text.Scanned_Bytes (Idx);

end Git_View_Clipboard;
