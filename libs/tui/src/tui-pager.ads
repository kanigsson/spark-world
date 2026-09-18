--  Tui.Pager — the embeddable pager engine.
--
--  This parent package holds the types shared by the engine's parts. The engine
--  is a COMPONENT, not a program: it owns no terminal and runs no loop. It views
--  already-materialised content (a Tui.Text line index over a byte buffer the
--  host holds) and renders into a Tui.Surface that the host composites and
--  displays. A host drives it; the standalone pager and a git viewer are two
--  such hosts.
--
--  Scope of the proven core (this crate): viewport math (Tui.Pager.View) and
--  rendering content into a surface (Tui.Pager.Render). Both are pure SPARK.
--
--  Deliberately NOT here yet (they are the I/O / orchestration boundary, and
--  belong in a host or a later non-SPARK layer):
--    * an abstract Source interface for lazily-generated content (a file read
--      on demand, `git log` output) — that is where the OS lives;
--    * the Engine instance with its key-command map and host callbacks.

with Tui.Text;

package Tui.Pager
  with SPARK_Mode => On
is

   --  Content line numbering is owned by Tui.Text; reuse it so the engine and
   --  the line index speak the same vocabulary.
   subtype Line_Number is Tui.Text.Line_Number;   --  1 .. N, a content line
   subtype Line_Total is Tui.Text.Line_Total;    --  0 .. N, a line count

   --  Screen geometry (rows, columns, scroll offsets). Generous cap that keeps
   --  all layout arithmetic well inside 32-bit Integer.
   Max_Dim : constant := 100_000;
   subtype Dimension is Natural range 0 .. Max_Dim;

   --  Tab stop width used when expanding tabs during layout.
   subtype Tab_Width is Positive range 1 .. 256;
   Default_Tab_Width : constant Tab_Width := 8;

end Tui.Pager;
