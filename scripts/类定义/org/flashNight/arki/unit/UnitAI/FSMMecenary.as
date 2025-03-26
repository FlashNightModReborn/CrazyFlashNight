import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.neur.StateMachine.FSM_StateMachine;

import org.flashNight.arki.unit.UnitAI.UnitAIData;

// 场景中佣兵与可雇佣敌人NPC的状态机

class org.flashNight.arki.unit.UnitAI.FSMMecenary extends FSM_StateMachine{

    public static var IDLE_TIME:Number = 10; // 停止状态持续10次action（即40帧）
    public static var WALK_TIME:Number = 5; // 移动状态持续5次action（即20帧）

    // 数据黑板
    public var data:UnitAIData;

    public function FSMMecenary(_data:UnitAIData){
        super(null,null.null);
        this.data = _data;

        // 状态列表
        // 睡眠状态（默认状态）
        this.AddStatus("Sleeping",new FSM_Status(null, this.sleep_enter, null));
        // 思考状态，结算进入状态函数后一定会跳转至其他状态
        this.AddStatus("Thinking",new FSM_Status(null, this.think, null));
        // 空闲状态
        this.AddStatus("Idle",new FSM_Status(null, this.sleep_enter, null));
        // 移动状态
        this.AddStatus("Walking",new FSM_Status(null, this.walk_enter,null));

        //过渡线
        this.transitions.push("Idle","Thinking",function(){
            return this.actionCount >= FSMMecenary.IDLE_TIME;
        });
        this.transitions.push("Walking","Thinking",function(){
            return this.actionCount >= FSMMecenary.WALK_TIME;
        });

        // 检测到思考标签时结束睡眠状态进入思考状态
        this.transitions.push("Sleeping","Thinking",function(){
            return data.self.思考标签 != null && _root.暂停 !== true;
        });
        // 所有状态在游戏暂停时及思考标签不存在时均会过渡到睡眠状态
        this.transitions.push("Idle","Sleeping", this.sleepCheck);
        this.transitions.push("Walking","Sleeping", this.sleepCheck);
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
        if(data.target != null){
            data.updateTarget();
            if(data.absdiff_x < 50 && data.absdiff_z < 25){
                data.self.删除可雇用敌人();
                return;
            }
        }else{
            var 出生点列表 = [];
            for (var 单位 in _root.gameworld){
                var 出生点 = _root.gameworld[单位];
                if (出生点.是否从门加载主角 && 单位 != "出生地"){
                    出生点列表.push(出生点);
                }
            }
            data.target = 出生点列表[random(出生点列表.length)];
        }
        //
        var newstate:String = random(2) == 0 ? "Walking" : "Idle";
        this.superMachine.ChangeState(newstate);
    }

    //跟随
    public function walk_enter():Void{
        data.updateSelf(); // 更新自身坐标
        data.updateTarget(); // 更新目标出生点坐标
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
            var randz = _root.Ymin + random(_root.Ymax - _root.Ymin);
            if(Math.abs(data.z - randz) > Y距离){
                self.上行 = data.z > randz;
                self.下行 = data.z < randz;
            }
        }else if (data.absdiff_z > Y距离){
            self.上行 = data.diff_z < 0;
            self.下行 = data.diff_z > 0;
        }
    }
    //睡眠及各个停止函数通用
    public function sleep_enter():Void{
        data.self.左行 = false;
        data.self.右行 = false;
        data.self.上行 = false;
        data.self.下行 = false;
    }
}
