package body Git_View_Search_Input with SPARK_Mode => On is

   use type Tui.Text.Byte;

   -----------
   -- Clear --
   -----------

   procedure Clear (E : out Editor) is
   begin
      E := (Pat => (others => 0), Len => 0);
   end Clear;

   ------------
   -- Append --
   ------------

   procedure Append (E : in out Editor; Code : Tui.Input.Code_Point) is
      --  UTF-8 byte groups. 0x3F masks the low six bits a continuation byte
      --  carries; 0x80/0xC0/0xE0/0xF0 are the lead-byte tags for 1/2/3/4
      --  bytes.
      Cont : constant := 16#80#;
      Six  : constant := 16#40#;   --  one continuation byte spans 0x40 values
      Seq  : array (1 .. 4) of Tui.Text.Byte := (others => 0);
      N    : Natural;              --  number of bytes the encoding needs
   begin
      if Code <= 16#7F# then
         N := 1;
         Seq (1) := Tui.Text.Byte (Code);
      elsif Code <= 16#7FF# then
         N := 2;
         Seq (1) := Tui.Text.Byte (16#C0# + Code / Six);
         Seq (2) := Tui.Text.Byte (Cont + Code mod Six);
      elsif Code <= 16#FFFF# then
         N := 3;
         Seq (1) := Tui.Text.Byte (16#E0# + Code / 16#1000#);
         Seq (2) := Tui.Text.Byte (Cont + (Code / Six) mod Six);
         Seq (3) := Tui.Text.Byte (Cont + Code mod Six);
      else
         N := 4;
         Seq (1) := Tui.Text.Byte (16#F0# + Code / 16#4_0000#);
         Seq (2) := Tui.Text.Byte (Cont + (Code / 16#1000#) mod Six);
         Seq (3) := Tui.Text.Byte (Cont + (Code / Six) mod Six);
         Seq (4) := Tui.Text.Byte (Cont + Code mod Six);
      end if;

      --  Append only if the whole character fits; otherwise drop it.
      if E.Len + N <= Max_Pattern then
         for I in 1 .. N loop
            E.Pat (E.Len + I) := Seq (I);
         end loop;
         E.Len := E.Len + N;
      end if;
   end Append;

   ---------------
   -- Backspace --
   ---------------

   procedure Backspace (E : in out Editor) is
   begin
      --  Continuation bytes are 10xxxxxx; peel them off, then the lead byte.
      while E.Len > 0 and then (E.Pat (E.Len) and 16#C0#) = 16#80# loop
         pragma Loop_Invariant (E.Len <= E.Len'Loop_Entry);
         pragma Loop_Variant (Decreases => E.Len);
         E.Len := E.Len - 1;
      end loop;
      if E.Len > 0 then
         E.Len := E.Len - 1;
      end if;
   end Backspace;

   -----------
   -- Bytes --
   -----------

   function Bytes (E : Editor) return Tui.Text.Buffer is
      (E.Pat (1 .. E.Len));

end Git_View_Search_Input;
