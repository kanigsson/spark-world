package body Git_View_Refs with SPARK_Mode => On is

   use type Tui.Text.Byte;

   ---------------------
   -- Decoration_Span --
   ---------------------

   procedure Decoration_Span
     (Line       : Tui.Text.Buffer;
      Sha_Length : Natural;
      Found      : out Boolean;
      From       : out Tui.Text.Byte_Count;
      To         : out Tui.Text.Byte_Count)
   is
      --  "%h %ad" occupies SHA + one space + ten date bytes. Git's
      --  decoration prefix contributes a further space before '['.
      Open_Offset : constant Natural := Sha_Length + 12;
      Pos         : Tui.Text.Byte_Count;
   begin
      Found := False;
      From  := 0;
      To    := 0;
      if Open_Offset >= Line'Length
        or else Line (Line'First + Open_Offset) /= Character'Pos ('[')
      then
         return;
      end if;

      Pos := Open_Offset + 1;
      while Pos < Line'Length loop
         pragma Loop_Invariant
           (not Found and then From = 0 and then To = 0);
         pragma Loop_Invariant (Pos > Open_Offset);
         pragma Loop_Variant (Decreases => Line'Length - Pos);
         if Line (Line'First + Pos) = Character'Pos (']') then
            Found := True;
            From  := Open_Offset;
            To    := Pos;
            return;
         end if;
         Pos := Pos + 1;
      end loop;
   end Decoration_Span;

end Git_View_Refs;
