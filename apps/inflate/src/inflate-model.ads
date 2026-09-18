--  Inflate.Model — an executable specification of what a DEFLATE stream
--  decodes to, for functional-correctness contracts.
--
--  The package retains the recursive stored-block relation used by the
--  original compressor proof and also provides an executable full-DEFLATE
--  model.  Its primary path is a separate canonical parser; exact fixed and
--  dynamic semantic relations provide proof-completeness fallbacks for the
--  specialized compressor-image decoders.
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

with Inflate.Fixed;
with Inflate.Dynamic;

package Inflate.Model
  with Pure, SPARK_Mode => On
is

   ---------------------------------------------------------------------
   --  LZ77 match-copy model (M4)
   ---------------------------------------------------------------------

   --  After is Before with Length bytes appended at Produced by an LZ77
   --  back-reference of Distance bytes.  The first Distance bytes come
   --  from the pre-existing prefix; subsequent bytes may read bytes written
   --  earlier by the same match.  The second conjunct is therefore the
   --  literal window equation used by DEFLATE, including overlap:
   --
   --    After [Produced + K] = After [Produced + K - Distance]
   --
   --  where the right side below Produced is taken from Before.
   function Copies_Match
     (Before, After : Byte_Array;
      Produced      : Natural;
      Length        : Natural;
      Distance      : Natural) return Boolean
   is ((for all K in 0 .. Produced - 1 =>
          After (After'First + K) = Before (Before'First + K))
       and then (for all K in 0 .. Length - 1 =>
                   After (After'First + Produced + K)
                   = (if K < Distance
                      then Before (Before'First + Produced - Distance + K)
                      else After (After'First + Produced + K - Distance))))
   with
     Pre =>
       Before'Length = After'Length
       and then Produced <= Before'Length
       and then Length <= Before'Length - Produced
       and then Distance in 1 .. Produced;

   --  The LEN field of the stored-block header starting at C (CF)
   --  (little-endian, so at most 16#FFFF#).
   function Block_Length (C : Byte_Array; CF : Positive) return Natural
   is (Natural (C (CF + 1)) + 256 * Natural (C (CF + 2)))
   with Pre => CF >= C'First and then CF <= C'Last and then C'Last - CF >= 2;

   --  C (CF .. CL) is a well-formed sequence of stored blocks decoding to
   --  exactly D (DF .. DL): each block is a header byte holding BFINAL
   --  and BTYPE = 00 (so the byte is 0 or 1, padding zeroed), LEN and its
   --  complement NLEN, then LEN literal bytes; the last block has BFINAL
   --  set and ends the stream exactly at CL, having consumed D exactly.
   --
   --  Recursion is front to back: one block, then the rest. The variant
   --  is the shrinking remainder of the compressed stream.
   function Encodes_Stored
     (C  : Byte_Array;
      CF : Positive;
      CL : Natural;
      D  : Byte_Array;
      DF : Positive;
      DL : Natural) return Boolean
   is (CL - CF >= 4
       and then C (CF) <= 1
       and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4))
                = 16#FFFF# - Block_Length (C, CF)
       and then CL - (CF + 4) >= Block_Length (C, CF)
       and then DL - DF + 1 >= Block_Length (C, CF)
       and then (for all K in 0 .. Block_Length (C, CF) - 1 =>
                   C (CF + 5 + K) = D (DF + K))
       and then (if C (CF) = 1
                 then
                   CF + 4 + Block_Length (C, CF) = CL
                   and then DF + Block_Length (C, CF) = DL + 1
                 else
                   Encodes_Stored
                     (C,
                      CF + 5 + Block_Length (C, CF),
                      CL,
                      D,
                      DF + Block_Length (C, CF),
                      DL)))
   with
     Pre                =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF <= DL + 1
       and then (if CL >= CF then CF >= C'First and then CL <= C'Last)
       and then (if DL >= DF then DF >= D'First and then DL <= D'Last),
     Subprogram_Variant => (Decreases => CL - CF);

   --  Whole-buffer form: C is a stored-block stream decoding to D.
   function Is_Stored_Encoding (C : Byte_Array; D : Byte_Array) return Boolean
   is (C'Length > 0
       and then Encodes_Stored
                  (C,
                   C'First,
                   C'Last,
                   D,
                   (if D'Length > 0 then D'First else 1),
                   (if D'Length > 0 then D'Last else 0)));

   ---------------------------------------------------------------------
   --  Full DEFLATE decode model (M5)
   ---------------------------------------------------------------------

   --  Input (Input'First .. Input'First + Consumed - 1) is a complete
   --  DEFLATE stream whose decoded bytes are exactly the first Produced
   --  bytes of Output.  Unlike Encodes_Stored, this executable relation
   --  covers stored, fixed-Huffman, and dynamic-Huffman blocks, including
   --  literal and overlapping LZ77 match output.
   --
   --  The primary implementation is an intentionally separate canonical
   --  decoder: it reads Huffman codes one bit at a time directly from code
   --  lengths and validates the caller-supplied output instead of constructing
   --  the shipping decoder's tables or using its fast lookup map.  Exact
   --  fixed and dynamic relations serve as specialized proof fallbacks.
   function Is_Decoding
     (Input    : Byte_Array;
      Output   : Byte_Array;
      Consumed : Natural;
      Produced : Natural) return Boolean
   with
     Global => null,
     Pre    => Consumed <= Input'Length and then Produced <= Output'Length,
     Post   =>
       (if Input'Length >= 5
          and then Stored_Stream_End (Input, Input'First, Input'Last) > 0
          and then Consumed > 0
          and then Input'First + (Consumed - 1)
                   = Stored_Stream_End (Input, Input'First, Input'Last)
          and then Stored_Decoded_Length (Input, Input'First, Input'Last)
                   = Produced
          and then (if Produced = 0
                    then
                      Encodes_Stored
                        (Input,
                         Input'First,
                         Input'First + (Consumed - 1),
                         Output,
                         (if Output'Length > 0 then Output'First else 1),
                         (if Output'Length > 0 then Output'First - 1 else 0))
                    else
                      Encodes_Stored
                        (Input,
                         Input'First,
                         Input'First + (Consumed - 1),
                         Output,
                         Output'First,
                         Output'First + (Produced - 1)))
        then Is_Decoding'Result)
       and then (if Input'Length <= Fixed.Max_Stream_Bytes
                   and then Fixed.Analyze (Input).Valid
                   and then Fixed.Analyze (Input).Decoded_Length
                            <= Output'Length
                   and then Consumed = (Fixed.Analyze (Input).End_Bit + 7) / 8
                   and then Produced = Fixed.Analyze (Input).Decoded_Length
                   and then Fixed.Is_Encoding
                              (Input,
                               Consumed,
                               Output
                                 (Output'First .. Output'First - 1 + Produced))
                 then Is_Decoding'Result)
       and then (if Input'Length <= Fixed.Max_Stream_Bytes
                   and then Dynamic.Decodes
                              (Input,
                               Consumed,
                               Output
                                 (Output'First .. Output'First - 1 + Produced))
                 then Is_Decoding'Result);

   --  Where the well-formed stored-block stream starting at CF ends within
   --  C (CF .. Last): the index of its final byte, or 0 when no such
   --  stream starts there. Unlike Encodes_Stored this constrains only the
   --  compressed bytes, so it can serve as the input-side hypothesis of
   --  the decoder's contract; the stream may end before Last (a container
   --  places its trailer after it).
   function Stored_Stream_End
     (C : Byte_Array; CF : Positive; Last : Natural) return Natural
   is (if Last - CF >= 4
         and then C (CF) <= 1
         and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4))
                  = 16#FFFF# - Block_Length (C, CF)
         and then Last - (CF + 4) >= Block_Length (C, CF)
       then
         (if C (CF) = 1
          then CF + 4 + Block_Length (C, CF)
          else Stored_Stream_End (C, CF + 5 + Block_Length (C, CF), Last))
       else 0)
   with
     Pre                =>
       Last <= Buffer_Index'Last
       and then CF <= Last + 1
       and then (if Last >= CF then CF >= C'First and then Last <= C'Last),
     Post               =>
       Stored_Stream_End'Result = 0
       or else Stored_Stream_End'Result in CF + 4 .. Last,
     Subprogram_Variant => (Decreases => Last - CF);

   --  Bytes the stream starting at CF decodes to (the sum of its LEN
   --  fields), 0 when no well-formed stream starts there. Only meaningful
   --  where Stored_Stream_End is positive. Every block yields at most as
   --  many bytes as it occupies past its header, whence the bound.
   function Stored_Decoded_Length
     (C : Byte_Array; CF : Positive; Last : Natural) return Natural
   is (if Last - CF >= 4
         and then C (CF) <= 1
         and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4))
                  = 16#FFFF# - Block_Length (C, CF)
         and then Last - (CF + 4) >= Block_Length (C, CF)
       then
         (if C (CF) = 1
          then Block_Length (C, CF)
          else
            Block_Length (C, CF)
            + Stored_Decoded_Length (C, CF + 5 + Block_Length (C, CF), Last))
       else 0)
   with
     Pre                =>
       Last <= Buffer_Index'Last
       and then CF <= Last + 1
       and then (if Last >= CF then CF >= C'First and then Last <= C'Last),
     Post               =>
       Stored_Decoded_Length'Result
       <= (if Last - CF >= 4 then Last - (CF + 4) else 0),
     Subprogram_Variant => (Decreases => Last - CF);

   --  C (CF .. CL) is a (possibly empty) sequence of *non-final* stored
   --  blocks decoding to exactly D (DF .. DL). This is the prefix shape a
   --  forward-walking decoder maintains: the blocks consumed so far are
   --  all non-final, and appending the still-unread rest of the stream
   --  (Lemma_Nonfinal_Close) recovers Encodes_Stored on the whole.
   function Encodes_Nonfinal
     (C  : Byte_Array;
      CF : Positive;
      CL : Natural;
      D  : Byte_Array;
      DF : Positive;
      DL : Natural) return Boolean
   is (if CF > CL
       then DF = DL + 1
       else
         CL - CF >= 4
         and then C (CF) = 0
         and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4))
                  = 16#FFFF# - Block_Length (C, CF)
         and then CL - (CF + 4) >= Block_Length (C, CF)
         and then DL - DF + 1 >= Block_Length (C, CF)
         and then (for all K in 0 .. Block_Length (C, CF) - 1 =>
                     C (CF + 5 + K) = D (DF + K))
         and then Encodes_Nonfinal
                    (C,
                     CF + 5 + Block_Length (C, CF),
                     CL,
                     D,
                     DF + Block_Length (C, CF),
                     DL))
   with
     Pre                =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF <= DL + 1
       and then (if CL >= CF then CF >= C'First and then CL <= C'Last)
       and then (if DL >= DF then DF >= D'First and then DL <= D'Last),
     Subprogram_Variant => (Decreases => CL - CF);

   --  Introduction lemma: the precondition is verbatim the definition of
   --  one block followed by an already-established tail, the postcondition
   --  folds it into the relation. Callers with large proof contexts use
   --  this instead of relying on the provers to instantiate the recursive
   --  definition themselves.
   procedure Lemma_Encodes_Step
     (C  : Byte_Array;
      CF : Positive;
      CL : Natural;
      D  : Byte_Array;
      DF : Positive;
      DL : Natural)
   with
     Ghost,
     Global => null,
     Pre    =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then DF <= DL + 1
       and then (if DL >= DF then DF >= D'First and then DL <= D'Last)
       and then CL - CF >= 4
       and then CF >= C'First
       and then CL <= C'Last
       and then C (CF) <= 1
       and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4))
                = 16#FFFF# - Block_Length (C, CF)
       and then CL - (CF + 4) >= Block_Length (C, CF)
       and then DL - DF + 1 >= Block_Length (C, CF)
       and then (for all K in 0 .. Block_Length (C, CF) - 1 =>
                   C (CF + 5 + K) = D (DF + K))
       and then (if C (CF) = 1
                 then
                   CF + 4 + Block_Length (C, CF) = CL
                   and then DF + Block_Length (C, CF) = DL + 1
                 else
                   Encodes_Stored
                     (C,
                      CF + 5 + Block_Length (C, CF),
                      CL,
                      D,
                      DF + Block_Length (C, CF),
                      DL)),
     Post   => Encodes_Stored (C, CF, CL, D, DF, DL);

   --  The relation only looks at C (CF .. CL) and D (DF .. DL): it is
   --  preserved when both buffers are unchanged on those ranges. Callers
   --  need this to carry the relation over writes elsewhere in a buffer
   --  (earlier blocks, container framing around the stream).
   procedure Lemma_Encodes_Frame
     (C1 : Byte_Array;
      C2 : Byte_Array;
      CF : Positive;
      CL : Natural;
      D1 : Byte_Array;
      D2 : Byte_Array;
      DF : Positive;
      DL : Natural)
   with
     Ghost,
     Global             => null,
     Pre                =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF <= DL + 1
       and then (if CL >= CF
                 then
                   CF >= C1'First
                   and then CL <= C1'Last
                   and then CF >= C2'First
                   and then CL <= C2'Last)
       and then (if DL >= DF
                 then
                   DF >= D1'First
                   and then DL <= D1'Last
                   and then DF >= D2'First
                   and then DL <= D2'Last)
       and then (for all I in CF .. CL => C2 (I) = C1 (I))
       and then (for all I in DF .. DL => D2 (I) = D1 (I))
       and then Encodes_Stored (C1, CF, CL, D1, DF, DL),
     Post               => Encodes_Stored (C2, CF, CL, D2, DF, DL),
     Subprogram_Variant => (Decreases => CL - CF);

   --  The prefix relation reads the same ranges only; same frame property.
   --  The decoded-side equality is phrased over offsets because that is
   --  the shape a decoder's per-block postcondition provides.
   procedure Lemma_Nonfinal_Frame
     (C1 : Byte_Array;
      C2 : Byte_Array;
      CF : Positive;
      CL : Natural;
      D1 : Byte_Array;
      D2 : Byte_Array;
      DF : Positive;
      DL : Natural)
   with
     Ghost,
     Global             => null,
     Pre                =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF <= DL + 1
       and then (if CL >= CF
                 then
                   CF >= C1'First
                   and then CL <= C1'Last
                   and then CF >= C2'First
                   and then CL <= C2'Last)
       and then (if DL >= DF
                 then
                   DF >= D1'First
                   and then DL <= D1'Last
                   and then DF >= D2'First
                   and then DL <= D2'Last)
       and then (for all I in CF .. CL => C2 (I) = C1 (I))
       and then (for all K in 0 .. DL - DF => D2 (DF + K) = D1 (DF + K))
       and then Encodes_Nonfinal (C1, CF, CL, D1, DF, DL),
     Post               => Encodes_Nonfinal (C2, CF, CL, D2, DF, DL),
     Subprogram_Variant => (Decreases => CL - CF);

   --  The stream-walk functions read C (CF .. Last) only: equal bytes
   --  there give equal results. Lets a caller restate the input-side
   --  hypothesis across a slice of the same buffer.
   procedure Lemma_Stream_Frame
     (C1 : Byte_Array; C2 : Byte_Array; CF : Positive; Last : Natural)
   with
     Ghost,
     Global             => null,
     Pre                =>
       Last <= Buffer_Index'Last
       and then CF <= Last + 1
       and then (if Last >= CF
                 then
                   CF >= C1'First
                   and then Last <= C1'Last
                   and then CF >= C2'First
                   and then Last <= C2'Last)
       and then (for all I in CF .. Last => C2 (I) = C1 (I)),
     Post               =>
       Stored_Stream_End (C2, CF, Last) = Stored_Stream_End (C1, CF, Last)
       and then Stored_Decoded_Length (C2, CF, Last)
                = Stored_Decoded_Length (C1, CF, Last),
     Subprogram_Variant => (Decreases => Last - CF);

   --  Destructor: where a well-formed stream starts, its first block is
   --  well formed, and the walk functions unfold across that block. A
   --  decoder consuming the stream front to back applies this once per
   --  block; stating the unfolding as a lemma keeps it available inside
   --  large proof contexts.
   procedure Lemma_Stream_Step (C : Byte_Array; CF : Positive; Last : Natural)
   with
     Ghost,
     Global => null,
     Pre    =>
       Last <= Buffer_Index'Last
       and then CF <= Last + 1
       and then (if Last >= CF then CF >= C'First and then Last <= C'Last)
       and then Stored_Stream_End (C, CF, Last) > 0,
     Post   =>
       Last - CF >= 4
       and then C (CF) <= 1
       and then Natural (C (CF + 3)) + 256 * Natural (C (CF + 4))
                = 16#FFFF# - Block_Length (C, CF)
       and then Last - (CF + 4) >= Block_Length (C, CF)
       and then Stored_Decoded_Length (C, CF, Last) >= Block_Length (C, CF)
       and then (if C (CF) = 1
                 then
                   Stored_Stream_End (C, CF, Last)
                   = CF + 4 + Block_Length (C, CF)
                   and then Stored_Decoded_Length (C, CF, Last)
                            = Block_Length (C, CF)
                 else
                   Stored_Stream_End (C, CF + 5 + Block_Length (C, CF), Last)
                   = Stored_Stream_End (C, CF, Last)
                   and then Stored_Stream_End
                              (C, CF + 5 + Block_Length (C, CF), Last)
                            > 0
                   and then Stored_Decoded_Length (C, CF, Last)
                            = Block_Length (C, CF)
                              + Stored_Decoded_Length
                                  (C, CF + 5 + Block_Length (C, CF), Last));

   --  Appending one more non-final block to a non-final prefix keeps it a
   --  non-final prefix. The decoder's per-block induction step; recursion
   --  is on the prefix already accumulated.
   procedure Lemma_Nonfinal_Snoc
     (C  : Byte_Array;
      CF : Positive;
      M  : Positive;
      D  : Byte_Array;
      DF : Positive;
      N  : Positive)
   with
     Ghost,
     Global             => null,
     Pre                =>
       M >= C'First
       and then M <= C'Last
       and then C'Last - M >= 4
       and then Block_Length (C, M) <= C'Last - (M + 4)
       and then CF in C'First .. M
       and then DF <= N
       --  D-side bounds are needed only where decoded bytes exist: the
       --  guard is "the extended range N + Block_Length - 1 reaches DF",
       --  spelled without overflow-prone arithmetic on unbounded N.
       and then (if Block_Length (C, M) > 0 or else DF <= N - 1
                 then
                   DF >= D'First
                   and then N - 1 <= D'Last
                   and then Block_Length (C, M) <= D'Last - (N - 1))
       and then C (M) = 0
       and then Natural (C (M + 3)) + 256 * Natural (C (M + 4))
                = 16#FFFF# - Block_Length (C, M)
       and then (for all K in 0 .. Block_Length (C, M) - 1 =>
                   C (M + 5 + K) = D (N + K))
       and then Encodes_Nonfinal (C, CF, M - 1, D, DF, N - 1),
     Post               =>
       Encodes_Nonfinal
         (C,
          CF,
          M + 4 + Block_Length (C, M),
          D,
          DF,
          N + (Block_Length (C, M) - 1)),
     Subprogram_Variant => (Decreases => M - CF);

   --  A non-final prefix followed by a complete stream is a complete
   --  stream: closes the decoder's induction when the final block lands.
   procedure Lemma_Nonfinal_Close
     (C  : Byte_Array;
      CF : Positive;
      M  : Positive;
      CL : Natural;
      D  : Byte_Array;
      DF : Positive;
      N  : Positive;
      DL : Natural)
   with
     Ghost,
     Global             => null,
     Pre                =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then CF <= M
       and then M <= CL + 1
       and then DF <= N
       and then N <= DL + 1
       and then (if CL >= CF then CF >= C'First and then CL <= C'Last)
       and then (if DL >= DF then DF >= D'First and then DL <= D'Last)
       and then Encodes_Nonfinal (C, CF, M - 1, D, DF, N - 1)
       and then Encodes_Stored (C, M, CL, D, N, DL),
     Post               => Encodes_Stored (C, CF, CL, D, DF, DL),
     Subprogram_Variant => (Decreases => M - CF);

   --  A complete stream determines where the walk ends and how much it
   --  decodes to: connects the relational contract of the compressor to
   --  the input-side hypothesis of the decoder.
   procedure Lemma_Encodes_End
     (C    : Byte_Array;
      CF   : Positive;
      CL   : Natural;
      D    : Byte_Array;
      DF   : Positive;
      DL   : Natural;
      Last : Natural)
   with
     Ghost,
     Global             => null,
     Pre                =>
       CL <= Buffer_Index'Last
       and then DL <= Buffer_Index'Last
       and then Last <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF <= DL + 1
       and then (if CL >= CF then CF >= C'First and then CL <= C'Last)
       and then (if DL >= DF then DF >= D'First and then DL <= D'Last)
       and then CL <= Last
       and then (if Last >= CF then Last <= C'Last)
       and then Encodes_Stored (C, CF, CL, D, DF, DL),
     Post               =>
       Stored_Stream_End (C, CF, Last) = CL
       and then Stored_Decoded_Length (C, CF, Last) = DL - DF + 1,
     Subprogram_Variant => (Decreases => CL - CF);

   --  The relation is functional in the decoded bytes: one compressed
   --  stream decodes to one byte sequence. Together with the decoder's
   --  contract this yields round-trip equality.
   procedure Lemma_Encodes_Functional
     (C   : Byte_Array;
      CF  : Positive;
      CL  : Natural;
      D1  : Byte_Array;
      DF1 : Positive;
      DL1 : Natural;
      D2  : Byte_Array;
      DF2 : Positive;
      DL2 : Natural)
   with
     Ghost,
     Global             => null,
     Pre                =>
       CL <= Buffer_Index'Last
       and then DL1 <= Buffer_Index'Last
       and then DL2 <= Buffer_Index'Last
       and then CF <= CL + 1
       and then DF1 <= DL1 + 1
       and then DF2 <= DL2 + 1
       and then (if CL >= CF then CF >= C'First and then CL <= C'Last)
       and then (if DL1 >= DF1 then DF1 >= D1'First and then DL1 <= D1'Last)
       and then (if DL2 >= DF2 then DF2 >= D2'First and then DL2 <= D2'Last)
       and then Encodes_Stored (C, CF, CL, D1, DF1, DL1)
       and then Encodes_Stored (C, CF, CL, D2, DF2, DL2),
     Post               =>
       DL1 - DF1 = DL2 - DF2
       and then (for all K in 0 .. DL1 - DF1 => D1 (DF1 + K) = D2 (DF2 + K)),
     Subprogram_Variant => (Decreases => CL - CF);

end Inflate.Model;
