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
- MVP mitigation: keep render path simple; queue control events outside callback; no per-sample allocation.
- Production: lock-free ring buffer for control messages.

2. Zipper noise from coarse control updates
- Risk: updating params at UI tick rate introduces stepping.
- Mitigation: all UI edits become timed ramps evaluated per sample.

3. Clipping with multilayer multiplication
- Risk: multiple layers can exceed expected level.
- Mitigation: apply output headroom limiter strategy (or conservative gain law).

4. Battery/performance
- Risk: heavy per-sample math for many layers.
- Mitigation: scale with vectorized math / bounded layer count later.

## Suggested Architecture
- `WaveAudioEngine`
  - Owns `AVAudioEngine`, `AVAudioSourceNode`, render state, command queue.
- `RampedParameter`
  - Encapsulates one active linear modifier at a time.
- `RenderState`
  - Oscillator phase, frame counter, parameters; pure sample generation.
- `WaveViewModel`
  - UI-facing state and validation; schedules transitions to engine.
- `SessionStore` (later)
  - Append completed modifiers to JSONL for playback/reconstruction.

## Layering Roadmap
- Carrier is mandatory and cannot be deleted.
- Pulse layers are dynamic; the app starts with one pulse, but supports carrier-only output.
- N pulse layers are multiplied into the output via neutral-at-zero contribution envelopes.
- Layer introduction rule: create muted layer, allow silent frequency/wetness tuning, then ramp layer volume up when desired.

## POC Scope (implemented now)
- Tone output to iPhone/iPad speaker/headphones.
- Smooth start/stop through gain ramp.
- Smooth carrier/pulse/wetness changes through timeline modifiers.
- Carrier minimum clamp at 200 Hz.
- Dynamic pulse add/remove with ramped pulse contribution.

## Deferred from POC
- Modifier persistence/replay files.
- Real-time safe lock-free control queue.
- Disable controls while active transition (optional UX policy).
