#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/compile_test.ps1"
