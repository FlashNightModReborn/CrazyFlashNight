import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;

import org.flashNight.arki.unit.UnitAI.UnitAIData;

class org.flashNight.arki.unit.UnitAI.BaseUnitAI{

    public static var IDLE_TIME:Number = 16; // 停止状态持续17次action（即68帧）
    public static var WANDER_TIME:Number = 50; // 随机移动状态持续50次action（即200帧）
    public static var PAUSE_TIME:Number = 5; // 跟随暂停状态持续5次action（即20帧）

    // 动作函数是否初始化完成
    public static var isActionsInitialized:Boolean = false;
    // 挂载默认动作函数的属性
    public static var think:Function;
    public static var chase:Function;
    public static var follow:Function;
    public static var sleep_enter:Function;
    public static var wander_enter:Function;

    public static function initActions():Void{
        //思考
        think = function():Void{
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
        chase = function():Void{
            data.update(); // 更新自身与攻击目标的坐标及差值
            var self = data.self;
            if (data.absdiff_z < data.zrange && data.absdiff_x < data.xrange){
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
                if (data.state != self.攻击模式 + "跑" && random(3) == 0){
                    self.状态改变(self.攻击模式 + "跑");
                }
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
                self.左行 = data.x > data.tx + data.xdistance;
                self.右行 = data.x < data.tx - data.xdistance;
            }
        }
        //跟随
        follow = function():Void{
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
        //睡眠及各个停止函数通用
        sleep_enter = function():Void{
            data.self.左行 = false;
            data.self.右行 = false;
            data.self.上行 = false;
            data.self.下行 = false;
        }
        //随机移动
        wander_enter = function():Void{
            var randy = random(_root.Ymax - _root.Ymin) + _root.Ymin;
            var randx = random(_root.Xmax - _root.Xmin) + _root.Xmin;
            data.self.左行 = randx < data.self.x;
            data.self.右行 = !data.self.左行;
            data.self.上行 = randy < data.self.y;
            data.self.下行 = randy > data.self.y;
        }
        isActionsInitialized = true;
    }


    // 自身引用
    public var self:MovieClip;

    // 状态机实例
    public var stateMachine:FSM_StateMachine;
    // 数据黑板，UnitAIData
    public var data;

    public function BaseUnitAI(_self:MovieClip){
        if(!isActionsInitialized) BaseUnitAI.initActions();
        this.self = _self;
        this.stateMachine = new FSM_StateMachine(null,null.null);
        this.data = new UnitAIData(this.self);
        this.stateMachine.data = this.data;

        // 状态列表
        // 睡眠状态（默认状态）
        this.stateMachine.AddStatus("Sleeping",new FSM_Status(null, BaseUnitAI.sleep_enter, null));
        // 思考状态，结算进入状态函数后一定会跳转至其他状态
        this.stateMachine.AddStatus("Thinking",new FSM_Status(null, BaseUnitAI.think, null));
        // 追击状态
        this.stateMachine.AddStatus("Chasing",new FSM_Status(BaseUnitAI.chase, null, null));
        // 跟随状态
        this.stateMachine.AddStatus("Following",new FSM_Status(BaseUnitAI.follow, null, null));
        // 跟随暂停状态
        this.stateMachine.AddStatus("FollowFinished",new FSM_Status(null, BaseUnitAI.sleep_enter, null));
        // 空闲状态
        this.stateMachine.AddStatus("Idle",new FSM_Status(null, BaseUnitAI.sleep_enter, null));
        // 随机移动状态
        this.stateMachine.AddStatus("Wandering",new FSM_Status(null, BaseUnitAI.wander_enter,null));

        //过渡线
        this.stateMachine.transitions.AddTransition("Chasing","Idle",function(){
            return random(data.self.停止机率) == 0;
        });
        this.stateMachine.transitions.AddTransition("Chasing","Wandering",function(){
            return random(data.self.随机移动机率) == 0;
        });
        this.stateMachine.transitions.AddTransition("Following","FollowFinished",function(){
            return true;
        });
        this.stateMachine.transitions.AddTransition("Idle","Thinking",function(){
            return this.actionCount >= BaseUnitAI.IDLE_TIME;
        });
        this.stateMachine.transitions.AddTransition("Wandering","Thinking",function(){
            return this.actionCount >= BaseUnitAI.WANDER_TIME;
        });
        this.stateMachine.transitions.AddTransition("FollowFinished","Thinking",function(){
            return this.actionCount >= BaseUnitAI.PAUSE_TIME;
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.stateMachine.transitions.AddTransition("Sleeping","Thinking",function(){
            return data.self.思考标签 != null && _root.暂停 !== true;
        });
        // 所有状态在游戏暂停时及思考标签不存在时均会过渡到睡眠状态
        var sleep_function = function(){
            return data.self.思考标签 == null || _root.暂停 === true;
        }
        this.stateMachine.transitions.AddTransition("Chasing","Sleeping", sleep_function);
        this.stateMachine.transitions.AddTransition("Following","Sleeping", sleep_function);
        this.stateMachine.transitions.AddTransition("FollowFinished","Sleeping", sleep_function);
        this.stateMachine.transitions.AddTransition("Idle","Sleeping", sleep_function);
        this.stateMachine.transitions.AddTransition("Wandering","Sleeping", sleep_function);
        
        this.stateMachine.setActiveState(this.stateMachine.getDefaultState());
    }

    //更新函数
    public function update():Void{
        this.stateMachine.onAction();
    }
}
