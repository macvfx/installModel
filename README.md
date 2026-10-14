# Hardware-aware MiniMax H3 installer for Apple Silicon

This repository contains an idempotent Bash installer for the MLX MiniMax H3 workflow documented in the [full Mac setup guide](docs/MINIMAX_H3_MAC_SETUP_GUIDE.md). It detects unified memory, selects a conservative profile, supports explicit overrides, and can keep the reusable model assets on an external drive.

The primary script is `install-minimax-h3-mac.sh`. The older `install-minimax-h3-m1-max.sh` filename remains as a compatibility wrapper and invokes the same hardware-aware installer.

The checked-in examples use fictional volume names and user paths. Generated environment files, model weights, outputs, caches, and machine-specific Xcode data are intentionally excluded from version control. Do not commit Hugging Face tokens or a generated `minimax-h3-paths.env` file.

## Documentation

- [Two-Mac Testing User Guide](docs/TESTING_USER_GUIDE.md) — preparation-Mac download, external-drive handoff, target-Mac setup, generation validation, and evidence checklist.
- [Development Backlog](docs/BACKLOG.md) — prioritized safety, readiness, generation, distribution, and performance work with acceptance gates.
- [Detailed Mac Setup Guide](docs/MINIMAX_H3_MAC_SETUP_GUIDE.md) — manual MLX setup concepts, commands, profile details, troubleshooting, and references.

## Minimal SwiftUI app

The repository also contains an early, deliberately small macOS SwiftUI front end. It:

- detects Apple Silicon, chip name, and unified memory;
- recommends the same 24 GB, 64 GB, or 128 GB profile as the script;
- guides the operator through Hugging Face account creation and license review;
- supports a local installation root plus a separate external `Models` folder;
- explains the Stage 1 preparation-Mac and Stage 2 target-Mac workflow;
- provides a persistent magic-wand appearance button that switches between the native System theme and a higher-contrast navy, cyan, and amber theme derived from the app icon;
- runs Preview, Check, and Install / Repair through a bundled copy of the reviewed installer; and
- shows the exact command and live combined output without asking for or storing a token.

This is a development prototype, not a signed or sandboxed release. It intentionally leaves browser account creation, license acceptance, Homebrew installation, and `hf auth login` under the operator's control. Model generation remains in the documented runtime commands after installation.

Build, test, and run it with Xcode's active command-line toolchain:

```bash
swift test
swift run InstallModel
```

To create a normal Finder-launchable application bundle with the included model-download icon:

```bash
./scripts/build-app.sh debug
open "build/Debug/InstallModel.app"
```

The bundle is ad-hoc signed for local inspection. It is not Developer ID signed, notarized, or packaged for distribution. You can also open `Package.swift` in Xcode and run the `InstallModel` scheme. The package requires macOS 14 or later. When the audited root installer changes, update the bundled copy at `Sources/InstallModelApp/Resources/Scripts/install-minimax-h3-mac.sh` in the same commit and verify that both copies are identical.

For a private test build that can be copied to other Apple Silicon Macs, use the Keychain-backed release script. It requires an installed Developer ID Application identity and a `notarytool` profile; it never accepts credentials as arguments:

```bash
./scripts/build-sign-notarize-test-release.sh \
  --output-dir "/Volumes/Example-Releases/InstallModel-0.1.0-1"
```

The script builds the Release app, applies the hardened runtime and secure timestamp, notarizes and staples the app and DMG, mounts the DMG, verifies its exact app with `codesign`, `stapler`, and Gatekeeper, and writes a SHA-256 file plus a release receipt. This produces a private test artifact only. GitHub publication remains a separate, explicitly approved operation.

## Profiles

| Auto-selected class | Conditioner | MLX memory guideline | Safe stream group | Initial test |
| --- | --- | ---: | ---: | --- |
| 24–47 GB | 4-bit | detected memory minus 8 GB | 1 | 768×448, 5 seconds |
| 48–95 GB | 8-bit | detected memory minus 16 GB | 1 | 768×448, 5 seconds |
| 96 GB or more | 8-bit | detected memory minus 24 GB | 1 | 768×448, 5 seconds |

For a 128 GB Mac, that produces a 104 GB MLX guideline. The installer also records stream group size 2 as a **performance experiment**, not the default. The pinned runtime documents larger streamed groups as opt-in, but model loading was a small part of measured runtime; group size 2 must therefore be benchmarked against group size 1 rather than assumed faster.

The tested 64 GB M1 Max baseline remains:

- calibrated INT8 transformer;
- locally converted 8-bit conditioner;
- stream group size 1;
- 768×448, 5 seconds, 9 sigma points / 8 denoiser evaluations;
- 24.6 minutes observed for the complete run, including MP4 muxing.

