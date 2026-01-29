// 文件路径：org/flashNight/arki/unit/Action/Shoot/ShootCore.as

import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

class org.flashNight.arki.unit.Action.Shoot.ShootCore {

    // 缓存的参数对象，仅有两种配置：主手与副手（保持原样）
    public static var primaryParams:Object = {
        shootingStateName: "主手射击中",
        actionFlagName: "动作A",
        prefix: "",
        bulletAttrKeys: ["子弹属性"],
        shootBulletAttrKey: "子弹属性",
        gunPath: "枪.枪.装扮.枪口位置",
        taskName: "keepshooting",
        playerBulletField: "子弹数"
    };

    public static var secondaryParams:Object = {
        shootingStateName: "副手射击中",
        actionFlagName: "动作B",
        prefix: "2",
        bulletAttrKeys: ["子弹属性", "子弹属性2"],
        shootBulletAttrKey: "子弹属性2",
        gunPath: "枪2.枪.装扮.枪口位置",
        taskName: "keepshooting2",
        playerBulletField: "子弹数_2"
    };

    /**
     * 全局缓存池：以 params 对象的 UID 作为键，存储解析后的配置
     */
    private static var _paramsCache:Object = {};

    /** 半自动锁属性名前缀，拼接 taskName 后存储在 core 上 */
    private static var SEMI_LOCK_PREFIX:String = "_semiLock_";

    /** 半自动射速间隔锁（key: "单位名_任务名" → true），由 EnhancedCooldownWheel 定时清除，帧同步 */
    public static var _lastShotTimes:Object = {};

    /** 半自动按键释放标记属性名前缀，存储在 core 上，用于枪械师技能判断点按/连按 */
    private static var SEMI_RELEASED_PREFIX:String = "_semiReleased_";

    /** 枪械师半自动：按键释放轮询任务属性名前缀（存储在 core 上） */
    private static var GUNSLINGER_RELEASE_POLL_PREFIX:String = "_gunslingerReleasePoll_";

    /** 枪械师半自动：连射链任务属性名前缀（存储在 core 上，避免污染 keepshooting/keepshooting2） */
    private static var GUNSLINGER_CHAIN_PREFIX:String = "_gunslingerChain_";

    /** 枪械师技能：点按间隔倍率（奖励） - 已废弃，使用动态计算方法 */
    public static var GUNSLINGER_TAP_MULTIPLIER:Number = 0.85;
    /** 枪械师技能：按住间隔倍率（惩罚） - 已废弃，使用动态计算方法 */
    public static var GUNSLINGER_HOLD_MULTIPLIER:Number = 1.25;

    /**
     * 根据枪械师等级计算半自动点按倍率
     * @param level 枪械师等级（1-10）
     * @return 点按倍率（1级=1.0，10级=0.85，线性插值）
     */
    public static function calcGunslingerTapMultiplier(level:Number):Number {
        if (level <= 0 || isNaN(level)) return 1.0;
        if (level >= 10) return 0.85;
        // 线性插值：1级=1.0，10级=0.85
        return 1.0 - (level - 1) * 0.15 / 9;
    }

    /**
     * 根据枪械师等级计算半自动连按倍率
     * @param level 枪械师等级（1-10）
     * @return 连按倍率（1级=1.5，10级=1.25，线性插值）
     */
    public static function calcGunslingerHoldMultiplier(level:Number):Number {
        if (level <= 0 || isNaN(level)) return 1.5;
        if (level >= 10) return 1.25;
        // 线性插值：1级=1.5，10级=1.25
        return 1.5 - (level - 1) * 0.25 / 9;
    }

