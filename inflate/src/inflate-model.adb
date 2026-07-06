package body Inflate.Model with SPARK_Mode => On is

   ------------------------
   -- Lemma_Encodes_Step --
   ------------------------

   procedure Lemma_Encodes_Step
     (C : Byte_Array; CF : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; DL : Natural)
   is null;

   --------------------------
   -- Lemma_Encodes_Frame --
   --------------------------

   procedure Lemma_Encodes_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; D2 : Byte_Array; DF : Positive; DL : Natural)
   is
      Len : constant Natural := Block_Length (C1, CF);
   begin
      pragma Assert (Block_Length (C2, CF) = Len);
      if C1 (CF) /= 1 then
         --  Not the final block: the tail relation transfers by induction
         --  on the remaining stream, then this block's own fields transfer
         --  byte for byte.
         Lemma_Encodes_Frame
           (C1, C2, CF + 5 + Len, CL, D1, D2, DF + Len, DL);
      end if;
   end Lemma_Encodes_Frame;

   --------------------------
   -- Lemma_Nonfinal_Frame --
   --------------------------

   procedure Lemma_Nonfinal_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; D2 : Byte_Array; DF : Positive; DL : Natural)
   is
   begin
      if CF <= CL then
         --  A non-empty prefix: the head block's fields transfer byte for
         --  byte, the rest by induction on the remaining prefix.
         declare
            Len : constant Natural := Block_Length (C1, CF);
         begin
            pragma Assert (Block_Length (C2, CF) = Len);
            Lemma_Nonfinal_Frame
              (C1, C2, CF + 5 + Len, CL, D1, D2, DF + Len, DL);
         end;
      end if;
   end Lemma_Nonfinal_Frame;

   ------------------------
   -- Lemma_Stream_Frame --
   ------------------------

   procedure Lemma_Stream_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; Last : Natural)
   is
   begin
      if Last - CF >= 4
        and then C1 (CF) <= 1
        and then Natural (C1 (CF + 3)) + 256 * Natural (C1 (CF + 4)) =
                   16#FFFF# - Block_Length (C1, CF)
        and then Last - (CF + 4) >= Block_Length (C1, CF)
      then
         --  A block starts here in both buffers (same bytes); the rest of
         --  the walk transfers by induction.
         pragma Assert (Block_Length (C2, CF) = Block_Length (C1, CF));
         Lemma_Stream_Frame (C1, C2, CF + 5 + Block_Length (C1, CF), Last);
      end if;
   end Lemma_Stream_Frame;

   -----------------------
   -- Lemma_Stream_Step --
   -----------------------

   procedure Lemma_Stream_Step
     (C : Byte_Array; CF : Positive; Last : Natural)
   is null;

   -------------------------
   -- Lemma_Nonfinal_Snoc --
   -------------------------

   procedure Lemma_Nonfinal_Snoc
     (C : Byte_Array; CF : Positive; M : Positive;
      D : Byte_Array; DF : Positive; N : Positive)
   is
      Len : constant Natural := Block_Length (C, M);
   begin
      if CF = M then
         --  Empty prefix: the result is the single appended block followed
         --  by an empty rest, one unfolding of the definition.
         pragma Assert (DF = N);
         pragma Assert
           (Encodes_Nonfinal
              (C, M + 5 + Len, M + 4 + Len, D, N + Len, N + (Len - 1)));
         pragma Assert
           (Encodes_Nonfinal (C, CF, M + 4 + Len, D, DF, N + (Len - 1)));
      else
         --  Peel the prefix's head block and recurse on the shorter
         --  prefix; the head block conjuncts are unchanged, so the whole
         --  refolds around the recursive result.
         declare
            Head : constant Natural := Block_Length (C, CF);
         begin
            Lemma_Nonfinal_Snoc (C, CF + 5 + Head, M, D, DF + Head, N);
            pragma Assert
              (Encodes_Nonfinal (C, CF, M + 4 + Len, D, DF, N + (Len - 1)));
         end;
      end if;
   end Lemma_Nonfinal_Snoc;

   --------------------------
   -- Lemma_Nonfinal_Close --
   --------------------------

   procedure Lemma_Nonfinal_Close
     (C : Byte_Array; CF : Positive; M : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; N : Positive; DL : Natural)
   is
   begin
      if CF = M then
         pragma Assert (DF = N);
      else
         --  Peel the prefix's head block, recurse, and refold: the head is
         --  non-final, so the full relation at CF is the head conjuncts
         --  plus the relation on the rest, which the recursion provides.
         declare
            Head : constant Natural := Block_Length (C, CF);
         begin
            Lemma_Nonfinal_Close
              (C, CF + 5 + Head, M, CL, D, DF + Head, N, DL);
            Lemma_Encodes_Step (C, CF, CL, D, DF, DL);
         end;
      end if;
   end Lemma_Nonfinal_Close;

   -----------------------
   -- Lemma_Encodes_End --
   -----------------------

   procedure Lemma_Encodes_End
     (C : Byte_Array; CF : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; DL : Natural;
      Last : Natural)
   is
      Len : constant Natural := Block_Length (C, CF);
   begin
      if C (CF) /= 1 then
         Lemma_Encodes_End (C, CF + 5 + Len, CL, D, DF + Len, DL, Last);
      end if;
   end Lemma_Encodes_End;

   ------------------------------
   -- Lemma_Encodes_Functional --
   ------------------------------

   procedure Lemma_Encodes_Functional
     (C  : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; DF1 : Positive; DL1 : Natural;
      D2 : Byte_Array; DF2 : Positive; DL2 : Natural)
   is
      Len : constant Natural := Block_Length (C, CF);
   begin
      if C (CF) = 1 then
         --  Single final block: both decoded ranges are exactly the
         --  payload, equal to the same compressed bytes.
         pragma Assert
           (for all K in 0 .. DL1 - DF1 => D1 (DF1 + K) = C (CF + 5 + K));
      else
         Lemma_Encodes_Functional
           (C, CF + 5 + Len, CL,
            D1, DF1 + Len, DL1,
            D2, DF2 + Len, DL2);
         --  Head payload bytes agree through the compressed stream, tail
         --  bytes by induction; every offset falls in one of the two. The
         --  identity assertion rewrites tail indices into the shifted form
         --  the induction hypothesis quantifies over.
         pragma Assert
           (for all K in 0 .. DL1 - DF1 =>
              (if K < Len then D1 (DF1 + K) = D2 (DF2 + K)));
         pragma Assert
           (for all K in Len .. DL1 - DF1 =>
              D1 (DF1 + K) = D1 ((DF1 + Len) + (K - Len))
              and then D2 (DF2 + K) = D2 ((DF2 + Len) + (K - Len)));
         pragma Assert
           (for all K in 0 .. DL1 - DF1 =>
              (if K >= Len then D1 (DF1 + K) = D2 (DF2 + K)));
      end if;
   end Lemma_Encodes_Functional;

end Inflate.Model;
