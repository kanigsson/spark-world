with Tui;
with Tui.UTF8;
with Tui.Width;
with Tui.Pager;
with Tui.Term.Output;

package body Git_View_Clipboard with SPARK_Mode => On is

   package Sel renames Git_View_Selection;

   subtype Copy_Length is Natural range 0 .. Max_Copy_Bytes;
   type Copy_Buffer is
     array (Positive range 1 .. Max_Copy_Bytes) of Tui.Text.Byte;

   --  Map a display cell to the byte containing it. End_Point chooses the
   --  exclusive end just after that code point; tabs count as their expanded
   --  cells but remain tabs in the copied text.
   function Byte_Offset
     (Line      : Tui.Text.Buffer;
      Column    : Natural;
      End_Point : Boolean) return Tui.Text.Byte_Count
   with Global => null,
        Post   => Byte_Offset'Result <= Line'Length;

   function Byte_Offset
     (Line      : Tui.Text.Buffer;
      Column    : Natural;
      End_Point : Boolean) return Tui.Text.Byte_Count
   is
   begin
      if Line'Length = 0 then
         return 0;
      end if;
      declare
         Pos : Natural := Line'First;
         Col : Tui.Pager.Dimension := 0;
         Hi  : constant Natural := Line'Last;
      begin
         while Pos <= Hi loop
            pragma Loop_Invariant (Pos >= Line'First);
            pragma Loop_Variant (Decreases => Hi - Pos);
            declare
            B0 : constant Tui.Byte := Tui.Byte (Line (Pos));
            B1 : constant Tui.Byte :=
              (if Pos + 1 <= Hi then Tui.Byte (Line (Pos + 1)) else 0);
            B2 : constant Tui.Byte :=
              (if Pos + 2 <= Hi then Tui.Byte (Line (Pos + 2)) else 0);
            B3 : constant Tui.Byte :=
              (if Pos + 3 <= Hi then Tui.Byte (Line (Pos + 3)) else 0);
            CP  : Tui.Code_Point;
            Len : Positive;
            W   : Natural;
         begin
            Tui.UTF8.Decode
              (B0, B1, B2, B3, Hi - Pos + 1, CP, Len);
            W := (if CP = 16#09# then 8 - Natural (Col mod 8)
                  else Natural (Tui.Width.Char_Width (CP)));
            if Column < Col
              or else Column - Col < Natural'Max (1, W)
            then
               return Pos - Line'First + (if End_Point then Len else 0);
            end if;
            Col := Natural'Min (Tui.Pager.Max_Dim, Col + W);
            Pos := Pos + Len;
            end;
         end loop;
      end;
      return Line'Length;
   end Byte_Offset;

   procedure Append_Byte
     (Out_Text  : in out Copy_Buffer;
      Length    : in out Copy_Length;
      B         : Tui.Text.Byte;
      Truncated : in out Boolean)
   with Global => null
   is
   begin
      if Length < Max_Copy_Bytes then
         Length := Length + 1;
         Out_Text (Length) := B;
      else
         Truncated := True;
      end if;
   end Append_Byte;

   procedure Append_Line_Part
     (Out_Text  : in out Copy_Buffer;
      Length    : in out Copy_Length;
      Line      : Tui.Text.Buffer;
      From, To  : Tui.Text.Byte_Count;
      Truncated : in out Boolean)
   with Global => null,
        Pre    => From <= To and then To <= Line'Length
   is
   begin
      if From < To then
         for K in From .. To - 1 loop
            Append_Byte
              (Out_Text, Length, Line (Line'First + K), Truncated);
         end loop;
      end if;
   end Append_Line_Part;

   Alphabet : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

   procedure Put_Base64
     (Raw        : Copy_Buffer;
      Raw_Length : Copy_Length)
   with Global => null
   is
      I : Natural := 1;
   begin
      while I <= Raw_Length loop
         pragma Loop_Invariant (I in 1 .. Max_Copy_Bytes + 1);
         pragma Loop_Variant (Decreases => Raw_Length - I);
         declare
            A : constant Natural := Natural (Raw (I));
            B : constant Natural :=
              (if I + 1 <= Raw_Length then Natural (Raw (I + 1)) else 0);
            C : constant Natural :=
              (if I + 2 <= Raw_Length then Natural (Raw (I + 2)) else 0);
            Quartet : constant String :=
              (1 => Alphabet (A / 4 + 1),
               2 => Alphabet ((A mod 4) * 16 + B / 16 + 1),
               3 => (if I + 1 <= Raw_Length
                     then Alphabet ((B mod 16) * 4 + C / 64 + 1) else '='),
               4 => (if I + 2 <= Raw_Length
                     then Alphabet (C mod 64 + 1) else '='));
         begin
            Tui.Term.Output.Put (Quartet);
            I := Natural'Min (Max_Copy_Bytes + 1, I + 3);
         end;
      end loop;
   end Put_Base64;

   procedure Copy
     (Content   : Tui.Text.Buffer;
      Idx       : Tui.Text.Index;
      A, B      : Sel.Position;
      Truncated : out Boolean)
   is
      First, Last : Sel.Position;
      Raw         : Copy_Buffer := (others => 0);
      Raw_Len     : Copy_Length := 0;
      ESC         : constant Character := Character'Val (16#1B#);
      BEL         : constant Character := Character'Val (16#07#);
   begin
      Sel.Ordered (A, B, First, Last);
      Truncated := False;

      for N in First.Line .. Last.Line loop
         declare
            Line : constant Tui.Text.Buffer := Tui.Text.Line (Idx, Content, N);
            From : constant Tui.Text.Byte_Count :=
              (if N = First.Line then Byte_Offset (Line, First.Col, False)
               else 0);
            To   : constant Tui.Text.Byte_Count :=
              (if N = Last.Line then Byte_Offset (Line, Last.Col, True)
               else Line'Length);
         begin
            Append_Line_Part
              (Raw, Raw_Len, Line, From, Natural'Max (From, To), Truncated);
            if N < Last.Line then
               Append_Byte
                 (Raw, Raw_Len, Character'Pos (ASCII.LF), Truncated);
            end if;
         end;
      end loop;

      if Raw_Len > 0 then
         Tui.Term.Output.Put (ESC & "]52;c;");
         Put_Base64 (Raw, Raw_Len);
         Tui.Term.Output.Put ((1 => BEL));
      end if;
   end Copy;

end Git_View_Clipboard;
