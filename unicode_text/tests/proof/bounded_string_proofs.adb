with SPARK.Big_Integers;  use SPARK.Big_Integers;
with Unicode_Text.Bounded;
with Unicode_Text.Models; use Unicode_Text.Models;
with Unicode_Text.UTF_8;  use Unicode_Text.UTF_8;

package body Bounded_String_Proofs
  with SPARK_Mode
is
   use type Scalar_Sequences.Sequence;

   package Exact_Text is new Unicode_Text.Bounded (Capacity => 4);
   package Repeated_Text is new Unicode_Text.Bounded (Capacity => 16);

   procedure Fill_Exact_Capacity is
      Result : Exact_Text.Bounded_String := Exact_Text.Empty;
   begin
      Exact_Text.Append (Result, 16#10_FFFF#);
      pragma Assert (Exact_Text.Byte_Length (Result) = 4);
      pragma Assert
        (Static => Exact_Text.Model (Result) = [16#10_FFFF#]);
   end Fill_Exact_Capacity;

   procedure Repeated_Appends is
      Result : Repeated_Text.Bounded_String := Repeated_Text.Empty;
   begin
      Repeated_Text.Append (Result, 16#007F#);
      pragma Assert
        (Static => Repeated_Text.Model (Result) = [16#007F#]);

      Repeated_Text.Append (Result, 16#0800#);
      pragma Assert
        (Static => Repeated_Text.Model (Result) = [16#007F#, 16#0800#]);

      Repeated_Text.Append (Result, 16#10_FFFF#);
      pragma Assert
        (Static =>
           Repeated_Text.Model (Result)
           = [16#007F#, 16#0800#, 16#10_FFFF#]);
   end Repeated_Appends;

   procedure Slice_And_Search is
      Raw_Source : constant String := "abcabc" with Ghost => Static;
      Needle     : constant String := "bc" with Ghost => Static;
      Missing_Needle : constant String := "z" with Ghost => Static;
      Empty_Needle   : constant String := "" with Ghost => Static;
      Present_Needle : constant String := "cab" with Ghost => Static;
   begin
      Lemma_ASCII_Valid (Raw_Source);
      Lemma_ASCII_Valid (Needle);
      Lemma_ASCII_Valid (Missing_Needle);
      Lemma_ASCII_Valid (Empty_Needle);
      Lemma_ASCII_Valid (Present_Needle);
      declare
         Source : constant Repeated_Text.Bounded_String :=
           Repeated_Text.To_Bounded_String (Raw_Source)
         with Ghost => Static;
         Part   : constant Repeated_Text.Bounded_String :=
           Repeated_Text.Slice (Source, 2, 3)
         with Ghost => Static;
         First  : constant Natural := Repeated_Text.Find (Source, Needle)
         with Ghost => Static;
         Later  : constant Natural :=
           Repeated_Text.Find (Source, Needle, From => 3)
         with Ghost => Static;
         Missing : constant Natural :=
           Repeated_Text.Find (Source, Missing_Needle)
         with Ghost => Static;
         Empty   : constant Natural :=
           Repeated_Text.Find (Source, Empty_Needle, From => 7)
         with Ghost => Static;
      begin
         pragma Assert
           (Static =>
              Is_Slice
                (Source => Repeated_Text.Model (Source),
                 First  => 2,
                 Count  => 3,
                 Result => Repeated_Text.Model (Part)));
         pragma Assert
           (Static =>
              Is_First_Occurrence
                (Repeated_Text.Model (Source),
                 Model (Needle),
                 1,
                 To_Big_Integer (First)));
         pragma Assert
           (Static =>
              Is_First_Occurrence
                (Repeated_Text.Model (Source),
                 Model (Needle),
                 3,
                 To_Big_Integer (Later)));
         pragma Assert
           (Static =>
              Is_First_Occurrence
                (Repeated_Text.Model (Source),
                 Model (Missing_Needle),
                 1,
                 To_Big_Integer (Missing)));
         pragma Assert (Static => Empty = 7);
         pragma Assert
           (Static =>
              Repeated_Text.Contains (Source, Present_Needle)
              = Unicode_Text.Models.Contains
                  (Repeated_Text.Model (Source), Model (Present_Needle)));
      end;
   end Slice_And_Search;

end Bounded_String_Proofs;
