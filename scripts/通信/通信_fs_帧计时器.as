// 帧计时器负责实际帧采样、游戏任务与表现目标执行。
// 性能预设、预算及自动升降档由 C# Host 独占；AS2 断连时保持末次有效状态。

// 初始化全局帧计时器对象
_root.帧计时器 = {};

// 调用 ColliderFactoryRegistry 初始化
ColliderFactoryRegistry.init();

// ═══════════════════════════════════════════════════════════════════════════════════════
// 帧计时器初始化函数：初始化所有与帧、性能、任务调度有关的参数，并创建 TaskManager 实例
// ═══════════════════════════════════════════════════════════════════════════════════════
_root.帧计时器.初始化任务栈 = function():Void {

    // ┌─────────────────────────────────────────────────────────┐
    // │ 【模块1】基础时间参数                                      │
    // └─────────────────────────────────────────────────────────┘

    this.帧率 = 30;                      // 项目标称帧率 (Hz)
    this.毫秒每帧 = this.帧率 / 1000;    // 帧率/1000，用于乘法优化
    this.当前帧数 = 0;                   // 全局帧计数器
    // 在线补给只消费本次运行的帧时间。测试偏移不改全局帧数，
    // 因而不会影响冷却、任务调度或其他消费帧计时器的系统。
    this.在线补给起始帧 = this.当前帧数;
    this.在线补给测试偏移帧 = 0;
    this.获取在线补给帧数 = function():Number {
        var elapsed:Number = Number(this.当前帧数) - Number(this.在线补给起始帧);
        if (isNaN(elapsed) || elapsed < 0) elapsed = 0;
        var adjusted:Number = elapsed + Number(this.在线补给测试偏移帧);
        return isNaN(adjusted) || adjusted < 0 ? 0 : Math.floor(adjusted);
    };
    this.设置在线补给测试分钟 = function(minutes:Number):Object {
        var normalized:Number = Number(minutes);
        if (isNaN(normalized) || normalized == Infinity || normalized == -Infinity
                || normalized < 0 || normalized > 1440) {
            return {success:false, error:"invalid_supply_minutes"};
        }
        normalized = Math.round(normalized * 100) / 100;
        var elapsed:Number = Number(this.当前帧数) - Number(this.在线补给起始帧);
        if (isNaN(elapsed) || elapsed < 0) elapsed = 0;
        var targetFrame:Number = Math.round(normalized * 60 * Number(this.帧率));
        this.在线补给测试偏移帧 = targetFrame - elapsed;
        return {success:true, minutes:normalized,
            frame:this.获取在线补给帧数()};
    };
    this.异常间隔帧数 = this.帧率 * 5;   // 异常检测周期 = 5秒

    // ┌─────────────────────────────────────────────────────────┐
    // │ 【模块2】性能与天气参数                                    │
    // └─────────────────────────────────────────────────────────┘

    this.性能等级上限 = 0;               // 旧存档兼容字段，不参与性能决策
    this.offsetTolerance = 10;          // 镜头业务默认值，与表现预算无关
    _root.面积系数 = 300000;             // NPC 生成业务默认值，与表现预算无关
    this.更新天气间隔 = 5 * this.帧率;   // 天气系统更新周期
    this.天气待更新时间 = this.更新天气间隔;

    // ┌─────────────────────────────────────────────────────────┐
    // │ 【模块3】性能调度器                                        │
    // │ → 控制理论详见 PerformanceScheduler.as 及其子模块           │
    // └─────────────────────────────────────────────────────────┘

    // C# 独占性能决策；AS2 只负责采样和执行完整目标。
    // PIDController / AdaptiveKalmanStage / HysteresisQuantizer / PerformanceLogger 已移除。
    this.scheduler = new PerformanceScheduler(this, this.帧率, 26, _root._quality, {root:_root});
    
    // --------------------------
    // 初始化任务调度部分：创建 ScheduleTimer 和 TaskManager 实例
    // --------------------------
    this.ScheduleTimer = new CerberusScheduler();
    var singleWheelSize:Number = 150;        // 单层时间轮大小（帧）
    var multiLevelSecondsSize:Number = 60;   // 二级时间轮大小（秒）
    var multiLevelMinutesSize:Number = 60;   // 三级时间轮大小（分）
    // [DEPRECATED v1.6] precisionThreshold 已废弃，保留仅为 API 兼容
    var precisionThreshold:Number = 0.1;
    this.ScheduleTimer.initialize(singleWheelSize,
                                  multiLevelSecondsSize,
                                  multiLevelMinutesSize,
                                  this.帧率,
                                  precisionThreshold);
    // 用 TaskManager 统一管理任务调度，内部会维护任务表和零帧任务
    this.taskManager = new TaskManager(this.ScheduleTimer, this.帧率);

    // 创建冷却时间轮，用于调度轻量化的ui任务
    this.cooldownWheel = CooldownWheel.I();

    // 创建单位update时间轮
    this.unitUpdateWheel = UnitUpdateWheel.I();
    
    // --------------------------
    // 其他相关初始化
    // --------------------------
    this.server = ServerManager.getInstance();
    if (this.server.isSocketConnected) this.scheduler.onTransportConnected();
    this.eventBus = EventBus.getInstance();
    TargetCacheManager.initialize();
    
    // --------------------------
    // 注册帧更新事件：每次帧更新时调用 TaskManager.updateFrame() 来处理任务
    // --------------------------
    this.eventBus.subscribe("frameUpdate", function():Void {
        _root.帧计时器.taskManager.updateFrame();
        _root.帧计时器.unitUpdateWheel.tick(); // 单位的 update 事件发布后于调度器执行
        SceneManager.instance.update(); // 场景管理器 update 函数
        WaveSpawner.instance.tick(); // 暂时把刷怪挂在这边
        StageManager.instance.tick(); // 波次结算后推进跨子图计时池，同帧通关优先
        // _root.服务器.发布服务器消息("frameUpdate")
        // _root.服务器.发布服务器消息(_root.场景进入位置名)
        // Mover.getWalkableDirections(TargetCacheManager.findHero());
    }, this);


    this.eventBus.subscribe("frameEnd", function():Void {
        // 帧末批量处理伤害数字显示（序列化 hn 数据写入 FrameBroadcaster 数据槽）
        HitNumberBatchProcessor.flush();
        // 更新射线视觉效果管理器（支持 Tesla/Prism/Spectrum/Wave 多风格）
        RayVfxManager.update();
        // 只读当前 Flash 子弹显示状态；未收到配套 Host 能力时零序列化。
        org.flashNight.arki.render.BulletVisualProbe.flush();
        org.flashNight.arki.render.CombatFxBridge.flush();
        // 帧末统一广播（收集 cam + 消费各子系统数据槽 → 单消息发送到 C#）
        FrameBroadcaster.send();
    }, this);
};

