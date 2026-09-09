package body Repro with SPARK_Mode => On is
   procedure Paint (D : Documents.Document; Count : out Natural) is
   begin
      Count := D.Bytes'Length;
   end Paint;
end Repro;
