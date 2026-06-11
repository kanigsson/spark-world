with JSON.Numbers;

package body JSON.Walk with SPARK_Mode => On is

   use type JSON.Pull.Event_Kind;
   use type JSON.Pull.State_Type;

   --  Expect one event of exactly the given kind; shared by the Open_*
   --  and Get_Boolean wrappers (the getters with payloads keep their own
   --  bodies, they need the event).
   procedure Expect
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Kind   : in     JSON.Pull.Event_Kind;
      Ev     :    out JSON.Pull.Event;
      Status :    out Step_Status)
   with
     Global => null,
     Pre    => Ready (Input, P)
               and then Kind /= JSON.Pull.Document_End,
     Post   => (if Status = OK
                then Ready (Input, P)
                     and then P.Pos > P.Pos'Old
                     and then Ev.Kind = Kind
                     and then (if Kind in JSON.Pull.Member_Key
                                        | JSON.Pull.String_Value
                                        | JSON.Pull.Number_Value
                               then Ev.First >= Input'First
                                    and then Ev.Last <= Input'Last
                                    and then Ev.First - 1 <= Ev.Last))
   is
      St : JSON.Status_Type;
   begin
      JSON.Pull.Next (Input, P, Ev, St);
      if St /= JSON.OK then
         Status := Bad_JSON;
      elsif Ev.Kind = Kind then
         Status := OK;
      else
         Status := Wrong_Shape;
      end if;
   end Expect;

   -----------------
   -- Open_Object --
   -----------------

   procedure Open_Object
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Status :    out Step_Status)
   is
      Ev : JSON.Pull.Event;
   begin
      Expect (Input, P, JSON.Pull.Object_Start, Ev, Status);
   end Open_Object;

   ----------------
   -- Open_Array --
   ----------------

   procedure Open_Array
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Status :    out Step_Status)
   is
      Ev : JSON.Pull.Event;
   begin
      Expect (Input, P, JSON.Pull.Array_Start, Ev, Status);
   end Open_Array;

   -----------------
   -- Next_Member --
   -----------------

   procedure Next_Member
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Key    :    out Span;
      Done   :    out Boolean;
      Status :    out Step_Status)
   is
      Ev : JSON.Pull.Event;
      St : JSON.Status_Type;
   begin
      Key  := (others => <>);
      Done := False;
      JSON.Pull.Next (Input, P, Ev, St);
      if St /= JSON.OK then
         Status := Bad_JSON;
      elsif Ev.Kind = JSON.Pull.Member_Key then
         Key    := (First => Ev.First, Last => Ev.Last,
                    Escaped => Ev.Escaped);
         Status := OK;
      elsif Ev.Kind = JSON.Pull.Object_End then
         Done   := True;
         Status := OK;
      else
         Status := Wrong_Shape;
      end if;
   end Next_Member;

   -----------------
   -- Find_Member --
   -----------------

   procedure Find_Member
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Name   : in     String;
      Found  :    out Boolean;
      Status :    out Step_Status)
   is
      Pos0 : constant Natural := P.Pos with Ghost;
      Key  : Span;
      Done : Boolean;
   begin
      Found := False;
      loop
         pragma Loop_Invariant (Ready (Input, P));
         pragma Loop_Invariant (P.Pos >= Pos0);
         pragma Loop_Variant (Increases => P.Pos);

         Next_Member (Input, P, Key, Done, Status);
         if Status /= OK or else Done then
            return;   --  not found: the object is consumed, or the walk died
         end if;
         if Matches (Input, Key, Name) then
            Found := True;
            return;   --  the cursor stands before the member's value
         end if;
         Skip_Value (Input, P, Status);
         if Status /= OK then
            return;
         end if;
      end loop;
   end Find_Member;

   ----------------
   -- Skip_Value --
   ----------------

   procedure Skip_Value
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Status :    out Step_Status)
   is
      Base : constant Natural := P.Depth;
      Pos0 : constant Natural := P.Pos with Ghost;
      Ev   : JSON.Pull.Event;
      St   : JSON.Status_Type;
   begin
      JSON.Pull.Next (Input, P, Ev, St);
      if St /= JSON.OK then
         Status := Bad_JSON;
         return;
      end if;

      case Ev.Kind is
         when JSON.Pull.String_Value | JSON.Pull.Number_Value
            | JSON.Pull.Boolean_Value | JSON.Pull.Null_Value =>
            Status := OK;

         when JSON.Pull.Object_Start | JSON.Pull.Array_Start =>
            --  Consume events until the depth falls back to where the
            --  skipped container started. Each successful step advances
            --  the cursor (only Document_End would not, and it cannot be
            --  delivered while a container is open), so the loop
            --  terminates.
            while P.Depth > Base loop
               pragma Loop_Invariant
                 (P.Pos <= Input'Length
                  and then JSON.Pull.Well_Formed (P)
                  and then P.State /= JSON.Pull.Failed
                  and then P.Pos > Pos0);
               pragma Loop_Variant (Increases => P.Pos);

               JSON.Pull.Next (Input, P, Ev, St);
               if St /= JSON.OK then
                  Status := Bad_JSON;
                  return;
               end if;
            end loop;
            Status := OK;

         when JSON.Pull.Member_Key | JSON.Pull.Object_End
            | JSON.Pull.Array_End | JSON.Pull.Document_End =>
            --  Not a value: the caller is lost (or the container just
            --  ended where a value was expected).
            Status := Wrong_Shape;
      end case;
   end Skip_Value;

   ----------------
   -- Get_String --
   ----------------

   procedure Get_String
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Value  :    out Span;
      Status :    out Step_Status)
   is
      Ev : JSON.Pull.Event;
   begin
      Value := (others => <>);
      Expect (Input, P, JSON.Pull.String_Value, Ev, Status);
      if Status = OK then
         Value := (First => Ev.First, Last => Ev.Last,
                   Escaped => Ev.Escaped);
      end if;
   end Get_String;

   -----------------
   -- Get_Integer --
   -----------------

   procedure Get_Integer
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Value  :    out Interfaces.Integer_64;
      Status :    out Step_Status)
   is
      Ev   : JSON.Pull.Event;
      St   : JSON.Status_Type;
      Fits : Boolean;
   begin
      Value := 0;
      JSON.Pull.Next (Input, P, Ev, St);
      if St /= JSON.OK then
         Status := Bad_JSON;
      elsif Ev.Kind = JSON.Pull.Number_Value and then Ev.Is_Integer then
         JSON.Numbers.To_Integer (Input (Ev.First .. Ev.Last), Value, Fits);
         if Fits then
            Status := OK;
         else
            Value  := 0;
            Status := Wrong_Shape;
         end if;
      else
         Status := Wrong_Shape;
      end if;
   end Get_Integer;

   -----------------
   -- Get_Boolean --
   -----------------

   procedure Get_Boolean
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Value  :    out Boolean;
      Status :    out Step_Status)
   is
      Ev : JSON.Pull.Event;
   begin
      Expect (Input, P, JSON.Pull.Boolean_Value, Ev, Status);
      Value := (if Status = OK then Ev.Bool else False);
   end Get_Boolean;

   -------------------------
   -- Next_Element_Object --
   -------------------------

   procedure Next_Element_Object
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Done   :    out Boolean;
      Status :    out Step_Status)
   is
      Ev : JSON.Pull.Event;
      St : JSON.Status_Type;
   begin
      Done := False;
      JSON.Pull.Next (Input, P, Ev, St);
      if St /= JSON.OK then
         Status := Bad_JSON;
      elsif Ev.Kind = JSON.Pull.Object_Start then
         Status := OK;
      elsif Ev.Kind = JSON.Pull.Array_End then
         Done   := True;
         Status := OK;
      else
         Status := Wrong_Shape;
      end if;
   end Next_Element_Object;

   -------------------------
   -- Next_Element_String --
   -------------------------

   procedure Next_Element_String
     (Input  : in     String;
      P      : in out JSON.Pull.Parser;
      Value  :    out Span;
      Done   :    out Boolean;
      Status :    out Step_Status)
   is
      Ev : JSON.Pull.Event;
      St : JSON.Status_Type;
   begin
      Value := (others => <>);
      Done  := False;
      JSON.Pull.Next (Input, P, Ev, St);
      if St /= JSON.OK then
         Status := Bad_JSON;
      elsif Ev.Kind = JSON.Pull.String_Value then
         Value  := (First => Ev.First, Last => Ev.Last,
                    Escaped => Ev.Escaped);
         Status := OK;
      elsif Ev.Kind = JSON.Pull.Array_End then
         Done   := True;
         Status := OK;
      else
         Status := Wrong_Shape;
      end if;
   end Next_Element_String;

end JSON.Walk;
