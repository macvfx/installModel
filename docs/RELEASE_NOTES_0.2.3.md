# InstallModel 0.2.3 (Build 5) — Private Test

InstallModel 0.2.3 addresses the first 0.2.2 test on a 64 GB target Mac.

## Remembered locations

- Setup remembers the last installation root, external Models folder, separate-model choice, workflow, and profile.
- Generate remembers the last `minimax-h3-paths.env` location and automatically reloads it when available.
- License confirmation remains intentionally session-only.

## Repair and generation behavior

- Install / Repair now saves a patch of changed installer-managed runtime files under `<installation root>/InstallModel Backups`, restores only those four managed files to the pinned revision, and continues.
- Unrelated files in the runtime checkout are not restored or removed.
- Check reports the required `uv` executable, while Install / Repair installs the Homebrew `uv` formula when needed.
- The runtime doctor runs from the pinned checkout so it can inspect the intended `pyproject.toml` and lockfile.
- If Hugging Face reports a successful refresh but the required `FL2VA/model_index.json` is not readable, Install / Repair force-downloads that single small file and verifies it before continuing.
- Generate automatically revalidates the environment when its tab reappears; **Load / Recheck** is also available for an immediate manual refresh.
- Generation checks for the configured checkpoint's `model_index.json` and the transformer, text encoder, and Turbo LoRA folders before launching Python.
- An incomplete or disconnected model drive therefore produces an actionable in-app message instead of a Python traceback.

## Field-log diagnosis

The 0.2.2 generation command correctly targeted the configured `MiniMax-H3/FL2VA` checkpoint, but `model_index.json` was missing there. Install / Repair was positioned to download that missing file but stopped first because a managed runtime file contained local changes. This build repairs that narrow condition while preserving the prior contents as a patch.

A later 0.2.2 repair successfully downloaded the missing checkpoint metadata and exposed a second installer omission: the runtime doctor requires `uv`, but the installer did not check or install it. This build includes that prerequisite.

This remains a private test build until Install / Repair, Check, generation, decode, and audiovisual acceptance complete on the target Mac.