// 调用初始化方法
_root.帧计时器.初始化任务栈();

// ===================================================================
// 搓招输入系统初始化（多模组版本 + XML 异步加载）
// ===================================================================

/**
 * 构建搓招模组
 * 从 CommandConfig 获取配置并编译 DFA
 * 此方法在 XML 加载完成后或直接使用硬编码时调用
 */
_root.帧计时器.构建搓招模组 = function():Void {
    this.commandModules = {};

    // 空手模组
    var bareReg:CommandRegistry = new CommandRegistry(64);
    bareReg.loadConfig(CommandConfig.getBarehanded());
    bareReg.compile();
    this.commandModules["barehand"] = {
        registry: bareReg,
        dfa: bareReg.getDFA()
    };

    // 轻武器模组
    var lightReg:CommandRegistry = new CommandRegistry(64);
    lightReg.loadConfig(CommandConfig.getLightWeapon());
    lightReg.compile();
    this.commandModules["lightWeapon"] = {
        registry: lightReg,
        dfa: lightReg.getDFA()
    };

    // 重武器模组
    var heavyReg:CommandRegistry = new CommandRegistry(64);
    heavyReg.loadConfig(CommandConfig.getHeavyWeapon());
    heavyReg.compile();
    this.commandModules["heavyWeapon"] = {
        registry: heavyReg,
        dfa: heavyReg.getDFA()
    };

    // 输入采样器（共用，保留用于本地调试/兜底）
    this.inputSampler = new InputSampler();

    // 标记 DFA 已构建，D 前缀待发送
    this.dfaBuilt = true;
    this.dfaSentToLauncher = false;
    this.发送DFA数据到Launcher();

    _root.服务器.发布服务器消息("[搓招] 模组构建完成 → Launcher 同步" + (this.dfaSentToLauncher ? "OK" : "等待连接"));
};

/**
 * 初始化搓招输入系统（带 XML 异步加载）
 * 优先尝试从 XML 加载配置，失败则回退到硬编码
 */
_root.帧计时器.初始化输入搓招系统 = function():Void {
    var self = this;
    var runtimeLoader:InputCommandRuntimeConfigLoader = new InputCommandRuntimeConfigLoader(
        "data/config/InputCommandRuntimeConfig.xml"
    );
    runtimeLoader.load(
        function(runtimeConfig:Object):Void {
            var listLoader:InputCommandListXMLLoader = new InputCommandListXMLLoader(
                "data/inputCommand/list.xml"
            );
            listLoader.loadAll(
                function(configs:Object):Void {
                    CommandConfig.setXMLConfigs(configs);
                    self.构建搓招模组();
                },
                function():Void {
                    self.构建搓招模组(); // XML 失败，硬编码 fallback
                }
            );
        },
        function():Void {
            var listLoader:InputCommandListXMLLoader = new InputCommandListXMLLoader(
                "data/inputCommand/list.xml"
            );
            listLoader.loadAll(
                function(configs:Object):Void {
                    CommandConfig.setXMLConfigs(configs);
                    self.构建搓招模组();
                },
                function():Void {
                    self.构建搓招模组(); // 全部失败，硬编码 fallback
                }
            );
        }
    );
};

