import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.item.LootMaterializationPlanner;

/**
 * 交互处理组件 - 负责处理地图元件的交互功能，如拾取等
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.InteractionHandler {
    
    // 交互距离常量
    private static var INTERACTION_Z_DISTANCE:Number = 50;
    private static var DEFAULT_PICKUP_AUDIO:String = "拾取音效.mp3";
    
    /**
     * 初始化目标的交互功能
     * @param target 要初始化的目标MovieClip
     */
    public static function initialize(target:MovieClip):Void {
        if (!target) return;
        if (target.__cf7InteractionHandlerInitialized === true
                && target.__cf7InteractionHandlerDispatcher === target.dispatcher) return;
        if (target.__cf7InteractionHandlerInitialized === true) {
            InteractionHandler.detachFromDispatcher(
                target, target.__cf7InteractionHandlerDispatcher);
        }
        delete target.__cf7InteractionHandlerInitialized;
        if (!target.dispatcher) {
            delete target.__cf7InteractionHandlerDispatcher;
            return;
        }
        target.__cf7InteractionHandlerDispatcher = target.dispatcher;

        // 三段接线必须整体成功；任一订阅失败都精确回滚，不能留下“已初始化”假状态。
        var initialized:Boolean = InteractionHandler.setupPickupDetection(target)
            && InteractionHandler.setupPickupHandler(target)
            && InteractionHandler.setupUnloadHandler(target);
        if (!initialized) {
            InteractionHandler.detachFromDispatcher(target, target.dispatcher);
            // 初始化失败后不会有 onUnload 清理机会，必须同时释放 arbiter known target 强引用。
            LootContainerService.handleTargetUnload(target);
            BoxInteractionArbiter.forget(target);
            delete target.__cf7InteractionHandlerDispatcher;
            return;
        }

        target.__cf7InteractionHandlerInitialized = true;
        // 只观察精确 authored 开发 fixture；普通箱子不会开启 S0 本地门。
        ChestS0SocketBridge.observeLocalFixture(target);
        _global.ASSetPropFlags(target, [
            "__cf7InteractionHandlerInitialized",
            "__cf7InteractionHandlerDispatcher",
            "__cf7InteractionGlobalFunc",
            "__cf7InteractionPickFunc",
            "__cf7InteractionDeathFunc",
            "__cf7InteractionUnloadHandlerId"
        ], 1, false);
    }
    
    /**
     * 设置拾取检测功能
     * @param target 要设置的目标MovieClip
     */
    private static function setupPickupDetection(target:MovieClip):Boolean {
        // 已识别箱型只允许走中央裁决器。注册失败必须使整段接线失败，
        // 不能回落到逐 target 全局监听，否则一次按键会重新扇出到多个箱子。
        if (BoxInteractionArbiter.isBoxPreset(target.presetName)) {
            return BoxInteractionArbiter.register(target, _root.gameworld);
        }
        if (!target.dispatcher
                || typeof target.dispatcher.subscribeGlobal != "function") return false;

        var pickUpFunc:Function = function():Void {
            if (this._killed) return; // 避免多次触发
            
            var focusedObject:MovieClip = TargetCacheManager.findHero();
            if (InteractionHandler.canInteract(this, focusedObject)) {
                this.dispatcher.publish("pickUpBox", this);
            }
        };
        target.__cf7InteractionGlobalFunc = pickUpFunc;
        if (!target.dispatcher.subscribeGlobal("interactionKeyDown", pickUpFunc, target)) {
            delete target.__cf7InteractionGlobalFunc;
            return false;
        }
        return true;
    }
    
    /**
     * 设置拾取处理功能，目前用到的只有箱子
     * @param target 要设置的目标MovieClip
     */
    private static function setupPickupHandler(target:MovieClip):Boolean {
        if (!target.dispatcher || typeof target.dispatcher.subscribe != "function") return false;
        var pickFunc:Function = function(target:MovieClip):Void {
            // SceneManager 在 attachMovie 后才 clone XML Parameters；提交互动时必须重读，
            // 不能依赖 initialize 阶段尚未出现的 authored 双 marker。
            ChestS0SocketBridge.observeLocalFixture(target);
            var s0Result:Object = ChestSessionService.beginFixture(
                target, ChestSessionService.SOURCE_ID);
            if (s0Result.handled) return;

            // 生产 Web 战利品箱在 kill 前先拿到唯一 reservation，并完整物化奖励。
            // 所有正网格箱都在这里进入 Web-only 权威；任何失败均保持 fail-closed，
            // 不得重新暴露已经退役的 Flash 资源箱 UI。
            var lootResult:Object = LootContainerService.beginFixture(target);
            if (lootResult.handled) {
                if (lootResult.reopen === true) {
                    // 原 target 始终保留 _killed；这里只恢复同一 authority/panel，禁止
                    // 再物化、再 kill、再执行 scavenger pickup 或重播拾取音效。
                    var resumed:Object = LootContainerService.resumeSuspended(target);
                    if (resumed == null || resumed.success !== true) {
                        trace("[LootContainer] suspended reopen rejected: "
                            + (resumed == null ? "unknown" : resumed.error));
                    }
                    return;
                }
                if (lootResult.reserved !== true) {
                    // Web-only 的 fail-closed 不能表现成“箱子偶尔没反应”。测试期必须把
                    // classifier / authority fence 的精确原因留在 trace，便于第一时间暴露
                    // 数据畸形、并发占用或未收束提交；仍然禁止回弹 Flash UI。
                    trace("[LootContainer] open rejected before materialization: reason="
                        + (lootResult.reason == undefined ? "unknown" : lootResult.reason)
                        + ", state="
                        + (lootResult.state == undefined ? "none" : lootResult.state));
                    return;
                }

                var materialized:Object = LootMaterializationPlanner.materialize(target);
                if (materialized == null || materialized.success !== true) {
                    LootContainerService.abortReservedOpen(target, "materialization_failed");
                    trace("[LootContainer] materialization rejected: "
                        + (materialized == null ? "planner_returned_null" : materialized.error));
                    return;
                }

                var committed:Object = LootContainerService.commitReservedOpen(
                    target, materialized.inventory,
                    function(box:MovieClip):Boolean {
                        return InteractionHandler.executePickup(box);
                    });
                if (!committed.success) {
                    // 物化完成后 service/journal 是唯一恢复依据。这里绝不撤销或重投影
                    // 到 Flash UI，否则会把协议/Host 故障伪装成一次成功的旧流程。
                    trace("[LootContainer] reserved commit rejected: "
                        + (committed.error == undefined ? "unknown" : committed.error));
                }
                return;
            }
            InteractionHandler.executePickup(target);
        };
        var deathFunc:Function = function(target:MovieClip):Void {
            // commitReservedOpen 要求 death 在同一 kill 调用栈内完成 own-target 证明。
            var lootDeath:Object = LootContainerService.observeDeath(target);
            if (lootDeath != null && lootDeath.handled === true
                    && lootDeath.ownKill !== true) {
                // 测试阶段必须显式暴露外部破坏、重入或时序漂移；这里仍只记录诊断，
                // 不得把未收束 authority 回弹到 Flash 资源箱 UI。
                trace("[LootContainer] unexpected target death: reason="
                    + (lootDeath.reason == undefined ? "unknown" : lootDeath.reason)
                    + ", state="
                    + (lootDeath.state == undefined ? "none" : lootDeath.state));
            }
            BoxInteractionArbiter.unregister(target);
            ChestS0SocketBridge.handleTargetInvalid(target);
        };
        target.__cf7InteractionPickFunc = pickFunc;
        target.__cf7InteractionDeathFunc = deathFunc;
        if (!target.dispatcher.subscribe("pickUpBox", pickFunc, target)) {
            delete target.__cf7InteractionPickFunc;
            delete target.__cf7InteractionDeathFunc;
            return false;
        }
        if (!target.dispatcher.subscribe("death", deathFunc, target)) {
            if (typeof target.dispatcher.unsubscribe == "function") {
                target.dispatcher.unsubscribe("pickUpBox", pickFunc, target);
            }
            delete target.__cf7InteractionPickFunc;
            delete target.__cf7InteractionDeathFunc;
            return false;
        }
        return true;
    }

    private static function setupUnloadHandler(target:MovieClip):Boolean {
        if (!target.dispatcher
                || typeof target.dispatcher.subscribeTargetEvent != "function") return true;
        var unloadFunc:Function = function():Void {
            // 未预期 unload 也必须释放 pending reservation；正常 own-kill unload 幂等。
            LootContainerService.handleTargetUnload(this);
            BoxInteractionArbiter.forget(this);
            ChestS0SocketBridge.handleTargetInvalid(this);
        };
        target.__cf7InteractionUnloadHandlerId = target.dispatcher.subscribeTargetEvent(
            "onUnload", unloadFunc, target);
        if (typeof target.__cf7InteractionUnloadHandlerId != "string"
                || target.__cf7InteractionUnloadHandlerId.length == 0) {
            delete target.__cf7InteractionUnloadHandlerId;
            return false;
        }
        return true;
    }

    /** 仅移除本组件在旧 dispatcher 上的精确订阅，用于 dispatcher 被替换的重初始化。 */
    private static function detachFromDispatcher(target:MovieClip, dispatcher:Object):Void {
        BoxInteractionArbiter.unregister(target);
        if (dispatcher !== undefined && dispatcher !== null) {
            if (typeof target.__cf7InteractionGlobalFunc == "function"
                    && typeof dispatcher.unsubscribeGlobal == "function") {
                dispatcher.unsubscribeGlobal(
                    "interactionKeyDown", target.__cf7InteractionGlobalFunc, target);
            }
            if (typeof target.__cf7InteractionPickFunc == "function"
                    && typeof dispatcher.unsubscribe == "function") {
                dispatcher.unsubscribe("pickUpBox", target.__cf7InteractionPickFunc, target);
            }
            if (typeof target.__cf7InteractionDeathFunc == "function"
                    && typeof dispatcher.unsubscribe == "function") {
                dispatcher.unsubscribe("death", target.__cf7InteractionDeathFunc, target);
            }
            if (typeof target.__cf7InteractionUnloadHandlerId == "string"
                    && typeof dispatcher.unsubscribeTargetEvent == "function") {
                dispatcher.unsubscribeTargetEvent(
                    "onUnload", target.__cf7InteractionUnloadHandlerId);
            }
        }
        delete target.__cf7InteractionGlobalFunc;
        delete target.__cf7InteractionPickFunc;
        delete target.__cf7InteractionDeathFunc;
        delete target.__cf7InteractionUnloadHandlerId;
    }
    
    /**
     * 检查两个对象是否可以交互
     * @param target 目标对象
     * @param hero 英雄对象
     * @return Boolean 如果可以交互返回true
     */
    public static function canInteract(target:MovieClip, hero:MovieClip):Boolean {
        if (!target || !hero || !target.area || !hero.area) {
            return false;
        }
        
        // 检查Z轴距离
        var zDistance:Number = Math.abs(target.Z轴坐标 - hero.Z轴坐标);
        if (zDistance >= INTERACTION_Z_DISTANCE) {
            return false;
        }
        
        // 检查区域碰撞
        return hero.area.hitTest(target.area);
    }
    
    /**
     * 执行拾取操作
     * @param target 要拾取的目标MovieClip
     */
    public static function executePickup(target:MovieClip):Boolean {
        if (!target || !target.dispatcher
                || typeof target.dispatcher.publish != "function") return false;
        // 发布死亡事件
        target.dispatcher.publish("kill", target);
        
        // 获取拾取者
        var scavenger:MovieClip = TargetCacheManager.findHero();
        if (!scavenger) return true;
        
        // 播放音效
        InteractionHandler.playPickupAudio(target);
        
        // 执行拾取逻辑
        if (scavenger.拾取) {
            scavenger.拾取();
        }
        return true;
    }
    
    /**
     * 播放拾取音效
     * @param target 拾取的目标MovieClip
     */
    private static function playPickupAudio(target:MovieClip):Void {
        var audio:String = target.audio || DEFAULT_PICKUP_AUDIO;
        _root.soundEffectManager.playSound(audio);

    }
    
    /**
     * 移除目标的所有交互监听器
     * @param target 要清理的目标MovieClip
     */
    public static function cleanup(target:MovieClip):Void {
        LootContainerService.handleTargetUnload(target);
        InteractionHandler.detachFromDispatcher(
            target, target.__cf7InteractionHandlerDispatcher);
        ChestS0SocketBridge.handleTargetInvalid(target);
        if (target.dispatcher) {
            target.dispatcher.unsubscribeAll();
        }
        delete target.__cf7InteractionHandlerInitialized;
        delete target.__cf7InteractionHandlerDispatcher;
    }
    
    /**
     * 设置交互距离
     * @param distance 新的交互距离
     */
    public static function setInteractionDistance(distance:Number):Void {
        INTERACTION_Z_DISTANCE = distance;
    }
}
