#!/usr/bin/env bash

set -euo pipefail

RUNTIME_REPO="https://github.com/Argus-AiTeam/minimax-h3-mac.git"
RUNTIME_COMMIT="3fcc9f8c557cf353400b1acf737b985e524a509f"
INT8_REPO="water1234/MiniMax-H3-MLX-Argus-Calibrated-INT8"
INT8_REVISION="70505b09c80e298e684d798d8e0f946937dcfad4"
TURBO_REPO="water1234/MiniMax-H3-Turbo-v4-step600-EMA-MLX"
TURBO_REVISION="9771f9c606a50671bb94ee57191461602f02d1fc"

STORAGE_ROOT=""
MODELS_DIR_OVERRIDE=""
PROFILE_REQUEST="auto"
MEMORY_OVERRIDE=""
INTERACTIVE=0
SHOW_CONFIG=0
CHECK_ONLY=0
LICENSE_ACCEPTED=0
SKIP_MODELS=0
CHECK_FAILURES=0
RUNTIME_REQUIRED_FILES=(
  requirements.txt
  scripts/generate.py
  scripts/doctor.py
  scripts/quantize_text_encoder.py
)

usage() {
  cat <<'EOF'
Install and check MiniMax H3 on Apple Silicon Macs with hardware-aware settings.

Usage:
  ./install-minimax-h3-mac.sh --storage-root /absolute/path --license-accepted
  ./install-minimax-h3-mac.sh --storage-root /absolute/path --profile 128gb --license-accepted
  ./install-minimax-h3-mac.sh --memory-gb 128 --show-config

Storage options:
  --storage-root PATH   Required installation root; --root is a compatible alias.
                        Apps, models, outputs, profiles, and settings live here.
  --models-dir PATH     Optional separate absolute model directory, useful for a
                        portable external model volume shared by multiple Macs.

Hardware/profile options:
  --profile PROFILE     auto, 24gb, 64gb, or 128gb (default: auto).
  --memory-gb NUMBER    Override the target unified-memory size used for tuning.
                        It may be lower, but not higher, than detected memory
                        during installation or checking.
  --interactive         Prompt for target memory and storage root.
  --show-config         Print the suggested configuration and exit without writes.

Operation options:
  --license-accepted   Assert that you personally reviewed and accepted the
                       MiniMax H3 Community License. This does not accept it.
  --skip-models        Install/check tools, runtime, and environment only.
  --check-only         Read-only readiness check; install or modify nothing.
  -h, --help           Show this help.

The script never requests a Hugging Face token on the command line. Complete
"hf auth login" yourself before running a full model installation.
EOF
}

say() { printf '[MiniMax H3] %s\n' "$*"; }
warn() { printf '[MiniMax H3] WARNING: %s\n' "$*" >&2; }
die() { printf '[MiniMax H3] ERROR: %s\n' "$*" >&2; exit 1; }
check_ok() { printf '[check] OK: %s\n' "$*"; }
check_missing() { printf '[check] MISSING: %s\n' "$*" >&2; CHECK_FAILURES=$((CHECK_FAILURES + 1)); }

require_positive_integer() {
  case "$2" in
    ''|*[!0-9]*) die "$1 must be a positive whole number" ;;
    0) die "$1 must be greater than zero" ;;
  esac
}

detect_memory_gib() {
  local memory_bytes memory_label memory_value memory_unit
  if memory_bytes="$(sysctl -n hw.memsize 2>/dev/null)"; then
    printf '%s\n' "$((memory_bytes / 1073741824))"
    return
  fi
  memory_label="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F ': ' '/Memory:/ {print $2; exit}')"
  memory_value="$(printf '%s\n' "$memory_label" | awk '{print $1}')"
  memory_unit="$(printf '%s\n' "$memory_label" | awk '{print $2}')"
  case "$memory_unit" in
    GB) printf '%s\n' "${memory_value%%.*}" ;;
    TB) printf '%s\n' "$(( ${memory_value%%.*} * 1024 ))" ;;
    *) printf '0\n' ;;
  esac
}

