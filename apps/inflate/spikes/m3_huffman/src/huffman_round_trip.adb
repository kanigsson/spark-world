package body Huffman_Round_Trip
  with SPARK_Mode => On
is

   procedure Lemma_Count_Monotone
     (Lengths : Full_Length_Array; L : Kraft.Code_Length_Pos; Lo, Hi : Natural)
   with
     Ghost,
     Pre                => Lo <= Hi and then Hi <= Lengths'Last + 1,
     Post               =>
       Count_Length (Lengths, L, Lo) <= Count_Length (Lengths, L, Hi),
     Subprogram_Variant => (Decreases => Hi - Lo);

   procedure Lemma_Count_Monotone
     (Lengths : Full_Length_Array; L : Kraft.Code_Length_Pos; Lo, Hi : Natural)
   is
   begin
      if Lo < Hi then
         Lemma_Count_Monotone (Lengths, L, Lo, Hi - 1);
      end if;
   end Lemma_Count_Monotone;

   procedure Lemma_Count_Step
     (Lengths : Full_Length_Array;
      L       : Kraft.Code_Length_Pos;
      Pos, Hi : Natural)
   with
     Ghost,
     Pre                =>
       Pos < Hi and then Hi <= Lengths'Last + 1 and then Lengths (Pos) = L,
     Post               =>
       Count_Length (Lengths, L, Hi) > Count_Length (Lengths, L, Pos),
     Subprogram_Variant => (Decreases => Hi - Pos);

   procedure Lemma_Count_Step
     (Lengths : Full_Length_Array;
      L       : Kraft.Code_Length_Pos;
      Pos, Hi : Natural) is
   begin
      if Hi > Pos + 1 then
         Lemma_Count_Step (Lengths, L, Pos, Hi - 1);
      end if;
   end Lemma_Count_Step;

   function Rank_Of
     (Book : Codebook; Symbol : Kraft.Symbol_Value) return Kraft.Symbol_Count
   is
   begin
      Lemma_Count_Step
        (Book.Lengths, Book.Lengths (Symbol), Symbol, Book.Lengths'Last + 1);
      return Count_Length (Book.Lengths, Book.Lengths (Symbol), Symbol);
   end Rank_Of;

   procedure Lemma_Pow2_Step (N : Kraft.Code_Length_Pos)
   with Ghost, Pre => N > 1, Post => Kraft.Pow2 (N) = 2 * Kraft.Pow2 (N - 1);

   procedure Lemma_Pow2_Step (N : Kraft.Code_Length_Pos) is
   begin
      case N is
         when 1  =>
            null;

         when 2  =>
            null;

         when 3  =>
            null;

         when 4  =>
            null;

         when 5  =>
            null;

         when 6  =>
            null;

         when 7  =>
            null;

         when 8  =>
            null;

         when 9  =>
            null;

         when 10 =>
            null;

         when 11 =>
            null;

         when 12 =>
            null;

         when 13 =>
            null;

         when 14 =>
            null;

         when 15 =>
            null;
      end case;
   end Lemma_Pow2_Step;

   procedure Lemma_Double_Div (P : Natural; B : Kraft.Bit; Q : Positive)
   with
     Ghost,
     Pre  => P <= Kraft.Pow2 (15) and then Q <= Kraft.Pow2 (15),
     Post => (2 * P + B) / (2 * Q) = P / Q;

   procedure Lemma_Double_Div (P : Natural; B : Kraft.Bit; Q : Positive)
   is null;

   procedure Lemma_Div_Monotone (A, B : Natural; D : Positive)
   with Ghost, Pre => A >= B, Post => A / D >= B / D;

   procedure Lemma_Div_Monotone (A, B : Natural; D : Positive) is null;

   procedure Lemma_Div_Substitute (A, A2 : Natural; D, D2 : Positive)
   with Ghost, Pre => A = A2 and then D = D2, Post => A / D = A2 / D2;

   procedure Lemma_Div_Substitute (A, A2 : Natural; D, D2 : Positive) is null;

   procedure Lemma_Scaled_Div (A, B : Natural; D, Q : Positive)
   with
     Ghost,
     Pre  =>
       A <= Kraft.Pow2 (15)
       and then B <= Kraft.Pow2 (15)
       and then D <= Kraft.Pow2 (15)
       and then Q <= Kraft.Pow2 (15)
       and then A >= 2 * B
       and then D = 2 * Q,
     Post => A / D >= B / Q;

   procedure Lemma_Scaled_Div (A, B : Natural; D, Q : Positive) is null;

   procedure Lemma_Count_Model
     (Lengths : Full_Length_Array; L : Kraft.Code_Length_Pos; Hi : Natural)
   with
     Ghost,
     Pre                => Hi <= Lengths'Last + 1,
     Post               =>
       Count_Length (Lengths, L, Hi) = Kraft.Count_Len (Lengths, L, Hi),
     Subprogram_Variant => (Decreases => Hi);

   procedure Lemma_Count_Model
     (Lengths : Full_Length_Array; L : Kraft.Code_Length_Pos; Hi : Natural) is
   begin
      if Hi > 0 then
         Lemma_Count_Model (Lengths, L, Hi - 1);
      end if;
   end Lemma_Count_Model;

   procedure Lemma_Kraft_Model
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length)
   with
     Ghost,
     Post               =>
       Kraft_Value (Counts, L) = Kraft.Kraft_Sum (Counts, L),
     Subprogram_Variant => (Decreases => L);

   procedure Lemma_Kraft_Model
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length) is
   begin
      if L > 0 then
         Lemma_Kraft_Model (Counts, L - 1);
      end if;
   end Lemma_Kraft_Model;

   procedure Lemma_First_Is_Kraft
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length_Pos)
   with
     Ghost,
     Pre                => L >= 1,
     Post               =>
       First_Code (Counts, L) = 2 * Kraft_Value (Counts, L - 1),
     Subprogram_Variant => (Decreases => L);

   procedure Lemma_First_Is_Kraft
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length_Pos) is
   begin
      if L > 1 then
         Lemma_First_Is_Kraft (Counts, L - 1);
      end if;
   end Lemma_First_Is_Kraft;

   procedure Lemma_Kraft_Prefix
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length)
   with
     Ghost,
     Pre                => Kraft_Value (Counts, 15) <= Kraft.Pow2 (15),
     Post               => Kraft_Value (Counts, L) <= Kraft.Pow2 (L),
     Subprogram_Variant => (Decreases => 15 - L);

   procedure Lemma_Kraft_Prefix
     (Counts : Kraft.Length_Count_Array; L : Kraft.Code_Length) is
   begin
      if L < 15 then
         Lemma_Kraft_Prefix (Counts, L + 1);
         pragma
           Assert
             (Kraft_Value (Counts, L + 1)
                = 2 * Kraft_Value (Counts, L) + Counts (L + 1));
         pragma Assert (Kraft.Pow2 (L + 1) = 2 * Kraft.Pow2 (L));
      end if;
   end Lemma_Kraft_Prefix;

   procedure Lemma_Canonical_Valid (Book : Codebook)
   with Ghost, Pre => Complete (Book), Post => Canonical_Valid (Book);

   procedure Lemma_Canonical_Valid (Book : Codebook) is
   begin
      for L in Kraft.Code_Length_Pos loop
         Lemma_First_Is_Kraft (Book.Counts, L);
         Lemma_Kraft_Prefix (Book.Counts, L);
         pragma
           Assert
             (Kraft_Value (Book.Counts, L)
                = 2 * Kraft_Value (Book.Counts, L - 1) + Book.Counts (L));
      end loop;
   end Lemma_Canonical_Valid;

   procedure Lemma_First_Separated
     (Counts : Kraft.Length_Count_Array;
      Short  : Kraft.Code_Length_Pos;
      Long   : Kraft.Code_Length_Pos)
   with
     Ghost,
     Pre                =>
       Short < Long
       and then (for all L in Kraft.Code_Length_Pos =>
                   First_Code (Counts, L) + Counts (L) <= Kraft.Pow2 (L)),
     Post               =>
       First_Code (Counts, Long) / Kraft.Pow2 (Long - Short)
       >= First_Code (Counts, Short) + Counts (Short),
     Subprogram_Variant => (Decreases => Long - Short);

   procedure Lemma_First_Separated
     (Counts : Kraft.Length_Count_Array;
      Short  : Kraft.Code_Length_Pos;
      Long   : Kraft.Code_Length_Pos) is
   begin
      if Long > Short + 1 then
         Lemma_First_Separated (Counts, Short, Long - 1);
         Lemma_Pow2_Step (Long - Short);
         pragma
           Assert
             (First_Code (Counts, Long) >= 2 * First_Code (Counts, Long - 1));
         pragma
           Assert
             (Kraft.Pow2 (Long - Short) = 2 * Kraft.Pow2 (Long - Short - 1));
         declare
            P : constant Natural := First_Code (Counts, Long - 1);
            Q : constant Positive := Kraft.Pow2 (Long - Short - 1);
            A : constant Natural := First_Code (Counts, Long);
            D : constant Positive := Kraft.Pow2 (Long - Short);
         begin
            pragma Assert (P <= Kraft.Pow2 (Long - 1));
            pragma Assert (A <= Kraft.Pow2 (Long));
            Lemma_Scaled_Div (A, P, D, Q);
            pragma
              Assert
                (A / D
                   >= First_Code (Counts, Long - 1)
                      / Kraft.Pow2 (Long - Short - 1));
            pragma
              Assert
                (First_Code (Counts, Long - 1) / Kraft.Pow2 (Long - Short - 1)
                   >= First_Code (Counts, Short) + Counts (Short));
         end;
         pragma
           Assert
             (First_Code (Counts, Long) / Kraft.Pow2 (Long - Short)
                >= First_Code (Counts, Short) + Counts (Short));
      else
         pragma Assert (Long = Short + 1);
         pragma
           Assert
             (First_Code (Counts, Long)
                = 2 * (First_Code (Counts, Short) + Counts (Short)));
      end if;
   end Lemma_First_Separated;

   procedure Lemma_Prefix_Shortens
     (Bits  : Bit_Buffer;
      Start : Bit_Index;
      Short : Kraft.Code_Length_Pos;
      Long  : Kraft.Code_Length_Pos)
   with
     Ghost,
     Pre                =>
       Short < Long and then Start + Long <= Max_Message_Bits,
     Post               =>
       Prefix_Value (Bits, Start, Short)
       = Prefix_Value (Bits, Start, Long) / Kraft.Pow2 (Long - Short),
     Subprogram_Variant => (Decreases => Long - Short);

   procedure Lemma_Prefix_Shortens
     (Bits  : Bit_Buffer;
      Start : Bit_Index;
      Short : Kraft.Code_Length_Pos;
      Long  : Kraft.Code_Length_Pos) is
   begin
      if Long > Short + 1 then
         Lemma_Prefix_Shortens (Bits, Start, Short, Long - 1);
         Lemma_Pow2_Step (Long - Short);
         declare
            P : constant Natural := Prefix_Value (Bits, Start, Long - 1);
            B : constant Kraft.Bit := Bits (Start + Long - 1);
            Q : constant Positive := Kraft.Pow2 (Long - Short - 1);
         begin
            pragma Assert (P < Kraft.Pow2 (Long - 1));
            pragma Assert (Prefix_Value (Bits, Start, Long) = 2 * P + B);
            Lemma_Double_Div (P, B, Q);
            Lemma_Div_Substitute (Kraft.Pow2 (Long - Short), 2 * Q, 1, 1);
            Lemma_Div_Substitute
              (Prefix_Value (Bits, Start, Long),
               2 * P + B,
               Kraft.Pow2 (Long - Short),
               2 * Q);
            pragma
              Assert
                (Prefix_Value (Bits, Start, Long) / Kraft.Pow2 (Long - Short)
                   = Prefix_Value (Bits, Start, Long - 1)
                     / Kraft.Pow2 (Long - Short - 1));
         end;
         pragma
           Assert
             (Kraft.Pow2 (Long - Short) = 2 * Kraft.Pow2 (Long - Short - 1));
      else
         pragma Assert (Long = Short + 1);
         pragma
           Assert
             (Prefix_Value (Bits, Start, Long) / 2
                = Prefix_Value (Bits, Start, Short));
      end if;
   end Lemma_Prefix_Shortens;

   procedure Lemma_No_Shorter_Code
     (Book     : Codebook;
      Bits     : Bit_Buffer;
      Start    : Bit_Index;
      Expected : Kraft.Symbol_Value;
      Short    : Kraft.Code_Length_Pos)
   with
     Ghost,
     Pre  =>
       Ready (Book)
       and then Book.Lengths (Expected) /= 0
       and then Short < Book.Lengths (Expected)
       and then Start + Book.Lengths (Expected) <= Max_Message_Bits
       and then Prefix_Value (Bits, Start, Book.Lengths (Expected))
                = Code_Of (Book, Expected),
     Post =>
       Prefix_Value (Bits, Start, Short) < First_Code (Book.Counts, Short)
       or else Prefix_Value (Bits, Start, Short)
               >= First_Code (Book.Counts, Short) + Book.Counts (Short);

   procedure Lemma_No_Shorter_Code
     (Book     : Codebook;
      Bits     : Bit_Buffer;
      Start    : Bit_Index;
      Expected : Kraft.Symbol_Value;
      Short    : Kraft.Code_Length_Pos)
   is
      Long : constant Kraft.Code_Length_Pos := Book.Lengths (Expected);
   begin
      Lemma_Prefix_Shortens (Bits, Start, Short, Long);
      Lemma_First_Separated (Book.Counts, Short, Long);
      pragma
        Assert (Code_Of (Book, Expected) >= First_Code (Book.Counts, Long));
      Lemma_Div_Monotone
        (Code_Of (Book, Expected),
         First_Code (Book.Counts, Long),
         Kraft.Pow2 (Long - Short));
      Lemma_Div_Substitute
        (Prefix_Value (Bits, Start, Long),
         Code_Of (Book, Expected),
         Kraft.Pow2 (Long - Short),
         Kraft.Pow2 (Long - Short));
      pragma
        Assert
          (Prefix_Value (Bits, Start, Short)
             >= First_Code (Book.Counts, Long) / Kraft.Pow2 (Long - Short));
      pragma
        Assert
          (First_Code (Book.Counts, Long) / Kraft.Pow2 (Long - Short)
             >= First_Code (Book.Counts, Short) + Book.Counts (Short));
   end Lemma_No_Shorter_Code;

   procedure Lemma_Shorter_Or_Equal
     (Book     : Codebook;
      Bits     : Bit_Buffer;
      Start    : Bit_Index;
      Expected : Kraft.Symbol_Value;
      L        : Kraft.Code_Length_Pos)
   with
     Ghost,
     Pre  =>
       Ready (Book)
       and then Book.Lengths (Expected) /= 0
       and then L <= Book.Lengths (Expected)
       and then Start + Book.Lengths (Expected) <= Max_Message_Bits
       and then Prefix_Value (Bits, Start, Book.Lengths (Expected))
                = Code_Of (Book, Expected),
     Post =>
       (if L < Book.Lengths (Expected)
        then
          Prefix_Value (Bits, Start, L) < First_Code (Book.Counts, L)
          or else Prefix_Value (Bits, Start, L)
                  >= First_Code (Book.Counts, L) + Book.Counts (L));

   procedure Lemma_Shorter_Or_Equal
     (Book     : Codebook;
      Bits     : Bit_Buffer;
      Start    : Bit_Index;
      Expected : Kraft.Symbol_Value;
      L        : Kraft.Code_Length_Pos) is
   begin
      if L < Book.Lengths (Expected) then
         Lemma_No_Shorter_Code (Book, Bits, Start, Expected, L);
      end if;
   end Lemma_Shorter_Or_Equal;

   procedure Lemma_Rank_Unique (Book : Codebook; A, B : Kraft.Symbol_Value)
   with
     Ghost,
     Pre  =>
       Exact_Counts (Book)
       and then Book.Lengths (A) /= 0
       and then Book.Lengths (B) = Book.Lengths (A)
       and then Rank_Of (Book, A) = Rank_Of (Book, B),
     Post => A = B;

   procedure Lemma_Rank_Unique (Book : Codebook; A, B : Kraft.Symbol_Value) is
   begin
      if A < B then
         Lemma_Count_Step (Book.Lengths, Book.Lengths (A), A, B);
      elsif B < A then
         Lemma_Count_Step (Book.Lengths, Book.Lengths (A), B, A);
      end if;
   end Lemma_Rank_Unique;

   procedure Lemma_Prefix_Frame
     (Before, After : Bit_Buffer;
      Start         : Bit_Index;
      Length        : Kraft.Code_Length)
   with
     Ghost,
     Pre                =>
       Start + Length <= Max_Message_Bits
       and then (for all K in Bit_Index range Start .. Start + Length - 1 =>
                   After (K) = Before (K)),
     Post               =>
       Prefix_Value (After, Start, Length)
       = Prefix_Value (Before, Start, Length),
     Subprogram_Variant => (Decreases => Length);

   procedure Lemma_Prefix_Frame
     (Before, After : Bit_Buffer;
      Start         : Bit_Index;
      Length        : Kraft.Code_Length) is
   begin
      if Length > 0 then
         Lemma_Prefix_Frame (Before, After, Start, Length - 1);
      end if;
   end Lemma_Prefix_Frame;

   procedure Lemma_Prefix_Step
     (Bits : Bit_Buffer; Start : Bit_Index; L : Kraft.Code_Length_Pos)
   with
     Ghost,
     Pre  => Start + L <= Max_Message_Bits,
     Post =>
       Prefix_Value (Bits, Start, L)
       = 2 * Prefix_Value (Bits, Start, L - 1) + Bits (Start + L - 1);

   procedure Lemma_Prefix_Step
     (Bits : Bit_Buffer; Start : Bit_Index; L : Kraft.Code_Length_Pos)
   is null;

   procedure Write_Code
     (Bits   : in out Bit_Buffer;
      Start  : Bit_Index;
      Length : Kraft.Code_Length_Pos;
      Code   : Natural)
   with
     Pre  =>
       Start + Length <= Max_Message_Bits and then Code < Kraft.Pow2 (Length),
     Post =>
       Prefix_Value (Bits, Start, Length) = Code
       and then (for all K in Bit_Index =>
                   (if K < Start or else K >= Start + Length
                    then Bits (K) = Bits'Old (K)));

   procedure Write_Code
     (Bits   : in out Bit_Buffer;
      Start  : Bit_Index;
      Length : Kraft.Code_Length_Pos;
      Code   : Natural) is
   begin
      if Length = 1 then
         Bits (Start) := Code mod 2;
      else
         Write_Code (Bits, Start, Length - 1, Code / 2);
         Bits (Start + Length - 1) := Code mod 2;
         pragma Assert (2 * (Code / 2) + Code mod 2 = Code);
      end if;
   end Write_Code;

   procedure Lemma_Encoded_Length_Strict
     (Book : Codebook; Input : Message_Buffer; Lo, Hi : Message_Count)
   with
     Ghost,
     Pre                =>
       Lo < Hi
       and then (for all I in Message_Index range 0 .. Hi - 1 =>
                   Book.Lengths (Input (I)) /= 0),
     Post               =>
       Encoded_Length (Book, Input, Lo) < Encoded_Length (Book, Input, Hi),
     Subprogram_Variant => (Decreases => Hi - Lo);

   procedure Lemma_Encoded_Length_Strict
     (Book : Codebook; Input : Message_Buffer; Lo, Hi : Message_Count) is
   begin
      if Hi > Lo + 1 then
         Lemma_Encoded_Length_Strict (Book, Input, Lo, Hi - 1);
      end if;
   end Lemma_Encoded_Length_Strict;

   procedure Lemma_Segment_Before
     (Book  : Codebook;
      Input : Message_Buffer;
      Pos   : Message_Index;
      Hi    : Message_Count)
   with
     Ghost,
     Pre  =>
       Pos < Hi
       and then (for all I in Message_Index range 0 .. Hi - 1 =>
                   Book.Lengths (Input (I)) /= 0),
     Post =>
       Encoded_Length (Book, Input, Pos) + Book.Lengths (Input (Pos))
       <= Encoded_Length (Book, Input, Hi);

   procedure Lemma_Segment_Before
     (Book  : Codebook;
      Input : Message_Buffer;
      Pos   : Message_Index;
      Hi    : Message_Count) is
   begin
      pragma
        Assert
          (Encoded_Length (Book, Input, Pos + 1)
             = Encoded_Length (Book, Input, Pos) + Book.Lengths (Input (Pos)));
      if Pos + 1 < Hi then
         Lemma_Encoded_Length_Strict (Book, Input, Pos + 1, Hi);
      end if;
   end Lemma_Segment_Before;

   procedure Find_Rank
     (Book   : in Codebook;
      Length : in Kraft.Code_Length_Pos;
      Rank   : in Kraft.Symbol_Count;
      Symbol : out Kraft.Symbol_Value)
   with
     Pre  => Exact_Counts (Book) and then Rank < Book.Counts (Length),
     Post =>
       Book.Lengths (Symbol) = Length and then Rank_Of (Book, Symbol) = Rank;

   procedure Find_Rank
     (Book   : in Codebook;
      Length : in Kraft.Code_Length_Pos;
      Rank   : in Kraft.Symbol_Count;
      Symbol : out Kraft.Symbol_Value)
   is
      Seen : Kraft.Symbol_Count := 0;
   begin
      Symbol := 0;
      for S in Kraft.Symbol_Value loop
         pragma Loop_Invariant (Seen = Count_Length (Book.Lengths, Length, S));
         pragma Loop_Invariant (Seen <= Rank);
         if Book.Lengths (S) = Length then
            if Seen = Rank then
               Symbol := S;
               pragma Assert (Rank_Of (Book, S) = Rank);
               return;
            end if;
            Seen := Seen + 1;
         end if;
      end loop;
      pragma Assert (Seen = Book.Counts (Length));
      pragma Assert (False);
   end Find_Rank;

   procedure Build
     (Lengths : in Full_Length_Array;
      Book    : out Codebook;
      Success : out Boolean)
   is
      Symbols     : Kraft.Symbol_Map;
      Is_Complete : Boolean;
      Is_Valid    : Boolean;
   begin
      Book.Lengths := Lengths;
      Kraft.Construct (Lengths, Book.Counts, Symbols, Is_Complete, Is_Valid);
      Success := Is_Valid and Is_Complete;
      if Success then
         for L in Kraft.Code_Length_Pos loop
            Lemma_Count_Model (Lengths, L, Lengths'Last + 1);
         end loop;
         Lemma_Kraft_Model (Book.Counts, 15);
         Lemma_Canonical_Valid (Book);
      end if;
   end Build;

   procedure Round_Trip
     (Book           : in Codebook;
      Input          : in Message_Buffer;
      Input_Count    : in Message_Count;
      Bits           : out Bit_Buffer;
      Length         : out Bit_Count;
      Restored       : out Message_Buffer;
      Restored_Count : out Message_Count)
   is
      Cursor : Bit_Count := 0;
   begin
      Bits := (others => 0);
      Restored := (others => 0);

      --  Encode canonical code integers most-significant bit first.
      for I in Message_Index range 0 .. Input_Count - 1 loop
         pragma Loop_Invariant (Cursor = Encoded_Length (Book, Input, I));
         pragma
           Loop_Invariant
             (for all J in Message_Index range 0 .. I - 1 =>
                Prefix_Value
                  (Bits,
                   Encoded_Length (Book, Input, J),
                   Book.Lengths (Input (J)))
                = Code_Of (Book, Input (J)));
         declare
            L      : constant Kraft.Code_Length_Pos :=
              Book.Lengths (Input (I));
            C      : constant Natural := Code_Of (Book, Input (I));
            Before : constant Bit_Buffer := Bits
            with Ghost;
         begin
            Write_Code (Bits, Cursor, L, C);
            for J in Message_Index range 0 .. I - 1 loop
               pragma
                 Loop_Invariant
                   (for all K in Message_Index range 0 .. J - 1 =>
                      Prefix_Value
                        (Bits,
                         Encoded_Length (Book, Input, K),
                         Book.Lengths (Input (K)))
                      = Code_Of (Book, Input (K)));
               Lemma_Segment_Before (Book, Input, J, I);
               pragma
                 Assert
                   (for all K in
                      Bit_Index
                        range Encoded_Length (Book, Input, J)
                              .. Encoded_Length (Book, Input, J)
                                 + Book.Lengths (Input (J))
                                 - 1 =>
                      Bits (K) = Before (K));
               Lemma_Prefix_Frame
                 (Before,
                  Bits,
                  Encoded_Length (Book, Input, J),
                  Book.Lengths (Input (J)));
            end loop;
            pragma
              Assert
                (for all J in Message_Index range 0 .. I - 1 =>
                   Prefix_Value
                     (Bits,
                      Encoded_Length (Book, Input, J),
                      Book.Lengths (Input (J)))
                   = Code_Of (Book, Input (J)));
            Cursor := Cursor + L;
         end;
      end loop;
      Length := Cursor;
      pragma Assert (Is_Encoding (Book, Bits, Length, Input, Input_Count));

      --  Decode from Bits and Length only.  Input is mentioned below only in
      --  ghost assertions which establish where the decoder must be in the
      --  just-created stream; it does not influence executable control flow.
      Cursor := 0;
      Restored_Count := 0;
      while Cursor < Length loop
         pragma
           Loop_Invariant
             (Cursor = Encoded_Length (Book, Input, Restored_Count));
         pragma Loop_Invariant (Restored_Count <= Input_Count);
         pragma
           Loop_Invariant
             (for all J in Message_Index range 0 .. Restored_Count - 1 =>
                Restored (J) = Input (J));
         pragma Loop_Variant (Decreases => Length - Cursor);
         if Restored_Count < Input_Count then
            null;
         else
            pragma Assert (Restored_Count = Input_Count);
            pragma Assert (Cursor = Length);
         end if;
         pragma Assert (Restored_Count < Input_Count);
         declare
            Expected        : constant Kraft.Symbol_Value :=
              Input (Restored_Count)
            with Ghost;
            Expected_Length : constant Kraft.Code_Length_Pos :=
              Book.Lengths (Expected)
            with Ghost;
            Code            : Natural := 0;
            First           : Natural := 0;
            Found           : Boolean := False;
         begin
            pragma
              Assert
                (Prefix_Value (Bits, Cursor, Expected_Length)
                   = Code_Of (Book, Expected));
            Lemma_Segment_Before (Book, Input, Restored_Count, Input_Count);
            pragma Assert (Cursor + Expected_Length <= Length);
            for L in Kraft.Code_Length_Pos loop
               pragma Loop_Invariant (not Found);
               pragma Loop_Invariant (L <= Expected_Length);
               pragma Loop_Invariant (First = First_Code (Book.Counts, L));
               pragma
                 Loop_Invariant (Code = Prefix_Value (Bits, Cursor, L - 1));
               pragma Loop_Invariant (Cursor + Expected_Length <= Length);
               Code := 2 * Code + Bits (Cursor + L - 1);
               Lemma_Prefix_Step (Bits, Cursor, L);
               pragma Assert (Code = Prefix_Value (Bits, Cursor, L));

               Lemma_Shorter_Or_Equal (Book, Bits, Cursor, Expected, L);

               if Code >= First and then Code - First < Book.Counts (L) then
                  declare
                     Rank   : constant Kraft.Symbol_Count := Code - First;
                     Symbol : Kraft.Symbol_Value;
                  begin
                     Find_Rank (Book, L, Rank, Symbol);
                     pragma Assert (L = Expected_Length);
                     pragma Assert (Rank = Rank_Of (Book, Expected));
                     Lemma_Rank_Unique (Book, Symbol, Expected);
                     pragma Assert (Symbol = Expected);
                     Restored (Restored_Count) := Symbol;
                     Restored_Count := Restored_Count + 1;
                     Cursor := Cursor + L;
                     Found := True;
                     exit;
                  end;
               else
                  pragma Assert (L < Expected_Length);
                  First := 2 * (First + Book.Counts (L));
               end if;
            end loop;
            pragma Assert (Found);
         end;
      end loop;
      if Restored_Count < Input_Count then
         Lemma_Encoded_Length_Strict
           (Book, Input, Restored_Count, Input_Count);
      end if;
      pragma Assert (Restored_Count = Input_Count);
   end Round_Trip;

end Huffman_Round_Trip;
