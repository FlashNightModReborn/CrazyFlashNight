import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.arki.unit.UnitAI.EnemyBehavior;
import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.naki.Select.QuickSelect;
// 会拾取物品的敌人状态机，继承敌人基础状态机

class org.flashNight.arki.unit.UnitAI.PickupEnemyBehavior extends EnemyBehavior{

    public static var CHASE_PICKUP_TIME:Number = 30; // 最大拾取时间为120帧

    public function PickupEnemyBehavior(_data:UnitAIData){
        super(_data);

        // 状态列表
        // 已有状态包括从敌人状态机继承的 睡眠 思考 追击 跟随 空闲 随机移动
        // 拾取物品状态
        this.AddStatus("ChasingPickup",new FSM_Status(this.chase_pickup, null, null));

        // 过渡线
        this.pushGateTransition("ChasingPickup","Thinking",function(){
            var t = data.target;
            return t == null || t.area == null || this.actionCount >= PickupEnemyBehavior.CHASE_PICKUP_TIME;
        });
    }

    // 重构思考函数
    public function think():Void{
        data.updateSelf(); // 更新自身坐标
        // 默认最大拾取范围为800
        var self = data.self;
        var maxdistance = 800;
        // 寻找攻击目标
        var chaseTarget = self.攻击目标;

        // 先尝试解析现有仇恨目标；若已失效则清除并降级为重新索敌
        if (chaseTarget && chaseTarget != "无") {
            data.target = _root.gameworld[chaseTarget];
            var resolved:MovieClip = data.target;
            if (resolved == null || !(resolved.hp > 0)) {
                data.target = null;
                self.dispatcher.publish("aggroClear", self);
                chaseTarget = "无";
            }
        }

        // 当前无有效仇恨目标时执行主动索敌
        if (!chaseTarget || chaseTarget == "无") {
            var threshold = self.threatThreshold > 1 ? LinearCongruentialEngine.instance.randomIntegerStrict(1, self.threatThreshold) : self.threatThreshold;
            var target_enemy = TargetCacheManager.findNearestThreateningEnemy(self, 1, threshold);

            if (target_enemy) {
                // 最大拾取范围为最近敌人的距离与800中的最小值
                var distance:Number = Math.abs(target_enemy._x - data.x);
                if (distance > 0 && distance < maxdistance) maxdistance = distance;

                data.target = target_enemy;
                self.dispatcher.publish("aggroSet", self, target_enemy);
                self.拾取目标 = null;
            } else {
                data.target = null;
            }
        }
        // 寻找地上的可拾取物
        // 单位为己方单位时，判定背包是否已满，若背包已满则本张图无法再触发拾取
        if(self.允许拾取 && self.是否为敌人 == false){
            if(_root.物品栏.背包.getFirstVacancy() == -1) self.允许拾取 = false;
        }
        if(self.允许拾取){
            // 混合策略优化：小数据量用线性查找，大数据量用QuickSelect
            var 可拾取物距离表 = [];

            // 收集已落地的可拾取物
            for (var i in _root.pickupItemManager.pickupItemDict){
                var 可拾取物 = _root.pickupItemManager.pickupItemDict[i];
                if(可拾取物 != null && 可拾取物.area != null) {
                    可拾取物距离表.push({
                        物品: 可拾取物,
                        距离: Math.abs(可拾取物._x - data.x)
                    });
                }
            }

            // 根据数据量选择算法
            var target_item = null;
            var 最小距离 = maxdistance;

            if(可拾取物距离表.length == 0) {
                // 没有可拾取物，跳过
            } else if(可拾取物距离表.length <= 20) {
                // 小数据量（≤20个）：使用O(n)线性查找
                for(var j = 0; j < 可拾取物距离表.length; j++) {
                    if(可拾取物距离表[j].距离 < 最小距离) {
                        最小距离 = 可拾取物距离表[j].距离;
                        target_item = 可拾取物距离表[j].物品;
                    }
                }
            } else {
                // 大数据量（>20个）：使用QuickSelect高效选择
                var 最近记录 = QuickSelect.selectKth(
                    可拾取物距离表,
                    0,  // 找第0小（即最小值）
                    function(a, b) { return a.距离 - b.距离; }
                );

                if(最近记录.距离 < maxdistance) {
                    target_item = 最近记录.物品;
                }
            }

            // 若找到符合条件的可拾取物，进入拾取状态
            if(target_item != null){
                data.target = target_item;
                self.dispatcher.publish("aggroClear", self);
                self.拾取目标 = target_item._name;
                this.superMachine.ChangeState("ChasingPickup");
                return;
            }
        }

        // 无拾取目标时按战斗目标/主角生存决定状态
        if (data.target) {
            this.superMachine.ChangeState("Chasing");
            return;
        }

        var hero = TargetCacheManager.findHero();
        if (hero != data.player) {
            data.player = hero;
        }
        this.superMachine.ChangeState((!hero || !(hero.hp > 0)) ? "Evading" : "Following");
    }

    // 拾取物品
    public function chase_pickup():Void{
        // 更新自身与拾取目标的坐标及差值
        data.updateSelf();
        data.updateTarget();

        var self = data.self;
        var pickupXRange = isNaN(self.x轴拾取距离) ? 40 : self.x轴拾取距离;
        var pickupZRange = 20;
        if (data.absdiff_z < pickupZRange && data.absdiff_x < pickupXRange){
            //每次action判定是否进入拾取动画
            self.左行 = false;
            self.右行 = false;
            self.上行 = false;
            self.下行 = false;
            if (data.diff_x < 0){
                self.方向改变("左");
            }else if(data.diff_x > 0){
                self.方向改变("右");
            }
            self.状态改变("拾取");
        }else{
            var sm = this.superMachine;
            if(sm.actionCount % 2 == 0){
                //每2次action判定移动方向
                if (data.absdiff_x + data.absdiff_z < 150){
                    self.状态改变(self.攻击模式 + "行走");
                }else if(self.状态 != self.攻击模式 + "跑" && LinearCongruentialEngine.instance.randomCheck(3)){
                    self.状态改变(self.攻击模式 + "跑");
                }
                self.上行 = data.diff_z < 0;
                self.下行 = data.diff_z > 0;
                self.左行 = data.diff_x < 0;
                self.右行 = data.diff_x > 0;
            }
        }
    }
}
