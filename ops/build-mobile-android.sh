#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
APP_DIR="${ROOT_DIR}/app"
MOBILE_ENV_FILE="${ROOT_DIR}/ops/app.mobile.env.prod"
ANDROID_DIR="${APP_DIR}/android"
ANDROID_LOCAL_PROPERTIES="${ANDROID_DIR}/local.properties"

if ! command -v pnpm >/dev/null 2>&1; then
  echo "ERROR: pnpm not found in PATH."
  exit 1
fi

if [ ! -f "${MOBILE_ENV_FILE}" ]; then
  echo "ERROR: missing ${MOBILE_ENV_FILE}"
  exit 1
fi

resolve_android_sdk_path() {
  if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "${ANDROID_SDK_ROOT}" ]; then
    printf '%s' "${ANDROID_SDK_ROOT}"
    return 0
  fi

  if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME}" ]; then
    printf '%s' "${ANDROID_HOME}"
    return 0
  fi

  if [ -d "/home/${USER}/Android/Sdk" ]; then
    printf '%s' "/home/${USER}/Android/Sdk"
    return 0
  fi

  local win_sdk_path
  win_sdk_path="$(ls -d /mnt/c/Users/*/AppData/Local/Android/Sdk 2>/dev/null | head -n 1 || true)"
  if [ -n "${win_sdk_path}" ] && [ -d "${win_sdk_path}" ]; then
    printf '%s' "${win_sdk_path}"
    return 0
  fi

  return 1
}

validate_android_sdk_path() {
  local sdk_path="$1"

  # Gradle in WSL/Linux needs Linux build-tools binaries (aapt), not .exe.
  if [ "$(uname -s)" = "Linux" ]; then
    local has_linux_aapt has_windows_aapt
    has_linux_aapt="$(find "${sdk_path}/build-tools" -maxdepth 2 -type f -name aapt 2>/dev/null | head -n 1 || true)"
    has_windows_aapt="$(find "${sdk_path}/build-tools" -maxdepth 2 -type f -name aapt.exe 2>/dev/null | head -n 1 || true)"

    if [ -z "${has_linux_aapt}" ]; then
      if [ -n "${has_windows_aapt}" ]; then
        echo "WARNING: Windows Android SDK detected at ${sdk_path} (aapt.exe only)."
        echo "         WSL/Gradle builds are not supported with this SDK."
        echo "         Continue with Android Studio on Windows (recommended for your setup)."
        return 1
      else
        echo "WARNING: Android SDK at ${sdk_path} has no usable build-tools 'aapt' binary."
        return 1
      fi
    fi
  fi

  return 0
}

ensure_android_local_properties() {
  local sdk_path
  if ! sdk_path="$(resolve_android_sdk_path)"; then
    echo "INFO: Android SDK not found in this shell."
    echo "      This is fine if you build/install from Android Studio on Windows."
    return 0
  fi

  if ! validate_android_sdk_path "${sdk_path}"; then
    # Keep script usable for webapp-build/sync even when WSL Gradle is not possible.
    return 0
  fi

  cat > "${ANDROID_LOCAL_PROPERTIES}" <<EOF
sdk.dir=${sdk_path}
EOF
  echo "Using Android SDK at: ${sdk_path}"
}

ensure_android_local_properties

cd "${APP_DIR}"

# Old root-owned files from containerized builds can block asset generation.
if [ -d "public/assets/icons" ] && [ ! -w "public/assets/icons" ]; then
  echo "WARNING: app/public/assets/icons is not writable by $(id -un)."
  echo "         Icon regeneration may be skipped."
  echo "         Fix with: sudo chown -R $(id -u):$(id -g) app/public/assets app/android app/ios"
fi

# Follow FAIMS CI style: export build variables and let env-cmd --no-override
# prefer these over local .env values, without rewriting app/.env.
set -a
# shellcheck disable=SC1090
source "${MOBILE_ENV_FILE}"

if git -C "${ROOT_DIR}" rev-parse --short=9 HEAD >/dev/null 2>&1; then
  VITE_COMMIT_VERSION="$(git -C "${ROOT_DIR}" rev-parse --short=9 HEAD)"
  echo "Using VITE_COMMIT_VERSION from ${ROOT_DIR}: ${VITE_COMMIT_VERSION}"
elif [ -n "${VITE_COMMIT_VERSION:-}" ]; then
  echo "Using pre-set VITE_COMMIT_VERSION: ${VITE_COMMIT_VERSION}"
else
  echo "WARNING: Could not detect git metadata in ${ROOT_DIR}."
  echo "         About Build may show a stale commit hash from app/.env."
  echo "         Set manually before build, for example:"
  echo "         export VITE_COMMIT_VERSION=\$(git -C /home/jakob/projects/faims3 rev-parse --short=9 HEAD)"
fi

# Android Gradle reads APP_ID for namespace/applicationId. Keep this aligned
# with VITE_APP_ID so install/uninstall package names are predictable.
if [ -z "${APP_ID:-}" ] && [ -n "${VITE_APP_ID:-}" ]; then
  APP_ID="${VITE_APP_ID}"
fi
set +a

echo "[1/2] Building web bundle and copying into native projects (FAIMS flow: webapp-build)"
pnpm run webapp-build

echo "[2/2] Syncing Android platform files (FAIMS flow: webapp-sync -- android)"
pnpm run webapp-sync -- android

echo
echo "Android project synced successfully."
echo "Next: open ${APP_DIR}/android in Android Studio and build APK/AAB."
