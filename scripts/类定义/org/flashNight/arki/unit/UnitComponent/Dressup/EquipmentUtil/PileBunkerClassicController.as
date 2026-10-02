import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupSubscriber;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;

/** 原版打桩机的普通狂野锤；保留原枪械帧动画，不接入进阶蓄压或燃气系统。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerClassicController {
    private var ref:Object;
    private var unit:MovieClip;
    private var equipment:Object;
    private var version:Number;
    private var active:Boolean;
    private var aliasActive:Boolean;
    private var tuning:Object;
    private var previousStyle:String;
    private var melee:PileBunkerMeleeProjection;
    private var oldBladeShoot:Function;
    private var wrappedBladeShoot:Function;
    private var placementHandler:Function;
    private var bladeClip:MovieClip;
    private var bladeOwner:Object;
    private var originalMatrix:flash.geom.Matrix;
    private var bladeMatrix:flash.geom.Matrix;
    private var facePoint:Object;

    public function PileBunkerClassicController(ownerRef:Object, param:Object) {
        ref = ownerRef; unit = ref.自机; equipment = unit.长枪; version = unit.version;
        tuning = param; active = true; aliasActive = false;
        bladeOwner = null; facePoint = null; unit.__pileBunkerClassic = this;
        configureAlias();
        var self:PileBunkerClassicController = this;
        oldBladeShoot = unit.刀口位置生成子弹;
        wrappedBladeShoot = function(owner:MovieClip, source:Object, knife:String):Void {
            if (!self.isCurrent() || !self.ownsBlade()) { self.oldBladeShoot.call(this,owner,source,knife); return; }
            if (!(self.unit.hp > 0) || self.unit.man.换弹标签 || !self.syncVisual()) return;
            self.melee.refresh();
            var projected:Object = {};
            for (var key:String in source) projected[key] = source[key];
            projected.伤害类型 = "物理"; projected.魔法伤害属性 = "";
            self.melee.projectBullet(projected);
            self.oldBladeShoot.call(this,owner,projected,knife);
        };
        if (aliasActive && typeof oldBladeShoot == "function") unit.刀口位置生成子弹 = wrappedBladeShoot;
        placementHandler = function():Void { self.syncVisual(); };
        if (aliasActive) DressupSubscriber.onPlacement(unit,"刀_引用",placementHandler,ref);
        if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
        ref.生命周期函数列表.push({动作:PileBunkerClassicController.cleanup,额外参数:ref});
    }

    private function configureAlias():Void {
        var power:Number = Number(tuning.bladePower);
        if (!(power > 0 && power < 100000) || !(ref.是否为主角 || unit.装备能力.复合枪械 === true)
                || typeof _root.刀配置 != "function") return;
        var intent:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(ref,"刀");
        if (intent == null) return;
        previousStyle = unit.兵器动作类型;
        _root.刀配置(unit._name,"桔色电子吉他",1);
        if (!RuntimeEquipmentProjection.commitSlotAlias(intent)) {
            RuntimeEquipmentProjection.cancelSlotAlias(intent); return;
        }
        var bladeProps:Object = {};
        for (var key:String in unit.刀属性) bladeProps[key] = unit.刀属性[key];
        var bonus:Number = Number(unit.装备刀锋利度加成);
        if (!isFinite(bonus)) bonus = 0;
        bladeProps.power = Math.floor(power * EquipmentConfigManager.getLevelMultiplier(equipment.value.level)) + bonus;
        bladeProps.actiontype = "狂野";
        unit.刀属性 = bladeProps; unit.刀_装扮 = unit.长枪_装扮;
        unit.刀_刀口数 = 3; unit.兵器动作类型 = "狂野";
        aliasActive = true;
        melee = new PileBunkerMeleeProjection(unit,equipment,"物理","");
        melee.refresh();
    }
    public function isCurrent():Boolean {
        return active && unit.__pileBunkerClassic === this && unit.version === version && unit.长枪 === equipment;
    }
    public function ownsBlade():Boolean {
        return aliasActive && unit.长枪 === equipment && unit.刀 === equipment && RuntimeEquipmentProjection.hasActiveAlias(unit,"刀","长枪");
    }
    public function syncVisual():Boolean {
        if (!isCurrent() || !ownsBlade()) return false;
        var blade:MovieClip = unit.刀_引用;
        if (!blade || !blade.动画 || !blade._parent) return false;
        if (bladeOwner == null || blade.__pileBunkerClassicOwner !== bladeOwner) {
            releaseVisual();
            if (!bindBlade(blade)) return false;
        }
        var bladeMode:Boolean = unit.攻击模式 == "兵器" || !!unit.man.兵器使用标签;
        var gun:MovieClip = unit.长枪_引用;
        if (gun.动画 && gun !== blade) gun.动画._visible = !bladeMode;
        blade.动画._visible = bladeMode;
        if (bladeMode) unit.兵器动作类型 = "狂野";
        return true;
    }
    private function bindBlade(blade:MovieClip):Boolean {
        if (blade.__pileBunkerClassicOwner != undefined) return false;
        for (var i:Number = 1; i < 4; i++) if (blade["刀口位置" + i] != undefined) return false;
        var animation:MovieClip = blade.动画;
        animation.gotoAndStop(1);
        var bounds:Object = animation.getRect(blade);
        var halfHeight:Number = Number(tuning.bladeFaceHalfHeight);
        var rotation:Number = Number(tuning.bladeRotation);
        if (!(bounds.xMax > bounds.xMin && bounds.yMax > bounds.yMin)
                || !isFinite(bounds.xMax) || !isFinite(bounds.yMax)
                || !(halfHeight > 0 && halfHeight < 500) || !isFinite(rotation)) return false;
        var axisY:Number = Number(blade.枪口位置._y);
        if (!isFinite(axisY)) axisY = (bounds.yMin + bounds.yMax) * .5;
        var turn:flash.geom.Matrix = new flash.geom.Matrix();
        turn.rotate(rotation * Math.PI / 180);
        originalMatrix = animation.transform.matrix;
        bladeMatrix = originalMatrix.clone(); bladeMatrix.concat(turn);
        bladeClip = blade; bladeOwner = {}; blade.__pileBunkerClassicOwner = bladeOwner;
        animation.transform.matrix = bladeMatrix;
        bladeMatrix = animation.transform.matrix;
        facePoint = {x:bounds.xMax,y:axisY};
        for (i = 1; i < 4; i++) {
            var marker:MovieClip = blade.createEmptyMovieClip("刀口位置" + i,blade.getNextHighestDepth());
            marker.__pileBunkerClassicOwner = bladeOwner;
            // 与进阶版相同的40x100判定片；真实面积不能用零尺寸空定位点替代。
            marker.beginFill(0,100); marker.moveTo(-20,-50); marker.lineTo(20,-50);
            marker.lineTo(20,50); marker.lineTo(-20,50); marker.lineTo(-20,-50); marker.endFill();
            marker._alpha = 0;
            var point:flash.geom.Point = turn.transformPoint(new flash.geom.Point(bounds.xMax,axisY+(i-2)*halfHeight));
            marker._x = point.x; marker._y = point.y; marker._rotation = rotation;
        }
        return true;
    }
    private function releaseVisual():Void {
        if (bladeOwner != null && bladeClip.__pileBunkerClassicOwner === bladeOwner) {
            for (var i:Number = 1; i < 4; i++) {
                var marker:MovieClip = bladeClip["刀口位置" + i];
                if (marker.__pileBunkerClassicOwner === bladeOwner) marker.removeMovieClip();
            }
            // 仅恢复仍由本实例写入的矩阵，不覆盖后来的挂载者。
            var current:flash.geom.Matrix = bladeClip.动画.transform.matrix;
            if (current.a == bladeMatrix.a && current.b == bladeMatrix.b && current.c == bladeMatrix.c
                    && current.d == bladeMatrix.d && current.tx == bladeMatrix.tx && current.ty == bladeMatrix.ty) {
                bladeClip.动画.transform.matrix = originalMatrix;
            }
            bladeClip.动画._visible = true;
            delete bladeClip.__pileBunkerClassicOwner;
        }
        bladeClip = null; bladeOwner = null; originalMatrix = null; bladeMatrix = null; facePoint = null;
    }
    public function dispose():Void {
        if (!active) return;
        if (unit.__pileBunkerClassic === this) {
            if (unit.刀口位置生成子弹 === wrappedBladeShoot) unit.刀口位置生成子弹 = oldBladeShoot;
            if (melee) melee.restore();
            if (ownsBlade() && unit.兵器动作类型 == "狂野") unit.兵器动作类型 = previousStyle;
            if (unit.长枪 === equipment && unit.长枪_引用.动画) unit.长枪_引用.动画._visible = true;
            delete unit.__pileBunkerClassic;
        }
        unit.dispatcher.unsubscribe("刀_引用",placementHandler,ref);
        if (ref.classicShotHandler) unit.dispatcher.unsubscribe("长枪射击",ref.classicShotHandler,ref);
        if (ref.classicGunPlacement) unit.dispatcher.unsubscribe("长枪_引用",ref.classicGunPlacement,ref);
        releaseVisual(); active = false;
    }
    public function getSnapshot():Object {
        return {active:isCurrent(),alias:ownsBlade(),geometryReady:bladeOwner != null,face:facePoint};
    }
    public static function cleanup(value:Object):Void { value.classicPileBunkerController.dispose(); }
}
