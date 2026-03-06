# Session Notes (2026-03-06)

## Purpose
Capture architecture and UX decisions made during implementation so future sessions preserve constraints and avoid regressions.

## Audio Architecture Decisions
- Parameter automation must use audio sample-frame time, not wall-clock timers.
- No abrupt transitions: frequency and gain changes are always ramped.
- Carrier frequency is always present and clamped to `>= 200 Hz`.
- Oscillator phase continuity is preserved during parameter changes.
- UI-to-engine command path uses a lock-free queue (avoid locks in render callback).
- Parameter updates are applied as staged edits with explicit `Apply` in UI to avoid partial state drift.
- Batched parameter apply command is available for coherent multi-parameter transitions.

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
- Transition slider exists on main screen.
- Transition minimum is `5.0s`.
- Each parameter row shows current value and inline edit icon.
- Per-parameter sheet supports:
  - Slider for coarse changes.
  - `- / +` nudge buttons for precise step changes.
  - `Apply` / `Cancel` actions.

## Repo / Workflow Preferences
- Prefer incremental, focused commits after each accepted UX/architecture refinement.
- Keep docs updated when behavior assumptions or constraints become explicit.
