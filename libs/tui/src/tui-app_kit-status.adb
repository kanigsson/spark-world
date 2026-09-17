package body Tui.App_Kit.Status with SPARK_Mode => On is

   -----------
   -- Reset --
   -----------

   procedure Reset (L : out Line) is
   begin
      L := (Text => (others => ' '), Len => 0);
   end Reset;

   --------------
   -- Put_Char --
   --------------

   procedure Put_Char (L : in out Line; C : Character) is
   begin
      if L.Len < Max_Status then
         L.Len := L.Len + 1;
         L.Text (L.Len) := C;
      end if;
   end Put_Char;

   ---------
   -- Put --
   ---------

   procedure Put (L : in out Line; S : String) is
   begin
      for C of S loop
         Put_Char (L, C);
      end loop;
   end Put;

   -------------
   -- Put_Nat --
   -------------

   procedure Put_Nat (L : in out Line; N : Natural) is
      S : constant String := Natural'Image (N);
   begin
      for I in S'Range loop
         if I > S'First then
            Put_Char (L, S (I));
         end if;
      end loop;
   end Put_Nat;

   --------------
   -- Put_Byte --
   --------------

   procedure Put_Byte (L : in out Line; B : Tui.Text.Byte) is
   begin
      Put_Char (L, Character'Val (Natural (B)));
   end Put_Byte;

   -------------------
   -- Format_Prompt --
   -------------------

   procedure Format_Prompt
     (L       : out Line;
      Forward : Boolean;
      Pattern : Tui.Text.Buffer)
   is
   begin
      Reset (L);
      Put_Char (L, (if Forward then '/' else '?'));
      for B of Pattern loop
         Put_Byte (L, B);
      end loop;
   end Format_Prompt;

end Tui.App_Kit.Status;
