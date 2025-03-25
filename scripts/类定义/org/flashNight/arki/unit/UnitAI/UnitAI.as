import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;

class org.flashNight.arki.StateMaunitchine.UnitAI.UnitAI extends FSM_StateMachine{

    public var interval:Number = 4; // 每4帧一次action
    public var idle_time:Number = 16; // 停止状态持续17次action（即68帧）
    public var wander_time:Number = 50; // 随机移动状态持续50次action（即200帧）
    public var pause_time:Number = 3; // 从暂停回到思考的时间可变

    public function FSM_Enemy(self:MovieClip){
        super(null,null.null);

        //状态
        this.AddStatus("思考",new FSM_Status(null, this.think, null));
        this.AddStatus("攻击",new FSM_Status(this.attack, null, null));
        this.AddStatus("跟随",new FSM_Status(this.follow, this.follow_enter, null));
        this.AddStatus("停止",new FSM_Status(null, this.idle_enter, null));
        this.AddStatus("随机移动",new FSM_Status(null, this.wander_enter,null));
        this.AddStatus("暂停",new FSM_Status(null, null, null));

        //过渡线
        this.transitions.AddTransition("攻击","停止",function(){
            return random(data.self.停止机率) == 0;
        });
        this.transitions.AddTransition("攻击","随机移动",function(){
            return random(data.self.随机移动机率) == 0;
        });
        this.transitions.AddTransition("跟随","暂停",function(){
            return true;
        });
        this.transitions.AddTransition("停止","思考",function(){
            return this.actionCount >= this.idle_time;
        });
        this.transitions.AddTransition("随机移动","思考",function(){
            return this.actionCount >= this.wander_time;
        });
        this.transitions.AddTransition("暂停","思考",function(){
            return this.actionCount >= this.pause_time;
        });
        
        this.setActiveState(this.defaultState);
        this.initData(self);
    }

    private function initData(self:MovieClip):Void{
        data = new Object();
        data.self = self;
        data.self_name = self._name;
        data.state = self.状态;
        // data.attackmode = self.攻击模式;
        data.target = null;
        data.target_name = null;
        data.player = _root.gameworld[_root.控制目标];
    }

    private function updateData():Void{
        var self:MovieClip = data.self;
        data.state = self.状态;
        data.x = self._x;
        data.y = self._y;
        data.z = self.Z轴坐标;
        data.right = self.方向 === "右";
        data.left = self.方向 === "左";
        //
        var target:MovieClip = data.target;
        if(target){
            data.tx = target._x;
            data.ty = target._y;
            data.tz = target.Z轴坐标;
            //
            data.diff_x = target._x - self._x;
            if(data.left) data.diff_x = -data.diff_x;
            data.diff_y = target._y - self._y;
            data.diff_z = target.Z轴坐标 - self.Z轴坐标;
            data.absdiff_x = Math.abs(data.diff_x);
            data.absdiff_z = Math.abs(data.diff_z);
        }else{
            data.tx = null;
            data.ty = null;
            data.tz = null;
            //
            data.diff_x = null;
            data.diff_y = null;
            data.diff_z = null;
            data.absdiff_x = null;
            data.absdiff_z = null;
        }
    }

    //具体执行函数
    //思考
    private function think():Void{
        //search target
        if (!data.target){
            data.self.攻击目标 = "无";
            var 遍历敌人表 = _root.帧计时器.获取敌人缓存(data.self,5);
            var 敌人距离表 = new Array();
            for (var i:Number = 0; i < 遍历敌人表.length; i++){
                var 敌人 = 遍历敌人表[i];
                敌人距离表.push({敌人: 敌人, 距离: Math.abs(敌人._x - data.x)});
            }
            敌人距离表.sortOn("距离",16);
            var target = 敌人距离表[0].敌人;
            if(target){
                data.target = target;
                data.self.攻击目标 = target._name;
            }
        }else if (data.target.hp <= 0){
            data.target = null;
            data.self.攻击目标 = "无";
        }
        //
        var newstate:String = data.target ? "攻击" : "跟随";
        this.superMachine.ChangeState(newstate);
    }
    //攻击
    private function attack(xrange, zrange, xdistance):Void{
        var self = data.self;
        if (data.absdiff_z < zrange && data.absdiff_x < xrange){
            //每次action判定是否进入攻击
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            if (data.diff_x < 0){
                var face = self.left ? "左" : "右";
                self.方向改变(face);
            }
            self.状态改变(self.攻击模式 + "攻击");
            if (data.target.hp <= 0){
                self.攻击目标 = "无";
            }
        }else if(this.superMachine.actionCount % 2 == 0){
            //每2次action判定追击方向
            if (data.state != self.攻击模式 + "跑" && random(3) == 0)
            {
                self.状态改变(self.攻击模式 + "跑");
            }
            self.上行 = data.diff_z < 0;
            self.下行 = data.diff_z > 0;
            self.左行 = data.x > data.tx + xdistance;
            self.右行 = data.x < data.tx - xdistance;
        }
    }
    //跟随
    private function follow_enter():Void{
        data.px = data.player._x;
        data.py = data.player._y;
        data.rand_x = random(300) - 100;
    }
    private function follow():Void{
        var self = data.self;
        var X距离 = random(300) - 100;
        var Y距离 = 50;
        var X目标 = data.player._x;
        if (Math.abs(data.x - X目标) > X距离){
            var Y目标 = _root.Ymin + random(_root.Ymax - _root.Ymin);
            self.左行 = data.x > X目标;
            self.右行 = data.x < X目标;
        }else{
            self.左行 = false;
            self.右行 = false;
            // 在跟随范围内 = true;
        }if (Math.abs(data.z - Y目标) > Y距离){
            self.上行 = data.z > Y目标;
            self.下行 = data.z < Y目标;
        }else{
            self.上行 = false;
            self.下行 = false;
        }
    }
    //停止
    private function idle_enter():Void{
        data.self.左行 = false;
        data.self.右行 = false;
        data.self.上行 = false;
        data.self.下行 = false;
    }
    //随机移动
    private function wander_enter():Void{
        var raqny = random(_root.Ymax - _root.Ymin) + _root.Ymin;
        var randx = random(_root.Xmax - _root.Xmin) + _root.Xmin;
        data.self.左行 = randx < data.self.x;
        data.self.右行 = !data.self.左行;
        data.self.上行 = randy < data.self.y;
        data.self.下行 = randy > data.self.y;
    }

    public function onAction():Void{
        if (_root.暂停) {
            data.self.左行 = false;
            data.self.右行 = false;
            data.self.上行 = false;
            data.self.下行 = false;
            return;
        }
        this.updateData();
        super.onAction();
    }
}
