// 文件路径：org/flashNight/arki/unit/Action/Shoot/ShootCore.as

import org.flashNight.naki.DataStructures.Dictionary; // 确保能正确导入 Dictionary 类

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
        // 内联展开：利用 Dictionary.getStaticUID 为 params 建立或获取缓存配置
        var uid:Number = Dictionary.getStaticUID(params);
        var config:Object = _paramsCache[uid];
        if (!config) {
            config = {
                // 将需要频繁访问的字段放入缓存
                shootingStateName:    params.shootingStateName,
                actionFlagName:       params.actionFlagName,
                prefix:               params.prefix,
                bulletAttrKeys:       params.bulletAttrKeys,
                shootBulletAttrKey:   params.shootBulletAttrKey,
                taskName:             params.taskName,
                playerBulletField:    params.playerBulletField,

                // 预处理1：拆分 gunPath，并缓存
                gunPathArray:         params.gunPath.split("."),

                // 预处理2：拼接固定字符串
                baseShootFrame:       "射击" + params.prefix
            };
            _paramsCache[uid] = config;
        }

        // 执行前置逻辑
        core.射击最大后摇中 = false;
        if(!core.man.射击许可标签) {
            core[config.shootingStateName] = false;
            _root.帧计时器.移除任务(core[config.taskName]);
            return false;
        }

        // 重置各指定子弹属性的角度偏移
        var bulletAttrKeys:Array = config.bulletAttrKeys;
        var len:Number = bulletAttrKeys.length;
        for(var i:Number = 0; i < len; i++) {
            var key:String = bulletAttrKeys[i];
            core.man[key].角度偏移 = 0;
        }

        // 默认动画帧名称
        var jumpFrameName:String = config.baseShootFrame;

        // 如果当前是控制目标，且不处于上下移动射击状态
        if(_root.控制目标 === core._name && !core.上下移动射击) {
            if(core.下行) {
                for(var j:Number = 0; j < len; j++) {
                    core.man[bulletAttrKeys[j]].角度偏移 = 30;
                }
                jumpFrameName = "下射击" + config.prefix;
            } else if(core.上行) {
                for(var k:Number = 0; k < len; k++) {
                    core.man[bulletAttrKeys[k]].角度偏移 = -30;
                }
                jumpFrameName = "上射击" + config.prefix;
            }
        }

        // 主循环：判断动作标记并执行射击逻辑
        core[config.shootingStateName] = false;
        if(core[config.actionFlagName]) {
            core.man.gotoAndPlay(jumpFrameName);

            // 利用缓存的 gunPathArray 获取枪口位置引用
            var gunRef:Object = core.man;
            var path:Array = config.gunPathArray;
            var pathLen:Number = path.length;
            for(var p:Number = 0; p < pathLen; p++) {
                gunRef = gunRef[path[p]];
            }

            // 调用具体的射击方法（方法名由 attackMode 与 "射击" 拼接而成）
            var shootBulletKey:String = config.shootBulletAttrKey;
            core[config.shootingStateName] = core[attackMode + "射击"](gunRef, core.man[shootBulletKey]);

            // 根据射击次数更新弹匣剩余子弹
            var magazineRemaining:Number = core[attackMode + "弹匣容量"] - core[attackMode + "射击次数"][core[attackMode]];
            if(_root.控制目标 === core._name) {
                _root.玩家信息界面.玩家必要信息界面[config.playerBulletField] = magazineRemaining;
            }
            if(magazineRemaining <= 0) {
                core[config.shootingStateName] = false;
            }
            core.射击最大后摇中 = core[config.shootingStateName];
            if(shootSpeed > 300) {
                _root.帧计时器.添加或更新任务(core, "结束射击后摇", function(target:Object):Void {
                    target.射击最大后摇中 = false;
                }, 300, core);
            }
        }

        if(core[config.shootingStateName]) {
            return true;
        }
        _root.帧计时器.移除任务(core[config.taskName]);
        return false;
    }
}
