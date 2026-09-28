#!/bin/sh
# CF7 #46：实验性、显式调用的检查器，不安装到 Steam，不修改父环境。
# 必须放在目标 Steam Linux Runtime 内、真正的 proton 入口之前。
# 未指定命令时只做检查；--locale 只影响本次调用及其子进程。
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROBE=${CF7_LOCALE_PROBE:-"$SCRIPT_DIR/locale-probe"}
MODE=check
LOCALE_SET=0
LOCALE_VALUE=
usage() {
    printf '%s\n' 'usage: proton-locale-guard.sh [--locale VALUE] [--check | -- COMMAND ARG...]' >&2
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --locale)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            [ -n "$2" ] || { echo 'locale must not be empty' >&2; exit 2; }
            LOCALE_VALUE=$2; LOCALE_SET=1; shift 2 ;;
        --check)
            shift
            [ "$#" -eq 0 ] || { usage; exit 2; }
            break ;;
        --)
            MODE=exec; shift
            [ "$#" -gt 0 ] || { usage; exit 2; }
            break ;;
        *) usage; exit 2 ;;
    esac
done
[ -x "$PROBE" ] || { echo "native probe unavailable: $PROBE" >&2; exit 2; }
# 原始证据发 stderr，不污染被执行程序的 stdout；非 UTF-8 不是停止采证的理由。
if "$PROBE" --stage before-guard >&2; then :; else
    RC=$?
    case "$RC" in 20|21) : ;; *) exit "$RC" ;; esac
fi
if [ "$LOCALE_SET" -eq 1 ]; then
    # 同时覆盖 Proton 使用的 HOST_LC_ALL 与本次 native 自检的 LC_ALL。
    # 不重命名资源，不碰全局 locale、registry、prefix 或真实存档。
    HOST_LC_ALL=$LOCALE_VALUE
    LC_ALL=$LOCALE_VALUE
    export HOST_LC_ALL LC_ALL
fi
# 对已核对的 Proton 11.0-2 / 10.0-4b 策略做模型检查，不冒充 Wine 实测。
if (
    if [ -n "${HOST_LC_ALL-}" ]; then
        LC_ALL=$HOST_LC_ALL; export LC_ALL
    else
        unset LC_ALL
    fi
    exec "$PROBE" --stage after-proton-policy-model
) >&2; then
    :
else
    RC=$?
    echo "CF7_LOCALE_GATE_REJECT exit=$RC (Wine/game not started by this guard)" >&2
    exit "$RC"
fi
if [ "$MODE" = check ]; then
    echo 'CF7_LOCALE_GATE_PASS_MODEL_ONLY (not Wine or Flash acceptance)' >&2
    exit 0
fi
# 不使用 eval，保留每个参数边界。调用者负责独立 prefix、超时与进程清理。
exec "$@"
