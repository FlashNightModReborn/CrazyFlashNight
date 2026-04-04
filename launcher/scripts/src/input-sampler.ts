/**
 * InputSampler - 输入采样器 (镜像 AS2 InputSampler.as)
 *
 * 职责：将 8-bit bitmask + 朝向 + doubleTapDir 转换为 InputEvent[] 列表。
 * 帧制语义：双击检测用帧计数器 + 帧间隔窗口（与 AS2 一致，不用 ms）。
 *
 * Bitmask bit 分配:
 *   0=左 1=右 2=上 3=下 4=A 5=B 6=C 7=Shift
 */
namespace GameInput {

    // Bitmask bit constants
    const BIT_LEFT  = 1;
    const BIT_RIGHT = 2;
    const BIT_UP    = 4;
    const BIT_DOWN  = 8;
    const BIT_A     = 16;
    const BIT_B     = 32;
    const BIT_C     = 64;
    const BIT_SHIFT = 128;

    export class InputSampler {
        // 上一帧状态（边沿检测）
        private _prevMask: number = 0;
        private _prevDoubleTapDir: number = 0;

        // 帧级双击检测状态
        private _frameCounter: number = 0;
        private _lastForwardFrame: number = -100;
        private _lastBackFrame: number = -100;
        private _doubleTapWindow: number = 12; // ~400ms @30fps

        // 上一帧归一化方向（用于帧级双击边沿）
        private _prevHoldForward: boolean = false;
        private _prevHoldBack: boolean = false;

        // 事件缓冲（复用）
        private _buf: number[] = [];

        reset(): void {
            this._prevMask = 0;
            this._prevDoubleTapDir = 0;
            this._frameCounter = 0;
            this._lastForwardFrame = -100;
            this._lastBackFrame = -100;
            this._prevHoldForward = false;
            this._prevHoldBack = false;
        }

        /**
         * 采样本帧输入，返回事件列表
         *
         * @param mask 当前帧 8-bit bitmask（AS2 Key.isDown() 生成）
         * @param facingRight 角色面向右=true
         * @param doubleTapDir -1/0/1（KeyManager 写入的双击方向）
         * @returns InputEvent ID 数组
         */
        sample(mask: number, facingRight: boolean, doubleTapDir: number): number[] {
            this._frameCounter++;
            const buf = this._buf;
            buf.length = 0;

            const prevMask = this._prevMask;

            // 解码 bitmask
            const left  = (mask & BIT_LEFT) !== 0;
            const right = (mask & BIT_RIGHT) !== 0;
            const up    = (mask & BIT_UP) !== 0;
            const down  = (mask & BIT_DOWN) !== 0;
            const keyA  = (mask & BIT_A) !== 0;
            const keyB  = (mask & BIT_B) !== 0;
            const keyC  = (mask & BIT_C) !== 0;
            const shift = (mask & BIT_SHIFT) !== 0;

            const prevA = (prevMask & BIT_A) !== 0;
            const prevB = (prevMask & BIT_B) !== 0;
            const prevC = (prevMask & BIT_C) !== 0;

            // 方向归一化
            const holdForward = facingRight ? right : left;
            const holdBack    = facingRight ? left  : right;

            // === 方向事件（复合优先）===
            if (down && holdForward) {
                buf.push(EV_DOWN_FORWARD);
            } else if (down && holdBack) {
                buf.push(EV_DOWN_BACK);
            } else if (up && holdForward) {
                buf.push(EV_UP_FORWARD);
            } else if (up && holdBack) {
                buf.push(EV_UP_BACK);
            } else {
                if (down) buf.push(EV_DOWN);
                if (up) buf.push(EV_UP);
                if (holdForward) buf.push(EV_FORWARD);
                if (holdBack) buf.push(EV_BACK);
            }

            // === 按键边沿检测（按下瞬间）===
            if (keyA && !prevA) buf.push(EV_A_PRESS);
            if (keyB && !prevB) buf.push(EV_B_PRESS);
            if (keyC && !prevC) buf.push(EV_C_PRESS);

            // === Shift 组合事件 ===
            if (shift) {
                buf.push(EV_SHIFT_HOLD);
                if (holdForward) buf.push(EV_SHIFT_FORWARD);
                if (holdBack)    buf.push(EV_SHIFT_BACK);
                if (down)        buf.push(EV_SHIFT_DOWN);
            }

            // === 双击检测通道1: doubleTapDir 边沿（KeyManager 毫秒级）===
            const prevDir = this._prevDoubleTapDir;
            if (doubleTapDir !== 0 && prevDir === 0) {
                if (facingRight) {
                    buf.push(doubleTapDir > 0 ? EV_DOUBLE_TAP_FORWARD : EV_DOUBLE_TAP_BACK);
                } else {
                    buf.push(doubleTapDir < 0 ? EV_DOUBLE_TAP_FORWARD : EV_DOUBLE_TAP_BACK);
                }
            }

            // === 双击检测通道2: 帧级 fallback（镜像 InputSampler.as:256-283）===
            const frame = this._frameCounter;

            // 前方向
            if (holdForward && !this._prevHoldForward) {
                if (frame - this._lastForwardFrame <= this._doubleTapWindow) {
                    buf.push(EV_DOUBLE_TAP_FORWARD);
                    this._lastForwardFrame = -100;
                }
            }
            if (!holdForward && this._prevHoldForward) {
                this._lastForwardFrame = frame;
            }

            // 后方向
            if (holdBack && !this._prevHoldBack) {
                if (frame - this._lastBackFrame <= this._doubleTapWindow) {
                    buf.push(EV_DOUBLE_TAP_BACK);
                    this._lastBackFrame = -100;
                }
            }
            if (!holdBack && this._prevHoldBack) {
                this._lastBackFrame = frame;
            }

            // === 更新 prev 状态 ===
            this._prevMask = mask;
            this._prevDoubleTapDir = doubleTapDir;
            this._prevHoldForward = holdForward;
            this._prevHoldBack = holdBack;

            return buf;
        }
    }
}
