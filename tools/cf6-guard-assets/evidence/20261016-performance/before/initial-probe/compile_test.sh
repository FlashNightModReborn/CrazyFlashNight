#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 透传参数，例如 -TimeoutSeconds 120（慢 CPU / 低压平板编译更久时调大）
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/compile_test.ps1" "$@"
