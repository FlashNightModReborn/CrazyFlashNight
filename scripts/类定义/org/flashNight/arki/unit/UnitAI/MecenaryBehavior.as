import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.BaseUnitBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;

// 场景中佣兵与可雇佣敌人NPC的状态机，继承单位状态机基类

class org.flashNight.arki.unit.UnitAI.MecenaryBehavior extends BaseUnitBehavior{

    public static var IDLE_TIME:Number = 30; // 停止状态每30次action（120帧）切换状态
    public static var WALK_TIME:Number = 8; // 移动状态每8次action（32帧）判断一次是否切换状态

    public function MecenaryBehavior(_data:UnitAIData){
        super(_data);

        // 状态列表 
        // 已存在的包括基类的睡眠状态（默认状态）

        // 思考状态，结算进入状态函数后一定会跳转至其他状态
        this.AddStatus("Thinking",new FSM_Status(null, this.think, null));
        // 空闲状态
        this.AddStatus("Idle",new FSM_Status(null, this.sleep_enter, null));
        // 移动状态
        this.AddStatus("Walking",new FSM_Status(this.walk, null, null));

        //过渡线
        this.pushGateTransition("Idle","Thinking",function(){
            return this.actionCount >= MecenaryBehavior.IDLE_TIME;
        });
        this.pushGateTransition("Walking","Thinking",function(){
            return this.actionCount % MecenaryBehavior.WALK_TIME == 0 && LinearCongruentialEngine.instance.randomCheckHalf();
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.pushGateTransition("Sleeping","Thinking",this.wakeupCheck);
    }



    // 具体执行函数
    //思考
    public function think():Void{
        data.updateSelf(); // 更新自身坐标
        //search target
        var newstate:String = null;
        var engine:LinearCongruentialEngine = LinearCongruentialEngine.instance;
        if(data.target == null){
            var 出生点列表 = [];
            for (var 单位 in _root.gameworld){
                var 出生点 = _root.gameworld[单位];
                if (出生点.是否从门加载主角 && 单位 != "出生地"){
                    出生点列表.push(出生点);
                }
            }
            data.target = MovieClip(engine.getRandomArrayElement(出生点列表));
            data.updateTarget();
            if(data.absdiff_x < 100 && data.absdiff_z < 50){
                newstate = "Idle"; // 若离目标门太近则先进入Idle
            }
        }
        if(newstate == null){
            newstate = engine.randomCheckHalf() ? "Idle" : "Walking"; // 否则有1/2的几率进入Walking，1/2的几率进入Idle
        }
        this.superMachine.ChangeState(newstate);
    }

    //跟随
    public function walk():Void{
        data.updateSelf(); // 更新自身坐标
        data.updateTarget(); // 更新目标出生点坐标
        if(data.absdiff_x < 50 && data.absdiff_z < 25){
            data.self.删除可雇用单位();
            return;
        }
        var sm = this.superMachine;
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
}