select_profile() {
  case "$PROFILE_REQUEST" in
    auto)
      if [[ "$TARGET_MEMORY_GIB" -lt 20 ]]; then
        die "MiniMax H3 needs at least a 24 GB-class Mac for this workflow"
      elif [[ "$TARGET_MEMORY_GIB" -lt 48 ]]; then
        PROFILE_ID="24gb"
      elif [[ "$TARGET_MEMORY_GIB" -lt 96 ]]; then
        PROFILE_ID="64gb"
      else
        PROFILE_ID="128gb"
      fi
      ;;
    24gb|64gb|128gb) PROFILE_ID="$PROFILE_REQUEST" ;;
    *) die "--profile must be auto, 24gb, 64gb, or 128gb" ;;
  esac

  case "$PROFILE_ID" in
    24gb)
      PROFILE_LABEL="24 GB low-memory"
      PROFILE_MIN_MEMORY=20
      CONDITIONER_BITS=4
      PROFILE_HEADROOM_GB=8
      STREAM_BLOCK_GROUP_SIZE=1
      PERFORMANCE_BLOCK_GROUP_SIZE=1
      MEMORY_PRESSURE_GUARD=1
      ;;
    64gb)
      PROFILE_LABEL="64 GB quality baseline"
      PROFILE_MIN_MEMORY=48
      CONDITIONER_BITS=8
      PROFILE_HEADROOM_GB=16
      STREAM_BLOCK_GROUP_SIZE=1
      PERFORMANCE_BLOCK_GROUP_SIZE=1
      MEMORY_PRESSURE_GUARD=0
      ;;
    128gb)
      PROFILE_LABEL="128 GB+ high-memory candidate"
      PROFILE_MIN_MEMORY=96
      CONDITIONER_BITS=8
      PROFILE_HEADROOM_GB=24
      STREAM_BLOCK_GROUP_SIZE=1
      PERFORMANCE_BLOCK_GROUP_SIZE=2
      MEMORY_PRESSURE_GUARD=0
      ;;
  esac
  [[ "$TARGET_MEMORY_GIB" -ge "$PROFILE_MIN_MEMORY" ]] || die "$PROFILE_ID requires at least ${PROFILE_MIN_MEMORY} GiB; target memory is ${TARGET_MEMORY_GIB} GiB"
  MEMORY_LIMIT_GB=$((TARGET_MEMORY_GIB - PROFILE_HEADROOM_GB))
}

print_configuration() {
  cat <<EOF

Suggested MiniMax H3 configuration
  Detected Mac:              ${CHIP_NAME:-unknown}
  Detected unified memory:   ${DETECTED_MEMORY_GIB} GiB
  Target unified memory:     ${TARGET_MEMORY_GIB} GiB
  Selected profile:          ${PROFILE_ID} (${PROFILE_LABEL})
  Conditioner:               ${CONDITIONER_BITS}-bit, first 50 layers
  Transformer:               calibrated INT8
  MLX memory guideline:      ${MEMORY_LIMIT_GB} GB
  Safe stream group size:    ${STREAM_BLOCK_GROUP_SIZE}
  Performance candidate:     ${PERFORMANCE_BLOCK_GROUP_SIZE}
  Memory-pressure guard:     ${MEMORY_PRESSURE_GUARD} (1 means enabled)
  Draft schedule:            5 sigma points / 4 denoiser evaluations
  Quality schedule:          9 sigma points / 8 denoiser evaluations
  First comparison canvas:   768x448 for 5 seconds
EOF
  if [[ "$PROFILE_ID" == "128gb" ]]; then
    cat <<'EOF'
  High-memory note:          group size 2 is an unmeasured throughput candidate.
                             Compare it with group size 1 using the same prompt
                             and seed before treating it as faster.
EOF
  fi
  if [[ -n "$STORAGE_ROOT" ]]; then
    printf '  Storage root:              %s\n' "$STORAGE_ROOT"
    printf '  Model directory:           %s\n' "$MODELS_DIR"
  fi
  printf '\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --storage-root|--root) [[ $# -ge 2 ]] || die "$1 requires an absolute path"; STORAGE_ROOT="$2"; shift 2 ;;
    --models-dir) [[ $# -ge 2 ]] || die "--models-dir requires an absolute path"; MODELS_DIR_OVERRIDE="$2"; shift 2 ;;
    --profile) [[ $# -ge 2 ]] || die "--profile requires a value"; PROFILE_REQUEST="$2"; shift 2 ;;
    --memory-gb) [[ $# -ge 2 ]] || die "--memory-gb requires a number"; MEMORY_OVERRIDE="$2"; shift 2 ;;
    --interactive) INTERACTIVE=1; shift ;;
    --show-config) SHOW_CONFIG=1; shift ;;
    --license-accepted) LICENSE_ACCEPTED=1; shift ;;
    --skip-models) SKIP_MODELS=1; shift ;;
    --check-only) CHECK_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (run with --help)" ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "this installer supports macOS only"
