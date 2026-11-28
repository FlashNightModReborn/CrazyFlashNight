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

    export interface InputAtom {
        readonly bit: number; // Converted from wire actionBit to the legacy mask layout.
        readonly down: boolean;
    }

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

        reset(mask: number = 0): void {
            this._prevMask = mask;
            this._buf.length = 0;
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
        sample(mask: number, facingRight: boolean, doubleTapDir: number,
               atoms?: readonly InputAtom[]): number[] {
            this._frameCounter++;
            const buf = this._buf;
            buf.length = 0;

            const prevMask = this._prevMask;
            if (atoms && atoms.length > 0) {
                this.appendVersionedEvents(buf, mask, prevMask, facingRight, atoms);
            } else {
                this.appendDirections(buf, mask, facingRight);
                this.appendActionPresses(buf, mask & ~prevMask);
                this.appendShift(buf, mask, facingRight);
            }

            // === 双击检测通道1: doubleTapDir 边沿（KeyManager 逻辑帧）===
            const prevDir = this._prevDoubleTapDir;
            if (doubleTapDir !== 0 && prevDir === 0) {
                if (facingRight) {
                    buf.push(doubleTapDir > 0 ? EV_DOUBLE_TAP_FORWARD : EV_DOUBLE_TAP_BACK);
                } else {
                    buf.push(doubleTapDir < 0 ? EV_DOUBLE_TAP_FORWARD : EV_DOUBLE_TAP_BACK);
                }
            }

            // Fallback consumes horizontal changes at the same logical-frame timestamp.
            if (atoms && atoms.length > 0) this.replayFallback(buf, mask, facingRight, atoms);
            else this.appendFallback(buf, mask, facingRight);

            this._prevMask = mask;
            this._prevDoubleTapDir = doubleTapDir;

            return buf;
        }

        private replayFallback(buf: number[], mask: number, facingRight: boolean,
                               atoms: readonly InputAtom[]): void {
            const horizontal = BIT_LEFT | BIT_RIGHT;
            let touched = 0;
            let levels = mask;
            for (const atom of atoms) {
                if (!(atom.bit & horizontal) || (touched & atom.bit)) continue;
                touched |= atom.bit;
                levels = atom.down ? levels & ~atom.bit : levels | atom.bit;
            }
            this.appendFallback(buf, levels, facingRight);
            if (touched === 0) return;

            for (const atom of atoms) {
                if (!(atom.bit & horizontal)) continue;
                levels = atom.down ? levels | atom.bit : levels & ~atom.bit;
                this.appendFallback(buf, levels, facingRight);
            }
        }

        private appendFallback(buf: number[], mask: number, facingRight: boolean): void {
            const holdForward = (mask & (facingRight ? BIT_RIGHT : BIT_LEFT)) !== 0;
            const holdBack = (mask & (facingRight ? BIT_LEFT : BIT_RIGHT)) !== 0;
            const frame = this._frameCounter;

            if (holdForward && !this._prevHoldForward) {
                if (frame - this._lastForwardFrame <= this._doubleTapWindow) {
                    buf.push(EV_DOUBLE_TAP_FORWARD);
                    this._lastForwardFrame = -100;
                }
            }
            if (!holdForward && this._prevHoldForward) this._lastForwardFrame = frame;

            if (holdBack && !this._prevHoldBack) {
                if (frame - this._lastBackFrame <= this._doubleTapWindow) {
                    buf.push(EV_DOUBLE_TAP_BACK);
                    this._lastBackFrame = -100;
                }
            }
            if (!holdBack && this._prevHoldBack) this._lastBackFrame = frame;

            this._prevHoldForward = holdForward;
            this._prevHoldBack = holdBack;
        }

        private appendVersionedEvents(buf: number[], mask: number, prevMask: number,
                                      facingRight: boolean, atoms: readonly InputAtom[]): void {
            let touched = 0;
            let pressed = 0;
            let initialDown = 0;
            let hasPulse = false;
            for (const atom of atoms) {
                if (touched & atom.bit) {
                    hasPulse = true;
                } else if (!atom.down) {
                    initialDown |= atom.bit;
                }
                touched |= atom.bit;
                if (atom.down) pressed |= atom.bit;
            }

            // For ordinary snapshots keep the original direction, A/B/C, Shift order.
            // Bits represented by atoms never also contribute a rising mask edge.
            const inferredPresses = mask & ~prevMask & ~touched;
            if (!hasPulse) {
                this.appendDirections(buf, mask, facingRight);
                this.appendActionPresses(buf, pressed | inferredPresses);
                this.appendShift(buf, mask, facingRight);
                return;
            }

            // Reconstruct the intra-frame bucket only where the wire supplies edges.
            // Untouched bits use their final levels, and can contribute at most once.
            const directions = BIT_LEFT | BIT_RIGHT | BIT_UP | BIT_DOWN;
            const shiftContext = directions | BIT_SHIFT;
            let levels = (mask & ~touched) | initialDown;
            let lastDirection = -1;
            let lastShiftContext = -1;
            if ((touched & directions) === 0) {
                this.appendDirections(buf, levels, facingRight);
                lastDirection = levels & directions;
            }
            for (const atom of atoms) {
                if (!atom.down) {
                    levels &= ~atom.bit;
                    if (atom.bit & directions) lastDirection = -1;
                    if (atom.bit & shiftContext) lastShiftContext = -1;
                    continue;
                }
                levels |= atom.bit;
                if (atom.bit & directions) {
                    this.appendDirections(buf, levels, facingRight);
                    lastDirection = levels & directions;
                }
                this.appendActionPresses(buf, atom.bit);
                if ((levels & BIT_SHIFT) && (atom.bit & shiftContext)) {
                    this.appendShift(buf, levels, facingRight);
                    lastShiftContext = levels & shiftContext;
                }
            }
            if ((mask & directions) !== lastDirection) this.appendDirections(buf, mask, facingRight);
            this.appendActionPresses(buf, inferredPresses);
            if ((mask & shiftContext) !== lastShiftContext) this.appendShift(buf, mask, facingRight);
        }

        private appendDirections(buf: number[], mask: number, facingRight: boolean): void {
            const holdForward = (mask & (facingRight ? BIT_RIGHT : BIT_LEFT)) !== 0;
            const holdBack = (mask & (facingRight ? BIT_LEFT : BIT_RIGHT)) !== 0;
            const down = (mask & BIT_DOWN) !== 0;
            const up = (mask & BIT_UP) !== 0;
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
        }

        private appendActionPresses(buf: number[], presses: number): void {
            if (presses & BIT_A) buf.push(EV_A_PRESS);
            if (presses & BIT_B) buf.push(EV_B_PRESS);
            if (presses & BIT_C) buf.push(EV_C_PRESS);
        }

        private appendShift(buf: number[], mask: number, facingRight: boolean): void {
            if (!(mask & BIT_SHIFT)) return;
            const holdForward = (mask & (facingRight ? BIT_RIGHT : BIT_LEFT)) !== 0;
            const holdBack = (mask & (facingRight ? BIT_LEFT : BIT_RIGHT)) !== 0;
            buf.push(EV_SHIFT_HOLD);
            if (holdForward) buf.push(EV_SHIFT_FORWARD);
            if (holdBack) buf.push(EV_SHIFT_BACK);
            if (mask & BIT_DOWN) buf.push(EV_SHIFT_DOWN);
            if ((mask & BIT_UP) && holdForward) buf.push(EV_SHIFT_UP_FORWARD);
        }
    }
}
