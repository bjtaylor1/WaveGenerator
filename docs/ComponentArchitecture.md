# Component Architecture

## Goal
Move the audio engine away from a hardcoded `carrier + pulse` render path and toward a list of independently-driven components whose outputs are combined at the end.

## Core Principles
- Each component owns only its own state.
- Each component receives only its own parameter commands.
- A component does not inspect another component's phase, wetness, or command history.
- The final output is produced by combining component amplitudes after each component has independently evaluated its own amplitude for the current sample time.

## Component Model
Each component should have:
- a minimum frequency
- a current phase
- a frequency ramp/automation timeline
- a wetness ramp/automation timeline
- an amplitude function evaluated from component-local state

In the current Swift refactor, the engine starts with two components:
- `components[0]`: mandatory base component, minimum frequency `200 Hz`
- `components[1]`: primary pulse component, minimum frequency `0.01 Hz`

The existing UI maps to those components as follows:
- `Carrier` edits `components[0].frequency`
- each pulse edits a dynamic pulse component's frequency, wetness, and volume
- the app starts with one pulse, but pulses can be removed down to carrier-only output

## Local Phase
The intended phase model matches the older C++ engine in `~/wavegen/wavelib`.

For each component, maintain a component-local phase `x`:

`x_next = x_current + 2 * pi * f / sampleRate`

The component's amplitude is then evaluated from that component-local phase and that component's own parameters.

This is important because:
- modulation should be expressed as a function of the component's own local phase
- components should remain independent of one another
- future multi-component support becomes a data-model problem rather than a special-case render-path problem

## Mixing Rule
The intended mixer rule is multiplicative:

`output(t) = masterGain(t) * product(component[i].amplitude(t))`

This matches the old C++ design, where grouped components can be aggregated by `product`.

Pulse volume is a contribution control, not a direct post-multiply gain. At `volume = 0`, a pulse component returns neutral amplitude `1` and has no effect on the output. At `volume = 1`, it contributes its full wetness-controlled pulse envelope. This lets pulse add/remove operations pass through a neutral multiplier instead of jolting the output.

## Command Ownership
Commands should be thought of as belonging to a specific component:
- set frequency for component `i`
- set wetness for component `i`
- eventually set gain or other per-component parameters for component `i`

Batch UI operations may still exist, but internally they should decompose into component-owned parameter updates.

## Why This Matters
This structure supports the intended roadmap:
- keep the base component mandatory
- allow many pulse components
- keep per-component automation isolated
- avoid coupling pulse logic to carrier-cycle inspection

## Important Caveat
Architectural separation does not by itself guarantee that the final multiplied waveform will visually remain a perfect sine in a recording. If multiple independently varying components are multiplied together, the final result can still contain modulation sidebands. The point of this architecture is correctness, extensibility, and component independence.
