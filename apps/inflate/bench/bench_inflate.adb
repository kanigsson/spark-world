--  Benchmark: one-shot raw-deflate decompression with the SPARK crate.
--
--  usage: bench_inflate INPUT OUT_CAP ITERS
--  prints: produced bytes, best wall time per iteration, MB/s (output)

with Ada.Command_Line;          use Ada.Command_Line;
with Ada.Real_Time;             use Ada.Real_Time;
with Ada.Streams;               use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;               use Ada.Text_IO;

with Inflate;                   use Inflate;
with Inflate.Raw;

procedure Bench_Inflate is
   type Byte_Array_Access is access Byte_Array;

   function Load (Name : String) return Byte_Array_Access is
      use Ada.Streams.Stream_IO;
      F : Ada.Streams.Stream_IO.File_Type;
   begin
      Open (F, In_File, Name);
      declare
         Len  : constant Natural := Natural (Size (F));
         Buf  : constant Byte_Array_Access := new Byte_Array (1 .. Len);
         SEA  : Stream_Element_Array (1 .. Stream_Element_Offset (Len));
         Last : Stream_Element_Offset;
      begin
         Read (F, SEA, Last);
         for I in SEA'Range loop
            Buf (Natural (I)) := Byte (SEA (I));
         end loop;
         Close (F);
         return Buf;
      end;
   end Load;

   Input    : constant Byte_Array_Access := Load (Argument (1));
   Out_Cap  : constant Natural := Natural'Value (Argument (2));
   Iters    : constant Natural := Natural'Value (Argument (3));
   Output   : constant Byte_Array_Access := new Byte_Array (1 .. Out_Cap);
   Consumed, Produced : Natural := 0;
   Status   : Status_Type := OK;
   T0       : Time;
   Best     : Duration := Duration'Last;
   Lap      : Duration;
begin
   for I in 1 .. Iters loop
      T0 := Clock;
      Raw.Decompress (Input.all, Output.all, Consumed, Produced, Status);
      Lap := To_Duration (Clock - T0);
      if Status /= OK then
         Put_Line ("error: " & Status'Image);
         Set_Exit_Status (1);
         return;
      end if;
      if Lap < Best then
         Best := Lap;
      end if;
   end loop;
   declare
      MBs : constant Float := Float (Produced) / Float (Best) / 1.0E6;
   begin
      Put_Line ("spark     produced=" & Produced'Image
                & " best=" & Duration'Image (Best) & "s "
                & MBs'Image & " MB/s");
   end;
end Bench_Inflate;
