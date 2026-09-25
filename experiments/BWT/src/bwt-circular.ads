--  Canonical rotations of circular sequences. A circular sequence is known
--  only up to rotation. Its least rotation is a key that does not depend on
--  where the sequence was cut. It serves to compare or de-duplicate plasmids,
--  ring structures, necklaces and similar data.

package BWT.Circular
  with SPARK_Mode
is
   --  S read from offset O, wrapping around once.
   function Rotated (S : String; O : Natural) return Rotation
   is ((1, S'Length, O))
   with
     Ghost,
     Pre  => Supported (S) and then O < S'Length,
     Post => Valid (Rotated'Result, S'Length);

   --  O starts a least rotation of S, and no earlier offset starts one.
   --  Rotations of one length-N word are decided by N letters.
   function Is_Least_Rotation (S : String; O : Natural) return Boolean
   is (O < S'Length
       and then (for all Q in 0 .. S'Length - 1 =>
                   LE (S, Rotated (S, O), Rotated (S, Q), S'Length))
       and then (for all Q in 0 .. O - 1 =>
                   not LE (S, Rotated (S, Q), Rotated (S, O), S'Length)))
   with Ghost, Pre => Supported (S);

   --  Linear time and constant space: two candidate offsets compare their
   --  rotations letter by letter, and each mismatch rules out as many
   --  offsets as letters were compared.
   function Least_Rotation (S : String) return Natural
   with
     Global => null,
     Pre    => Supported (S) and then S'Length > 0,
     Post   => Is_Least_Rotation (S, Least_Rotation'Result);

   --  The least rotation itself.
   function Canonical (S : String) return String
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Canonical'Result'First = 1
       and then Canonical'Result'Length = S'Length
       and then (if S'Length > 0
                 then
                   (for all I in Canonical'Result'Range =>
                      Canonical'Result (I)
                      = Letter (S, Rotated (S, Least_Rotation (S)), I - 1)));
end BWT.Circular;
