with Tui.Term.Output;

package body Tui.Term.Clipboard with SPARK_Mode => On is

   ESC : constant Character := Character'Val (16#1B#);
   BEL : constant Character := Character'Val (16#07#);

   ---------
   -- Set --
   ---------

   procedure Set
     (Text      : Tui.Panes.Clip.Payload;
      To        : Destination := Clipboard;
      Ends_With : Terminator := Bell)
   is
      Count : constant Natural := Tui.Panes.Clip.Quartet_Count (Text);
   begin
      if Count = 0 then
         return;
      end if;

      Output.Put (ESC & "]52;" & (case To is
                                    when Clipboard => 'c',
                                    when Primary   => 'p') & ";");
      for N in 1 .. Count loop
         Output.Put (Tui.Panes.Clip.Encode (Text, N));
      end loop;
      case Ends_With is
         when Bell              => Output.Put ((1 => BEL));
         when String_Terminator => Output.Put (ESC & "\");
      end case;
   end Set;

end Tui.Term.Clipboard;
