import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.bullet.Factory.BulletFactory;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * 灰蛊蚀刻霰弹延迟引爆控制器。
 *
 * 契约：
 * 1. 任意弹片真实命中存活且未处于蚀刻倒计时中的目标时，植入单个延迟引爆 Buff。
 * 2. 倒计时窗口内再次命中不叠加、不刷新、不覆盖已锁定的射击快照。
 * 3. 到达 delayFrames 后若目标仍存活，按植入瞬间锁定的武器快照注入一次零距离满弹片结算，
 *    并附带 detonationCrumble 血量上限击溃；目标提前阵亡则静默清理。
 * 4. 引爆用结算弹体不携带 hitBehavior，天然杜绝自我递归重挂。
 */
class org.flashNight.arki.component.Buff.Effect.GrayGooShotgunEtch extends MetaBuff {
    private static var ID_PREFIX:String = "灰蛊霰弹蚀刻_";
    private static var DEFAULT_STACK_GROUP:String = "grayGooShotgunEtch";

    private var _target:Object;
    private var _shooter:Object;
    private var _timer:TimeLimitComponent;
    private var _delayFrames:Number;
    private var _elapsed:Number;
    private var _resolved:Boolean;
    private var _snapshot:Object;

    public function GrayGooShotgunEtch(target:Object, shooter:Object, delayFrames:Number, snapshot:Object) {
        super([], [], 0);
        this._target = target;
        this._shooter = shooter;
        this._delayFrames = delayFrames;
        this._elapsed = 0;
        this._resolved = false;
        this._snapshot = snapshot;
        this._timer = new TimeLimitComponent(delayFrames);
        this.addComponent(this._timer);
    }

    public static function getStackGroupFor(config:Object):String {
        var value:Object = config ? config.stackGroup : null;
        var group:String = value != null ? String(value) : "";
        return group.length > 0 ? group : DEFAULT_STACK_GROUP;
    }

    public static function getBuffIdFor(config:Object):String {
        return ID_PREFIX + getStackGroupFor(config);
    }

    public static function applyToTarget(target:Object, shooter:Object,
                                         config:Object, bullet:Object):Boolean {
        if (!target || !(target.hp > 0) || target._killed === true || target.防止无限飞 === true) {
            return false;
        }
        if (!shooter || !config || !bullet || !target.buffManager) return false;

        var delayFrames:Number = Math.floor(Number(config.delayFrames));
        if (!(delayFrames >= 1) || !isFinite(delayFrames)) return false;

        var detonationCrumble:Number = Number(config.detonationCrumble);
        if (!(detonationCrumble >= 0) || !isFinite(detonationCrumble)) detonationCrumble = 0;

        var manager:BuffManager = target.buffManager;
        var id:String = getBuffIdFor(config);
        var existing:Object = manager.getBuffById(id);
        if (existing && typeof existing["isPending"] == "function" && existing.isPending()) {
            return false;
        }

        var snapshot:Object = buildShotSnapshot(shooter, bullet, detonationCrumble);
        var effect:GrayGooShotgunEtch = new GrayGooShotgunEtch(target, shooter, delayFrames, snapshot);
        if (manager.addBuffImmediate(effect, id) == null) {
            effect.destroy();
            return false;
        }
        target.grayGooEtchPending = true;
        effect.emitFeedbackVisual(1, 0);
        return true;
    }

