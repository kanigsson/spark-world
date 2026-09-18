package Git_Changes.Core.Hunks
  with SPARK_Mode
is

   type Line_Range is record
      First : Natural := 0;
      Count : Natural := 0;
   end record
   with
     Dynamic_Predicate => (if Line_Range.Count > 0 then Line_Range.First > 0);

   type Hunk is record
      Old_Lines : Line_Range := (First => 1, Count => 1);
      New_Lines : Line_Range := (First => 1, Count => 1);
   end record
   with
     Dynamic_Predicate =>
       Hunk.Old_Lines.Count > 0 or else Hunk.New_Lines.Count > 0;

   type Hunk_Result is (Hunk_Parsed, No_More_Hunks, Malformed_Hunk);

   procedure Parse_Next
     (Input  : String;
      Cursor : in out Positive;
      Item   : out Hunk;
      Result : out Hunk_Result)
   with
     Pre  =>
       Input'First = 1
       and then Input'Last < Positive'Last
       and then Cursor <= Input'Last + 1,
     Post => Cursor >= Cursor'Old;

end Git_Changes.Core.Hunks;
