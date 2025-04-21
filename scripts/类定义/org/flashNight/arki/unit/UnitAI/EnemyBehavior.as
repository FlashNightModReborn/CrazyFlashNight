import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;

import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;

// 敌人基础状态机，继承单位状态机基类

class org.flashNight.arki.unit.UnitAI.EnemyBehavior extends BaseUnitBehavior{

    public static var IDLE_BASIC_TIME:Number = 8; // 停止状态持续8次action（即32帧）。计划在ai进一步重构后废弃
    public static var WANDER_BASIC_TIME:Number = 15; // 随机移动状态持续15次action（即60帧）。计划在ai进一步重构后废弃
    public static var FOLLOW_TIME:Number = 5; // 跟随状态持续5次action（即20帧）

    public static var CHASE_TIME:Number = 30; // 追击状态持续30次action（即120帧）后再开始判断停止或随机移动。计划在ai进一步重构后废弃

    public function EnemyBehavior(_data:UnitAIData){
        super(_data);

        // 状态列表 
        // 已存在的包括基类的睡眠状态（默认状态）

        // 思考状态，结算进入状态函数后一定会跳转至其他状态
        this.AddStatus("Thinking",new FSM_Status(null, this.think, null));
        // 追击状态
        this.AddStatus("Chasing",new FSM_Status(this.chase, this.chase_enter, null));
        // 跟随状态
        this.AddStatus("Following",new FSM_Status(null, this.follow_enter, null));
        // 空闲状态
        this.AddStatus("Idle",new FSM_Status(null, this.idle_enter, null));
        // 随机移动状态
        this.AddStatus("Wandering",new FSM_Status(null, this.wander_enter,null));

        //过渡线
        this.transitions.push("Chasing","Idle",function(){
            return this.actionCount >= data.idle_threshold;
        });
        this.transitions.push("Chasing","Wandering",function(){
            return this.actionCount >= data.wander_threshold;
        });
        this.transitions.push("Idle","Thinking",function(){
            return this.actionCount >= data.think_threshold;
        });
        this.transitions.push("Wandering","Thinking",function(){
            return this.actionCount >= data.think_threshold;
        });
        this.transitions.push("Following","Thinking",function(){
            return this.actionCount >= EnemyBehavior.FOLLOW_TIME;
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.transitions.push("Sleeping","Thinking",this.wakeupCheck);
    }



    // 具体执行函数
    // 思考
    public function think():Void{
        data.updateSelf(); // 更新自身坐标
        //search target
        var chaseTarget = data.self.攻击目标;
        if (!chaseTarget || chaseTarget == "无"){
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
        }else{
            data.target = _root.gameworld[chaseTarget];
        }
        if (data.target.hp <= 0){
            data.target = null;
            data.self.攻击目标 = "无";
        }
        //
        var newstate:String = data.target ? "Chasing" : "Following";
        this.superMachine.ChangeState(newstate);
    }

    // 追击
    public function chase_enter():Void{
        var 友军数量 = _root.帧计时器.获取友军缓存(data.self,5).length;
        if(友军数量 <= 1){
            // 若己方没有任何队友，则永远不会停止追击
            data.idle_threshold = 999999;
            data.wander_threshold = 999999;
        }else{
            // 根据停止机率和随机移动机率随机一个临界时间
            var temp = 友军数量 <= 5 ? 3 : (友军数量 <= 15 ? 2 : 1);
            data.idle_threshold = 友军数量 < 1 ? 999999 : EnemyBehavior.CHASE_TIME + random(temp * data.self.停止机率);
            data.wander_threshold = 友军数量 < 1 ? 999999 : EnemyBehavior.CHASE_TIME + random(temp * data.self.随机移动机率);
        }
    }
    public function chase():Void{
        // 与攻击目标参数一致
        if(data.target._name != data.self.攻击目标){
            data.target = _root.gameworld[data.self.攻击目标];
        }
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
            self.攻击目标 = data.target.hp <= 0 ? "无" : data.target._name;
            if (data.diff_x < 0){
                self.方向改变("左");
            }else if(data.diff_x > 0){
                self.方向改变("右");
            }
            self.状态改变(self.攻击模式 + "攻击");
        }else{
            var sm = this.superMachine;
            if(sm.actionCount % 2 == 0){
                //每奇数次action判定追击方向
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
                self.左行 = data.x > data.tx + data.xdistance;
                self.右行 = data.x < data.tx - data.xdistance;
            }else if (data.state != self.攻击模式 + "跑"){
                //每偶数次action判定是否起跑
                if(data.absdiff_x > 120 & data.absdiff_z > 60 && random(3) == 0){
                    self.状态改变(self.攻击模式 + "跑");
                }
            }
        }
    }
    // 丢失攻击目标
    // public function chase_exit():Void{
    // }
    // 跟随
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
    // 停止
    public function idle_enter():Void{
        // 丢失攻击目标
        data.target = null;
        data.self.攻击目标 = "无";
        data.self.左行 = false;
        data.self.右行 = false;
        data.self.上行 = false;
        data.self.下行 = false;
        // 根据友军数量计算随机时间
        var 友军数量 = _root.帧计时器.获取友军缓存(data.self,5).length;
        var temp = 友军数量 <= 5 ? 0 : (友军数量 <= 10 ? 1 : 2);
        data.think_threshold = EnemyBehavior.IDLE_BASIC_TIME + random(temp * EnemyBehavior.IDLE_BASIC_TIME);
    }
    // 随机移动
    public function wander_enter():Void{
        // 丢失攻击目标
        data.target = null;
        data.self.攻击目标 = "无";
        data.updateSelf(); // 更新自身坐标
        var randy = random(_root.Ymax - _root.Ymin) + _root.Ymin;
        var randx = random(_root.Xmax - _root.Xmin) + _root.Xmin;
        data.self.左行 = randx < data.x;
        data.self.右行 = !data.self.左行;
        data.self.上行 = randy < data.z;
        data.self.下行 = randy > data.z;
        // 根据友军数量计算随机时间
        var 友军数量 = _root.帧计时器.获取友军缓存(data.self,5).length;
        var temp = 友军数量 <= 5 ? 0 : (友军数量 <= 10 ? 1 : 2);
        data.think_threshold = EnemyBehavior.WANDER_BASIC_TIME + random(temp * EnemyBehavior.WANDER_BASIC_TIME);
    }
}
