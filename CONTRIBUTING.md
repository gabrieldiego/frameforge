# Contributing To FrameForge

FrameForge is currently a skeleton for codec and hardware-acceleration experiments. Contributions should keep the first milestone small, explicit, and easy to verify.

## Ground Rules

- Do not claim VVC/H.266 conformance until generated bitstreams have been validated against the specification and external decoders.
- Do not import VTM, VVdeC, or other incompatible source code.
- Prefer clean-room notes and TODOs over guessed codec syntax.
- Keep generic infrastructure generic. VVC-specific code should stay isolated.
- Keep screen-content coding work as planned modules or stubs until the core bitstream path exists.

## Local Checks

```sh
make check-tools
make fmt
make test
```

RTL checks require cocotb and a simulator. The default target is Icarus Verilog:

```sh
make rtl-test SIM=icarus
```

## Patch Style

- Small, reviewable patches are preferred.
- Add focused tests for bitstream utilities, traversal behavior, trace output, and future golden-model logic.
- For RTL, keep ready/valid behavior explicit and add cocotb tests for handshake assumptions.
- Avoid adding large directory layouts before there is code that needs them.

