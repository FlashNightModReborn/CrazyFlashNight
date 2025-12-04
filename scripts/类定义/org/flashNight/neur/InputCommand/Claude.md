下面我先给出“要拆什么 + 拆成什么样”的整体图，然后再给一个可以按步骤执行的完整重构计划。

一、要拆的东西：两类配置

搓招“数据配置”（当前在 CommandConfig.as 里）

现在包括：
commands: name / sequence / action / priority / tags
derivations: 派生关系
groups: 分组
目标：XML 化到 data/ 下，支持多子模块 + list.xml 汇总。
搓招“运行时参数配置”

目前散落在代码里：
CommandDFA.DEFAULT_TIMEOUT
CommandDFA.DEFAULT_FRAME_WINDOW
CommandDFA.TIMEOUT_BASE / TIMEOUT_FACTOR
InputHistoryBuffer.DEFAULT_*
InputSampler.doubleTapWindow（这个也非常像配置）
目标：独立一个 config XML（如 data/config/InputCommandRuntimeConfig.xml）集中管理。
二、CommandConfig 拆分为 XML 的建议结构

以你的习惯，我建议这样组织目录：

data/inputCommand/list.xml（汇总入口）
data/inputCommand/barehand.xml（空手搓招）
data/inputCommand/light_weapon.xml（轻武器搓招）
data/inputCommand/heavy_weapon.xml（重武器搓招）
后续可以很自然再加：
data/inputCommand/gun.xml、knife.xml、character_X.xml 等
1）list.xml 结构（例）

<?xml version="1.0" encoding="UTF-8"?>
<InputCommandSets>
    <Set id="barehand"   file="data/inputCommand/barehand.xml"/>
    <Set id="lightWeapon" file="data/inputCommand/light_weapon.xml"/>
    <Set id="heavyWeapon" file="data/inputCommand/heavy_weapon.xml"/>
</InputCommandSets>
只负责告诉 loader “有哪些 set + 各自的 XML 路径”。
未来新增 set 只需要改这个文件，不改代码。
2）单个 command set XML（以空手为例）

<?xml version="1.0" encoding="UTF-8"?>
<CommandSet id="barehand" label="空手">
    <Commands>
        <Command name="波动拳" action="波动拳" priority="10">
            <!-- 建议用事件常量名：DOWN_FORWARD / A_PRESS，避免编码问题 -->
            <Sequence>
                <Event>DOWN_FORWARD</Event>
                <Event>A_PRESS</Event>
            </Sequence>
            <Tags>
                <Tag>空手</Tag>
                <Tag>远程</Tag>
                <Tag>必杀</Tag>
            </Tags>
            <!-- 可选：把等级 / MP 等门槛也下沉到 data 层 -->
            <Requirements>
                <Skill name="拳脚攻击" minLevel="5"/>
                <!-- <MP ratio="0.1"/> -->
            </Requirements>
        </Command>

        <Command name="诛杀步" action="诛杀步" priority="5">
            <Sequence>
                <Event>DOUBLE_TAP_FORWARD</Event>
            </Sequence>
            <Tags>
                <Tag>空手</Tag>
                <Tag>移动</Tag>
                <Tag>基础</Tag>
            </Tags>
        </Command>

        <!-- 其它命令... -->
    </Commands>

    <Derivations>
        <Derive from="波动拳">
            <To>诛杀步</To>
            <To>后撤步</To>
            <To>燃烧指节</To>
            <To>能量喷泉</To>
        </Derive>
        <Derive from="诛杀步">
            <To>波动拳</To>
            <To>后撤步</To>
            <To>燃烧指节</To>
            <To>能量喷泉</To>
        </Derive>
        <!-- ... -->
    </Derivations>

    <Groups>
        <Group name="空手全部">
            <Member>波动拳</Member>
            <Member>诛杀步</Member>
            <Member>后撤步</Member>
            <Member>燃烧指节</Member>
            <Member>能量喷泉</Member>
        </Group>
        <Group name="移动类">
            <Member>诛杀步</Member>
            <Member>后撤步</Member>
        </Group>
        <Group name="攻击类">
            <Member>波动拳</Member>
            <Member>燃烧指节</Member>
            <Member>能量喷泉</Member>
        </Group>
    </Groups>
</CommandSet>
解析之后返回的结构仍然是：
{
  commands: [...],
  derivations: {...},
  groups: {...}
}
和现在 CommandConfig.getBarehanded() 返回的对象兼容，这样 CommandRegistry.loadConfig() 完全不用改。
3）事件名称 → InputEvent ID 的映射

XML 里推荐用 常量名风格：DOWN_FORWARD / A_PRESS / SHIFT_BACK，便于肉眼识别，也避免 UTF-8 箭头字符的编码坑。

需要在 InputEvent 里增加一个反向映射方法，例如：

