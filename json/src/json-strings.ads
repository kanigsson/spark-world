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

package JSON.Strings with SPARK_Mode => On is

   --  Decode Input into Output (Output'First .. Output'First + Length - 1).
   --  Output is a scratch buffer: bytes beyond Length may have been
   --  written, and on a non-OK status Length is 0. It is `in out` rather
   --  than `out` so that callers need not prove initialization of a buffer
   --  that is data-flow-wise write-before-read.
   procedure Decode
     (Input  : in     String;
      Output : in out String;
      Length :    out Natural;
      Status :    out Status_Type)
   with
     Global => null,
     Pre    => Input'Last < Positive'Last
               and then Output'Last < Positive'Last
               and then Output'Length >= Input'Length,
     Post   => Length <= Input'Length;

end JSON.Strings;
