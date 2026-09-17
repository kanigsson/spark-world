package body Frame_Proofs
  with SPARK_Mode => On
is

   pragma
     Assertion_Policy
       (Assert => Ignore, Loop_Invariant => Ignore, Ghost => Ignore);

   -----------------
   -- Write_Frame --
   -----------------

   procedure Write_Frame (B : in out Buffer; Tag : Byte; Payload : Byte_Array)
   is
      Base  : constant Natural := Length (B);
      Start : constant Buffer := B
      with Ghost => Static;
   begin
      Append (B, Tag);

      declare
         After_Tag : constant Buffer := B
         with Ghost => Static;
      begin
         Append_16 (B, Word16 (Payload'Length), Little_Endian);

         declare
            After_Header : constant Buffer := B
            with Ghost => Static;
         begin
            Append (B, Payload);

            --  The tag and the length field were written before the payload
            --  was; carrying them across that append is what the framing
            --  vocabulary is for. Prefix preservation composes over the three
            --  appends, and the length field then loads the same value out of
            --  the longer buffer because its own two bytes did not move.
            Lemma_Same_Prefix_Trans (Start, After_Tag, After_Header, Base);
            Lemma_Same_Prefix_Trans (Start, After_Header, B, Base);

            pragma
              Assert
                (Static =>
                   Equal_Ranges
                     (Contents (After_Header),
                      Contents (B),
                      Base + 2,
                      Base + 2,
                      2));
            Lemma_Load_16_Frame
              (Contents (After_Header),
               Contents (B),
               Base + 2,
               Base + 2,
               Little_Endian);
         end;
      end;
   end Write_Frame;

   ----------------
   -- Read_Frame --
   ----------------

   procedure Read_Frame
     (B       : in out Buffer;
      Tag     : out Byte;
      Payload : in out Byte_Array;
      Size    : out Natural)
   is
      Base   : constant Natural := Read_Position (B);
      Header : Word16;
   begin
      Read (B, Tag);
      Read_16 (B, Header, Little_Endian);
      Size := Natural (Header);

      if Size <= Natural'Min (Length (B) - Read_Position (B), Payload'Length)
      then
         Read (B, Payload (Payload'First .. Payload'First - 1 + Size));
      end if;

      pragma Assert (Read_Position (B) >= Base + Header_Size);
   end Read_Frame;

   ---------------
   -- Write_Run --
   ---------------

   procedure Write_Run (B : in out Buffer; Value : Byte; Count : Positive) is
      Base : constant Natural := Length (B);
   begin
      Append (B, Value);

      declare
         First_Byte : constant Buffer := B
         with Ghost => Static;
      begin
         if Count > 1 then
            Append_Copy (B, 1, Count - 1);
            Lemma_Copies_Back_Run (First_Byte, B, Count - 1);
         end if;

         pragma Assert (Static => Element (First_Byte, Base + 1) = Value);
      end;
   end Write_Run;

   -----------
   -- Drain --
   -----------

   procedure Drain
     (Source : in out Buffer; Target : in out Buffer; Moved : out Natural)
   is
      Result : Transfer;
   begin
      Moved := 0;

      --  Reclaim the consumed prefix before concluding there is no room: a
      --  full buffer whose bytes have been read is not really full.
      if Available (Target) = 0 then
         Compact (Target);
      end if;

      --  One Move is sufficient: by definition it either exhausts Source or
      --  fills Target, which is exactly the stopping condition.
      if Unread (Source) > 0 and then Available (Target) > 0 then
         Move (Source, Target, Result);
         Moved := Result.Consumed;
      end if;
   end Drain;

end Frame_Proofs;
