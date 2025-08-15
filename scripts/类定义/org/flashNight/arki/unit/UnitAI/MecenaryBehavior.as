import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.sara.util.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;

// 场景中佣兵与可雇佣敌人NPC的状态机，继承单位状态机基类

class org.flashNight.arki.unit.UnitAI.MecenaryBehavior extends BaseUnitBehavior{

    public static var IDLE_MIN_TIME:Number = 10; // 停止状态最短10次action（40帧）切换状态
    public static var IDLE_MAX_TIME:Number = 40; // 停止状态最长40次action（160帧）切换状态
    public static var WALK_MIN_TIME:Number = 8; // 移动状态最短8次action（32帧）切换状态
    public static var WALK_MAX_TIME:Number = 40; // 移动状态最长40次action（160帧）切换状态
    public static var WANDER_MIN_TIME:Number = 15; // 漫游状态最短15次action（60帧）切换状态
    public static var WANDER_MAX_TIME:Number = 50; // 漫游状态最长50次action（200帧）切换状态
    public static var ALIVE_MAX_TIME:Number = 30 * 30; // 最大存活30s
    public static var STUCK_COUNT_MAX:Number = 3;

    public function MecenaryBehavior(_data:UnitAIData){
        super(_data);

        // 状态列表 
        // 已存在的包括基类的睡眠状态（默认状态）

        // 思考状态，结算进入状态函数后一定会跳转至其他状态
        this.AddStatus("Thinking",new FSM_Status(null, this.think, null));
        // 空闲状态
        this.AddStatus("Idle",new FSM_Status(null, this.idle_enter, null));
        // 移动状态
        this.AddStatus("Walking",new FSM_Status(this.walk, this.walk_enter, null));
        // 漫游状态
        this.AddStatus("Wandering",new FSM_Status(null, this.wander_enter, null));

        //过渡线
        this.pushGateTransition("Idle","Thinking",function(){
            return this.actionCount >= data.think_threshold;
        });
        this.pushGateTransition("Walking","Thinking",function(){
            return this.actionCount >= data.think_threshold;
        });
        this.pushGateTransition("Wandering","Thinking",function(){
            return this.actionCount >= data.think_threshold;
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.pushGateTransition("Sleeping","Thinking",this.wakeupCheck);
    }



    // 具体执行函数
    // 思考
    public function think():Void{
        var self:MovieClip = data.self;

        if(_root.帧计时器.当前帧数 - data.createdFrame > ALIVE_MAX_TIME) {
            self.删除可雇用单位();
            return;
        }
        data.updateSelf(); // 更新自身坐标
        //search target
        var newstate:String = null;
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        if(data.target == null){
            var 出生点列表 = [];
            for (var 单位 in _root.gameworld){
                var 出生点 = _root.gameworld[单位];
                if (出生点.是否从门加载主角 && 单位 != "出生地"){
                    if(Mover.isReachable(self, 出生点, 50, true)) {
                        出生点列表.push(出生点);
                    } else {
                        // _root.发布消息(出生点,"unReachable");
                    }
                    
                }
            }
            if(出生点列表.length > 0){
                data.target = engine.getRandomArrayElement(出生点列表);
                data.updateTarget();
                if(true) {
                    var aabb:AABB = AABB.fromMovieClip(data.target, 0);
                    AABBRenderer.renderAABB(AABBCollider.fromAABB(aabb), 0, "filled");
                }
                
                if(data.absdiff_x < 100 && data.absdiff_z < 50){
                    newstate = "Idle"; // 若离目标门太近则先进入Idle
                } else {
                    newstate = engine.randomCheckHalf() ? "Idle" : "Walking"; // 避免佣兵停留时间太短，概率逗留
                }
            }else{
                // 找不到目标时进入漫游状态
                newstate = "Wandering";
            }
        }
        if(newstate == null){
            newstate = engine.randomCheckHalf() ? "Idle" : "Walking"; // 兜底
        }

        // _root.发布消息(self, "think");

        this.superMachine.ChangeState(newstate);
    }

    // 移动
    public function walk():Void{
        // 更新目标出生点坐标,并且检查是否卡死
        var sm = this.superMachine;
        if(sm.actionCount % 4 == 0) {
            var isStuck:Boolean = data.stuckProbeByDiffChange(true, 8, 3); 
            
            // 如果检测到卡死，切换到漫游状态以获得自行解困能力
            if(isStuck){
                this.superMachine.ChangeState("Wandering");
                _root.发布消息(data.self, "检测到卡死，切换到漫游模式");
                return;
            }
        } else {
            data.updateTarget();
        }

        
        if(data.absdiff_x < 50 && data.absdiff_z < 25){
            data.self.删除可雇用单位();
            return;
        }


        if(sm.actionCount % 4 == 0){
            //每5次action判定移动方向
            var self = data.self;
            var X距离 = 20;
            var Y距离 = 10;

            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            if (data.absdiff_x > X距离){
                self.左行 = data.diff_x < 0;
                self.右行 = data.diff_x > 0;
            }
            if (data.absdiff_z > Y距离){
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
            }
        }
    }

    // 进入移动状态
    public function walk_enter():Void{
        data.think_threshold = LinearCongruentialEngine.instance.randomIntegerStrict(WALK_MIN_TIME, WALK_MAX_TIME);
    }

    // 进入停止状态
    public function idle_enter():Void{
        data.self.左行 = false;
        data.self.右行 = false;
        data.self.上行 = false;
        data.self.下行 = false;
        data.think_threshold = LinearCongruentialEngine.instance.randomIntegerStrict(IDLE_MIN_TIME, IDLE_MAX_TIME);
    }

    // 进入漫游状态
    public function wander_enter():Void{
        data.target = null; // 清除目标
        data.updateSelf(); // 更新自身坐标

        var self = data.self;
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;

        data.think_threshold = engine.randomIntegerStrict(WANDER_MIN_TIME, WANDER_MAX_TIME);

        if(data.standby) {
            // 待机状态下无法移动
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            return; 
        }

        var randy = engine.randomIntegerStrict(_root.Ymin, _root.Ymax);
        var randx = engine.randomIntegerStrict(_root.Xmin, _root.Xmax);
        
        self.左行 = randx < data.x;
        self.右行 = !self.左行;
        self.上行 = randy < data.z;
        self.下行 = randy > data.z;
    }
}
