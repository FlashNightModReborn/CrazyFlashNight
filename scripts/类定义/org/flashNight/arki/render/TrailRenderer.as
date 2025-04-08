import org.flashNight.arki.render.*;

/**
 * TrailRenderer 拖影渲染器（单例）
 * 用于记录并渲染攻击刀口、子弹轨迹等动态残影效果。
 * 支持样式配置、轨迹平滑处理、历史帧限制与自动内存清理。
 */
class org.flashNight.arki.render.TrailRenderer {
    // --- 静态变量 ---
    
    /** TrailRenderer 单例实例 */
    private static var _instance:TrailRenderer;
    
    // --- 成员变量 ---
    
    /** 拖影样式表，按样式名称存储不同的视觉配置 */
    private var _styles:Object;
    
    /** 轨迹记录表，以发射者ID（如影片剪辑名称）为键，记录历史轨迹点 */
    private var _trackRecords:Object;
    
    /** 每条轨迹记录允许保留的最大历史帧数（默认 5） */
    private var _maxFrames:Number;
    
    // --- 构造与初始化 ---
    
    /**
     * 私有构造函数，禁止外部直接创建实例，请使用 getInstance()
     */
    private function TrailRenderer() {
        _initStyles();                // 初始化默认样式
        _trackRecords = {};          // 创建轨迹记录容器
        _maxFrames = 5;              // 默认轨迹历史帧数限制
    }

    /**
     * 获取 TrailRenderer 单例实例（懒汉式创建）
     * @return 单例实例
     */
    public static function getInstance():TrailRenderer {
        if (_instance == null) {
            _instance = new TrailRenderer();
        }
        return _instance;
    }

    /**
     * 初始化可用拖影样式（颜色、透明度、线宽等）
     */
    private function _initStyles():Void {
        _styles = {
            预设: {
                color: 0xFFFFFF,        // 填充颜色
                lineColor: 0xFFFFFF,    // 边框颜色
                lineWidth: 2,           // 边框线宽
                fillOpacity: 100,       // 填充透明度（0~100）
                lineOpacity: 100        // 边框透明度（0~100）
            },
            白色蓝框: {
                color: 0xFFFFFF,
                lineColor: 0x4FB6FF,
                lineWidth: 2,
                fillOpacity: 50,
                lineOpacity: 50
            },
            红色透明: {
                color: 0xFF6666,
                lineColor: 0xFF6666,
                lineWidth: 2,
                fillOpacity: 50,
                lineOpacity: 50
            },
            蓝色魅影: {
                color: 0x4DE6FF,
                lineColor: 0x4FB6FF,
                lineWidth: 2,
                fillOpacity: 50,
                lineOpacity: 50
            },
            蓝色幽灵: {
                color: 0x74EBFF,
                lineColor: 0x74EBFF,
                lineWidth: 2,
                fillOpacity: 25,
                lineOpacity: 25
            }
        };
    }

    // --- 主功能入口 ---

