--  The policy half of the git source, proved: what a failed load means for
--  the document, and the failure fallback that keeps the diff pane
--  well-formed. Repository access itself lives behind the trusted private
--  child, which drives the git_changes library.

with Git_View_Source.OS;

package body Git_View_Source with SPARK_Mode => On is

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
   begin
      OS.Load_History (From, Filter, Doc, Ok);
   end Load_Log;

   ---------------
   -- Load_Diff --
   ---------------

   procedure Load_Diff
     (Id  : Git_View_Sha.Sha;
      Doc : in out Tui.Text.Doc_Ref;
      Ok  : out Boolean)
   is
   begin
      Tui.Text.Free (Doc);   --  reclaim the replaced document (no-op on null)
      OS.Load_Commit (Git_View_Sha.Image (Id), Doc, Ok);
      if Doc = null then
         Ok := False;
         Doc := Text_Document ("git show " & Git_View_Sha.Image (Id)
                               & " failed");
      end if;
   end Load_Diff;

end Git_View_Source;
