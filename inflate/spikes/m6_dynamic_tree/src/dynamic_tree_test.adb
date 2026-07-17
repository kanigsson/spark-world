with Ada.Text_IO;      use Ada.Text_IO;
with Inflate;          use Inflate;
with Inflate.Codebooks;
with Inflate.Dynamic;  use Inflate.Dynamic;
with Inflate.Fixed;
with Inflate.Raw;

procedure Dynamic_Tree_Test is

   procedure Check
     (Name        : String;
      Frequencies : Frequency_Array;
      Expected    : Symbol_Count)
   is
      Lengths  : Code_Length_Array (Frequencies'Range);
      Assigned : Natural := 0;
      Space    : Natural := 0;
   begin
      Build_Lengths (Frequencies, Lengths);
      for I in Lengths'Range loop
         if Frequencies (I) > 0 then
            pragma Assert (Lengths (I) > 0);
         end if;
         pragma Assert (Lengths (I) <= 9);
         if Lengths (I) > 0 then
            Assigned := Assigned + 1;
            Space := Space + Pow2 (15 - Lengths (I));
         end if;
      end loop;
      pragma Assert (Assigned = Expected);
      pragma Assert (Space = Pow2 (15));
      Put_Line
        (Name & ":" & Assigned'Image & " leaves, complete code");
   end Check;

   Empty_Code_Lengths : constant Frequency_Array (0 .. 18) := (others => 0);

   One_Literal : Frequency_Array (0 .. 285) := (others => 0);

   Symbol_Zero_Only : Frequency_Array (0 .. 29) := (others => 0);

   Sparse_Literals : Frequency_Array (0 .. 285) := (others => 0);

   All_Literals : constant Frequency_Array (0 .. 285) := (others => 1);

   Distance_Alphabet : Frequency_Array (0 .. 29) := (others => 0);

   Payload_Literals  : Frequency_Array (0 .. 285) := (others => 0);
   Payload_Distances : Frequency_Array (0 .. 29) := (others => 0);
   Literal_Book      : Inflate.Codebooks.Codebook
     (Inflate.Codebooks.Canonical);
   Distance_Book     : Inflate.Codebooks.Codebook
     (Inflate.Codebooks.Canonical);
   Literal_Ready, Distance_Ready : Boolean;
   Payload_Data : constant Byte_Array (1 .. 9) :=
     (Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
      Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'),
      Character'Pos ('a'), Character'Pos ('b'), Character'Pos ('c'));
   Payload_Bits : Byte_Array (1 .. 8) := (others => 0);
   Payload_End  : Natural;

   Body_Output : Byte_Array (1 .. Max_Size (Payload_Data'Length)) :=
     (others => 16#A5#);
   Body_Produced : Natural;
   Decoded       : Byte_Array (Payload_Data'Range) := (others => 0);
   Body_Consumed, Decoded_Length : Natural;
   Body_Status : Status_Type;

   Hex_Digits : constant String := "0123456789abcdef";
begin
   Check ("empty code-length alphabet", Empty_Code_Lengths, 2);

   One_Literal (256) := 1;
   Check ("end-of-block only", One_Literal, 2);

   Symbol_Zero_Only (0) := 1;
   Check ("symbol zero only", Symbol_Zero_Only, 2);

   Sparse_Literals (0) := 20;
   Sparse_Literals (65) := 100;
   Sparse_Literals (256) := 1;
   Check ("sparse literal alphabet", Sparse_Literals, 3);

   Check ("full literal alphabet", All_Literals, 286);

   Distance_Alphabet (0) := 12;
   Distance_Alphabet (3) := 4;
   Distance_Alphabet (29) := 1;
   Check ("distance alphabet", Distance_Alphabet, 3);

   --  The shared plan chooses three literals followed by a length-six,
   --  distance-three match.  The balanced dynamic books assign
   --    a=00, b=01, c=10, EOB=110, length-6=111, distance-3=1,
   --  so the common writer emits 00 01 10 111 1 110 (thirteen bits).
   Payload_Literals (Character'Pos ('a')) := 1;
   Payload_Literals (Character'Pos ('b')) := 1;
   Payload_Literals (Character'Pos ('c')) := 1;
   Payload_Literals (256) := 1;
   Payload_Literals (260) := 1;
   Payload_Distances (2) := 1;
   Build_Codebook (Payload_Literals, Literal_Book, Literal_Ready);
   Build_Codebook (Payload_Distances, Distance_Book, Distance_Ready);
   pragma Assert (Literal_Ready and then Distance_Ready);
   Serialize_Payload
     (Payload_Data, Literal_Book, Distance_Book,
      Payload_Bits, 0, Payload_End);
   pragma Assert (Payload_End = 13);
   pragma Assert (Inflate.Fixed.Prefix_Value (Payload_Bits, 0, 2) = 0);
   pragma Assert (Inflate.Fixed.Prefix_Value (Payload_Bits, 2, 2) = 1);
   pragma Assert (Inflate.Fixed.Prefix_Value (Payload_Bits, 4, 2) = 2);
   pragma Assert (Inflate.Fixed.Prefix_Value (Payload_Bits, 6, 3) = 7);
   pragma Assert (Inflate.Fixed.Prefix_Value (Payload_Bits, 9, 1) = 1);
   pragma Assert (Inflate.Fixed.Prefix_Value (Payload_Bits, 10, 3) = 6);
   Put_Line ("shared dynamic payload serialization passed");

   pragma Assert (Books_Encodable (Literal_Book, Distance_Book));
   Serialize_Body
     (Payload_Data, Literal_Book, Distance_Book,
      Body_Output, Body_Produced);
   pragma Assert (Body_Produced <= Body_Output'Length);
   pragma Assert
     (Header_Encodes (Body_Output, Literal_Book, Distance_Book));

   Inflate.Raw.Decompress
     (Body_Output, Decoded, Body_Consumed, Decoded_Length, Body_Status);
   pragma Assert (Body_Status = OK);
   pragma Assert (Body_Consumed = Body_Produced);
   pragma Assert (Decoded_Length = Payload_Data'Length);
   pragma Assert (Decoded = Payload_Data);
   Put_Line ("dynamic header/body round trip passed");

   Put ("dynamic body hex: ");
   for I in 0 .. Body_Produced - 1 loop
      declare
         Value : constant Natural :=
           Natural (Body_Output (Body_Output'First + I));
      begin
         Put (Hex_Digits (Value / 16 + 1));
         Put (Hex_Digits (Value mod 16 + 1));
      end;
   end loop;
   New_Line;

   Put_Line ("all dynamic-tree runtime checks passed");
end Dynamic_Tree_Test;
