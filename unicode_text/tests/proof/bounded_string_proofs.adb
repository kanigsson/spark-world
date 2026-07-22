with Unicode_Text.Bounded;
with Unicode_Text.Models; use Unicode_Text.Models;

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

end Bounded_String_Proofs;
