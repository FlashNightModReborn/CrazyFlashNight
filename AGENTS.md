# AGENTS.md

## 项目概述
《闪客快打7佣兵帝国》（Crazy Flasher 7: Mercenary Empire）单机版 MOD 开发工程，基于 ActionScript 2.0 和 Adobe Flash 技术栈。项目已获得原作者 **andylaw** 授权，旨在提供可修改的单机游戏体验。

**⚠️ 重要提示：此项目无法在 Linux 容器或现代开发环境中直接编译运行，需要 Windows 环境和 Adobe Flash CS6。**

## 环境限制说明

### 开发环境要求
- **操作系统**：Windows 7/10/11（必需）
- **核心软件**：Adobe Flash Professional CS6（无可替代方案）
- **语言版本**：ActionScript 2.0（已停止维护的旧版本）
- **编译方式**：仅支持 Flash IDE 图形界面编译，**无命令行编译选项**
- **辅助工具**：Node.js 14+ （用于本地服务器）

### AI 代理限制
- **禁止尝试编译**：不要尝试编译 ActionScript 代码或 FLA 文件
- **禁止环境搭建**：不要尝试在容器中安装 Flash 开发环境
- **只能进行代码审查**：仅可分析代码结构、语法和逻辑

## 项目结构详解

### 完整目录布局
```
/workspace/CrazyFlashNight
├── 0.说明文件与教程/        # 中文项目文档和教程
├── automation/             # PowerShell自动化脚本和config.toml
├── config/                 # XML系统配置文件
├── data/                   # 游戏数据：关卡、物品、单位等
├── flashswf/               # FLA/SWF资源（此处不可编辑）
├── scripts/                # ActionScript 2.0源代码
│   ├── 展现/                # 视觉系统和UI交互代码
│   ├── 引擎/                # 引擎工具（调试、随机、声音等）
│   ├── 通信/                # 网络和保存系统脚本
│   ├── 逻辑/                # 游戏逻辑
│   └── 类定义/              # 主要类库（org.flashNight.*）
├── tools/Local Server/     # 用于AS2的Node.js本地服务器
└── 其他（README.md、crossdomain.xml等）
```

### 可直接修改的文件
```
data/                       # 游戏数据文件（XML/JSON，立即生效）
├── stages/                 # 关卡定义
├── items/                  # 物品配置
├── units/                  # 单位数据
├── dialogues/              # 对话脚本
├── environment/            # 环境设置（如scene_environment.xml）
└── *.xml                   # 其他游戏数据

config/                     # 运行配置文件（XML，立即生效）
├── PIDControllerConfig.xml        # PID控制器配置
├── WeatherSystemConfig.xml        # 天气系统配置（昼夜循环、光照）
└── *.xml                   # 其他系统配置

tools/Local Server/         # Node.js本地服务器（可测试和修改）
├── server.js               # 主服务器文件
├── controllers/            # 任务处理器（eval、regex、计算、音频）
├── routes/                 # HTTP路由
├── services/               # 服务模块（socketServer.js等）
├── utils/                  # 工具模块（logger.js等）
├── config/ports.js         # 端口配置
├── package.json            # 依赖配置
└── server.md              # 服务器详细文档

automation/                 # 自动化脚本（PowerShell）
├── start.ps1              # 主启动脚本
├── start_game.ps1         # 游戏启动脚本
├── start_server.ps1       # 服务器启动脚本
├── configure_server.ps1   # 服务器配置脚本
└── config.toml            # 运行时配置（Flash路径、SWF路径等）
```

