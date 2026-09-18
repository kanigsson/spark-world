package body Grep_Front
  with SPARK_Mode => On
is

   ------------------
   -- Apply_Letter --
   ------------------

   procedure Apply_Letter
     (Opt : in out Settings; Letter : Character; Outcome : out Letter_Result)
   is
   begin
      Outcome := Accepted;
      case Letter is
         when 'E'    =>
            Opt.Fixed := False;

         when 'F'    =>
            Opt.Fixed := True;

         when 'n'    =>
            Opt.Numbered := True;

         when 'v'    =>
            Opt.Invert := True;

         when 'c'    =>
            Opt.Count_Only := True;

         when 'q'    =>
            Opt.Quiet := True;

         when 'l'    =>
            Opt.List_Files := True;

         when 'x'    =>
            Opt.Whole := True;

         when 'h'    =>
            Opt.Names := Never;

         when 'H'    =>
            Opt.Names := Always;

         when 'z'    =>
            Opt.Delimiter := ASCII.NUL;

         when 'e'    =>
            Outcome := Needs_Value;

         when others =>
            Outcome := Unknown;
      end case;
   end Apply_Letter;

   -----------------
   -- Set_Pattern --
   -----------------

   procedure Set_Pattern
     (Self : in out Pattern_State; Value : String; Result : out Pattern_Result)
   is
   begin
      if Self.Present then
         Result := Already_Set;
      else
         Self :=
           (Text => Unbounded.To_Unbounded_String (Value), Present => True);
         Result := Taken;
      end if;
   end Set_Pattern;

   ----------------
   -- Meta_Count --
   ----------------

   function Meta_Count (Literal : String) return Natural
   is (if Literal'Length = 0
       then 0
       else
         Meta_Count (Literal (Literal'First .. Literal'Last - 1))
         + (if Is_Meta (Literal (Literal'Last)) then 1 else 0));

   --------------------
   -- Escape_Literal --
   --------------------

   function Escape_Literal (Literal : String) return String is
      --  Initialised at the declaration: flow analysis does not follow the
      --  written prefix, so an uninitialised buffer leaves the returned slice
      --  unproved.
      Result : String (1 .. 2 * Literal'Length) := [others => ' '];
      Last   : Natural := 0;
   begin
      for K in Literal'Range loop
         pragma
           Loop_Invariant
             (Last
                = (K - Literal'First)
                  + Meta_Count (Literal (Literal'First .. K - 1)));
         if Is_Meta (Literal (K)) then
            Last := Last + 1;
            Result (Last) := '\';
         end if;
         Last := Last + 1;
         Result (Last) := Literal (K);
      end loop;
      return Result (1 .. Last);
   end Escape_Literal;

end Grep_Front;