/**
 * 同步初始化搓招系统（不使用 XML，直接用硬编码）
 * 用于测试环境或需要立即可用的场景
 */
_root.帧计时器.初始化输入搓招系统同步 = function():Void {
    CommandConfig.disableXMLMode();
    this.构建搓招模组();
};

/**
 * 将已编译的 DFA 数据通过 D 前缀发送到 Launcher V8。
 * 可能在以下时机被调用：
 * 1. 构建搓招模组() 完成后（如果 socket 已连接）
 * 2. frameUpdate 中检测到 dfaBuilt 但未发送（socket 延迟连接的情况）
 */
_root.帧计时器.发送DFA数据到Launcher = function():Void {
    if (this.dfaSentToLauncher || !this.dfaBuilt) return;
    var sm:Object = _root.server;
    if (sm == undefined || !sm.isSocketConnected) return;

    var moduleIds:Array = ["barehand", "lightWeapon", "heavyWeapon"];
    var moduleNums:Array = ["0", "1", "2"];
    for (var mi:Number = 0; mi < moduleIds.length; mi++) {
        var mod:Object = this.commandModules[moduleIds[mi]];
        if (mod != undefined && mod.registry != undefined) {
            sm.sendSocketMessage("D" + moduleNums[mi] + "\x01" + mod.registry.serializeForLauncher());
        }
    }
    this.dfaSentToLauncher = true;
};

/**
 * 根据单位的 兵器动作类型 推断对应的搓招模组
 * @param unit 单位对象
 * @return 模组名: "barehand" | "lightWeapon" | "heavyWeapon"
 */
_root.帧计时器.推断动作模组 = function(unit:Object):String {
    var state:String = unit.攻击模式;

    // 空手模式 → barehand（最常见路径，最先判断并立即返回）
    if (state == "空手") {
        return "barehand";
    }

    // 非空手时才计算技能状态
    var isSkillState:Boolean = (state == "技能" || state == "战技");

    // 拳类技能/战技 → barehand
    if (isSkillState && HeroUtil.isFistSkill(unit.技能名)) {
        return "barehand";
    }

    // 兵器模式，或非拳技能/战技 → 根据兵器动作类型轻重划分
    if (state == "兵器" || isSkillState) {
        var actionType:String = unit.兵器动作类型;
        if (actionType == "长柄" || actionType == "长枪" ||
            actionType == "长棍" || actionType == "狂野" ||
            actionType == "重斩" || actionType == "镰刀") {
            return "heavyWeapon";
        }
        return "lightWeapon";
    }

};

// 调用搓招系统初始化（异步加载 XML）
_root.帧计时器.初始化输入搓招系统();

_root.帧计时器.性能评估优化 = function() {

    // 固化单路径：由 PerformanceScheduler 接管
    this.scheduler.evaluate();
};


_root.帧计时器.scheduler.applyInitialState();

_root.帧计时器.定期异常检查 = function()
{
    if (--this.异常间隔帧数 === 0) 
    {
        var 游戏世界 = _root.gameworld;

        for (var 待选目标 in 游戏世界) 
        {
            var 目标 = 游戏世界[待选目标];
            if(目标.hp > 0)
            {
                目标.异常指标 = 0;
            }
            else if(目标.hp <= 0 and 目标.hp !== undefinded)
            {
                if(++目标.异常指标 > 2)
                {
                    if(++目标.移除指标 > 2)
                    {
                        目标.removeMovieClip();
                        _root.发布消息("remove " + 目标);
                    }
                    else if(目标.异常指标 === 3)
                    {
                        目标.死亡检测();
                        _root.发布消息("kill " + 目标);
                    }
                }
            }

        }   
        _root.服务器.发布服务器消息("正在检查异常");
        this.异常间隔帧数 = this.帧率 * 5;
    }
};

_root.帧计时器.定期更新天气 = function()
{
    var gameWorld:MovieClip = _root.gameworld;
    if(!gameWorld) return;
    if (--this.天气待更新时间 === 0 || !gameWorld.已更新天气) 
    {
        this.eventBus.publish("WeatherUpdated");
        if(!gameWorld.已更新天气){            
            gameWorld.已更新天气 = true;//保证换场景可切换
            _global.ASSetPropFlags(gameWorld, ["已更新天气"], 1, true);

            // 清理缓存，避免循环引用

            Delegate.clearCache();
            Dictionary.destroyStatic();
            // _root.服务器.发布服务器消息("SceneChanged")
        }
        
        this.天气待更新时间 = this.更新天气间隔 * (1 + this.scheduler.getPerformanceLevel());

    }
};



