# InstallModel Development Backlog

**Status:** Planned work after InstallModel 0.2.1 (build 3)

This backlog distinguishes shipped behavior from work that has not yet been implemented. Priority reflects safety and test value, not a promised delivery date.

## Current baseline

The repository currently provides:

- a hardware-aware, idempotent Bash installer;
- automatic 24 GB, 64 GB, and 128 GB profile selection;
- separate local-runtime and external-model storage paths;
- Stage 1 preparation and Stage 2 target-Mac guidance;
- read-only Preview and Check operations plus Install / Repair;
- a SwiftUI development app with System and Magic themes;
- a safe Generate tab with paired MP4/profile JSON naming and profile-aware settings;
- About and in-app Help windows;
- an ad-hoc local builder plus Developer ID signing, notarization, stapling, checksum, and Gatekeeper validation; and
- twelve unit tests covering setup profiles, external model reuse, safe environment parsing, direct generation arguments, runtime location, and readable-script validation.

The two-Mac external-drive workflow has not yet completed formal end-to-end acceptance through the app.

## P0 — Acceptance and execution safety

Version 0.2.1 adds installation keep-awake behavior, durable logs, runtime integrity repair, and best-effort process-tree interruption. The acceptance items below remain open until lifecycle/cancellation automation and the second-Mac procedure pass.

### P0.1 Two-Mac external-drive acceptance

**Goal:** Prove Stage 1 on a preparation Mac and Stage 2 on a different target Mac using the same external model folder.

**Acceptance gates:**

- run the [two-Mac testing guide](TESTING_USER_GUIDE.md) without undocumented recovery steps;
- preserve the same external-volume mount path across both machines;
- demonstrate model-file reuse on the target Mac;
- finish the target doctor and final read-only check successfully;
- generate and validate a five-second MP4 with video and audio; and
- retain an anonymized test record with timing and hardware details.

### P0.2 Keep-awake support

**Goal:** Prevent normal idle sleep during downloads, model preparation, doctor runs, and generation.

**Acceptance gates:**

- keep-awake assertion begins only while an operation is active;
- assertion ends after success, failure, cancellation, or app termination;
- UI clearly indicates when sleep prevention is active; and
- automated tests cover lifecycle state transitions.

### P0.3 Durable operation logs

**Goal:** Save timestamped output independently of the on-screen console.

**Acceptance gates:**

- each Preview, Check, and Install / Repair run receives a separate UTF-8 log;
- log location is visible and revealable in Finder;
- secrets are not added by the app;
- log includes app version, operation, selected profile, exit status, and timestamps; and
- public issue guidance requires anonymizing usernames, paths, and volume labels.

### P0.4 Safe process-tree cancellation

**Goal:** Stop the installer and its active child processes without leaving downloads, Python conversion, or Homebrew running unexpectedly.

**Acceptance gates:**

- cancellation targets the owned process group rather than unrelated processes;
- UI distinguishes cancelling from cancelled;
- cancellation has a bounded graceful period before escalation;
- app reports the final termination status; and
- tests cover a process with at least one child.

### P0.5 Quit and external-drive protection

**Goal:** Avoid accidental interruption or silent writes to an unintended replacement path.

**Acceptance gates:**

- quitting during an active operation requires explicit confirmation;
- disappearance of the selected external volume stops new work and surfaces a clear error;
- app does not silently create a `Models` folder on another volume when the intended mount is absent; and
- reconnection instructions preserve partial downloads for a safe retry.

## P1 — Readiness and generation experience

### P1.1 Readiness dashboard

**Goal:** Replace raw output as the primary status view while retaining the full log.

**Acceptance gates:**

- individual status rows cover Command Line Tools, Homebrew, Python 3.12, Git, Hugging Face CLI, authentication, FFmpeg, runtime revision, MLX import, license assertion, and each required model component;
- every failed row contains one actionable recovery instruction;
- statuses derive from the same checks as the installer to prevent drift; and
- a successful dashboard corresponds to the script's READY result.

### P1.2 Stage-aware workflow state

**Goal:** Make the preparation-Mac and target-Mac paths harder to confuse.

**Acceptance gates:**