public static function fromName(name:String):Number {
    // 支持 "DOWN_FORWARD" 这类标识符
    if (name == "DOWN_FORWARD") return DOWN_FORWARD;
    if (name == "A_PRESS") return A_PRESS;
    // ...
}
若你更喜欢 "↓↘A" 这种紧凑表示，也可以在 XML 用 <SequenceString>↓↘A</SequenceString> 然后重用现有 InputEvent.getName 的表去做逆向解析（但会涉及到字符集，稍复杂）。

三、运行时参数独立 XML 的建议

是的，这部分很适合拆出来一个单独的 runtime config XML，例如：

文件：data/config/InputCommandRuntimeConfig.xml
结构示例：

<?xml version="1.0" encoding="UTF-8"?>
<InputCommandRuntimeConfig>
    <DFA>
        <DefaultTimeout>5</DefaultTimeout>               <!-- CommandDFA.DEFAULT_TIMEOUT -->
        <DefaultFrameWindow>15</DefaultFrameWindow>      <!-- CommandDFA.DEFAULT_FRAME_WINDOW -->
        <TimeoutBase>3</TimeoutBase>                     <!-- CommandDFA.TIMEOUT_BASE -->
        <TimeoutFactor>2</TimeoutFactor>                 <!-- CommandDFA.TIMEOUT_FACTOR -->
    </DFA>

    <HistoryBuffer>
        <EventCapacity>64</EventCapacity>                <!-- InputHistoryBuffer.DEFAULT_EVENT_CAPACITY -->
        <FrameCapacity>30</FrameCapacity>                <!-- InputHistoryBuffer.DEFAULT_FRAME_CAPACITY -->
    </HistoryBuffer>

    <Sampler>
        <DoubleTapWindow>12</DoubleTapWindow>            <!-- InputSampler.doubleTapWindow 默认值 -->
    </Sampler>

    <!-- 可选：按模组细化参数（例） -->
    <ModuleOverrides>
        <Module id="heavyWeapon">
            <DefaultTimeout>6</DefaultTimeout>
        </Module>
    </ModuleOverrides>
</InputCommandRuntimeConfig>
使用方式：

新增一个配置类，例如：org.flashNight.neur.InputCommand.InputCommandRuntimeConfig：

静态字段：defaultTimeout / defaultFrameWindow / timeoutBase / timeoutFactor / historyEventCap / historyFrameCap / doubleTapWindow 等。
提供方法 applyToDFA(dfa:CommandDFA):Void，或供 CommandDFA 的构造/静态方法读取。
在 LoadXml 目录下加一个 InputCommandRuntimeConfigLoader，在游戏启动时（例如 通信_fs_帧计时器.as 的初始化阶段）加载 XML，然后：

InputCommandRuntimeConfig.applyFromXML(parsedConfig);
CommandDFA/InputHistoryBuffer/InputSampler 中：

原来的静态常量 保留作为默认值，但在构造函数里优先读取 InputCommandRuntimeConfig 的值：
if (timeout == undefined) timeout = InputCommandRuntimeConfig.defaultTimeout;
这样即便 XML 没加载成功，也不会炸，回退到硬编码默认值。
四、需要新增/调整的模块（代码层面）

1）新的 XML Loader 类（放在你说的 LoadXml 目录）

org.flashNight.gesh.xml.LoadXml.InputCommandSetXMLLoader

职责：加载单个 <CommandSet> XML，并解析成 {commands, derivations, groups}。
API 形态可以跟 StageXMLLoader 类似：
class InputCommandSetXMLLoader {
    public function InputCommandSetXMLLoader(path:String,
                                             onLoad:Function,
                                             onError:Function) { ... }
}
org.flashNight.gesh.xml.LoadXml.InputCommandListXMLLoader

读取 data/inputCommand/list.xml，拿到 { id -> filePath } 映射。
根据你需要，可以：
只做“读取列表”，由外部自己循环加载；
或者内部帮你依次加载所有 set，最后一次性把结果传出。
org.flashNight.gesh.xml.LoadXml.InputCommandRuntimeConfigLoader

一个文件一个对象，结构非常简单，读取后直接调用 InputCommandRuntimeConfig.applyFromXML()。
2）CommandConfig.as 的重构方向

保留核心工具方法，弱化“数据源”角色：

保留：

merge(configs:Array):Object
dump(config:Object):Void
数据源改成“外部注入”模式：

在游戏初始化时：
用 InputCommandListXMLLoader + InputCommandSetXMLLoader 加载各个 set 的 {commands, derivations, groups} 对象。
然后在某个中心（例如 _root.帧计时器.commandModulesConfig 或 CommandConfig 的静态字段）里缓存：
CommandConfig.barehandConfig = parsedBarehandConfig;
CommandConfig.lightWeaponConfig = parsedLightConfig;
CommandConfig.heavyWeaponConfig = parsedHeavyConfig;
CommandConfig.getBarehanded() 不再硬编码，而是：
public static function getBarehanded():Object {
    return CommandConfig.barehandConfig;
}
这样：
CommandRegistry.loadConfig(CommandConfig.getBarehanded()) 这类调用点完全不用改；
数据从 XML 来，结构仍然兼容之前的注册逻辑。
3）CommandDFA.as / InputHistoryBuffer.as / InputSampler.as

