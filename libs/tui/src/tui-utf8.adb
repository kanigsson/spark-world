package body Tui.UTF8
  with SPARK_Mode => On
is

   ------------
   -- Decode --
   ------------

   procedure Decode
     (B0, B1, B2, B3 : Tui.Byte;
      Avail          : Positive;
      CP             : out Tui.Code_Point;
      Len            : out Positive)
   is
      --  The length classifier already settles well-formedness; the branches
      --  below only extract the scalar value, reusing the very arithmetic the
      --  classifier checked, so the prover sees each result inside its range.
      L : constant Natural := Sequence_Length (B0, B1, B2, B3, Avail);
   begin
      if L = 0 then
         CP := Replacement;
         Len := 1;
      else
         Len := L;
         case L is
            when 1      =>
               CP := Natural (B0);

            when 2      =>
               CP := Scalar_2 (B0, B1);

            when 3      =>
               CP := Scalar_3 (B0, B1, B2);

            when others =>
               CP := Scalar_4 (B0, B1, B2, B3);  --  L = 4
         end case;
      end if;
   end Decode;

end Tui.UTF8;
