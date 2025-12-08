import org.flashNight.neur.InputCommand.InputEvent;
import org.flashNight.neur.InputCommand.InputHistoryBuffer;
 
/**
 * InputSampler - 输入采样层
 *
 * 负责：
 * 1. 每帧读取键盘状态和角色方向
 * 2. 将原始输入转换为归一化事件（前/后/上/下）
 * 3. 检测边沿事件（按键按下瞬间）
 * 4. 检测复合事件（双击、Shift组合）
 * 5. 输出本帧事件列表供DFA消费
 * 6. [v1.1] 可选的历史缓冲区集成
 *
 * 使用方式：
 *   var sampler:InputSampler = new InputSampler();
 *   // 每帧调用
 *   var events:Array = sampler.sample(自机);
 *   dfa.update(自机, events);
 *
 *   // 或使用带历史记录的版本
 *   sampler.enableHistory(64, 30);
 *   var events:Array = sampler.sampleWithHistory(自机);
 *   dfa.updateWithHistory(自机, events);
 *
 * @author FlashNight
 * @version 1.1
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

    /** 上一帧归一化方向状态（用于双击边沿检测） */
    private var prevHoldForward:Boolean;
    private var prevHoldBack:Boolean;

    /** 上一帧 doubleTapRunDirection（用于边沿检测） */
    private var prevDoubleTapRunDirection:Number;

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

    // ========== 历史缓冲区（v1.1 新增）==========

    /** 输入历史缓冲区（可选） */
    private var historyBuffer:InputHistoryBuffer;

    /** 是否启用历史记录 */
    private var historyEnabled:Boolean;

    // ========== 构造函数 ==========

    public function InputSampler() {
        this.prevKeyA = false;
        this.prevKeyB = false;
        this.prevKeyC = false;
        this.prevLeft = false;
        this.prevRight = false;
        this.prevDown = false;
        this.prevUp = false;
        this.prevHoldForward = false;
        this.prevHoldBack = false;
        this.prevDoubleTapRunDirection = 0;

        this.lastForwardFrame = -100;
        this.lastBackFrame = -100;
        this.doubleTapWindow = 12; // 双击窗口，约0.4秒@30fps
        this.frameCounter = 0;

        this.eventBuffer = [];

        // 历史缓冲默认禁用
        this.historyBuffer = null;
        this.historyEnabled = false;
    }

    // ========== 核心采样方法 ==========

    /**
     * 采样本帧输入，返回事件列表
     *
     * @param unit 角色对象，需要包含：
     *   - 方向: "左" | "右"
     *   - 左行, 右行, 上行, 下行: Boolean
     *   - 动作A, 动作B: Boolean (攻击/跳跃键)
     *   - 动作C: Boolean (换弹键，可用于搓招DFA)
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

        // C键（换弹键）边沿检测
        var keyC:Boolean = unit.动作C;
        if (keyC && !this.prevKeyC) {
            events.push(InputEvent.C_PRESS);
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
        // 1. 优先检测 doubleTapRunDirection 的边沿（KeyManager 毫秒级检测，更可靠）
        // 2. 备用帧级检测（处理 KeyManager 未覆盖的场景）
        this.detectDoubleTapFromKeyManager(unit, events, facingRight);
        this.detectDoubleTap(holdForward, holdBack, events, facingRight);

        // === 更新上一帧状态 ===
        this.prevKeyA = keyA;
        this.prevKeyB = keyB;
        this.prevKeyC = keyC;
        this.prevLeft = left;
        this.prevRight = right;
        this.prevDown = down;
        this.prevUp = up;
        this.prevHoldForward = holdForward;
        this.prevHoldBack = holdBack;
        this.prevDoubleTapRunDirection = unit.doubleTapRunDirection || 0;

        return events;
    }

    /**
     * 从 KeyManager 的 doubleTapRunDirection 检测双击边沿
     *
     * KeyManager 基于键盘事件（毫秒级），能检测到帧内的快速双击。
     * 当 doubleTapRunDirection 从 0 变成 ±1 时产出双击事件。
     *
     * 注意：
     * - doubleTapRunDirection 在长按时持续有效，所以只在边沿时触发一次
     * - 面向右时 +1 = 前方向双击，-1 = 后方向双击
     * - 面向左时 -1 = 前方向双击，+1 = 后方向双击
     */
    private function detectDoubleTapFromKeyManager(unit:Object, events:Array, facingRight:Boolean):Void {
        var currentDir:Number = unit.doubleTapRunDirection || 0;
        var prevDir:Number = this.prevDoubleTapRunDirection;

        // 边沿检测：从 0 变成非 0
        if (currentDir != 0 && prevDir == 0) {
            // 根据角色朝向归一化
            if (facingRight) {
                // 面向右：+1 = 双击前，-1 = 双击后
                if (currentDir > 0) {
                    events.push(InputEvent.DOUBLE_TAP_FORWARD);
                } else {
                    events.push(InputEvent.DOUBLE_TAP_BACK);
                }
            } else {
                // 面向左：-1 = 双击前，+1 = 双击后
                if (currentDir < 0) {
                    events.push(InputEvent.DOUBLE_TAP_FORWARD);
                } else {
                    events.push(InputEvent.DOUBLE_TAP_BACK);
                }
            }
        }
    }

    /**
     * 内部双击检测（帧级备用）
     *
     * 检测逻辑：
     * 1. 当前帧按下方向 && 上一帧未按（按下边沿）
     * 2. 距离上次释放该方向的时间 <= doubleTapWindow
     * 3. 触发双击事件，并重置时间戳防止连续触发
     *
     * 释放记录：
     * - 当前帧未按方向 && 上一帧按住（释放边沿）时记录时间戳
     *
     * @param holdForward 当前帧是否按住前方向
     * @param holdBack 当前帧是否按住后方向
     * @param events 事件输出数组
     * @param facingRight 角色是否面向右（用于注释，实际归一化已在外部完成）
     */
    private function detectDoubleTap(holdForward:Boolean, holdBack:Boolean, events:Array, facingRight:Boolean):Void {
        var frame:Number = this.frameCounter;

        // === 前方向双击检测 ===
        // 按下边沿：当前按住 && 上一帧未按
        if (holdForward && !this.prevHoldForward) {
            // 检查是否在双击窗口内
            if (frame - this.lastForwardFrame <= this.doubleTapWindow) {
                events.push(InputEvent.DOUBLE_TAP_FORWARD);
                this.lastForwardFrame = -100; // 消费掉，防止连续触发
            }
        }
        // 释放边沿：当前未按 && 上一帧按住 -> 记录释放时间
        if (!holdForward && this.prevHoldForward) {
            this.lastForwardFrame = frame;
        }

        // === 后方向双击检测 ===
        if (holdBack && !this.prevHoldBack) {
            if (frame - this.lastBackFrame <= this.doubleTapWindow) {
                events.push(InputEvent.DOUBLE_TAP_BACK);
                this.lastBackFrame = -100;
            }
        }
        if (!holdBack && this.prevHoldBack) {
            this.lastBackFrame = frame;
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
        this.prevHoldForward = false;
        this.prevHoldBack = false;
        this.prevDoubleTapRunDirection = 0;
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

    // ========== 历史缓冲区功能（v1.1 新增）==========

    /**
     * 启用输入历史记录
     *
     * @param eventCapacity 事件容量（默认64）
     * @param frameCapacity 帧容量（默认30）
     */
    public function enableHistory(eventCapacity:Number, frameCapacity:Number):Void {
        if (eventCapacity == undefined) eventCapacity = 64;
        if (frameCapacity == undefined) frameCapacity = 30;

        this.historyBuffer = new InputHistoryBuffer(eventCapacity, frameCapacity);
        this.historyEnabled = true;
    }

    /**
     * 禁用输入历史记录
     */
    public function disableHistory():Void {
        this.historyBuffer = null;
        this.historyEnabled = false;
    }

    /**
     * 获取历史缓冲区（用于 updateWithHistory 等方法）
     */
    public function getHistoryBuffer():InputHistoryBuffer {
        return this.historyBuffer;
    }

    /**
     * 检查历史记录是否启用
     */
    public function isHistoryEnabled():Boolean {
        return this.historyEnabled;
    }

    /**
     * 采样并自动追加到历史缓冲区
     *
     * @param unit 角色对象
     * @return 本帧事件数组
     */
    public function sampleWithHistory(unit:Object):Array {
        var events:Array = this.sample(unit);

        if (this.historyEnabled && this.historyBuffer != null) {
            this.historyBuffer.appendFrame(events);
        }

        return events;
    }

    /**
     * 获取最近 N 帧的事件序列
     *
     * @param frameWindow 帧窗口大小
     * @return {sequence:Array, from:Number, to:Number}
     */
    public function getRecentInputs(frameWindow:Number):Object {
        if (!this.historyEnabled || this.historyBuffer == null) {
            return {sequence: [], from: 0, to: 0};
        }

        var seq:Array = this.historyBuffer.getSequence();
        var from:Number = this.historyBuffer.getWindowStart(frameWindow);

        return {
            sequence: seq,
            from: from,
            to: seq.length
        };
    }

    /**
     * 清空历史缓冲区
     */
    public function clearHistory():Void {
        if (this.historyBuffer != null) {
            this.historyBuffer.clear();
        }
    }

    /**
     * 获取历史缓冲区状态信息
     */
    public function getHistoryInfo():Object {
        if (!this.historyEnabled || this.historyBuffer == null) {
            return {enabled: false};
        }

        return {
            enabled: true,
            eventCount: this.historyBuffer.getEventCount(),
            frameCount: this.historyBuffer.getFrameCount(),
            capacity: this.historyBuffer.getCapacityInfo()
        };
    }
}
