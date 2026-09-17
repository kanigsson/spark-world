# Tui.App_Kit

Shared building blocks for app hosts of the `Tui.Pager` engine — the
search-pattern editor and the bounded status-line buffer. Written in SPARK and
proved free of run-time errors. See **Proof status** for what the proofs do
and don't cover.

## Why it exists

Every app that wires the engine to the terminal driver grows the same small
proved pieces: an editor that collects the search pattern while the user types
it, and a fixed-size buffer that assembles the status-line text. The
standalone pager built them first; `git_view` carried copies; by the
ecosystem's own rule — extract on the second consumer, a third copy is
forbidden — they live here now, one layer above the engine and below the apps.

## What it is

| Package                    | Contents |
|----------------------------|----------|
| `Tui.App_Kit.Search_Input` | the pattern `Editor`: bounded UTF-8 byte string grown by `Append` (in-SPARK UTF-8 encoder), shrunk by whole code points on `Backspace` |
| `Tui.App_Kit.Status`       | the status `Line`: bounded text buffer with `Put`/`Put_Char`/`Put_Nat`/`Put_Byte` building blocks and the shared search-prompt formatter |

The split between kit and app is mechanism versus policy. The editor and the
buffer (and the one text every consumer formats identically, the `/`/`?`
search prompt) are mechanism and live here. What the transient notes say and
how the position read-out is laid out are app policy: each app keeps its own
note enumeration and position formatters, assembled from the kit's `Put`
primitives.

The kit owns no surface and runs no loop. The editor's bytes go to the
engine's pattern installer and to the prompt formatter; the host paints
`Image (L)` onto its status row, truncating to the real column count.

Bounds, both inherited from the consumers' world: the pattern caps at the
engine's `Max_Pattern` (no point holding bytes the engine would drop), and
the status line caps at 4096 bytes (a surface row's maximum extent — text
past it is never visible). Every append truncates instead of overflowing; a
code point that would not fit is dropped whole, never half-written.

## Proof status

```
gnatprove -P tui.gpr -u tui-app_kit-status.adb   ->   Success: all checks proved
```

The most recent recorded run proved **577 checks** (the closure including the
withed engine and foundation specs; machine-readable verdict in
`obj/gnatprove/result.json`: `overall = all_proved`, trust summary clean).
What is proved: no run-time errors anywhere, termination of the backspace
scan, and the boundary contracts — `Bytes` returns exactly `Length` bytes
1-based, `Image` likewise, appends never shrink the editor, backspace never
grows it.

What is *not* proved: that the UTF-8 encoding is the right bit pattern, or
that a formatted line says what it should — those are pinned by the
behavioural tests.

## Where this lives

```
src/tui-app_kit.ads
src/tui-app_kit-search_input.ads
src/tui-app_kit-search_input.adb
src/tui-app_kit-status.ads
src/tui-app_kit-status.adb
tests/src/test_app_kit.adb
```

The whole library builds, tests and proves as one; see the crate
[README](../README.md) for the commands. To prove this layer alone:

```sh
gnatprove -P tui.gpr -u tui-app_kit.ads
```