_root.帧计时器.键盘输入控制目标 = function()
{
    var 控制对象 = TargetCacheManager.findHero()
    if(!控制对象) {
        org.flashNight.arki.scene.StageRunSession.observeInputState(null, -1);
        return;
    }

    if(_root.暂停){
        // 清空所有状态
        控制对象.左行 = false;
        控制对象.右行 = false;
        控制对象.上行 = false;
        控制对象.下行 = false;
        控制对象.动作A = false;
        控制对象.动作B = false;
        控制对象.动作C = false;
        控制对象.强制奔跑 = false;
        // 暂停时重置搓招状态
        控制对象.commandId = 0;
        控制对象.当前搓招ID = 0;
        控制对象.当前搓招名 = "";
    }else{
        // 使用位掩码存储按键状态
        var mask:Number =
            (Key.isDown(控制对象.左键) ? 1 : 0) |
            (Key.isDown(控制对象.右键) ? 2 : 0) |
            (Key.isDown(控制对象.上键) ? 4 : 0) |
            (Key.isDown(控制对象.下键) ? 8 : 0) |
            (Key.isDown(控制对象.A键) ? 16 : 0) |
            (Key.isDown(控制对象.B键) ? 32 : 0) |
            (Key.isDown(控制对象.C键) ? 64 : 0) |
            (Key.isDown(_root.奔跑键) ? 128 : 0); 

        // 解码位掩码更新控制对象状态
        控制对象.左行 = (mask & 1) != 0;
        控制对象.右行 = (mask & 2) != 0;
        控制对象.上行 = (mask & 4) != 0;
        控制对象.下行 = (mask & 8) != 0;
        控制对象.动作A = (mask & 16) != 0;
        控制对象.动作B = (mask & 32) != 0;
        控制对象.动作C = (mask & 64) != 0;
        // Shift 奔跑 与 双击方向奔跑 合并判定
        // - actionsPressed：按下任一 A/B/C 则不允许进入奔跑
        // - shiftRun：按住“奔跑键”（默认 Shift）时触发
        // - doubleRun：UI 层通过 KeyManager 订阅双击左右键后设置的方向意图
        //              ctrl.doubleTapRunDirection = -1（左）/ 1（右），松开方向键自动清零
        var actionsPressed:Boolean = (mask & (16 | 32 | 64)) != 0;
        var shiftRun:Boolean = !actionsPressed && ((mask & 128) != 0);

        var doubleRun:Boolean = false;
        var dir:Number = 控制对象.doubleTapRunDirection;
        if (dir) {  // dir 为 null/undefined/0 时都为 false
            var leftPressed:Boolean = (mask & 1) != 0;
            var rightPressed:Boolean = (mask & 2) != 0;
            doubleRun = !actionsPressed && ((dir < 0 && leftPressed) || (dir > 0 && rightPressed));
            // 若水平方向均未按下，则清除双击奔跑方向
            if (!leftPressed && !rightPressed) {
                控制对象.doubleTapRunDirection = 0;
            }
        }

        控制对象.强制奔跑 = shiftRun || doubleRun;

        // === \x04 数据发送：mask + 朝向 + 模组 + 双击方向 → Launcher V8 ===
        var 模组名:String = this.推断动作模组(控制对象);
        var facingBit:Number = (控制对象.方向 == "右") ? 1 : 0;
        var moduleId:Number = (模组名 == "barehand") ? 0 : ((模组名 == "heavyWeapon") ? 2 : 1);
        var dtDir:Number = 控制对象.doubleTapRunDirection;
        if (dtDir == undefined) dtDir = 0;
        FrameBroadcaster.setInputPayload(mask + "|" + facingBit + "|" + moduleId + "|" + dtDir);

        // === 搓招缓冲（输入源：Launcher K 前缀 cmdId，替代本地 DFA）===
        var frame:Number = this.当前帧数;
        var launcherCmdId:Number = FrameBroadcaster.getCmdId();

        // 模组切换时清空缓冲
        if (控制对象.当前搓招模组 != 模组名) {
            控制对象.搓招缓冲ID = 0;
            控制对象.搓招缓冲名 = "";
            控制对象.搓招缓冲已消费 = true;
        }
        控制对象.当前搓招模组 = 模组名;

        // Launcher DFA 命中时写入缓冲（同时缓存名字，因为下一帧 K 会清空 _cmdName）
        if (launcherCmdId != 0) {
            控制对象.搓招缓冲ID = launcherCmdId;
            控制对象.搓招缓冲名 = FrameBroadcaster.getCmdName();
            控制对象.搓招缓冲帧 = frame;
            控制对象.搓招缓冲已消费 = false;
        }

        // 根据宽容帧数决定当前帧是否有有效搓招（tolerance +1 补偿通信延迟）
        var tolerance:Number = InputCommandRuntimeConfigLoader.bufferTolerance + 1;
        var active:Boolean = false;

        if (控制对象.搓招缓冲ID != 0 &&
            !控制对象.搓招缓冲已消费 &&
            frame - 控制对象.搓招缓冲帧 <= tolerance) {
            active = true;
        }

        if (active) {
            控制对象.当前搓招ID = 控制对象.搓招缓冲ID;
            控制对象.当前搓招名 = 控制对象.搓招缓冲名;
        } else {
            控制对象.当前搓招ID = 0;
            控制对象.当前搓招名 = "";
            if (控制对象.搓招缓冲ID != 0 && frame - 控制对象.搓招缓冲帧 > tolerance) {
                控制对象.搓招缓冲ID = 0;
            }
        }

        // 搓招识别日志已迁移到 WebView2 combo overlay，默认不刷屏
        // 如需调试可取消注释:
        // if(控制对象.当前搓招名 !== "" && frame == 控制对象.搓招缓冲帧){
        //     _root.发布消息(_root.帧计时器.当前帧数 + ":模组=" + 模组名 + " 搓招=" + 控制对象.当前搓招名 + " [Launcher DFA]");
        // }
    }

    org.flashNight.arki.scene.StageRunSession.observeInputState(控制对象, _root.暂停 ? 0 : mask);

    // 武器技能键由 AS2 输入服务统一持有按住锁存与释放编排。
    // 即使暂停也必须采样松键，让已消费的本次按住能够重新武装；是否允许触发由服务内部判定。
    var 武器技能输入控制器:Object = _root.武器技能输入控制器;
    if (武器技能输入控制器 && 武器技能输入控制器.update) {
        武器技能输入控制器.update(控制对象, Key.isDown(_root.武器技能键));
    }

    // 12 槽快捷技能由 AS2 输入服务统一采样与编排。暂停期间仍逐帧更新，确保松键能重新武装。
    var 快捷技能输入控制器:Object = _root.快捷技能输入控制器;
    if (快捷技能输入控制器 && 快捷技能输入控制器.update) {
        快捷技能输入控制器.update(控制对象);
    }

    // 四槽快捷药剂由 AS2 输入服务读取权威库存并编排消耗；旧 XFL 控制器只显示键位。
    var 药剂输入控制器:Object = _root.药剂输入控制器;
    if (药剂输入控制器 && 药剂输入控制器.update) {
        药剂输入控制器.update(控制对象);
    }
};