### 需要特殊处理的文件（仅可分析，无法编译）
```
scripts/                    # ActionScript 2.0源代码
├── 展现/                   # 视觉系统和UI交互
├── 引擎/                   # 引擎核心代码
│   ├── 引擎_fs_随机数引擎.as
│   ├── 引擎_fs_eval解析器.as
│   └── 引擎_fs_调试模式.as
├── 通信/                   # 网络通信模块（XML解析、本地服务器通信）
├── 逻辑/                   # 游戏逻辑
│   ├── 关卡系统/           # 如关卡系统_fs_佣兵刷新系统.as
│   └── 战斗系统/
└── 类定义/org/flashNight/  # 核心类库
    ├── arki/               # 主要游戏引擎组件
    │   ├── bullet/         # 子弹系统（Factory/BulletFactory.as等）
    │   ├── camera/         # 摄像机系统
    │   ├── component/      # 单位组件
    │   ├── item/           # 物品管理
    │   └── audio/          # 音频引擎
    ├── aven/               # 事件协调工具
    ├── gesh/               # 通用工具（数组、字符串、解析、算法）
    ├── naki/               # 数据结构、数学工具、随机数引擎
    │   ├── random/         # LinearCongruentialEngine、MersenneTwister等
    │   └── math/           # AdvancedMatrix.as等
    ├── neur/               # 事件系统、控制器、计时器、状态机
    │   └── Timer/          # FrameTimer.as等
    └── sara/               # 物理引擎（粒子、约束、表面）

flashswf/                   # Flash资源文件（需Flash CS6编辑）
├── arts/                   # 角色与怪物逻辑（链接到FLA脚本）
├── UI/                     # 用户界面代码和素材
├── backgrounds/            # 背景资源
├── miniGames/              # 小游戏资源
└── skybox/                # 天空盒资源
```

## 核心类库详解

### scripts/类定义/org/flashNight 包结构

#### arki - 游戏引擎核心组件
- **bullet/** - 子弹工厂和生命周期处理器
- **camera/** - 摄像机控制系统
- **component/** - 单位组件系统
- **item/** - 物品管理系统
- **audio/** - 音频引擎（如LightweightSoundEngine实现IMusicEngine）

#### aven - 事件协调工具
- 事件总线和事件包装器

#### gesh - 通用工具库
- 数组操作工具
- 字符串解析工具（如EvalParser.as）
- 算法实现

#### naki - 数据结构和数学工具
- 高级数学运算（AdvancedMatrix.as）
- 随机数引擎（LinearCongruentialEngine、MersenneTwister）
- 数据结构实现

#### neur - 事件和控制系统
- 事件系统
- 控制器
- 计时器（FrameTimer.as）
- 状态机

#### sara - 物理引擎
- 粒子系统
- 物理约束
- 表面碰撞检测

### 特殊工具类示例
- **DepthManager.as** - 使用AVL树管理MovieClip深度，包含详细调试跟踪
- **LightweightSoundEngine.as** - 实现IMusicEngine接口的简单音频播放

## Node.js 本地服务器详解

### 服务器架构
```
tools/Local Server/
├── server.js              # Express HTTP服务器 + XMLSocket服务
├── controllers/            # 任务处理控制器
│   ├── audioTask.js       # 音频播放（使用howler库）
│   ├── evalTask.js        # 安全代码执行（使用vm2沙箱）
│   ├── regexTask.js       # 正则表达式处理
│   └── computationTask.js # 计算任务
├── services/
│   └── socketServer.js    # XMLSocket消息处理和任务分发
├── utils/
│   └── logger.js          # 基于winston的日志轮转
├── config/
│   └── ports.js           # 从"eyeOf119"提取可用端口，默认3000
└── server.md              # 详细模块文档和JSON请求示例
```

### 服务器功能
- **HTTP服务器**：提供REST API和静态文件服务
- **XMLSocket服务器**：与AS2客户端进行实时通信
- **任务处理**：支持代码执行、正则处理、音频播放等
- **CORS支持**：配置跨域资源共享
- **日志系统**：每日轮转的结构化日志

### 启动服务器
```bash
# 在tools/Local Server/目录下
node server.js
```

### 路由示例
- `GET /getSocketPort` - 获取XMLSocket端口
- 其他路由详见`server.md`

## 代码规范与风格

### ActionScript 2.0 编码规范
- **命名约定**：
  - 类名使用 PascalCase：`PlayerController`、`BulletFactory`
  - 方法和变量使用 camelCase：`updatePosition`、`createBullet`
  - 常量使用 UPPER_CASE：`MAX_HEALTH`、`DEFAULT_SPEED`
  - 私有成员使用下划线前缀：`_privateVar`、`_health`
  - 接口以 `I` 开头：`IMusicEngine`、`IMovable`

- **代码组织**：
  - 每个类一个文件
  - 包结构严格遵循 `org.flashNight.*` 命名空间
  - 测试文件放在对应的 `test/` 子目录下

### 文档要求（JSDoc 风格）
所有 ActionScript 代码必须包含完整的 JSDoc 风格注释：

```actionscript
/**
 * 子弹工厂类，负责创建和管理子弹实例
 * @class BulletFactory
 * @package org.flashNight.arki.bullet.Factory
 * @author [作者名]
 * @version 1.0.0
 */
