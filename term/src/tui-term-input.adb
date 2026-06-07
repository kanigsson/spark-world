with System;
with Interfaces.C;            use Interfaces.C;

package body Tui.Term.Input is

   POLLIN : constant short := 1;

   ---------------------------------------------------------------------------
   --  libc bindings — the read edge
   ---------------------------------------------------------------------------

   function C_Read (FD : int; Buf : System.Address; Count : size_t)
      return long
     with Import, Convention => C, External_Name => "read";

   type Pollfd is record
      FD      : int;
      Events  : short := 0;
      Revents : short := 0;
   end record
     with Convention => C;

   function C_Poll (Fds : System.Address; N : unsigned_long; Timeout : int)
      return int
     with Import, Convention => C, External_Name => "poll";

   function Wait (Timeout_Ms : Integer) return Integer is
      PFD : aliased Pollfd := (FD => int (Stdin_FD), Events => POLLIN, others => 0);
   begin
      return Integer (C_Poll (PFD'Address, 1, int (Timeout_Ms)));
   end Wait;

   ---------------------------------------------------------------------------
   --  Raw-byte buffer, refilled by read() and drained one byte at a time into
   --  the decoder. Process-wide (there is one terminal); not task-safe by
   --  design — a single host loop owns the read side.
   ---------------------------------------------------------------------------

   Buf     : array (1 .. 256) of Tui.Input.Byte;
   Buf_Len : Natural := 0;   --  bytes currently held
   Buf_Pos : Natural := 1;   --  next byte to feed (1 .. Buf_Len)

   ---------------------------------------------------------------------------
   --  Next
   ---------------------------------------------------------------------------

   procedure Next
     (D       : in out Tui.Input.Decoder;
      Event   :    out Tui.Input.Key_Event;
      Status  :    out Read_Status;
      Timeout : Integer := -1)
   is
      Avail     : Boolean;
      Effective : Integer;
      P         : Integer;
      N         : long;
   begin
      Event := (others => <>);

      loop
         --  1. Drain whatever bytes we already have.
         while Buf_Pos <= Buf_Len loop
            declare
               B : constant Tui.Input.Byte := Buf (Buf_Pos);
            begin
               Buf_Pos := Buf_Pos + 1;
               Tui.Input.Feed (D, B, Event, Avail);
               if Avail then
                  Status := Got_Event;
                  return;
               end if;
            end;
         end loop;

         --  2. Buffer empty. Pick the wait. While the decoder is mid-sequence,
         --  never wait longer than the ESC window, so a stranded ESC resolves
         --  to the Escape key promptly (and never blocks forever on Timeout<0).
         if Tui.Input.Is_Pending (D) then
            Effective :=
              (if Timeout < 0 then Default_Esc_Timeout_Ms
               else Integer'Min (Timeout, Default_Esc_Timeout_Ms));
         else
            Effective := Timeout;
         end if;

         P := Wait (Effective);

         if P = 0 then
            --  Timed out. A pending sequence becomes its resolved key (ESC).
            if Tui.Input.Is_Pending (D) then
               Tui.Input.Flush (D, Event, Avail);
               if Avail then
                  Status := Got_Event;
                  return;
               end if;
            end if;
            Status := Timed_Out;
            return;

         elsif P < 0 then
            --  Interrupted by a signal (EINTR) or an error: hand control back
            --  so the host can check Tui.Term.Signals, then call Next again.
            Status := Timed_Out;
            return;
         end if;

         --  3. Data is ready: refill the buffer.
         N := C_Read (int (Stdin_FD), Buf'Address, Buf'Length);
         if N <= 0 then
            Status := End_Of_Input;
            return;
         end if;
         Buf_Len := Natural (N);
         Buf_Pos := 1;
      end loop;
   end Next;

end Tui.Term.Input;
