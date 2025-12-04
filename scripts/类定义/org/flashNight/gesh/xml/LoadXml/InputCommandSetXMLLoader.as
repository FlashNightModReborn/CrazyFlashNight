import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.path.*;
import org.flashNight.gesh.object.*;
import org.flashNight.neur.InputCommand.InputEvent;

/**
 * InputCommandSetXMLLoader - 搓招配置集 XML 加载器
 *
 * 加载单个 CommandSet XML 文件，并解析为与 CommandConfig 兼容的配置对象：
 * {
 *   commands: Array,      // 命令定义列表
 *   derivations: Object,  // 派生关系
 *   groups: Object        // 分组定义
 * } 
 *
 * 注意：XMLLoader 返回的是经 XMLParser.parseXMLNode() 处理后的 Object，
 * 而非原始 XMLNode，因此本类直接处理 Object 结构。
 *
 * @author FlashNight
 * @version 2.0
 */
class org.flashNight.gesh.xml.LoadXml.InputCommandSetXMLLoader {

    // ========== 日志方法 ==========

    private static function log(message:String, level:String):Void {
        var formattedMessage:String = "[InputCommandSetXMLLoader] [" + level + "] " + message;
        if (_root["服务器"] != undefined && _root["服务器"]["发布服务器消息"] != undefined) {
            _root["服务器"]["发布服务器消息"](formattedMessage);
        }
        trace(formattedMessage);
    }

    private static function logError(message:String):Void { log(message, "ERROR"); }
    private static function logWarn(message:String):Void { log(message, "WARN"); }
    private static function logInfo(message:String):Void { log(message, "INFO"); }
    private static function logDebug(message:String):Void { log(message, "DEBUG"); }

    // ========== 实例字段 ==========

    private var _data:Object = null;
    private var _isLoading:Boolean = false;
    private var _filePath:String;
    private var _setId:String;

    // ========== 构造函数 ==========

    /**
     * 创建 InputCommandSetXMLLoader 实例
     * @param relativePath 相对于资源目录的 XML 文件路径
     */
    public function InputCommandSetXMLLoader(relativePath:String) {
        PathManager.initialize();

        if (!PathManager.isEnvironmentValid()) {
            logError("未检测到有效的资源环境！");
            return;
        }

        this._filePath = PathManager.resolvePath(relativePath);
        if (this._filePath == null) {
            logError("路径解析失败: " + relativePath);
        }
    }

    // ========== 加载方法 ==========

    /**
     * 加载并解析 CommandSet XML
     * @param onSuccess 成功回调 function(config:Object):Void
     * @param onError 失败回调 function():Void
     */
    public function load(onSuccess:Function, onError:Function):Void {
        if (this._isLoading) {
            logWarn("正在加载中，忽略重复请求");
            return;
        }

        if (this._data != null) {
            logDebug("使用缓存数据");
            if (onSuccess != null) onSuccess(this._data);
            return;
        }

        if (this._filePath == null) {
            logError("文件路径为空，无法加载");
            if (onError != null) onError();
            return;
        }

        this._isLoading = true;
        var self:InputCommandSetXMLLoader = this;
        var startTime:Number = getTimer();

        logInfo("开始加载: " + this._filePath);

        new XMLLoader(this._filePath, function(parsedData:Object):Void {
            var loadTime:Number = getTimer() - startTime;
            self._isLoading = false;

            logInfo("加载成功，耗时: " + loadTime + "ms");

            // parsedData 是 XMLParser.parseXMLNode() 返回的 Object
            var config:Object = self.parseCommandSet(parsedData);
            if (config != null) {
                self._data = config;
                logInfo("解析完成: " + config.commands.length + " 个命令");
                if (onSuccess != null) onSuccess(config);
            } else {
                logError("XML 解析失败");
                if (onError != null) onError();
            }

        }, function():Void {
            self._isLoading = false;
            logError("加载失败: " + self._filePath);
            if (onError != null) onError();
        });
    }

    // ========== Object 结构解析方法 ==========

    /**
     * 解析 CommandSet Object 为配置对象
     * XMLParser 已经将 XML 转换为 Object 结构
     *
     * @param data XMLParser 返回的 Object，结构如：
     *   {
     *     id: "barehand",
     *     label: "空手",
     *     Commands: { Command: [...] },
     *     Derivations: { Derive: [...] },
     *     Groups: { Group: [...] }
     *   }
     * @return 配置对象 {commands, derivations, groups}
     */
    private function parseCommandSet(data:Object):Object {
        if (data == null) {
            logError("data 为 null");
            return null;
        }

        this._setId = data.id;
        logDebug("解析 CommandSet: " + this._setId + " (" + data.label + ")");

        var result:Object = {
            commands: [],
            derivations: {},
            groups: {}
        };

        // 解析 Commands
        if (data.Commands != undefined) {
            result.commands = this.parseCommands(data.Commands);
        }

        // 解析 Derivations
        if (data.Derivations != undefined) {
            result.derivations = this.parseDerivations(data.Derivations);
        }

        // 解析 Groups
        if (data.Groups != undefined) {
            result.groups = this.parseGroups(data.Groups);
        }

        return result;
    }

