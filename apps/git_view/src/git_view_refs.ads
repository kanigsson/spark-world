--  Locate the optional bracketed ref decoration in a commit-list line.
--  The SHA and date retain fixed leading positions; malformed lines simply
--  produce Found = False and remain uncoloured.

with Tui.Text;

package Git_View_Refs
  with SPARK_Mode => On
is

   procedure Decoration_Span
     (Line       : Tui.Text.Buffer;
      Sha_Length : Natural;
      Found      : out Boolean;
      From       : out Tui.Text.Byte_Count;
      To         : out Tui.Text.Byte_Count)
   with
     Global => null,
     Pre    => Sha_Length <= 40,
     Post   => (if Found then From <= To and then To < Line'Length);

end Git_View_Refs;