    /**
     * 内核函数：处理持续射击的通用逻辑
     * @param core           当前作战对象（自机）
     * @param attackMode     攻击模式（用作方法名称拼接）
     * @param shootSpeed     射击速度
     * @param params         参数对象，包含各个包装函数不同的配置项：
     *   - shootingStateName: String, 如 "主手射击中" 或 "副手射击中"
     *   - actionFlagName   : String, 如 "动作A" 或 "动作B"
     *   - prefix           : String, 帧名称后缀（主手为空，副手为 "2"）
     *   - bulletAttrKeys   : Array, 需要重置角度偏移的子弹属性键，如 ["子弹属性"] 或 ["子弹属性", "子弹属性2"]
     *   - shootBulletAttrKey: String, 实际用于射击时的子弹属性键
     *   - gunPath          : String, 指定枪口位置的路径，如 "枪.枪.装扮.枪口位置"
     *   - taskName         : String, 帧计时器中任务的名称，如 "keepshooting" 或 "keepshooting2"
     *   - playerBulletField: String, 玩家界面中需要更新的子弹数属性，如 "子弹数" 或 "子弹数_2"
     * @return Boolean       返回是否处于持续射击状态
     */
    public static function continuousShoot(core:Object, attackMode:String, shootSpeed:Number, params:Object):Boolean {
        // 缓存常用全局对象和属性引用
        var root:Object = _root;
        var man:Object  = core.man;
        var controlTarget:Object = root.控制目标;

        // 利用 Dictionary.getStaticUID 为 params 建立或获取缓存配置
        var uid:Number = Dictionary.getStaticUID(params);
        var config:Object = _paramsCache[uid];
        if (!config) {
            config = {
                shootingStateName:  params.shootingStateName,
                actionFlagName:     params.actionFlagName,
                prefix:             params.prefix,
                bulletAttrKeys:     params.bulletAttrKeys,
                shootBulletAttrKey: params.shootBulletAttrKey,
                taskName:           params.taskName,
                playerBulletField:  params.playerBulletField,
                gunPathArray:       params.gunPath.split("."),
                baseShootFrame:     "射击" + params.prefix
            };
            _paramsCache[uid] = config;
        }

        // 缓存配置中的关键字段到局部变量
        var shootStateName:String = config.shootingStateName;
        var actionFlagName:String = config.actionFlagName;
        var bulletAttrKeys:Array = config.bulletAttrKeys;
        var len:Number = bulletAttrKeys.length;

        // 初始状态设定
        core.射击最大后摇中 = false;
        if (!man.射击许可标签) {
            // _root.发布消息("主角函数.射击许可", "不允许射击");
            core[shootStateName] = false;
            // 移除现有射击任务
            EnhancedCooldownWheel.I().removeTask(core[config.taskName]);
            return false;
        }

        // 根据当前状态预设角度偏移和动画帧名称
        var offset:Number = 0;
        var jumpFrameName:String = config.baseShootFrame;
        var isControlTarget:Boolean = (controlTarget === core._name);
        var dispatcher:EventDispatcher = core.dispatcher;
        if (isControlTarget && !core.上下移动射击) {
            if (core.下行) {
                offset = 30;
                jumpFrameName = "下射击" + config.prefix;
            } else if (core.上行) {
                offset = -30;
                jumpFrameName = "上射击" + config.prefix;
            }
        }

        // _root.发布消息(core.下行, core.上行, offset, jumpFrameName)

        // 更新所有需要重置的子弹属性角度偏移
        for (var i:Number = 0; i < len; i++) {
            man[bulletAttrKeys[i]].角度偏移 = offset;
        }

        // 预计算需要调用的函数和属性名
        var shootMethodName:String  = attackMode + "射击";
        var magazineCapName:String  = attackMode + "弹匣容量";

        // 执行射击逻辑
        core[shootStateName] = false;

        if (core[actionFlagName]) {
            dispatcher.publish(attackMode + "射击");
            // _root.发布消息(attackMode + "射击");
            man.gotoAndPlay(jumpFrameName);

            // 利用缓存的 gunPathArray 快速获取枪口位置引用
            var gunRef:Object = man;
            var gunPath:Array = config.gunPathArray;
            var pathLen:Number = gunPath.length;
            for (var p:Number = 0; p < pathLen; p++) {
                gunRef = gunRef[gunPath[p]];
            }
            // 调用具体射击方法，并将结果缓存
            var shootBulletAttrKey:String = config.shootBulletAttrKey;
            var bulletAttr:Object = man[shootBulletAttrKey];
            // _root.发布消息(bulletAttr.子弹种类, bulletAttr.击中地图)
            core[shootStateName] = core[shootMethodName](gunRef, bulletAttr);

            // 更新弹匣剩余子弹数量
            var magazineRemaining:Number = bulletAttr.ammoCost * (core[magazineCapName] - core[attackMode].value.shot);
            dispatcher.publish("updateBullet", core, shootStateName, magazineRemaining, config.playerBulletField);
            if (shootSpeed > 300) {
                // [v1.3] 使用生命周期 API 自动管理后摇任务
                EnhancedCooldownWheel.I().addOrUpdateTask(
                    core, "结束射击后摇",
                    function(target:Object):Void { target.射击最大后摇中 = false; },
                    300, false, 0, [core]
                );
            }
        }

        // 根据当前状态返回是否仍在持续射击中，并清理任务
        if (core[shootStateName]) {
            return true;
        }
        // 移除现有射击任务
        EnhancedCooldownWheel.I().removeTask(core[config.taskName]);
        return false;
    }

