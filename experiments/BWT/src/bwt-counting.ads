--  Ghost accounting for the inverse's visited set.
package BWT.Counting with SPARK_Mode is
   type Flags is array (Positive range <>) of Boolean;

   function Unseen (Seen : Flags; Through : Natural) return Natural
   with Ghost,
        Pre => Seen'First = 1 and then Seen'Length <= Max_Length
          and then Through <= Seen'Length,
        Post => Unseen'Result <= Through
          and then ((Unseen'Result = 0) =
            (for all I in 1 .. Through => Seen (I))),
        Subprogram_Variant => (Decreases => Through);

   procedure Marked (Before, After : Flags; Position : Positive)
   with Ghost,
        Pre => Before'First = 1 and then After'First = 1
          and then Before'Length <= Max_Length
          and then Before'Length = After'Length
          and then Position in Before'Range
          and then not Before (Position) and then After (Position)
          and then (for all I in Before'Range =>
            (if I /= Position then Before (I) = After (I))),
        Post => Unseen (Before, Before'Length) =
          Unseen (After, After'Length) + 1;

   procedure All_Clear (Seen : Flags)
   with Ghost,
        Pre => Seen'First = 1 and then Seen'Length <= Max_Length
          and then (for all B of Seen => not B),
        Post => Unseen (Seen, Seen'Length) = Seen'Length;
end BWT.Counting;
