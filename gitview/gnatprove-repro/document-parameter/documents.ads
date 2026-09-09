package Documents with SPARK_Mode => On is
   type Index (Capacity : Natural) is private;
   function Scanned (I : Index) return Natural;
   type Document (Size, Capacity : Natural) is record
      Bytes : String (1 .. Size);
      Idx : Index (Capacity);
   end record
     with Dynamic_Predicate => Scanned (Document.Idx) <= Document.Size;
   type Doc_Ref is access Document;
private
   type Positions is array (Positive range <>) of Natural;
   type Index (Capacity : Natural) is record
      Spans : Positions (1 .. Capacity);
      Count : Natural := 0;
   end record
     with Dynamic_Predicate => Index.Count <= Index.Capacity
       and then (for all I in 1 .. Index.Count => Index.Spans (I) <= Index.Count);
   function Scanned (I : Index) return Natural is (I.Count);
end Documents;
