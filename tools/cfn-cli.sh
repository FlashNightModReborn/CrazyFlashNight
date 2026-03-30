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

# 端口文件（launcher 启动时写入，优先读取）
PORTS_FILE="$PROJECT_ROOT/launcher_ports.json"

# 盲扫候选列表（fallback，与 PortAllocator 种子 "1192433993" 一致）
PORTS=(1192 1924 9243 2433 4339 3399 3993 11924 19243 24339 43399 33993 3000)

discover_port() {
    # 优先从端口文件读取（用 python 解析，容忍任意 JSON 格式）
    if [ -f "$PORTS_FILE" ]; then
        local file_port=$(python -c "import json; print(json.load(open('$PORTS_FILE'))['httpPort'])" 2>/dev/null)
        if [ -n "$file_port" ]; then
            code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                "http://localhost:$file_port/testConnection" \
                -H "Content-Length: 0" --connect-timeout 1 2>/dev/null) || true
            if [ "$code" = "200" ]; then
                echo "$file_port"
                return 0
            fi
        fi
    fi

    # Fallback: 盲扫候选端口
    for port in "${PORTS[@]}"; do
        code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            "http://localhost:$port/testConnection" \
            -H "Content-Length: 0" --connect-timeout 1 2>/dev/null) || true
        if [ "$code" = "200" ]; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

case "${1:-status}" in
    start-bus)
        # 启动 launcher --bus-only 后台进程
        EXE="$PROJECT_ROOT/CRAZYFLASHER7MercenaryEmpire.exe"
        if [ ! -f "$EXE" ]; then
            echo "Error: Launcher EXE not found: $EXE" >&2; exit 1
        fi
        if discover_port > /dev/null 2>&1; then
            echo "Bus already running on port $(discover_port)"
            exit 0
        fi
        "$EXE" --bus-only &
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
        # 优雅关闭：先尝试 /shutdown 端点，fallback 到 taskkill
        PORT=$(discover_port 2>/dev/null) || true
        if [ -n "$PORT" ]; then
            curl -s -X POST "http://localhost:$PORT/shutdown" \
                -H "Content-Length: 0" --connect-timeout 2 2>/dev/null
            echo "Shutdown signal sent"
            sleep 1
        else
            taskkill //IM CRAZYFLASHER7MercenaryEmpire.exe //F 2>/dev/null && echo "Bus killed" || echo "No bus process found"
        fi
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
        PORT=$(discover_port) || { echo "Error: Bus not running" >&2; exit 1; }
        for i in $(seq 1 "$TIMEOUT"); do
            connected=$(curl -s "http://localhost:$PORT/status" 2>/dev/null \
                | grep -o '"socketConnected":true' || true)
            if [ -n "$connected" ]; then
                echo "Socket connected (port $PORT)"
                exit 0
            fi
            sleep 1
        done
        echo "Error: Socket not connected after ${TIMEOUT}s" >&2; exit 1
        ;;

    status|console|toast|log|port)
        # 这些命令需要 bus 已在运行
        PORT=$(discover_port) || { echo "Error: Guardian Launcher not found." >&2; exit 1; }

        case "$1" in
            status)
                curl -s "http://localhost:$PORT/status" | python -m json.tool 2>/dev/null \
                    || curl -s "http://localhost:$PORT/status"
                ;;
            console)
                shift; CMD="$*"
                if [ -z "$CMD" ]; then echo "Usage: cfn-cli console <command>" >&2; exit 1; fi
                SAFE_CMD=$(printf '%s' "$CMD" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))') || { echo "Error: python required for JSON escaping" >&2; exit 1; }
                curl -s -X POST "http://localhost:$PORT/console" \
                    -H "Content-Type: application/json" \
                    -d "{\"command\":$SAFE_CMD}" 2>/dev/null
                echo
                ;;
            toast)
                shift; MSG="$*"
                if [ -z "$MSG" ]; then echo "Usage: cfn-cli toast <message>" >&2; exit 1; fi
                SAFE_MSG=$(printf '%s' "$MSG" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))') || { echo "Error: python required for JSON escaping" >&2; exit 1; }
                curl -s -X POST "http://localhost:$PORT/task" \
                    -H "Content-Type: application/json" \
                    -d "{\"task\":\"toast\",\"payload\":$SAFE_MSG}" 2>/dev/null
                echo
                ;;
            log)
                shift; MSG="$*"
                if [ -z "$MSG" ]; then echo "Usage: cfn-cli log <message>" >&2; exit 1; fi
                curl -s -X POST "http://localhost:$PORT/logBatch" \
                    -d "frame=0&messages=$MSG" 2>/dev/null
                echo "Logged: $MSG"
                ;;
            port)
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
        ;;
esac
