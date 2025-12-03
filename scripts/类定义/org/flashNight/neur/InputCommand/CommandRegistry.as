import org.flashNight.neur.InputCommand.InputEvent;
import org.flashNight.neur.InputCommand.CommandDFA; 

/**
 * CommandRegistry - 搓招命令注册表（配置注入模式）
 *
 * 通用化的搓招系统构建器，支持：
 * 1. 外部配置注入 - 招式数据不硬编码，由外部传入
 * 2. 编译固化 - 配置解析后编译为高效DFA
 * 3. 动态扩展 - 支持不同角色/武器类型的招式集
 * 4. 派生关系 - 支持声明式定义招式派生链
 *
 * 使用方式：
 *   // 1. 创建实例
 *   var registry:CommandRegistry = new CommandRegistry();
 *
 *   // 2. 注入配置
 *   registry.loadConfig(myCommandConfig);
 *
 *   // 3. 编译
 *   registry.compile();
 *
 *   // 4. 使用
 *   var dfa:CommandDFA = registry.getDFA();
 *   var cmdId:Number = registry.getCommandId("波动拳");
 *
 * 配置格式：
 *   {
 *     commands: [
 *       {name:"波动拳", sequence:[EV.DOWN_FORWARD, EV.A_PRESS], action:"波动拳", priority:10, tags:["空手"]},
 *       ...
 *     ],
 *     derivations: {
 *       "波动拳": ["诛杀步", "后撤步", "燃烧指节"],  // 波动拳可派生的招式
 *       ...
 *     },
 *     groups: {
 *       "空手": ["波动拳", "诛杀步", "后撤步"],
 *       "轻武器": ["剑气释放", "百万突刺"],
 *       ...
 *     }
 *   }
 *
 * @author FlashNight
 * @version 2.0
 */
class org.flashNight.neur.InputCommand.CommandRegistry {

    // ========== 常量 ==========

    /** 无命令 */
    public static var CMD_NONE:Number = 0;

    // ========== 内部状态 ==========

    /** DFA 实例 */
    private var _dfa:CommandDFA;

    /** 是否已编译 */
    private var _compiled:Boolean;

    /** 命令名称 -> ID 映射 */
    private var _nameToId:Object;

    /** 命令ID -> 名称 映射 */
    private var _idToName:Array;

    /** 命令ID -> 配置对象 映射 */
    private var _idToConfig:Array;

    /** 派生关系：cmdId -> allowMask (可派生的招式 bitmask) */
    private var _derivationMask:Array;

    /** 分组：groupName -> allowMask */
    private var _groupMask:Object;

    /** 标签索引：tag -> [cmdId, cmdId, ...] */
    private var _tagIndex:Object;

    /** 下一个可用命令ID（用于注册阶段） */
    private var _nextCmdId:Number;

    // ========== 构造函数 ==========

    /**
     * 创建 CommandRegistry 实例
     * @param initialCapacity DFA 初始状态容量（默认64）
     */
    public function CommandRegistry(initialCapacity:Number) {
        if (initialCapacity == undefined || initialCapacity < 32) {
            initialCapacity = 64;
        }

        this._dfa = new CommandDFA(initialCapacity);
        this._compiled = false;
        this._nameToId = {};
        this._idToName = [];
        this._idToConfig = [];
        this._derivationMask = [];
        this._groupMask = {};
        this._tagIndex = {};
        this._nextCmdId = 1;  // 0 保留为 CMD_NONE

        // 初始化索引0
        this._idToName[0] = "";
        this._idToConfig[0] = null;
        this._derivationMask[0] = 0;
    }

    // ========== 配置加载 ==========

    /**
     * 加载配置对象
     *
     * @param config 配置对象，格式如下：
     *   {
     *     commands: Array,      // 命令定义列表
     *     derivations: Object,  // 派生关系（可选）
     *     groups: Object        // 分组定义（可选）
     *   }
     */
    public function loadConfig(config:Object):Void {
        if (this._compiled) {
            trace("[CommandRegistry] Error: Cannot load config after compile()");
            return;
        }

        if (config == undefined) {
            trace("[CommandRegistry] Error: config is undefined");
            return;
        }

        // 1. 注册命令
        if (config.commands != undefined) {
            this.loadCommands(config.commands);
        }

        // 2. 加载派生关系
        if (config.derivations != undefined) {
            this.loadDerivations(config.derivations);
        }

        // 3. 加载分组
        if (config.groups != undefined) {
            this.loadGroups(config.groups);
        }
    }

