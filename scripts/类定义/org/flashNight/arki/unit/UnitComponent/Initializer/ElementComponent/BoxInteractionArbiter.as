import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.scene.SceneInteractionManager;
import org.flashNight.arki.item.LootContainerService;

/**
 * 箱子互动中央裁决器。
 *
 * 每个 gameworld 只订阅一个 interactionKeyDown；箱子在初始化和清理时
 * 显式注册/撤销，不扫描 gameworld。一次输入以距离平方和稳定注册序
 * 做单遍选择，最多只向一个胜出箱发布本地 pickUpBox。
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.BoxInteractionArbiter {

    private static var INTERACTION_Z_DISTANCE:Number = 50;
    private static var FARTHEST_DISTANCE:Number = Number.POSITIVE_INFINITY;

    /**
     * [{gameworld, handler, knownRecords, activeRecords, nextOrder}]
     * knownRecords 在单场景内保留首次 order，使撤销后重注册仍可复用。
     */
    private static var worldEntries:Array = [];

    // TestLoader 内部测试接缝；不挂 _root，不进入任何正常协议。
    private static var testContextEnabled:Boolean = false;
    private static var testHero:Object = null;
    private static var testSceneCurrent:Object = null;

    /** 判定是否为六种明确箱型。 */
    public static function isBoxPreset(presetName:String):Boolean {
        return presetName === "保险柜" ||
            presetName === "生存箱" ||
            presetName === "装备箱" ||
            presetName === "资源箱" ||
            presetName === "纸箱" ||
            presetName === "隐藏资源点";
    }

    /** 为指定 gameworld 幂等建立唯一全局监听。 */
    public static function initialize(gameworld:Object):Boolean {
        if (!gameworld || !gameworld.dispatcher ||
            typeof gameworld.dispatcher.subscribeGlobal != "function") {
            return false;
        }
        if (BoxInteractionArbiter.findWorldEntry(gameworld) != null) return true;

        var handler:Function = function():Void {
            BoxInteractionArbiter.handleGlobalInteraction(gameworld);
        };
        if (!gameworld.dispatcher.subscribeGlobal(
            "interactionKeyDown", handler, gameworld)) {
            return false;
        }

        worldEntries.push({
            gameworld: gameworld,
            handler: handler,
            knownRecords: [],
            activeRecords: [],
            nextOrder: 0
        });
        return true;
    }

    /** 注册箱子；重复注册幂等，撤销后重注册复用首次 order。 */
    public static function register(target:Object, gameworld:Object):Boolean {
        if (!target || !BoxInteractionArbiter.isBoxPreset(target.presetName)) return false;
        if (!gameworld) gameworld = target._parent;
        if (!BoxInteractionArbiter.initialize(gameworld)) return false;

        var entry:Object = BoxInteractionArbiter.findWorldEntry(gameworld);
        var record:Object = BoxInteractionArbiter.findKnownRecord(entry, target);
        if (record == null) {
            record = {
                target: target,
                registrationOrder: entry.nextOrder++,
                active: false
            };
            entry.knownRecords.push(record);
        }
        if (record.active) return true;

        record.active = true;
        entry.activeRecords.push(record);
        return true;
    }

    /** 撤销目标，但在当前 gameworld 生命期内保留其稳定 order。 */
    public static function unregister(target:Object):Boolean {
        if (!target) return false;
        for (var i:Number = 0; i < worldEntries.length; i++) {
            var records:Array = worldEntries[i].activeRecords;
            for (var j:Number = 0; j < records.length; j++) {
                var record:Object = records[j];
                if (record.target === target) {
                    record.active = false;
                    var last:Number = records.length - 1;
                    if (j != last) records[j] = records[last];
                    records.pop();
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * 真实 target onUnload 专用：同时释放 active 与 known 中对已销毁 MovieClip 的强引用。
     * nextOrder 永不回退；普通 cleanup/重初始化仍应使用 unregister 以复用稳定 order。
     */
    public static function forget(target:Object):Boolean {
        if (!target) return false;
        var removed:Boolean = false;
        for (var i:Number = 0; i < worldEntries.length; i++) {
            var entry:Object = worldEntries[i];
            var active:Array = entry.activeRecords;
            for (var j:Number = active.length - 1; j >= 0; j--) {
                if (active[j].target === target) {
                    active[j].active = false;
                    active[j] = active[active.length - 1];
                    active.pop();
                    removed = true;
                }
            }
            var known:Array = entry.knownRecords;
            for (j = 0; j < known.length; j++) {
                if (known[j].target === target) {
                    known[j].active = false;
                    known[j] = known[known.length - 1];
                    known.pop();
                    removed = true;
                    break;
                }
            }
        }
        return removed;
    }

    /** TestLoader 专用：验证 unload forget 不在长场景内累积 target 引用。 */
    public static function __getKnownRecordCount(gameworld:Object):Number {
        var entry:Object = BoxInteractionArbiter.findWorldEntry(gameworld);
        return entry == null ? 0 : entry.knownRecords.length;
    }

    /** 场景级清理：只取消本裁决器的那一个全局监听。 */
    public static function cleanup(gameworld:Object):Void {
        for (var i:Number = 0; i < worldEntries.length; i++) {
            var entry:Object = worldEntries[i];
            if (entry.gameworld === gameworld) {
                if (gameworld && gameworld.dispatcher &&
                    typeof gameworld.dispatcher.unsubscribeGlobal == "function") {
                    gameworld.dispatcher.unsubscribeGlobal(
                        "interactionKeyDown", entry.handler, gameworld);
                }
                var known:Array = entry.knownRecords;
                for (var j:Number = 0; j < known.length; j++) known[j].active = false;
                known.length = 0;
                entry.activeRecords.length = 0;

                var last:Number = worldEntries.length - 1;
                if (i != last) worldEntries[i] = worldEntries[last];
                worldEntries.pop();
                return;
            }
        }
    }

    /** TestLoader 专用：为全局监听注入英雄/场景优先级上下文。 */
    public static function __setTestInteractionContext(hero:Object, sceneCurrent:Object):Void {
        testContextEnabled = true;
        testHero = hero;
        testSceneCurrent = sceneCurrent;
    }

    /** TestLoader 专用：恢复正常解析路径。 */
    public static function __clearTestInteractionContext():Void {
        testContextEnabled = false;
        testHero = null;
        testSceneCurrent = null;
    }

    private static function handleGlobalInteraction(gameworld:Object):Void {
        var hero:Object;
        var sceneCurrent:Object;
        if (testContextEnabled) {
            hero = testHero;
            sceneCurrent = testSceneCurrent;
        } else {
            hero = TargetCacheManager.findHero();
            var sceneManager:SceneInteractionManager = SceneInteractionManager.instance;
            sceneCurrent = sceneManager ? sceneManager.currentMC : null;
        }
        BoxInteractionArbiter.dispatchWinner(gameworld, hero, sceneCurrent);
    }

    /** 单次候选快照 + 单遍最小值裁决。 */
    private static function dispatchWinner(
        gameworld:Object, hero:Object, sceneCurrent:Object):Boolean {
        if (sceneCurrent != null || !hero) return false;

        var entry:Object = BoxInteractionArbiter.findWorldEntry(gameworld);
        if (entry == null) return false;
        var records:Array = entry.activeRecords;
        var snapshot:Array = [];
        var i:Number;
        for (i = 0; i < records.length; i++) snapshot[i] = records[i];

        var winner:Object = null;
        var bestDistance:Number = FARTHEST_DISTANCE;
        var bestOrder:Number = FARTHEST_DISTANCE;
        for (i = 0; i < snapshot.length; i++) {
            var record:Object = snapshot[i];
            var target:Object = record.target;
            if (!record.active ||
                !BoxInteractionArbiter.isBoxPreset(target.presetName) ||
                !BoxInteractionArbiter.canInteract(target, hero)) {
                continue;
            }

            var distance:Number = BoxInteractionArbiter.distanceSquared(target, hero);
            var order:Number = record.registrationOrder;
            if (winner == null || distance < bestDistance ||
                (distance == bestDistance && order < bestOrder)) {
                winner = target;
                bestDistance = distance;
                bestOrder = order;
            }
        }

        if (winner == null || !winner.dispatcher ||
            typeof winner.dispatcher.publish != "function") {
            return false;
        }
        // 只发布胜出箱的本地事件，不写全局 consumed flag。
        winner.dispatcher.publish("pickUpBox", winner);
        return true;
    }

    private static function canInteract(target:Object, hero:Object):Boolean {
        if (!target) return false;
        // kill 是一次性奖励物化的事实，永不清回 false。唯一例外只恢复 exact
        // LOOT_SUSPENDED scene anchor 的交互资格，其余碰撞/Z/scene/input 门保持原样。
        var suspendedReopen:Boolean = target._killed === true
            && LootContainerService.canReopenSuspendedTarget(target);
        if ((target._killed && !suspendedReopen) || target.interactionEnabled === false ||
            target.pickupEnabled === false || !target.area || !hero.area ||
            typeof hero.area.hitTest != "function") {
            return false;
        }

        var targetZ:Number = Number(target.Z轴坐标);
        var heroZ:Number = Number(hero.Z轴坐标);
        var zDifference:Number = targetZ - heroZ;
        // 严格不等式同时屏蔽 NaN/Infinity，避免 AVM1 >= 的 NaN 陷阱。
        if (!BoxInteractionArbiter.isFiniteNumber(zDifference) ||
            !(Math.abs(zDifference) < INTERACTION_Z_DISTANCE)) {
            return false;
        }
        return hero.area.hitTest(target.area);
    }

    private static function distanceSquared(target:Object, hero:Object):Number {
        var targetX:Number = Number(target._x);
        var heroX:Number = Number(hero._x);
        var targetZ:Number = Number(target.Z轴坐标);
        var heroZ:Number = Number(hero.Z轴坐标);
        if (!BoxInteractionArbiter.isFiniteNumber(targetX) ||
            !BoxInteractionArbiter.isFiniteNumber(heroX) ||
            !BoxInteractionArbiter.isFiniteNumber(targetZ) ||
            !BoxInteractionArbiter.isFiniteNumber(heroZ)) {
            return FARTHEST_DISTANCE;
        }

        var dx:Number = targetX - heroX;
        var dz:Number = targetZ - heroZ;
        var result:Number = dx * dx + dz * dz;
        return BoxInteractionArbiter.isFiniteNumber(result)
            ? result : FARTHEST_DISTANCE;
    }

    /** (x - x) != 0 在 AVM1 中同时捕获 NaN 与 Infinity。 */
    private static function isFiniteNumber(value:Number):Boolean {
        return (value - value) == 0;
    }

    private static function findWorldEntry(gameworld:Object):Object {
        for (var i:Number = 0; i < worldEntries.length; i++) {
            if (worldEntries[i].gameworld === gameworld) return worldEntries[i];
        }
        return null;
    }

    private static function findKnownRecord(entry:Object, target:Object):Object {
        var known:Array = entry.knownRecords;
        for (var i:Number = 0; i < known.length; i++) {
            if (known[i].target === target) return known[i];
        }
        return null;
    }
}
