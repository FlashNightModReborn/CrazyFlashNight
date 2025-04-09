import org.flashNight.arki.render.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.gesh.object.*;

/**
 * TrailRenderer 拖影渲染器（单例）
 * 
 * 用于记录并渲染攻击刀口、子弹轨迹等动态残影效果，
 * 支持样式配置、轨迹平滑处理、历史帧限制与自动内存清理。
 *
 * 优化改进包括：
 * 1. 使用环形队列（Ring Buffer）替代 Array.shift() 操作，提升性能
 * 2. 坐标比较采用平方距离计算，避免频繁调用 Math.sqrt
 * 3. 缓存对象引用减少属性查找
 * 4. 初始化逻辑统一封装
 * 5. 阈值作为类属性，避免重复计算
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
    
    /** 移动最小差异阈值（单位：像素） */
    private var _movementThreshold:Number;
    
    /** 移动最小差异阈值的平方，用于避免 Math.sqrt 调用 */
    private var _movementThresholdSqr:Number;
    
    // --- 构造与初始化 ---
    
    /**
     * 私有构造函数，禁止外部直接创建实例，请使用 getInstance()
     */
    private function TrailRenderer() {
        this._trackRecords = {};          // 创建轨迹记录容器
        this._maxFrames = 3;              // 默认轨迹历史帧数限制
        this._movementThreshold = 5.0;    // 最小差异阈值（单位：像素）
        this._movementThresholdSqr = this._movementThreshold * this._movementThreshold;
    }
    
    /**
     * 获取 TrailRenderer 单例实例（懒汉式创建）
     * @return TrailRenderer 单例实例
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
    public function initStyles():Void {
        var loader:TrailStylesLoader = TrailStylesLoader.getInstance();
        var self = this;
        loader.loadStyles(function(styles:Object):Void {
            self._styles = styles;
            // 样式加载成功
        }, function():Void {
            _root.服务器.发布服务器消息("TrailRenderer: 样式加载失败，使用默认样式！");
            self._styles = {
                预设: {
                    color: 0xFFFFFF,
                    lineColor: 0xFFFFFF,
                    lineWidth: 2,
                    fillOpacity: 100,
                    lineOpacity: 100
                }
            };
        });
    }
    
    // --- 主功能入口 ---
    
    /**
     * 添加并记录一个发射者当前帧的轨迹数据，并触发渲染。
     * 如果当前输入点集与上一次记录末尾的数据变化非常小（低于设定阈值），则直接跳过更新与渲染，
     * 从而节省性能消耗。
     * 
     * @param emitterId   发射者唯一标识（例如影片剪辑的 _name）
     * @param edgeArray   边缘点数组，每项包含 edge1 和 edge2 坐标对象
     * @param styleName   拖影样式名称（必须存在于样式表中）
     */
    public function addTrailData(emitterId:String, edgeArray:Array, styleName:String):Void {
        var currentFrame:Number = _root.帧计时器.当前帧数;
        var trackRecords:Object = this._trackRecords; // 缓存引用，减少属性查找
        var record:Object = trackRecords[emitterId];
        var len:Number = edgeArray.length;
        var i:Number;
        
        // 若发射者第一次出现，初始化记录结构
        if (!record) {
            record = this._initializeRecord(edgeArray, currentFrame);
            trackRecords[emitterId] = record;
            return;
        }
        
        // 超过 10 帧未更新，则清空历史轨迹（避免突变造成拖影跳变）
        if (currentFrame - record._lastFrame > 10) {
            for (i = 0; i < len; i++) {
                // 通过环形队列的 clear 方法重置数据
                record[i].edge1.clear(edgeArray[i].edge1);
                record[i].edge2.clear(edgeArray[i].edge2);
            }
            record._lastFrame = currentFrame;
            return;
        }
        
        // 对比当前输入的轨迹数据与上一次记录的末尾数据，
        // 如果对应点的变化幅度均低于设定阈值，则认为变化非常小，跳过更新与渲染
        var needUpdate:Boolean = false;
        for (i = 0; i < len; i++) {
            var traj:Object = record[i];
            // 缓存环形队列引用
            var ringE1:Object = traj.edge1;
            var ringE2:Object = traj.edge2;
            var lastEdge1:Object = ringE1.get(ringE1.count - 1);
            var lastEdge2:Object = ringE2.get(ringE2.count - 1);
            var newE1:Object = edgeArray[i].edge1;
            var newE2:Object = edgeArray[i].edge2;
            var dx1:Number = lastEdge1.x - newE1.x;
            var dy1:Number = lastEdge1.y - newE1.y;
            if (dx1 * dx1 + dy1 * dy1 > this._movementThresholdSqr) {
                needUpdate = true;
                break;
            }
            var dx2:Number = lastEdge2.x - newE2.x;
            var dy2:Number = lastEdge2.y - newE2.y;
            if (dx2 * dx2 + dy2 * dy2 > this._movementThresholdSqr) {
                needUpdate = true;
                break;
            }
        }
        
        // 如果数据变化非常小，则跳过此次更新与渲染
        if (!needUpdate) {
            return;
        }
        
        // 更新当前轨迹信息，将新帧数据插入各环形队列中
        for (i = 0; i < len; i++) {
            var traj:Object = record[i];
            traj.edge1.push(edgeArray[i].edge1);
            traj.edge2.push(edgeArray[i].edge2);
        }
        
        // 执行渲染逻辑
        this._renderTrails(record, edgeArray, styleName, currentFrame);
        
        // 更新记录最后活跃的帧数
        record._lastFrame = currentFrame;
    }
    
    // --- 核心渲染逻辑 ---
    
    /**
     * 渲染指定发射者的轨迹记录，自动处理轨迹平滑和透明衰减。
     * 
     * @param record         当前发射者的历史轨迹记录（包含环形队列）
     * @param edgeArray      当前帧边缘点数组（用于遍历轨迹数量）
     * @param styleName      拖影样式名称（用于获取样式配置）
     * @param currentFrame   当前帧数（用于控制平滑处理的频率）
     */
    private function _renderTrails(record:Object, edgeArray:Array, styleName:String, currentFrame:Number):Void {
        var len:Number = edgeArray.length;
        // 定义用于绘制四边形的四个顶点数组
        var quadPoints:Array = [ {x:0, y:0}, {x:0, y:0}, {x:0, y:0}, {x:0, y:0} ];
        var i:Number, j:Number;
        
        for (i = 0; i < len; i++) {
            var traj:Object = record[i];
            // 通过环形队列获取当前有效数据个数
            var count:Number = traj.edge1.count;
            // 如果不足两帧数据，则无法构成四边形，直接跳过
            if (count < 2 || traj.edge2.count < 2) continue;
            
            // 每 3 帧执行一次轨迹平滑处理（简单移动平均算法）
            if (currentFrame % 3 == 0) {
                this._simpleSmooth(traj.edge1);
                this._simpleSmooth(traj.edge2);
            }
            
            // 遍历相邻帧，依次绘制四边形残影
            for (j = 0; j < count - 1; j++) {
                var ptE1A:Object = traj.edge1.get(j);
                var ptE1B:Object = traj.edge1.get(j + 1);
                var ptE2A:Object = traj.edge2.get(j);
                var ptE2B:Object = traj.edge2.get(j + 1);
                
                // 指数衰减：越旧的帧越透明
                var alphaFactor:Number = 100 * Math.pow(0.7, j);
                
                // 设定四边形顶点（顺时针排列）
                quadPoints[0].x = ptE1A.x; quadPoints[0].y = ptE1A.y;
                quadPoints[1].x = ptE1B.x; quadPoints[1].y = ptE1B.y;
                quadPoints[2].x = ptE2B.x; quadPoints[2].y = ptE2B.y;
                quadPoints[3].x = ptE2A.x; quadPoints[3].y = ptE2A.y;
                
                this._drawQuad(quadPoints, styleName, alphaFactor);
            }
        }
    }
    
    /**
     * 简单轨迹平滑算法：使用相邻三个点的平均值减少轨迹抖动（对环形队列操作）
     * 
     * @param ring 包含多个 {x, y} 坐标点的环形队列对象
     */
    private function _simpleSmooth(ring:Object):Void {
        var count:Number = ring.count;
        if (count < 3) return;
        var i:Number;
        for (i = 1; i < count - 1; i++) {
            var pPrev:Object = ring.get(i - 1);
            var pCurr:Object = ring.get(i);
            var pNext:Object = ring.get(i + 1);
            pCurr.x = (pPrev.x + pCurr.x + pNext.x) / 3;
            pCurr.y = (pPrev.y + pCurr.y + pNext.y) / 3;
        }
    }
    
    /**
     * 实际调用残影渲染系统绘制四边形。
     * 
     * @param quadPoints  组成四边形的四个顶点数组（顺时针排列）
     * @param styleName   样式名称（用于获取样式配置）
     * @param alphaValue  当前透明衰减值（0~100）
     */
    private function _drawQuad(quadPoints:Array, styleName:String, alphaValue:Number):Void {
        var style:Object = this._styles[styleName];
        if (style == undefined) {
            style = this._styles["预设"];
        }
        // 计算最终透明度：样式配置透明度乘以衰减系数
        var fillAlpha:Number = style.fillOpacity * (alphaValue / 100);
        var lineAlpha:Number = style.lineOpacity * (alphaValue / 100);
        // 调用渲染器绘制四边形残影
        VectorAfterimageRenderer.instance.drawShape(
            quadPoints,
            style.color,
            style.lineColor,
            style.lineWidth,
            fillAlpha,
            lineAlpha
        );
    }
    
    // --- 环形队列辅助方法 ---
    
    /**
     * 创建一个固定长度的环形队列，用于存储轨迹点数据，
     * 避免因 Array.shift() 操作产生的性能开销。
     * 
     * @param initialItem 初始存储项（可选）
     * @return 环形队列对象，包含 push、get 和 clear 方法
     */
    private function _createRingBuffer(initialItem:Object):Object {
        var ring:Object = { buffer: new Array(this._maxFrames), start: 0, count: 0, max: this._maxFrames };
        ring.push = function(item:Object):Void {
            if (this.count < this.max) {
                this.buffer[(this.start + this.count) % this.max] = item;
                this.count++;
            } else {
                this.buffer[this.start] = item;
                this.start = (this.start + 1) % this.max;
            }
        };
        ring.get = function(index:Number):Object {
            return this.buffer[(this.start + index) % this.max];
        };
        ring.clear = function(item:Object):Void {
            this.buffer = new Array(this.max);
            this.start = 0;
            this.count = 0;
            this.push(item);
        };
        if (initialItem != undefined) {
            ring.push(initialItem);
        }
        return ring;
    }
    
    /**
     * 初始化新的发射者轨迹记录，统一创建环形队列结构。
     * 
     * @param edgeArray    当前帧边缘点数组
     * @param currentFrame 当前帧数
     * @return 初始化后的记录对象，包含每条边缘的环形队列数据
     */
    private function _initializeRecord(edgeArray:Array, currentFrame:Number):Object {
        var rec:Object = { _lastFrame: currentFrame };
        var len:Number = edgeArray.length;
        var i:Number;
        for (i = 0; i < len; i++) {
            rec[i] = { 
                edge1: this._createRingBuffer(edgeArray[i].edge1),
                edge2: this._createRingBuffer(edgeArray[i].edge2)
            };
        }
        return rec;
    }
    
    // --- 内存管理 ---
    
    /**
     * 清理未活跃轨迹数据，释放内存。
     * 
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