// 定义按键事件
// _root.帧计时器.onKeyDown = _root.帧计时器.onKeyUp = _root.帧计时器.键盘输入控制目标;

// 注册监听器
// Key.addListener(_root.帧计时器);

_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    this.性能评估优化();
    this.定期更新天气();
    // D 前缀重试：DFA 已构建但 socket 当时未连接，等连接后自动发送
    if (this.dfaBuilt && !this.dfaSentToLauncher) {
        this.发送DFA数据到Launcher();
    }
    this.键盘输入控制目标();
    this.当前帧数 = this.server.currentFrame;
    // _root.发布消息(System.IME.getEnabled())
}, _root.帧计时器);

_root.帧计时器.eventBus.subscribe("frameUpdate", function() {
    _root.显示列表.播放列表();
}, _root.帧计时器);


// ---------------------------------------------------
// 以下为对外公开的任务调度方法，均为包装 TaskManager 方法
// ---------------------------------------------------

// 【添加任务】（通用版：可指定执行次数或无限循环）
_root.帧计时器.添加任务 = function(action:Function, interval:Number, repeatCount):String {
    // 提取额外动态参数
    var parameters:Array = (arguments.length > 3) ? ArgumentsUtil.sliceArgs(arguments, 3) : [];
    return this.taskManager.addTask(action, interval, repeatCount, parameters);
};

// 【添加单次任务】（间隔 <= 0 时直接执行，返回 null）
_root.帧计时器.添加单次任务 = function(action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 2) ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    return this.taskManager.addSingleTask(action, interval, parameters);
};

// 【添加循环任务】（无限重复执行）
_root.帧计时器.添加循环任务 = function(action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 2) ? ArgumentsUtil.sliceArgs(arguments, 2) : [];
    return this.taskManager.addLoopTask(action, interval, parameters);
};

// 【添加或更新任务】（相同对象+标签，只会存在一个任务）
_root.帧计时器.添加或更新任务 = function(obj:Object, labelName:String, action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 4) ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    return this.taskManager.addOrUpdateTask(obj, labelName, action, interval, parameters);
};

// 【添加生命周期任务】（无限循环，并绑定对象卸载时的清理回调）
_root.帧计时器.添加生命周期任务 = function(obj:Object, labelName:String, action:Function, interval:Number):String {
    var parameters:Array = (arguments.length > 4) ? ArgumentsUtil.sliceArgs(arguments, 4) : [];
    return this.taskManager.addLifecycleTask(obj, labelName, action, interval, parameters);
};

// 【移除任务】（根据任务ID删除任务，内部会通知 ScheduleTimer 移除）
_root.帧计时器.移除任务 = function(taskID:Number):Void {
    this.taskManager.removeTask(taskID);
};

// 【移除生命周期任务】[NEW v1.6]（通过 obj + labelName 移除生命周期任务）
// 适用于不跟踪 taskID 的场景，会同时清理 obj.taskLabel[labelName]
_root.帧计时器.移除生命周期任务 = function(obj:Object, labelName:String):Boolean {
    return this.taskManager.removeLifecycleTask(obj, labelName);
};

