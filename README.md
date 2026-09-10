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

- **Region-focused monitoring** — the cursor is evaluated only against the zones' screen-edge regions; zone geometry is cached and rebuilt only when your display layout changes
- **Event-driven dwell** — no timers run while the cursor rests in a zone; dwell completion and cancellation are driven by the cursor events themselves
- **Throttled hot path** — per-mouse-event overhead is stripped from the event tap; no polling loops, no background threads
- **Charging Dwell Glow** — the glow charges in sync with cursor movement and stays silent while the cursor is still

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
