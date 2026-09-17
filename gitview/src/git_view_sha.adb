package body Git_View_Sha with SPARK_Mode => On is

   use type Tui.Text.Byte;

   Space   : constant Tui.Text.Byte := Character'Pos (' ');
   Digit_0 : constant Tui.Text.Byte := Character'Pos ('0');
   Digit_9 : constant Tui.Text.Byte := Character'Pos ('9');
   Hex_A   : constant Tui.Text.Byte := Character'Pos ('a');
   Hex_F   : constant Tui.Text.Byte := Character'Pos ('f');

   --  Git prints object names in lowercase hexadecimal.
   function Is_Hex (B : Tui.Text.Byte) return Boolean is
     (B in Digit_0 .. Digit_9 or else B in Hex_A .. Hex_F);

   -------------
   -- Extract --
   -------------

   procedure Extract
     (Content : Tui.Text.Buffer;
      Idx     : Tui.Text.Index;
      N       : Tui.Text.Line_Number;
      Result  : out Sha)
   is
      Sp    : constant Tui.Text.Span := Tui.Text.Line_Span (Idx, N);
      Count : Sha_Length := 0;
   begin
      Result := (Text => (others => ' '), Len => 0);

      for I in 1 .. Sp.Length loop
         declare
            B : constant Tui.Text.Byte := Content (Sp.Start + (I - 1));
         begin
            exit when B = Space;   --  end of the leading token
            if Count = Max_Sha or else not Is_Hex (B) then
               return;             --  too long or not hex: no commit id here
            end if;
            Count := Count + 1;
            Result.Text (Count) := Character'Val (Natural (B));
         end;
         pragma Loop_Invariant (Count <= Max_Sha and then Result.Len = 0);
      end loop;

      Result.Len := Count;
   end Extract;

end Git_View_Sha;
