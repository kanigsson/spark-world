--  Root namespace for the TUI ecosystem.
--
--  This package is almost empty. It exists so that every layer of the
--  ecosystem lives under a single, stable `Tui.*` prefix without any of them
--  defining (and colliding over) its own copy of the root. Keeping it Pure
--  means it constrains nothing about its children.
--
--  A child package needs its parent as a compilation unit, so someone must own
--  this one; when the layers were separate crates, each carried a throwaway
--  copy and the first build closure to combine two of them saw duplicate
--  `tui.ads` files. Shared geometry/types may move here later, when a second
--  consumer needs them without their current home — not before.
--
--  That moment has arrived for the two scalar types below. `Tui.Width` and
--  `Tui.Input` each declared their own identical `Byte` / `Code_Point`; a third
--  consumer (`Tui.Strings`) makes the duplication a liability, so the canonical
--  declarations live here now. The layers can drop their local
--  copies in favour of these (a non-breaking change: a local subtype of the
--  same name simply shadows this one until removed).

package Tui
  with Pure, SPARK_Mode => On
is

   --  A single octet — the unit of any byte buffer, UTF-8 stream, or wire read.
   type Byte is mod 2**8;

   --  A Unicode scalar value. The surrogate range 16#D800# .. 16#DFFF# is
   --  representable here but is not a valid scalar value; encoders and decoders
   --  exclude it. (Kept a subtype of Natural so it interoperates with plain
   --  arithmetic and with 'Pos values without conversions.)
   subtype Code_Point is Natural range 0 .. 16#10_FFFF#;

end Tui;
