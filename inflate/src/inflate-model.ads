--  Inflate.Model — an executable specification of what a DEFLATE stream
--  decodes to, for functional-correctness contracts.
--
--  The model currently covers the stored-block fragment of DEFLATE
--  (RFC 1951 §3.2.4): a stream that is a sequence of byte-aligned stored
--  blocks whose header padding bits are zero. That is exactly the image
--  of the stored-only compressor, and deliberately narrower than what
--  the decoder accepts (the decoder ignores the padding bits; the model
--  pins them to zero).
--
--  The relation is not marked Ghost so it stays executable: the test
--  suite can run the very predicate the contracts use, which makes the
--  model a tested artifact instead of trusted text.
--
--  Cursors are explicit indices rather than slices: CF .. CL is the
--  compressed stream within C, DF .. DL the decoded bytes within D.
--  Explicit bounds keep every verification condition about plain array
--  elements, which the provers handle far better than slice equalities.
--  An empty decoded range is expressed as DF = DL + 1, which also covers
--  buffers whose bounds are meaningless because they are empty.

package Inflate.Model with Pure, SPARK_Mode => On is

   use type Interfaces.Unsigned_8;

   --  The LEN field of the stored-block header starting at C (CF)
   --  (little-endian, so at most 16#FFFF#).
   function Block_Length (C : Byte_Array; CF : Positive) return Natural is
     (Natural (C (CF + 1)) + 256 * Natural (C (CF + 2)))
   with Pre => CF >= C'First and then CF <= C'Last
               and then C'Last - CF >= 2;

   --  C (CF .. CL) is a well-formed sequence of stored blocks decoding to
   --  exactly D (DF .. DL): each block is a header byte holding BFINAL
   --  and BTYPE = 00 (so the byte is 0 or 1, padding zeroed), LEN and its
   --  complement NLEN, then LEN literal bytes; the last block has BFINAL
   --  set and ends the stream exactly at CL, having consumed D exactly.
   --
   --  Recursion is front to back: one block, then the rest. The variant
   --  is the shrinking remainder of the compressed stream.
   function Encodes_Stored
     (C : Byte_Array; CF : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; DL : Natural) return Boolean
   is
     (CL - CF >= 4
      and then C (CF) <= 1
      and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4)) =
                 16#FFFF# - Block_Length (C, CF)
      and then CL - (CF + 4) >= Block_Length (C, CF)
      and then DL - DF + 1 >= Block_Length (C, CF)
      and then (for all K in 0 .. Block_Length (C, CF) - 1 =>
                  C (CF + 5 + K) = D (DF + K))
      and then (if C (CF) = 1
                then CF + 4 + Block_Length (C, CF) = CL
                     and then DF + Block_Length (C, CF) = DL + 1
                else Encodes_Stored
                       (C, CF + 5 + Block_Length (C, CF), CL,
                        D, DF + Block_Length (C, CF), DL)))
   with
     Pre =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF <= DL + 1
       and then (if CL >= CF then CF >= C'First and then CL <= C'Last)
       and then (if DL >= DF then DF >= D'First and then DL <= D'Last),
     Subprogram_Variant => (Decreases => CL - CF);

   --  Whole-buffer form: C is a stored-block stream decoding to D.
   function Is_Stored_Encoding (C : Byte_Array; D : Byte_Array) return Boolean
   is
     (C'Length > 0
      and then Encodes_Stored
                 (C, C'First, C'Last,
                  D,
                  (if D'Length > 0 then D'First else 1),
                  (if D'Length > 0 then D'Last else 0)));

   --  Introduction lemma: the precondition is verbatim the definition of
   --  one block followed by an already-established tail, the postcondition
   --  folds it into the relation. Callers with large proof contexts use
   --  this instead of relying on the provers to instantiate the recursive
   --  definition themselves.
   procedure Lemma_Encodes_Step
     (C : Byte_Array; CF : Positive; CL : Natural;
      D : Byte_Array; DF : Positive; DL : Natural)
   with
     Ghost,
     Global => null,
     Pre  =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then DF <= DL + 1
       and then (if DL >= DF then DF >= D'First and then DL <= D'Last)
       and then CL - CF >= 4
       and then CF >= C'First and then CL <= C'Last
       and then C (CF) <= 1
       and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4)) =
                  16#FFFF# - Block_Length (C, CF)
       and then CL - (CF + 4) >= Block_Length (C, CF)
       and then DL - DF + 1 >= Block_Length (C, CF)
       and then (for all K in 0 .. Block_Length (C, CF) - 1 =>
                   C (CF + 5 + K) = D (DF + K))
       and then (if C (CF) = 1
                 then CF + 4 + Block_Length (C, CF) = CL
                      and then DF + Block_Length (C, CF) = DL + 1
                 else Encodes_Stored
                        (C, CF + 5 + Block_Length (C, CF), CL,
                         D, DF + Block_Length (C, CF), DL)),
     Post => Encodes_Stored (C, CF, CL, D, DF, DL);

   --  The relation only looks at C (CF .. CL) and D (DF .. DL): it is
   --  preserved when both buffers are unchanged on those ranges. Callers
   --  need this to carry the relation over writes elsewhere in a buffer
   --  (earlier blocks, container framing around the stream).
   procedure Lemma_Encodes_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; CL : Natural;
      D1 : Byte_Array; D2 : Byte_Array; DF : Positive; DL : Natural)
   with
     Ghost,
     Global => null,
     Pre  =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF <= DL + 1
       and then (if CL >= CF
                 then CF >= C1'First and then CL <= C1'Last
                      and then CF >= C2'First and then CL <= C2'Last)
       and then (if DL >= DF
                 then DF >= D1'First and then DL <= D1'Last
                      and then DF >= D2'First and then DL <= D2'Last)
       and then (for all I in CF .. CL => C2 (I) = C1 (I))
       and then (for all I in DF .. DL => D2 (I) = D1 (I))
       and then Encodes_Stored (C1, CF, CL, D1, DF, DL),
     Post => Encodes_Stored (C2, CF, CL, D2, DF, DL),
     Subprogram_Variant => (Decreases => CL - CF);

end Inflate.Model;
