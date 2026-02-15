import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.UnitAI.UnitAIData{

    // 自身引用
    public var self:MovieClip;
    public var self_name:String;
    public var state:String;
    public var createdFrame:Number;

    // 自身坐标
    public var x:Number;
    public var y:Number;
    public var z:Number;
    public var right:Boolean;
    public var left:Boolean;

    // 攻击目标引用
    public var target:MovieClip;
    // public var target_name:String; // 暂未启用

    // 攻击目标坐标
    public var tx:Number;
    public var ty:Number;
    public var tz:Number;
    // 攻击目标与自身的坐标差值
    public var diff_x:Number;
    public var diff_y:Number;
    public var diff_z:Number;
    public var absdiff_x:Number;
    public var absdiff_z:Number;

    // 玩家引用
    public var player:MovieClip;

    // 根据自身的奔跑xy速度计算起跑距离
    public var run_threshold_x:Number;
    public var run_threshold_z:Number;

    
    // AI相关参数
    public var xrange:Number; // x轴攻击范围
    public var zrange:Number; // z轴攻击范围
	public var xdistance:Number; // x轴保持距离

    public var idle_threshold:Number; // 由追击转入停止状态的临界动作次数
    public var wander_threshold:Number; // 由追击转入随机移动状态的临界动作次数
    public var think_threshold:Number // 返回思考的临界时长
    
    public var evade_distance:Number; // 个性化的远离安全距离

    public var standby:Boolean; // 是否处于待机状态

    public var aiNextMode:String; // 模块主观完成信号（方案A预留）

    // 人格向量 + 派生AI参数（Phase 2）
    // 引用 self.personality 同一对象，mutate-only 策略保证不陈旧
    public var personality:Object;

    // Utility 评估器实例（Phase 2 Step 3）
    // 仅 Hero 类型创建，其他类型为 null
    public var evaluator;

    
    public function UnitAIData(_self:MovieClip){
        this.self = _self;
        init();
    }

    public function init():Void{
        this.self_name = self._name;
        this.state = self.状态;
        // this.attackmode = self.攻击模式;
        this.target = null;
        // this.target_name = null;
        this.player = TargetCacheManager.findHero();
        //初始化ai参数
        this.xrange = self.x轴攻击范围;
        this.xdistance = self.x轴保持距离;
        this.zrange = 10; // 这里暂时不使用设置的z轴范围参数，并强制将原来填的数值刷新为10
        this.self.y轴攻击范围 = 10;
        // 根据自身的奔跑xy速度计算起跑距离
        // 如果跑速度尚未初始化（getter未装/属性未设置），从行走X速度和奔跑速度倍率推算
        var runX:Number = self.跑X速度;
        var runY:Number = self.跑Y速度;
        if (isNaN(runX) || runX <= 0) {
            var walkX:Number = self.行走X速度;
            var runMult:Number = self.奔跑速度倍率;
            if (isNaN(runMult) || runMult <= 0) runMult = 2;
            runX = walkX * runMult;
            runY = (walkX / 2) * runMult;
        }
        this.run_threshold_x = runX * 8;
        this.run_threshold_z = runY * 8;

        this.aiNextMode = null;
        this.personality = self.personality; // 六维 + 派生参数（同一对象引用）
        this.createdFrame = _root.帧计时器.当前帧数;
    }

    public function updateSelf():Void{
        this.state = self.状态;
        this.x = self._x;
        this.y = self._y;
        this.z = self.Z轴坐标;
        this.right = self.方向 === "右";
        this.left = self.方向 === "左";
        this.standby = self.待机 ? true : false;
        // _root.发布消息(self._name, this.standby, self.待机)
    }
    
    public function updateTarget():Void{
        var target:MovieClip = this.target;
        if(target != null){
            this.tx = target._x;
            this.ty = target._y;
            this.tz = isNaN(target.Z轴坐标) ? target._y : target.Z轴坐标;
            //
            this.diff_x = this.tx - this.x;
            this.diff_y = this.ty - this.y;
            this.diff_z = this.tz - this.z;
            this.absdiff_x = Math.abs(this.diff_x);
            this.absdiff_z = Math.abs(this.diff_z);
        }else{
            this.tx = null;
            this.ty = null;
            this.tz = null;
            //
            this.diff_x = null;
            this.diff_y = null;
            this.diff_z = null;
            this.absdiff_x = null;
            this.absdiff_z = null;
        }
    }

    // 卡死检测的历史位置缓存
    private var _lastStuckCheckFrame:Number = -1;
    private var _lastSelfX:Number;
    private var _lastSelfY:Number;
    private var _lastSelfZ:Number;
    private var _stuckCheckCount:Number = 0;

    /**
     * 改进版卡死检测 - 基于自身绝对位置变化而非相对距离变化
     * 
     * 解决原版本的误报问题：
     * 1. 检测自身绝对位置变化而非与目标的相对距离
     * 2. 适配间隔检测（非每帧调用）
     * 3. 需要连续多次检测到无移动才判定为卡死
     *
     * @param isTryingToMove  是否有移动意图
     * @param eps            位置变化阈值（像素）
     * @param minStuckCount  连续无移动的最小次数才判定卡死（默认3）
     * @return Boolean       true=确实卡死；false=正常
     */
    public function stuckProbeByDiffChange(isTryingToMove:Boolean, eps:Number, minStuckCount:Number):Boolean {
        // 参数默认值处理
        if (isTryingToMove == undefined) {
            var s:String = this.state;
            isTryingToMove = (s == "Walk" || s == "Run" || s == "Chase" || s == "移动" || s == "追击" || s == "奔跑");
        }
        if (eps == undefined) eps = 8; // 提高阈值，适配四向移动
        if (minStuckCount == undefined) minStuckCount = 3;

        var currentFrame:Number = _root.帧计时器.当前帧数;

        // 非移动意图 / 待机状态：重置检测计数
        if (!isTryingToMove || this.standby) {
            this._stuckCheckCount = 0;
            this._lastStuckCheckFrame = currentFrame;
            return false;
        }

        // 更新自身坐标
        this.updateSelf();

        // 初次检测：记录位置，不判定卡死
        if (this._lastStuckCheckFrame < 0 || 
            this._lastSelfX == undefined || 
            this._lastSelfY == undefined || 
            this._lastSelfZ == undefined) {
            
            this._lastSelfX = this.x;
            this._lastSelfY = this.y;
            this._lastSelfZ = this.z;
            this._lastStuckCheckFrame = currentFrame;
            this._stuckCheckCount = 0;
            return false;
        }

        // 检测时间间隔过短，跳过本次检测
        var frameGap:Number = currentFrame - this._lastStuckCheckFrame;
        if (frameGap < 4) { // 至少4帧间隔再检测
            return this._stuckCheckCount >= minStuckCount;
        }

        // 计算位置变化量
        var deltaX:Number = Math.abs(this.x - this._lastSelfX);
        var deltaY:Number = Math.abs(this.y - this._lastSelfY);
        var deltaZ:Number = Math.abs(this.z - this._lastSelfZ);
        var totalDelta:Number = Math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ);

        // 判断是否有显著移动
        var hasMoved:Boolean = totalDelta > eps;

        if (hasMoved) {
            // 有移动：重置卡死计数
            this._stuckCheckCount = 0;
        } else {
            // 无移动：增加卡死计数
            this._stuckCheckCount++;
        }

        // 更新检测记录
        this._lastSelfX = this.x;
        this._lastSelfY = this.y;
        this._lastSelfZ = this.z;
        this._lastStuckCheckFrame = currentFrame;

        // 调试输出
        if (_root.调试模式 && this._stuckCheckCount > 0) {
            _root.发布消息(this.self, "卡死检测: " + this._stuckCheckCount + "/" + minStuckCount + " 移动距离: " + totalDelta);
        }

        // 只有连续多次无移动才判定为真正卡死
        return this._stuckCheckCount >= minStuckCount;
    }

    /**
     * 兼容旧版本的卡死检测（已废弃，保留向下兼容）
     * @deprecated 请使用改进版的 stuckProbeByDiffChange
     */
    public function stuckProbeByDiffChange_Legacy(isTryingToMove:Boolean, eps:Number):Boolean {
        if (eps == undefined) eps = 0;
        if (!isTryingToMove || this.standby || this.target == null) {
            return false;
        }

        var old_dx:Number = this.diff_x;
        var old_dy:Number = this.diff_y;
        var old_dz:Number = this.diff_z;

        this.updateSelf();
        this.updateTarget();

        if (old_dx == null || old_dy == null || old_dz == null ||
            this.diff_x == null || this.diff_y == null || this.diff_z == null) {
            return false;
        }

        var changed:Boolean =
            Math.abs(this.diff_x - old_dx) > eps ||
            Math.abs(this.diff_y - old_dy) > eps ||
            Math.abs(this.diff_z - old_dz) > eps;

        return !changed;
    }

}
