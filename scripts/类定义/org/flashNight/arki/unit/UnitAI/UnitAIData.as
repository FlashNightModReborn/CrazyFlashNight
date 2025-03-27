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

    
    // AI相关参数
    public var xrange:Number; // x轴攻击范围
    public var zrange:Number; // z轴攻击范围
	public var xdistance:Number; // x轴保持距离 

    
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
        this.player = _root.gameworld[_root.控制目标];
        //初始化ai参数
        this.xrange = self.x轴攻击范围;
        this.zrange = 10; // 这里暂时不使用设置的参数
        this.xdistance = self.x轴保持距离;
    }

    public function updateSelf():Void{
        this.state = self.状态;
        this.x = self._x;
        this.y = self._y;
        this.z = self.Z轴坐标;
        this.right = self.方向 === "右";
        this.left = self.方向 === "左";
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