    /**
     * 处理射击的启动逻辑（主手/副手通用）
     *
     * 职责：
     * 1. 状态检查：射击中/换弹中状态快速返回
     * 2. 弹匣容量验证：触发自动换弹逻辑
     * 3. 射击许可检查：验证是否允许射击
     * 4. 启动持续射击任务：通过帧计时器驱动射击循环
     *
     * @param core         自机对象的 MovieClip 引用（通常为 this._parent）
     * @param protagonist  主角功能对象（包含换弹标签、射击速度等属性）
     * @param params       射击配置参数对象（主副手参数对象）
     *
     * @see ShootCore.continuousShoot  实际执行持续射击的核心逻辑
     * @see ShootCore.primaryParams    主手射击的标准配置
     * @see ShootCore.secondaryParams  副手射击的标准配置
     *
     * @example 典型调用方式（主手）：
     * ShootCore.startShooting(
     *     _parent,
     *     this,
     *     ShootCore.primaryParams
     * );
     *
     * @internal 关键流程说明：
     * 1. 通过 params.shootingStateName 获取当前武器的射击状态字段名
     * 2. 使用 attackMode 动态拼接弹匣容量字段（如"突击弹匣容量"）
     * 3. 当弹匣打空且满足条件时，调用 protagonist.开始换弹()
     * 4. 通过帧计时器添加持续射击任务，任务名由 params.taskName 定义
     * 5. 长射击间隔（>300ms）时添加后摇状态解除任务
     */

