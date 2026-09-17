with Tui.UTF8;
with Tui.Width;
with Tui.Pager;

package body Tui.Panes.Clip with SPARK_Mode => On is

   --  Map a display cell to the byte containing it. End_Point chooses the
   --  exclusive end just after that code point; tabs count as the cells they
   --  expand to but remain tabs in the copied text.
   function Byte_Offset
     (Line      : Tui.Text.Buffer;
      Column    : Natural;
      End_Point : Boolean) return Tui.Text.Byte_Count
   with Global => null,
        Post   => Byte_Offset'Result <= Line'Length
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
               Tui.UTF8.Decode (B0, B1, B2, B3, Hi - Pos + 1, CP, Len);
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

   procedure Append
     (Text      : in out Payload;
      B         : Tui.Text.Byte;
      Truncated : in out Boolean)
   with Global => null
   is
   begin
      if Text.Len < Max_Payload then
         Text.Len := Text.Len + 1;
         Text.Bytes (Text.Len) := B;
      else
         Truncated := True;
      end if;
   end Append;

   procedure Append_Part
     (Text      : in out Payload;
      Line      : Tui.Text.Buffer;
      From, To  : Tui.Text.Byte_Count;
      Truncated : in out Boolean)
   with Global => null,
        Pre    => From <= To and then To <= Line'Length
   is
   begin
      if From < To then
         for K in From .. To - 1 loop
            Append (Text, Line (Line'First + K), Truncated);
         end loop;
      end if;
   end Append_Part;

   -------------
   -- Extract --
   -------------

   procedure Extract
     (Content     : Tui.Text.Buffer;
      Idx         : Tui.Text.Index;
      First, Last : Selection.Position;
      Text        : out Payload;
      Truncated   : out Boolean)
   is
   begin
      Text      := (Bytes => (others => 0), Len => 0);
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
            Append_Part (Text, Line, From, Natural'Max (From, To), Truncated);
            if N < Last.Line then
               Append (Text, Character'Pos (ASCII.LF), Truncated);
            end if;
         end;
      end loop;
   end Extract;

   ------------
   -- Encode --
   ------------

   Alphabet : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

   function Encode (P : Payload; N : Positive) return Quartet is
      I : constant Positive := (N - 1) * 3 + 1;
      A : constant Natural := Natural (P.Bytes (I));
      B : constant Natural :=
        (if I + 1 <= P.Len then Natural (P.Bytes (I + 1)) else 0);
      C : constant Natural :=
        (if I + 2 <= P.Len then Natural (P.Bytes (I + 2)) else 0);
   begin
      return (1 => Alphabet (A / 4 + 1),
              2 => Alphabet ((A mod 4) * 16 + B / 16 + 1),
              3 => (if I + 1 <= P.Len
                    then Alphabet ((B mod 16) * 4 + C / 64 + 1) else '='),
              4 => (if I + 2 <= P.Len
                    then Alphabet (C mod 64 + 1) else '='));
   end Encode;

end Tui.Panes.Clip;
