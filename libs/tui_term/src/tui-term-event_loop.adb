with Tui.Surface;            use Tui.Surface;
with Tui.Surface.Diff;
with Tui.Term.Mode;
with Tui.Term.Output;
with Tui.Term.Input;
with Tui.Term.Signals;

package body Tui.Term.Event_Loop is

   --  Heartbeat for the read wait. The signal handlers only flip flags (and,
   --  under GNAT's model, signals are fielded by a separate task rather than
   --  interrupting our poll), so the loop must wake periodically to notice a
   --  resize or quit. 100 ms is well under human-perceptible lag.
   Tick_Ms : constant := 100;

   procedure Run
     (Paint  : Painter;
      On_Key : Key_Handler;
      Mouse  : Boolean := False)
   is
      Term : Tui.Term.Mode.Session;          --  enters raw/alt mode now (RAII)
      Dec  : Tui.Input.Decoder;
   begin
      Tui.Term.Signals.Install;

      --  Not a terminal (piped/redirected): nothing to drive. Term.Finalize is
      --  a no-op in this case.
      if not Term.Active then
         return;
      end if;

      if Mouse then
         Tui.Term.Mode.Enable_Mouse (Term);
      end if;

      --  Each pass of this loop owns one terminal size. A resize exits the
      --  inner loop and re-enters here to rebuild buffers at the new geometry.
      Size_Epoch :
      loop
         exit Size_Epoch when Tui.Term.Signals.Quit_Requested;

         declare
            Sz : constant Size := Tui.Term.Mode.Get_Size;
         begin
            exit Size_Epoch when not Is_Known (Sz);

            declare
               Rows : constant Row_Count :=
                 Row_Count (Integer'Min (Sz.Rows, Max_Extent));
               Cols : constant Col_Count :=
                 Col_Count (Integer'Min (Sz.Cols, Max_Extent));

               Prev : Tui.Surface.Surface := Blank (Rows, Cols);
               Cur  : Tui.Surface.Surface := Blank (Rows, Cols);

               Buf : Tui.Surface.Diff.Change_Array
                       (1 .. Tui.Surface.Diff.Cell_Count (Cur));
               Cnt : Natural;

               Ev    : Tui.Input.Key_Event;
               St    : Tui.Term.Input.Read_Status;
               Dirty : Boolean;
               Quit  : Boolean;
            begin
               --  Fresh full frame for this size (clears any stale content).
               Paint (Cur);
               Tui.Term.Output.New_Frame;
               Tui.Term.Output.Blit (Cur);
               Prev := Cur;

               Read_Keys :
               loop
                  exit Size_Epoch when Tui.Term.Signals.Quit_Requested;
                  exit Read_Keys   when Tui.Term.Signals.Resize_Pending;

                  Tui.Term.Input.Next (Dec, Ev, St, Timeout => Tick_Ms);

                  case St is
                     when Tui.Term.Input.Got_Event =>
                        On_Key (Ev, Dirty, Quit);
                        exit Size_Epoch when Quit;
                        if Dirty then
                           Clear (Cur);          --  blank, then repaint
                           Paint (Cur);
                           Tui.Surface.Diff.Compute (Prev, Cur, Buf, Cnt);
                           Tui.Term.Output.Apply (Buf, Cnt);
                           Prev := Cur;
                        end if;

                     when Tui.Term.Input.Timed_Out =>
                        null;   --  tick: fall through to re-check signals

                     when Tui.Term.Input.End_Of_Input =>
                        exit Size_Epoch;
                  end case;
               end loop Read_Keys;
            end;
         end;
      end loop Size_Epoch;

      --  Falling off here finalizes Term, which restores the terminal.
   end Run;

end Tui.Term.Event_Loop;
