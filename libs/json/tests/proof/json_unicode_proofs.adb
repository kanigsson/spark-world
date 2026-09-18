with JSON.Strings;

package body JSON_Unicode_Proofs
  with SPARK_Mode => On
is

   use type JSON.Status_Type;
   use type JSON.Walk.Step_Status;

   procedure Decode_Client
     (Input      : in String;
      Output     : in out String;
      Length     : out Natural;
      Codepoints : out Natural;
      Status     : out JSON.Status_Type) is
   begin
      JSON.Strings.Decode (Input, Output, Length, Status);
      if Status = JSON.OK then
         Codepoints :=
           Unicode_Text.UTF_8.Code_Point_Length
             (JSON.Strings.Active_Prefix (Output, Length));
      else
         Codepoints := 0;
      end if;
   end Decode_Client;

   procedure Empty_Decode_Client
     (Output     : in out String;
      Codepoints : out Natural;
      Status     : out JSON.Status_Type)
   is
      Length : Natural;
   begin
      JSON.Strings.Decode ("", Output, Length, Status);
      if Status = JSON.OK then
         Codepoints :=
           Unicode_Text.UTF_8.Code_Point_Length
             (JSON.Strings.Active_Prefix (Output, Length));
      else
         Codepoints := 0;
      end if;
   end Empty_Decode_Client;

   procedure Pull_Payload_Client
     (Input      : in String;
      P          : in out JSON.Pull.Parser;
      Codepoints : out Natural;
      Status     : out JSON.Status_Type)
   is
      Ev : JSON.Pull.Event;
   begin
      JSON.Pull.Next (Input, P, Ev, Status);
      if Status = JSON.OK
        and then Ev.Kind in JSON.Pull.Member_Key | JSON.Pull.String_Value
        and then not Ev.Escaped
      then
         Codepoints :=
           Unicode_Text.UTF_8.Code_Point_Length
             (JSON.Payload (Input, Ev.First, Ev.Last));
      else
         Codepoints := 0;
      end if;
   end Pull_Payload_Client;

   procedure Walk_Find_Client
     (Input  : in String;
      P      : in out JSON.Pull.Parser;
      Name   : in String;
      Found  : out Boolean;
      Status : out JSON.Walk.Step_Status)
   is
      Start : constant Natural := P.Pos
      with Ghost;
      Key   : JSON.Walk.Span;
      Done  : Boolean;
   begin
      Found := False;
      loop
         pragma Loop_Invariant (JSON.Walk.Ready (Input, P));
         pragma Loop_Invariant (P.Pos >= Start);
         pragma Loop_Variant (Increases => P.Pos);

         JSON.Walk.Next_Member (Input, P, Key, Done, Status);
         if Status /= JSON.Walk.OK or else Done then
            return;
         end if;
         if JSON.Walk.Matches (Input, Key, Name) then
            Found := True;
            return;
         end if;
         JSON.Walk.Skip_Value (Input, P, Status);
         if Status /= JSON.Walk.OK then
            return;
         end if;
      end loop;
   end Walk_Find_Client;

end JSON_Unicode_Proofs;
