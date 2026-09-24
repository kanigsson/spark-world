package BWT
  with SPARK_Mode
is
   --  Reference implementation: byte strings, normalized to a first index of 1.
   --  The bound keeps arithmetic small; no byte is reserved as a sentinel.
   Max_Length : constant := 1_024;

   function Supported (S : String) return Boolean
   is (S'First = 1 and then S'Length <= Max_Length);

   type Classical_Result (Length : Natural) is record
      Last    : String (1 .. Length);
      Primary : Natural;
   end record;

   --  Mathematical LF orbit; shared by the decoder contract and roundtrip
   --  proof. It is ghost code and does not participate in decoding.
   function Walk
     (Last : String; Primary : Positive; Steps : Natural) return Positive
   with
     Ghost,
     Global => null,
     Pre    =>
       Supported (Last)
       and then Primary in Last'Range
       and then Steps <= Last'Length,
     Post   => Walk'Result in Last'Range;

   function Classical_Encode (S : String) return Classical_Result
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Classical_Encode'Result.Length = S'Length
       and then (if S'Length = 0
                 then Classical_Encode'Result.Primary = 0
                 else Classical_Encode'Result.Primary in 1 .. S'Length)
       and then (for all K in 0 .. S'Length - 1 =>
                   Classical_Encode'Result.Last
                     (Walk
                        (Classical_Encode'Result.Last,
                         Classical_Encode'Result.Primary,
                         K))
                   = S (S'Length - K));

   --  Decoding is defined for every in-range primary index. The roundtrip law
   --  applies to pairs produced by Classical_Encode, not arbitrary pairs.
   function Classical_Decode (Last : String; Primary : Natural) return String
   with
     Global => null,
     Pre    =>
       Supported (Last)
       and then (if Last'Length = 0
                 then Primary = 0
                 else Primary in 1 .. Last'Length),
     Post   =>
       Supported (Classical_Decode'Result)
       and then Classical_Decode'Result'Length = Last'Length
       and then (for all K in 0 .. Last'Length - 1 =>
                   Classical_Decode'Result (Last'Length - K)
                   = Last (Walk (Last, Primary, K)));

   function Bijective_Encode (S : String) return String
   with
     Global => null,
     Pre    => Supported (S),
     Post   =>
       Supported (Bijective_Encode'Result)
       and then Bijective_Encode'Result'Length = S'Length;

   function Bijective_Decode (Last : String) return String
   with
     Global => null,
     Pre    => Supported (Last),
     Post   =>
       Supported (Bijective_Decode'Result)
       and then Bijective_Decode'Result'Length = Last'Length;
private
   --  The bijective inverse laws are proved where the implementation is
   --  visible; BWT.Theorems states them against the public functions.

   procedure Prove_Bijective_Round_Trip (S : String)
   with
     Ghost,
     Global => null,
     Pre    => Supported (S),
     Post   => Bijective_Decode (Bijective_Encode (S)) = S;

   procedure Prove_Bijective_Onto (Last : String)
   with
     Ghost,
     Global => null,
     Pre    => Supported (Last),
     Post   => Bijective_Encode (Bijective_Decode (Last)) = Last;
end BWT;
