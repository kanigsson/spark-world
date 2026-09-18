--  Inflate.LZ77 — the byte-copy semantics of a DEFLATE back-reference.
--
--  This package isolates milestone M4 from Huffman decoding and block
--  framing.  Copy_Match is the operation used by the shipping decoder after
--  it has validated a (length, distance) pair.  Its functional postcondition
--  covers non-overlapping copies and the forward-copy overlap that implements
--  repetition when Distance < Length.

with Inflate.Model;

package Inflate.LZ77
  with SPARK_Mode => On
is

   --  Copies_Match quantifies over the whole produced prefix.  It is a proof
   --  contract, not work the decoder should repeat after every match in an
   --  assertion-enabled executable.  GNATprove verifies Ignore-policy
   --  contracts normally; focused tests evaluate the model explicitly.
   pragma Assertion_Policy (Post => Ignore);

   procedure Copy_Match
     (Output   : in out Byte_Array;
      Produced : in out Natural;
      Length   : in Positive;
      Distance : in Positive)
   with
     Global => null,
     Pre    =>
       Produced <= Output'Length
       and then Distance <= Produced
       and then Length <= Output'Length - Produced,
     Post   =>
       Produced = Produced'Old + Length
       and then Model.Copies_Match
                  (Output'Old, Output, Produced'Old, Length, Distance);

end Inflate.LZ77;
