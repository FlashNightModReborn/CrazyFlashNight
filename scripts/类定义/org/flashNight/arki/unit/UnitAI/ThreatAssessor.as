import org.flashNight.arki.unit.UnitAI.UnitAIData;
import org.flashNight.arki.unit.UnitAI.AIEnvironment;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

// ThreatAssessor -- 威胁评估（从 ActionArbiter 提取）
//
// 前置条件：update 方法要求 data.updateSelf() 已在当帧执行。
// 数据源：全部从 data.* 聚合字段读取，不直读 MC。
class org.flashNight.arki.unit.UnitAI.ThreatAssessor {

    private var p:Object;

    // 撤退紧迫度
    private var _prevHpRatio:Number;
    private var _retreatUrgency:Number;

    // 包围度 + 近距密度
    private var _encirclement:Number;
    private var _nearbyCount:Number;
    private var _leftEnemyCount:Number;
    private var _rightEnemyCount:Number;
    private var _lastEncirclementFrame:Number;

    public function ThreatAssessor(personality:Object) {
        this.p = personality;
        _prevHpRatio = NaN;
        _retreatUrgency = 0;
        _encirclement = 0;
        _nearbyCount = 0;
        _leftEnemyCount = 0;
        _rightEnemyCount = 0;
        _lastEncirclementFrame = -999;
    }

    // ---- Getters ----

    public function getRetreatUrgency():Number {
        return _retreatUrgency;
    }

    public function getEncirclement():Number {
        return _encirclement;
    }

    public function getNearbyCount():Number {
        return _nearbyCount;
    }

    public function getLeftEnemyCount():Number {
        return _leftEnemyCount;
    }

    public function getRightEnemyCount():Number {
        return _rightEnemyCount;
    }

    // ---- 撤退紧迫度（burst damage tracking）----

    // hpRatio 从 data.hp / data.hpMax 读取（聚合字段，零 MC 直读）
    public function updateRetreatUrgency(data:UnitAIData, frame:Number):Void {
        var maxHP:Number = data.hpMax;
        var hpRatio:Number = (maxHP > 0) ? Math.max(0, Math.min(1, data.hp / maxHP)) : 1;
        var hpDelta:Number = hpRatio - _prevHpRatio;
        _prevHpRatio = hpRatio;
        if (isNaN(hpDelta)) hpDelta = 0;
        if (hpDelta < -0.01) {
            _retreatUrgency = Math.min(1,
                _retreatUrgency + Math.max(0, -hpDelta - p.勇气 * 0.15) * 3);
        }
        _retreatUrgency *= 0.92;
        if (_retreatUrgency < 0.05) _retreatUrgency = 0;
    }

    // ---- 空间感知（包围度 + 近距密度 + 射弹预警）----

    // 包围度/近距密度每 16 帧周期性采样，射弹预警逐帧。
    // 射弹数据从 data.btFrame/btCount/btMinETA 读取（聚合字段，零 MC 直读）。
    public function updateSpatialAwareness(data:UnitAIData, frame:Number):Void {
        var self:MovieClip = data.self;

        // 包围度 + 近距密度检测（周期性，每 16 帧）
        if (frame - _lastEncirclementFrame >= 16) {
            _lastEncirclementFrame = frame;
            var scanRange:Number = 250;
            var leftCount:Number = TargetCacheManager.getEnemyCountInRange(self, 8, scanRange, 0, true);
            var rightCount:Number = TargetCacheManager.getEnemyCountInRange(self, 8, 0, scanRange, true);
            _leftEnemyCount = leftCount;
            _rightEnemyCount = rightCount;
            _encirclement = Math.min(1, leftCount * rightCount / 4);
            _nearbyCount = TargetCacheManager.getEnemyCountInRange(self, 16, 150, 150, true);
        }

        // 包围加剧低勇气角色的撤退紧迫度
        if (_encirclement > 0.2) {
            var courageDampen:Number = 1.0 - p.勇气;
            _retreatUrgency = Math.min(1, _retreatUrgency + _encirclement * courageDampen * 0.3);
        }

        // 射弹预警（从 data 聚合字段读取）
        var btAge:Number = frame - data.btFrame;
        var btCount:Number = data.btCount;
        if (btAge >= 0 && btAge <= 1 && !isNaN(btCount) && btCount > 0) {
            var btETA:Number = data.btMinETA - btAge;
            if (isNaN(btETA) || btETA < 0) btETA = 0;
            var btUrgency:Number = Math.min(0.5, btCount * 0.1)
                * Math.max(0, 1 - btETA / 20)
                * (1 - p.勇气 * 0.7);
            _retreatUrgency = Math.min(1, _retreatUrgency + btUrgency);
        }
    }
}