// 【定位任务】（根据任务ID获取 Task 对象，用于检查或后续操作）
_root.帧计时器.定位任务 = function(taskID:Number):Task {
    return this.taskManager.locateTask(taskID);
};

// 【延迟执行任务】（给已有任务延迟一段时间后执行）
_root.帧计时器.延迟执行任务 = function(taskID:Number, delayTime):Boolean {
    return this.taskManager.delayTask(taskID, delayTime);
};


_root.帧计时器.添加冷却任务 = function(delay:Number, callback:Function):Void {
    this.cooldownWheel.add(delay, callback);
};



EventBus.getInstance().subscribe("SceneChanged", StaticInitializer.onSceneChanged, StaticInitializer); 

_root.帧计时器.获取敌人缓存 = Delegate.create(TargetCacheManager, TargetCacheManager.getCachedEnemy);
_root.帧计时器.获取友军缓存 = Delegate.create(TargetCacheManager, TargetCacheManager.getCachedAlly);

_root.帧计时器.添加主动战技cd = function(动作, 间隔时间){
    return _root.帧计时器.添加单次任务(动作, 间隔时间); // 返回任务ID
};


_root.帧计时器.eventBus.subscribe("SceneChanged", SceneCoordinateManager.update
, SceneCoordinateManager); 

_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
    // 换场递增观察 epoch 并重放当前表现目标，不做前馈调档。
    _root.帧计时器.scheduler.onSceneChanged();

    System.IME.setEnabled(false);
    _root.关卡结束界面._visible = false;
    // 清空打击数字批处理队列，避免跨场景残留
    HitNumberBatchProcessor.clear();
    // 重置 FrameBroadcaster 数据槽，防止跨场景残留的 hn 数据被发送
    FrameBroadcaster.reset();
    // 通知 C# 清除活跃伤害数字动画（S2 修复：场景切换时同步 reset）
    // 快车道前缀 "R" 绕过 MessageRouter JSON 路由，直达 FrameTask.HandleReset()
    // 注意：_root.server = ServerManager 单例，_root.服务器 = 兼容代理（无 socket 属性）
    if (_root.server.isSocketConnected) {
        _root.server.sendSocketMessage("R");
    }
    // 重置射线视觉效果管理器，清理跨场景残留的射线
    RayVfxManager.reset();
    // Plan A: 在 deactivateAll 失活轮子前同步落盘 SaveManager pending save。
    // **无条件 flushNow**：unconditional 是 audit 漏标 mutator 的 safety net——
    // 即使 audit 漏掉某 mutator 没设 dirtyMark，本 hook 也会保存当前 mydata，
    // 数据不丢。代价：每次场景切换 1 次落盘（与 baseline 淡出 unconditional 相同）。
    // R1 步骤 11：内核换 flushDurableNow("scene.changed_safety_net")，只换调用目标。
    // 冻结项：仍无条件（不加 dirty 守卫）、仍严格位于 deactivateAll() 之前；
    // 它不是 transition API（scene change 已发生），故不得改用 flushBeforeTransition。
    SaveManager.getInstance().flushDurableNow("scene.changed_safety_net");
    // 失活上一场景遗留的射击/特效循环任务，避免绑定已销毁单位的"孤儿循环"跨场景累积。
    // 用 deactivateAll 而非 reset：不误伤与之共享底层 CooldownWheel 的 UI 冷却等任务。
    EnhancedCooldownWheel.I().deactivateAll();
    // 重置 TimSort 重入保护标志，防止 compare 异常后永久降级为 Array.sort()
    org.flashNight.naki.Sort.TimSort.resetState();
    // 运行时任务清理完成后，通知需要重建全局循环/对象池的子系统。
    _root.帧计时器.eventBus.publish("SceneRuntimeReset");
}, null);


_root.帧计时器.添加循环任务(BulletFactory.resetCount, 1000 * 60 * 5); // 每5分钟重置一次子弹深度计数

// 保存 stageWatcher 到 _root.帧计时器 以便在 cleanupForRestart 时移除
_root.帧计时器.stageWatcher = {};

_root.帧计时器.stageWatcher.onFullScreen = function(nowFull:Boolean):Void {
    EventBus.getInstance().publish("FlashFullScreenChanged", nowFull);
};
_root.帧计时器.stageWatcher.onResize = function():Void {
    // 记录舞台大小变化
    _root.发布消息("Flash 大小状态变更: ", Stage.width, Stage.height);
};
Stage.addListener(_root.帧计时器.stageWatcher);