    public static function startShooting(
        core:Object,           // 自机对象（原 parent）
        protagonist:Object,       // 原主角函数对象（原 this）
        params:Object             // 主副手参数（primaryParams/secondaryParams）
    ):Void {
        // 若正在该状态射击中或正在换弹，直接返回
        if (core[params.shootingStateName] || protagonist.换弹标签) return;

        // 半自动冷却检查：锁标记存储在 core 上，随 MC 生命周期自动释放
        var semiLockProp:String = SEMI_LOCK_PREFIX + params.taskName;
        if (core[semiLockProp]) return;

        // 缓存攻击模式与射击速度
        var attackMode:String = core.攻击模式;
        var interval:Number = protagonist.射击速度;
        // 弹匣容量键名
        var magazineCapName:String = attackMode + "弹匣容量";


        // 检查弹匣是否打空
        if (core[attackMode].value.shot >= core[magazineCapName]) {
            // 若剩余弹匣>0 或非控制目标，触发换弹
            if (protagonist.剩余弹匣数 > 0 || _root.控制目标 != core._name) {
                protagonist.开始换弹();
            }
            return;
        }

        // 检查射击许可标签
        if (!protagonist.射击许可标签) {
            // _root.发布消息("主角函数.射击许可", "不允许射击");
            return;
        }

        // 半自动射速间隔防御：即使 core 重建导致锁标记丢失，轮定时器仍可保障最小间隔
        // 仅对玩家控制的单位启用半自动逻辑，AI 统一走全自动分支
        var isSemiAuto:Boolean = protagonist.是否单发 && (TargetCacheManager.findHero() === core);
        var rateKey:String = null;
        if (isSemiAuto) {
            rateKey = core._name + "_" + params.taskName;
            if (_lastShotTimes[rateKey]) return;
        }

        // 枪械师技能半自动优化：半自动支持"按住=1.25x自动连射 / 点按=0.85x更快间隔"
        // 实现方式：
        // - 连按（按住不放）：由 _gunslingerContinuousShoot 以 1.25x 间隔调度下一发，startShooting 每帧调用时直接返回，避免叠加
        // - 点按（每发都松开）：以 0.85x 作为最小间隔解锁下一次 startShooting
        var hasGunslingerSkill:Boolean = isSemiAuto && core.被动技能 && core.被动技能.枪械师 && core.被动技能.枪械师.启用;
        var semiReleasedProp:String = hasGunslingerSkill ? (SEMI_RELEASED_PREFIX + params.taskName) : null;
        var chainProp:String = hasGunslingerSkill ? (GUNSLINGER_CHAIN_PREFIX + params.taskName) : null;
        var gunslingerLevel:Number = hasGunslingerSkill ? (core.被动技能.枪械师.等级 || 1) : 1;
        var tapInterval:Number = hasGunslingerSkill ? (interval * calcGunslingerTapMultiplier(gunslingerLevel)) : interval;
        var holdInterval:Number = hasGunslingerSkill ? (interval * calcGunslingerHoldMultiplier(gunslingerLevel)) : interval;

        // 枪械师半自动：当连射链存在时，交由链任务驱动下一发，避免"清锁帧"与 startShooting 同帧触发导致叠加
        if (hasGunslingerSkill && core[chainProp] != null) {
            return;
        }

        // 调用持续射击核心逻辑
        if (ShootCore.continuousShoot(core, attackMode, interval, params)) {
            if (hasGunslingerSkill) {
                // 枪械师技能：半自动武器连射
                // 1) 点按收益：以 0.85x 作为最小射击间隔（解锁下一次 startShooting）
                _lastShotTimes[rateKey] = true;
                EnhancedCooldownWheel.I().addTask(ShootCore._clearRateLimit, tapInterval, false, rateKey);
                core[params.shootingStateName] = false;

                // 2) 按住自动：注册连射链（固定 1.25x 间隔）
                core[chainProp] = EnhancedCooldownWheel.I().addTask(
                    ShootCore._gunslingerContinuousShoot,
                    holdInterval,
                    false, // 一次性：由回调自行决定是否继续
                    core,
                    attackMode,
                    interval, // 基础间隔
                    params,
                    chainProp,
                    semiReleasedProp
                );

                // 3) 轮询检测按键释放：释放时取消连射链，避免挂起任务干扰点按节奏
                var pollProp:String = GUNSLINGER_RELEASE_POLL_PREFIX + params.taskName;
                var existingPoll = core[pollProp];
                if (existingPoll != null) {
                    EnhancedCooldownWheel.I().removeTask(existingPoll);
                    delete core[pollProp];
                }
                core[pollProp] = EnhancedCooldownWheel.I().addTask(
                    ShootCore._pollGunslingerRelease,
                    33,
                    true,
                    core,
                    pollProp,
                    chainProp,
                    params.actionFlagName,
                    semiReleasedProp
                );
            } else if (isSemiAuto) {
                // 普通半自动模式：仅射击一发，需要释放按键才能继续
                _lastShotTimes[rateKey] = true;
                EnhancedCooldownWheel.I().addTask(ShootCore._clearRateLimit, interval, false, rateKey);
                core[params.shootingStateName] = false;
                core[semiLockProp] = true;
                EnhancedCooldownWheel.I().addTask(
                    ShootCore._onSemiCooldownDone,
                    interval,
                    false,
                    core,
                    semiLockProp,
                    params.actionFlagName,
                    null
                );
            } else {
                // 全自动模式：注册持续射击循环任务
                core[params.taskName] = EnhancedCooldownWheel.I().addTask(
                    ShootCore.continuousShoot,
                    interval,
                    true,
                    core,
                    attackMode,
                    interval,
                    params
                );
            }

            // 若射击间隔较长，添加后摇解除任务
            if (interval > 300) {
                // [v1.3] 使用生命周期 API 自动管理后摇任务
                EnhancedCooldownWheel.I().addOrUpdateTask(
                    core, "结束射击后摇",
                    function(自机:MovieClip):Void { 自机.射击最大后摇中 = false; },
                    300, false, 0, [core]
                );
            }
        }
    }