class org.flashNight.arki.bullet.Factory.BulletFactory {
    
    /**
     * 当前激活的子弹数量
     * @type Number
     * @private
     */
    private var _activeBulletCount:Number;
    
    /**
     * 创建新的子弹实例
     * @param {Number} x 起始X坐标
     * @param {Number} y 起始Y坐标
     * @param {Number} angle 发射角度（弧度）
     * @param {Number} speed 初始速度
     * @returns {MovieClip} 创建的子弹MovieClip对象
     */
    public function createBullet(x:Number, y:Number, angle:Number, speed:Number):MovieClip {
        // 实现代码
        trace("创建子弹: x=" + x + ", y=" + y + ", angle=" + angle);
        return bulletClip;
    }
}
```

### 调试和跟踪规范
- 使用 `trace()` 语句进行调试输出
- 关键操作必须包含详细的跟踪信息
- 依赖 `_root` 全局变量进行MovieClip操作

### XML 配置文件规范
- 使用4空格缩进
- 属性值必须使用双引号
- 添加详细的中文注释说明各参数用途
- 保持文档结构清晰

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- 天气系统配置文件 -->
<WeatherSystemConfig>
    <!-- 昼夜循环设置 -->
    <DayNightCycle>
        <dayLength>1200</dayLength>        <!-- 白天持续时间（帧） -->
        <nightLength>800</nightLength>     <!-- 夜晚持续时间（帧） -->
        <transitionTime>100</transitionTime>  <!-- 过渡时间（帧） -->
    </DayNightCycle>
    
    <!-- 光照级别配置 -->
    <LightLevels>
        <day>100</day>      <!-- 白天光照强度 -->
        <night>30</night>   <!-- 夜晚光照强度 -->
    </LightLevels>
</WeatherSystemConfig>
```

## 测试要求

### 测试覆盖率目标
- **代码覆盖率**：100%（所有类和方法必须有对应测试）
- **XML 配置验证**：所有配置文件必须有格式验证
- **集成测试**：关键游戏流程必须有端到端测试

### 测试文件组织
```
scripts/类定义/org/flashNight/
├── arki/
│   ├── bullet/
│   │   ├── BulletFactory.as
│   │   └── test/
│   │       └── BulletFactoryTest.as
│   └── component/
│       ├── BuffCalculator.as
│       └── test/
│           └── BuffCalculatorTest.as
└── [其他包]/
    └── test/              # 每个包都有对应的test目录
```

### 测试规范
- **一句话启动风格**：使用 `runAllTests()` 进行测试调用
- **测试类命名**：`[ClassName]Test.as`
- **测试方法命名**：`test_方法名_预期结果`
- **Mock对象**：模拟外部依赖（特别是MovieClip和_root引用）
- **边界测试**：包含边界条件和异常情况测试

### 测试示例
```actionscript
/**
 * 子弹工厂测试类
 * @class BulletFactoryTest
 */
class org.flashNight.arki.bullet.test.BulletFactoryTest {
    
    public function runAllTests():Void {
        test_createBullet_validParameters();
        test_createBullet_invalidParameters();
        trace("BulletFactoryTest: 所有测试完成");
    }
    
    private function test_createBullet_validParameters():Void {
        // 测试实现
    }
}
```

## 自动化和部署

### PowerShell 自动化脚本
```
automation/
├── start.ps1              # 主入口脚本
├── start_game.ps1         # 启动Flash游戏
├── start_server.ps1       # 启动Node.js服务器
├── configure_server.ps1   # 服务器配置
└── config.toml            # 配置文件
```