    /**
     * 加载命令列表
     *
     * @param commands 命令配置数组，每个元素：
     *   {
     *     name: String,        // 命令名称（必需）
     *     sequence: Array,     // 输入序列（必需）
     *     action: String,      // 动作名（可选，默认=name）
     *     priority: Number,    // 优先级（可选，默认=0）
     *     tags: Array          // 标签列表（可选）
     *   }
     */
    public function loadCommands(commands:Array):Void {
        if (this._compiled) {
            trace("[CommandRegistry] Error: Cannot load commands after compile()");
            return;
        }

        for (var i:Number = 0; i < commands.length; i++) {
            this.registerCommand(commands[i]);
        }
    }

    /**
     * 注册单个命令
     *
     * @param cmdConfig 命令配置对象
     * @return 命令ID，失败返回 CMD_NONE
     */
    public function registerCommand(cmdConfig:Object):Number {
        if (this._compiled) {
            trace("[CommandRegistry] Error: Cannot register after compile()");
            return CMD_NONE;
        }

        if (cmdConfig == undefined || cmdConfig.name == undefined || cmdConfig.sequence == undefined) {
            trace("[CommandRegistry] Error: Invalid command config");
            return CMD_NONE;
        }

        var name:String = cmdConfig.name;
        var sequence:Array = cmdConfig.sequence;
        var action:String = (cmdConfig.action != undefined) ? cmdConfig.action : name;
        var priority:Number = (cmdConfig.priority != undefined) ? cmdConfig.priority : 0;
        var tags:Array = cmdConfig.tags;

        // 检查重名
        if (this._nameToId[name] != undefined) {
            trace("[CommandRegistry] Warning: Command '" + name + "' already registered, skipping");
            return this._nameToId[name];
        }

        // 注册到 DFA
        var cmdId:Number = this._dfa.registerCommand(name, sequence, action, priority);

        if (cmdId == CommandDFA.INVALID) {
            trace("[CommandRegistry] Error: Failed to register command '" + name + "'");
            return CMD_NONE;
        }

        // 更新索引
        this._nameToId[name] = cmdId;
        this._idToName[cmdId] = name;
        this._idToConfig[cmdId] = cmdConfig;
        this._derivationMask[cmdId] = 0;  // 默认无派生

        // 处理标签
        if (tags != undefined) {
            for (var t:Number = 0; t < tags.length; t++) {
                var tag:String = tags[t];
                if (this._tagIndex[tag] == undefined) {
                    this._tagIndex[tag] = [];
                }
                this._tagIndex[tag].push(cmdId);
            }
        }

        return cmdId;
    }

    /**
     * 加载派生关系
     *
     * @param derivations 派生配置，格式：
     *   {
     *     "波动拳": ["诛杀步", "后撤步"],  // 名称数组
     *     "诛杀步": ["波动拳", "燃烧指节"],
     *     ...
     *   }
     */
    public function loadDerivations(derivations:Object):Void {
        // 存储原始配置，在 compile 时解析
        // （因为派生可能引用尚未注册的命令）
        this._pendingDerivations = derivations;
    }

    /** 待处理的派生配置 */
    private var _pendingDerivations:Object;

    /**
     * 加载分组定义
     *
     * @param groups 分组配置，格式：
     *   {
     *     "空手": ["波动拳", "诛杀步", "后撤步"],
     *     "轻武器": ["剑气释放", "百万突刺"],
     *     ...
     *   }
     */
    public function loadGroups(groups:Object):Void {
        // 存储原始配置，在 compile 时解析
        this._pendingGroups = groups;
    }

    /** 待处理的分组配置 */
    private var _pendingGroups:Object;

    // ========== 编译 ==========

    /**
     * 编译注册表
     * 在所有配置加载完成后调用
     */
    public function compile():Void {
        if (this._compiled) {
            trace("[CommandRegistry] Warning: Already compiled");
            return;
        }

        // 1. 编译 DFA
        this._dfa.build();

        // 2. 解析派生关系
        if (this._pendingDerivations != undefined) {
            this.compileDerivations();
        }

        // 3. 解析分组
        if (this._pendingGroups != undefined) {
            this.compileGroups();
        }

        this._compiled = true;
        trace("[CommandRegistry] Compiled: " + this._dfa.getCommandCount() + " commands");
    }

    /**
     * 编译派生关系
     */
    private function compileDerivations():Void {
        for (var sourceName:String in this._pendingDerivations) {
            var sourceId:Number = this._nameToId[sourceName];
            if (sourceId == undefined) {
                trace("[CommandRegistry] Warning: Derivation source '" + sourceName + "' not found");
                continue;
            }

            var targets:Array = this._pendingDerivations[sourceName];
            var mask:Number = 0;

            for (var i:Number = 0; i < targets.length; i++) {
                var targetName:String = targets[i];
                var targetId:Number = this._nameToId[targetName];

                if (targetId == undefined) {
                    trace("[CommandRegistry] Warning: Derivation target '" + targetName + "' not found");
                    continue;
                }

                mask = mask | this.toBit(targetId);
            }

            this._derivationMask[sourceId] = mask;
        }

        this._pendingDerivations = undefined;
    }

