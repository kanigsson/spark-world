--  The policy half of the git source, proved: which arguments each load
--  passes, what an exit code means for the document, and the failure
--  fallback that keeps the diff pane well-formed. The spawn/capture
--  mechanics live behind the trusted private child.

with Git_View_Source.OS;

package body Git_View_Source with SPARK_Mode => On is

   --  Bound a short argument into the boundary's fixed-size record.
   function Arg (S : String) return OS.Argument
   with Pre => S'Length <= OS.Max_Argument_Length;

   function Arg (S : String) return OS.Argument is
      R : OS.Argument;
   begin
      R.Len := S'Length;
      R.Text (1 .. S'Length) := S;
      return R;
   end Arg;

   --  A one-line document carrying Msg, for the failure fallback.
   function Text_Document (Msg : String) return Tui.Text.Doc_Ref
   with Pre  => Msg'Length <= 60,
        Post => Text_Document'Result /= null;

   function Text_Document (Msg : String) return Tui.Text.Doc_Ref is
      Buf : Tui.Text.Buffer (1 .. Msg'Length) := (others => 0);
   begin
      for K in 1 .. Msg'Length loop
         Buf (K) := Character'Pos (Msg (Msg'First + (K - 1)));
      end loop;
      return Tui.Text.New_Document (Buf);
   end Text_Document;

   ---------------
   -- Available --
   ---------------

   function Available return Boolean is (OS.Find_Git);

   -------------------
   -- Make_Revision --
   -------------------

   procedure Make_Revision
     (Text  : String;
      Value : out Revision;
      Ok    : out Boolean)
   is
   begin
      Value := (Text => (others => ' '), Len => 0);
      Ok := Text'Length in 1 .. Max_Revision_Length;
      if Ok then
         Value.Text (1 .. Text'Length) := Text;
         Value.Len := Text'Length;
      end if;
   end Make_Revision;

   -----------------
   -- Make_Filter --
   -----------------

   procedure Make_Filter
     (Text  : String;
      Value : out Filter_Value;
      Ok    : out Boolean)
   is
   begin
      Value := (Text => (others => ' '), Len => 0);
      Ok := Text'Length in 1 .. Max_Filter_Length;
      if Ok then
         Value.Text (1 .. Text'Length) := Text;
         Value.Len := Text'Length;
      end if;
   end Make_Filter;

   --------------
   -- Load_Log --
   --------------

   procedure Load_Log
     (From    : Revision;
      Filter  : Filters;
      Doc     : out Tui.Text.Doc_Ref;
      Ok      : out Boolean)
   is
      Max_Log_Args : constant := 17;
      Args : OS.Argument_Vector (1 .. Max_Log_Args);
      Last : Natural range 0 .. Max_Log_Args := 0;
      Code : Integer;

      procedure Add (S : String)
      with Pre  => Last < Max_Log_Args and then S'Length <= 255,
           Post => Last = Last'Old + 1;

      procedure Add (S : String) is
      begin
         Last := Last + 1;
         Args (Last) := Arg (S);
      end Add;
   begin
      --  The abbreviated id must stay the first space-terminated token of
      --  every line: the proved commit-id parser depends on it. No --graph
      --  for the same reason — its continuation lines carry no commit.
      Add ("log");
      Add ("--date=short");
      Add ("--decorate=short");
      Add ("--pretty=format:%h %ad%(decorate:prefix= [,suffix=],separator=%x2C ) %an %s");
      if Filter.All_Refs then
         Add ("--all");
      end if;
      if Filter.First_Parent then
         Add ("--first-parent");
      end if;
      if Filter.Author.Len > 0 then
         Add ("--author");
         Add (Image (Filter.Author));
      end if;
      if Filter.Since.Len > 0 then
         Add ("--since");
         Add (Image (Filter.Since));
      end if;
      if Filter.Until_Date.Len > 0 then
         Add ("--until");
         Add (Image (Filter.Until_Date));
      end if;
      if Filter.Message.Len > 0 then
         Add ("--grep");
         Add (Image (Filter.Message));
      end if;
      if From.Len > 0 then
         Add (Image (From));
      end if;
      if From.Len > 0 or else Filter.Path.Len > 0 then
         --  Everything after -- is a pathspec; a revision before it can never
         --  be mistaken for a path, preserving the previous CLI boundary.
         Add ("--");
      end if;
      if Filter.Path.Len > 0 then
         Add (Image (Filter.Path));
      end if;

      OS.Capture
        (Args       => Args (1 .. Last),
         Err_To_Out => False,
         Doc        => Doc,
         Code       => Code);
      if Code /= 0 and then Doc /= null then
         Tui.Text.Free (Doc);
      end if;
      Ok := Doc /= null;
   end Load_Log;

   ---------------
   -- Load_Diff --
   ---------------

   procedure Load_Diff
     (Id  : Git_View_Sha.Sha;
      Doc : in out Tui.Text.Doc_Ref;
      Ok  : out Boolean)
   is
      Code : Integer;
   begin
      Tui.Text.Free (Doc);   --  reclaim the replaced document (no-op on null)

      --  Fold stderr into the pane: the alternate screen is up by now, and
      --  git's own message in the diff pane beats a corrupted display.
      OS.Capture
        (Args       => (Arg ("show"), Arg (Git_View_Sha.Image (Id))),
         Err_To_Out => True,
         Doc        => Doc,
         Code       => Code);
      Ok := Code = 0 and then Doc /= null;
      if Doc = null then
         Doc := Text_Document ("git show " & Git_View_Sha.Image (Id)
                               & " failed");
      end if;
   end Load_Diff;

end Git_View_Source;
