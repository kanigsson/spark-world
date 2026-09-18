--  What the two timing harnesses here have in common: both measure the same
--  call, Git_View_Repository.Load, and differ only in the view they set up
--  before it. They had a character-for-character identical Timed of their own.

with Git_View_Model;
with Git_View_Repository;

package Git_View_Bench is

   procedure Timed
     (Name  : String;
      Runs  : Positive;
      View  : in out Git_View_Model.View_State;
      Frame : in out Git_View_Repository.Frame);

end Git_View_Bench;
