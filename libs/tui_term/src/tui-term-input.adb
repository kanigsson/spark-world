with Tui.Term.Sys;
use type Tui.Term.Sys.Read_Outcome;
use type Tui.Term.Sys.Poll_Outcome;

--  SPARK_Mode is On here: this body is the first consumer to lean on the
--  Tui.Term.Sys boundary contracts, and it is the place the roadmap singled out.
--  Because Buf_Len is bounded by its subtype and Sys.Read promises Count is
--  within the buffer, the assignment Buf_Len := Count discharges its range check
--  from that contract — the buffer-bound reasoning that used to be an unchecked
--  narrowing of read()'s raw return is now machine-checked. The raw bytes feed a
--  decoder that is itself proved (Tui.Input); only the syscall behind Sys.Read
--  stays trusted.

package body Tui.Term.Input
  with SPARK_Mode => On
is

   ---------------------------------------------------------------------------
   --  Raw-byte buffer, refilled by Tui.Term.Sys.Read and drained one byte at a
   --  time into the decoder. Process-wide (there is one terminal); not task-safe
   --  by design — a single host loop owns the read side.
   --
   --  The subtypes carry the invariants the proof needs across calls: Buf_Len is
   --  never more than the buffer holds, and Buf_Pos walks 1 .. Buf_Len + 1. Buf
   --  starts fully zeroed and is only ever read at indices <= Buf_Len, so no
   --  uninitialised byte is ever fed to the decoder.
   ---------------------------------------------------------------------------

   Capacity : constant := 256;

   subtype Length_Range is Natural range 0 .. Capacity;
   subtype Cursor_Range is Positive range 1 .. Capacity + 1;

   Buf     : Tui.Term.Sys.Byte_Array (1 .. Capacity) := (others => 0);
   Buf_Len : Length_Range := 0;   --  bytes currently held
   Buf_Pos : Cursor_Range := 1;   --  next byte to feed (1 .. Buf_Len)

   ---------------------------------------------------------------------------
   --  Next
   ---------------------------------------------------------------------------

   procedure Next
     (D       : in out Tui.Input.Decoder;
      Event   : out Tui.Input.Key_Event;
      Status  : out Read_Status;
      Timeout : Integer := -1)
   is
      Avail     : Boolean;
      Effective : Integer;
      Count     : Natural;
      Outcome   : Tui.Term.Sys.Read_Outcome;
   begin
      Event := (others => <>);

      loop
         --  1. Drain whatever bytes we already have. The guard keeps Buf_Pos in
         --  1 .. Buf_Len <= Capacity, so the index into Buf is in range.
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
              (if Timeout < 0
               then Default_Esc_Timeout_Ms
               else Integer'Min (Timeout, Default_Esc_Timeout_Ms));
         else
            Effective := Timeout;
         end if;

         case Tui.Term.Sys.Poll (Stdin_FD, Effective) is
            when Tui.Term.Sys.Poll_Timeout     =>
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

            when Tui.Term.Sys.Poll_Interrupted =>
               --  Interrupted by a signal (EINTR) or an error: hand control back
               --  so the host can check Tui.Term.Signals, then call Next again.
               Status := Timed_Out;
               return;

            when Tui.Term.Sys.Poll_Ready       =>
               --  Data is ready: refill. Sys.Read bounds Count by Buf'Length, so
               --  Buf_Len := Count is in Length_Range with no narrowing of its
               --  own — the bound is discharged from the boundary contract.
               Tui.Term.Sys.Read (Stdin_FD, Buf, Count, Outcome);
               if Outcome = Tui.Term.Sys.Read_Closed then
                  Status := End_Of_Input;
                  return;
               end if;
               Buf_Len := Count;
               Buf_Pos := 1;
         end case;
      end loop;
   end Next;

end Tui.Term.Input;
