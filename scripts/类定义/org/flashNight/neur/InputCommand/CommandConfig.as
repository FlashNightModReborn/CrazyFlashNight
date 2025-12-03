import org.flashNight.neur.InputCommand.InputEvent;

/**
 * CommandConfig - 搓招配置工厂
 *
 * 提供预置的搓招配置数据，用于注入到 CommandRegistry。
 * 这是一个纯数据类，将搓招定义从代码逻辑中分离出来。
 *
 * 使用方式：
 *   var registry:CommandRegistry = new CommandRegistry();
 *   registry.loadConfig(CommandConfig.getBarehanded());  // 空手招式
 *   // 或
 *   registry.loadConfig(CommandConfig.getLightWeapon()); // 轻武器招式
 *   registry.compile();
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.neur.InputCommand.CommandConfig {

    // 缓存引用，避免频繁属性查找
    private static var EV:Object = null;

    /**
     * 初始化事件常量引用
     */
    private static function initEventRef():Void {
        if (EV == null) {
            EV = InputEvent;
        }
    }

    // ========== 空手搓招配置 ==========

    /**
     * 获取空手搓招配置
     *
     * 招式列表：
     * - 波动拳: ↓↘ + A (下前A)
     * - 诛杀步: →→ (双击前)
     * - 后撤步: Shift + ← (Shift + 后)
     * - 燃烧指节: → + B (前B)
     * - 能量喷泉: ↓ + B (下B)
     */
    public static function getBarehanded():Object {
        initEventRef();

        return {
            commands: [
                // 波动拳: 下前 + A，要求拳脚攻击 Lv5
                {
                    name: "波动拳",
                    sequence: [EV.DOWN_FORWARD, EV.A_PRESS],
                    action: "波动拳",
                    priority: 10,
                    tags: ["空手", "远程", "必杀"]
                },
                // 诛杀步: 双击前，要求拳脚攻击 Lv1
                {
                    name: "诛杀步",
                    sequence: [EV.DOUBLE_TAP_FORWARD],
                    action: "诛杀步",
                    priority: 5,
                    tags: ["空手", "移动", "基础"]
                },
                // 后撤步: Shift + 后，要求拳脚攻击 Lv1
                {
                    name: "后撤步",
                    sequence: [EV.SHIFT_BACK],
                    action: "后撤步",
                    priority: 5,
                    tags: ["空手", "移动", "防御"]
                },
                // 燃烧指节: 前 + B，要求升龙拳 Lv1
                {
                    name: "燃烧指节",
                    sequence: [EV.FORWARD, EV.B_PRESS],
                    action: "燃烧指节",
                    priority: 8,
                    tags: ["空手", "近战", "连招"]
                },
                // 能量喷泉: 下 + B，要求裂地拳 Lv1 + 10% MP
                {
                    name: "能量喷泉",
                    sequence: [EV.DOWN, EV.B_PRESS],
                    action: "能量喷泉1段",
                    priority: 7,
                    tags: ["空手", "近战", "消耗"]
                }
            ],

            // 派生关系：招式A可以派生出哪些招式
            derivations: {
                波动拳: ["诛杀步", "后撤步", "燃烧指节", "能量喷泉"],
                诛杀步: ["波动拳", "后撤步", "燃烧指节", "能量喷泉"],
                后撤步: ["波动拳", "诛杀步", "燃烧指节", "能量喷泉"],
                燃烧指节: ["波动拳", "诛杀步", "后撤步", "能量喷泉"],
                能量喷泉: ["波动拳", "诛杀步", "后撤步", "燃烧指节"]
            },

            // 分组（用于快速筛选）
            groups: {
                空手全部: ["波动拳", "诛杀步", "后撤步", "燃烧指节", "能量喷泉"],
                移动类: ["诛杀步", "后撤步"],
                攻击类: ["波动拳", "燃烧指节", "能量喷泉"]
            }
        };
    }

    // ========== 轻武器搓招配置 ==========

    /**
     * 获取轻武器搓招配置
     *
     * 招式列表：
     * - 剑气释放: ↓↘ + A (下前A)
     * - 百万突刺: →→ (双击前)
     * - 蓄力重劈: Shift + ↓ + A
     * - 十六夜月华: ← + A (后A)
     */
    public static function getLightWeapon():Object {
        initEventRef();

        return {
            commands: [
                // 剑气释放: 下前 + A，要求刀剑攻击 Lv3
                {
                    name: "剑气释放",
                    sequence: [EV.DOWN_FORWARD, EV.A_PRESS],
                    action: "剑气释放",
                    priority: 10,
                    tags: ["轻武器", "远程", "必杀"]
                },
                // 百万突刺: 双击前，要求刀剑攻击 Lv1
                {
                    name: "百万突刺",
                    sequence: [EV.DOUBLE_TAP_FORWARD],
                    action: "百万突刺",
                    priority: 5,
                    tags: ["轻武器", "移动", "基础"]
                },
                // 蓄力重劈: Shift + 下 + A，要求下劈 Lv1
                {
                    name: "蓄力重劈",
                    sequence: [EV.SHIFT_DOWN, EV.A_PRESS],
                    action: "蓄力重劈",
                    priority: 8,
                    tags: ["轻武器", "近战", "蓄力"]
                },
                // 十六夜月华: 后 + A，要求上挑 Lv1
                {
                    name: "十六夜月华",
                    sequence: [EV.BACK, EV.A_PRESS],
                    action: "十六夜月华",
                    priority: 7,
                    tags: ["轻武器", "近战", "反击"]
                }
            ],

            derivations: {
                剑气释放: ["百万突刺", "蓄力重劈", "十六夜月华"],
                百万突刺: ["剑气释放", "蓄力重劈", "十六夜月华"],
                蓄力重劈: ["剑气释放", "百万突刺", "十六夜月华"],
                十六夜月华: ["剑气释放", "百万突刺", "蓄力重劈"]
            },

            groups: {
                轻武器全部: ["剑气释放", "百万突刺", "蓄力重劈", "十六夜月华"],
                移动类: ["百万突刺"],
                攻击类: ["剑气释放", "蓄力重劈", "十六夜月华"]
            }
        };
    }

    // ========== 重型武器搓招配置 ==========

    /**
     * 获取重型武器搓招配置
     *
     * 与轻武器类似，但剑气释放替换为飞沙走石
     */
    public static function getHeavyWeapon():Object {
        initEventRef();

        return {
            commands: [
                // 飞沙走石: 下前 + A，要求刀剑攻击 Lv1
                {
                    name: "飞沙走石",
                    sequence: [EV.DOWN_FORWARD, EV.A_PRESS],
                    action: "飞沙走石",
                    priority: 10,
                    tags: ["重武器", "远程", "必杀"]
                },
                // 百万突刺: 双击前
                {
                    name: "百万突刺",
                    sequence: [EV.DOUBLE_TAP_FORWARD],
                    action: "百万突刺",
                    priority: 5,
                    tags: ["重武器", "移动", "基础"]
                },
                // 蓄力重劈: Shift + 下 + A
                {
                    name: "蓄力重劈",
                    sequence: [EV.SHIFT_DOWN, EV.A_PRESS],
                    action: "蓄力重劈",
                    priority: 8,
                    tags: ["重武器", "近战", "蓄力"]
                },
                // 十六夜月华: 后 + A
                {
                    name: "十六夜月华",
                    sequence: [EV.BACK, EV.A_PRESS],
                    action: "十六夜月华",
                    priority: 7,
                    tags: ["重武器", "近战", "反击"]
                }
            ],

            derivations: {
                飞沙走石: ["百万突刺", "蓄力重劈", "十六夜月华"],
                百万突刺: ["飞沙走石", "蓄力重劈", "十六夜月华"],
                蓄力重劈: ["飞沙走石", "百万突刺", "十六夜月华"],
                十六夜月华: ["飞沙走石", "百万突刺", "蓄力重劈"]
            },

            groups: {
                重武器全部: ["飞沙走石", "百万突刺", "蓄力重劈", "十六夜月华"]
            }
        };
    }

    // ========== 配置合并工具 ==========

    /**
     * 合并多个配置
     * 用于需要同时支持多种招式集的场景
     *
     * @param configs 配置数组
     * @return 合并后的配置
     */
    public static function merge(configs:Array):Object {
        var result:Object = {
            commands: [],
            derivations: {},
            groups: {}
        };

        for (var i:Number = 0; i < configs.length; i++) {
            var cfg:Object = configs[i];

            // 合并命令（去重）
            if (cfg.commands != undefined) {
                var nameSet:Object = {};
                // 先记录已有命令
                for (var j:Number = 0; j < result.commands.length; j++) {
                    nameSet[result.commands[j].name] = true;
                }
                // 添加新命令
                for (var k:Number = 0; k < cfg.commands.length; k++) {
                    var cmd:Object = cfg.commands[k];
                    if (nameSet[cmd.name] == undefined) {
                        result.commands.push(cmd);
                        nameSet[cmd.name] = true;
                    }
                }
            }

            // 合并派生关系
            if (cfg.derivations != undefined) {
                for (var srcName:String in cfg.derivations) {
                    if (result.derivations[srcName] == undefined) {
                        result.derivations[srcName] = [];
                    }
                    var targets:Array = cfg.derivations[srcName];
                    for (var m:Number = 0; m < targets.length; m++) {
                        // 避免重复
                        var found:Boolean = false;
                        for (var n:Number = 0; n < result.derivations[srcName].length; n++) {
                            if (result.derivations[srcName][n] == targets[m]) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            result.derivations[srcName].push(targets[m]);
                        }
                    }
                }
            }

            // 合并分组
            if (cfg.groups != undefined) {
                for (var grpName:String in cfg.groups) {
                    if (result.groups[grpName] == undefined) {
                        result.groups[grpName] = [];
                    }
                    var members:Array = cfg.groups[grpName];
                    for (var p:Number = 0; p < members.length; p++) {
                        var exists:Boolean = false;
                        for (var q:Number = 0; q < result.groups[grpName].length; q++) {
                            if (result.groups[grpName][q] == members[p]) {
                                exists = true;
                                break;
                            }
                        }
                        if (!exists) {
                            result.groups[grpName].push(members[p]);
                        }
                    }
                }
            }
        }

        return result;
    }

    // ========== 调试辅助 ==========

    /**
     * 打印配置信息
     */
    public static function dump(config:Object):Void {
        trace("===== CommandConfig Dump =====");

        if (config.commands != undefined) {
            trace("\n--- Commands (" + config.commands.length + ") ---");
            for (var i:Number = 0; i < config.commands.length; i++) {
                var cmd:Object = config.commands[i];
                var seqStr:String = InputEvent.sequenceToString(cmd.sequence);
                trace("  " + cmd.name + ": " + seqStr +
                      " (priority: " + cmd.priority +
                      ", action: " + cmd.action + ")");
                if (cmd.tags != undefined) {
                    trace("    tags: [" + cmd.tags.join(", ") + "]");
                }
            }
        }

        if (config.derivations != undefined) {
            trace("\n--- Derivations ---");
            for (var srcName:String in config.derivations) {
                trace("  " + srcName + " -> [" + config.derivations[srcName].join(", ") + "]");
            }
        }

        if (config.groups != undefined) {
            trace("\n--- Groups ---");
            for (var grpName:String in config.groups) {
                trace("  " + grpName + ": [" + config.groups[grpName].join(", ") + "]");
            }
        }

        trace("==============================");
    }
}