EventBus.getInstance().subscribe("SceneChanged", function() {
    /*
    // ══════════════════════════════════════════════════════════════════════════════
    // 刀口数量自动化检测脚本（仅执行一次）
    // 任务：遍历所有刀类武器，检测刀口数量并输出到服务器消息
    // ══════════════════════════════════════════════════════════════════════════════
    if (!_root.刀口检测已完成) {
        _root.刀口检测已完成 = true;

        var ItemUtil = org.flashNight.arki.item.ItemUtil;
        var MeleeStatsBuilder = org.flashNight.gesh.tooltip.builder.MeleeStatsBuilder;

        var itemDataDict:Object = ItemUtil.itemDataDict;
        var meleeWeapons:Array = [];
        var results:Array = [];

        // 第一步：收集所有刀类武器
        // 注意：dressup 在 itemData.data 内部，不在顶层
        for (var itemName:String in itemDataDict) {
            var itemData:Object = itemDataDict[itemName];
            if (itemData.use === "刀") {
                var dressup:String = (itemData.data && itemData.data.dressup) ? itemData.data.dressup : null;
                meleeWeapons.push({
                    name: itemName,
                    icon: itemData.icon,
                    dressup: dressup
                });
            }
        }

        _root.服务器.发布服务器消息("=== 刀口数量检测开始 ===");
        _root.服务器.发布服务器消息("共发现 " + meleeWeapons.length + " 把刀类武器");

        // 第二步：逐个检测刀口数量
        for (var i:Number = 0; i < meleeWeapons.length; i++) {
            var weapon:Object = meleeWeapons[i];
            var bladeCount:Number = MeleeStatsBuilder.getBladeCount(weapon.dressup, weapon.icon);

            results.push({
                name: weapon.name,
                icon: weapon.icon,
                dressup: weapon.dressup,
                bladeCount: bladeCount
            });

            // 输出检测结果
            var dressupInfo:String = weapon.dressup ? weapon.dressup : "(无)";
            _root.服务器.发布服务器消息(
                "[" + (i + 1) + "/" + meleeWeapons.length + "] " +
                weapon.name + " | 刀口数: " + bladeCount +
                " | dressup: " + dressupInfo +
                " | icon: " + weapon.icon
            );
        }

        // 第三步：统计汇总（使用数组，索引即刀口数）
        var countStats:Array = [0, 0, 0, 0, 0, 0, 0]; // 索引 0-6
        for (var j:Number = 0; j < results.length; j++) {
            var bc:Number = results[j].bladeCount;
            if (bc >= 0 && bc <= 6) {
                countStats[bc]++;
            }
        }

        _root.服务器.发布服务器消息("=== 刀口数量统计 ===");
        for (var k:Number = 0; k <= 6; k++) {
            if (countStats[k] > 0) {
                _root.服务器.发布服务器消息("刀口数 " + k + ": " + countStats[k] + " 把");
            }
        }
        _root.服务器.发布服务器消息("=== 刀口数量检测完成 ===");

        // 将结果存储到全局变量，便于后续处理
        _root.刀口检测结果 = results;
    }
    // ══════════════════════════════════════════════════════════════════════════════

    */
    
	// _root.服务器.发布服务器消息("准备清理地图信息")
    _root.gameworld.frameFlag = _root.帧计时器.当前帧数;
	_root.帧计时器.添加或更新任务(_root.gameworld, "ASSetPropFlags", function() {
		var arr:Array = [   "效果", 
							"子弹区域", 
							"已更新天气",
							"动画",
							"背景",
							"地图",
							"出生地",
							"deadbody",
							"允许通行",
                            "frameFlag"
		]

        /*
		_root.服务器.发布服务器消息("开始清理地图信息")

		for(var each in _root.gameworld) {
			_root.服务器.发布服务器消息("key " + each)
		}

		for(var i:Number = 0; i < arr.length; i++) {
			if(_root.gameworld[arr[i]]) {
				_global.ASSetPropFlags(_root.gameworld, [arr[i]], 1, false);
				_root.服务器.发布服务器消息("ASSetPropFlags " + arr[i])
			}
		}

		for(var each in _root.gameworld) {
			_root.服务器.发布服务器消息("key " + each)
		}

        _root.服务器.发布服务器消息("结束清理地图信息");

        */
        _global.ASSetPropFlags(_root.gameworld, arr, 1, false);
	}, 5000)
}, null); // 地图变动时，将需要设置的部件设置成不可枚举以避免进入遍历范围

// ===================================================================
// cleanupForRestart - 游戏重启前的统一清理入口
// 用于 loadMovieNum(..., 0) 重载主 SWF 前清理所有持久状态
// ===================================================================

/**
 * 清理所有持久状态，为游戏重启做准备
 *
 * 调用时机：
 *   - 返回主菜单前
 *   - 重新开始游戏前
 *   - 任何需要 loadMovieNum 重载的场景前
 *
 * 清理顺序按依赖关系排列：
 *   1. StageManager (持有 WaveSpawner, StageEventHandler 引用)
 *   2. StageEventHandler (持有 gameworld.dispatcher 引用)
 *   3. WaveSpawnWheel (持有 WaveSpawner 引用)
 *   4. SceneManager (持有 gameworld MovieClip 引用)
 *   5. WaveSpawner (持有 StageManager, SceneManager, WaveSpawnWheel 引用)
 *   6. Stage/Key 监听器
 *   7. EventBus
 *   8. 音效、keyPollMC、_global 变量等
 */