The M2 Ultra 128 GB profile is a proposed test configuration. Its larger memory budget is source-backed, but no result should be recorded until that machine completes the same prompt, seed, resolution, and validation.

## Manual requirements

### Storage

Use a fast APFS internal SSD or Thunderbolt/USB4 NVMe SSD. Have 200 GB free before initial preparation. The examples use the fictional `/Volumes/Example-H3` path.

`--storage-root` keeps the runtime, models, outputs, profiles, and generated settings together:

```text
/Volumes/Example-H3/
├── Apps/minimax-h3-mac/
├── Models/
├── Outputs/
├── Profiles/
└── minimax-h3-paths.env
```

This is the simplest portable layout. Keep the same external-volume name when moving it between Macs because the Python environment and generated settings contain absolute paths. Model files themselves are portable; if the mount path changes, rerun the installer at the new path instead of editing the virtual environment.

`minimax-h3-paths.env` represents the last Mac/profile that ran the installer. When one portable root moves between a 64 GB and 128 GB Mac, rerun the installer—not only `--check-only`—on the destination before generating; the large model files will be reused while the machine-specific settings are refreshed.

To keep the runtime locally while storing only large reusable model assets on an external volume, specify a separate directory:

```bash
./install-minimax-h3-mac.sh \
  --storage-root "/Users/example/MiniMax-H3" \
  --models-dir "/Volumes/Example-H3-Models/Models" \
  --license-accepted
```

The parent directories must already exist. The installer creates only the named installation and model folders; it does not erase or relocate existing files.

## Two-stage installation using two Macs

Use this workflow to download and prepare the large model assets on one Mac, carry them on an external drive, and finish the machine-specific setup on the Mac that will generate video. Keeping only `Models` on the portable drive is preferred: each Mac gets its own runtime and Python environment, while the expensive downloads are shared.

### Stage 1: prepare the external model drive

On the preparation Mac:

1. Connect a fast APFS-formatted external SSD. The example volume is fictional; substitute the actual mounted volume.
2. Install Homebrew and authenticate this Mac with Hugging Face.
3. Run the installer with a local runtime root and the external model directory:

   ```bash
   hf auth login
   hf auth whoami

   ./install-minimax-h3-mac.sh \
     --storage-root "$HOME/MiniMax-H3-Prepare" \
     --models-dir "/Volumes/Example-H3-Models/Models" \
     --license-accepted
   ```

The preparation Mac downloads the tokenizer, processor, BF16 conditioner source, VAEs, pinned calibrated INT8 transformer, and pinned Turbo adapter to the external drive. It also builds the conditioner selected for that Mac.

- A 48 GB or larger preparation Mac builds the same 8-bit conditioner used by the 64 GB and 128 GB profiles, so the target can reuse it directly.
- A 24 GB preparation Mac builds a 4-bit conditioner. The future 128 GB target will reuse all downloads but will still build its additional 8-bit conditioner from the existing BF16 source; that is local processing rather than another complete model download.

Allow the installer and doctor to finish successfully. Preserve the complete `Models` directory, including each hidden `.cache/huggingface` directory. Those metadata files let a later `hf download --local-dir` invocation recognize completed files efficiently. Using the external drive directly is preferable to copying with a tool that might omit hidden files.

Safely eject the model drive when preparation is complete.

### Stage 2: finish setup on the target Mac

On the target Mac, mount the drive with the same volume name. Homebrew itself and Hugging Face authentication are machine-specific:

1. Install Homebrew manually if `brew --version` fails.
2. Run `hf auth login` and confirm with `hf auth whoami`.
3. Optionally run a read-only check to see what is missing. A failing result is expected when the target runtime or Homebrew formulas have not been installed yet:

   ```bash
   ./install-minimax-h3-mac.sh \
     --storage-root "$HOME/MiniMax-H3" \
     --models-dir "/Volumes/Example-H3-Models/Models" \
     --profile 128gb \
     --memory-gb 128 \
     --check-only \
     --license-accepted
   ```

4. Run the full installer to install missing formulas, create the target's local runtime and Python environment, reuse the external assets, prepare any missing conditioner precision, write target-specific settings, and run the doctor:

   ```bash
   ./install-minimax-h3-mac.sh \
     --storage-root "$HOME/MiniMax-H3" \
     --models-dir "/Volumes/Example-H3-Models/Models" \
     --profile 128gb \
     --memory-gb 128 \
     --license-accepted
   ```

Use the full installer—not only `--check-only`—when you want missing components repaired. The second `hf download` pass checks the existing local-directory metadata and normally downloads only files that are missing or have changed. The community INT8 transformer and Turbo adapter are revision-pinned; the official common MiniMax assets are checked against their upstream repository and could receive changed files.

After the target doctor passes, source `$HOME/MiniMax-H3/minimax-h3-paths.env` and run the comparable smoke test below. Keep the external model drive connected throughout generation.

