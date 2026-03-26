#!/bin/bash
# train_cycle.sh — 编译 + 等待 Trainer 完成 + 提取 SUMMARY REPORT
# 用法: bash scripts/train_cycle.sh [wait_seconds]
# 默认等待 70s（编译 ~25s + Trainer ~40s + 缓冲 5s）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLASH_LOG="$APPDATA/Macromedia/Flash Player/Logs/flashlog.txt"
WAIT=${1:-70}

# 清 ASO 缓存（仅 Gobang 相关）
find "$LOCALAPPDATA/Adobe/Flash CS6" -name "*.aso" -path "*/Gobang/*" -delete 2>/dev/null || true
find "$LOCALAPPDATA/Adobe/Flash CS6" -name "*.aso" -path "*/Server/*" -delete 2>/dev/null || true

# 记录 flashlog 当前大小
BEFORE_SIZE=0
if [ -f "$FLASH_LOG" ]; then
    BEFORE_SIZE=$(wc -c < "$FLASH_LOG")
fi

# 触发编译
echo "[CYCLE] Triggering compile..."
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-ScheduledTask -TaskName 'CompileTriggerTask'" 2>/dev/null

# 等待 publish_done.marker
MARKER="$SCRIPT_DIR/publish_done.marker"
for i in $(seq 1 30); do
    if [ -f "$MARKER" ]; then
        echo "[CYCLE] Compile done (${i}s)"
        rm -f "$MARKER"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[CYCLE] TIMEOUT waiting for compile"
        exit 1
    fi
    sleep 1
done

# 等待 Trainer 完成（轮询 SUMMARY REPORT）
echo "[CYCLE] Waiting for Trainer (max ${WAIT}s)..."
TRAINER_WAIT=$((WAIT - 25))
if [ "$TRAINER_WAIT" -lt 30 ]; then TRAINER_WAIT=30; fi

for i in $(seq 1 $TRAINER_WAIT); do
    if [ -f "$FLASH_LOG" ]; then
        if grep -q "SUMMARY REPORT" "$FLASH_LOG" 2>/dev/null; then
            # 确认是新的 SUMMARY（文件大小增长）
            CUR_SIZE=$(wc -c < "$FLASH_LOG")
            if [ "$CUR_SIZE" -gt "$BEFORE_SIZE" ]; then
                echo "[CYCLE] Trainer complete (${i}s after compile)"
                break
            fi
        fi
    fi
    if [ "$i" -eq "$TRAINER_WAIT" ]; then
        echo "[CYCLE] TIMEOUT waiting for Trainer"
        # 仍然输出当前日志
    fi
    sleep 1
done

# 提取结果
echo "===== TRAINER RESULTS ====="
if [ -f "$FLASH_LOG" ]; then
    # 提取测试结果
    grep "Results:.*passed" "$FLASH_LOG" | tail -1
    echo "---"
    # 提取 Trainer 的 PASS/FAIL 行
    grep "\[Trainer\] \[" "$FLASH_LOG" | grep -v "SKIP"
    echo "---"
    # 提取 SUMMARY
    grep -A 20 "SUMMARY REPORT" "$FLASH_LOG" | head -25
fi
echo "===== END RESULTS ====="
