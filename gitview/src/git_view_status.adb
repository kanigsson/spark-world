package body Git_View_Status with SPARK_Mode => On is

   use Tui.App_Kit.Status;

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
         when Selection_Copied  => Put (L, "Selection copied");
         when Selection_Copy_Truncated =>
            Put (L, "Selection copied (first 65536 bytes)");
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
