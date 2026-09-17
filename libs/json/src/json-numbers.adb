--  JSON.Numbers body.
--
--  To_Integer accumulates on the negative side so that Integer_64'First
--  (whose magnitude exceeds 'Last) is reachable, with the overflow guard
--  spelled as two literal comparisons the prover discharges linearly.
--
--  To_Float splits the token into an up-to-19-digit mantissa and one
--  decimal exponent that aggregates the explicit exponent, dropped
--  integer digits and used fraction digits. The mantissa converts to
--  Long_Float exactly enough (one rounding), and the exponent is then
--  applied by repeated multiplication or division by 10.0 behind a
--  conservative magnitude guard — one rounding per step, which is where
--  the documented ~1.0E-13 relative error bound comes from, and a
--  rejection threshold one decade under Long_Float'Last.

package body JSON.Numbers with SPARK_Mode => On is

   use type Interfaces.Unsigned_64;

   subtype I64 is Interfaces.Integer_64;
   subtype U64 is Interfaces.Unsigned_64;

   function Cur (Token : String; Pos : Natural) return Character is
     (Token (Token'First + Pos))
   with Pre => Pos < Token'Length;

   function Is_Digit (C : Character) return Boolean is (C in '0' .. '9');

   function Digit (C : Character) return Natural is
     (Character'Pos (C) - Character'Pos ('0'))
   with Pre => Is_Digit (C), Post => Digit'Result <= 9;

   ----------------
   -- To_Integer --
   ----------------

   procedure To_Integer
     (Token : in     String;
      Value :    out I64;
      OK    :    out Boolean)
   is
      --  Integer_64'First / 10, truncated: V may take one more digit
      --  exactly when V is above this, or equal to it with a digit <= 8
      Limit : constant I64 := -922_337_203_685_477_580;

      Pos : Natural := 0;
      Neg : Boolean := False;
      V   : I64     := 0;
      D   : Natural range 0 .. 9;
   begin
      Value := 0;
      OK    := False;

      if Token'Length = 0 then
         return;
      end if;
      if Cur (Token, Pos) = '-' then
         Neg := True;
         Pos := Pos + 1;
         if Pos >= Token'Length then
            return;
         end if;
      end if;

      --  int = 0 / digit1-9 *DIGIT: a leading zero stands alone

      if Cur (Token, Pos) = '0' and then Token'Length - Pos > 1 then
         return;
      end if;

      while Pos < Token'Length loop
         pragma Loop_Invariant (Pos <= Token'Length);
         pragma Loop_Invariant (V in I64'First .. 0);
         pragma Loop_Variant (Increases => Pos);
         if not Is_Digit (Cur (Token, Pos)) then
            return;
         end if;
         D := Digit (Cur (Token, Pos));
         if V < Limit or else (V = Limit and then D > 8) then
            return;  --  the next digit would overflow Integer_64
         end if;
         V   := V * 10 - I64 (D);
         Pos := Pos + 1;
      end loop;

      if Neg then
         Value := V;
      else
         if V = I64'First then
            return;  --  9223372036854775808 has no positive Integer_64
         end if;
         Value := -V;
      end if;
      OK := True;
   end To_Integer;

   --------------
   -- To_Float --
   --------------

   procedure To_Float
     (Token : in     String;
      Value :    out Long_Float;
      OK    :    out Boolean)
   is
      --  Mantissa digits beyond this would not change the result; the
      --  guard keeps M * 10 + 9 below 2**63
      M_Limit : constant U64 := 10**18 - 1;

      --  Decimal exponents beyond these bounds saturate: the value is
      --  certainly an overflow (high side) or a flush to zero (low side)

      E_Cap   : constant := 100_000;

      Pos      : Natural := 0;
      Neg      : Boolean := False;
      M        : U64     := 0;
      E10      : Integer range -E_Cap .. E_Cap := 0;
      Exp      : Natural range 0 .. E_Cap := 0;
      Exp_Neg  : Boolean := False;
      E        : Integer;
      F        : Long_Float;
   begin
      Value := 0.0;
      OK    := False;

      if Token'Length = 0 then
         return;
      end if;
      if Cur (Token, Pos) = '-' then
         Neg := True;
         Pos := Pos + 1;
         if Pos >= Token'Length then
            return;
         end if;
      end if;

      --  int = 0 / digit1-9 *DIGIT

      if not Is_Digit (Cur (Token, Pos)) then
         return;
      end if;
      if Cur (Token, Pos) = '0' then
         Pos := Pos + 1;
         if Pos < Token'Length and then Is_Digit (Cur (Token, Pos)) then
            return;  --  leading zero
         end if;
      else
         while Pos < Token'Length and then Is_Digit (Cur (Token, Pos)) loop
            pragma Loop_Invariant (Pos <= Token'Length);
            pragma Loop_Invariant (M <= M_Limit * 10 + 9);
            pragma Loop_Variant (Increases => Pos);
            if M <= M_Limit then
               M := M * 10 + U64 (Digit (Cur (Token, Pos)));
            elsif E10 < E_Cap then
               E10 := E10 + 1;  --  dropped integer digit
            end if;
            Pos := Pos + 1;
         end loop;
      end if;

      --  frac = '.' 1*DIGIT

      if Pos < Token'Length and then Cur (Token, Pos) = '.' then
         Pos := Pos + 1;
         if Pos >= Token'Length
           or else not Is_Digit (Cur (Token, Pos))
         then
            return;
         end if;
         while Pos < Token'Length and then Is_Digit (Cur (Token, Pos)) loop
            pragma Loop_Invariant (Pos <= Token'Length);
            pragma Loop_Invariant (M <= M_Limit * 10 + 9);
            pragma Loop_Variant (Increases => Pos);
            if M <= M_Limit and then E10 > -E_Cap then
               M   := M * 10 + U64 (Digit (Cur (Token, Pos)));
               E10 := E10 - 1;  --  used fraction digit
            end if;
            Pos := Pos + 1;
         end loop;
      end if;

      --  exp = ('e' / 'E') [sign] 1*DIGIT

      if Pos < Token'Length and then Cur (Token, Pos) in 'e' | 'E' then
         Pos := Pos + 1;
         if Pos < Token'Length and then Cur (Token, Pos) in '+' | '-' then
            Exp_Neg := Cur (Token, Pos) = '-';
            Pos     := Pos + 1;
         end if;
         if Pos >= Token'Length
           or else not Is_Digit (Cur (Token, Pos))
         then
            return;
         end if;
         while Pos < Token'Length and then Is_Digit (Cur (Token, Pos)) loop
            pragma Loop_Invariant (Pos <= Token'Length);
            pragma Loop_Variant (Increases => Pos);
            if Exp < E_Cap / 10 then
               Exp := Exp * 10 + Digit (Cur (Token, Pos));
            else
               Exp := E_Cap;  --  saturate: magnitude is decided anyway
            end if;
            Pos := Pos + 1;
         end loop;
      end if;

      if Pos < Token'Length then
         return;  --  trailing characters: not a number token
      end if;

      --  Combine and scale. M = 0 covers "0", "-0", "0.00e99".

      if M = 0 then
         OK := True;
         return;
      end if;

      E := E10 + (if Exp_Neg then -Exp else Exp);

      if E > 310 then
         return;          --  >= 10**310: certain overflow
      elsif E < -360 then
         OK := True;      --  < 10**(19-360): certain flush to zero
         return;
      end if;

      F := Long_Float (M);

      while E > 0 loop
         pragma Loop_Invariant (E <= 310);
         pragma Loop_Invariant (F in 0.0 .. 1.0E308);
         pragma Loop_Variant (Decreases => E);
         if F > 1.0E307 then
            Value := 0.0;
            return;  --  conservative: within one decade of 'Last
         end if;
         F := F * 10.0;
         E := E - 1;
      end loop;

      while E < 0 loop
         pragma Loop_Invariant (E >= -360);
         pragma Loop_Invariant (F in 0.0 .. 1.0E308);
         pragma Loop_Variant (Increases => E);
         F := F / 10.0;
         E := E + 1;
      end loop;

      Value := (if Neg then -F else F);
      OK    := True;
   end To_Float;

end JSON.Numbers;
