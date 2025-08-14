import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.UnitAI.UnitAIData{

    // 自身引用
    public var self:MovieClip;
    public var self_name:String;
    public var state:String;

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
        this.run_threshold_x = self.跑X速度 * 8;
        this.run_threshold_z = self.跑Y速度 * 8;
    }

    public function updateSelf():Void{
        this.state = self.状态;
        this.x = self._x;
        this.y = self._y;
        this.z = self.Z轴坐标;
        this.right = self.方向 === "右";
        this.left = self.方向 === "左";
        this.standby = self.待机 === true ? true : false;
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
}
