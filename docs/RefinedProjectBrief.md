# WaveGenerator iOS - Refined Project Brief

## Goal
Build an iOS app that continuously synthesizes and outputs a waveform to speaker or connected headphones with **no audible clicks/jolts** when starting, stopping, or changing parameters.

## Core Model
- Carrier frequency (`fc`): always present, constrained to `>= 200 Hz`.
- Pulse frequency (`fp`): modulates loudness envelope.
- Wetness (`w`, `0...1`): controls pulse depth.
  - `w = 1`: constant tone (no pulsing)
  - `w = 0`: full pulse envelope from 0 to 1
  - Envelope formula (single pulse layer):
    - `pulse = (sin(2π fp t) + 1) / 2`
    - `env = w + (1 - w) * pulse`
- Output (single pulse layer MVP):
  - `y(t) = masterGain(t) * sin(2π fc t) * env(t)`

## Why Your Modifier Timeline Is Viable
Your `StartTime / StartValue / TargetValue / EndTime` ramp concept is a good fit and should prevent hard discontinuities if all parameter changes are ramped.

Refinements:
- Use **audio sample time** (frame index) rather than wall-clock time for deterministic ramps.
- Keep one active modifier per parameter for MVP (as proposed).
- On a new change while ramping, begin from the parameter's current interpolated value at "now".
- Persist completed modifiers as compact events (not PCM), enabling deterministic replay.

## Constraints To Enforce
- Carrier floor: `fc = max(fc, 200)`.
- No abrupt gain or frequency jumps:
  - Start/stop via `masterGain` ramps (e.g. 0.5-2.0s in MVP).
  - Parameter changes always scheduled as linear ramps with minimum duration.
- Phase continuity:
  - Keep oscillator phases continuous while parameters move.
  - Do not reset phase during normal edits.

## Potential Issues and Mitigations
1. Real-time thread safety
- Risk: locking/allocating in render callback can cause glitches.
- Current mitigation: keep render path simple; queue control events through a fixed-size lock-free command queue; avoid per-sample allocation.

2. Zipper noise from coarse control updates
- Risk: updating params at UI tick rate introduces stepping.
- Mitigation: all UI edits become timed ramps evaluated per sample.

3. Clipping with multilayer multiplication
- Risk: multiple layers can exceed expected level.
- Mitigation: final samples are hard-clamped to `-1...1`; consider a headroom/limiter strategy later if clipping audibly occurs.

4. Battery/performance
- Risk: heavy per-sample math for many layers.
- Mitigation: scale with vectorized math / bounded layer count later.

## Current Architecture
- `WaveAudioEngine`
  - Owns `AVAudioEngine`, `AVAudioSourceNode`, render state, command queue.
- `RampedParameter`
  - Encapsulates one active linear modifier at a time.
- `RenderState`
  - Holds sample rate, frame position, master gain, stereo flag, and channel component state.
- `WaveGeneratorViewModel`
  - UI-facing state and validation; schedules transitions to engine.
- `WaveSessionHistoryStore`
  - Retains the most recent compact session timelines for replay, export, and offline rendering.

## Layering Roadmap
- Carrier is mandatory and cannot be deleted.
- Pulse layers are dynamic; the app starts with one pulse, but supports carrier-only output.
- N pulse layers are multiplied into the output via neutral-at-zero contribution envelopes.
- Layer introduction rule: create muted layer, allow silent frequency/wetness tuning, then ramp layer volume up when desired.
- Pulse layers are independent; each pulse owns its own frequency, phase, wetness, and volume automation.

## POC Scope (implemented now)
- Tone output to iPhone/iPad speaker/headphones.
- Smooth start/stop through gain ramp.
- Smooth carrier/pulse/wetness changes through timeline modifiers.
- Carrier minimum clamp at 200 Hz.
- Dynamic pulse add/remove with ramped pulse contribution.
- Save completed playback sessions as compact action timelines that can be replayed, exported from history, or rendered offline to WAV.
- Load exported JSON session files, validate them, play them back, and render them to WAV.
- Each pulse keeps a direct frequency editor with a `0...5 Hz` range.

## Deferred from POC
- Broader session editing UI beyond replay/export/render.
- More advanced export/analysis tools beyond WAV rendering.
- Disable controls while active transition (optional UX policy).
