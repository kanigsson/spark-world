package body Git_View_Status with SPARK_Mode => On is

   ---------------------------------------------------------------------------
   --  Line-buffer building blocks. Every append truncates at Max_Status, so
   --  the only proof obligation is an in-range index, which the guard gives.
   ---------------------------------------------------------------------------

   procedure Reset (L : out Line) is
   begin
      L := (Text => (others => ' '), Len => 0);
   end Reset;

   procedure Put_Char (L : in out Line; C : Character) is
   begin
      if L.Len < Max_Status then
         L.Len := L.Len + 1;
         L.Text (L.Len) := C;
      end if;
   end Put_Char;

   procedure Put (L : in out Line; S : String) is
   begin
      for C of S loop
         Put_Char (L, C);
      end loop;
   end Put;

   --  Decimal image of N with no leading space (Natural'Image prefixes one).
   procedure Put_Nat (L : in out Line; N : Natural) is
      S : constant String := Natural'Image (N);
   begin
      for I in S'Range loop
         if I > S'First then
            Put_Char (L, S (I));
         end if;
      end loop;
   end Put_Nat;

   --  One pattern byte, shown as a Latin-1 character.
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

   -----------------
   -- Format_Note --
   -----------------

   procedure Format_Note (L : out Line; N : Note) is
   begin
      Reset (L);
      case N is
         when Pattern_Not_Found => Put (L, "Pattern not found");
         when No_Pattern        => Put (L, "No pattern");
         when No_Commit_On_Line => Put (L, "No commit on this line");
         when Git_Show_Failed   => Put (L, "git show failed");
         when No_Note           => null;   --  excluded by the precondition
      end case;
   end Format_Note;

   --------------------------
   -- Format_List_Position --
   --------------------------

   procedure Format_List_Position
     (L        : out Line;
      Selected : Natural;
      Total    : Natural;
      Id       : String)
   is
   begin
      Reset (L);
      Put (L, "[commits] ");
      Put_Nat (L, Selected);
      Put_Char (L, '/');
      Put_Nat (L, Total);
      if Id'Length > 0 then
         Put (L, "  ");
         Put (L, Id);
      end if;
      Put (L, "   (Enter diff  Tab pane  / search  q quit)");
   end Format_List_Position;

   --------------------------
   -- Format_Diff_Position --
   --------------------------

   procedure Format_Diff_Position
     (L     : out Line;
      Id    : String;
      Top   : Natural;
      Last  : Natural;
      Total : Natural)
   is
      --  Percentage of the diff scrolled past, 100 for an empty document.
      --  Last and Total are bounded by Max_Lines (precondition), so the
      --  Long_Integer product and the back-conversion stay well in range.
      Pct : constant Natural :=
        (if Total = 0 then 100
         else Natural ((Long_Integer (Last) * 100) / Long_Integer (Total)));
   begin
      Reset (L);
      Put (L, "[diff] ");
      if Id'Length > 0 then
         Put (L, Id);
         Put (L, "  ");
      end if;
      Put_Nat (L, Top);
      Put_Char (L, '-');
      Put_Nat (L, Last);
      Put_Char (L, '/');
      Put_Nat (L, Total);
      Put (L, "  ");
      Put_Nat (L, Pct);
      Put (L, "%   (Tab pane  / search  q quit)");
   end Format_Diff_Position;

end Git_View_Status;