    private static function buildShotSnapshot(shooter:Object, bullet:Object, detonationCrumble:Number):Object {
        var initialScatter:Number = Number(bullet.初始霰弹值);
        if (!(initialScatter > 0) || !isFinite(initialScatter)) {
            initialScatter = 1;
        } else {
            initialScatter = initialScatter >> 0;
        }

        var rawScatter:Number = Number(bullet.霰弹值);
        var currentScatter:Number = 1;
        if (rawScatter < -65535) {
            currentScatter = (-rawScatter) >>> 16;
        } else if (rawScatter > 0 && isFinite(rawScatter)) {
            currentScatter = rawScatter >> 0;
        }

        var pelletCount:Number = initialScatter > currentScatter ? initialScatter : currentScatter;
        if (!(pelletCount >= 1)) pelletCount = 1;

        var baseCrumble:Number = (bullet.击溃 > 0 && isFinite(Number(bullet.击溃))) ? Number(bullet.击溃) : 0;
        var finalCrumble:Number = !(baseCrumble > detonationCrumble) ? detonationCrumble : baseCrumble;

        var hitRate:Number = Number(bullet.命中率);
        if (isNaN(hitRate)) {
            hitRate = Number(shooter.命中率);
            if (isNaN(hitRate)) hitRate = 10000;
        }

        var snap:Object = {
            pelletCount: pelletCount,
            发射者: bullet.发射者 != undefined ? bullet.发射者 : shooter._name,
            子弹威力: (bullet.子弹威力 > 0 && isFinite(Number(bullet.子弹威力))) ? Number(bullet.子弹威力) : 0,
            固伤: bullet.固伤 | 0,
            百分比伤害: (bullet.百分比伤害 > 0 && isFinite(Number(bullet.百分比伤害))) ? Number(bullet.百分比伤害) : 0,
            伤害类型: bullet.伤害类型 != undefined ? bullet.伤害类型 : (shooter.伤害类型 != undefined ? shooter.伤害类型 : "物理"),
            魔法伤害属性: bullet.魔法伤害属性,
            命中率: hitRate,
            暴击: bullet.暴击,
            吸血: (bullet.吸血 > 0 && isFinite(Number(bullet.吸血))) ? Number(bullet.吸血) : 0,
            斩杀: (bullet.斩杀 > 0 && isFinite(Number(bullet.斩杀))) ? Number(bullet.斩杀) : 0,
            击溃: finalCrumble,
            毒: bullet.毒 | 0,
            nanoToxic: (bullet.nanoToxic > 0 && isFinite(Number(bullet.nanoToxic))) ? Number(bullet.nanoToxic) : 0,
            nanoToxicDecay: (bullet.nanoToxicDecay > 0 && isFinite(Number(bullet.nanoToxicDecay))) ? Number(bullet.nanoToxicDecay) : 0,
            击倒率: !isNaN(Number(bullet.击倒率)) ? Number(bullet.击倒率) : 10,
            水平击退速度: !isNaN(Number(bullet.水平击退速度)) ? Number(bullet.水平击退速度) : 10,
            垂直击退速度: bullet.垂直击退速度 | 0,
            Z轴攻击范围: (bullet.Z轴攻击范围 > 0 && isFinite(Number(bullet.Z轴攻击范围))) ? Number(bullet.Z轴攻击范围) : 40,
            不硬直: Boolean(bullet.不硬直),
            水平击退反向: Boolean(bullet.水平击退反向),
            友军伤害: Boolean(bullet.友军伤害),
            消音策略: bullet.消音策略,
            击中后子弹的效果: bullet.击中后子弹的效果 != undefined ? String(bullet.击中后子弹的效果) : "",
            __huofengDamageSnapshot: bullet.__huofengDamageSnapshot != undefined ? bullet.__huofengDamageSnapshot : (shooter.伤害加成 | 0),
            shooterName: shooter._name != undefined ? String(shooter._name) : "",
            shooterX: !isNaN(Number(shooter._x)) ? Number(shooter._x) : 0,
            shooterXScale: !isNaN(Number(shooter._xscale)) ? Number(shooter._xscale) : 100,
            isEnemy: Boolean(shooter.是否为敌人)
        };
        if (bullet.__huofengFinalPower === true) {
            snap.__huofengFinalPower = true;
        }
        return snap;
    }

    public function isPending():Boolean {
        return !this._resolved &&
               !this.isDestroyed() &&
               this._target != null &&
               this._target.hp > 0 &&
               this._target._killed !== true &&
               this._timer != null &&
               this._timer.getRemaining() > 0;
    }

    public function update(deltaFrames:Number):StateInfo {
        if (this._resolved) {
            return super.update(deltaFrames);
        }
        if (!this._target || !(this._target.hp > 0) || this._target._killed === true) {
            this._resolved = true;
            if (this._target) this._target.grayGooEtchPending = false;
            this.hidePreviousMark();
            if (this._timer) this._timer.setRemaining(0);
            return super.update(deltaFrames);
        }
        if (deltaFrames > 0) {
            this._elapsed += deltaFrames;
            if (this._elapsed >= this._delayFrames) {
                this._resolved = true;
                this._target.grayGooEtchPending = false;
                if (this._timer) this._timer.setRemaining(0);
                this.detonate();
            }
        }
        return super.update(deltaFrames);
    }

