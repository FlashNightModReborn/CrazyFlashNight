/**
 * InputEvent - 输入事件常量 (镜像 AS2 InputEvent.as)
 *
 * 搓招系统使用的 18 种输入事件。方向归一化：前/后/上/下，不区分左右。
 */
namespace GameInput {

    // 无事件
    export const EV_NONE              = 0;

    // 方向事件（归一化：前=面向方向，后=背向方向）
    export const EV_FORWARD           = 1;
    export const EV_BACK              = 2;
    export const EV_DOWN              = 3;
    export const EV_UP                = 4;
    export const EV_DOWN_FORWARD      = 5;
    export const EV_DOWN_BACK         = 6;
    export const EV_UP_FORWARD        = 7;
    export const EV_UP_BACK           = 8;

    // 按键边沿事件（按下瞬间触发）
    export const EV_A_PRESS           = 9;
    export const EV_B_PRESS           = 10;
    export const EV_C_PRESS           = 11;

    // 复合事件
    export const EV_DOUBLE_TAP_FORWARD = 12;
    export const EV_DOUBLE_TAP_BACK    = 13;
    export const EV_SHIFT_HOLD         = 14;
    export const EV_SHIFT_FORWARD      = 15;
    export const EV_SHIFT_BACK         = 16;
    export const EV_SHIFT_DOWN         = 17;

    // 字母表大小（DFA 数组分配用）
    export const ALPHABET_SIZE         = 18;

    // 事件名称（调试 + 可视化提示）
    const _names: string[] = [
        "NONE",
        "\u2192",       // →  FORWARD
        "\u2190",       // ←  BACK
        "\u2193",       // ↓  DOWN
        "\u2191",       // ↑  UP
        "\u2198",       // ↘  DOWN_FORWARD
        "\u2199",       // ↙  DOWN_BACK
        "\u2197",       // ↗  UP_FORWARD
        "\u2196",       // ↖  UP_BACK
        "A",            // A_PRESS
        "B",            // B_PRESS
        "C",            // C_PRESS
        "\u2192\u2192", // →→ DOUBLE_TAP_FORWARD
        "\u2190\u2190", // ←← DOUBLE_TAP_BACK
        "Shift",        // SHIFT_HOLD
        "Shift+\u2192", // Shift+→ SHIFT_FORWARD
        "Shift+\u2190", // Shift+← SHIFT_BACK
        "Shift+\u2193"  // Shift+↓ SHIFT_DOWN
    ];

    export function eventName(id: number): string {
        return (id >= 0 && id < _names.length) ? _names[id] : "?";
    }

    export function sequenceToString(events: number[]): string {
        let s = "";
        for (let i = 0; i < events.length; i++) {
            s += eventName(events[i]);
        }
        return s;
    }
}
