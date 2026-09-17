with SPARK.Big_Integers;  use SPARK.Big_Integers;
with Unicode_Text.Models; use Unicode_Text.Models;
with Unicode_Text.UTF_8;  use Unicode_Text.UTF_8;

package body Search_Scaling
  with SPARK_Mode
is
   procedure Repeated_Searches is
      Source        : constant String := "abababababababab"
      with Ghost => Static;
      Needle        : constant String := "ab" with Ghost => Static;
      Present       : constant String := "baba" with Ghost => Static;
      Absent        : constant String := "abba" with Ghost => Static;
   begin
      Lemma_ASCII_Valid (Source);
      Lemma_ASCII_Valid (Needle);
      Lemma_ASCII_Valid (Present);
      Lemma_ASCII_Valid (Absent);
      declare
         R1 : constant Natural := Find (Source, Needle, From => 1)
         with Ghost => Static;
         R2 : constant Natural := Find (Source, Needle, From => 3)
         with Ghost => Static;
         R3 : constant Natural := Find (Source, Needle, From => 5)
         with Ghost => Static;
         R4 : constant Natural := Find (Source, Needle, From => 7)
         with Ghost => Static;
         R5 : constant Natural := Find (Source, Needle, From => 9)
         with Ghost => Static;
         R6 : constant Natural := Find (Source, Needle, From => 11)
         with Ghost => Static;
         R7 : constant Natural := Find (Source, Needle, From => 13)
         with Ghost => Static;
         R8 : constant Natural := Find (Source, Needle, From => 15)
         with Ghost => Static;
      begin
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 1, To_Big_Integer (R1)));
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 3, To_Big_Integer (R2)));
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 5, To_Big_Integer (R3)));
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 7, To_Big_Integer (R4)));
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 9, To_Big_Integer (R5)));
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 11, To_Big_Integer (R6)));
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 13, To_Big_Integer (R7)));
         pragma Assert
           (Static => Is_First_Occurrence
              (Model (Source), Model (Needle), 15, To_Big_Integer (R8)));
         pragma Assert
           (Static =>
              Contains (Source, Present)
              = Unicode_Text.Models.Contains
                  (Model (Source), Model (Present)));
         pragma Assert
           (Static =>
              Contains (Source, Absent)
              = Unicode_Text.Models.Contains
                  (Model (Source), Model (Absent)));
      end;
   end Repeated_Searches;
end Search_Scaling;
