import org.flashNight.naki.DataStructures.SlidingWindowBuffer;

/**
 * FPSVisualization - 帧率数据记录与曲线可视化
 *
 * 职责：
 * - 维护一段长度为 N 的历史帧率滑动窗口（SlidingWindowBuffer）
 * - 维护帧率 min/max/差值缩放参数（用于曲线映射）
 * - 同步记录光照等级曲线（用于在同一画布上叠加显示）
 * - 提供 drawCurve() 绘制函数（逻辑逐字提取自工作版本）
 *
 * 说明：
 * - 为保持行为等价，updateData() 内仍使用“全局最小/最大帧率”+最小差异(minDiff)扩展区间的策略；
 * - drawCurve() 直接操作传入的 canvas(MovieClip)。
 */
class org.flashNight.neur.PerformanceOptimizer.FPSVisualization {

    private var _bufferLength:Number;
    private var _frameRate:Number;

    private var _frameRateBuffer:SlidingWindowBuffer;

    private var _totalFPS:Number;
    private var _minFPS:Number;
    private var _maxFPS:Number;
    private var _minDiff:Number;
    private var _fpsDiff:Number;

    private var _lightLevelData:Array;
    private var _currentHour:Number;
    private var _weatherSystem:Object;

    /**
     * 构造函数
     * @param bufferLength:Number 历史窗口长度（工作版本默认24）
     * @param frameRate:Number 标称帧率（通常30）
     * @param weatherSystem:Object 天气系统（需要提供 当前时间 与 昼夜光照[24]）
     */
    public function FPSVisualization(bufferLength:Number, frameRate:Number, weatherSystem:Object) {
        this._bufferLength = (isNaN(bufferLength) || bufferLength <= 0) ? 24 : bufferLength;
        this._frameRate = (isNaN(frameRate) || frameRate <= 0) ? 30 : frameRate;
        this._weatherSystem = weatherSystem;

        this._frameRateBuffer = new SlidingWindowBuffer(this._bufferLength);
        for (var i:Number = 0; i < this._bufferLength; i++) {
            this._frameRateBuffer.insert(this._frameRate);
        }

        this._totalFPS = 0;
        this._minFPS = this._frameRate;
        this._maxFPS = 0;
        this._minDiff = 5;
        this._fpsDiff = this._minDiff;

        this._lightLevelData = [];
        this._currentHour = null;
    }

    /**
     * 更新帧率数据（提取自 _root.帧计时器.更新帧率数据）
     * @param currentFPS:Number 当前测得帧率
     */
    public function updateData(currentFPS:Number):Void {
        this._frameRateBuffer.insert(currentFPS);

        var currentMin:Number = this._frameRateBuffer.min;
        var currentMax:Number = this._frameRateBuffer.max;
        var currentAvg:Number = this._frameRateBuffer.average;

        this._totalFPS = currentAvg * this._bufferLength;

        if (currentMax > this._maxFPS) this._maxFPS = currentMax;
        if (currentMin < this._minFPS) this._minFPS = currentMin;

        if (this._maxFPS - this._minFPS < this._minDiff) {
            var delta:Number = (this._minDiff - (this._maxFPS - this._minFPS)) / 2;
            this._minFPS -= delta;
            this._maxFPS += delta;
            this._fpsDiff = this._minDiff;
        } else {
            this._fpsDiff = this._maxFPS - this._minFPS;
        }

        // 光照数据处理（保持工作版本逻辑）
        if (this._weatherSystem != null && this._weatherSystem.当前时间 != undefined) {
            var startHour:Number = Math.floor(this._weatherSystem.当前时间);
            if (this._currentHour !== startHour) {
                this._lightLevelData = [];
                this._currentHour = startHour;
                for (var i:Number = 0; i < this._bufferLength; i++) {
                    this._lightLevelData.push(this._weatherSystem.昼夜光照[(startHour + i) % 24]);
                }
            }
        }
    }

    /**
     * 绘制帧率曲线（提取自 _root.帧计时器.绘制帧率曲线）
     * @param canvas:MovieClip 画布 MovieClip
     * @param performanceLevel:Number 当前性能等级（用于决定颜色）
     */
    public function drawCurve(canvas:MovieClip, performanceLevel:Number):Void {
        var height:Number = 14;
        var width:Number = 72;
        var stepLen:Number = width / this._bufferLength;

        canvas._x = 2;
        canvas._y = 2;
        canvas.clear();

        // 光照等级曲线
        var lightColor:Number = 0x333333;
        canvas.beginFill(lightColor, 100);
        var lightStepHeight:Number = height / 9;
        var x0:Number = 0;
        var y0:Number = height - (this._lightLevelData[0] * lightStepHeight);

        canvas.moveTo(x0, height);
        canvas.lineTo(x0, y0);

        for (var i:Number = 1; i < this._bufferLength; i++) {
            var x1:Number = x0 + stepLen;
            var y1:Number = height - (this._lightLevelData[i] * lightStepHeight);
            canvas.curveTo((x0 + x1) / 2, (y0 + y1) / 2, x1, y1);
            x0 = x1;
            y0 = y1;
        }

        canvas.lineTo(x0, height);
        canvas.endFill();

        // 帧率曲线颜色根据性能等级变化
        var fpsLineColor:Number;
        switch (performanceLevel) {
            case 0:
                fpsLineColor = 0x00FF00;
                break;
            case 1:
                fpsLineColor = 0x00CCFF;
                break;
            case 2:
                fpsLineColor = 0xFFFF00;
                break;
            default:
                fpsLineColor = 0xFF0000;
        }
        canvas.lineStyle(1.5, fpsLineColor, 100);

        // 绘制帧率曲线
        var fpsStepHeight:Number = height / this._fpsDiff;
        var startX:Number = 0;
        var startY:Number = height - ((this._frameRateBuffer.min <= 0) ? 0 : (this._frameRateBuffer.min - this._minFPS) * fpsStepHeight);

        canvas.moveTo(startX, startY);

        var self = this;
        this._frameRateBuffer.forEach(function(value:Number):Void {
            var x1:Number = startX + stepLen;
            var y1:Number = height - ((value - self._minFPS) * fpsStepHeight);

            canvas.curveTo((startX + x1) / 2, (startY + y1) / 2, x1, y1);

            startX = x1;
            startY = y1;
        });
    }

    public function getBuffer():SlidingWindowBuffer { return this._frameRateBuffer; }
    public function getBufferLength():Number { return this._bufferLength; }

    public function setWeatherSystem(weatherSystem:Object):Void { this._weatherSystem = weatherSystem; }
    public function getWeatherSystem():Object { return this._weatherSystem; }

    public function getMinFPS():Number { return this._minFPS; }
    public function getMaxFPS():Number { return this._maxFPS; }
    public function getFPSDiff():Number { return this._fpsDiff; }
    public function getTotalFPS():Number { return this._totalFPS; }
}