    /**
     * 编译分组
     */
    private function compileGroups():Void {
        for (var groupName:String in this._pendingGroups) {
            var members:Array = this._pendingGroups[groupName];
            var mask:Number = 0;

            for (var i:Number = 0; i < members.length; i++) {
                var memberName:String = members[i];
                var memberId:Number = this._nameToId[memberName];

                if (memberId == undefined) {
                    trace("[CommandRegistry] Warning: Group member '" + memberName + "' not found in group '" + groupName + "'");
                    continue;
                }

                mask = mask | this.toBit(memberId);
            }

            this._groupMask[groupName] = mask;
        }

        this._pendingGroups = undefined;
    }

    // ========== 查询接口 ==========

    /**
     * 获取 DFA 实例
     */
    public function getDFA():CommandDFA {
        return this._dfa;
    }

    /**
     * 是否已编译
     */
    public function isCompiled():Boolean {
        return this._compiled;
    }

    /**
     * 根据名称获取命令ID
     * @param name 命令名称
     * @return 命令ID，未找到返回 CMD_NONE
     */
    public function getCommandId(name:String):Number {
        var id:Number = this._nameToId[name];
        return (id != undefined) ? id : CMD_NONE;
    }

    /**
     * 根据ID获取命令名称
     */
    public function getCommandName(cmdId:Number):String {
        return this._idToName[cmdId];
    }

    /**
     * 获取命令配置对象
     */
    public function getCommandConfig(cmdId:Number):Object {
        return this._idToConfig[cmdId];
    }

    /**
     * 获取命令的派生 mask
     * @param cmdId 命令ID
     * @return 可派生的命令 bitmask
     */
    public function getDerivationMask(cmdId:Number):Number {
        var mask:Number = this._derivationMask[cmdId];
        return (mask != undefined) ? mask : 0;
    }

    /**
     * 获取分组 mask
     * @param groupName 分组名称
     * @return 该分组包含的命令 bitmask
     */
    public function getGroupMask(groupName:String):Number {
        var mask:Number = this._groupMask[groupName];
        return (mask != undefined) ? mask : 0;
    }

    /**
     * 根据标签获取命令ID列表
     * @param tag 标签名
     * @return 命令ID数组
     */
    public function getCommandsByTag(tag:String):Array {
        var ids:Array = this._tagIndex[tag];
        return (ids != undefined) ? ids : [];
    }

    /**
     * 获取标签对应的 bitmask
     * @param tag 标签名
     * @return 该标签下所有命令的 bitmask
     */
    public function getTagMask(tag:String):Number {
        var ids:Array = this._tagIndex[tag];
        if (ids == undefined) return 0;

        var mask:Number = 0;
        for (var i:Number = 0; i < ids.length; i++) {
            mask = mask | this.toBit(ids[i]);
        }
        return mask;
    }

    /**
     * 检查命令是否在 mask 中
     */
    public function isCommandInMask(cmdId:Number, mask:Number):Boolean {
        if (cmdId <= 0) return false;
        return (mask & this.toBit(cmdId)) != 0;
    }

    /**
     * 获取已注册命令数量
     */
    public function getCommandCount():Number {
        return this._dfa.getCommandCount();
    }

    // ========== 工具方法 ==========

    /**
     * 命令ID转 bitmask 位
     */
    public function toBit(cmdId:Number):Number {
        if (cmdId <= 0 || cmdId >= 32) return 0;
        return 1 << cmdId;
    }

    /**
     * 合并多个 mask
     */
    public function combineMasks():Number {
        var result:Number = 0;
        for (var i:Number = 0; i < arguments.length; i++) {
            result = result | arguments[i];
        }
        return result;
    }

    // ========== 调试方法 ==========

    /**
     * 打印注册表信息
     */
    public function dump():Void {
        trace("===== CommandRegistry Dump =====");
        trace("Compiled: " + this._compiled);
        trace("Commands: " + this._dfa.getCommandCount());

        trace("\n--- Commands ---");
        for (var i:Number = 1; i <= this._dfa.getCommandCount(); i++) {
            var name:String = this._idToName[i];
            var config:Object = this._idToConfig[i];
            var derivMask:Number = this._derivationMask[i];
            trace("  [" + i + "] " + name +
                  " (priority: " + (config.priority || 0) + ")" +
                  " derivation: 0x" + derivMask.toString(16));
        }

        trace("\n--- Groups ---");
        for (var groupName:String in this._groupMask) {
            trace("  " + groupName + ": 0x" + this._groupMask[groupName].toString(16));
        }

        trace("\n--- Tags ---");
        for (var tag:String in this._tagIndex) {
            trace("  " + tag + ": " + this._tagIndex[tag].join(", "));
        }

        trace("================================");
    }
}