    /**
     * 添加并记录一个发射者当前帧的轨迹数据，并触发渲染
     * @param emitterId   发射者唯一标识（如影片剪辑的 _name）
     * @param edgeArray   边缘点数组：每项包含 edge1 和 edge2 坐标
     * @param styleName   拖影样式名（必须存在于样式表中）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void {
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var record:Object = this._trackRecords[emitterId];
        var i:Number;
        var len:Number = edgeArray.length;
        
        // 第一次出现该发射者，初始化记录结构
        if (!record) {
            record = { _lastFrame: currentFrame };
            for (i = 0; i < len; i++) {
                record[i] = {
                    edge1: [edgeArray[i].edge1],
                    edge2: [edgeArray[i].edge2]
                };
            }
            this._trackRecords[emitterId] = record;
            return;
        }
        
        // 若超过 30 帧未更新，则清空历史轨迹（避免突然移动造成拖影跳变）
        if (currentFrame - record._lastFrame > 30) {
            for (i = 0; i < len; i++) {
                record[i] = {
                    edge1: [edgeArray[i].edge1],
                    edge2: [edgeArray[i].edge2]
                };
            }
            record._lastFrame = currentFrame;
            return;
        }

        // 更新当前轨迹信息，插入新帧数据
        for (i = 0; i < len; i++) {
            var traj:Object = record[i];
            if (!traj) {
                traj = { edge1: [], edge2: [] };
                record[i] = traj;
            }
            traj.edge1.push(edgeArray[i].edge1);
            traj.edge2.push(edgeArray[i].edge2);

            // 控制轨迹点历史长度不超过最大限制
            if (traj.edge1.length > this._maxFrames) traj.edge1.shift();
            if (traj.edge2.length > this._maxFrames) traj.edge2.shift();
        }

        // 执行渲染逻辑
        this._renderTrails(record, edgeArray, styleName, currentFrame);

        // 更新记录的最后活跃帧
        record._lastFrame = currentFrame;
    }

    // --- 核心渲染逻辑 ---

    /**
     * 渲染指定轨迹记录，自动处理平滑和透明衰减
     * @param record         当前发射者的历史轨迹数据
     * @param edgeArray      当前帧边缘数组（用于遍历长度）
     * @param styleName      拖影样式名
     * @param currentFrame   当前帧数（用于控制平滑频率）
     */
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void {
        var len:Number = edgeArray.length;
        var quadPoints:Array = [ {x:0, y:0}, {x:0, y:0}, {x:0, y:0}, {x:0, y:0} ];
        
        for (var i:Number = 0; i < len; i++) {
            var traj:Object = record[i];
            var count:Number = traj.edge1.length;

            // 若不足两帧数据，则无法形成四边形，跳过
            if (count < 2 || traj.edge2.length < 2) continue;

            // 每3帧执行一次轨迹平滑处理（移动平均）
            if (currentFrame % 3 == 0) {
                this._simpleSmooth(traj.edge1);
                this._simpleSmooth(traj.edge2);
            }

            // 遍历相邻帧，绘制四边形残影
            for (var j:Number = 0; j < count - 1; j++) {
                var ptE1A:Object = traj.edge1[j];
                var ptE1B:Object = traj.edge1[j+1];
                var ptE2A:Object = traj.edge2[j];
                var ptE2B:Object = traj.edge2[j+1];

                // 指数衰减，越老的帧越透明
                var alphaFactor:Number = 100 * Math.pow(0.7, j);

                // 准备绘制点（顺时针构成四边形）
                quadPoints[0].x = ptE1A.x; quadPoints[0].y = ptE1A.y;
                quadPoints[1].x = ptE1B.x; quadPoints[1].y = ptE1B.y;
                quadPoints[2].x = ptE2B.x; quadPoints[2].y = ptE2B.y;
                quadPoints[3].x = ptE2A.x; quadPoints[3].y = ptE2A.y;

                this._drawQuad(quadPoints, styleName, alphaFactor);
            }
        }
    }

    /**
     * 简单轨迹平滑算法：使用三点平均减少抖动
     * @param points 包含多个 {x,y} 点的数组
     */
    private function _simpleSmooth(points:Array):Void {
        var len:Number = points.length;
        if (len < 3) return;

        for (var i:Number = 1; i < len - 1; i++) {
            var prev:Object = points[i - 1];
            var curr:Object = points[i];
            var next:Object = points[i + 1];
            curr.x = (prev.x + curr.x + next.x) / 3;
            curr.y = (prev.y + curr.y + next.y) / 3;
        }
    }

    /**
     * 实际调用残影渲染系统绘制四边形
     * @param quadPoints  四个点构成的数组，代表一个四边形（顺时针）
     * @param styleName   样式名称（取样式表配置）
     * @param alphaValue  当前透明衰减值（0~100）
     */
    private function _drawQuad(quadPoints:Array, styleName:String, alphaValue:Number):Void {
        var style:Object = _styles[styleName];
        if (style == undefined) {
            style = _styles["预设"];
        }

        // 计算最终透明度：样式原始值 × 衰减系数
        var fillAlpha:Number = style.fillOpacity * (alphaValue / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaValue / 100);

        // 使用残影渲染器绘制（合批、渲染性能由其内部处理）
        VectorAfterimageRenderer.instance.drawShape(
            quadPoints,
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha
        );
    }

    // --- 内存管理 ---

    /**
     * 清理未活跃轨迹数据，释放内存
     * @param forceCleanAll    是否强制清除所有记录（默认 false）
     * @param maxInactiveFrames 发射者若超过此帧数未更新则判定为闲置（默认 300）
     * @return 被清理的发射者数量
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
