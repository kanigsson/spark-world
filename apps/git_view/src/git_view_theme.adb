package body Git_View_Theme
  with SPARK_Mode => On
is

   use type Tui.Text.Byte;

   --  True when the line begins with the literal ASCII prefix.
   function Starts_With
     (Line : Tui.Text.Buffer; Prefix : String) return Boolean
   with Global => null
   is
   begin
      if Line'Length < Prefix'Length then
         return False;
      end if;
      for I in Prefix'Range loop
         if Line (Line'First + (I - Prefix'First))
           /= Tui.Text.Byte (Character'Pos (Prefix (I)))
         then
            return False;
         end if;
      end loop;
      return True;
   end Starts_With;

   --------------
   -- Classify --
   --------------

   function Classify (Line : Tui.Text.Buffer) return Line_Kind is
   begin
      if Line'Length = 0 then
         return Plain_Line;
      end if;

      if Starts_With (Line, "diff ")
        or else Starts_With (Line, "index ")
        or else Starts_With (Line, "+++")
        or else Starts_With (Line, "---")
        or else Starts_With (Line, "new file ")
        or else Starts_With (Line, "deleted file ")
        or else Starts_With (Line, "old mode ")
        or else Starts_With (Line, "new mode ")
        or else Starts_With (Line, "rename ")
        or else Starts_With (Line, "copy ")
        or else Starts_With (Line, "similarity ")
        or else Starts_With (Line, "dissimilarity ")
        or else Starts_With (Line, "Binary files ")
      then
         return File_Meta;
      elsif Starts_With (Line, "@@") then
         return Hunk;
      elsif Starts_With (Line, "+") then
         return Added;
      elsif Starts_With (Line, "-") then
         return Removed;
      elsif Starts_With (Line, "commit ") then
         return Commit_Head;
      else
         return Plain_Line;
      end if;
   end Classify;

end Git_View_Theme;
