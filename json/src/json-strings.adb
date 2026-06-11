--  JSON.Strings body. The decode loop maintains one central invariant:
--  the output position never exceeds the input position, because every
--  step writes at most as many bytes as it consumes (plain characters and
--  UTF-8 sequences copy one-for-one; every escape shrinks). That invariant
--  is what lets the output index checks and the Length postcondition
--  discharge. The escape and UTF-8 validation mirrors the pull parser's
--  treatment so that the decoder stands alone on unvalidated input.

package body JSON.Strings with SPARK_Mode => On is

   function Cur (Input : String; Pos : Natural) return Character is
     (Input (Input'First + Pos))
   with Pre => Pos < Input'Length;

   --  Four hex digits of a \u escape, as a code unit

   procedure Hex4
     (Input  : in     String;
      Pos    : in out Natural;
      Code   :    out Natural;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Pos <= Input'Length,
     Post   => Pos in Pos'Old .. Input'Length
               and then Code <= 16#FFFF#
               and then (if Status = OK then Pos = Pos'Old + 4);

   --  One byte of output

   procedure Put
     (Output  : in out String;
      Out_Pos : in out Natural;
      B       : in     Natural)
   with
     Global => null,
     Pre    => B <= 255
               and then Output'Last < Positive'Last
               and then Out_Pos < Output'Length,
     Post   => Out_Pos = Out_Pos'Old + 1;

   --  One code point as UTF-8, at most four bytes

   procedure Encode
     (Output  : in out String;
      Out_Pos : in out Natural;
      U       : in     Natural)
   with
     Global => null,
     Pre    => U <= 16#10FFFF#
               and then Output'Last < Positive'Last
               and then Output'Length - Out_Pos >= 4,
     Post   => Out_Pos = Out_Pos'Old + (if U < 16#80# then 1
                                        elsif U < 16#800# then 2
                                        elsif U < 16#10000# then 3
                                        else 4);

   --  One validated continuation byte, copied through

   procedure Copy_Cont
     (Input   : in     String;
      In_Pos  : in out Natural;
      Output  : in out String;
      Out_Pos : in out Natural;
      Lo, Hi  : in     Natural;
      Status  :    out Status_Type)
   with
     Global => null,
     Pre    => Lo <= Hi and then Hi <= 255
               and then In_Pos <= Input'Length
               and then Output'Last < Positive'Last
               and then Out_Pos <= Output'Length
               and then (In_Pos >= Input'Length
                         or else Out_Pos < Output'Length),
     Post   => In_Pos in In_Pos'Old .. Input'Length
               and then Out_Pos in Out_Pos'Old .. Out_Pos'Old + 1
               and then (if Status = OK
                         then In_Pos = In_Pos'Old + 1
                              and then Out_Pos = Out_Pos'Old + 1);

   ----------
   -- Hex4 --
   ----------

   procedure Hex4
     (Input  : in     String;
      Pos    : in out Natural;
      Code   :    out Natural;
      Status :    out Status_Type)
   is
      C : Character;
      V : Natural range 0 .. 15;
   begin
      Code := 0;
      if Input'Length - Pos < 4 then
         Status := Truncated;
         return;
      end if;
      for I in 1 .. 4 loop
         pragma Loop_Invariant (Pos = Pos'Loop_Entry + (I - 1));
         pragma Loop_Invariant
           (Code <= (case I is
                        when 1 => 0, when 2 => 15,
                        when 3 => 255, when 4 => 4095));
         C := Cur (Input, Pos);
         case C is
            when '0' .. '9' =>
               V := Character'Pos (C) - Character'Pos ('0');
            when 'a' .. 'f' =>
               V := (Character'Pos (C) - Character'Pos ('a')) + 10;
            when 'A' .. 'F' =>
               V := (Character'Pos (C) - Character'Pos ('A')) + 10;
            when others =>
               Code   := 0;
               Status := Invalid_Escape;
               return;
         end case;
         Code := Code * 16 + V;
         Pos  := Pos + 1;
      end loop;
      Status := OK;
   end Hex4;

   ---------
   -- Put --
   ---------

   procedure Put
     (Output  : in out String;
      Out_Pos : in out Natural;
      B       : in     Natural)
   is
   begin
      Output (Output'First + Out_Pos) := Character'Val (B);
      Out_Pos := Out_Pos + 1;
   end Put;

   ------------
   -- Encode --
   ------------

   procedure Encode
     (Output  : in out String;
      Out_Pos : in out Natural;
      U       : in     Natural)
   is
   begin
      if U < 16#80# then
         Put (Output, Out_Pos, U);
      elsif U < 16#800# then
         Put (Output, Out_Pos, 16#C0# + U / 64);
         Put (Output, Out_Pos, 16#80# + U mod 64);
      elsif U < 16#10000# then
         Put (Output, Out_Pos, 16#E0# + U / 4096);
         Put (Output, Out_Pos, 16#80# + (U / 64) mod 64);
         Put (Output, Out_Pos, 16#80# + U mod 64);
      else
         Put (Output, Out_Pos, 16#F0# + U / 262144);
         Put (Output, Out_Pos, 16#80# + (U / 4096) mod 64);
         Put (Output, Out_Pos, 16#80# + (U / 64) mod 64);
         Put (Output, Out_Pos, 16#80# + U mod 64);
      end if;
   end Encode;

   ---------------
   -- Copy_Cont --
   ---------------

   procedure Copy_Cont
     (Input   : in     String;
      In_Pos  : in out Natural;
      Output  : in out String;
      Out_Pos : in out Natural;
      Lo, Hi  : in     Natural;
      Status  :    out Status_Type)
   is
      B : Natural;
   begin
      if In_Pos >= Input'Length then
         Status := Truncated;
         return;
      end if;
      B := Character'Pos (Cur (Input, In_Pos));
      if B in Lo .. Hi then
         Put (Output, Out_Pos, B);
         In_Pos := In_Pos + 1;
         Status := OK;
      else
         Status := Invalid_UTF8;
      end if;
   end Copy_Cont;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Input  : in     String;
      Output : in out String;
      Length :    out Natural;
      Status :    out Status_Type)
   is
      In_Pos  : Natural := 0;
      Out_Pos : Natural := 0;
      C       : Character;
      B0      : Natural;
      Rest    : Natural;
      High    : Natural;
      Low     : Natural;
      U       : Natural;
   begin
      Length := 0;

      while In_Pos < Input'Length loop
         pragma Loop_Invariant (In_Pos <= Input'Length);
         pragma Loop_Invariant (Out_Pos <= In_Pos);
         pragma Loop_Variant (Increases => In_Pos);
         C := Cur (Input, In_Pos);

         if C = '\' then
            In_Pos := In_Pos + 1;
            if In_Pos >= Input'Length then
               Status := Truncated;
               return;
            end if;
            C      := Cur (Input, In_Pos);
            In_Pos := In_Pos + 1;
            case C is
               when '"' | '\' | '/' =>
                  Put (Output, Out_Pos, Character'Pos (C));
               when 'b' =>
                  Put (Output, Out_Pos, 8);
               when 'f' =>
                  Put (Output, Out_Pos, 12);
               when 'n' =>
                  Put (Output, Out_Pos, 10);
               when 'r' =>
                  Put (Output, Out_Pos, 13);
               when 't' =>
                  Put (Output, Out_Pos, 9);

               when 'u' =>
                  Hex4 (Input, In_Pos, High, Status);
                  if Status /= OK then
                     return;
                  end if;
                  if High in 16#D800# .. 16#DBFF# then
                     --  High surrogate: require the paired \uXXXX low
                     --  surrogate and emit one supplementary character
                     if Input'Length - In_Pos < 2 then
                        Status := Truncated;
                        return;
                     end if;
                     if Cur (Input, In_Pos) /= '\'
                       or else Cur (Input, In_Pos + 1) /= 'u'
                     then
                        Status := Invalid_Escape;
                        return;
                     end if;
                     In_Pos := In_Pos + 2;
                     Hex4 (Input, In_Pos, Low, Status);
                     if Status /= OK then
                        return;
                     end if;
                     if Low not in 16#DC00# .. 16#DFFF# then
                        Status := Invalid_Escape;
                        return;
                     end if;
                     U := (16#10000# + ((High - 16#D800#) * 16#400#))
                       + (Low - 16#DC00#);
                     Encode (Output, Out_Pos, U);
                  elsif High in 16#DC00# .. 16#DFFF# then
                     Status := Invalid_Escape;
                     return;
                  else
                     Encode (Output, Out_Pos, High);
                  end if;

               when others =>
                  Status := Invalid_Escape;
                  return;
            end case;

         elsif Character'Pos (C) < 32 then
            Status := Invalid_String_Char;
            return;

         elsif Character'Pos (C) < 128 then
            Put (Output, Out_Pos, Character'Pos (C));
            In_Pos := In_Pos + 1;

         else
            --  A multi-byte UTF-8 sequence: validate (the same tightened
            --  first-byte ranges as the pull parser, excluding overlong
            --  forms, surrogates and > U+10FFFF) and copy through
            B0     := Character'Pos (C);
            Put (Output, Out_Pos, B0);
            In_Pos := In_Pos + 1;
            if B0 in 16#C2# .. 16#DF# then
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#80#, 16#BF#, Status);
               Rest := 0;
            elsif B0 = 16#E0# then
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#A0#, 16#BF#, Status);
               Rest := 1;
            elsif B0 in 16#E1# .. 16#EC# or else B0 in 16#EE# .. 16#EF# then
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#80#, 16#BF#, Status);
               Rest := 1;
            elsif B0 = 16#ED# then
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#80#, 16#9F#, Status);
               Rest := 1;
            elsif B0 = 16#F0# then
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#90#, 16#BF#, Status);
               Rest := 2;
            elsif B0 in 16#F1# .. 16#F3# then
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#80#, 16#BF#, Status);
               Rest := 2;
            elsif B0 = 16#F4# then
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#80#, 16#8F#, Status);
               Rest := 2;
            else
               Status := Invalid_UTF8;
               return;
            end if;
            if Status /= OK then
               return;
            end if;
            for I in 1 .. Rest loop
               pragma Loop_Invariant
                 (In_Pos in In_Pos'Loop_Entry .. Input'Length);
               pragma Loop_Invariant (Out_Pos <= In_Pos);
               Copy_Cont (Input, In_Pos, Output, Out_Pos,
                          16#80#, 16#BF#, Status);
               if Status /= OK then
                  return;
               end if;
            end loop;
         end if;
      end loop;

      Length := Out_Pos;
      Status := OK;
   end Decode;

end JSON.Strings;
