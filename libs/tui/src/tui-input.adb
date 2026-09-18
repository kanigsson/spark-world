package body Tui.Input
  with SPARK_Mode => On
is

   Unknown_Event : constant Key_Event :=
     (Kind => Unknown, Mods => No_Modifiers, Code => 0, others => <>);

   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   --  Decode the CSI modifier parameter (e.g. 5 -> Ctrl). The encoding is
   --  (value - 1) as a bitmask: bit 0 Shift, bit 1 Alt, bit 2 Ctrl.
   function Mods_Of (P : Param_Val) return Modifiers is
      Bits : Natural;
   begin
      if P = 0 then
         return No_Modifiers;
      end if;
      Bits := P - 1;
      return
        (Shift => (Bits mod 2) = 1,
         Alt   => ((Bits / 2) mod 2) = 1,
         Ctrl  => ((Bits / 4) mod 2) = 1);
   end Mods_Of;

   --  Map the numeric parameter of an "ESC [ n ~" sequence to a key.
   function Tilde_Key (P : Param_Val) return Key_Kind is
   begin
      case P is
         when 1 | 7  =>
            return Home;

         when 4 | 8  =>
            return End_Key;

         when 2      =>
            return Insert;

         when 3      =>
            return Delete;

         when 5      =>
            return Page_Up;

         when 6      =>
            return Page_Down;

         when 11     =>
            return F1;

         when 12     =>
            return F2;

         when 13     =>
            return F3;

         when 14     =>
            return F4;

         when 15     =>
            return F5;

         when 17     =>
            return F6;

         when 18     =>
            return F7;

         when 19     =>
            return F8;

         when 20     =>
            return F9;

         when 21     =>
            return F10;

         when 23     =>
            return F11;

         when 24     =>
            return F12;

         when others =>
            return Unknown;
      end case;
   end Tilde_Key;

   --  Interpret a single, non-escape byte (printable ASCII, C0 control, or
   --  DEL) as a key event, with the given Alt modifier folded in. Bytes
   --  outside that range (e.g. a UTF-8 lead) yield Unknown; the Ground state
   --  handles those before reaching here.
   function Simple_Event (B : Byte; Alt : Boolean) return Key_Event is
      M : constant Modifiers := (Ctrl => False, Alt => Alt, Shift => False);
   begin
      if B = 16#0D# or else B = 16#0A# then
         --  CR / LF
         return (Kind => Enter, Mods => M, Code => 0, others => <>);
      elsif B = 16#09# then
         --  HT
         return (Kind => Tab, Mods => M, Code => 0, others => <>);
      elsif B = 16#08# or else B = 16#7F# then
         --  BS / DEL
         return (Kind => Backspace, Mods => M, Code => 0, others => <>);
      elsif B = 16#00# then
         --  NUL = Ctrl-@
         return
           (Kind   => Char,
            Mods   => (Ctrl => True, Alt => Alt, Shift => False),
            Code   => 64,
            others => <>);
      elsif B in 16#01# .. 16#1F# then
         --  other C0 = Ctrl-<letter>
         return
           (Kind   => Char,
            Mods   => (Ctrl => True, Alt => Alt, Shift => False),
            Code   => Code_Point (B) + 64,
            others => <>);
      elsif B in 16#20# .. 16#7E# then
         --  printable ASCII
         return
           (Kind => Char, Mods => M, Code => Code_Point (B), others => <>);
      else
         return (Kind => Unknown, Mods => M, Code => 0, others => <>);
      end if;
   end Simple_Event;

   ---------------------------------------------------------------------------
   --  Per-state byte handlers
   ---------------------------------------------------------------------------

   --  Note: the decoder's predicate couples St, Pending and Acc, so these
   --  fields must move together. We always assign the record as a whole rather
   --  than field-by-field, which would transiently break the predicate.
   procedure Start_Utf8 (D : in out Decoder; B : Byte) is
      P : Pending_Count;
      A : Acc_Type;
   begin
      if B in 16#C0# .. 16#DF# then
         P := 1;
         A := Acc_Type (B and 16#1F#);
      elsif B in 16#E0# .. 16#EF# then
         P := 2;
         A := Acc_Type (B and 16#0F#);
      else
         --  16#F0# .. 16#F7#
         P := 3;
         A := Acc_Type (B and 16#07#);
      end if;
      D :=
        (St      => In_Utf8,
         Acc     => A,
         Pending => P,
         P1      => 0,
         P2      => 0,
         P3      => 0,
         PIdx    => 1,
         Mouse   => False);
   end Start_Utf8;

   --  A clean Ground state that preserves the (now irrelevant) CSI parameters.
   function Reset_To_Ground (D : Decoder) return Decoder
   is (St      => Ground,
       Acc     => 0,
       Pending => 0,
       P1      => D.P1,
       P2      => D.P2,
       P3      => D.P3,
       PIdx    => D.PIdx,
       Mouse   => D.Mouse);

   procedure Ground_Byte
     (D         : in out Decoder;
      B         : Byte;
      Event     : out Key_Event;
      Available : out Boolean) is
   begin
      if B = ESC then
         D.St := After_Esc;
         Event := Unknown_Event;
         Available := False;
      elsif B in 16#C0# .. 16#F7# then
         --  UTF-8 lead byte
         Start_Utf8 (D, B);
         Event := Unknown_Event;
         Available := False;
      elsif B in 16#80# .. 16#BF# or else B in 16#F8# .. 16#FF# then
         Event :=
           Unknown_Event;                 --  stray continuation / invalid
         Available := True;
      else
         Event := Simple_Event (B, Alt => False);
         Available := True;
      end if;
   end Ground_Byte;

   procedure Utf8_Byte
     (D         : in out Decoder;
      B         : Byte;
      Event     : out Key_Event;
      Available : out Boolean) is
   begin
      if B in 16#80# .. 16#BF# then
         --  a continuation byte
         declare
            New_Acc : constant Acc_Type :=
              D.Acc * 64 + Acc_Type (B and 16#3F#);
         begin
            if D.Pending = 1 then
               --  sequence complete
               if New_Acc <= 16#10_FFFF# then
                  Event :=
                    (Kind   => Char,
                     Mods   => No_Modifiers,
                     Code   => Code_Point (New_Acc),
                     others => <>);
               else
                  Event := Unknown_Event;
               end if;
               D := Reset_To_Ground (D);
               Available := True;
            else
               --  more bytes to come
               D :=
                 (St      => In_Utf8,
                  Acc     => New_Acc,
                  Pending => D.Pending - 1,
                  P1      => D.P1,
                  P2      => D.P2,
                  P3      => D.P3,
                  PIdx    => D.PIdx,
                  Mouse   => D.Mouse);
               Event := Unknown_Event;
               Available := False;
            end if;
         end;
      else
         --  malformed; abort, drop byte
         D := Reset_To_Ground (D);
         Event := Unknown_Event;
         Available := False;
      end if;
   end Utf8_Byte;

   procedure Esc_Byte
     (D         : in out Decoder;
      B         : Byte;
      Event     : out Key_Event;
      Available : out Boolean) is
   begin
      if B = 16#5B# then
         --  '[' : start CSI
         D.St := In_Csi;
         D.P1 := 0;
         D.P2 := 0;
         D.P3 := 0;
         D.PIdx := 1;
         D.Mouse := False;
         Event := Unknown_Event;
         Available := False;
      elsif B = 16#4F# then
         --  'O' : start SS3
         D.St := In_Ss3;
         Event := Unknown_Event;
         Available := False;
      elsif B = ESC then
         --  the previous ESC was Escape
         D.St := After_Esc;                       --  this ESC starts afresh
         Event :=
           (Kind => Escape, Mods => No_Modifiers, Code => 0, others => <>);
         Available := True;
      else
         --  ESC <byte> = Alt-<byte>
         D.St := Ground;
         Event := Simple_Event (B, Alt => True);
         Available := True;
      end if;
   end Esc_Byte;

   procedure Interpret_Csi
     (P1, P2    : Param_Val;
      Final     : Byte;
      Event     : out Key_Event;
      Available : out Boolean)
   is
      M : constant Modifiers := Mods_Of (P2);
      K : Key_Kind;
   begin
      case Final is
         when 16#41# =>
            K := Up;        --  'A'

         when 16#42# =>
            K := Down;      --  'B'

         when 16#43# =>
            K := Right;     --  'C'

         when 16#44# =>
            K := Left;      --  'D'

         when 16#48# =>
            K := Home;      --  'H'

         when 16#46# =>
            K := End_Key;   --  'F'

         when 16#5A# =>
            --  'Z' = back-tab
            Event :=
              (Kind   => Tab,
               Mods   => (Shift => True, Ctrl => False, Alt => False),
               Code   => 0,
               others => <>);
            Available := True;
            return;

         when 16#7E# =>
            K := Tilde_Key (P1);  --  '~'

         when others =>
            K := Unknown;
      end case;
      Event := (Kind => K, Mods => M, Code => 0, others => <>);
      Available := True;
   end Interpret_Csi;

   --  Interpret the final byte of an SGR mouse report, CSI < Pb ; Px ; Py M/m.
   --  Pb's low two bits select the button, bit 6 marks a wheel notch, bit 5
   --  flags motion, and bits 2..4 carry the usual Shift/Alt/Ctrl. The coordinates
   --  are the terminal's, 1-based, passed through unchanged.
   procedure Interpret_Mouse
     (Pb, Px, Py : Param_Val;
      Final      : Byte;
      Event      : out Key_Event;
      Available  : out Boolean)
   is
      M      : constant Modifiers :=
        (Shift => (Pb / 4) mod 2 = 1,
         Alt   => (Pb / 8) mod 2 = 1,
         Ctrl  => (Pb / 16) mod 2 = 1);
      Motion : constant Boolean := (Pb / 32) mod 2 = 1;
      Wheel  : constant Boolean := (Pb / 64) mod 2 = 1;
      Low    : constant Param_Val := Pb mod 4;
      K      : Key_Kind;
      Btn    : Mouse_Button := No_Button;
   begin
      if Wheel then
         K :=
           (case Low is
              when 0      => Wheel_Up,
              when 1      => Wheel_Down,
              when others => Unknown);   --  wheel-left/right: unmapped

      else
         case Low is
            when 0      =>
               Btn := Left_Button;

            when 1      =>
               Btn := Middle_Button;

            when 2      =>
               Btn := Right_Button;

            when others =>
               Btn := No_Button;
         end case;
         K :=
           (if Motion
            then Mouse_Motion
            elsif Final = 16#4D#
            then Mouse_Press
            else Mouse_Release);
      end if;

      if K = Unknown then
         Event := Unknown_Event;
      else
         Event :=
           (Kind   => K,
            Mods   => M,
            Code   => 0,
            Button => Btn,
            Col    => Px,
            Row    => Py);
      end if;
      Available := True;
   end Interpret_Mouse;

   procedure Csi_Byte
     (D         : in out Decoder;
      B         : Byte;
      Event     : out Key_Event;
      Available : out Boolean) is
   begin
      if B in 16#30# .. 16#39# then
         --  digit
         declare
            Digit : constant Param_Val := Param_Val (B - 16#30#);
         begin
            if D.PIdx = 1 then
               if D.P1 <= 999 then
                  D.P1 := D.P1 * 10 + Digit;
               end if;
            elsif D.PIdx = 2 then
               if D.P2 <= 999 then
                  D.P2 := D.P2 * 10 + Digit;
               end if;
            else
               if D.P3 <= 999 then
                  D.P3 := D.P3 * 10 + Digit;
               end if;
            end if;
         end;
         Event := Unknown_Event;
         Available := False;
      elsif B = 16#3B# then
         --  ';' : next parameter
         if D.PIdx < 3 then
            D.PIdx := D.PIdx + 1;
         end if;
         Event := Unknown_Event;
         Available := False;
      elsif B in 16#3C# .. 16#3F# or else B in 16#20# .. 16#2F# then
         if B = 16#3C# then
            --  '<' : an SGR mouse report
            D.Mouse := True;
         end if;
         Event := Unknown_Event;                   --  other private /
         Available := False;                       --  intermediate: ignore
      elsif B in 16#40# .. 16#7E# then
         --  final byte
         if D.Mouse then
            if B = 16#4D# or else B = 16#6D# then
               --  'M' press / 'm' release
               Interpret_Mouse (D.P1, D.P2, D.P3, B, Event, Available);
            else
               --  '<' with a foreign final
               Event := Unknown_Event;
               Available := True;
            end if;
         else
            Interpret_Csi (D.P1, D.P2, B, Event, Available);
         end if;
         D.St := Ground;
      elsif B = ESC then
         --  restart on embedded ESC
         D.St := After_Esc;
         Event := Unknown_Event;
         Available := False;
      else
         --  unexpected: abort
         D.St := Ground;
         Event := Unknown_Event;
         Available := False;
      end if;
   end Csi_Byte;

   procedure Ss3_Byte
     (D         : in out Decoder;
      B         : Byte;
      Event     : out Key_Event;
      Available : out Boolean)
   is
      K : Key_Kind;
   begin
      case B is
         when 16#41# =>
            K := Up;        --  'A'

         when 16#42# =>
            K := Down;      --  'B'

         when 16#43# =>
            K := Right;     --  'C'

         when 16#44# =>
            K := Left;      --  'D'

         when 16#48# =>
            K := Home;      --  'H'

         when 16#46# =>
            K := End_Key;   --  'F'

         when 16#50# =>
            K := F1;        --  'P'

         when 16#51# =>
            K := F2;        --  'Q'

         when 16#52# =>
            K := F3;        --  'R'

         when 16#53# =>
            K := F4;        --  'S'

         when others =>
            K := Unknown;
      end case;
      D.St := Ground;
      Event := (Kind => K, Mods => No_Modifiers, Code => 0, others => <>);
      Available := True;
   end Ss3_Byte;

   ---------------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------------

   procedure Feed
     (D         : in out Decoder;
      Input     : Byte;
      Event     : out Key_Event;
      Available : out Boolean) is
   begin
      case D.St is
         when Ground    =>
            Ground_Byte (D, Input, Event, Available);

         when After_Esc =>
            Esc_Byte (D, Input, Event, Available);

         when In_Csi    =>
            Csi_Byte (D, Input, Event, Available);

         when In_Ss3    =>
            Ss3_Byte (D, Input, Event, Available);

         when In_Utf8   =>
            Utf8_Byte (D, Input, Event, Available);
      end case;
   end Feed;

   procedure Flush
     (D : in out Decoder; Event : out Key_Event; Available : out Boolean) is
   begin
      if D.St = After_Esc then
         D.St := Ground;
         Event :=
           (Kind => Escape, Mods => No_Modifiers, Code => 0, others => <>);
         Available := True;
      else
         D := Reset_To_Ground (D);
         Event := Unknown_Event;
         Available := False;
      end if;
   end Flush;

end Tui.Input;
