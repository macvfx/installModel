# InstallModel 0.2.0 (Build 2)

InstallModel 0.2.0 adds a safe SwiftUI generation workflow to the existing hardware-aware MiniMax H3 installer.

## Highlights

- Run an installed MiniMax H3 environment from the new **Generate** tab.
- Edit the prompt, output name, resolution, duration, quality steps, seed, and advanced profile-aware settings.
- Write a paired MP4 and forward-profile JSON without overwriting existing results.
- Load only allowlisted values from `minimax-h3-paths.env`; the file is not sourced or executed.
- Use the installer-selected Python runtime and explicit Homebrew FFmpeg path through direct process arguments.
- Follow native About and Help windows, including the complete public guides and [code.matx.ca](https://code.matx.ca).

## Requirements

- Apple Silicon Mac with at least 24 GB-class unified memory; the installer requires at least 20 GiB detected memory.
- macOS 14 or later.
- A Hugging Face account with the MiniMax H3 license personally reviewed and accepted.
- Homebrew and machine-specific `hf auth login` authentication.
- Approximately 200 GB free before the initial model preparation.

## Important boundaries

- The app does not request or store Hugging Face tokens.
- Model weights are not included in the DMG and retain their upstream license terms.
- A successful generation still requires manual stream, decode, visual, motion, prompt-adherence, and audio review.
- Formal two-Mac acceptance and M2 Ultra 128 GB performance measurement remain open work.

See the [README](https://github.com/macvfx/installModel#readme), [Two-Mac Testing User Guide](https://github.com/macvfx/installModel/blob/main/docs/TESTING_USER_GUIDE.md), and [changelog](https://github.com/macvfx/installModel/blob/main/CHANGELOG.md).
