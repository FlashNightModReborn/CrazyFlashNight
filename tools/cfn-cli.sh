#!/bin/bash
# cfn-cli — CrazyFlashNight Guardian Launcher CLI
# 用法:
#   cfn-cli status              查看连接状态和 task 清单
#   cfn-cli console <command>   执行 AS2 控制台命令
#   cfn-cli toast <message>     发送 toast 消息
#   cfn-cli log <message>       发送调试日志
#   cfn-cli wait [timeout]      等待 bus 就绪（默认 30s）
#   cfn-cli wait-socket [timeout]  等待 socket 连接（Flash 已连上）
#   cfn-cli start-bus           启动 launcher --bus-only（后台）
#   cfn-cli stop-bus            关闭 bus-only launcher

set -e

# 项目根目录（cfn-cli.sh 在 tools/ 下）
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# launcher_ports.json 是唯一可接受的端点权威。
PORTS_FILE="$PROJECT_ROOT/launcher_ports.json"

read_exact_port() {
    python - "$PROJECT_ROOT" "$PORTS_FILE" <<'PY'
import json, os, stat, sys
root, ports_file = sys.argv[1:3]
try:
    info = os.lstat(ports_file)
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ValueError("ports_not_regular")
    with open(ports_file, "r", encoding="utf-8") as stream:
        ports = json.load(stream)
    pid = ports.get("pid")
    http_port = ports.get("httpPort")
    socket_port = ports.get("socketPort")
    if (type(pid) is not int or pid <= 0
            or type(http_port) is not int or not 1 <= http_port <= 65535
            or type(socket_port) is not int or not 1 <= socket_port <= 65535
            or http_port == socket_port):
        raise ValueError("ports_shape")
    os.kill(pid, 0)
    print(http_port)
except Exception as error:
    print("Error: invalid exact launcher_ports.json: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
}

read_legacy_auth_context() {
    python - "$PROJECT_ROOT" "$PORTS_FILE" <<'PY'
import hashlib, json, os, re, stat, subprocess, sys
root, ports_file = sys.argv[1:3]
try:
    ports_stat = os.lstat(ports_file)
    if not stat.S_ISREG(ports_stat.st_mode) or stat.S_ISLNK(ports_stat.st_mode):
        raise ValueError("ports_not_regular")
    with open(ports_file, "r", encoding="utf-8") as stream:
        ports = json.load(stream)
    pid = ports.get("pid")
    http_port = ports.get("httpPort")
    socket_port = ports.get("socketPort")
    advertised = ports.get("legacyHttpAuthFile")
    if (type(pid) is not int or pid <= 0
            or type(http_port) is not int or not 1 <= http_port <= 65535
            or type(socket_port) is not int or not 1 <= socket_port <= 65535
            or http_port == socket_port
            or not isinstance(advertised, str) or not advertised.strip()):
        raise ValueError("ports_shape")
    os.kill(pid, 0)
    local_app_data = os.environ.get("LOCALAPPDATA")
    if not local_app_data:
        raise ValueError("localappdata_unavailable")
    canonical = os.path.abspath(root).rstrip("\\/").upper()
    root_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:32]
    expected = os.path.abspath(os.path.join(
        local_app_data, "CF7FlashNight", "agent-runtime", "v1",
        root_hash, "legacy-http-credential.json"))
    if os.path.normcase(os.path.abspath(advertised)) != os.path.normcase(expected):
        raise ValueError("credential_path_mismatch")
    credential_stat = os.lstat(expected)
    if (not stat.S_ISREG(credential_stat.st_mode)
            or stat.S_ISLNK(credential_stat.st_mode)):
        raise ValueError("credential_not_regular")
    with open(expected, "r", encoding="utf-8") as stream:
        credential = json.load(stream)
    token = credential.get("token")
    header = credential.get("header")
    ticks = credential.get("processStartUtcTicks")
    capabilities = credential.get("capabilities")
    if (credential.get("v") != 1
            or credential.get("kind") != "legacy_http_automation"
            or credential.get("pid") != pid
            or header != "X-CF7-Automation-Token"
            or not isinstance(credential.get("lifecycleId"), str)
            or not credential.get("lifecycleId")
            or not isinstance(ticks, str)
            or re.fullmatch(r"[1-9][0-9]{15,18}", ticks) is None
            or not isinstance(token, str)
            or re.fullmatch(r"[A-Za-z0-9_-]{43}", token) is None
            or not isinstance(capabilities, list)):
        raise ValueError("credential_shape")
    powershell = os.path.join(
        os.environ.get("SystemRoot", r"C:\Windows"),
        "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    script = (
        '$ErrorActionPreference = "Stop"; '
        f'$processRecord = Get-Process -Id {pid}; '
        '[Console]::Out.Write('
        '$processRecord.StartTime.ToUniversalTime().Ticks.ToString('
        '[Globalization.CultureInfo]::InvariantCulture))')
    actual_ticks = subprocess.run(
        [powershell, "-NoLogo", "-NoProfile", "-NonInteractive",
         "-Command", script],
        check=True, capture_output=True, text=True,
        timeout=5).stdout.strip()
    if actual_ticks != ticks:
        raise ValueError("credential_process_identity_mismatch")
    print(str(http_port) + "|" + header + "|" + token)
except Exception as error:
    print("Error: invalid legacy HTTP credential: " + str(error), file=sys.stderr)
    sys.exit(1)
PY
}

