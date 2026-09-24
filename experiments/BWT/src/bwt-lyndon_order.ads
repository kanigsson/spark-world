with BWT.Words;

--  How Lyndon words, ordered as finite words, sit in the periodic order
--  that sorts rotations.

package BWT.Lyndon_Order
  with SPARK_Mode, Ghost
is
   use BWT.Words;

   --  A strictly precedes B in the periodic order.
   function Omega_Less (S : String; A, B : Rotation) return Boolean
   is (not LE (S, B, A, 2 * S'Length))
   with
     Pre =>
       Supported (S) and then Valid (A, S'Length) and then Valid (B, S'Length);

   function Word (F, L : Positive) return Rotation
   is ((F, L, 0));

   --  A Lyndon word precedes every other rotation of itself.
   procedure Lyndon_Least (S : String; F, L, O : Positive)
   with
     Pre  => In_Word (S, F, L) and then Lyndon (S, F, L) and then O < L,
     Post => Omega_Less (S, (F, L, 0), (F, L, O));

   --  Lyndon words keep their lexicographic order when repeated forever.
   procedure Lyndon_Omega (S : String; UF, N, VF, M : Positive)
   with
     Pre  =>
       In_Word (S, UF, N)
       and then In_Word (S, VF, M)
       and then Lyndon (S, UF, N)
       and then Lyndon (S, VF, M)
       and then Lex_Less (S, UF, N, VF, M),
     Post => Omega_Less (S, (UF, N, 0), (VF, M, 0));

   --  A word that precedes each of its other rotations is a Lyndon word.
   procedure Least_Lyndon (S : String; F, L : Positive)
   with
     Pre  =>
       In_Word (S, F, L)
       and then (for all O in 1 .. L - 1 =>
                   Omega_Less (S, (F, L, 0), (F, L, O))),
     Post => Lyndon (S, F, L);

   --  Distinct rotations of a Lyndon word differ somewhere.
   procedure Primitive (S : String; F, L, A, B : Natural)
   with
     Pre  =>
       In_Word (S, F, L)
       and then F >= 1
       and then Lyndon (S, F, L)
       and then A < L
       and then B < L
       and then A /= B,
     Post => not Equal_Prefix (S, (F, L, A), (F, L, B), 2 * S'Length);

   procedure Same_Word_Equal (S : String; G, H, L : Positive)
   with
     Pre  =>
       In_Word (S, G, L) and then In_Word (S, H, L) and then Same (S, G, H, L),
     Post => Equal_Prefix (S, (G, L, 0), (H, L, 0), 2 * S'Length);
end BWT.Lyndon_Order;
