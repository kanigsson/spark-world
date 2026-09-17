--  Throwaway dogfooding demo for tui_term. NOT part of the library.
--
--  It exercises the roadmap's "done when" for the driver: enter the alternate
--  screen, clear, draw a coloured box, read keys, handle resize live, and
--  ALWAYS restore the terminal on exit (normal quit, or an exception bubbling
--  out of Run — the Mode.Session's Finalize runs either way). Resize the window
--  while it runs; quit with q, Esc, or Ctrl-C.

with Tui.Term.Event_Loop;
with Box_Demo;

procedure Main is
begin
   Tui.Term.Event_Loop.Run
     (Paint  => Box_Demo.Paint'Access,
      On_Key => Box_Demo.On_Key'Access);
end Main;