_root.cleanupForRestart = function():Boolean {
    _root.发布消息("[cleanupForRestart] 开始清理持久状态...");

    // 任何 manager 开始 dispose 前先完成 transient loot 权威收敛；失败时保持
    // 整个运行时原样，禁止形成“前半已清、SceneManager 被 pending 挡住”的半清理。
    var lootExpiry:Object = org.flashNight.arki.item.LootContainerService.expireScene(
        "scene_cleanup");
    if (lootExpiry == null || lootExpiry.success !== true) {
        _root.发布消息("[cleanupForRestart] 战利品权威尚未收敛，重启清理已阻塞");
        return false;
    }

    // -------------------------
    // 1. 清理 StageManager (关卡管理器)
    // -------------------------
    if (StageManager.instance != null) {
        StageManager.instance.dispose();
        _root.发布消息("[cleanupForRestart] StageManager disposed");
    }

    // -------------------------
    // 2. 清理 StageEventHandler (关卡事件处理器)
    // -------------------------
    if (StageEventHandler.instance != null) {
        StageEventHandler.instance.dispose();
        _root.发布消息("[cleanupForRestart] StageEventHandler disposed");
    }

    // -------------------------
    // 3. 清理 WaveSpawnWheel (刷怪时间轮)
    // -------------------------
    if (WaveSpawnWheel.instance != null) {
        WaveSpawnWheel.instance.dispose();
        _root.发布消息("[cleanupForRestart] WaveSpawnWheel disposed");
    }

    // -------------------------
    // 4. 清理 SceneManager (场景管理器)
    // -------------------------
    if (SceneManager.instance != null) {
        if (!SceneManager.instance.dispose()) {
            _root.发布消息("[cleanupForRestart] 战利品权威尚未收敛，重启清理已阻塞");
            return false;
        }
        _root.发布消息("[cleanupForRestart] SceneManager disposed");
    }

    // -------------------------
    // 5. 清理 WaveSpawner (刷怪器)
    // -------------------------
    if (WaveSpawner.instance != null) {
        WaveSpawner.instance.dispose();
        _root.发布消息("[cleanupForRestart] WaveSpawner disposed");
    }

    // -------------------------
    // 6. 移除 Stage 监听器
    // -------------------------
    if (_root.帧计时器.stageWatcher != null) {
        Stage.removeListener(_root.帧计时器.stageWatcher);
        _root.帧计时器.stageWatcher = null;
        _root.发布消息("[cleanupForRestart] Stage listener removed");
    }

    // -------------------------
    // 7. 清理 EventBus
    // -------------------------
    if (EventBus.instance != null) {
        EventBus.instance.clear();
        _root.发布消息("[cleanupForRestart] EventBus cleared");
    }

    // -------------------------
    // 8. 停止所有音效
    // -------------------------
    stopAllSounds();
    _root.发布消息("[cleanupForRestart] All sounds stopped");

    // -------------------------
    // 9. 移除 keyPollMC (如果存在)
    // -------------------------
    if (_root.keyPollMC != null) {
        _root.keyPollMC.removeMovieClip();
        _root.keyPollMC = null;
        _root.发布消息("[cleanupForRestart] keyPollMC removed");
    }

    // -------------------------
    // 10. 清理 _global 持久变量
    // -------------------------
    if (_global.__HOLO_STRIPE__ != null) {
        // 释放 BitmapData
        if (_global.__HOLO_STRIPE__.dispose != null) {
            _global.__HOLO_STRIPE__.dispose();
        }
        _global.__HOLO_STRIPE__ = null;
        _root.发布消息("[cleanupForRestart] _global.__HOLO_STRIPE__ released");
    }

    // -------------------------
    // 11. 清理 TargetCacheManager
    // -------------------------
    TargetCacheManager.clear();
    _root.发布消息("[cleanupForRestart] TargetCacheManager cleared");

    // -------------------------
    // 11.5 清理 HitNumberBatchProcessor 队列 + FrameBroadcaster 数据槽
    // -------------------------
    HitNumberBatchProcessor.clear();
    FrameBroadcaster.reset();
    _root.发布消息("[cleanupForRestart] HitNumberBatchProcessor + FrameBroadcaster cleared");

    // -------------------------
    // 12. 清理 CooldownWheel 和 UnitUpdateWheel
    // -------------------------
    if (_root.帧计时器.cooldownWheel != null) {
        _root.帧计时器.cooldownWheel.clear();
    }
    if (_root.帧计时器.unitUpdateWheel != null) {
        _root.帧计时器.unitUpdateWheel.clear();
    }

    // -------------------------
    // 13. 清理 TaskManager 和 ScheduleTimer
    // -------------------------
    if (_root.帧计时器.taskManager != null) {
        _root.帧计时器.taskManager.clear();
    }
    if (_root.帧计时器.ScheduleTimer != null) {
        _root.帧计时器.ScheduleTimer.clear();
    }

    _root.发布消息("[cleanupForRestart] 清理完成，可以安全重载");
    return true;
};
