package body Inflate.GZip with SPARK_Mode => On is

   --  The ghost bridges below invoke recursive lemmas whose evaluation
   --  cost grows with the data; this policy keeps them (and the local
   --  assertions) out of assertion-enabled executables. GNATprove proves
   --  Ignore-policy assertions all the same, and the contracts in the
   --  spec remain executable.
   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   use Interfaces;

   function LE32 (B0, B1, B2, B3 : Byte) return Word32 is
     (Word32 (B0)
      or Shift_Left (Word32 (B1), 8)
      or Shift_Left (Word32 (B2), 16)
      or Shift_Left (Word32 (B3), 24));

   --  Header flag bits (RFC 1952 §2.3.1)
   FHCRC    : constant Byte := 16#02#;
   FEXTRA   : constant Byte := 16#04#;
   FNAME    : constant Byte := 16#08#;
   FCOMMENT : constant Byte := 16#10#;

   procedure Decompress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Consumed :    out Natural;
      Produced :    out Natural;
      Status   :    out Status_Type)
   is
      P   : Natural;  --  current offset from Input'First
      FLG : Byte;
      Raw_Consumed, Raw_Produced : Natural;
      Stored_CRC, Stored_Size    : Word32;

      --  Ghost bridge for the decode-half postcondition, inlined for
      --  proof and called right after the DEFLATE body is decoded. On a
      --  member in the compressor's image the header has no optional
      --  fields, so the body was decoded from the slice starting 10 bytes
      --  in; the stream-walk hypothesis transfers to that slice (same
      --  bytes, same indices), the core's postcondition fires, and its
      --  relation transfers back to Input.
      procedure Relate_Member with Ghost;

      procedure Relate_Member is
      begin
         if Stored_Member (Input, Output'Length) then
            pragma Assert (P = 10);
            Model.Lemma_Stream_Frame
              (Input, Input (Input'First + P .. Input'Last),
               Input'First + 10, Input'Last);
            pragma Assert (Status = OK);
            pragma Assert (Raw_Consumed = Input'Length - 18);
            Model.Lemma_Encodes_Frame
              (Input (Input'First + P .. Input'Last), Input,
               Input'First + 10, Input'Last - 8,
               Output, Output,
               (if Output'Length > 0 then Output'First else 1),
               (if Output'Length > 0
                then Output'First + (Raw_Produced - 1)
                else 0));
         end if;
      end Relate_Member;
   begin
      Consumed := 0;
      Produced := 0;

      if Input'Length < 2 then
         Status := Truncated_Input;
         return;
      end if;
      if Input (Input'First) /= 16#1F#
        or else Input (Input'First + 1) /= 16#8B#
      then
         Status := GZip_Bad_Magic;
         return;
      end if;
      if Input'Length < 10 then
         Status := Truncated_Input;
         return;
      end if;
      if Input (Input'First + 2) /= 8 then
         Status := GZip_Bad_Method;
         return;
      end if;
      FLG := Input (Input'First + 3);
      if (FLG and 16#E0#) /= 0 then
         Status := GZip_Reserved_Flags;
         return;
      end if;
      --  MTIME, XFL and OS carry no constraints; skip to the optional fields
      P := 10;

      if (FLG and FEXTRA) /= 0 then
         if Input'Length - P < 2 then
            Status := Truncated_Input;
            return;
         end if;
         declare
            XLen : constant Natural :=
              Natural (Input (Input'First + P))
              + 256 * Natural (Input (Input'First + P + 1));
         begin
            P := P + 2;
            if XLen > Input'Length - P then
               Status := Truncated_Input;
               return;
            end if;
            P := P + XLen;
         end;
      end if;

      --  NAME then COMMENT, when present: zero-terminated byte strings
      for Field in 1 .. 2 loop
         pragma Loop_Invariant (P <= Input'Length);
         pragma Loop_Invariant (if FLG = 0 then P = 10);
         if (FLG and (if Field = 1 then FNAME else FCOMMENT)) /= 0 then
            loop
               pragma Loop_Invariant (P <= Input'Length);
               pragma Loop_Variant (Increases => P);
               if P >= Input'Length then
                  Status := Truncated_Input;
                  return;
               end if;
               P := P + 1;
               exit when Input (Input'First + P - 1) = 0;
            end loop;
         end if;
      end loop;

      if (FLG and FHCRC) /= 0 then
         if Input'Length - P < 2 then
            Status := Truncated_Input;
            return;
         end if;
         declare
            --  The stored value is the low 16 bits of the CRC-32 of the
            --  header bytes up to (not including) this field.
            Header_CRC : constant Word32 :=
              CRC32.Compute (Input (Input'First .. Input'First - 1 + P));
            Stored : constant Natural :=
              Natural (Input (Input'First + P))
              + 256 * Natural (Input (Input'First + P + 1));
         begin
            P := P + 2;
            if Natural (Header_CRC and 16#FFFF#) /= Stored then
               Status := GZip_Header_CRC_Mismatch;
               return;
            end if;
         end;
      end if;

      if Input'Length - P < 1 then
         Status := Truncated_Input;
         return;
      end if;
      Raw.Decompress
        (Input (Input'First + P .. Input'Last), Output,
         Raw_Consumed, Raw_Produced, Status);
      Relate_Member;
      Consumed := P + Raw_Consumed;
      Produced := Raw_Produced;
      if Status /= OK then
         return;
      end if;

      --  Trailer: CRC-32 then length mod 2**32, both little-endian
      if Input'Length - Consumed < 8 then
         Status := Truncated_Input;
         return;
      end if;
      Stored_CRC := LE32
        (Input (Input'First + Consumed),
         Input (Input'First + Consumed + 1),
         Input (Input'First + Consumed + 2),
         Input (Input'First + Consumed + 3));
      Stored_Size := LE32
        (Input (Input'First + Consumed + 4),
         Input (Input'First + Consumed + 5),
         Input (Input'First + Consumed + 6),
         Input (Input'First + Consumed + 7));
      Consumed := Consumed + 8;

      if Stored_CRC /=
        CRC32.Compute (Output (Output'First .. Output'First - 1 + Produced))
      then
         Status := GZip_Checksum_Mismatch;
      elsif Stored_Size /= Word32 (Produced) then
         Status := GZip_Length_Mismatch;
      end if;
   end Decompress;

   procedure Decompress_All
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural;
      Status   :    out Status_Type)
   is
      In_Pos  : Natural := 0;
      Out_Pos : Natural := 0;
      C, Pr   : Natural;

      --  Ghost bridge for the whole-file case: a file that is exactly one
      --  member in the compressor's image is consumed by the first
      --  iteration's Decompress, whose member contract fires on the
      --  identical-content slices and transfers back to the full buffers.
      procedure Relate_First with Ghost;

      procedure Relate_First is
      begin
         if Stored_Member (Input, Output'Length)
           and then In_Pos = 0 and then Out_Pos = 0
         then
            Model.Lemma_Stream_Frame
              (Input, Input (Input'First + In_Pos .. Input'Last),
               Input'First + 10, Input'Last);
            pragma Assert
              (Stored_Member
                 (Input (Input'First + In_Pos .. Input'Last),
                  Output'Length - Out_Pos));
            pragma Assert (C = Input'Length);
            pragma Assert
              (Pr = Model.Stored_Decoded_Length
                      (Input, Input'First + 10, Input'Last));
            Model.Lemma_Encodes_Frame
              (Input (Input'First + In_Pos .. Input'Last), Input,
               Input'First + 10, Input'Last - 8,
               Output (Output'First + Out_Pos .. Output'Last), Output,
               (if Output'Length > 0 then Output'First else 1),
               (if Output'Length > 0
                then Output'First + (Pr - 1)
                else 0));
         end if;
      end Relate_First;
   begin
      Produced := 0;
      if Input'Length = 0 then
         Status := Truncated_Input;
         return;
      end if;
      loop
         pragma Loop_Invariant (In_Pos < Input'Length);
         pragma Loop_Invariant (Out_Pos <= Output'Length);
         pragma Loop_Invariant
           (if Stored_Member (Input, Output'Length)
            then In_Pos = 0 and then Out_Pos = 0);
         pragma Loop_Variant (Increases => In_Pos);
         Decompress
           (Input (Input'First + In_Pos .. Input'Last),
            Output (Output'First + Out_Pos .. Output'Last),
            C, Pr, Status);
         Relate_First;
         In_Pos  := In_Pos + C;
         Out_Pos := Out_Pos + Pr;
         Produced := Out_Pos;
         exit when Status /= OK or else In_Pos >= Input'Length;
      end loop;
   end Decompress_All;

   --------------
   -- Compress --
   --------------

   procedure Compress
     (Input    : in     Byte_Array;
      Output   : in out Byte_Array;
      Produced :    out Natural)
   is
      N         : constant Natural      := Input'Length;
      Body_Size : constant Positive     := Raw.Stored_Size (N);
      CRC       : constant Word32       := CRC32.Compute (Input);
      F         : constant Buffer_Index := Output'First;
      T         : constant Buffer_Index := F + 10 + Body_Size;

      In_First : constant Positive := (if N > 0 then Input'First else 1);
      In_Last  : constant Natural  := (if N > 0 then Input'Last else 0);

      Raw_Produced : Natural;
      pragma Warnings (Off, Raw_Produced,
                       Reason => "the size is known statically: the callee "
                                 & "promises Raw_Produced = Stored_Size");
   begin
      --  Fixed header: deflate, no optional fields, MTIME unknown (0),
      --  no XFL hints, OS unknown.
      Output (F)     := 16#1F#;
      Output (F + 1) := 16#8B#;
      Output (F + 2) := 8;
      Output (F + 3) := 0;
      Output (F + 4) := 0;
      Output (F + 5) := 0;
      Output (F + 6) := 0;
      Output (F + 7) := 0;
      Output (F + 8) := 0;
      Output (F + 9) := 16#FF#;

      --  Trailer: CRC-32 of the data, then its length, little-endian.
      --  Written before the body so that nothing is written after the
      --  region the decode-model relation is stated on.
      Output (T)     := Byte (CRC and 16#FF#);
      Output (T + 1) := Byte (Shift_Right (CRC, 8) and 16#FF#);
      Output (T + 2) := Byte (Shift_Right (CRC, 16) and 16#FF#);
      Output (T + 3) := Byte (Shift_Right (CRC, 24));
      Output (T + 4) := Byte (Word32 (N) and 16#FF#);
      Output (T + 5) := Byte (Shift_Right (Word32 (N), 8) and 16#FF#);
      Output (T + 6) := Byte (Shift_Right (Word32 (N), 16) and 16#FF#);
      Output (T + 7) := Byte (Shift_Right (Word32 (N), 24));

      --  The body goes exactly between header and trailer.
      Raw.Compress_Stored (Input, Output (F + 10 .. T - 1), Raw_Produced);

      --  The callee states the relation on the slice it was given;
      --  restate it on Output itself (same bytes, same indices).
      Model.Lemma_Encodes_Frame
        (Output (F + 10 .. T - 1), Output,
         F + 10, T - 1,
         Input, Input, In_First, In_Last);

      Produced := Body_Size + 18;
   end Compress;

end Inflate.GZip;