[[ "$(uname -m)" == "arm64" ]] || die "Apple Silicon arm64 is required"

CHIP_NAME="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F ': ' '/Chip:/ {print $2; exit}')"
DETECTED_MEMORY_GIB="$(detect_memory_gib)"
require_positive_integer "detected memory" "$DETECTED_MEMORY_GIB"

if [[ "$INTERACTIVE" -eq 1 && -t 0 ]]; then
  if [[ -z "$MEMORY_OVERRIDE" ]]; then
    printf 'Target unified memory in GB [%s]: ' "$DETECTED_MEMORY_GIB"
    read -r INTERACTIVE_MEMORY
    MEMORY_OVERRIDE="${INTERACTIVE_MEMORY:-$DETECTED_MEMORY_GIB}"
  fi
  if [[ -z "$STORAGE_ROOT" && "$SHOW_CONFIG" -eq 0 ]]; then
    printf 'Storage root (for example /Volumes/Example-H3): '
    read -r STORAGE_ROOT
  fi
elif [[ "$INTERACTIVE" -eq 1 ]]; then
  warn "--interactive was requested without a terminal; using automatic detection"
fi

if [[ -n "$MEMORY_OVERRIDE" ]]; then
  require_positive_integer "--memory-gb" "$MEMORY_OVERRIDE"
  TARGET_MEMORY_GIB="$MEMORY_OVERRIDE"
else
  TARGET_MEMORY_GIB="$DETECTED_MEMORY_GIB"
fi
if [[ "$SHOW_CONFIG" -eq 0 && "$TARGET_MEMORY_GIB" -gt "$DETECTED_MEMORY_GIB" ]]; then
  die "--memory-gb cannot exceed the ${DETECTED_MEMORY_GIB} GiB detected on this Mac"
fi
select_profile

