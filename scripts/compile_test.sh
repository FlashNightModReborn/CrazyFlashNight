#!/bin/bash
# compile_test.sh - Agent 自动编译触发脚本
# 前提条件：
#   1. 运行过 setup_compile_env.bat（一次性）
#   2. 已导入 CompileTriggerTask 计划任务（一次性）
#   3. Flash CS6 已运行且 TestLoader 已打开

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- 加载环境配置 ----
ENV_FILE="$SCRIPT_DIR/compile_env.sh"
if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] 环境未配置，请先运行 scripts/setup_compile_env.bat"
    exit 1
fi
source "$ENV_FILE"

# ---- 清理旧状态 ----
rm -f "$MARKER" "$ERROR_MARKER" 2>/dev/null

# ---- 通过计划任务触发编译 ----
echo "[INFO] 触发编译..."
powershell -Command "Start-ScheduledTask -TaskName 'CompileTriggerTask'" 2>/dev/null

# ---- 等待完成（最多 30 秒）----
for i in $(seq 1 30); do
    if [ -f "$MARKER" ]; then
        echo "[OK] 编译完成 (${i}s)"
        rm -f "$MARKER"

        # 读取 trace 输出
        if [ -f "$FLASH_LOG" ]; then
            echo "=== FLASH TRACE OUTPUT ==="
            cat "$FLASH_LOG"
            echo "=== END ==="
            cp "$FLASH_LOG" "$SCRIPTS_DIR/flashlog.txt" 2>/dev/null
        else
            echo "[INFO] 无 trace 输出 (publish 模式不执行 trace)"
        fi
        exit 0
    fi

    if [ -f "$ERROR_MARKER" ]; then
        echo "[ERROR] 编译失败:"
        cat "$ERROR_MARKER"
        rm -f "$ERROR_MARKER"
        exit 1
    fi

    sleep 1
done

echo "[TIMEOUT] 30 秒未完成，可能原因："
echo "  - Flash CS6 未运行"
echo "  - TestLoader 未在 Flash 中打开"
echo "  - CompileTriggerTask 计划任务未导入"
exit 1
