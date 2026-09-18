--  The painter and key handler for the scratch demo, in a library-level package
--  because Tui.Term.Event_Loop's callback access types require subprograms that
--  outlive the call (a procedure nested in Main would fail the accessibility
--  check). State (box position, last key) lives in the body.

with Tui.Surface;
with Tui.Input;

package Box_Demo is

   --  Fill the (blanked, terminal-sized) surface: a title, a movable coloured
   --  box, and a status line.
   procedure Paint (S : in out Tui.Surface.Surface);

   --  Arrows move the box; q / Escape / Ctrl-C quit; anything else just updates
   --  the status line.
   procedure On_Key
     (Event : Tui.Input.Key_Event; Dirty : out Boolean; Quit : out Boolean);

end Box_Demo;
