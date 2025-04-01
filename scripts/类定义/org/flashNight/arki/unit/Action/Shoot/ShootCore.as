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
    public static function continuousShoot(core:MovieClip, attackMode:String, shootSpeed:Number, params:Object):Boolean {
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
            core[shootStateName] = core[shootMethodName](gunRef, man[config.shootBulletAttrKey]);

            // 更新弹匣剩余子弹数量
            var magazineRemaining:Number = core[magazineCapName] - core[shootCountName][core[attackMode]];
            dispatcher.publish("ReloadEvent", core, shootStateName, magazineRemaining, config.playerBulletField);
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
}