引入 InputCommandRuntimeConfig 后，将默认参数改成“优先读取 config，失败时回退到原常量”。
如果以后你想支持“按模组不同超时”，可以在 _root.帧计时器.键盘输入控制目标 里切模组时按需覆盖 timeout 参数（比如兵器模组用更宽容的超时）。
4）通信_fs_帧计时器.as 中的初始化顺序

理想顺序（伪代码）：

// 1. 初始化帧计时器基础设施
_root.帧计时器.初始化任务栈();

// 2. 加载 InputCommand 运行时配置
var runtimeLoader:InputCommandRuntimeConfigLoader = new InputCommandRuntimeConfigLoader(
    "data/config/InputCommandRuntimeConfig.xml",
    function(cfg:Object):Void {
        InputCommandRuntimeConfig.applyFromXML(cfg);

        // 3. 加载搓招 CommandSet 列表 + 每个 set
        var listLoader:InputCommandListXMLLoader = new InputCommandListXMLLoader(
            "data/inputCommand/list.xml",
            function(list:Object):Void {
                // list: { barehand:"data/inputCommand/barehand.xml", ... }
                // 逐个 set 用 InputCommandSetXMLLoader 加载，完成后：
                CommandConfig.barehandConfig = ...;
                CommandConfig.lightWeaponConfig = ...;
                CommandConfig.heavyWeaponConfig = ...;

                // 4. 现在再构建 CommandRegistry / CommandDFA
                _root.帧计时器.初始化输入搓招系统();
            }
        );
    }
);
在你的现有实现中，初始化输入搓招系统 是直接手动 loadConfig(CommandConfig.getXxx())，这一步只需要改为“等 XML 全部加载完再调用”。
5）InputCommandTest.as 如何处理

测试环境不方便搞异步 XML 加载，可以：
保留当前硬编码版 CommandConfig 作为测试专用；
在 runtime 配置里用 XML，测试则仍旧 CommandConfig.getBarehanded() 返回内置数据。
一种办法是拆出 CommandConfigXML.as 专门给 runtime 用，现有 CommandConfig.as 留给测试。
如果你以后希望连测试也验证 XML，可以再单独写一个基于 XML 的 InputCommandConfigTest，不必一次到位。
五、完整重构计划（按步骤执行）

设计并写出 XML 模式初稿

在 data/inputCommand/ 下新建 barehand.xml/light_weapon.xml/heavy_weapon.xml，内容按上面示例先抽取当前 CommandConfig 的数据。
写 list.xml 列出这三个 set。
加 InputCommandRuntimeConfig.xml

先只填现有硬编码值（5/15/3/2/64/30/12），保证行为不变。
一并决定是否要 per-module override（可以先不做）。
实现 XML Loader 类

在 scripts/类定义/org/flashNight/gesh/xml/LoadXml 下新增：
InputCommandSetXMLLoader.as
InputCommandListXMLLoader.as
InputCommandRuntimeConfigLoader.as
Loader 内部用 XML + 你现有的 XMLParser 风格解析，最终返回 JS-like Object。
新增 InputCommandRuntimeConfig 类

用静态字段持有配置值；
提供 applyFromXML(cfg:Object)；
在 CommandDFA/InputHistoryBuffer/InputSampler 内用这些值作为默认配置来源（回退到旧常量）。
调整 CommandConfig.as

保留 merge/dump；
新增静态字段 barehandConfig/lightWeaponConfig/heavyWeaponConfig；
把 getBarehanded/getLightWeapon/getHeavyWeapon 改为直接返回这些字段。
临时保留当前硬编码实现，但包一层开关，便于测试用：
比如如果 barehandConfig == null 时，回退到旧硬编码数据。
在帧计时器初始化中接入 XML 加载

在 通信_fs_帧计时器.as 中：
在调用 _root.帧计时器.初始化输入搓招系统() 之前，先用 Loader 加载 runtime config + command sets，并写入 InputCommandRuntimeConfig 和 CommandConfig 的静态字段。
加一层防护：若 XML 加载失败，使用 CommandConfig 的硬编码 fallback；并 trace 一条错误消息。
验证与渐进迁移

先只在空手/兵器模式下跑 XML 版 config，确认触发逻辑与现在一致；
如无问题，再考虑把“技能等级/MP 消耗/否定按键”等门槛逐步下沉到 XML 的 <Requirements> 部分，再由单位函数脚本读取这些配置，而不是硬写在脚本里。
这样拆完之后：

搓招指令结构完全数据化，可增删命令/派生/分组而不必改 AS2。
运行时行为（超时、窗口大小）也可以在 XML 里细调，而不用重新导出 SWF。
现有 CommandRegistry/CommandDFA 与 通信_fs_帧计时器 的多模组架构都可以几乎不动，只是数据来源从“硬编码”换成“XML loader + CommandConfig 缓存”。