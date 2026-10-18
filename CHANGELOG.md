# Changelog

## 0.2.0 (build 2) — 2026-10-18

### Added

- Generate tab for running the installed MiniMax H3 model without assembling a long Terminal command.
- Editable prompt, paired MP4/profile JSON output name, resolution, duration, quality steps, seed, Turbo LoRA scale, and profile-aware memory controls.
- Safe allowlisted parsing of `minimax-h3-paths.env` without sourcing or evaluating shell content.
- Direct `Process` invocation using the installed Python runtime and explicit verified FFmpeg path.
- Live generation output, Stop, Reveal MP4, and Reveal JSON controls.
- Native About window with version information and a [code.matx.ca](https://code.matx.ca) link.
- Native Help window covering setup, two-Mac model reuse, generation, failure recovery, and validation boundaries.

### Safety and documentation

- Existing MP4 or JSON results are never overwritten.
- Memory cannot be raised above the selected install profile's guideline.
- README, two-Mac user guide, detailed setup guide, and backlog now describe the app generation workflow and release boundary.
- Expanded the automated suite from five to nine tests.

### Known limitations

- Hugging Face account creation, model-license acceptance, Homebrew installation, and `hf auth login` remain manual.
- Post-generation `ffprobe`, full decode, prompt-adherence, motion, and audio review remain manual.
- Formal two-Mac external-drive acceptance and M2 Ultra 128 GB performance measurement are not yet complete.