    /**
     * 半自动射速间隔冷却回调：由 EnhancedCooldownWheel 在 interval 后触发，清除射速锁
     * @param key 射速间隔锁的键（格式: "单位名_任务名"）
     */
    public static function _clearRateLimit(key:String):Void {
        delete _lastShotTimes[key];
    }

    /**
     * 半自动Phase1回调：最小射击间隔已过
     * 检查按键是否已释放。若已释放则立即解锁；
     * 若仍被按住则启动轮询，等待释放后再解锁。
     *
     * @param core           自机对象引用（MC重建后引用失效，锁属性随之消失）
     * @param lockProp       锁标记属性名（存储在 core 上）
     * @param actionFlagName 动作标志属性名（如"动作A"）
     * @param releasedProp   释放标记属性名（用于枪械师技能判断）
     */
    public static function _onSemiCooldownDone(core:Object, lockProp:String, actionFlagName:String, releasedProp:String):Void {
        if (!core[lockProp]) return; // MC已重建或被cleanup清理

        // 按键已释放，直接解锁，并标记为已释放（用于枪械师点按判断）
        if (!core[actionFlagName]) {
            delete core[lockProp];
            if (releasedProp) core[releasedProp] = true;
            return;
        }

        // 按键仍被按住，启动轮询检测释放（~30fps频率）
        core[lockProp] = EnhancedCooldownWheel.I().addTask(
            ShootCore._pollRelease,
            33,
            true,
            core,
            lockProp,
            actionFlagName,
            releasedProp
        );
    }

    /**
     * 半自动Phase2轮询：检测按键释放
     * 当按键释放（或core引用失效）时，清除冷却锁定并停止轮询
     *
     * @param core           自机对象引用
     * @param lockProp       锁标记属性名
     * @param actionFlagName 动作标志属性名
     * @param releasedProp   释放标记属性名（用于枪械师技能判断）
     */
    public static function _pollRelease(core:Object, lockProp:String, actionFlagName:String, releasedProp:String):Void {
        if (!core[actionFlagName]) {
            var task = core[lockProp];
            delete core[lockProp];
            if (task != null && typeof task == "number") {
                EnhancedCooldownWheel.I().removeTask(task);
            }
            // 标记按键已释放（用于枪械师点按判断）
            if (releasedProp) core[releasedProp] = true;
        }
    }

    /**
     * 枪械师半自动：按键释放轮询（用于取消连射链）
     *
     * @param core            自机对象引用
     * @param pollProp        轮询任务ID存储属性名（存储在 core 上）
     * @param chainTaskProp   连射链任务ID存储属性名（通常为 params.taskName）
     * @param actionFlagName  动作标志属性名（如"动作A"）
     * @param releasedProp    释放标记属性名（用于点按识别，可选）
     */
    public static function _pollGunslingerRelease(
        core:Object,
        pollProp:String,
        chainTaskProp:String,
        actionFlagName:String,
        releasedProp:String
    ):Void {
        if (core[actionFlagName]) return;

        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();

        // 1) 取消轮询自身
        var pollTaskId = core[pollProp];
        delete core[pollProp];
        if (pollTaskId != null && typeof pollTaskId == "number") {
            wheel.removeTask(pollTaskId);
        }

        // 2) 取消连射链（若仍挂起）
        var chainTaskId = core[chainTaskProp];
        delete core[chainTaskProp];
        if (chainTaskId != null && typeof chainTaskId == "number") {
            wheel.removeTask(chainTaskId);
        }

        // 3) 标记按键已释放（用于点按识别）
        if (releasedProp) core[releasedProp] = true;
    }

