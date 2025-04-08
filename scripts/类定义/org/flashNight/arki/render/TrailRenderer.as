class org.flashNight.arki.render.TrailRenderer
{
    // 单例引用
    private static var _instance:TrailRenderer;

    // 拖影样式表
    private var _styles:Object;

    // 轨迹记录表：按发射者ID（影片剪辑名等）区分
    private var _trackRecords:Object;

    // 最大历史帧数，用于控制拖尾点数量
    private var _maxFrames:Number;

    /**
     * 构造函数为私有，仅允许 getInstance() 获取单例
     */
    private function TrailRenderer() {
        _initStyles();
        _trackRecords = {};
        _maxFrames = 5; // 默认最大帧数，可根据需要在此修改
    }

    /**
     * 获取单例
     */
    public static function getInstance():TrailRenderer {
        if (_instance == null) {
            _instance = new TrailRenderer();
        }
        return _instance;
    }

    /**
     * 初始化可用的拖影样式
     */
    private function _initStyles():Void {
        _styles = {
            预设: {
                颜色: 0xFFFFFF,
                线条颜色: 0xFFFFFF,
                线条宽度: 2,
                填充透明度: 100,
                线条透明度: 100
            },
            白色蓝框: {
                颜色: 0xFFFFFF,
                线条颜色: 0x4FB6FF,
                线条宽度: 2,
                填充透明度: 50,
                线条透明度: 50
            },
            红色透明: {
                颜色: 0xFF6666,
                线条颜色: 0xFF6666,
                线条宽度: 2,
                填充透明度: 50,
                线条透明度: 50
            },
            蓝色魅影: {
                颜色: 0x4DE6FF,
                线条颜色: 0x4FB6FF,
                线条宽度: 2,
                填充透明度: 50,
                线条透明度: 50
            },
            蓝色幽灵: {
                颜色: 0x74EBFF,
                线条颜色: 0x74EBFF,
                线条宽度: 2,
                填充透明度: 25,
                线条透明度: 25
            }
        };
    }

    /**
     * 外部入口：添加新的刀口/发射者拖影数据，并进行渲染
     * @param emitterId   唯一标识（比如：影片剪辑._name）
     * @param edgeArray   [{edge1:{x,y}, edge2:{x,y}}, ...]
     * @param styleName   拖影样式名称（如 "预设"、"白色蓝框" 等）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void {
        var currentFrame:Number = _root.帧计时器.当前帧数;
        
        // 若首次出现，初始化记录
        if (!this._trackRecords[emitterId]) {
            this._trackRecords[emitterId] = { _lastFrame: currentFrame };
            for (var i:Number = 0; i < edgeArray.length; i++) {
                this._trackRecords[emitterId][i] = {
                    edge1: [ edgeArray[i].edge1 ],
                    edge2: [ edgeArray[i].edge2 ]
                };
            }
            return;
        }

        var record:Object = this._trackRecords[emitterId];
        
        // 若中断超过30帧，清空历史，防止出现长时间静止后忽然拖尾“抖动”
        if (currentFrame - record._lastFrame > 30) {
            for (var j:Number = 0; j < edgeArray.length; j++) {
                record[j] = {
                    edge1: [ edgeArray[j].edge1 ],
                    edge2: [ edgeArray[j].edge2 ]
                };
            }
            record._lastFrame = currentFrame;
            return;
        }

        // 更新轨迹信息（加入本帧刀口点）
        for (var k:Number = 0; k < edgeArray.length; k++) {
            if (!record[k]) {
                record[k] = { edge1: [], edge2: [] };
            }
            record[k].edge1.push(edgeArray[k].edge1);
            record[k].edge2.push(edgeArray[k].edge2);
            // 控制历史帧数量
            if (record[k].edge1.length > this._maxFrames) record[k].edge1.shift();
            if (record[k].edge2.length > this._maxFrames) record[k].edge2.shift();
        }

        // 进行拖影绘制
        this._renderTrails(record, edgeArray, styleName, currentFrame);

        // 更新最后活跃帧
        record._lastFrame = currentFrame;
    }

    /**
     * 核心渲染逻辑：平滑轨迹并调用残影系统绘制
     */
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void {
        for (var i:Number = 0; i < edgeArray.length; i++) {
            var traj:Object = record[i];
            if (traj.edge1.length < 2 || traj.edge2.length < 2) {
                continue;
            }

            // 每3帧进行一次平滑处理
            if (currentFrame % 3 == 0) {
                this._simpleSmooth(traj.edge1);
                this._simpleSmooth(traj.edge2);
            }

            // 相邻两帧构成四边形并绘制
            for (var j:Number = 0; j < traj.edge1.length - 1; j++) {
                var ptE1A:Object = traj.edge1[j];
                var ptE1B:Object = traj.edge1[j+1];
                var ptE2A:Object = traj.edge2[j];
                var ptE2B:Object = traj.edge2[j+1];

                // 指数衰减控制透明度
                var alphaFactor:Number = 100 * Math.pow(0.7, j);

                var quadPoints:Array = [
                    { x: ptE1A.x, y: ptE1A.y },
                    { x: ptE1B.x, y: ptE1B.y },
                    { x: ptE2B.x, y: ptE2B.y },
                    { x: ptE2A.x, y: ptE2A.y }
                ];
                this._drawQuad(quadPoints, styleName, alphaFactor);
            }
        }
    }

    /**
     * 简单平滑：对轨迹点做移动平均，减少抖动
     */
    private function _simpleSmooth(points:Array):Void {
        if (points.length < 3) return;
        for (var i:Number = 1; i < points.length - 1; i++) {
            points[i].x = (points[i - 1].x + points[i].x + points[i + 1].x) / 3;
            points[i].y = (points[i - 1].y + points[i].y + points[i + 1].y) / 3;
        }
    }

    /**
     * 绘制一个四边形到残影系统
     */
    private function _drawQuad(quadPoints:Array, styleName:String, alphaValue:Number):Void {
        var style:Object = _styles[styleName];
        if (!style) {
            style = _styles["预设"]; // 若找不到，使用默认预设
        }
        // 最终透明度 = 样式原始透明度 * 动态衰减系数
        var fillAlpha:Number = style.填充透明度 * (alphaValue / 100);
        var lineAlpha:Number = style.线条透明度 * (alphaValue / 100);

        // 交给残影系统做实际绘制（合批、渲染优化等由其内部实现）
        _root.残影系统.绘制形状(
            quadPoints,
            style.颜色,
            style.线条颜色,
            style.线条宽度,
            fillAlpha,
            lineAlpha
        );
    }

    /**
     * 清理内部记录，避免长时间闲置对象堆积
     * @param forceCleanAll     是否强制清空所有（默认false）
     * @param maxInactiveFrames 判定为闲置的最大帧差（默认300）
     * @return                  被清理对象的数量
     */
    public function cleanMemory(forceCleanAll:Boolean, maxInactiveFrames:Number):Number {
        if (forceCleanAll == undefined) forceCleanAll = false;
        if (maxInactiveFrames == undefined) maxInactiveFrames = 300;

        var currentFrame:Number = _root.帧计时器.当前帧数;
        var cleanedCount:Number = 0;

        for (var emitterId:String in this._trackRecords) {
            var rec:Object = this._trackRecords[emitterId];
            if (forceCleanAll || (currentFrame - rec._lastFrame > maxInactiveFrames)) {
                delete this._trackRecords[emitterId];
                cleanedCount++;
            }
        }

        trace("[TrailRenderer] 已清理 " + cleanedCount + " 个闲置发射者轨迹");
        return cleanedCount;
    }
}
