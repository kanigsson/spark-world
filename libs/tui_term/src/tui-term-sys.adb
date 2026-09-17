with System;
with Interfaces.C;            use Interfaces.C;

--  SPARK_Mode is Off for this body by design: it passes 'Address to libc, which
--  cannot be expressed in SPARK, and binds value-returning C functions (which an
--  Ada function must mirror, yet a SPARK function may not have a buffer it
--  fills). So the shims here are TRUSTED glue. Their contracts live on the spec
--  (which is SPARK), where consumers in the proved core check against them — the
--  boundary is machine-checked even though this side of it is not.
package body Tui.Term.Sys with SPARK_Mode => Off is

   POLLIN : constant short := 1;

   ---------------------------------------------------------------------------
   --  libc imports — the bare syscall edge. The assumptions the spec's shim
   --  contracts encode (read() returns <= Count and fills those bytes; write()
   --  returns <= Count; poll() returns <= nfds) are stated there, assumed there.
   ---------------------------------------------------------------------------

   function C_Read (FD : int; Buf : System.Address; Count : size_t) return long
     with Import, Convention => C, External_Name => "read";

   function C_Write (FD : int; Buf : System.Address; Count : size_t) return long
     with Import, Convention => C, External_Name => "write";

   type Pollfd is record
      FD      : int;
      Events  : short := 0;
      Revents : short := 0;
   end record
     with Convention => C;

   function C_Poll (Fds : System.Address; N : unsigned_long; Timeout : int)
      return int
     with Import, Convention => C, External_Name => "poll";

   ---------------------------------------------------------------------------
   --  Read
   ---------------------------------------------------------------------------

   procedure Read
     (FD      : File_Descriptor;
      Buf     : out Byte_Array;
      Count   : out Natural;
      Outcome : out Read_Outcome)
   is
      N : constant long := C_Read (int (FD), Buf'Address, size_t (Buf'Length));
   begin
      if N <= 0 then
         --  EOF, error, or interrupted: nothing was placed in Buf.
         Outcome := Read_Closed;
         Count   := 0;
      else
         Outcome := Read_Data;
         Count   := Natural (N);
      end if;
   end Read;

   ---------------------------------------------------------------------------
   --  Write
   ---------------------------------------------------------------------------

   procedure Write
     (FD      : File_Descriptor;
      Data    : String;
      Written : out Natural)
   is
   begin
      if Data'Length = 0 then
         Written := 0;
      else
         declare
            N : constant long :=
              C_Write (int (FD), Data (Data'First)'Address, size_t (Data'Length));
         begin
            Written := (if N <= 0 then 0 else Natural (N));
         end;
      end if;
   end Write;

   ---------------------------------------------------------------------------
   --  Poll
   ---------------------------------------------------------------------------

   function Poll (FD : File_Descriptor; Timeout_Ms : Integer) return Poll_Outcome
   is
      PFD : aliased Pollfd := (FD => int (FD), Events => POLLIN, others => 0);
      R   : constant int := C_Poll (PFD'Address, 1, int (Timeout_Ms));
   begin
      if R > 0 then
         return Poll_Ready;
      elsif R = 0 then
         return Poll_Timeout;
      else
         return Poll_Interrupted;
      end if;
   end Poll;

end Tui.Term.Sys;