    /**
     * 枪械师技能连射回调：半自动武器的连射支持
     * 每次射击后检测按键状态，动态调整下次射击间隔
     *
     * @param core           自机对象引用
     * @param attackMode     攻击模式
     * @param baseInterval   基础射击间隔
     * @param params         射击参数对象
     * @param chainProp      连射链任务ID存储属性名（存储在 core 上）
     * @param releasedProp   释放标记属性名
     */
    public static function _gunslingerContinuousShoot(
        core:Object,
        attackMode:String,
        baseInterval:Number,
        params:Object,
        chainProp:String,
        releasedProp:String
    ):Void {
        // 检查按键是否仍被按住
        if (!core[params.actionFlagName]) {
            // 按键已释放，标记并停止连射
            if (releasedProp) core[releasedProp] = true;
            delete core[chainProp];
            return;
        }

        var gunslingerLevel:Number = core.被动技能.枪械师.等级 || 1;
        var holdInterval:Number = baseInterval * calcGunslingerHoldMultiplier(gunslingerLevel);
        var tapInterval:Number = baseInterval * calcGunslingerTapMultiplier(gunslingerLevel);

        // 尝试射击
        if (ShootCore.continuousShoot(core, attackMode, baseInterval, params)) {
            // 射击成功：点按收益最小间隔（用于下一次 startShooting）
            var rateKey:String = core._name + "_" + params.taskName;
            _lastShotTimes[rateKey] = true;
            EnhancedCooldownWheel.I().addTask(ShootCore._clearRateLimit, tapInterval, false, rateKey);
            core[params.shootingStateName] = false;

            // 连射链：固定 1.25x 间隔
            core[chainProp] = EnhancedCooldownWheel.I().addTask(
                ShootCore._gunslingerContinuousShoot,
                holdInterval,
                false,
                core,
                attackMode,
                baseInterval,
                params,
                chainProp,
                releasedProp
            );
        } else {
            // 射击失败：结束连射链，交回 startShooting 处理（如触发换弹）
            delete core[chainProp];
        }
    }

    /**
     * 枪械师技能连射回调（双枪系统专用）
     * 与 _gunslingerContinuousShoot 类似，但使用双枪系统的参数结构
     *
     * @param core              自机对象引用（parentRef）
     * @param target            主角函数对象（self/that）
     * @param weaponType        武器类型（攻击模式）
     * @param baseInterval      基础射击间隔
     * @param continueMethodName 持续射击方法名
     * @param shootingFlagProp  射击状态属性名
     * @param actionFlagName    动作标志属性名
     * @param timerProp         定时器任务属性名
     * @param chainProp         连射链任务ID存储属性名
     * @param releasedProp      释放标记属性名
     */
    public static function _gunslingerDualGunContinuousShoot(
        core:Object,
        target:Object,
        weaponType:String,
        baseInterval:Number,
        continueMethodName:String,
        shootingFlagProp:String,
        actionFlagName:String,
        timerProp:String,
        chainProp:String,
        releasedProp:String
    ):Void {
        // 检查按键是否仍被按住
        if (!core[actionFlagName]) {
            // 按键已释放，标记并停止连射
            if (releasedProp) core[releasedProp] = true;
            delete core[chainProp];
            return;
        }

        var gunslingerLevel:Number = core.被动技能.枪械师.等级 || 1;
        var holdInterval:Number = baseInterval * calcGunslingerHoldMultiplier(gunslingerLevel);
        var tapInterval:Number = baseInterval * calcGunslingerTapMultiplier(gunslingerLevel);

        // 尝试射击
        var continueShooting:Boolean = target[continueMethodName](core, weaponType, baseInterval, target);
        if (continueShooting) {
            // 射击成功：点按收益最小间隔（用于下一次 startShooting）
            var rateKey:String = core._name + "_" + timerProp;
            _lastShotTimes[rateKey] = true;
            EnhancedCooldownWheel.I().addTask(ShootCore._clearRateLimit, tapInterval, false, rateKey);
            core[shootingFlagProp] = false;

            // 连射链：固定 hold 间隔
            core[chainProp] = EnhancedCooldownWheel.I().addTask(
                ShootCore._gunslingerDualGunContinuousShoot,
                holdInterval,
                false,
                core,
                target,
                weaponType,
                baseInterval,
                continueMethodName,
                shootingFlagProp,
                actionFlagName,
                timerProp,
                chainProp,
                releasedProp
            );
        } else {
            // 射击失败：结束连射链，交回开始射击函数处理（如触发换弹）
            delete core[chainProp];
        }
    }

