with Interfaces;

package body Inflate.LZ77 with SPARK_Mode => On is

   use type Interfaces.Unsigned_8;

   --  The quantified assertions below expose each branch's semantic facts to
   --  GNATprove.  Evaluating them after every decoder match would make debug
   --  builds quadratic in produced output, so keep them proof-only.
   pragma Assertion_Policy
     (Assert         => Ignore,
      Loop_Invariant => Ignore,
      Ghost          => Ignore);

   procedure Copy_Match
     (Output   : in out Byte_Array;
      Produced : in out Natural;
      Length   : in     Positive;
      Distance : in     Positive)
   is
      First  : constant Buffer_Index := Output'First;
      P      : constant Natural := Produced;
      Before : constant Byte_Array := Output with Ghost;
   begin
      if Distance = 1 then
         --  The overlap recurrence has period one, hence every destination
         --  byte is the byte immediately preceding the match.
         Output (First + P .. First - 1 + P + Length) :=
           (others => Output (First + P - 1));
         Produced := P + Length;

         pragma Assert
           (for all K in 0 .. P - 1 =>
              Output (First + K) = Before (First + K));
         pragma Assert
           (for all K in 0 .. Length - 1 =>
              Output (First + P + K) = Before (First + P - 1));
         pragma Assert
           (Model.Copies_Match (Before, Output, P, Length, Distance));

      elsif Distance >= Length then
         --  The source ends no later than the destination starts, so Ada's
         --  slice assignment is the direct non-overlapping window copy.
         Output (First + P .. First - 1 + P + Length) :=
           Output (First + P - Distance ..
                   First - 1 + P + Length - Distance);
         Produced := P + Length;

         pragma Assert
           (for all K in 0 .. P - 1 =>
              Output (First + K) = Before (First + K));
         pragma Assert
           (for all K in 0 .. Length - 1 =>
              Output (First + P + K) =
                Before (First + P - Distance + K));
         pragma Assert
           (Model.Copies_Match (Before, Output, P, Length, Distance));

      else
         --  Forward copying is essential here: once K reaches Distance,
         --  the source is an earlier byte produced by this same match.
         for K in 0 .. Length - 1 loop
            pragma Loop_Invariant
              (for all J in 0 .. P - 1 =>
                 Output (First + J) = Before (First + J));
            pragma Loop_Invariant
              (for all J in 0 .. K - 1 =>
                 Output (First + P + J) =
                   (if J < Distance
                    then Before (First + P - Distance + J)
                    else Output (First + P + J - Distance)));

            Output (First + P + K) :=
              Output (First + P + K - Distance);

            if K < Distance then
               pragma Assert (P + K - Distance < P);
               pragma Assert
                 (Output (First + P + K - Distance) =
                    Before (First + P + K - Distance));
            else
               pragma Assert (P + K - Distance >= P);
               pragma Assert (K - Distance < K);
            end if;

            pragma Assert
              (for all J in 0 .. P - 1 =>
                 Output (First + J) = Before (First + J));
            pragma Assert
              (for all J in 0 .. K - 1 =>
                 Output (First + P + J) =
                   (if J < Distance
                    then Before (First + P - Distance + J)
                    else Output (First + P + J - Distance)));
         end loop;

         Produced := P + Length;
         pragma Assert
           (Model.Copies_Match (Before, Output, P, Length, Distance));
      end if;
   end Copy_Match;

end Inflate.LZ77;