if [[ -n "$STORAGE_ROOT" ]]; then
  [[ "$STORAGE_ROOT" == /* ]] || die "--storage-root must be an absolute path"
  [[ "$STORAGE_ROOT" != "/" ]] || die "--storage-root cannot be /"
  APPS_DIR="$STORAGE_ROOT/Apps"
  OUTPUTS_DIR="$STORAGE_ROOT/Outputs"
  PROFILES_DIR="$STORAGE_ROOT/Profiles"
  PATHS_FILE="$STORAGE_ROOT/minimax-h3-paths.env"
  MODELS_DIR="${MODELS_DIR_OVERRIDE:-$STORAGE_ROOT/Models}"
  [[ "$MODELS_DIR" == /* ]] || die "--models-dir must be an absolute path"
  [[ "$MODELS_DIR" != "/" ]] || die "--models-dir cannot be /"
fi

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  [[ -n "$STORAGE_ROOT" ]] || MODELS_DIR="<storage-root>/Models"
  print_configuration
  exit 0
fi

[[ -n "$STORAGE_ROOT" ]] || die "--storage-root is required (or use --interactive)"
RUNTIME_DIR="$APPS_DIR/minimax-h3-mac"
VENV_PYTHON="$RUNTIME_DIR/.venv/bin/python"
CHECKPOINT_DIR="$MODELS_DIR/MiniMax-H3/FL2VA"
SOURCE_ENCODER_DIR="$CHECKPOINT_DIR/text_encoder"
INT8_DIR="$MODELS_DIR/MiniMax-H3-MLX-Argus-Calibrated-INT8"
ENCODER_DIR="$MODELS_DIR/MiniMax-H3-MLX-TextEncoder-${CONDITIONER_BITS}bit"
TURBO_DIR="$MODELS_DIR/MiniMax-H3-Turbo-v4-step600-EMA-MLX"

print_configuration
ROOT_PARENT="$(dirname "$STORAGE_ROOT")"
[[ -d "$ROOT_PARENT" ]] || die "storage parent does not exist: $ROOT_PARENT"
if [[ -d "$STORAGE_ROOT" ]]; then
  INSTALL_STORAGE_PROBE="$STORAGE_ROOT"
else
  INSTALL_STORAGE_PROBE="$ROOT_PARENT"
fi
if [[ -n "$MODELS_DIR_OVERRIDE" ]]; then
  if [[ -d "$MODELS_DIR" ]]; then
    MODELS_STORAGE_PROBE="$MODELS_DIR"
  else
    MODELS_STORAGE_PROBE="$(dirname "$MODELS_DIR")"
  fi
elif [[ -d "$STORAGE_ROOT" ]]; then
  MODELS_STORAGE_PROBE="$STORAGE_ROOT"
else
  MODELS_STORAGE_PROBE="$ROOT_PARENT"
fi
[[ -d "$MODELS_STORAGE_PROBE" ]] || die "model-directory parent does not exist: $MODELS_STORAGE_PROBE"

describe_storage() {
  local label="$1" probe="$2" info volume_name mount_point device_name
  info="$(diskutil info "$probe" 2>/dev/null || true)"
  volume_name="$(printf '%s\n' "$info" | awk -F ': *' '/Volume Name/ {print $2; exit}')"
  mount_point="$(printf '%s\n' "$info" | awk -F ': *' '/Mount Point/ {print $2; exit}')"
  device_name="$(df -Pk "$probe" | awk 'NR == 2 {print $1}')"
  say "$label storage: ${volume_name:-$device_name}${mount_point:+ mounted at $mount_point} (probe: $probe)"
}

describe_storage "Installation" "$INSTALL_STORAGE_PROBE"
INSTALL_AVAILABLE_KIB="$(df -Pk "$INSTALL_STORAGE_PROBE" | awk 'NR == 2 {print $4}')"
INSTALL_AVAILABLE_GIB=$((INSTALL_AVAILABLE_KIB / 1048576))
say "Available installation-volume space: ${INSTALL_AVAILABLE_GIB} GiB"
if [[ "$INSTALL_AVAILABLE_GIB" -lt 20 ]]; then
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    check_missing "at least 20 GiB free on the selected installation volume"
  else
    die "at least 20 GiB free is required on the selected installation volume"
  fi
fi

describe_storage "Model" "$MODELS_STORAGE_PROBE"
FILESYSTEM_NAME="$(diskutil info "$MODELS_STORAGE_PROBE" 2>/dev/null | awk -F ': *' '/File System Personality/ {print $2; exit}' || true)"
if [[ -n "$FILESYSTEM_NAME" && "$FILESYSTEM_NAME" != *"APFS"* ]]; then
  warn "model storage reports '$FILESYSTEM_NAME'; APFS on a fast SSD is recommended"
fi
AVAILABLE_KIB="$(df -Pk "$MODELS_STORAGE_PROBE" | awk 'NR == 2 {print $4}')"
AVAILABLE_GIB=$((AVAILABLE_KIB / 1048576))
say "Available selected model-volume space: ${AVAILABLE_GIB} GiB"
if [[ "$SKIP_MODELS" -eq 0 && "$CHECK_ONLY" -eq 0 ]]; then
  if [[ "$AVAILABLE_GIB" -lt 120 ]]; then
    die "at least 120 GiB free is required for Install / Repair; 200 GiB is recommended"
  elif [[ "$AVAILABLE_GIB" -lt 200 ]]; then
    warn "less than the recommended 200 GiB is free; monitor the model volume"
  fi
elif [[ "$CHECK_ONLY" -eq 1 && "$AVAILABLE_GIB" -lt 20 ]]; then
  check_missing "at least 20 GiB free on the model volume"
elif [[ "$AVAILABLE_GIB" -lt 20 ]]; then
  die "at least 20 GiB free is required for tools-only installation"
fi

REQUIRED_COMMANDS="git hf"
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  if xcode-select -p >/dev/null 2>&1; then check_ok "Apple Command Line Tools"; else check_missing "Apple Command Line Tools; run: xcode-select --install"; fi
  if command -v brew >/dev/null 2>&1; then check_ok "Homebrew"; else check_missing "Homebrew; install it manually from https://brew.sh/"; fi
  for command_name in $REQUIRED_COMMANDS; do
    if command -v "$command_name" >/dev/null 2>&1; then check_ok "$command_name ($(command -v "$command_name"))"; else check_missing "$command_name"; fi
  done
  BREW_PYTHON_PREFIX="$(brew --prefix python@3.12 2>/dev/null || true)"
  if [[ -x "$BREW_PYTHON_PREFIX/bin/python3.12" ]]; then check_ok "Homebrew Python 3.12 at $BREW_PYTHON_PREFIX/bin/python3.12"; else check_missing "Homebrew Python 3.12; run: brew install python@3.12"; fi
  BREW_FFMPEG_PREFIX="$(brew --prefix ffmpeg 2>/dev/null || true)"
  if [[ -n "$BREW_FFMPEG_PREFIX" ]] && [[ -x "$BREW_FFMPEG_PREFIX/bin/ffmpeg" ]] && [[ -x "$BREW_FFMPEG_PREFIX/bin/ffprobe" ]] && "$BREW_FFMPEG_PREFIX/bin/ffmpeg" -version >/dev/null 2>&1 && "$BREW_FFMPEG_PREFIX/bin/ffprobe" -version >/dev/null 2>&1; then
    check_ok "working Homebrew ffmpeg and ffprobe at $BREW_FFMPEG_PREFIX/bin"
  else
    check_missing "working Homebrew ffmpeg/ffprobe; run: brew reinstall ffmpeg"
  fi
  if [[ -d "$RUNTIME_DIR/.git" ]]; then
    CURRENT_COMMIT="$(git -C "$RUNTIME_DIR" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$CURRENT_COMMIT" == "$RUNTIME_COMMIT" ]]; then check_ok "runtime pinned at $RUNTIME_COMMIT"; else check_missing "runtime revision (found ${CURRENT_COMMIT:-unknown}; expected $RUNTIME_COMMIT)"; fi
    for relative_path in "${RUNTIME_REQUIRED_FILES[@]}"; do
      if [[ -r "$RUNTIME_DIR/$relative_path" ]]; then check_ok "runtime file $relative_path"; else check_missing "runtime file $RUNTIME_DIR/$relative_path"; fi
    done
    if git -C "$RUNTIME_DIR" diff HEAD --quiet -- "${RUNTIME_REQUIRED_FILES[@]}"; then
      check_ok "required runtime files match the pinned checkout"
    else
      check_missing "required runtime files are modified or deleted"
    fi
  else
    check_missing "runtime repository at $RUNTIME_DIR"
  fi
  if [[ -x "$VENV_PYTHON" ]] && "$VENV_PYTHON" -c 'import mlx.core as mx; print(mx.default_device())' >/dev/null 2>&1; then check_ok "Python environment and MLX import"; else check_missing "working MLX Python environment at $RUNTIME_DIR/.venv"; fi
  if [[ "$SKIP_MODELS" -eq 0 ]]; then
    if command -v hf >/dev/null 2>&1 && hf auth whoami >/dev/null 2>&1; then check_ok "Hugging Face authentication"; else check_missing "Hugging Face authentication or connectivity; run: hf auth login"; fi
    if [[ "$LICENSE_ACCEPTED" -eq 1 ]]; then check_ok "license acceptance asserted for this check"; else check_missing "license assertion; review the license and add --license-accepted"; fi
    for required_file in "$CHECKPOINT_DIR/model_index.json" "$SOURCE_ENCODER_DIR/model.safetensors.index.json" "$INT8_DIR/model.safetensors.index.json" "$ENCODER_DIR/model.safetensors.index.json" "$ENCODER_DIR/quant_config.json" "$TURBO_DIR/adapter.safetensors.index.json"; do
      if [[ -f "$required_file" ]]; then check_ok "$required_file"; else check_missing "$required_file"; fi
    done
    if [[ -x "$VENV_PYTHON" && -f "$ENCODER_DIR/quant_config.json" ]]; then
      FOUND_BITS="$("$VENV_PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["bits"])' "$ENCODER_DIR/quant_config.json" 2>/dev/null || true)"
      if [[ "$FOUND_BITS" == "$CONDITIONER_BITS" ]]; then check_ok "conditioner precision is ${CONDITIONER_BITS}-bit"; else check_missing "conditioner precision (found ${FOUND_BITS:-unknown}; expected $CONDITIONER_BITS)"; fi
    fi
  fi
  if [[ "$CHECK_FAILURES" -gt 0 ]]; then printf '\n[check] FAILED: %d required item(s) are missing.\n' "$CHECK_FAILURES" >&2; exit 1; fi
  printf '\n[check] READY: all requested checks passed.\n'
  exit 0
fi

if ! xcode-select -p >/dev/null 2>&1; then say "Apple Command Line Tools are missing. Starting Apple's installer..."; xcode-select --install || true; die "complete the Apple installer, then rerun"; fi
command -v brew >/dev/null 2>&1 || die "install Homebrew manually from https://brew.sh/, then rerun"
for formula in python@3.12 ffmpeg git hf; do
  if brew list --formula "$formula" >/dev/null 2>&1; then say "$formula is already installed"; else say "Installing Homebrew formula: $formula"; brew install "$formula"; fi
done
for command_name in $REQUIRED_COMMANDS; do command -v "$command_name" >/dev/null 2>&1 || die "$command_name is unavailable after installation"; done

BREW_PYTHON_PREFIX="$(brew --prefix python@3.12)"
PREFERRED_PYTHON="$BREW_PYTHON_PREFIX/bin/python3.12"
BREW_FFMPEG_PREFIX="$(brew --prefix ffmpeg)"
PREFERRED_FFMPEG="$BREW_FFMPEG_PREFIX/bin/ffmpeg"
PREFERRED_FFPROBE="$BREW_FFMPEG_PREFIX/bin/ffprobe"
[[ -x "$PREFERRED_PYTHON" ]] || die "Homebrew Python 3.12 was not found at $PREFERRED_PYTHON"
[[ -x "$PREFERRED_FFMPEG" ]] || die "Homebrew ffmpeg was not found at $PREFERRED_FFMPEG"
[[ -x "$PREFERRED_FFPROBE" ]] || die "Homebrew ffprobe was not found at $PREFERRED_FFPROBE"
"$PREFERRED_FFMPEG" -version >/dev/null 2>&1 || die "Homebrew ffmpeg cannot start; run: brew reinstall ffmpeg"
"$PREFERRED_FFPROBE" -version >/dev/null 2>&1 || die "Homebrew ffprobe cannot start; run: brew reinstall ffmpeg"
say "Using Homebrew Python and media tools independently of PATH order"

if [[ "$SKIP_MODELS" -eq 0 ]]; then
  [[ "$LICENSE_ACCEPTED" -eq 1 ]] || die "review https://huggingface.co/MiniMaxAI/MiniMax-H3 and add --license-accepted"
  hf auth whoami >/dev/null 2>&1 || die "run 'hf auth login' yourself, then rerun"
fi
mkdir -p "$APPS_DIR" "$MODELS_DIR" "$OUTPUTS_DIR" "$PROFILES_DIR"
if [[ -e "$RUNTIME_DIR" && ! -d "$RUNTIME_DIR/.git" ]]; then die "$RUNTIME_DIR exists but is not a Git checkout; move it aside manually"; fi
if [[ ! -d "$RUNTIME_DIR/.git" ]]; then say "Cloning the MiniMax H3 MLX runtime"; git clone "$RUNTIME_REPO" "$RUNTIME_DIR"; fi

CURRENT_ORIGIN="$(git -C "$RUNTIME_DIR" remote get-url origin 2>/dev/null || true)"
case "$CURRENT_ORIGIN" in
  "$RUNTIME_REPO"|"https://github.com/Argus-AiTeam/minimax-h3-mac"|"git@github.com:Argus-AiTeam/minimax-h3-mac.git") ;;
  *) die "unexpected runtime origin: ${CURRENT_ORIGIN:-missing}" ;;
esac
CURRENT_COMMIT="$(git -C "$RUNTIME_DIR" rev-parse HEAD)"
if [[ "$CURRENT_COMMIT" != "$RUNTIME_COMMIT" ]]; then
  [[ -z "$(git -C "$RUNTIME_DIR" status --porcelain)" ]] || die "runtime has local changes and is not at the pinned revision"
  if ! git -C "$RUNTIME_DIR" cat-file -e "${RUNTIME_COMMIT}^{commit}" 2>/dev/null; then git -C "$RUNTIME_DIR" fetch origin "$RUNTIME_COMMIT"; fi
  git -C "$RUNTIME_DIR" checkout --detach "$RUNTIME_COMMIT"
fi
say "Runtime is pinned at $RUNTIME_COMMIT"

for relative_path in "${RUNTIME_REQUIRED_FILES[@]}"; do
  if [[ ! -r "$RUNTIME_DIR/$relative_path" ]]; then
    if git -C "$RUNTIME_DIR" cat-file -e "$RUNTIME_COMMIT:$relative_path" 2>/dev/null; then
      say "Restoring missing managed runtime file: $relative_path"
      git -C "$RUNTIME_DIR" checkout "$RUNTIME_COMMIT" -- "$relative_path"
    else
      die "required runtime file is absent from the pinned revision: $relative_path"
    fi
  fi
done
if ! git -C "$RUNTIME_DIR" diff HEAD --quiet -- "${RUNTIME_REQUIRED_FILES[@]}"; then
  say "Changed installer-managed runtime files:"
  git -C "$RUNTIME_DIR" diff HEAD --name-only -- "${RUNTIME_REQUIRED_FILES[@]}" | while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] && say "  $relative_path"
  done
  RUNTIME_BACKUP_DIR="$STORAGE_ROOT/InstallModel Backups/runtime-$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$RUNTIME_BACKUP_DIR"
  git -C "$RUNTIME_DIR" diff HEAD -- "${RUNTIME_REQUIRED_FILES[@]}" > "$RUNTIME_BACKUP_DIR/managed-runtime-files.patch"
  say "Preserved changed managed runtime files as $RUNTIME_BACKUP_DIR/managed-runtime-files.patch"
  say "Restoring installer-managed runtime files to the pinned revision"
  git -C "$RUNTIME_DIR" checkout "$RUNTIME_COMMIT" -- "${RUNTIME_REQUIRED_FILES[@]}"
fi
git -C "$RUNTIME_DIR" diff HEAD --quiet -- "${RUNTIME_REQUIRED_FILES[@]}" || die "installer-managed runtime files could not be restored"
say "Required runtime files are present and match the pinned revision"

if [[ ! -x "$VENV_PYTHON" ]]; then say "Creating Python 3.12 virtual environment"; "$PREFERRED_PYTHON" -m venv "$RUNTIME_DIR/.venv"; fi
"$VENV_PYTHON" -m pip install --upgrade pip
"$VENV_PYTHON" -m pip install -r "$RUNTIME_DIR/requirements.txt"
"$VENV_PYTHON" -c 'import mlx.core as mx; print("MLX device:", mx.default_device())'

write_environment() {
  {
    printf 'export MINIMAX_H3_ROOT=%q\n' "$STORAGE_ROOT"
    printf 'export MINIMAX_H3_MODELS=%q\n' "$MODELS_DIR"
    printf 'export MINIMAX_H3_RUNTIME=%q\n' "$RUNTIME_DIR"
    printf 'export MINIMAX_H3_CHECKPOINT=%q\n' "$CHECKPOINT_DIR"
    printf 'export MINIMAX_H3_TRANSFORMER=%q\n' "$INT8_DIR"
    printf 'export MINIMAX_H3_TEXT_ENCODER=%q\n' "$ENCODER_DIR"
    printf 'export MINIMAX_H3_TURBO=%q\n' "$TURBO_DIR"
    printf 'export MINIMAX_H3_TURBO_LORA=%q\n' "$TURBO_DIR"
    printf 'export MINIMAX_H3_OUTPUTS=%q\n' "$OUTPUTS_DIR"
    printf 'export MINIMAX_H3_PROFILES=%q\n' "$PROFILES_DIR"
    printf 'export MINIMAX_H3_FFMPEG=%q\n' "$PREFERRED_FFMPEG"
    printf 'export MINIMAX_H3_FFPROBE=%q\n' "$PREFERRED_FFPROBE"
    printf 'export MINIMAX_H3_PROFILE_ID=%q\n' "$PROFILE_ID"
    printf 'export MINIMAX_H3_TARGET_MEMORY_GB=%q\n' "$TARGET_MEMORY_GIB"
    printf 'export MINIMAX_H3_MEMORY_LIMIT_GB=%q\n' "$MEMORY_LIMIT_GB"
    printf 'export MINIMAX_H3_STREAM_BLOCK_GROUP_SIZE=%q\n' "$STREAM_BLOCK_GROUP_SIZE"
    printf 'export MINIMAX_H3_PERFORMANCE_BLOCK_GROUP_SIZE=%q\n' "$PERFORMANCE_BLOCK_GROUP_SIZE"
    printf 'export MINIMAX_H3_CONDITIONER_BITS=%q\n' "$CONDITIONER_BITS"
    printf 'export MINIMAX_H3_MEMORY_PRESSURE_GUARD=%q\n' "$MEMORY_PRESSURE_GUARD"
    printf 'export MINIMAX_H3_DRAFT_STEPS=5\n'
    printf 'export MINIMAX_H3_QUALITY_STEPS=9\n'
    printf 'export MINIMAX_H3_SMOKE_RESOLUTION=768x448\n'
  } > "$PATHS_FILE"
}

if [[ "$SKIP_MODELS" -eq 1 ]]; then write_environment; say "Tools and runtime are ready; model download was skipped."; say "Saved suggested settings to $PATHS_FILE"; exit 0; fi

export HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-30}"
say "Downloading official tokenizer, processor, BF16 conditioner source, and VAEs"
hf download MiniMaxAI/MiniMax-H3 --include "FL2VA/model_index.json" "FL2VA/tokenizer/**" "FL2VA/processor/**" "FL2VA/text_encoder/**" "FL2VA/video_vae/**" "FL2VA/audio_vae/**" --local-dir "$MODELS_DIR/MiniMax-H3"
say "Downloading the revision-pinned calibrated INT8 transformer"
hf download "$INT8_REPO" --revision "$INT8_REVISION" --local-dir "$INT8_DIR"
say "Downloading the revision-pinned native MLX Turbo adapter"
hf download "$TURBO_REPO" --revision "$TURBO_REVISION" --local-dir "$TURBO_DIR"

[[ -f "$SOURCE_ENCODER_DIR/model.safetensors.index.json" ]] || die "BF16 text-encoder source is incomplete"
if [[ -f "$ENCODER_DIR/model.safetensors.index.json" && -f "$ENCODER_DIR/quant_config.json" ]]; then
  FOUND_BITS="$("$VENV_PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["bits"])' "$ENCODER_DIR/quant_config.json")"
  [[ "$FOUND_BITS" == "$CONDITIONER_BITS" ]] || die "existing conditioner is ${FOUND_BITS}-bit, expected ${CONDITIONER_BITS}-bit"
  say "${CONDITIONER_BITS}-bit conditioner is already present"
else
  if [[ -d "$ENCODER_DIR" && -n "$(ls -A "$ENCODER_DIR" 2>/dev/null)" ]]; then die "partial conditioner output exists at $ENCODER_DIR; inspect or move it aside manually"; fi
  say "Building the streamed ${CONDITIONER_BITS}-bit conditioner"
  "$VENV_PYTHON" "$RUNTIME_DIR/scripts/quantize_text_encoder.py" --source "$SOURCE_ENCODER_DIR" --output "$ENCODER_DIR" --bits "$CONDITIONER_BITS" --group-size 64 --num-layers 50
fi

write_environment
say "Running the runtime's model and environment doctor"
MINIMAX_H3_ACCEPT_LICENSE=1 "$VENV_PYTHON" "$RUNTIME_DIR/scripts/doctor.py" \
  --checkpoint "$CHECKPOINT_DIR" --transformer "$INT8_DIR" --text-encoder "$ENCODER_DIR" --turbo-lora "$TURBO_DIR" \
  --output-dir "$OUTPUTS_DIR" --ffmpeg "$PREFERRED_FFMPEG" --ffprobe "$PREFERRED_FFPROBE" \
  --min-memory-gib "$PROFILE_MIN_MEMORY" --min-free-gib 20 --require-model-paths --require-license-acceptance --pretty

say "Installation and preflight completed."
say "Saved paths and selected profile to: $PATHS_FILE"
say "Source that file before using the README generation commands."
