--  Tui.App_Kit — shared building blocks for hosts of the pager engine.
--
--  An app that wires the engine to the terminal driver grows the same
--  small proved pieces every time: an editor that collects the search
--  pattern while the user types it, and a bounded buffer that assembles
--  the status-line text. The standalone pager built them first; git_view
--  carried copies; by the ecosystem's own rule (extract on the second
--  consumer, never a third copy) they live here now.
--
--  This parent package is intentionally empty: the kit is its children.
--  Everything is pure SPARK — no I/O, no OS, no heap. The host still owns
--  the surface, the loop and the terminal; these packages only hold and
--  build bytes for it.

package Tui.App_Kit with Pure, SPARK_Mode => On is
end Tui.App_Kit;
