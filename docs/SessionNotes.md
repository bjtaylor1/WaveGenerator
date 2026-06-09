# Session Notes (2026-03-06)

## Purpose
Capture architecture and UX decisions made during implementation so future sessions preserve constraints and avoid regressions.

## Audio Architecture Decisions
- Parameter automation must use audio sample-frame time, not wall-clock timers.
- No abrupt transitions: frequency and gain changes ramp while playing; stopped-wave parameter changes apply immediately.
- Carrier frequency is always present and clamped to `>= 200 Hz`.
- Final rendered samples are hard-clamped to `-1...1` before output.
- Oscillator phase continuity is preserved during parameter changes.
- UI-to-engine command path uses a lock-free queue (avoid locks in render callback).
- Completed playback sessions are persisted as compact action timelines: the app stores the starting settings snapshot plus accepted audio-changing actions at frame offsets from playback start.
- Exported session files do not include absolute date/time fields; replay timing comes from `sampleRate`, `durationFrames`, event `frameOffset`, and transition frame counts.
- History and imported session files can be replayed from their compact timelines, with remaining playback time shown while a file session is active.
- History and imported session files can be rendered offline to WAV after validation.
- Imported session files are validated before playback/rendering for header fields, channel settings, event timing, value ranges, and pulse indices.
- Parameter updates are applied as staged edits with explicit `Apply` in UI to avoid partial state drift.
- Batched parameter apply command is available for coherent multi-parameter transitions.
- Waveform settings are persisted in `UserDefaults`, including carrier, transition, pulse layers, and selected pulse; the most recent 50 session timelines are also retained for export.

## iPhone Audio Startup Reliability
Observed issue:
- `NSOSStatusErrorDomain Code=-50` during engine startup on physical iPhone.

Working setup:
- Use minimal audio session config: `setCategory(.playback, mode: .default, options: [])`.
- Use explicit source render format when connecting source node:
  - `pcmFormatFloat32`
  - non-interleaved
  - 2 channels
  - explicit sample rate (session sample rate fallback to 48k)

Result:
- Startup succeeds on device and tone output works.

## State Consistency Rules
- If command queue is saturated, `Apply` is disabled.
- Apply action retries until accepted; no silent drop on staged commit.
- Main displayed values represent committed/applied state, not transient drag state.

## UX Preferences Captured
- Main screen uses compact inline edit controls (pencil icons), not extra edit rows.
- Separate per-parameter edit sheets (Carrier, Pulse, Wetness), each with one primary control.
- Fine tuning uses slider + icon-only nudge buttons (`minus.circle` / `plus.circle`).
- Avoid visually heavy button labels where icon buttons are sufficient.

## Current Parameter Editing UX
- Transition uses the same inline pencil edit sheet pattern as the other controls.
- Transition minimum is `5.0s`.
- Each parameter row shows current value and inline edit icon.
- Carrier is always visible and cannot be removed.
- Pulses use a segmented selector with add/remove icon controls.
- New pulses are added silently at `0.00` volume so frequency and wetness can be staged before ramping contribution up.
- Pulse frequencies are independent; each pulse can be edited directly across the `0...5 Hz` range.
- Per-parameter sheet supports:
  - Slider for coarse changes.
  - `- / +` nudge buttons for precise step changes.
  - `Apply` / `Cancel` actions.

## Repo / Workflow Preferences
- Prefer incremental, focused commits after each accepted UX/architecture refinement.
- Keep docs updated when behavior assumptions or constraints become explicit.