    private function detonate():Void {
        var targetRef = this._target;
        var snap:Object = this._snapshot;
        if (!targetRef || !(targetRef.hp > 0) || targetRef._killed === true || targetRef.防止无限飞 === true || !snap) {
            this.hidePreviousMark();
            return;
        }

        var shooterRef = this._shooter;
        if (!shooterRef) {
            shooterRef = {
                _name: snap.shooterName,
                _x: snap.shooterX,
                _xscale: snap.shooterXScale,
                是否为敌人: snap.isEnemy,
                伤害加成: snap.__huofengDamageSnapshot
            };
        }

        var hitX:Number = !isNaN(Number(targetRef._x)) ? Number(targetRef._x) : 0;
        var hitY:Number = !isNaN(Number(targetRef._y)) ? Number(targetRef._y) : 0;
        var hitZ:Number = !isNaN(Number(targetRef.Z轴坐标)) ? Number(targetRef.Z轴坐标) : 0;

        var props:Object = {
            子弹种类: (snap.pelletCount > 1) ? "横向联弹-普通子弹" : "普通子弹",
            霰弹值: snap.pelletCount,
            最小霰弹值: 1,
            发射者: snap.发射者,
            shootX: hitX,
            shootY: hitY,
            shootZ: hitZ,
            子弹威力: snap.子弹威力,
            固伤: snap.固伤,
            百分比伤害: snap.百分比伤害,
            伤害类型: snap.伤害类型,
            魔法伤害属性: snap.魔法伤害属性,
            命中率: snap.命中率,
            暴击: snap.暴击,
            吸血: snap.吸血,
            斩杀: snap.斩杀,
            击溃: snap.击溃,
            毒: snap.毒,
            nanoToxic: snap.nanoToxic,
            nanoToxicDecay: snap.nanoToxicDecay,
            击倒率: snap.击倒率,
            水平击退速度: snap.水平击退速度,
            垂直击退速度: snap.垂直击退速度,
            Z轴攻击范围: snap.Z轴攻击范围,
            不硬直: snap.不硬直,
            水平击退反向: snap.水平击退反向,
            友军伤害: snap.友军伤害,
            消音策略: snap.消音策略,
            击中后子弹的效果: snap.击中后子弹的效果,
            技能名: "灰蛊蚀刻引爆",
            lockShooterAttributes: true,
            __huofengDamageSnapshot: snap.__huofengDamageSnapshot
        };
        if (snap.__huofengFinalPower === true) {
            props.__huofengFinalPower = true;
        }

        var settlement:Object = BulletFactory.createSettlementBullet(props, shooterRef);
        var damageResult:Object = BulletQueueProcessor.injectHit(
            settlement, shooterRef, targetRef, hitX, hitY, 1, false
        );

        targetRef.grayGooEtchDetonationCount =
            (targetRef.grayGooEtchDetonationCount > 0 ? targetRef.grayGooEtchDetonationCount : 0) + 1;

        var resolvedCrumble:Number = (damageResult && damageResult._crumbleDamage > 0)
            ? Number(damageResult._crumbleDamage) : 0;

        if (targetRef.dispatcher) {
            targetRef.dispatcher.publish(
                "GrayGooEtchDetonated", targetRef, shooterRef, damageResult, snap.pelletCount, resolvedCrumble
            );
        }

        this.emitFeedbackVisual(3, resolvedCrumble);

        if (_root && _root.gameworld && typeof EffectSystem.Effect == "function" &&
            settlement.shouldGeneratePostHitEffect &&
            snap.击中后子弹的效果 != "" && snap.击中后子弹的效果 != "无") {
            EffectSystem.Effect(snap.击中后子弹的效果, hitX, hitY, snap.shooterXScale, undefined, true);
        }
    }

    private function hidePreviousMark():Void {
        if (!this._target) return;
        var targetKey:String = String(Dictionary.getStaticUID(this._target));
        var previous:MovieClip = this._target.grayGooLastMarkEffect;
        if (previous && previous._visible && previous.grayGooTargetKey === targetKey && previous.标志) {
            previous.标志._visible = false;
        }
    }