    /**
     * 枪械师半自动释放轮询（通用）
     * 检测按键释放，取消连射链以避免挂起任务干扰点按节奏
     *
     * @param core           自机对象
     * @param actionFlagName 动作标志属性名
     * @param chainProp      连射链属性名
     * @param releasedProp   释放标记属性名
     */
    public static function _gunslingerReleasePoll(
        core:Object,
        actionFlagName:String,
        chainProp:String,
        releasedProp:String
    ):Void {
        if (!core[actionFlagName]) {
            // 按键已释放：取消连射链，标记释放状态
            var chainTask = core[chainProp];
            if (chainTask != null) {
                EnhancedCooldownWheel.I().removeTask(chainTask);
                delete core[chainProp];
            }
            if (releasedProp) core[releasedProp] = true;
        }
    }

    /**
     * 清理 core 上的半自动锁标记，并移除可能存在的轮询任务
     *
     * @param core     自机对象
     * @param wheel    定时器轮引用
     * @param lockProp 锁标记属性名
     */
    private static function _cleanupSemiLock(core:Object, wheel:EnhancedCooldownWheel, lockProp:String):Void {
        var val = core[lockProp];
        if (val != null) {
            if (typeof val == "number") wheel.removeTask(val);
            delete core[lockProp];
        }
    }

    /**
     * 清理指定单位的所有射击相关任务
     * 用于在武器切换或刷新装扮时清理遗留的射击任务
     *
     * @param core 需要清理的单位对象
     */
    public static function cleanup(core:Object):Void {
        if (!core) return;

        var wheel:EnhancedCooldownWheel = EnhancedCooldownWheel.I();

        // 清理主手射击任务
        if (core[primaryParams.taskName]) {
            wheel.removeTask(core[primaryParams.taskName]);
            delete core[primaryParams.taskName];
        }

        // 清理副手射击任务
        if (core[secondaryParams.taskName]) {
            wheel.removeTask(core[secondaryParams.taskName]);
            delete core[secondaryParams.taskName];
        }

        // [v1.3] 使用生命周期 API 清理射击后摇任务
        wheel.removeTaskByLabel(core, "结束射击后摇");

        // 清理半自动冷却锁定（包括可能存在的轮询任务）
        _cleanupSemiLock(core, wheel, SEMI_LOCK_PREFIX + primaryParams.taskName);
        _cleanupSemiLock(core, wheel, SEMI_LOCK_PREFIX + secondaryParams.taskName);

        // 清理枪械师半自动释放轮询任务
        var pollProp1:String = GUNSLINGER_RELEASE_POLL_PREFIX + primaryParams.taskName;
        if (core[pollProp1] != null) {
            wheel.removeTask(core[pollProp1]);
            delete core[pollProp1];
        }
        var pollProp2:String = GUNSLINGER_RELEASE_POLL_PREFIX + secondaryParams.taskName;
        if (core[pollProp2] != null) {
            wheel.removeTask(core[pollProp2]);
            delete core[pollProp2];
        }

        // 清理枪械师半自动连射链任务
        var chainProp1:String = GUNSLINGER_CHAIN_PREFIX + primaryParams.taskName;
        if (core[chainProp1] != null) {
            wheel.removeTask(core[chainProp1]);
            delete core[chainProp1];
        }
        var chainProp2:String = GUNSLINGER_CHAIN_PREFIX + secondaryParams.taskName;
        if (core[chainProp2] != null) {
            wheel.removeTask(core[chainProp2]);
            delete core[chainProp2];
        }

        // 清理半自动射速时间戳
        var namePrefix:String = core._name + "_";
        delete _lastShotTimes[namePrefix + primaryParams.taskName];
        delete _lastShotTimes[namePrefix + secondaryParams.taskName];

        // 清理枪械师半自动点按标记
        delete core[SEMI_RELEASED_PREFIX + primaryParams.taskName];
        delete core[SEMI_RELEASED_PREFIX + secondaryParams.taskName];

        // 重置射击状态标志
        core[primaryParams.shootingStateName] = false;
        core[secondaryParams.shootingStateName] = false;
        core.射击最大后摇中 = false;
    }
}