    /**
     * 解析 Commands 对象
     * @param commandsObj { Command: [...] } 或 { Command: {...} }
     */
    private function parseCommands(commandsObj:Object):Array {
        var commands:Array = [];
        var cmdList:Array = this.ensureArray(commandsObj.Command);

        for (var i:Number = 0; i < cmdList.length; i++) {
            var cmdObj:Object = cmdList[i];

            var cmd:Object = {
                name: cmdObj.name,
                action: (cmdObj.action != undefined) ? cmdObj.action : cmdObj.name,
                priority: (cmdObj.priority != undefined) ? Number(cmdObj.priority) : 0,
                sequence: [],
                tags: []
            };

            // 解析 Sequence
            if (cmdObj.Sequence != undefined) {
                cmd.sequence = this.parseSequence(cmdObj.Sequence);
            }

            // 解析 Tags
            if (cmdObj.Tags != undefined) {
                cmd.tags = this.parseTags(cmdObj.Tags);
            }

            // 解析 Requirements（可选）
            if (cmdObj.Requirements != undefined) {
                cmd.requirements = this.parseRequirements(cmdObj.Requirements);
            }

            if (cmd.name != undefined && cmd.sequence.length > 0) {
                commands.push(cmd);
                logDebug("  命令: " + cmd.name + " = " + InputEvent.sequenceToString(cmd.sequence));
            }
        }

        return commands;
    }

    /**
     * 解析 Sequence 对象，将事件名称转为事件ID
     * @param seqObj { Event: ["DOWN_FORWARD", "A_PRESS"] } 或 { Event: "DOWN_FORWARD" }
     */
    private function parseSequence(seqObj:Object):Array {
        var sequence:Array = [];
        var eventList:Array = this.ensureArray(seqObj.Event);

        for (var i:Number = 0; i < eventList.length; i++) {
            var eventName:String = String(eventList[i]);
            var eventId:Number = InputEvent.fromName(eventName);

            if (eventId != InputEvent.NONE) {
                sequence.push(eventId);
            } else {
                logWarn("未知事件名: " + eventName);
            }
        }

        return sequence;
    }

    /**
     * 解析 Tags 对象
     * @param tagsObj { Tag: ["空手", "远程"] } 或 { Tag: "空手" }
     */
    private function parseTags(tagsObj:Object):Array {
        var tags:Array = [];
        var tagList:Array = this.ensureArray(tagsObj.Tag);

        for (var i:Number = 0; i < tagList.length; i++) {
            var tagName:String = String(tagList[i]);
            if (tagName != "") {
                tags.push(tagName);
            }
        }

        return tags;
    }

    /**
     * 解析 Requirements 对象
     * @param reqObj { Skill: {...} 或 [...], MP: {...} }
     */
    private function parseRequirements(reqObj:Object):Object {
        var requirements:Object = {
            skills: [],
            mp: null
        };

        // 解析 Skill
        if (reqObj.Skill != undefined) {
            var skillList:Array = this.ensureArray(reqObj.Skill);
            for (var i:Number = 0; i < skillList.length; i++) {
                var skillObj:Object = skillList[i];
                requirements.skills.push({
                    name: skillObj.name,
                    minLevel: (skillObj.minLevel != undefined) ? Number(skillObj.minLevel) : 1
                });
            }
        }

        // 解析 MP
        if (reqObj.MP != undefined) {
            requirements.mp = {
                ratio: (reqObj.MP.ratio != undefined) ? Number(reqObj.MP.ratio) : 0
            };
        }

        return requirements;
    }

    /**
     * 解析 Derivations 对象
     * @param derivObj { Derive: [...] }
     */
    private function parseDerivations(derivObj:Object):Object {
        var derivations:Object = {};
        var deriveList:Array = this.ensureArray(derivObj.Derive);

        for (var i:Number = 0; i < deriveList.length; i++) {
            var deriveItem:Object = deriveList[i];
            var fromName:String = deriveItem.from;
            if (fromName == undefined) continue;

            var targets:Array = this.ensureArray(deriveItem.To);
            if (targets.length > 0) {
                // To 可能是字符串数组或单个字符串
                var targetNames:Array = [];
                for (var j:Number = 0; j < targets.length; j++) {
                    targetNames.push(String(targets[j]));
                }
                derivations[fromName] = targetNames;
            }
        }

        return derivations;
    }

    /**
     * 解析 Groups 对象
     * @param groupsObj { Group: [...] }
     */
    private function parseGroups(groupsObj:Object):Object {
        var groups:Object = {};
        var groupList:Array = this.ensureArray(groupsObj.Group);

        for (var i:Number = 0; i < groupList.length; i++) {
            var groupItem:Object = groupList[i];
            var groupName:String = groupItem.name;
            if (groupName == undefined) continue;

            var members:Array = this.ensureArray(groupItem.Member);
            if (members.length > 0) {
                var memberNames:Array = [];
                for (var j:Number = 0; j < members.length; j++) {
                    memberNames.push(String(members[j]));
                }
                groups[groupName] = memberNames;
            }
        }

        return groups;
    }

    // ========== 工具方法 ==========

    /**
     * 确保值为数组
     * XMLParser 对于单个子节点返回对象，多个子节点返回数组
     * 注意：AS2 中 instanceof Array 可能不可靠，使用 length 属性检测
     */
    private function ensureArray(value):Array {
        if (value == undefined || value == null) {
            return [];
        }
        // AS2 中 instanceof Array 可能失败，改用 length 属性和 push 方法检测
        if (typeof(value.length) == "number" && typeof(value.push) == "function") {
            return value;
        }
        var arr:Array = [];
        arr.push(value);
        return arr;
    }

    // ========== 访问器 ==========

    /**
     * 获取已加载的配置数据
     */
    public function getData():Object {
        return this._data;
    }

    /**
     * 获取 CommandSet ID
     */
    public function getSetId():String {
        return this._setId;
    }

    /**
     * 是否已加载
     */
    public function isLoaded():Boolean {
        return this._data != null;
    }

    /**
     * 是否正在加载
     */
    public function isLoading():Boolean {
        return this._isLoading;
    }
}
