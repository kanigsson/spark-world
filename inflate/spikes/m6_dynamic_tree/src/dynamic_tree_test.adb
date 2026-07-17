with Ada.Text_IO;    use Ada.Text_IO;
with Inflate.Dynamic; use Inflate.Dynamic;

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

   Put_Line ("all dynamic-tree runtime checks passed");
end Dynamic_Tree_Test;
