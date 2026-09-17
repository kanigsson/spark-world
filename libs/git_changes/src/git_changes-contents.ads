with Ada.Strings.Unbounded;

package Git_Changes.Contents is
   procedure Load
     (Changes : Change_Set;
      File    : Positive;
      Which   : Side;
      Content : out Ada.Strings.Unbounded.Unbounded_String;
      Error   : out Error_Info)
     with Pre => File <= File_Count (Changes)
       and then Content_Available (Changes, File, Which);
end Git_Changes.Contents;
