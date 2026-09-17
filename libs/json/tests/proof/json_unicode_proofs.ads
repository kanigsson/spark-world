with JSON;
with JSON.Pull;
with JSON.Walk;
with Unicode_Text.UTF_8;

package JSON_Unicode_Proofs with SPARK_Mode => On is

   procedure Decode_Client
     (Input      : in     String;
      Output     : in out String;
      Length     :    out Natural;
      Codepoints :    out Natural;
      Status     :    out JSON.Status_Type)
   with
     Global => null,
     Pre    =>
       Input'Last < Positive'Last
       and then Output'Last < Positive'Last
       and then Output'Length >= Input'Length;

   procedure Empty_Decode_Client
     (Output     : in out String;
      Codepoints :    out Natural;
      Status     :    out JSON.Status_Type)
   with
     Global => null,
     Pre    => Output'Last < Positive'Last;

   procedure Pull_Payload_Client
     (Input      : in     String;
      P          : in out JSON.Pull.Parser;
      Codepoints :    out Natural;
      Status     :    out JSON.Status_Type)
   with
     Global => null,
     Pre    =>
       Input'Last < Positive'Last
       and then P.Pos <= Input'Length
       and then JSON.Pull.Well_Formed (P)
       and then P.State not in JSON.Pull.Finished | JSON.Pull.Failed;

   procedure Walk_Find_Client
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Name   : in     String;
      Found  :    out Boolean;
      Status :    out JSON.Walk.Step_Status)
   with
     Global => null,
     Pre    =>
       JSON.Walk.Ready (Input, P)
       and then Unicode_Text.UTF_8.Is_Valid_UTF_8 (Name);

end JSON_Unicode_Proofs;
