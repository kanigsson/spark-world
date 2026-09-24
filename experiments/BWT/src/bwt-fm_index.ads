with BWT.Search;

--  An FM-index over a last column: the column, how many letters sort below
--  each letter, and the letter counts at every Block-th row. A rank then
--  scans less than one block, so a count costs O(|P| * Block), not
--  O(|P| * N). Count equals Search.Count, so its theorems apply unchanged.

package BWT.FM_Index
  with SPARK_Mode
is
   Block : constant := 256;

   type Counts is array (Character) of Natural;
   type Checkpoints is array (Natural range <>) of Counts;

   type Index
     (Length : Natural;
      Blocks : Natural)
   is record
      Last  : String (1 .. Length);
      Below : Counts;
      Marks : Checkpoints (0 .. Blocks);
   end record;

   --  Rows of Last (1 .. Through) ending in C, and ending below C.
   function Occ
     (Last : String; C : Character; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else Occ (Last, C, Through - 1) + (if Last (Through) = C then 1 else 0))
   with
     Ghost,
     Pre                => Supported (Last) and then Through <= Last'Length,
     Post               => Occ'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   function Below_Count
     (Last : String; C : Character; Through : Natural) return Natural
   is (if Through = 0
       then 0
       else
         Below_Count (Last, C, Through - 1)
         + (if Last (Through) < C then 1 else 0))
   with
     Ghost,
     Pre                => Supported (Last) and then Through <= Last'Length,
     Post               => Below_Count'Result <= Through,
     Subprogram_Variant => (Decreases => Through);

   function Valid (Idx : Index) return Boolean
   is (Supported (Idx.Last)
       and then Idx.Blocks = Idx.Length / Block
       and then (for all C in Character =>
                   Idx.Below (C) = Below_Count (Idx.Last, C, Idx.Length))
       and then (for all K in 0 .. Idx.Blocks =>
                   (for all C in Character =>
                      Idx.Marks (K) (C) = Occ (Idx.Last, C, K * Block))))
   with Ghost;

   function Build (Last : String) return Index
   with
     Pre  => Supported (Last),
     Post => Valid (Build'Result) and then Build'Result.Last = Last;

   --  Rows up to T ending in C.
   function Rank (Idx : Index; C : Character; T : Natural) return Natural
   with
     Pre  => Valid (Idx) and then T <= Idx.Length,
     Post => Rank'Result = Occ (Idx.Last, C, T);

   function Count (Idx : Index; P : String) return Natural
   with
     Pre  =>
       Valid (Idx) and then P'First = 1 and then P'Length <= 2 * Max_Length,
     Post => Count'Result = Search.Count (Idx.Last, P);
end BWT.FM_Index;
