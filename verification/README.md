# Verification Workspace

This directory is for local verification resources and generated outputs.

FrameForge does not vendor VTM source code. If no decoder is configured through
environment variables, `scripts/ensure_reference_decoder.py` clones and builds
VTM under `verification/codecs/vvc/reference/vtm` for the VVC codec. Existing
legacy trees under `verification/reference/vtm` are still detected.

Useful variables:

- `FRAMEFORGE_DECODER`: complete decoder command.
- `FRAMEFORGE_VTM_DECODER`: direct path to a built VTM decoder executable.
- `FRAMEFORGE_VTM_ENCODER`: direct path to a built VTM encoder executable.
- `FRAMEFORGE_VTM_ROOT`: existing VTM tree to search for a decoder.
- `FRAMEFORGE_REF_DIR`: parent directory for downloaded validation tools.
- `FRAMEFORGE_VTM_REPO`: VTM repository URL.
- `FRAMEFORGE_VTM_REF`: optional VTM branch or tag.
- `FRAMEFORGE_VTM_BUILD_DIR`: CMake build directory.
- `FRAMEFORGE_GENERATED_DIR`: local generated input directory for helper scripts.

Quality and bitrate validation baselines are recorded in
`docs/quality-bitrate.md`. Synthesis baselines remain in `docs/synthesis.md`.
