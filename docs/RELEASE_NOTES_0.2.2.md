# InstallModel 0.2.2 (Build 4) — Private Test

InstallModel 0.2.2 supersedes the 0.2.1 private test build with storage-capacity checks that follow the selected installation and model paths to their actual mounted filesystems.

## Storage behavior

- The app shows available space for the installation root and model directory separately.
- If the model directory is on an attached drive, the 120 GiB minimum and 200 GiB recommendation are calculated from that attached drive.
- The app labels the resolved volume and mount point before installation.
- A path under an attached volume that is no longer mounted is rejected; the app does not substitute the internal `/Volumes` directory.
- The installer independently performs the same selected-volume checks before writing.

## Included 0.2.1 recovery fixes

- Correct readable-file validation for the normal `0644` `scripts/generate.py` file.
- Runtime or `generate.py` locator and Setup-path synchronization.
- Missing managed runtime-file restoration and modified-file protection.
- Durable operation logs, installation keep-awake behavior, and best-effort process-tree interruption.

Use a 64 GB Apple Silicon Mac with at least 200 GiB free on the volume selected for model files. This remains a private test build until installation, Check, generation, decode, and audiovisual acceptance pass on that Mac.