    private function emitFeedbackVisual(stageFrame:Number, resolvedCrumble:Number):Void {
        if (!this._target || !_root || !_root.gameworld || typeof EffectSystem.Effect != "function") {
            return;
        }
        var world:MovieClip = _root.gameworld;
        var point:Object = this.getFeedbackAnchor(world);
        var cameraScale:Number = Number(world._xscale) * 0.01;
        if (!(cameraScale > 0) || !isFinite(cameraScale)) cameraScale = 1;
        var displayScale:Number = 100 / cameraScale;

        var effect:MovieClip = EffectSystem.Effect("灰蛊裂隙特效", point.x, point.y,
            displayScale, !!_root.是否视觉元素);
        if (!effect) return;

        effect._yscale = displayScale;
        effect.effectType = "灰蛊裂隙特效";
        effect.targetFrame = stageFrame;

        var targetKey:String = String(Dictionary.getStaticUID(this._target));
        var previous:MovieClip = this._target.grayGooLastMarkEffect;
        if (previous && previous._visible && previous.grayGooTargetKey === targetKey && previous.标志) {
            previous.标志._visible = false;
        }
        effect.grayGooTargetKey = targetKey;
        this._target.grayGooLastMarkEffect = effect;

        if (effect.标志 && typeof effect.标志.gotoAndStop == "function") {
            effect.标志._visible = true;
            effect.标志.gotoAndStop(stageFrame);
        }

        var amount:Number = (resolvedCrumble > 0 && isFinite(resolvedCrumble)) ? resolvedCrumble : 0;
        effect.grayGooCrumbleAmount = amount;
        var burst:MovieClip = effect.击溃爆发;
        if (burst) {
            burst._visible = amount > 0;
            if (amount > 0) {
                burst.gotoAndStop(stageFrame);
                burst.动画._visible = true;
                burst.动画.gotoAndPlay(1);
            } else if (burst.动画) {
                burst.动画.gotoAndStop(1);
                burst.动画._visible = false;
            }
        }
    }

    private function getFeedbackAnchor(world:MovieClip):Object {
        var point:Object;
        var info:MovieClip = this._target.新版人物文字信息;
        if (typeof info == "movieclip") {
            var bounds:Object = info.getBounds(world);
            if (isFinite(Number(bounds.yMin)) && bounds.yMax > bounds.yMin && bounds.xMax > bounds.xMin) {
                point = {x: (bounds.xMin + bounds.xMax) * 0.5, y: bounds.yMin};
            }
        }
        if (!point) {
            var ix:Number = Number(this._target.icX);
            var iy:Number = Number(this._target.icY);
            point = {x: isFinite(ix) ? ix : 0, y: isFinite(iy) ? iy : -90};
            if (typeof this._target.localToGlobal == "function" && typeof world.globalToLocal == "function") {
                this._target.localToGlobal(point);
                world.globalToLocal(point);
            } else {
                point.x += Number(this._target._x) || 0;
                point.y += Number(this._target._y) || 0;
            }
        }
        var scale:Number = Number(world._xscale) * 0.01;
        if (!(scale > 0) || !isFinite(scale)) scale = 1;
        var wx:Number = Number(world._x) || 0;
        var wy:Number = Number(world._y) || 0;
        var screenX:Number = wx + point.x * scale;
        var screenY:Number = wy + point.y * scale - 24;
        var left:Number = 64, right:Number = Stage.width - 64;
        if (right < left) left = right = Stage.width * 0.5;
        if (screenX < left) screenX = left;
        if (screenX > right) screenX = right;
        var top:Number = 128, bottom:Number = Stage.height - 48;
        if (bottom < top) top = bottom;
        if (screenY < top) screenY = top;
        if (screenY > bottom) screenY = bottom;
        point.x = (screenX - wx) / scale;
        point.y = (screenY - wy) / scale;
        return point;
    }

    public function destroy():Void {
        if (!this._resolved) {
            this._resolved = true;
            if (this._target) this._target.grayGooEtchPending = false;
            this.hidePreviousMark();
        }
        this._snapshot = null;
        this._shooter = null;
        this._target = null;
        super.destroy();
    }
}
