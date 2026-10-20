# InstallModel 0.2.1 (Build 3) — Private Test

InstallModel 0.2.1 is a recovery-focused private test build for a fresh installation and generation test on a 64 GB Apple Silicon Mac with ample free disk space.

## Fixed

- Generation now treats `scripts/generate.py` as a readable Python source file. It no longer incorrectly requires the file itself to have executable permission.
- Check verifies the required runtime files as well as the pinned Git revision.
- Install / Repair restores missing managed runtime files from the pinned revision and stops rather than overwriting locally modified required files.
- Loading `minimax-h3-paths.env` synchronizes the Setup installation and model paths, preventing repair of a different root.

## Recovery and evidence

- **Locate runtime or generate.py…** can select either the runtime directory or its `scripts/generate.py` file.
- The app validates the Python environment, FFmpeg, requirements file, generator, doctor, and conditioner tool before enabling generation.
- Preview, Check, Install / Repair, and Generate write revealable logs under `~/Library/Logs/InstallModel`.
- Installation now runs under `caffeinate`; Stop sends an interrupt to the observed operation and child processes.
- Model Install / Repair requires at least 120 GiB free and warns below the recommended 200 GiB.

## Required second-Mac test

- Use the 64 GB profile selected automatically on the target Mac.
- Keep at least 200 GiB free before starting.
- Preserve the operation logs and the final `minimax-h3-paths.env` file.
- Require Check to report ready before generation.
- Generate a short test clip, then manually validate the MP4 with `ffprobe`, a complete decode, and audiovisual review.

This private test build is not proof of completed end-to-end acceptance until those steps pass on the target Mac.
