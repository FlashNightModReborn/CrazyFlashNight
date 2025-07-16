// 文件路径：org/flashNight/arki/unit/Action/Shoot/ShootCore.as

import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;

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

        var dispatcher:EventDispatcher = core.dispatcher;
        dispatcher.publish(attackMode + "射击");

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
            root.帧计时器.移除任务(core[config.taskName]);
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
        var shootCountName:String   = attackMode + "射击次数";

        // 执行射击逻辑
        core[shootStateName] = false;
        if (core[actionFlagName]) {
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
            core[shootStateName] = core[shootMethodName](gunRef, bulletAttr);

            // 更新弹匣剩余子弹数量
            var magazineRemaining:Number = bulletAttr.ammoCost * (core[magazineCapName] - core[shootCountName][core[attackMode]]);
            dispatcher.publish("updateBullet", core, shootStateName, magazineRemaining, config.playerBulletField);
            if (shootSpeed > 300) {
                // 延迟任务：结束后摇状态
                root.帧计时器.添加或更新任务(core, "结束射击后摇", function(target:Object):Void {
                    target.射击最大后摇中 = false;
                }, 300, core);
            }
        }

        // 根据当前状态返回是否仍在持续射击中，并清理任务
        if (core[shootStateName]) {
            return true;
        }
        root.帧计时器.移除任务(core[config.taskName]);
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
     * @param root         全局根引用（用于访问帧计时器等系统）
     * 
     * @see ShootCore.continuousShoot  实际执行持续射击的核心逻辑
     * @see ShootCore.primaryParams    主手射击的标准配置
     * @see ShootCore.secondaryParams  副手射击的标准配置
     * 
     * @example 典型调用方式（主手）：
     * ShootCore.startShooting(
     *     _parent, 
     *     this,
     *     ShootCore.primaryParams,
     *     _root
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
        params:Object,            // 主副手参数（primaryParams/secondaryParams）
        root:Object               // 全局根引用
    ):Void {
        // 若正在该状态射击中或正在换弹，直接返回
        if (core[params.shootingStateName] || protagonist.换弹标签) return;

        // 缓存攻击模式与射击速度
        var attackMode:String = core.攻击模式;
        var interval:Number = protagonist.射击速度;

        // 弹匣容量与射击次数键名
        var magazineCapName:String = attackMode + "弹匣容量";
        var shootCountName:String = attackMode + "射击次数";


        // 检查弹匣是否打空
        if (core[shootCountName][core[attackMode]] >= core[magazineCapName]) {
            // 若剩余弹匣>0 或非控制目标，触发换弹
            if (protagonist.剩余弹匣数 > 0 || root.控制目标 != core._name) {
                protagonist.开始换弹();
            }
            return;
        }

        // 检查射击许可标签
        if (!protagonist.射击许可标签) {
            // _root.发布消息("主角函数.射击许可", "不允许射击");
            return;
        }

        // 调用持续射击核心逻辑
        if (ShootCore.continuousShoot(core, attackMode, interval, params)) {
            // 添加持续射击任务到帧计时器
            core[params.taskName] = root.帧计时器.taskManager.addLifecycleTask(
                core, 
                "开始射击", 
                ShootCore.continuousShoot, 
                interval, 
                [core, attackMode, interval, params]  // 额外参数打包成数组
            );

            // 若射击间隔较长，添加后摇解除任务
            if (interval > 300) {
                root.帧计时器.添加或更新任务(
                    core,
                    "结束射击后摇",
                    function(自机:MovieClip):Void {
                        自机.射击最大后摇中 = false;
                    },
                    300,
                    core
                );
            }
        }
    }
}
