import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;

import org.flashNight.arki.unit.UnitAI.UnitAIData;

// 单位基础状态机

class org.flashNight.arki.unit.UnitAI.FSMEnemy extends FSM_StateMachine{

    public static var IDLE_TIME:Number = 16; // 停止状态持续17次action（即68帧）
    public static var WANDER_TIME:Number = 50; // 随机移动状态持续50次action（即200帧）
    public static var PAUSE_TIME:Number = 5; // 跟随状态持续5次action（即20帧）

    // 数据黑板
    public var data:UnitAIData;

    public function FSMEnemy(_data:UnitAIData){
        super(null,null.null);
        this.data = _data;

        // 状态列表
        // 睡眠状态（默认状态）
        this.AddStatus("Sleeping",new FSM_Status(null, this.sleep_enter, null));
        // 思考状态，结算进入状态函数后一定会跳转至其他状态
        this.AddStatus("Thinking",new FSM_Status(null, this.think, null));
        // 追击状态
        this.AddStatus("Chasing",new FSM_Status(this.chase, null, null));
        // 跟随状态
        this.AddStatus("Following",new FSM_Status(null, this.follow_enter, null));
        // 空闲状态
        this.AddStatus("Idle",new FSM_Status(null, this.sleep_enter, null));
        // 随机移动状态
        this.AddStatus("Wandering",new FSM_Status(null, this.wander_enter,null));

        //过渡线
        this.transitions.AddTransition("Chasing","Idle",function(){
            return random(data.self.停止机率) == 0;
        });
        this.transitions.AddTransition("Chasing","Wandering",function(){
            return random(data.self.随机移动机率) == 0;
        });
        this.transitions.AddTransition("Idle","Thinking",function(){
            return this.actionCount >= FSMEnemy.IDLE_TIME;
        });
        this.transitions.AddTransition("Wandering","Thinking",function(){
            return this.actionCount >= FSMEnemy.WANDER_TIME;
        });
        this.transitions.AddTransition("Following","Thinking",function(){
            return this.actionCount >= FSMEnemy.PAUSE_TIME;
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.transitions.AddTransition("Sleeping","Thinking",function(){
            return data.self.思考标签 != null && _root.暂停 !== true;
        });
        // 所有状态在游戏暂停时及思考标签不存在时均会过渡到睡眠状态
        this.transitions.AddTransition("Chasing","Sleeping", this.sleepCheck);
        this.transitions.AddTransition("Following","Sleeping", this.sleepCheck);
        this.transitions.AddTransition("Idle","Sleeping", this.sleepCheck);
        this.transitions.AddTransition("Wandering","Sleeping", this.sleepCheck);
    }



    // 具体执行函数
    // 检查是否启用ai
    public function sleepCheck(){
        return data.self.思考标签 == null || _root.暂停 === true;
    }

    //思考
    public function think():Void{
        data.updateSelf(); // 更新自身坐标
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
        var newstate:String = data.target != null ? "Chasing" : "Following";
        this.superMachine.ChangeState(newstate);
    }

    //追击
    public function chase():Void{
        // 更新自身与攻击目标的坐标及差值
        data.updateSelf();
        data.updateTarget();

        var self = data.self;
        if (data.absdiff_z < data.zrange && data.absdiff_x < data.xrange){
            //每次action判定是否进入攻击
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            if (data.diff_x < 0){
                self.方向改变("左");
            }else if(data.diff_x > 0){
                self.方向改变("右");
            }
            self.状态改变(self.攻击模式 + "攻击");
            if (data.target.hp <= 0){
                self.攻击目标 = "无";
            }
        }else{
            var sm = this.superMachine;
            if(sm.actionCount % 2 == 0){
                //每2次action判定追击方向
                if (data.state != self.攻击模式 + "跑" && random(3) == 0){
                    self.状态改变(self.攻击模式 + "跑");
                }
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
                self.左行 = data.x > data.tx + data.xdistance;
                self.右行 = data.x < data.tx - data.xdistance;
            }
        }
    }
    //跟随
    public function follow_enter():Void{
        data.updateSelf(); // 更新自身坐标
        var self = data.self;
        var X距离 = random(200) + 100;
        var Y距离 = 50;
        var playerx = data.player._x;
        var playery = data.player._y;

        self.左行 = false;
        self.右行 = false;
        self.上行 = false;
        self.下行 = false;
        if (Math.abs(data.x - playerx) > X距离){
            self.左行 = data.x > playerx;
            self.右行 = data.x < playerx;
            var randz = _root.Ymin + random(_root.Ymax - _root.Ymin);
            if(Math.abs(data.z - randz) > Y距离){
                self.上行 = data.z > randz;
                self.下行 = data.z < randz;
            }
        }else if (Math.abs(data.z - playery) > Y距离){
            self.上行 = data.z > playery;
            self.下行 = data.z < playery;
        }
    }
    //睡眠及各个停止函数通用
    public function sleep_enter():Void{
        data.self.左行 = false;
        data.self.右行 = false;
        data.self.上行 = false;
        data.self.下行 = false;
    }
    //随机移动
    public function wander_enter():Void{
        data.updateSelf(); // 更新自身坐标
        var randy = random(_root.Ymax - _root.Ymin) + _root.Ymin;
        var randx = random(_root.Xmax - _root.Xmin) + _root.Xmin;
        data.self.左行 = randx < data.self.x;
        data.self.右行 = !data.self.左行;
        data.self.上行 = randy < data.self.y;
        data.self.下行 = randy > data.self.y;
    }

}
