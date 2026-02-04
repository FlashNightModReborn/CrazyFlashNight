/**
 * PerformanceLogger - 低开销性能日志（环形缓冲区）
 *
 * 设计目标：
 * - 默认不挂载到 PerformanceScheduler（scheduler._logger 为 null）时零开销；
 * - 挂载后也尽量避免对象分配：用预分配的数组做 ring buffer；
 * - 记录结构化数据（数值为主），便于后续离线分析/自优化模块使用。
 *
 * 使用方式（示例）：
 *   var logger = new org.flashNight.neur.PerformanceOptimizer.PerformanceLogger(256);
 *   _root.帧计时器.scheduler.setLogger(logger);
 *
 * 注意：
 * - dump/toCSV 属于重操作，仅用于调试/手动导出，不应在每帧/每次采样中调用。
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceLogger {

    public static var EVT_SAMPLE:Number        = 1;
    public static var EVT_LEVEL_CHANGED:Number = 2;
    public static var EVT_MANUAL_SET:Number    = 3;
    public static var EVT_SCENE_CHANGED:Number = 4;

    private var _enabled:Boolean;
    private var _capacity:Number;
    private var _size:Number;
    private var _cursor:Number;

    // 采用“列存”避免每条记录创建对象
    private var _t:Array;    // timeMs
    private var _evt:Array;  // event type
    private var _a:Array;    // payload a
    private var _b:Array;    // payload b
    private var _c:Array;    // payload c
    private var _d:Array;    // payload d
    private var _s:Array;    // payload string（仅少数事件使用，如 quality）

    public function PerformanceLogger(capacity:Number) {
        if (isNaN(capacity) || capacity <= 0) capacity = 256;
        this._capacity = Math.floor(capacity);
        this._enabled = true;
        this.clear();
        this._initBuffers();
    }

    private function _initBuffers():Void {
        this._t = new Array(this._capacity);
        this._evt = new Array(this._capacity);
        this._a = new Array(this._capacity);
        this._b = new Array(this._capacity);
        this._c = new Array(this._capacity);
        this._d = new Array(this._capacity);
        this._s = new Array(this._capacity);
    }

    public function setEnabled(enabled:Boolean):Void { this._enabled = enabled; }
    public function isEnabled():Boolean { return this._enabled; }

    public function getCapacity():Number { return this._capacity; }
    public function getSize():Number { return this._size; }

    public function clear():Void {
        this._size = 0;
        this._cursor = 0;
    }

    private function _write(evt:Number, timeMs:Number, a:Number, b:Number, c:Number, d:Number, s:String):Void {
        var i:Number = this._cursor;
        this._t[i] = timeMs;
        this._evt[i] = evt;
        this._a[i] = a;
        this._b[i] = b;
        this._c[i] = c;
        this._d[i] = d;
        this._s[i] = s;

        i++;
        if (i >= this._capacity) i = 0;
        this._cursor = i;
        if (this._size < this._capacity) this._size++;
    }

    // ------------------------------------------------------------
    // Scheduler hooks（仅在 scheduler 内部采样点调用）
    // ------------------------------------------------------------

    /**
     * 采样点记录：闭环采样窗口结束时的一次观测/估计/控制输出
     * @param timeMs:Number 时间戳（ms）
     * @param level:Number 当前性能等级
     * @param actualFPS:Number 区间平均 FPS
     * @param denoisedFPS:Number 滤波后的 FPS
     * @param pidOutput:Number PID 连续输出
     */
    public function sample(timeMs:Number, level:Number, actualFPS:Number, denoisedFPS:Number, pidOutput:Number):Void {
        if (!this._enabled) return;
        this._write(EVT_SAMPLE, timeMs, level, actualFPS, denoisedFPS, pidOutput, null);
    }

    /**
     * 档位切换记录：只有当迟滞确认通过并实际执行切档时调用
     */
    public function levelChanged(timeMs:Number, oldLevel:Number, newLevel:Number, actualFPS:Number, quality:String):Void {
        if (!this._enabled) return;
        this._write(EVT_LEVEL_CHANGED, timeMs, oldLevel, newLevel, actualFPS, 0, quality);
    }

    /**
     * 前馈手动设置记录
     */
    public function manualSet(timeMs:Number, level:Number, holdSec:Number):Void {
        if (!this._enabled) return;
        this._write(EVT_MANUAL_SET, timeMs, level, holdSec, 0, 0, null);
    }

    /**
     * 场景切换记录
     */
    public function sceneChanged(timeMs:Number):Void {
        if (!this._enabled) return;
        this._write(EVT_SCENE_CHANGED, timeMs, 0, 0, 0, 0, null);
    }

    // ------------------------------------------------------------
    // Debug / export helpers（重操作，按需调用）
    // ------------------------------------------------------------

    /**
     * 导出为 CSV 文本（最近 maxRows 条，按时间顺序）
     */
    public function toCSV(maxRows:Number):String {
        if (maxRows == undefined || maxRows <= 0) maxRows = this._size;
        maxRows = Math.min(maxRows, this._size);

        var out:String = "timeMs,evt,a,b,c,d,s\n";
        var start:Number = this._cursor - maxRows;
        if (start < 0) start += this._capacity;

        for (var k:Number = 0; k < maxRows; k++) {
            var i:Number = start + k;
            if (i >= this._capacity) i -= this._capacity;
            out += this._t[i] + "," + this._evt[i] + "," + this._a[i] + "," + this._b[i] + "," +
                   this._c[i] + "," + this._d[i] + "," + (this._s[i] == null ? "" : this._s[i]) + "\n";
        }
        return out;
    }

    public function dump(maxRows:Number):Void {
        var csv:String = this.toCSV(maxRows);
        if(_root.服务器 != undefined) {
            _root.服务器.发布服务器消息(this.toCSV(maxRows));
        }
        else {
            trace(csv);
        }
    }
}

