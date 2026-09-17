with Tui;
with Tui.UTF8;
with Tui.Width;

package body Git_View_Syntax with SPARK_Mode => On is

   use type Tui.Text.Byte;

   function Lower (B : Tui.Text.Byte) return Tui.Text.Byte is
     (if B in Character'Pos ('A') .. Character'Pos ('Z')
      then B + (Character'Pos ('a') - Character'Pos ('A')) else B);

   function Starts_With (Line : Tui.Text.Buffer; Prefix : String)
     return Boolean
   with Pre => Prefix'Length in 1 .. 16
   is
      Off : Natural := 0;
   begin
      if Line'Length < Prefix'Length then
         return False;
      end if;
      while Off < Prefix'Length loop
         pragma Loop_Invariant (Off <= Prefix'Length);
         pragma Loop_Variant (Decreases => Prefix'Length - Off);
         if Line (Line'First + Off)
           /= Tui.Text.Byte (Character'Pos (Prefix (Prefix'First + Off)))
         then
            return False;
         end if;
         Off := Off + 1;
      end loop;
      return True;
   end Starts_With;

   function Ends_With (Line : Tui.Text.Buffer; Suffix : String)
     return Boolean
   with Pre => Suffix'Length in 1 .. 16
   is
      Off : Natural := 0;
   begin
      if Line'Length < Suffix'Length then
         return False;
      end if;
      while Off < Suffix'Length loop
         pragma Loop_Invariant (Off <= Suffix'Length);
         pragma Loop_Variant (Decreases => Suffix'Length - Off);
         if Lower (Line (Line'Last - Suffix'Length + 1 + Off))
           /= Tui.Text.Byte (Character'Pos (Suffix (Suffix'First + Off)))
         then
            return False;
         end if;
         Off := Off + 1;
      end loop;
      return True;
   end Ends_With;

   procedure Header_Language
     (Line  : Tui.Text.Buffer;
      Found : out Boolean;
      Lang  : out Language)
   is
   begin
      Found := False;
      Lang  := Plain;
      if not (Starts_With (Line, "+++ b/")
              or else Starts_With (Line, "--- a/"))
      then
         return;
      end if;

      Found := True;
      if Ends_With (Line, ".adb") or else Ends_With (Line, ".ads")
        or else Ends_With (Line, ".ada") or else Ends_With (Line, ".gpr")
      then
         Lang := Ada_Lang;
      elsif Ends_With (Line, ".c") or else Ends_With (Line, ".h")
        or else Ends_With (Line, ".cc") or else Ends_With (Line, ".hh")
        or else Ends_With (Line, ".cpp") or else Ends_With (Line, ".hpp")
        or else Ends_With (Line, ".cxx") or else Ends_With (Line, ".rs")
        or else Ends_With (Line, ".go") or else Ends_With (Line, ".java")
        or else Ends_With (Line, ".js") or else Ends_With (Line, ".jsx")
        or else Ends_With (Line, ".ts") or else Ends_With (Line, ".tsx")
        or else Ends_With (Line, ".swift") or else Ends_With (Line, ".kt")
      then
         Lang := C_Family;
      elsif Ends_With (Line, ".py") or else Ends_With (Line, ".pyi")
        or else Ends_With (Line, ".rb")
      then
         Lang := Python_Like;
      elsif Ends_With (Line, ".sh") or else Ends_With (Line, ".bash")
        or else Ends_With (Line, ".zsh")
      then
         Lang := Shell_Like;
      elsif Ends_With (Line, ".json") or else Ends_With (Line, ".toml")
        or else Ends_With (Line, ".yaml") or else Ends_With (Line, ".yml")
      then
         Lang := Config;
      end if;
   end Header_Language;

   function Language_At
     (Content : Tui.Text.Buffer;
      Idx     : Tui.Text.Index;
      N       : Tui.Text.Line_Number) return Language
   is
      Found : Boolean;
      Lang  : Language;
   begin
      for K in reverse 1 .. N loop
         Header_Language (Tui.Text.Line (Idx, Content, K), Found, Lang);
         if Found then
            return Lang;
         end if;
      end loop;
      return Plain;
   end Language_At;

   function Is_Identifier_Start (B : Tui.Text.Byte) return Boolean is
     (B in Character'Pos ('a') .. Character'Pos ('z')
      or else B in Character'Pos ('A') .. Character'Pos ('Z')
      or else B = Character'Pos ('_'));

   function Is_Identifier (B : Tui.Text.Byte) return Boolean is
     (Is_Identifier_Start (B) or else Is_Digit (B));

   function Same_Word
     (Line : Tui.Text.Buffer;
      From : Tui.Text.Byte_Index;
      To   : Tui.Text.Byte_Index;
      Word : String;
      Fold : Boolean) return Boolean
   with Pre => From in Line'Range and then To in From .. Line'Last
               and then Word'Length in 1 .. 16
   is
      Off : Natural := 0;
   begin
      if To - From + 1 /= Word'Length then
         return False;
      end if;
      while Off < Word'Length loop
         pragma Loop_Invariant (Off <= Word'Length);
         pragma Loop_Variant (Decreases => Word'Length - Off);
         declare
            B : constant Tui.Text.Byte := Line (From + Off);
         begin
            if (if Fold then Lower (B) else B)
              /= Tui.Text.Byte (Character'Pos (Word (Word'First + Off)))
            then
               return False;
            end if;
         end;
         Off := Off + 1;
      end loop;
      return True;
   end Same_Word;

   function Is_Keyword
     (Line : Tui.Text.Buffer;
      From : Tui.Text.Byte_Index;
      To   : Tui.Text.Byte_Index;
      Lang : Language) return Boolean
   is
      Fold : constant Boolean := Lang = Ada_Lang;
   begin
      case Lang is
         when Ada_Lang =>
            return Same_Word (Line, From, To, "procedure", Fold)
              or else Same_Word (Line, From, To, "function", Fold)
              or else Same_Word (Line, From, To, "package", Fold)
              or else Same_Word (Line, From, To, "begin", Fold)
              or else Same_Word (Line, From, To, "end", Fold)
              or else Same_Word (Line, From, To, "is", Fold)
              or else Same_Word (Line, From, To, "type", Fold)
              or else Same_Word (Line, From, To, "subtype", Fold)
              or else Same_Word (Line, From, To, "record", Fold)
              or else Same_Word (Line, From, To, "with", Fold)
              or else Same_Word (Line, From, To, "use", Fold)
              or else Same_Word (Line, From, To, "if", Fold)
              or else Same_Word (Line, From, To, "then", Fold)
              or else Same_Word (Line, From, To, "else", Fold)
              or else Same_Word (Line, From, To, "elsif", Fold)
              or else Same_Word (Line, From, To, "loop", Fold)
              or else Same_Word (Line, From, To, "for", Fold)
              or else Same_Word (Line, From, To, "while", Fold)
              or else Same_Word (Line, From, To, "return", Fold)
              or else Same_Word (Line, From, To, "declare", Fold)
              or else Same_Word (Line, From, To, "constant", Fold)
              or else Same_Word (Line, From, To, "private", Fold)
              or else Same_Word (Line, From, To, "body", Fold)
              or else Same_Word (Line, From, To, "null", Fold);
         when C_Family =>
            return Same_Word (Line, From, To, "if", False)
              or else Same_Word (Line, From, To, "else", False)
              or else Same_Word (Line, From, To, "for", False)
              or else Same_Word (Line, From, To, "while", False)
              or else Same_Word (Line, From, To, "return", False)
              or else Same_Word (Line, From, To, "switch", False)
              or else Same_Word (Line, From, To, "case", False)
              or else Same_Word (Line, From, To, "break", False)
              or else Same_Word (Line, From, To, "continue", False)
              or else Same_Word (Line, From, To, "class", False)
              or else Same_Word (Line, From, To, "struct", False)
              or else Same_Word (Line, From, To, "enum", False)
              or else Same_Word (Line, From, To, "fn", False)
              or else Same_Word (Line, From, To, "let", False)
              or else Same_Word (Line, From, To, "const", False)
              or else Same_Word (Line, From, To, "var", False)
              or else Same_Word (Line, From, To, "function", False)
              or else Same_Word (Line, From, To, "pub", False)
              or else Same_Word (Line, From, To, "impl", False)
              or else Same_Word (Line, From, To, "import", False)
              or else Same_Word (Line, From, To, "interface", False)
              or else Same_Word (Line, From, To, "type", False);
         when Python_Like =>
            return Same_Word (Line, From, To, "def", False)
              or else Same_Word (Line, From, To, "class", False)
              or else Same_Word (Line, From, To, "if", False)
              or else Same_Word (Line, From, To, "elif", False)
              or else Same_Word (Line, From, To, "else", False)
              or else Same_Word (Line, From, To, "for", False)
              or else Same_Word (Line, From, To, "while", False)
              or else Same_Word (Line, From, To, "return", False)
              or else Same_Word (Line, From, To, "import", False)
              or else Same_Word (Line, From, To, "from", False)
              or else Same_Word (Line, From, To, "as", False)
              or else Same_Word (Line, From, To, "try", False)
              or else Same_Word (Line, From, To, "except", False)
              or else Same_Word (Line, From, To, "with", False)
              or else Same_Word (Line, From, To, "lambda", False)
              or else Same_Word (Line, From, To, "yield", False)
              or else Same_Word (Line, From, To, "async", False)
              or else Same_Word (Line, From, To, "await", False)
              or else Same_Word (Line, From, To, "True", False)
              or else Same_Word (Line, From, To, "False", False)
              or else Same_Word (Line, From, To, "None", False);
         when Shell_Like =>
            return Same_Word (Line, From, To, "if", False)
              or else Same_Word (Line, From, To, "then", False)
              or else Same_Word (Line, From, To, "else", False)
              or else Same_Word (Line, From, To, "elif", False)
              or else Same_Word (Line, From, To, "fi", False)
              or else Same_Word (Line, From, To, "for", False)
              or else Same_Word (Line, From, To, "while", False)
              or else Same_Word (Line, From, To, "do", False)
              or else Same_Word (Line, From, To, "done", False)
              or else Same_Word (Line, From, To, "case", False)
              or else Same_Word (Line, From, To, "esac", False)
              or else Same_Word (Line, From, To, "function", False)
              or else Same_Word (Line, From, To, "in", False);
         when Config =>
            return Same_Word (Line, From, To, "true", False)
              or else Same_Word (Line, From, To, "false", False)
              or else Same_Word (Line, From, To, "null", False);
         when Plain =>
            return False;
      end case;
   end Is_Keyword;

   function Starts_Comment
     (Line : Tui.Text.Buffer;
      Pos  : Tui.Text.Byte_Index;
      Lang : Language) return Boolean
   is
      B : constant Tui.Text.Byte := Line (Pos);
   begin
      case Lang is
         when Ada_Lang =>
            return B = Character'Pos ('-') and then Pos < Line'Last
              and then Line (Pos + 1) = Character'Pos ('-');
         when C_Family =>
            return B = Character'Pos ('/') and then Pos < Line'Last
              and then (Line (Pos + 1) = Character'Pos ('/')
                        or else Line (Pos + 1) = Character'Pos ('*'));
         when Python_Like | Shell_Like | Config =>
            return B = Character'Pos ('#');
         when Plain =>
            return False;
      end case;
   end Starts_Comment;

   function Display_Column
     (Line   : Tui.Text.Buffer;
      Offset : Tui.Text.Byte_Count) return Tui.Pager.Dimension
   is
   begin
      if Offset = 0 then
         return 0;
      end if;
      declare
         Pos       : Natural := Line'First;
         Remaining : Tui.Text.Byte_Count := Offset;
         Col       : Tui.Pager.Dimension := 0;
      begin
         while Remaining > 0 and then Col < Tui.Pager.Max_Dim loop
            pragma Loop_Invariant (Pos in Line'First .. Line'Last);
            pragma Loop_Invariant
              (Remaining <= Line'Last - Pos + 1);
            pragma Loop_Variant (Decreases => Remaining);
            declare
            Avail : constant Positive := Remaining;
            B0 : constant Tui.Byte := Tui.Byte (Line (Pos));
            B1 : constant Tui.Byte :=
              (if Remaining >= 2 then Tui.Byte (Line (Pos + 1)) else 0);
            B2 : constant Tui.Byte :=
              (if Remaining >= 3 then Tui.Byte (Line (Pos + 2)) else 0);
            B3 : constant Tui.Byte :=
              (if Remaining >= 4 then Tui.Byte (Line (Pos + 3)) else 0);
            CP  : Tui.Code_Point;
            Len : Positive;
            W   : Natural;
         begin
            Tui.UTF8.Decode (B0, B1, B2, B3, Avail, CP, Len);
            W := (if CP = 16#09# then 8 - (Col mod 8)
                  else Natural (Tui.Width.Char_Width (CP)));
            Col := Natural'Min (Tui.Pager.Max_Dim, Col + W);
            Remaining := Remaining - Len;
            if Remaining > 0 then
               Pos := Pos + Len;
            end if;
            end;
         end loop;
         return Col;
      end;
   end Display_Column;

end Git_View_Syntax;
