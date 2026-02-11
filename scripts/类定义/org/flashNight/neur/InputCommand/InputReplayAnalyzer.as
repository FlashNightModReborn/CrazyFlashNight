import org.flashNight.neur.Automaton.TrieDFA;
import org.flashNight.neur.InputCommand.CommandDFA; 
import org.flashNight.neur.InputCommand.CommandRegistry;
import org.flashNight.neur.InputCommand.InputEvent;

/**
 * InputReplayAnalyzer - 输入序列离线分析工具
 *
 * 用于分析录制的输入序列，支持：
 * - 全序列招式检测
 * - 按标签/分组过滤
 * - 时间线生成
 * - 统计报告
 *
 * 典型用途：
 * - 战斗回放分析
 * - AI 行为调试
 * - 招式使用统计
 * - 教程/演示录制验证
 *
 * 使用方式：
 *   var analyzer:InputReplayAnalyzer = new InputReplayAnalyzer(registry);
 *   var report:Object = analyzer.analyze(recordedInputs);
 *   trace("Total matches: " + report.totalMatches);
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.neur.InputCommand.InputReplayAnalyzer {

    // ========== 内部引用 ==========

    /** DFA 实例 */
    private var dfa:TrieDFA;

    /** Registry 实例（可选，用于元数据查询） */
    private var registry:CommandRegistry;

    /** CommandDFA 实例（可选，直接使用时） */
    private var commandDFA:CommandDFA;

    // ========== 构造函数 ==========

    /**
     * 创建 InputReplayAnalyzer 实例
     *
     * @param source 数据源，可以是：
     *   - CommandRegistry: 使用其内部的 DFA
     *   - CommandDFA: 使用其内部的 TrieDFA
     *   - TrieDFA: 直接使用
     */
    public function InputReplayAnalyzer(source:Object) {
        if (source instanceof CommandRegistry) {
            this.registry = CommandRegistry(source);
            this.commandDFA = this.registry.getDFA();
            this.dfa = this.commandDFA.getTrieDFA();
        } else if (source instanceof CommandDFA) {
            this.commandDFA = CommandDFA(source);
            this.dfa = this.commandDFA.getTrieDFA();
            this.registry = null;
        } else if (source instanceof TrieDFA) {
            this.dfa = TrieDFA(source);
            this.commandDFA = null;
            this.registry = null;
        } else {
            trace("[InputReplayAnalyzer] Error: Invalid source type");
        }
    }

    // ========== 核心分析方法 ==========

    /**
     * 分析输入序列
     *
     * @param sequence 输入事件序列（Array of InputEvent IDs）
     * @param options 可选配置：
     *   - filterMask:Number   只包含指定 mask 中的命令
     *   - filterTags:Array    只包含指定标签的命令
     *   - minPriority:Number  最小优先级过滤
     * @return 分析报告对象
     */
    public function analyze(sequence:Array, options:Object):Object {
        if (sequence == undefined || sequence.length == 0) {
            return this.createEmptyReport();
        }

        if (options == undefined) {
            options = {};
        }

        // 执行全序列匹配
        this.dfa.findAllFast(sequence);

        var totalMatches:Number = this.dfa.resultCount;
        var positions:Array = this.dfa.resultPositions;
        var patternIds:Array = this.dfa.resultPatternIds;

        // 构建结果
        var commands:Array = [];
        var timeline:Array = [];
        var commandStats:Object = {};

        for (var i:Number = 0; i < totalMatches; i++) {
            var pos:Number = positions[i];
            var cmdId:Number = patternIds[i];

            // 应用过滤
            if (!this.passFilter(cmdId, options)) {
                continue;
            }

            // 获取命令信息
            var cmdInfo:Object = this.getCommandInfo(cmdId);
            cmdInfo.position = pos;
            cmdInfo.endPosition = pos + cmdInfo.length;

            commands.push(cmdInfo);

            // 统计
            var cmdName:String = cmdInfo.name;
            if (commandStats[cmdName] == undefined) {
                commandStats[cmdName] = {
                    count: 0,
                    cmdId: cmdId,
                    positions: []
                };
            }
            commandStats[cmdName].count++;
            commandStats[cmdName].positions.push(pos);
        }

        // 按位置排序
        commands.sort(function(a, b) {
            if (a.position != b.position) return a.position - b.position;
            return b.priority - a.priority; // 同位置，高优先级在前
        });

        // 生成时间线
        timeline = this.generateTimeline(commands, sequence.length);

        return {
            sequenceLength: sequence.length,
            totalMatches: commands.length,
            commands: commands,
            timeline: timeline,
            stats: commandStats
        };
    }

    /**
     * 快速统计（只返回计数，不构建详细信息）
     *
     * @param sequence 输入事件序列
     * @return 匹配总数
     */
    public function countMatches(sequence:Array):Number {
        if (sequence == undefined || sequence.length == 0) {
            return 0;
        }
        return this.dfa.findAllFast(sequence);
    }

    /**
     * 检查序列中是否包含指定命令
     *
     * @param sequence 输入事件序列
     * @param cmdId 命令ID
     * @return 是否包含
     */
    public function containsCommand(sequence:Array, cmdId:Number):Boolean {
        this.dfa.findAllFast(sequence);

        for (var i:Number = 0; i < this.dfa.resultCount; i++) {
            if (this.dfa.resultPatternIds[i] == cmdId) {
                return true;
            }
        }
        return false;
    }

    /**
     * 查找指定命令的所有出现位置
     *
     * @param sequence 输入事件序列
     * @param cmdId 命令ID
     * @return 位置数组
     */
    public function findCommandPositions(sequence:Array, cmdId:Number):Array {
        this.dfa.findAllFast(sequence);

        var result:Array = [];
        for (var i:Number = 0; i < this.dfa.resultCount; i++) {
            if (this.dfa.resultPatternIds[i] == cmdId) {
                result.push(this.dfa.resultPositions[i]);
            }
        }
        return result;
    }

    // ========== 过滤方法 ==========

    /**
     * 检查命令是否通过过滤条件
     */
    private function passFilter(cmdId:Number, options:Object):Boolean {
        // Mask 过滤
        if (options.filterMask != undefined && options.filterMask != 0) {
            if (this.registry != null) {
                if (!this.registry.isCommandInMask(cmdId, options.filterMask)) {
                    return false;
                }
            }
        }

        // 标签过滤
        if (options.filterTags != undefined && options.filterTags.length > 0) {
            if (this.registry != null) {
                var config:Object = this.registry.getCommandConfig(cmdId);
                if (config == null || config.tags == undefined) {
                    return false;
                }

                var hasTag:Boolean = false;
                for (var i:Number = 0; i < options.filterTags.length; i++) {
                    var filterTag:String = options.filterTags[i];
                    for (var j:Number = 0; j < config.tags.length; j++) {
                        if (config.tags[j] == filterTag) {
                            hasTag = true;
                            break;
                        }
                    }
                    if (hasTag) break;
                }
                if (!hasTag) return false;
            }
        }

        // 优先级过滤
        if (options.minPriority != undefined) {
            var priority:Number = this.dfa.getPriority(cmdId);
            if (priority < options.minPriority) {
                return false;
            }
        }

        return true;
    }

    // ========== 辅助方法 ==========

    /**
     * 获取命令详细信息
     */
    private function getCommandInfo(cmdId:Number):Object {
        var info:Object = {
            cmdId: cmdId,
            name: "",
            action: "",
            length: this.dfa.getPatternLength(cmdId),
            priority: this.dfa.getPriority(cmdId),
            sequence: this.dfa.getPattern(cmdId),
            tags: []
        };

        if (this.commandDFA != null) {
            info.name = this.commandDFA.getCommandName(cmdId);
            info.action = this.commandDFA.getCommandAction(cmdId);
        } else {
            info.name = "Pattern_" + cmdId;
            info.action = "Pattern_" + cmdId;
        }

        if (this.registry != null) {
            var config:Object = this.registry.getCommandConfig(cmdId);
            if (config != null && config.tags != undefined) {
                info.tags = config.tags;
            }
        }

        return info;
    }

    /**
     * 生成时间线视图
     */
    private function generateTimeline(commands:Array, seqLength:Number):Array {
        var timeline:Array = [];

        // 按位置分组
        var byPosition:Object = {};
        for (var i:Number = 0; i < commands.length; i++) {
            var cmd:Object = commands[i];
            var pos:Number = cmd.position;

            if (byPosition[pos] == undefined) {
                byPosition[pos] = [];
            }
            byPosition[pos].push(cmd);
        }

        // 转换为数组
        for (var posStr:String in byPosition) {
            var posNum:Number = parseInt(posStr);
            timeline.push({
                position: posNum,
                commands: byPosition[posStr]
            });
        }

        // 按位置排序
        timeline.sort(function(a, b) {
            return a.position - b.position;
        });

        return timeline;
    }

    /**
     * 创建空报告
     */
    private function createEmptyReport():Object {
        return {
            sequenceLength: 0,
            totalMatches: 0,
            commands: [],
            timeline: [],
            stats: {}
        };
    }

    // ========== 可视化辅助 ==========

    /**
     * 生成人类可读的分析报告字符串
     *
     * @param sequence 输入事件序列
     * @param options 分析选项
     * @return 格式化的报告字符串
     */
    public function generateReport(sequence:Array, options:Object):String {
        var report:Object = this.analyze(sequence, options);
        var lines:Array = [];

        lines.push("===== Input Replay Analysis Report =====");
        lines.push("Sequence length: " + report.sequenceLength + " events");
        lines.push("Total matches: " + report.totalMatches);
        lines.push("");

        // 统计摘要
        lines.push("--- Command Statistics ---");
        for (var cmdName:String in report.stats) {
            var stat:Object = report.stats[cmdName];
            lines.push("  " + cmdName + ": " + stat.count + " times");
        }
        lines.push("");

        // 时间线
        lines.push("--- Timeline ---");
        for (var i:Number = 0; i < report.timeline.length; i++) {
            var entry:Object = report.timeline[i];
            var cmdNames:Array = [];
            for (var j:Number = 0; j < entry.commands.length; j++) {
                cmdNames.push(entry.commands[j].name);
            }
            lines.push("  [" + entry.position + "] " + cmdNames.join(", "));
        }
        lines.push("");

        // 详细命令列表
        lines.push("--- Detailed Commands ---");
        for (var k:Number = 0; k < report.commands.length; k++) {
            var cmd:Object = report.commands[k];
            var seqStr:String = InputEvent.sequenceToString(cmd.sequence);
            lines.push("  " + k + ". " + cmd.name +
                      " @ pos " + cmd.position + "-" + cmd.endPosition +
                      " (" + seqStr + ")" +
                      " priority=" + cmd.priority);
        }

        lines.push("=========================================");

        return lines.join("\n");
    }

    /**
     * 将分析结果转换为可视化数据（用于 UI 绘制）
     *
     * @param sequence 输入事件序列
     * @return 可视化数据对象
     */
    public function generateVisualization(sequence:Array):Object {
        var report:Object = this.analyze(sequence);

        // 为每个位置生成标记
        var markers:Array = new Array(sequence.length);
        for (var i:Number = 0; i < sequence.length; i++) {
            markers[i] = {
                position: i,
                event: sequence[i],
                eventName: InputEvent.getName(sequence[i]),
                matchStarts: [],   // 从这里开始的匹配
                matchEnds: [],     // 在这里结束的匹配
                inProgress: []     // 经过这里的匹配
            };
        }

        // 填充匹配信息
        for (var j:Number = 0; j < report.commands.length; j++) {
            var cmd:Object = report.commands[j];
            var startPos:Number = cmd.position;
            var endPos:Number = cmd.endPosition;

            // 标记开始
            if (startPos < markers.length) {
                markers[startPos].matchStarts.push(cmd);
            }

            // 标记结束
            if (endPos > 0 && endPos <= markers.length) {
                markers[endPos - 1].matchEnds.push(cmd);
            }

            // 标记中间
            for (var p:Number = startPos + 1; p < endPos - 1 && p < markers.length; p++) {
                markers[p].inProgress.push(cmd);
            }
        }

        return {
            sequenceLength: sequence.length,
            markers: markers,
            commands: report.commands,
            stats: report.stats
        };
    }

    // ========== 调试方法 ==========

    /**
     * 打印分析结果到 trace
     */
    public function dump(sequence:Array, options:Object):Void {
        trace(this.generateReport(sequence, options));
    }
}