- Stage 1 emphasizes local runtime plus external model destination;
- Stage 2 requires selecting an existing external model directory;
- app warns when Stage 2 points to an empty or unexpected folder;
- selected paths and profile are summarized before installation; and
- app explains when an additional conditioner precision will be built.

### P1.3 Hugging Face readiness helper

**Goal:** Clarify the manual account and authentication boundary.

**Acceptance gates:**

- app opens only official account, token, model, and license pages;
- app detects `hf auth whoami` without displaying the token;
- no token field, command-line token, or token logging is introduced; and
- authentication is clearly marked as machine-specific.

### P1.4 Minimal generation screen — initial implementation complete

**Goal:** Run the installed model without requiring the operator to assemble the long Terminal command.

**Acceptance gates:**

- automatically loads the selected `minimax-h3-paths.env` values without executing unrelated shell content;
- exposes prompt, duration, resolution, quality schedule, seed, and output destination;
- uses the explicit verified Homebrew FFmpeg and requires a muxed MP4;
- prevents incompatible settings for the selected memory profile;
- retains console and forward-profile output; and
- reveals the completed MP4 in Finder.

Implemented in the SwiftUI Generate tab. It safely parses known installer values, keeps the MP4 and forward-profile JSON names paired, uses direct process arguments and the installed FFmpeg path, constrains memory to the loaded profile guideline, streams console output, and reveals either generated file. Target-Mac generation and visual/audio review remain acceptance work rather than completed proof.

### P1.5 Media validation summary

**Goal:** Separate successful generation from valid, reviewable output.

**Acceptance gates:**

- runs `ffprobe` for video, audio, and duration;
- performs a full decode check;
- reports file size and checksum;
- presents a concise pass/fail summary; and
- leaves manual motion, prompt-adherence, and audio review explicitly unverified until the operator confirms them.

## P2 — Distribution, performance, and quality

### P2.1 Native Xcode application target

**Goal:** Replace the manual bundle assembly with a conventional macOS application target.

**Acceptance gates:**

- Xcode builds `InstallModel.app` directly with the checked-in icon and resources;
- Debug and Release configurations use deterministic version/build values;
- bundled installer parity is automatically checked; and
- the app launches on a clean supported Mac without SwiftPM development paths.

### P2.2 Developer ID release pipeline

**Goal:** Produce a testable distributable build.

**Acceptance gates:**

- hardened-runtime Developer ID signature validates;
- notarization succeeds and the ticket is stapled;
- DMG is signed, notarized, checksummed, and validated by Gatekeeper;
- a fresh download is verified separately from the build copy; and
- signing, notarization, launch, and functional acceptance are reported as separate results.

Implemented for 0.2.0 with exact-artifact validation and fresh-download verification required for each published release. This does not imply that the two-Mac or audiovisual acceptance gates are complete.

### P2.3 M2 Ultra 128 GB benchmark

**Goal:** Measure rather than assume the performance benefit of additional memory and stream group size 2.

**Acceptance gates:**

- compare group sizes 1 and 2 with identical prompt, seed, steps, resolution, and duration;
- record load time, seconds per step, total time, peak memory, swap, and output validation;
- repeat enough runs to identify obvious warm-cache effects; and
- keep group size 1 as default unless group size 2 demonstrates a repeatable benefit without quality or stability regression.

### P2.4 Accessibility and UI automation

**Goal:** Verify the app can be operated with keyboard navigation and assistive technologies.

**Acceptance gates:**

- every control has an accessible label, value, and hint where needed;
- System and Magic themes meet contrast expectations;
- full setup can be traversed without a pointing device;
- text remains readable at larger accessibility sizes; and
- automated UI coverage includes theme switching, path selection boundaries, Preview, and Check.

### P2.5 Maintenance and update policy

**Goal:** Make upstream revision changes reviewable and reproducible.

**Acceptance gates:**

- runtime, transformer, and Turbo revisions remain explicit;
- changes include upstream source review, model-manifest validation, installer/bundle parity, and smoke testing;
- app displays the installed runtime and model revisions; and
- update checks never replace a locally modified runtime automatically.

## Backlog completion rule

An item moves out of this document only after its acceptance gates are supported by committed code, tests, and retained evidence. A successful build alone does not satisfy operational, audiovisual, signing, or cross-machine acceptance.
