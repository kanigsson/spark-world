with Unicode_Text.UTF_8;

--  JSON.Strings — decoding a string payload (the slice a Pull event hands
--  back, i.e. the content between the quotes) into its UTF-8 text: escape
--  sequences are resolved, including \uXXXX and surrogate pairs.
--
--  The decoded form is never longer than the raw payload (every escape
--  shrinks: \n is 2 bytes in and 1 out, \uXXXX is 6 in and at most 3 out,
--  a surrogate pair is 12 in and 4 out), so an output buffer the size of
--  the input always suffices — that is the precondition, and the bound is
--  the postcondition.
--
--  The decoder stands alone: it revalidates escapes and UTF-8, so it is
--  safe on slices that did not come from a successful Pull event. Input
--  that a Pull event delivered with Escaped = False needs no decoding at
--  all — the payload slice is already the text.

package JSON.Strings
  with SPARK_Mode => On
is

   --  The initialized active prefix of a caller-owned buffer. The empty
   --  prefix is represented without forming a fragile First - 1 slice.
   function Active_Prefix (Buffer : String; Length : Natural) return String
   is (if Length = 0
       then ""
       else Buffer (Buffer'First .. Buffer'First + Length - 1))
   with Pre => Buffer'Last < Positive'Last and then Length <= Buffer'Length;

   --  Decode Input into Output (Output'First .. Output'First + Length - 1).
   --  Output is a scratch buffer: bytes beyond Length may have been
   --  written, and on a non-OK status Length is 0. It is `in out` rather
   --  than `out` so that callers need not prove initialization of a buffer
   --  that is data-flow-wise write-before-read.
   procedure Decode
     (Input  : in String;
      Output : in out String;
      Length : out Natural;
      Status : out Status_Type)
   with
     Global => null,
     Pre    =>
       Input'Last < Positive'Last
       and then Output'Last < Positive'Last
       and then Output'Length >= Input'Length,
     Post   =>
       Length <= Input'Length
       and then (if Status = OK
                 then
                   Unicode_Text.UTF_8.Is_Valid_UTF_8
                     (Active_Prefix (Output, Length))
                 else Length = 0);

   --  Compare the logical text represented by a JSON string payload with
   --  an already-valid UTF-8 string. Input is treated as hostile and a
   --  malformed payload simply compares unequal. The comparison streams
   --  scalar by scalar and allocates no temporary decoded string.
   function Decoded_Equals (Input, Expected : String) return Boolean
   with
     Pre =>
       Input'Last < Positive'Last
       and then Unicode_Text.UTF_8.Is_Valid_UTF_8 (Expected);

end JSON.Strings;
