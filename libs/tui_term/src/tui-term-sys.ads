--  Tui.Term.Sys — the syscall edge, with a machine-checked boundary.
--
--  This is the ONE place the raw libc read/write/poll imports live. The shims it
--  exposes turn each bare syscall into a typed, bounded operation, and the seam
--  between trusted and proved is drawn exactly at this spec:
--
--    * The BODY is `SPARK_Mode => Off` by design (principle 3: the OS edge stays
--      out of SPARK). It does what only unproved glue can — pass `'Address` to
--      libc, bind value-returning C functions — and is trusted, not verified.
--
--    * This SPEC is SPARK. Each shim's contract (the bounded `Count`, the outcome
--      classification) is the boundary the proved core checks against: a consumer
--      that stores `Count` into a buffer-length variable has its range check
--      discharged here, rather than trusting by hand that read()/write() never
--      report more bytes than they were handed.
--
--  So the assumption the rest of the stack used to take on faith ("read() returns
--  at most Count") moves from a prose comment into a contract the prover enforces
--  at every call site in SPARK code. What stays trusted — that libc honours its
--  own man-page — is confined to the one Off body behind these contracts.

with Tui.Input;

package Tui.Term.Sys
  with SPARK_Mode => On
is

   --  Raw bytes as they come off the wire. Same octet type the decoder consumes,
   --  so a refilled buffer feeds straight in with no reinterpretation.
   type Byte_Array is array (Positive range <>) of Tui.Input.Byte;

   ---------------------------------------------------------------------------
   --  read()
   ---------------------------------------------------------------------------

   type Read_Outcome is
     (Read_Data,     --  Count bytes were read (Count in 1 .. Buf'Length)
      Read_Closed);  --  EOF, error, or signal: read() returned <= 0, stop

   --  Read up to Buf'Length bytes from FD into Buf, leaving Count in
   --  0 .. Buf'Length and Outcome saying whether anything arrived. The bounded
   --  Count is the point: a caller stores it into a buffer-length variable and
   --  the range check discharges from this Post — no unchecked narrowing of
   --  read()'s raw return value, which is where the old reader simply trusted
   --  that read() never reports more than it was asked for.
   procedure Read
     (FD      : File_Descriptor;
      Buf     : out Byte_Array;
      Count   : out Natural;
      Outcome : out Read_Outcome)
   with
     Global => null,
     Post   =>
       Count <= Buf'Length and then (Outcome = Read_Data) = (Count > 0);

   ---------------------------------------------------------------------------
   --  write()
   ---------------------------------------------------------------------------

   --  Write up to Data'Length bytes of Data to FD. Written is how many libc
   --  actually took, 0 .. Data'Length (0 on a closed pipe or error); the caller
   --  loops on the remainder. The bound is what keeps that loop's offset
   --  arithmetic in range.
   procedure Write (FD : File_Descriptor; Data : String; Written : out Natural)
   with Global => null, Post => Written <= Data'Length;

   ---------------------------------------------------------------------------
   --  poll()
   ---------------------------------------------------------------------------

   type Poll_Outcome is
     (Poll_Ready,        --  data is waiting on FD
      Poll_Timeout,      --  the wait elapsed with nothing to read
      Poll_Interrupted); --  a signal (EINTR) or error cut the wait short

   --  Wait up to Timeout_Ms for FD to become readable (a negative timeout
   --  blocks). Folds poll()'s int return into the three cases a host loop
   --  actually distinguishes, and hides the pollfd struct and its address.
   function Poll
     (FD : File_Descriptor; Timeout_Ms : Integer) return Poll_Outcome
   with Global => null;

end Tui.Term.Sys;
