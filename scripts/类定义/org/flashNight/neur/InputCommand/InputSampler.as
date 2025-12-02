import org.flashNight.neur.InputCommand.InputEvent;

/**
 * InputSampler - 输入采样层
 *
 * 负责：
 * 1. 每帧读取键盘状态和角色方向
 * 2. 将原始输入转换为归一化事件（前/后/上/下）
 * 3. 检测边沿事件（按键按下瞬间）
 * 4. 检测复合事件（双击、Shift组合）
 * 5. 输出本帧事件列表供DFA消费
 *
 * 使用方式：
 *   var sampler:InputSampler = new InputSampler();
 *   // 每帧调用
 *   var events:Array = sampler.sample(自机);
 *   dfa.update(自机, events);
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.neur.InputCommand.InputSampler {

    // ========== 边沿检测状态 ==========

    /** 上一帧按键状态 */
    private var prevKeyA:Boolean;
    private var prevKeyB:Boolean;
    private var prevKeyC:Boolean;

    /** 上一帧方向状态（用于检测方向变化） */
    private var prevLeft:Boolean;
    private var prevRight:Boolean;
    private var prevDown:Boolean;
    private var prevUp:Boolean;

    // ========== 双击检测状态 ==========

    /** 双击检测：上次按前的帧号 */
    private var lastForwardFrame:Number;
    /** 双击检测：上次按后的帧号 */
    private var lastBackFrame:Number;
    /** 双击窗口（帧数） */
    private var doubleTapWindow:Number;

    /** 当前帧号（需要外部更新或自增） */
    private var frameCounter:Number;

    // ========== 事件输出缓冲 ==========

    /** 本帧事件列表（复用以减少GC） */
    private var eventBuffer:Array;

    // ========== 构造函数 ==========

    public function InputSampler() {
        this.prevKeyA = false;
        this.prevKeyB = false;
        this.prevKeyC = false;
        this.prevLeft = false;
        this.prevRight = false;
        this.prevDown = false;
        this.prevUp = false;

        this.lastForwardFrame = -100;
        this.lastBackFrame = -100;
        this.doubleTapWindow = 12; // 双击窗口，约0.4秒@30fps
        this.frameCounter = 0;

        this.eventBuffer = [];
    }

    // ========== 核心采样方法 ==========

    /**
     * 采样本帧输入，返回事件列表
     *
     * @param unit 角色对象，需要包含：
     *   - 方向: "左" | "右"
     *   - 左行, 右行, 上行, 下行: Boolean
     *   - 动作A, 动作B: Boolean (攻击/跳跃键)
     *   - doubleTapRunDirection: Number (可选，外部双击检测结果)
     *
     * @return Array of InputEvent IDs
     */
    public function sample(unit:Object):Array {
        this.frameCounter++;
        var events:Array = this.eventBuffer;
        events.length = 0; // 清空复用

        var facingRight:Boolean = (unit.方向 == "右");

        // 读取原始输入
        var left:Boolean  = unit.左行;
        var right:Boolean = unit.右行;
        var down:Boolean  = unit.下行;
        var up:Boolean    = unit.上行;
        var keyA:Boolean  = unit.动作A;
        var keyB:Boolean  = unit.动作B;
        var shift:Boolean = Key.isDown(_root.奔跑键);

        // === 方向归一化 ===
        var holdForward:Boolean = facingRight ? right : left;
        var holdBack:Boolean    = facingRight ? left : right;

        // === 检测方向事件 ===
        // 复合方向优先
        if (down && holdForward) {
            events.push(InputEvent.DOWN_FORWARD);
        } else if (down && holdBack) {
            events.push(InputEvent.DOWN_BACK);
        } else if (up && holdForward) {
            events.push(InputEvent.UP_FORWARD);
        } else if (up && holdBack) {
            events.push(InputEvent.UP_BACK);
        } else {
            // 单方向
            if (down) events.push(InputEvent.DOWN);
            if (up) events.push(InputEvent.UP);
            if (holdForward) events.push(InputEvent.FORWARD);
            if (holdBack) events.push(InputEvent.BACK);
        }

        // === 按键边沿检测（按下瞬间） ===
        if (keyA && !this.prevKeyA) {
            events.push(InputEvent.A_PRESS);
        }
        if (keyB && !this.prevKeyB) {
            events.push(InputEvent.B_PRESS);
        }

        // === Shift组合事件 ===
        if (shift) {
            events.push(InputEvent.SHIFT_HOLD);

            if (holdForward) {
                events.push(InputEvent.SHIFT_FORWARD);
            }
            if (holdBack) {
                events.push(InputEvent.SHIFT_BACK);
            }
            if (down) {
                events.push(InputEvent.SHIFT_DOWN);
            }
        }

        // === 双击检测 ===
        // 优先使用外部双击检测结果
        if (unit.doubleTapRunDirection != undefined && unit.doubleTapRunDirection != 0) {
            var doubleTapDir:Number = unit.doubleTapRunDirection;
            if ((facingRight && doubleTapDir == 1) || (!facingRight && doubleTapDir == -1)) {
                events.push(InputEvent.DOUBLE_TAP_FORWARD);
            } else if ((facingRight && doubleTapDir == -1) || (!facingRight && doubleTapDir == 1)) {
                events.push(InputEvent.DOUBLE_TAP_BACK);
            }
        } else {
            // 内部双击检测（备用）
            this.detectDoubleTap(holdForward, holdBack, events);
        }

        // === 更新上一帧状态 ===
        this.prevKeyA = keyA;
        this.prevKeyB = keyB;
        this.prevLeft = left;
        this.prevRight = right;
        this.prevDown = down;
        this.prevUp = up;

        return events;
    }

    /**
     * 内部双击检测（当外部doubleTapRunDirection不可用时）
     */
    private function detectDoubleTap(holdForward:Boolean, holdBack:Boolean, events:Array):Void {
        var frame:Number = this.frameCounter;

        // 检测前方向释放后再次按下
        if (holdForward) {
            if (frame - this.lastForwardFrame <= this.doubleTapWindow) {
                events.push(InputEvent.DOUBLE_TAP_FORWARD);
                this.lastForwardFrame = -100; // 防止连续触发
            }
        } else if (this.prevRight || this.prevLeft) {
            // 刚释放前方向，记录时间点
            // 注意：这里简化处理，实际需要更精确的边沿检测
        }

        // 后方向类似
        if (holdBack) {
            if (frame - this.lastBackFrame <= this.doubleTapWindow) {
                events.push(InputEvent.DOUBLE_TAP_BACK);
                this.lastBackFrame = -100;
            }
        }
    }

    /**
     * 记录前方向释放时间点（需要在方向释放时调用）
     */
    public function recordForwardRelease():Void {
        this.lastForwardFrame = this.frameCounter;
    }

    /**
     * 记录后方向释放时间点
     */
    public function recordBackRelease():Void {
        this.lastBackFrame = this.frameCounter;
    }

    // ========== 配置方法 ==========

    /**
     * 设置双击窗口（帧数）
     */
    public function setDoubleTapWindow(frames:Number):Void {
        this.doubleTapWindow = frames;
    }

    /**
     * 重置采样器状态
     */
    public function reset():Void {
        this.prevKeyA = false;
        this.prevKeyB = false;
        this.prevKeyC = false;
        this.prevLeft = false;
        this.prevRight = false;
        this.prevDown = false;
        this.prevUp = false;
        this.lastForwardFrame = -100;
        this.lastBackFrame = -100;
        this.eventBuffer.length = 0;
    }

    // ========== 调试方法 ==========

    /**
     * 将事件列表转换为可读字符串
     */
    public function eventsToString(events:Array):String {
        if (events.length == 0) return "(none)";
        return InputEvent.sequenceToString(events);
    }
}
