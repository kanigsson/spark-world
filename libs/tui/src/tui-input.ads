--  Tui.Input — a byte-at-a-time terminal input decoder.
--
--  Feed it one byte at a time; it accumulates internal state and emits at most
--  one Key_Event per byte. It recognises:
--    * printable ASCII and C0 control codes (the latter as Ctrl-<letter>),
--    * UTF-8 multibyte sequences (assembled into a Char code point),
--    * CSI escape sequences  (ESC [ ... final)  — arrows, nav, function keys,
--      and the standard modifier encoding (ESC [ 1 ; 5 A = Ctrl-Up),
--    * SS3 escape sequences  (ESC O x)          — application-mode F1-F4/arrows,
--    * SGR mouse reports     (ESC [ < b ; x ; y M/m) — button presses,
--      releases, drag motion and wheel notches, with their 1-based position
--      (a driver must have asked the terminal for them; see the term crate),
--    * ESC <byte> as an Alt-modified key.
--
--  The lone-ESC ambiguity (is a bare ESC the Escape key, or the start of a
--  sequence whose tail has not arrived yet?) is resolved by the CALLER's clock:
--  the decoder never guesses on a timer. A driver that sees no follow-up byte
--  within its timeout calls Flush, which turns a pending bare ESC into Escape.
--  This keeps the decoder pure — no notion of time — and SPARK-provable.
--
--  Everything here is SPARK, proved to silver (no run-time errors). The
--  internal predicate also rules out arithmetic overflow during UTF-8 assembly.
--  No I/O, no OS: a driver crate reads the raw bytes; this only interprets them.

package Tui.Input
  with SPARK_Mode => On
is

   --  Names kept for the clients that spell them `Tui.Input.Byte`; the type
   --  itself is the root's, so a byte read here and a byte held by Tui.Text
   --  are now one type rather than two that need a conversion between them.
   subtype Byte is Tui.Byte;
   subtype Code_Point is Tui.Code_Point;

   type Key_Kind is
     (Char,                                   --  a printable character (Code)
      Enter,
      Tab,
      Backspace,
      Escape,          --  common editing keys
      Up,
      Down,
      Left,
      Right,                   --  cursor keys
      Home,
      End_Key,
      Page_Up,
      Page_Down,       --  navigation
      Insert,
      Delete,
      F1,
      F2,
      F3,
      F4,
      F5,
      F6,                  --  function keys
      F7,
      F8,
      F9,
      F10,
      F11,
      F12,
      Mouse_Press,
      Mouse_Release,
      Mouse_Motion, --  button down / up / drag
      Wheel_Up,
      Wheel_Down,                    --  scroll-wheel notches
      Unknown);                                --  recognised structure, no mapping

   type Modifiers is record
      Ctrl, Alt, Shift : Boolean := False;
   end record;

   No_Modifiers : constant Modifiers := (others => False);

   --  Mouse reports carry a 1-based screen position; 0 means "no position"
   --  (every non-mouse event). The bound is the CSI parameter range, which
   --  comfortably exceeds any real terminal's extent.
   subtype Mouse_Coordinate is Natural range 0 .. 9_999;

   --  Which button a press/release/motion report names. No_Button covers the
   --  reports that name none (it never accompanies a press from a terminal
   --  honouring the protocol, but the decoder does not trust the wire).
   type Mouse_Button is (Left_Button, Middle_Button, Right_Button, No_Button);

   --  One decoded key event. Code is meaningful only when Kind = Char, and
   --  Button/Col/Row only for the mouse kinds; everywhere else they hold
   --  their defaults and should be ignored. (A flat record rather than a
   --  discriminated one keeps `out` usage and aggregates trivial.)
   type Key_Event is record
      Kind   : Key_Kind := Unknown;
      Mods   : Modifiers := No_Modifiers;
      Code   : Code_Point := 0;
      Button : Mouse_Button := No_Button;
      Col    : Mouse_Coordinate := 0;
      Row    : Mouse_Coordinate := 0;
   end record;

   ---------------------------------------------------------------------------
   --  The decoder
   ---------------------------------------------------------------------------

   type Decoder is private;
   --  Default-initialised to the Ground state; just declare `D : Decoder;`.

   --  Consume one byte. On return, Available says whether Event holds a
   --  freshly-completed key event. Bytes that merely advance a pending sequence
   --  return Available = False.
   procedure Feed
     (D         : in out Decoder;
      Input     : Byte;
      Event     : out Key_Event;
      Available : out Boolean)
   with Global => null;

   --  Resolve a pending sequence with no further input (driver timeout / EOF).
   --  A pending bare ESC becomes the Escape key; any other partial sequence is
   --  discarded. Always leaves the decoder in the Ground state.
   procedure Flush
     (D : in out Decoder; Event : out Key_Event; Available : out Boolean)
   with
     Global => null,
     Post   =>
       not Is_Pending (D) and then (if Available then Event.Kind = Escape);

   --  True when the decoder is mid-sequence — i.e. a Flush could still produce
   --  an event. Drivers use this to decide whether to arm an ESC timeout.
   function Is_Pending (D : Decoder) return Boolean
   with Global => null;

private

   ESC : constant Byte := 16#1B#;

   type Parser_State is (Ground, After_Esc, In_Csi, In_Ss3, In_Utf8);

   subtype Pending_Count is Natural range 0 .. 3;          --  UTF-8 bytes left
   subtype Acc_Type is Natural range 0 .. 2_097_151;  --  UTF-8 accumulator
   subtype Param_Val is Mouse_Coordinate;              --  one CSI parameter
   subtype Param_Index is Positive range 1 .. 3;         --  which param

   --  The predicate ties the UTF-8 accumulator to the number of continuation
   --  bytes still expected, so that each `Acc * 64 + ...` step is provably
   --  in range (max legitimate value is 0x1F_FFFF, the subtype's bound).
   type Decoder is record
      St      : Parser_State := Ground;
      Acc     : Acc_Type := 0;
      Pending : Pending_Count := 0;
      P1      : Param_Val := 0;
      P2      : Param_Val := 0;
      P3      : Param_Val := 0;
      PIdx    : Param_Index := 1;
      Mouse   : Boolean := False;   --  saw the SGR '<' marker after CSI
   end record
   with
     Dynamic_Predicate =>
       ((Decoder.St = In_Utf8) = (Decoder.Pending > 0))
       and then (if Decoder.Pending = 1 then Decoder.Acc <= 32_767)
       and then (if Decoder.Pending = 2 then Decoder.Acc <= 511)
       and then (if Decoder.Pending = 3 then Decoder.Acc <= 7);

   function Is_Pending (D : Decoder) return Boolean
   is (D.St /= Ground);

end Tui.Input;
