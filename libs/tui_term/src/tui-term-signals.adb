with System;
with Ada.Interrupts.Names;

package body Tui.Term.Signals is

   --  All three signals funnel into one protected object. Handlers run at the
   --  hardware-interrupt priority and may only touch protected state, which is
   --  exactly what this does: flip a Boolean and return.
   protected Dispatcher
     with Interrupt_Priority => System.Interrupt_Priority'Last
   is
      procedure On_Winch with Attach_Handler => Ada.Interrupts.Names.SIGWINCH;
      procedure On_Term  with Attach_Handler => Ada.Interrupts.Names.SIGTERM;
      --  SIGINT is deliberately NOT attached: this GNAT runtime reserves it,
      --  and in raw mode (ISIG off) an interactive Ctrl-C reaches us as the
      --  byte 0x03 — an ordinary key event — not a signal anyway.

      --  Read-and-clear the resize flag (a procedure, not a function, because
      --  it mutates).
      procedure Take_Resize (Pending : out Boolean);

      function Quitting return Boolean;
   private
      Resized  : Boolean := False;
      Quit_Set : Boolean := False;
   end Dispatcher;

   protected body Dispatcher is

      procedure On_Winch is
      begin
         Resized := True;
      end On_Winch;

      procedure On_Term is
      begin
         Quit_Set := True;
      end On_Term;

      procedure Take_Resize (Pending : out Boolean) is
      begin
         Pending := Resized;
         Resized := False;
      end Take_Resize;

      function Quitting return Boolean is (Quit_Set);

   end Dispatcher;

   ---------------------------------------------------------------------------
   --  Public face
   ---------------------------------------------------------------------------

   procedure Install is
   begin
      --  Touch the object so this call provably depends on its elaboration;
      --  the Attach_Handler aspects have already done the real work by now.
      if Dispatcher.Quitting then
         null;
      end if;
   end Install;

   function Resize_Pending return Boolean is
      Pending : Boolean;
   begin
      Dispatcher.Take_Resize (Pending);
      return Pending;
   end Resize_Pending;

   function Quit_Requested return Boolean is (Dispatcher.Quitting);

end Tui.Term.Signals;