### 配置文件示例（config.toml）
```toml
[flash]
player_path = "C:/path/to/flashplayer.exe"
swf_path = "./main.swf"

[server]
auto_start = true
port = 3000

[debug]
enable_trace = true
log_level = "debug"
```

### 启动流程
1. 确保PowerShell执行策略允许脚本运行
2. 运行 `automation/start.ps1`
3. 脚本自动读取 `config.toml` 配置
4. 并行启动Flash游戏和Node.js服务器

## 开发工作流程

### 代码修改流程
1. **分析阶段**：理解现有代码结构和逻辑
2. **设计阶段**：设计修改方案和测试计划
3. **实现阶段**：编写代码和文档（**无法验证编译**）
4. **测试阶段**：编写完整的测试用例
5. **文档阶段**：更新相关文档和说明

### 文件修改优先级
1. **优先修改**：`data/` 和 `config/` 下的XML配置文件（立即生效）
2. **次要修改**：Node.js服务器代码（可测试和验证）
3. **谨慎修改**：ActionScript源代码（需要Flash CS6验证）
4. **避免修改**：已编译的SWF文件和关键引擎代码

### 版本控制指导
- **不要提交**：已编译的SWF文件或大型二进制资源
- **已提交依赖**：`node_modules`已在仓库中，添加新包时需评估是否提交
- **分支策略**：建议为重大修改创建功能分支

## 特殊注意事项

### ActionScript 2.0 特性
- **弱类型系统**：支持动态类型，但建议明确声明类型
- **原型继承**：理解原型链和继承机制
- **_root 依赖**：许多游戏逻辑依赖 `_root` 全局变量访问舞台对象
- **MovieClip 操作**：动态创建和管理 MovieClip 实例
- **事件处理**：使用 EventDispatcher 模式和自定义事件系统

### Flash 特有概念
- **MovieClip**：动态影片剪辑对象，支持嵌套和时间轴控制
- **Stage**：舞台对象和显示列表管理
- **Timeline**：时间轴和帧概念，支持帧脚本
- **Symbol**：元件和库资源管理
- **Linkage**：FLA中的脚本链接，连接代码和资源

### 兼容性考虑
- 代码必须兼容 **Flash Player 9.0+**
- 避免使用ActionScript 3.0语法特性
- 注意跨浏览器兼容性问题
- XMLSocket通信需要crossdomain.xml支持

## 禁止操作清单

### 严格禁止
- ❌ 尝试编译或构建ActionScript项目
- ❌ 安装Adobe Flash相关软件
- ❌ 修改已编译的SWF文件
- ❌ 删除或重命名核心配置文件
- ❌ 在非Windows环境下运行Flash相关操作

### 建议避免
- ⚠️ 大幅修改核心引擎代码（`scripts/引擎/`）
- ⚠️ 改变现有的包结构（`org.flashNight.*`）
- ⚠️ 修改关键的游戏平衡参数
- ⚠️ 删除已有的测试文件

## 可安全操作

### 推荐操作
- ✅ 分析和审查ActionScript代码结构
- ✅ 修改XML配置文件（`data/`、`config/`）
- ✅ 编写和完善JSDoc风格文档
- ✅ 添加测试用例（使用runAllTests()风格）
- ✅ 优化Node.js服务器代码
- ✅ 改进PowerShell自动化脚本
- ✅ 更新项目文档和教程

### 可以测试的部分
- ✅ Node.js服务器功能
- ✅ XML配置文件格式验证
- ✅ PowerShell脚本执行
- ✅ 日志系统和监控

## 获取帮助和文档

### 技术参考
- **ActionScript 2.0**：官方语言参考（已归档）
- **Flash Player API**：MovieClip、Stage等核心对象文档
- **Node.js服务器**：Express框架和XMLSocket实现

---

**核心原则：这是一个基于已停产技术栈的遗留项目MOD。重点应放在代码分析、文档完善、配置优化和测试覆盖上，而不是尝试现代化构建流程或跨平台兼容性。**