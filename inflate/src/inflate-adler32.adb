package body Inflate.Adler32 with SPARK_Mode => On is

   pragma Assertion_Policy
     (Pre            => Ignore,
      Post           => Ignore,
      Ghost          => Ignore,
      Assert         => Ignore,
      Loop_Invariant => Ignore,
      Loop_Variant   => Ignore);

   -------------------
   -- Initial_State --
   -------------------

   function Initial_State (Adler : Word32) return State is
     (A => Component ((Adler and 16#FFFF#) mod Base),
      B => Component (Shift_Right (Adler, 16) mod Base));

   ---------------------
   -- Model_Byte_Step --
   ---------------------

   function Model_Byte_Step (S : State; Value : Byte) return State is
      Next_A : constant Component :=
        S.A + Component (Value);
   begin
      return
        (A => Next_A,
         B => S.B + Next_A);
   end Model_Byte_Step;

   ----------
   -- Pack --
   ----------

   function Pack (S : State) return Word32 is
     (Shift_Left (Word32 (S.B), 16) or Word32 (S.A));

   ----------
   -- Fold --
   ----------

   function Fold
     (S : State; Data : Byte_Array; From : Positive; To : Natural)
      return State
   is
     (if From > To
      then S
      else Fold
        (Model_Byte_Step (S, Data (From)), Data, From + 1, To));

   function Update (Adler : Word32; Data : Byte_Array) return Word32 is
      Initial : constant State := Initial_State (Adler);
      Current : State := Initial;
   begin
      for I in Data'Range loop
         pragma Loop_Invariant
           (Fold (Initial, Data, Data'First, Data'Last) =
              Fold (Current, Data, I, Data'Last));
         Current := Model_Byte_Step (Current, Data (I));
      end loop;
      return Pack (Current);
   end Update;

end Inflate.Adler32;