discover_port() {
    [ -f "$PORTS_FILE" ] || return 1
    local context file_port ignored_header ignored_token
    context=$(read_legacy_auth_context) || return 1
    IFS='|' read -r file_port ignored_header ignored_token <<< "$context"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://localhost:$file_port/testConnection" \
        -H "Content-Length: 0" --connect-timeout 1 2>/dev/null) || true
    [ "$code" = "200" ] || return 1
    echo "$file_port"
}

load_authenticated_port() {
    local context
    context=$(read_legacy_auth_context) || return 1
    IFS='|' read -r AUTH_PORT AUTH_HEADER AUTH_TOKEN <<< "$context"
    local public_port
    public_port=$(discover_port) || return 1
    [ "$AUTH_PORT" = "$public_port" ] || {
        echo "Error: credential/launcher_ports.json port mismatch" >&2
        return 1
    }
    PORT="$AUTH_PORT"
}

case "${1:-status}" in
    start-bus)
        # 启动 launcher --bus-only 后台进程
        # 跳过 bootstrap（headless 自动化不要 MessageBox prompt），直接走 Core.exe；
        # Core 是 FDD apphost，要求机器上已装 .NET 10 Desktop Runtime
        # 该命令固定使用 promotion 后的 projectRoot\runtime\ 正式 Core；不扫描 bin/candidate
        EXE="$PROJECT_ROOT/runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe"
        BOOTSTRAP="$PROJECT_ROOT/CRAZYFLASHER7MercenaryEmpire.exe"
        if [ ! -f "$EXE" ]; then
            echo "Error: Launcher Core EXE not found: $EXE" >&2
            echo "  Tip: 正式 runtime 缺失；launcher/build.ps1 只生成隔离 candidate，不能修复部署。请恢复可信正式包或完成 v2 promotion" >&2
            exit 1
        fi
        if [ ! -f "$BOOTSTRAP" ]; then
            echo "Error: Bootstrap integrity probe not found: $BOOTSTRAP" >&2
            exit 1
        fi
        "$BOOTSTRAP" --verify-only
        if [ "$?" -ne 0 ]; then
            echo "Error: Runtime bundle integrity verification failed" >&2
            exit 1
        fi
        if discover_port > /dev/null 2>&1; then
            echo "Bus already running on port $(discover_port)"
            exit 0
        fi
        # Runtime 探测 — 与 launcher/native/bootstrap/bootstrap.cpp ScanOneDotnetRoot 等价：
        #   1. 系统位置 %ProgramFiles%\dotnet 优先 — 命中即跳过 env override（apphost 默认搜得到）
        #   2. user-scope 候选必须含 Microsoft.WindowsDesktop.App.deps.json（防半安装空壳目录）
        # 与 PS 助手 tools/dotnet-runtime-detect.ps1 行为对齐
        _has_valid_runtime() {
            # $1 = dotnet root（Posix 风格路径）。命中输出 root，未命中返回 1。
            local root="$1"
            [ -z "$root" ] && return 1
            local desktop="$root/shared/Microsoft.WindowsDesktop.App"
            [ -d "$desktop" ] || return 1
            for ver in "$desktop"/10.*; do
                [ -d "$ver" ] || continue
                if [ -f "$ver/Microsoft.WindowsDesktop.App.deps.json" ]; then
                    return 0
                fi
            done
            return 1
        }

        _runtime_ok=0
        # 1. 系统位置（与 apphost 默认搜路径一致，命中不设 env）
        SYSTEM_DOTNET="${PROGRAMFILES:-/c/Program Files}/dotnet"
        if _has_valid_runtime "$SYSTEM_DOTNET"; then
            echo "Using system .NET 10 desktop runtime at $SYSTEM_DOTNET (no DOTNET_ROOT override)"
            _runtime_ok=1
        else
            # 2. user-scope 候选（命中必须 export DOTNET_ROOT 让 apphost 找得到）
            for cand in "$LOCALAPPDATA/Microsoft/dotnet" "$USERPROFILE/.dotnet"; do
                [ -z "$cand" ] && continue
                if _has_valid_runtime "$cand"; then
                    WIN_DOTNET_ROOT=$(cygpath -w "$cand" 2>/dev/null || echo "$cand")
                    export DOTNET_ROOT_X64="$WIN_DOTNET_ROOT"
                    export DOTNET_ROOT="$WIN_DOTNET_ROOT"
                    echo "Using user-scope .NET 10 desktop runtime at $WIN_DOTNET_ROOT (DOTNET_ROOT set)"
                    _runtime_ok=1
                    break
                fi
            done
        fi

        if [ "$_runtime_ok" -ne 1 ]; then
            echo "[Error] 未找到带 Microsoft.WindowsDesktop.App.deps.json 的 .NET 10 桌面运行时；" >&2
            echo "        请双击 CRAZYFLASHER7MercenaryEmpire.exe 让 bootstrap 自动安装，或手动" >&2
            echo "        运行 tools/dotnet-runtime/windowsdesktop-runtime-10.*-win-x64.exe" >&2
            exit 1
        fi
        # 显式传 --project-root（Core 在子目录，AppContext.BaseDirectory ≠ projectRoot；不传会走 walk-up fallback）
        # 路径用 Windows 反斜杠（Core 内部 Path.GetFullPath 会规范化）
        WIN_PROJECT_ROOT=$(cygpath -w "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
        "$EXE" --bus-only --project-root "$WIN_PROJECT_ROOT" &
        echo "Bus starting (PID=$!)..."
        # 等待就绪
        for i in $(seq 1 15); do
            sleep 1
            if discover_port > /dev/null 2>&1; then
                echo "Bus ready on port $(discover_port)"
                exit 0
            fi
        done
        echo "Error: Bus failed to start within 15s" >&2; exit 1
        ;;

    stop-bus)
        load_authenticated_port || {
            echo "Error: no authenticated exact bus is available; refusing process-name fallback." >&2
            exit 1
        }
        curl -fsS -X POST "http://localhost:$PORT/shutdown" \
            -H "$AUTH_HEADER: $AUTH_TOKEN" \
            -H "Content-Length: 0" --connect-timeout 2
        echo "Shutdown signal sent"
        sleep 1
        ;;

    wait)
        # 等待 HTTP bus 就绪
        TIMEOUT="${2:-30}"
        for i in $(seq 1 "$TIMEOUT"); do
            if discover_port > /dev/null 2>&1; then
                echo "Bus ready on port $(discover_port)"
                exit 0
            fi
            sleep 1
        done
        echo "Error: Bus not ready after ${TIMEOUT}s" >&2; exit 1
        ;;

    wait-socket)
        # 等待 socket 连接（Flash 客户端已连上）
        TIMEOUT="${2:-60}"
        load_authenticated_port || {
            echo "Error: authenticated exact bus is not running" >&2
            exit 1
        }
        for i in $(seq 1 "$TIMEOUT"); do
            connected=$(curl -fsS "http://localhost:$PORT/status" \
                -H "$AUTH_HEADER: $AUTH_TOKEN" 2>/dev/null \
                | grep -o '"socketConnected":true' || true)
            if [ -n "$connected" ]; then
                echo "Socket connected (port $PORT)"
                exit 0
            fi
            sleep 1
        done
        echo "Error: Socket not connected after ${TIMEOUT}s" >&2; exit 1
        ;;

    task)
        # 调用 /task 端点，主要用于 archive 调试：
        #   cfn-cli task archive list
        #   cfn-cli task archive load <slot>
        #   cfn-cli task archive delete <slot>
        #   cfn-cli task archive shadow <slot>
        shift
        TASK="${1:-}"; OP="${2:-}"; SLOT="${3:-}"
        if [ -z "$TASK" ] || [ -z "$OP" ]; then
            echo "Usage: cfn-cli task <task-name> <op> [slot]" >&2; exit 1
        fi
        load_authenticated_port || {
            echo "Error: authenticated exact Guardian Launcher not found." >&2
            exit 1
        }
        if [ -n "$SLOT" ]; then
            PAYLOAD="{\"op\":\"$OP\",\"slot\":\"$SLOT\"}"
        else
            PAYLOAD="{\"op\":\"$OP\"}"
        fi
        curl -fsS -X POST "http://localhost:$PORT/task" \
            -H "$AUTH_HEADER: $AUTH_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"task\":\"$TASK\",\"payload\":$PAYLOAD}"
        echo
        ;;

    status|console|toast|log|port)
        case "$1" in
            status)
                load_authenticated_port || {
                    echo "Error: authenticated exact Guardian Launcher not found." >&2
                    exit 1
                }
                RESPONSE=$(curl -fsS "http://localhost:$PORT/status" \
                    -H "$AUTH_HEADER: $AUTH_TOKEN")
                printf '%s' "$RESPONSE" | python -m json.tool 2>/dev/null \
                    || printf '%s\n' "$RESPONSE"
                ;;
            console)
                shift; CMD="$*"
                if [ -z "$CMD" ]; then echo "Usage: cfn-cli console <command>" >&2; exit 1; fi
                load_authenticated_port || {
                    echo "Error: authenticated exact Guardian Launcher not found." >&2
                    exit 1
                }
                SAFE_CMD=$(printf '%s' "$CMD" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))') || { echo "Error: python required for JSON escaping" >&2; exit 1; }
                curl -fsS -X POST "http://localhost:$PORT/console" \
                    -H "$AUTH_HEADER: $AUTH_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "{\"command\":$SAFE_CMD}" 2>/dev/null
                echo
                ;;
            toast)
                shift; MSG="$*"
                if [ -z "$MSG" ]; then echo "Usage: cfn-cli toast <message>" >&2; exit 1; fi
                load_authenticated_port || {
                    echo "Error: authenticated exact Guardian Launcher not found." >&2
                    exit 1
                }
                SAFE_MSG=$(printf '%s' "$MSG" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))') || { echo "Error: python required for JSON escaping" >&2; exit 1; }
                curl -fsS -X POST "http://localhost:$PORT/task" \
                    -H "$AUTH_HEADER: $AUTH_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "{\"task\":\"toast\",\"payload\":$SAFE_MSG}" 2>/dev/null
                echo
                ;;
            log)
                shift; MSG="$*"
                if [ -z "$MSG" ]; then echo "Usage: cfn-cli log <message>" >&2; exit 1; fi
                PORT=$(discover_port) || {
                    echo "Error: exact Guardian Launcher not found." >&2
                    exit 1
                }
                # /logBatch remains a public Flash compatibility endpoint.
                curl -s -X POST "http://localhost:$PORT/logBatch" \
                    -d "frame=0&messages=$MSG" 2>/dev/null
                echo "Logged: $MSG"
                ;;
            port)
                PORT=$(discover_port) || {
                    echo "Error: exact Guardian Launcher not found." >&2
                    exit 1
                }
                echo "$PORT"
                ;;
        esac
        ;;

    *)
        echo "cfn-cli — Guardian Launcher CLI"
        echo ""
        echo "Bus lifecycle:"
        echo "  start-bus               Start launcher in --bus-only mode (background)"
        echo "  stop-bus                Stop bus-only launcher"
        echo "  wait [timeout]          Wait for HTTP bus ready (default 30s)"
        echo "  wait-socket [timeout]   Wait for Flash socket connection (default 60s)"
        echo ""
        echo "Commands (require running bus):"
        echo "  status                  Show connection state and task list"
        echo "  console <command>       Execute AS2 console command"
        echo "  toast <message>         Send toast message"
        echo "  log <message>           Send debug log"
        echo "  port                    Print discovered HTTP port"
        echo "  task <name> <op> [slot] POST /task (archive 调试：list/load/delete/shadow)"
        ;;
esac
