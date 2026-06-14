#!/usr/bin/env bash
# CF7 Animate Kit — one-click launcher (macOS / Linux).
# First run installs deps + builds; downloads Electron to TMP; then starts the cockpit.
set -euo pipefail

TOOL_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$TOOL_ROOT"

ELECTRON_VER="35.7.5"
ELECTRON_MAIN="$TOOL_ROOT/packages/web/dist/electron/main.cjs"

# Platform detection
case "$(uname -s)" in
  Darwin*)
    if [ "$(uname -m)" = "arm64" ]; then PLATFORM="darwin-arm64"; else PLATFORM="darwin-x64"; fi
    ELECTRON_BIN_NAME="Electron.app/Contents/MacOS/Electron"
    ;;
  *)
    PLATFORM="linux-x64"
    ELECTRON_BIN_NAME="electron"
    ;;
esac

CACHE_DIR="${TMPDIR:-/tmp}/cf7-electron-v${ELECTRON_VER}"
CACHE_EXE="$CACHE_DIR/dist/$ELECTRON_BIN_NAME"
NPM_EXE="$TOOL_ROOT/node_modules/electron/dist/$ELECTRON_BIN_NAME"
SIBLING_DIST="$TOOL_ROOT/../cf7-packer/node_modules/electron/dist"  # reuse same-version Electron
MIRROR_URL="https://cdn.npmmirror.com/binaries/electron/v${ELECTRON_VER}/electron-v${ELECTRON_VER}-${PLATFORM}.zip"
GITHUB_URL="https://github.com/electron/electron/releases/download/v${ELECTRON_VER}/electron-v${ELECTRON_VER}-${PLATFORM}.zip"

# SHA256 checksums from official Electron SHASUMS256.txt (v35.7.5)
declare -A ELECTRON_SHA256=(
  ["win32-x64"]="b87b2d6167845ece1d373eb37f5ce49868a07ec90203de44b6bd415d6c673c6d"
  ["darwin-x64"]="48a426bb5df999dd46c0700261a1a7f572b17581c4c0d1c28afade5ae600cdc9"
  ["darwin-arm64"]="2fe3a3cfad607a8c1627f6f2bb9834f959c665ef575b663206db11929634b92f"
  ["linux-x64"]="368d155a2189e1056d111d334b712779e77066fce1f5ab935b22c4ef544eaa29"
)
EXPECTED_SHA256="${ELECTRON_SHA256[$PLATFORM]}"

# ═══ Phase 1: npm deps + build (Electron binary downloaded separately below) ═══
if [ ! -d "$TOOL_ROOT/node_modules" ]; then
  echo "[*] Installing dependencies (first run)..."
  ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm install
fi
echo "[*] Building core + an-host + web..."
npm run build -w @cf7-animate-kit/core -w @cf7-animate-kit/an-host -w @cf7-animate-kit/web

# ═══ Phase 2: locate Electron binary ═══
ELECTRON_EXE=""
ELECTRON_DIST=""
if [ -f "$CACHE_EXE" ]; then
  echo "[OK] Electron: TEMP cache"
  ELECTRON_EXE="$CACHE_EXE"; ELECTRON_DIST="$CACHE_DIR/dist"
elif [ -f "$NPM_EXE" ]; then
  echo "[OK] Electron: node_modules"
  ELECTRON_EXE="$NPM_EXE"; ELECTRON_DIST="$TOOL_ROOT/node_modules/electron/dist"
elif [ -f "$SIBLING_DIST/$ELECTRON_BIN_NAME" ] && [ -f "$SIBLING_DIST/version" ] && [ "$(tr -d '[:space:]' < "$SIBLING_DIST/version")" = "$ELECTRON_VER" ]; then
  echo "[OK] Electron: reusing sibling cf7-packer install (v${ELECTRON_VER})"
  ELECTRON_EXE="$SIBLING_DIST/$ELECTRON_BIN_NAME"; ELECTRON_DIST="$SIBLING_DIST"
else
  # ═══ Phase 3: download ═══
  echo "[!] Electron v${ELECTRON_VER} not found, downloading..."
  mkdir -p "$CACHE_DIR"
  ZIP_PATH="$CACHE_DIR/electron.zip"
  download_ok=false

  if [ "$download_ok" = false ] && command -v curl &>/dev/null; then
    echo "    [1/3] curl + npmmirror..."
    if curl -fSL --connect-timeout 15 --max-time 300 --retry 2 -o "$ZIP_PATH" "$MIRROR_URL" 2>/dev/null; then download_ok=true; else rm -f "$ZIP_PATH"; fi
  fi
  if [ "$download_ok" = false ] && command -v curl &>/dev/null; then
    echo "    [2/3] curl + GitHub..."
    if curl -fSL --connect-timeout 15 --max-time 300 --retry 2 -o "$ZIP_PATH" "$GITHUB_URL" 2>/dev/null; then download_ok=true; else rm -f "$ZIP_PATH"; fi
  fi
  if [ "$download_ok" = false ] && command -v wget &>/dev/null; then
    echo "    [3/3] wget + npmmirror..."
    if wget -q --timeout=15 --tries=2 -O "$ZIP_PATH" "$MIRROR_URL" 2>/dev/null; then download_ok=true; else rm -f "$ZIP_PATH"; fi
  fi

  if [ "$download_ok" = true ] && [ -f "$ZIP_PATH" ]; then
    echo "    verifying SHA256..."
    if command -v sha256sum &>/dev/null; then ACTUAL=$(sha256sum "$ZIP_PATH" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then ACTUAL=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
    else echo "    [!] no sha256sum/shasum; skipping"; ACTUAL="$EXPECTED_SHA256"; fi
    if [ "$ACTUAL" != "$EXPECTED_SHA256" ]; then
      echo "[X] SHA256 mismatch (expected $EXPECTED_SHA256, got $ACTUAL)"; rm -f "$ZIP_PATH"; exit 1
    fi
    echo "    verified."
    mkdir -p "$CACHE_DIR/dist"
    unzip -qo "$ZIP_PATH" -d "$CACHE_DIR/dist"
    if [ -f "$CACHE_EXE" ]; then
      chmod +x "$CACHE_EXE"; ELECTRON_EXE="$CACHE_EXE"; ELECTRON_DIST="$CACHE_DIR/dist"
      echo "[OK] Electron v${ELECTRON_VER} ready."
    else rm -f "$ZIP_PATH"; fi
  fi

  if [ -z "$ELECTRON_EXE" ]; then
    echo ""
    echo "[X] All download strategies failed. Manually download:"
    echo "      mirror: $MIRROR_URL"
    echo "      github: $GITHUB_URL"
    echo "    unzip into $CACHE_DIR/dist/ and re-run ./launch.sh"
    exit 1
  fi
fi

# ═══ Phase 4: launch ═══
if [ ! -f "$ELECTRON_MAIN" ]; then echo "[X] main process bundle missing: $ELECTRON_MAIN"; exit 1; fi
export ELECTRON_OVERRIDE_DIST_PATH="$ELECTRON_DIST"
unset ELECTRON_RUN_AS_NODE 2>/dev/null || true
echo "Starting CF7 Animate Kit cockpit..."
"$ELECTRON_EXE" "$ELECTRON_MAIN"
