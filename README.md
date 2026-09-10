<div align="center">

# Octopus

<img src="assets/octopus-hero.svg" alt="Octopus" width="720">

Hot corners for your whole screen. Hover the cursor in any of 8 zones — Octopus fires your action.

</div>

## Features

- **8 trigger zones** — four corners plus top, bottom, left-middle, and right-middle edges
- **Open anything** — drop an app, file, folder, or script onto a zone in Settings and it launches when the zone triggers
- **7 system actions** — Mission Control, Apps, Show Desktop, Start Screen Saver, Lock Screen, Put Display to Sleep, and Control Center
- **Dwell trigger** — optional dwell delay (off by default); with dwell off, actions fire instantly on cursor entry
- **Ghosting** — configurable re-trigger cooldown per zone, so an action doesn't repeat while the cursor rests in a zone
- **Trigger effect** — visual feedback when a zone fires: Dwell Glow pulses at the corner, Edge Flash sweeps along the edge; size scales 50–200%
- **Trigger sound** — optional built-in macOS sound played together with the effect; pick *None* to keep visuals silent
- **Multi-monitor** — zones cover every connected display
- **Menu bar only** — no Dock icon; optional launch at login
- **Vector icon** — the octopus is a true SVG, rendered crisply at every size

## Performance

Octopus is built to sit quietly in the background — at rest it uses effectively no CPU at all.

- **Zero work while idle** — when the cursor is still, nothing runs. No timers, no polling loops, no background threads ticking away a cost nobody asked for.
- **Event-driven, not sampled** — Octopus is driven by mouse-move events themselves; it never samples the cursor position on a schedule. One event in, one evaluation out.
- **Region-focused evaluation** — only the thin screen-edge strips and corner squares that can actually trigger are ever tested. A single bounding-box check dismisses the whole screen in a handful of comparisons; the 8-zone detail pass runs only when the cursor is truly near an edge.
- **Cached zone geometry** — trigger regions are computed once per display layout and reused at full speed; they rebuild only when you add, remove, or rearrange a monitor.
- **Throttled hot path** — the per-event overhead is allocation-free and rate-limited, so the cursor cannot spin it faster than it needs to run.
- **True dwell, no inventory** — the optional dwell delay is one one-shot timer that exists only while you are actually holding in a zone, and is cancelled the instant you move elsewhere. The charging glow tracks your cursor in real time and stays silent while you hold still.
- **Self-healing input monitoring** — if macOS ever suspends input monitoring (screen lock, wake from sleep), Octopus detects it and re-enables itself within seconds, so hot corners still respond when you come back.
- **Lazy settings UI** — preference status refreshes on window activation and a slow background cadence, not a tight poll while you work.

On any modern Mac the app idles near 0% CPU and only does measurable work while your cursor is actually crossing into a trigger zone.

## Assigning an action

Open **Settings** from the Octopus menu bar icon, then drag any app, file, folder, or script onto one of the eight zones. Prefer a built-in action? Pick one from the system-actions dropdown in the same editor.

## Requirements

- Apple Silicon (M1 or later) — Intel Macs are not supported
- macOS Tahoe (26) or later
- Accessibility permission: System Settings → Privacy & Security → Accessibility (Octopus asks on first launch)

## Build

```
xcodegen generate
xcodebuild -project Octopus.xcodeproj -scheme Octopus -configuration Release build
```
