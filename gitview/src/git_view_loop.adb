with Tui.Surface; use Tui.Surface;
with Tui.Surface.Diff;
with Tui.Input;
with Tui.Term.Mode;
with Tui.Term.Input;
with Tui.Term.Output;
with Tui.Term.Signals;
with Tui.Term; use Tui.Term;
with Git_View_Explorer;

package body Git_View_Loop with SPARK_Mode => Off is
   procedure Run (Mouse : Boolean) is
      Term : Tui.Term.Mode.Session;
      Decoder : Tui.Input.Decoder;
   begin
      Tui.Term.Signals.Install;
      if not Term.Active then Git_View_Explorer.Stop; return; end if;
      if Mouse then Tui.Term.Mode.Enable_Mouse (Term); end if;
      Sizes : loop
         exit when Tui.Term.Signals.Quit_Requested;
         declare
            Size : constant Tui.Term.Size := Tui.Term.Mode.Get_Size;
         begin
            exit when not Is_Known (Size);
            declare
               Rows : constant Row_Count := Row_Count (Integer'Min (Size.Rows, Max_Extent));
               Cols : constant Col_Count := Col_Count (Integer'Min (Size.Cols, Max_Extent));
               Current : Surface := Blank (Rows, Cols);
               Previous : Surface := Blank (Rows, Cols);
               Changes : Tui.Surface.Diff.Change_Array (1 .. Tui.Surface.Diff.Cell_Count (Current));
               Count : Natural;
               Event : Tui.Input.Key_Event;
               Status : Tui.Term.Input.Read_Status;
               Dirty, Quit, Ready : Boolean;
            begin
               Git_View_Explorer.Paint (Current);
               Tui.Term.Output.New_Frame;
               Tui.Term.Output.Blit (Current);
               Previous := Current;
               loop
                  exit Sizes when Tui.Term.Signals.Quit_Requested;
                  exit when Tui.Term.Signals.Resize_Pending;
                  --  The wait also bounds how long a finished frame sits in
                  --  the mailbox before the poll below picks it up, so it is
                  --  short enough not to be seen.
                  Tui.Term.Input.Next (Decoder, Event, Status, Timeout => 20);
                  Dirty := False;
                  case Status is
                     when Tui.Term.Input.End_Of_Input => exit Sizes;
                     when Tui.Term.Input.Got_Event =>
                        Git_View_Explorer.On_Key (Event, Dirty, Quit);
                        exit Sizes when Quit;
                     when Tui.Term.Input.Timed_Out => null;
                  end case;
                  Git_View_Explorer.Tick (Ready);
                  if Dirty or else Ready then
                     Clear (Current);
                     Git_View_Explorer.Paint (Current);
                     Tui.Surface.Diff.Compute (Previous, Current, Changes, Count);
                     Tui.Term.Output.Apply (Changes, Count);
                     Previous := Current;
                  end if;
               end loop;
            end;
         end;
      end loop Sizes;
      Git_View_Explorer.Stop;
   exception
      when others => Git_View_Explorer.Stop; raise;
   end Run;
end Git_View_Loop;
