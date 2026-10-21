# Changelog

## 0.2.3 (build 5) — 2026-10-20

### Fixed

- Setup now remembers the last installation root, external Models folder, separate-model choice, workflow, and profile between app launches.
- Generate remembers the last environment-file location and automatically reloads it when the file remains available.
- Generation now checks for `FL2VA/model_index.json` and the configured transformer, text encoder, and Turbo LoRA folders before launching Python.
- Install / Repair no longer stops at changed installer-managed runtime files. It saves their diff under `InstallModel Backups`, restores only the four managed files to the pinned revision, and continues the repair.
- Check now reports the runtime doctor's required `uv` executable, and Install / Repair installs the Homebrew `uv` formula when it is absent.
- The runtime doctor now runs from the pinned runtime directory so its project metadata and lockfile checks resolve against the intended checkout.

### Diagnosis from 0.2.2 field logs

- The checkpoint path was correct, but `/Volumes/.../MiniMax-H3/FL2VA/model_index.json` was absent.
- Install / Repair would have downloaded the missing checkpoint metadata, but it stopped earlier because a managed runtime file differed from the pinned checkout.
- A subsequent 0.2.2 repair downloaded the missing checkpoint metadata and then exposed the omitted `uv` prerequisite.

## 0.2.2 (build 4) — 2026-10-20

### Fixed

- Free-space checks now resolve the selected installation and model paths to their actual mounted filesystems.
- A Models path on an attached drive is measured against that drive rather than the internal disk.
- An unmounted `/Volumes/<drive>/…` selection is rejected instead of falling back to `/Volumes` on the internal filesystem.

### Added

- Separate in-app capacity rows for installation files and model files, including volume name, mount point, available GiB, minimum, and recommendation.
- The installer log now identifies both selected storage volumes and their probe paths before enforcing 20 GiB for installation files and 120 GiB for model files.
- Regression tests for new folders on an existing volume and missing attached-volume paths.

## 0.2.1 (build 3) — 2026-10-20

### Fixed

- Corrected generation preflight so `scripts/generate.py` is required to be readable, not executable. The pinned runtime intentionally stores the Python script with normal `0644` permissions.
- Added runtime integrity checks to Check and Install / Repair. Missing managed runtime files are restored from the pinned commit, while locally modified required files stop with an explicit error.
- Prevented repair from silently targeting a different installation by loading the installer root and model directory from `minimax-h3-paths.env` into Setup.

### Added

- **Locate runtime or generate.py…** recovery control with validation of Python, FFmpeg, `requirements.txt`, and the required runtime scripts.
- Durable local logs for Preview, Check, Install / Repair, and Generate operations, with reveal controls in the app.
- Keep-awake protection for installation and repair, plus best-effort interruption of the observed child process tree.
- A 120 GiB free-space requirement for every model Install / Repair run, retaining the 200 GiB recommendation.
- Regression coverage for ordinary non-executable Python scripts, missing `generate.py`, runtime selection, and installation-root synchronization data.

### Boundaries

- This build has source, unit-test, and local bundle validation but still requires the planned 64 GB second-Mac installation and real generation acceptance.
- Post-generation `ffprobe`, full decode, prompt-adherence, motion, and audio review remain manual.

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
