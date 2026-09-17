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

      --  Ghost bridge for the decode-half postcondition.  Member fixes the
      --  body at offset ten, so the raw decoder's common-body contract can
      --  be carried without another stored/fixed case split.
      procedure Relate_Member with Ghost;

      procedure Relate_Member is
      begin
         if Member (Input, Output'Length) then
            pragma Assert (P = 10);
            pragma Assert (Status = OK);
            pragma Assert (Raw_Consumed = Input'Length - 18);
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
              Natural (Load_16 (Input, Input'First + P, Little_Endian));
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
              Natural (Load_16 (Input, Input'First + P, Little_Endian));
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
      Stored_CRC  :=
        Load_32 (Input, Input'First + Consumed, Little_Endian);
      Stored_Size :=
        Load_32 (Input, Input'First + Consumed + 4, Little_Endian);
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
         if Member (Input, Output'Length)
           and then In_Pos = 0 and then Out_Pos = 0
         then
            pragma Assert
              (Member
                 (Input (Input'First + In_Pos .. Input'Last),
                  Output'Length - Out_Pos));
            pragma Assert (C = Input'Length);
            pragma Assert
              (Pr = Bodies.Decoded_Size
                      (Input (Input'First + 10 .. Input'Last)));
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
           (if Member (Input, Output'Length)
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
      N           : constant Natural      := Input'Length;
      Try_Dynamic : constant Boolean      :=
        Dynamic.Selects_Byte_Run (Input);
      Use_Fixed : Boolean :=
        not Try_Dynamic and then N <= Fixed.Max_Input;
      Body_Bound  : constant Positive     :=
        (if Try_Dynamic then Dynamic.Max_Size (N)
         elsif Use_Fixed then Fixed.Max_Size (N)
         else Raw.Stored_Size (N));
      CRC         : constant Word32       := CRC32.Compute (Input);
      F           : constant Buffer_Index := Output'First;

      Raw_Produced   : Natural;
      Dynamic_Success : Boolean := False;
      pragma Warnings (Off, Raw_Produced,
                       Reason => "every selected body encoder initializes it");
   begin
      --  Produce the selected body into its allocation bound. Dynamic bodies
      --  discover their exact size while serializing, so the trailer is framed
      --  around the returned prefix below.
      if Try_Dynamic then
         pragma Assert (N <= Dynamic.Max_Input);
         Dynamic.Compress_Byte_Run
           (Input,
            Output (F + 10 .. F + 9 + Body_Bound), Raw_Produced,
            Dynamic_Success);
         if Dynamic_Success
           and then Raw_Produced < Fixed.Encoded_Size (Input)
         then
            Bodies.Lemma_Dynamic_Encoding
              (Output (F + 10 .. F + 9 + Body_Bound),
               Raw_Produced, Input);
         else
            --  Retain totality if the checked canonical builder rejects, and
            --  retain the exact fixed image unless dynamic coding is smaller.
            Dynamic_Success := False;
            Use_Fixed := True;
            pragma Assert (Fixed.Max_Size (N) <= Dynamic.Max_Size (N));
            Fixed.Compress
              (Input,
               Output (F + 10 .. F + 9 + Body_Bound), Raw_Produced);
            Bodies.Lemma_Fixed_Encoding
              (Output (F + 10 .. F + 9 + Body_Bound),
               Raw_Produced, Input);
         end if;
      elsif Use_Fixed then
         pragma Assert
           (Output (F + 10 .. F + 9 + Body_Bound)'Length <=
              Fixed.Max_Stream_Bytes);
         Fixed.Compress
           (Input,
            Output (F + 10 .. F + 9 + Body_Bound), Raw_Produced);
         Bodies.Lemma_Fixed_Encoding
           (Output (F + 10 .. F + 9 + Body_Bound), Raw_Produced, Input);
      else
         Raw.Compress_Stored
           (Input, Output (F + 10 .. F + 9 + Body_Bound), Raw_Produced);
         Bodies.Lemma_Stored_Encoding
           (Output (F + 10 .. F + 9 + Body_Bound), Raw_Produced, Input);
      end if;

      declare
         Body_Before_Trailer : constant Byte_Array :=
           Output (F + 10 .. F + 9 + Body_Bound) with Ghost;
         T : constant Buffer_Index := F + 10 + Raw_Produced;
      begin
         pragma Assert (Raw_Produced in 1 .. Body_Bound);

         --  Carry the encoding relation onto the snapshot here, while the
         --  proof context is still just the body encoder's. Established
         --  after the trailer writes it is the same fact, but has to be
         --  found among their framing hypotheses.
         pragma Assert
           (Bodies.Body_Encodes (Body_Before_Trailer, Raw_Produced, Input));

         --  Trailer: CRC-32 of the data, then its length, little-endian.
         --  The frame condition of Store_32 is what keeps the body bytes
         --  before T available to the reframing lemmas below.
         Store_32 (Output, T, CRC, Little_Endian);
         Store_32 (Output, T + 4, Word32 (N), Little_Endian);

         --  Fixed header: deflate, no optional fields, MTIME unknown (0),
         --  no XFL hints, OS unknown. Writing it after the disjoint body and
         --  trailer regions keeps these public framing facts local.
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

         --  Trailer writes preserve the body prefix. Reframe the common
         --  relation over the exact member suffix before exposing recognition
         --  and size facts to the theorem layer.
         Bodies.Lemma_Encoding_Frame
           (Body_Before_Trailer,
            Output (F + 10 .. T + 7),
            Raw_Produced, Input);
         Bodies.Lemma_Encoding_Recognized
           (Output (F + 10 .. T + 7), Raw_Produced, Input);

         Produced := Raw_Produced + 18;
         pragma Assert (Output (F) = 16#1F#);
         pragma Assert (Output (F + 1) = 16#8B#);
         pragma Assert (Output (F + 2) = 8);
         pragma Assert (Output (F + 3) = 0);
         pragma Assert
           (if Dynamic_Success
            then Raw_Produced <= Dynamic.Max_Size (N)
            elsif Use_Fixed
            then Raw_Produced = Fixed.Encoded_Size (Input)
            else Raw_Produced = Raw.Stored_Size (N));
         pragma Assert (Produced <= Compressed_Size (N));
      end;
   end Compress;

end Inflate.GZip;
