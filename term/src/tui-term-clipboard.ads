--  Tui.Term.Clipboard — putting text on the user's clipboard over OSC 52.
--
--  This is the emission half of the clipboard; the encoding half is pure and
--  lives in Tui.Panes.Clip. Splitting them keeps a terminal write out of
--  proved code and lets the encoder be tested without a terminal.
--
--  A caveat worth knowing rather than discovering: terminals cap how long an
--  OSC 52 sequence they will accept, and some multiplexers cap it far below
--  the payload bound. Over that cap the terminal drops the sequence silently.
--  Tui.Panes.Clip.Extract reports its own truncation, but nothing here can
--  detect the terminal's.

with Tui.Panes.Clip;

package Tui.Term.Clipboard with SPARK_Mode => On is

   --  OSC 52's selection targets: the clipboard proper, or the X11 primary
   --  selection that middle-click pastes.
   type Destination is (Clipboard, Primary);

   --  How the sequence ends. BEL is accepted almost everywhere; some
   --  terminals want the string terminator instead.
   type Terminator is (Bell, String_Terminator);

   procedure Set
     (Text     : Tui.Panes.Clip.Payload;
      To       : Destination := Clipboard;
      Ends_With : Terminator := Bell)
   with Global => null;

end Tui.Term.Clipboard;