### Moving the complete installation instead

You may instead set `--storage-root` directly to the external drive on both Macs. This carries the runtime, virtual environment, models, outputs, and profiles together. Keep the same mounted volume path and rerun the full installer on the destination so it can verify the Python environment, install host-specific Homebrew dependencies, and rewrite `minimax-h3-paths.env` for the destination profile. The large model files are still reused.

### Homebrew and Apple tools

Install [Homebrew](https://brew.sh/) manually if `brew --version` fails. The script installs or checks `python@3.12`, `ffmpeg`, `git`, and `hf`. If Apple's Command Line Tools are absent, it starts Apple's installer and asks you to rerun afterward.

The generated environment records the exact Homebrew `ffmpeg` and `ffprobe` binaries. This avoids the previously observed broken MacPorts binary under `/opt/local/bin`.

### Hugging Face account and license

A free Hugging Face account is required:

1. Create or sign into an account at [huggingface.co](https://huggingface.co/join).
2. Open [MiniMaxAI/MiniMax-H3](https://huggingface.co/MiniMaxAI/MiniMax-H3).
3. Read the current MiniMax H3 Community License and complete any access step shown.
4. Run `hf auth login`, followed by `hf auth whoami`.

The installer never takes a token as an argument. `--license-accepted` only records your assertion for that invocation; it does not accept the license or bypass access controls.

## Inspect the recommendation without installing

Automatic detection on the current Mac:

```bash
./install-minimax-h3-mac.sh --show-config
```

Preview how the script would tune another memory size:

```bash
./install-minimax-h3-mac.sh --memory-gb 64 --show-config
./install-minimax-h3-mac.sh --memory-gb 128 --show-config
```

`--show-config` is the only mode that permits a target memory value larger than the current Mac because it writes nothing. Installation and checking reject a target larger than detected hardware.

Interactive selection is also available:

```bash
./install-minimax-h3-mac.sh --interactive --license-accepted
```

Press Return to accept detected memory, then enter the storage root.

## Install

Allow automatic hardware selection:

```bash
./install-minimax-h3-mac.sh \
  --storage-root "/Volumes/Example-H3" \
  --license-accepted
```

Explicit M1 Max 64 GB profile:

```bash
./install-minimax-h3-mac.sh \
  --storage-root "/Volumes/Example-H3" \
  --profile 64gb \
  --memory-gb 64 \
  --license-accepted
```

Explicit M2 Ultra 128 GB profile:

```bash
./install-minimax-h3-mac.sh \
  --storage-root "/Volumes/Example-H3" \
  --profile 128gb \
  --memory-gb 128 \
  --license-accepted
```

On the actual 128 GB Mac, `--profile auto` produces the same class automatically. Existing model downloads and a completed 8-bit conditioner are reused, so the same external model folder can serve the 64 GB and 128 GB profiles.

The installer pins the runtime and community model revisions, retains the BF16 conditioner source, refuses to overwrite an unrelated directory or dirty runtime revision, and runs the runtime doctor when preparation completes.

### Tools and runtime only

```bash
./install-minimax-h3-mac.sh \
  --storage-root "/Volumes/Example-H3" \
  --skip-models
```

## Read-only check

Use the same profile or memory override that was used during installation:

```bash
./install-minimax-h3-mac.sh \
  --storage-root "/Volumes/Example-H3" \
  --check-only \
  --license-accepted
```

The check validates hardware selection, storage, command-line tools, the working Homebrew media binaries, pinned runtime, MLX environment, Hugging Face authentication, model indexes, and conditioner precision.

If installation used `--models-dir`, repeat that same option during `--check-only` so the checker resolves the portable assets correctly.

## First comparable smoke test

Source the settings written by the installer:

```bash
source "/Volumes/Example-H3/minimax-h3-paths.env"
cd "$MINIMAX_H3_RUNTIME"
mkdir -p "$MINIMAX_H3_OUTPUTS/$MINIMAX_H3_PROFILE_ID" "$MINIMAX_H3_PROFILES/$MINIMAX_H3_PROFILE_ID"
```

Prepare the optional guard flag; it remains empty for profiles that do not need it:

```bash
H3_MEMORY_GUARD_ARGS=()
if [[ "$MINIMAX_H3_MEMORY_PRESSURE_GUARD" == "1" ]]; then
  H3_MEMORY_GUARD_ARGS+=(--memory-pressure-guard)
fi
```

Run the same baseline on every Mac so timings remain comparable:

```bash
caffeinate -dimsu .venv/bin/python scripts/generate.py \
  "A cinematic locked-off shot of a small red fox walking through fresh snow at dawn, natural coherent movement, detailed fur, soft backlight, quiet winter ambience, no text, no watermark" \
  --checkpoint "$MINIMAX_H3_CHECKPOINT" \
  --transformer "$MINIMAX_H3_TRANSFORMER" \
  --text-encoder "$MINIMAX_H3_TEXT_ENCODER" \
  --turbo-lora "$MINIMAX_H3_TURBO" \
  --turbo-lora-scale 1.0 \
  --profile quality \
  --low-memory \
  --stream-blocks \
  --stream-block-group-size "$MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE" \
  --resolution "$MINIMAX_H3_SMOKE_RESOLUTION" \
  --duration 5 \
  --steps "$MINIMAX_H3_QUALITY_STEPS" \
  --seed 42 \
  --memory-limit-gb "$MINIMAX_H3_MEMORY_LIMIT_GB" \
  --no-block-cache \
  --dense-dequant-profile off \
  "${H3_MEMORY_GUARD_ARGS[@]}" \
  --ffmpeg "$MINIMAX_H3_FFMPEG" \
  --require-muxed-mp4 \
  --forward-profile-json "$MINIMAX_H3_PROFILES/$MINIMAX_H3_PROFILE_ID/fox-test-group-$MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE.json" \
  --output "$MINIMAX_H3_OUTPUTS/$MINIMAX_H3_PROFILE_ID/fox-test-group-$MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE.mp4"
```

Quit Ollama and other GPU-heavy software first. Watch the complete clip with sound, then validate it:

```bash
"$MINIMAX_H3_FFPROBE" -v error \
  -show_entries stream=index,codec_type,codec_name,width,height,r_frame_rate,channels,sample_rate,duration \
  -of json \
  "$MINIMAX_H3_OUTPUTS/$MINIMAX_H3_PROFILE_ID/fox-test-group-$MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE.mp4"

"$MINIMAX_H3_FFMPEG" -v error \
  -i "$MINIMAX_H3_OUTPUTS/$MINIMAX_H3_PROFILE_ID/fox-test-group-$MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE.mp4" \
  -f null -
```

No output from the complete `ffmpeg` decode indicates that decoding passed. It does not replace visual and audio review.

## M2 Ultra performance comparison

First complete the safe group-size-1 baseline above. Then change only the group size:

```bash
export MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE="$MINIMAX_H3_PERFORMANCE_BLOCK_GROUP_SIZE"
```

Rerun the identical command. Compare total time, seconds per step, maximum memory pressure, the profile JSON, and the complete rendered clip. Keep group size 2 only if it is stable and produces a material improvement. The M2 Ultra's greater GPU resources and 800 GB/s memory bandwidth may make it faster than the M1 Max, but the exact gain cannot be inferred from RAM capacity and must be measured.

For quick drafts, change only `--steps` to `"$MINIMAX_H3_DRAFT_STEPS"`. Five sigma points means four denoiser evaluations and is expected to be much faster than the nine-point quality baseline, with a possible quality tradeoff.

## Troubleshooting

- **Missing `FL2VA/model_index.json`:** rerun the installer or download that exact file with `hf download MiniMaxAI/MiniMax-H3 "FL2VA/model_index.json" --local-dir "$MINIMAX_H3_MODELS/MiniMax-H3"`.
- **`401`, `403`, or gated access:** confirm the license/access step in the same account, then run `hf auth login --force`.
- **Partial conditioner directory:** inspect or move only the reported `MiniMax-H3-MLX-TextEncoder-4bit` or `8bit` folder aside; retain the BF16 source.
- **`dyld` references `/opt/local`:** use `--ffmpeg "$MINIMAX_H3_FFMPEG"`; the generated value points to the tested Homebrew binary.
- **Excessive swap:** return to stream group size 1, close other GPU workloads, and use the profile-selected memory guideline.
- **External volume path changed:** remount it with the original name or rerun the installer with the new absolute root. Do not hand-edit virtual-environment shebangs.

## Sources and evidence boundary

- [Argus-AiTeam MiniMax H3 Mac runtime](https://github.com/Argus-AiTeam/minimax-h3-mac/blob/main/README_EN.md)
- [Pinned runtime CLI options](https://github.com/Argus-AiTeam/minimax-h3-mac/blob/3fcc9f8c557cf353400b1acf737b985e524a509f/minimax_h3_mlx/generate_cli.py)
- [Official MiniMax H3 model and license](https://huggingface.co/MiniMaxAI/MiniMax-H3)
- [Official Hugging Face CLI documentation](https://huggingface.co/docs/huggingface_hub/guides/cli)
- [Apple Mac Studio 2023 specifications](https://support.apple.com/en-gb/111835)

The 64 GB timing above is a completed local operator test. The 128 GB memory guideline and group-size experiment are conservative proposals based on the pinned runtime's controls, not a measured M2 Ultra performance claim.
