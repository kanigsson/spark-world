package body Inflate.CRC32 with SPARK_Mode => On is

   --  The loop invariant tying the implementation to the fold model
   --  recurses as deep as the data yet to be processed, on every
   --  iteration; the content lemma recurses as deep as the data. This
   --  policy keeps both out of assertion-enabled executables; GNATprove
   --  proves Ignore-policy assertions all the same.
   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   use Interfaces;

   type Table_Type is array (Byte) of Word32;

   function Build_Table return Table_Type with Global => null;

   function Build_Table return Table_Type is
      T : Table_Type;
      C : Word32;
   begin
      for I in Byte loop
         C := Word32 (I);
         for K in 1 .. 8 loop
            C := (if (C and 1) /= 0
                  then 16#EDB8_8320# xor Shift_Right (C, 1)
                  else Shift_Right (C, 1));
         end loop;
         T (I) := C;
      end loop;
      return T;
   end Build_Table;

   Table : constant Table_Type := Build_Table;

   --  One byte folded into the running state: the loop body of Update,
   --  named so the model can be stated in terms of it.
   function Step (C : Word32; B : Byte) return Word32 is
     (Table (Byte (C and 16#FF#) xor B) xor Shift_Right (C, 8))
   with Ghost, Global => null;

   ----------
   -- Fold --
   ----------

   function Fold
     (C : Word32; Data : Byte_Array; From : Positive; To : Natural)
      return Word32
   is
     (if From > To then C else Fold (Step (C, Data (From)), Data, From + 1, To));

   ------------
   -- Update --
   ------------

   function Update (CRC : Word32; Data : Byte_Array) return Word32 is
      C : Word32 := CRC xor 16#FFFF_FFFF#;
   begin
      for I in Data'Range loop
         --  The final fold is invariant: what has been absorbed into C
         --  plus the fold of the rest equals the fold of the whole.
         pragma Loop_Invariant
           (Fold (CRC xor 16#FFFF_FFFF#, Data, Data'First, Data'Last) =
              Fold (C, Data, I, Data'Last));
         C := Table (Byte (C and 16#FF#) xor Data (I)) xor Shift_Right (C, 8);
      end loop;
      return C xor 16#FFFF_FFFF#;
   end Update;

   --------------------------
   -- Lemma_Update_Content --
   --------------------------

   --  Equal byte sequences fold identically from any starting state, by
   --  induction on the sequence.
   procedure Lemma_Fold_Content
     (C  : Word32;
      D1 : Byte_Array; F1 : Positive; T1 : Natural;
      D2 : Byte_Array; F2 : Positive; T2 : Natural)
   with
     Ghost,
     Global => null,
     Pre  =>
       T1 <= Buffer_Index'Last and then T2 <= Buffer_Index'Last
       and then F1 <= T1 + 1 and then F2 <= T2 + 1
       and then (if T1 >= F1 then F1 >= D1'First and then T1 <= D1'Last)
       and then (if T2 >= F2 then F2 >= D2'First and then T2 <= D2'Last)
       and then T1 - F1 = T2 - F2
       and then (for all K in 0 .. T1 - F1 => D2 (F2 + K) = D1 (F1 + K)),
     Post => Fold (C, D2, F2, T2) = Fold (C, D1, F1, T1),
     Subprogram_Variant => (Decreases => T1 - F1);

   procedure Lemma_Fold_Content
     (C  : Word32;
      D1 : Byte_Array; F1 : Positive; T1 : Natural;
      D2 : Byte_Array; F2 : Positive; T2 : Natural)
   is
   begin
      if F1 <= T1 then
         pragma Assert
           (for all K in 0 .. T1 - (F1 + 1) =>
              D2 ((F2 + 1) + K) = D1 ((F1 + 1) + K));
         Lemma_Fold_Content
           (Step (C, D1 (F1)), D1, F1 + 1, T1, D2, F2 + 1, T2);
      end if;
   end Lemma_Fold_Content;

   procedure Lemma_Update_Content
     (CRC : Word32; D1 : Byte_Array; D2 : Byte_Array)
   is
   begin
      if D1'Length > 0 then
         Lemma_Fold_Content
           (CRC xor 16#FFFF_FFFF#,
            D1, D1'First, D1'Last,
            D2, D2'First, D2'Last);
      end if;
   end Lemma_Update_Content;

end Inflate.CRC32;
