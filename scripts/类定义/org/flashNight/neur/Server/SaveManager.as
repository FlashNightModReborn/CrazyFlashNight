import org.flashNight.neur.Server.ServerManager;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.weather.*;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import LiteJSON;
import JSON;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.arki.key.KeyManager;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
/**
 * SaveManager — 存档系统统一管理器（单例）
 *
 * 职责：
 *   1. 归一化存档数据（tasks/pets/shop 折入 mydata）
 *   2. 单次 flush 替代多模块各自 flush
 *   3. 过渡期 dual-write（顶层 key + mydata 内部），读取优先非空顶层，空壳回退 mydata
 *   4. 版本迁移链（undefined → 2.6 → 2.7 → 3.0）
 *   5. 为后续 Launcher 迁移提供统一接口
 */
class org.flashNight.neur.Server.SaveManager {

    /**
     * ============================================================
     * 性能演进路线图（Plan A 已落地 / Plan B / Plan C）
     * ============================================================
     *
     * [Plan A] saveAll 尾防抖 + SceneChanged flushNow + 淡出守卫 + dirtyMark
     *   audit 补全（已落地）
     *   - 见 saveAll / flushNow / _doSaveAll
     *   - SceneChanged hook 在 通信_fs_帧计时器.as deactivateAll 之前**无条件**
     *     调用 flushNow，消除 deactivateAll 静默杀 token 风险；同时是 audit
     *     漏标的 safety net
     *   - 淡出动画 frame 16 改为 dirtyMark 守卫；SceneChanged hook 已 flush，
     *     淡出 frame 16 到达时 dirty=false 跳过
     *   - 关键事件（safeExit/升级×2/商城checkout/商城claim/手动/任务奖励/物品奖励）
     *     走 flushNow
     *   - 21 处 _root.储存数据库存盘 / _root.保存仓库数据 死调用已清
     *   - dirtyMark audit 三列清单见本注释末尾
     *
     * [Plan B] 分块 dirty（待启动）
     *   - 触发条件：存档膨胀到 ≥ 30KB（击杀统计扩展是主膨胀源），或用户反馈
     *     "手动存档卡顿"
     *   - 设计思路：
     *       a) packGameState 拆 sections: character / equipment / inventory /
     *          collection / infrastructure / tasks / pets / shop / killStats / others
     *       b) 每个 section 独立 dirty bit（替换全局 _dirtyMark）
     *       c) _doSaveAll 只重新组包 dirty sections，clean 复用上次产物挂回
     *       d) shadow push 仍 14KB 全量（launcher 端不做增量协议，先扛住）
     *   - 关键 schema 决策点：
     *       * mydata.version 不动（仍 "3.0"）—— 分块是组包路径优化，不改格式
     *       * SO 内仍写完整 mydata，避免 readback 拼接复杂度
     *       * dirty bit 用 Object hash 而非 bitmask（AS2 友好）
     *       * 击杀统计 schema 同期定型（按敌种 / 按关卡 / 按 session 颗粒度选型）
     *
     * [Plan C] 早退守卫 + shopPanelClose 收紧
     *   - 触发条件：监控发现 _dirtyMark=false 时仍走 _doSaveAll 频次 > 30%
     *   - 设计思路：
     *       a) _doSaveAll 头部加 if (!_dirtyMark) return true; 早退
     *       b) shopPanelClose（商城系统_WebView.as:49）从 _root.自动存盘()
     *          改为 if(dirtyMark) 守卫或直接删除（checkout/claim 已 flushNow）
     *       c) 其他 13 处仍 _root.自动存盘() 的非关键 UI 关闭事件可考虑 dirty 守卫
     *
     * [Plan A2 TODO — review 反馈 Medium] 硬退出前 flush 兜底
     *   - 问题：剩余 _root.自动存盘() 路径走 300ms trailing debounce；玩家在
     *     非关键 UI 关闭后立即关进程 / alt+F4 / Launcher 退出 → pending token
     *     未 fire 即被杀 → 比旧同步 自动存盘() 多一个 300ms 丢存窗口
     *   - 当前覆盖：safeExit 已走 flushNow；SceneChanged hook 已 unconditional
     *     flushNow（场景切换路径无窗口）；剩余路径是 同一场景内 UI 关闭后立即退
     *   - 设计思路：
     *       a) launcher 端：OnSocketClosed / OnApplicationExit 前先发
     *          force_flush command 给 Flash，等 ack 后才退出
     *       b) AS2 端：新增 gameCommands["forceFlush"] handler → 调
     *          SaveManager.getInstance().flushNow()
     *       c) 备选方案：把 13 处中能"零间距 lead to 退出"的 UI 关闭逐个改成
     *          flushNow（但难精准识别）
     *   - 优先级：低（场景切换路径已 cover 主用例；剩余仅"同场景内关 UI →
     *     立即退游戏"罕见用例）
     *
     * Plan B + C 实施后，预期 saveAll 单次成本从 14KB+socket 降到 ~2-3KB 平均，
     * FPS 影响应进一步消失。
     * ============================================================
     *
     * [Plan A dirtyMark Audit 三列清单]
     *
     * == 已审计路径（有 dirtyMark setter）==
     *   - scripts/通信/通信_鸡蛋_任务系统.as:135 → 修复错位的任务存档 末尾标脏
     *   - scripts/类定义/.../EnemyKilledEventComponent.as:59 → 击杀统计更新
     *   - scripts/类定义/.../ItemUtil.as:218 / 246 / 254 → moveItem 三态（背包/装备栏/药剂栏迁移）
     *   - NPC 商店、双栏工作台、装备操作已迁入各 Web PanelService 的事务提交路径
     *
     * == 补标路径（Plan A 本轮新增 dirtyMark = true）==
     *   - scripts/类定义/.../ItemUtil.as:516 (acquire return 前)
     *       覆盖 acquire 内 金钱/虚拟币/经验值/技能点数/材料/情报/药剂栏/背包 全部写入
     *   - scripts/通信/通信_鸡蛋_任务系统.as: AddTask / DeleteTask / FinishTask (splice后) /
     *       FinishStage (循环后) / UpdateTaskProgress (id != null 分支末尾)
     *       覆盖 tasks_to_do / tasks_finished / task_chains_progress 运行时变更
     *   - scripts/引擎/引擎_lsy_战宠系统.as: 开宠物格子 末尾
     *       覆盖 宠物领养限制 / 宠物信息 写入
     *   - scripts/引擎/引擎_lsy_等级与经验值.as: 经验值计算 line 148 之后
     *       覆盖 经验值 += 路径（升级路径已 flushNow，不升级路径靠本标脏）
     *   - scripts/类定义/.../PetPanelService.as: handleBuy 末尾
     *       覆盖 金钱 / 虚拟币 / 宠物信息 写入（WebView 宠物购买路径）
     *   - scripts/类定义/.../MercPanelService.as: handleRecruit 末尾
     *       覆盖 金钱 / 虚拟币 / 同伴数据 / 同伴数 / 佣兵是否出战信息 写入
     *   - scripts/类定义/.../MercPanelService.as: handleDeploy 末尾
     *       覆盖 佣兵是否出战信息[mercIndex] toggle 写入（上游 WebView 佣兵迁移引入）
     *   - scripts/逻辑系统分区/商城系统_WebView.as: shopSaveCart 末尾
     *       覆盖 _root.商城购物车 写入；review High 反馈后从原子层 flush 改为
     *       dirtyMark + 自动存盘 debounce（与 checkout/claim 一致性原子写入）
     *   - scripts/逻辑系统分区/商城系统_WebView.as: shopCheckout / shopClaim
     *       删除原 _root.存盘商城已购买物品() / _root.保存购物车() 子层 flush
     *       （子层 SOL 与 mydata 顶层之间的崩溃窗口风险），统一走 _root.强制存盘()
     *       一次性原子写入
     *
     * == 确认无需补标路径（state 改动但有理由）==
     *   - SaveManager 内部所有 newCharacter / loadGameState / migrateAndSync /
     *       restoreFromSnapshot 路径写入：均是 load/init，不算运行时变更，重启会重做
     *   - 引擎_lsy_技能系统.as: _root.更新主角被动技能 line 64 / 70 重建 _root.主角被动技能
     *       理由：_root.主角被动技能 是从 _root.主角技能表 重建的 cache，原 mutator
     *       在调用方（学习技能/启用技能 UI），_root.主角技能表 写入处应已通过物品栏 UI
     *       已由物品栏核心 149 / 230 与“强化与样品栏”1140 / 1415 路径标脏
     *   - 引擎_lsy_技能系统.as line 230-232: _root.主角技能表 init 默认数组（length>0 提前 return 幂等）
     *   - 引擎_lsy_等级与经验值.as line 43 / 64 / 86 / 107: 升级路径 _root.技能点数 +=
     *       理由：升级路径末尾走 _root.强制存盘() = flushNow，已绕过 debounce 立即落盘
     *   - 通信_鸡蛋_任务系统.as 检查任务数据完整性 line 162 / 168: 写 tasks_finished
     *       理由：该函数顶部调 _root.修复错位的任务存档(line 146) 已标脏；为 init/repair 路径
     *
     * == 相邻冗余（Plan §6d 记录但不修复，下一轮 Plan B/C 处理）==
     *   - 经验值计算 内部调 主角是否升级 + 外层调用方又调一次
     *     (单位函数_lsy_敌人模板迁移.as:292, 单位函数_fs_aka_玩家模板迁移.as:1390)
     *     第二次升级 while 已推进无新等级，冗余但非数据风险
     * ============================================================
     */

    // ==================== 单例 ====================
    private static var _instance:SaveManager;

    public static function getInstance():SaveManager {
        if (!_instance) {
            _instance = new SaveManager();
        }
        SaveManager.getInstance = function():SaveManager {
            return _instance;
        };
        return _instance;
    }

    // ==================== 常量 ====================
    public static var LATEST_VERSION:String = "3.0";
    public static var SAVE_KEY:String = "test";

    // ==================== 修复字典常量 ====================
    // 这些常量是 launcher/data/save_repair_dict.json 的同源权威。
    // tools/cf7-save-repair-dict-build/ 在生成 dict 时直接 dump 这些数组字面量。
    // 维护者新增技能/任务链/关卡时，必须同步加到对应数组并 regenerate dict (npm run build)；
    // CI gate 会在 dict 与 AS2 常量不一致时拒绝合入。
    //
    // 解析规则（见 tools/.../as2-constants.ts）：
    //   - 必须是 `public static var <名字>:Array = [` 起始
    //   - 字符串字面量用双引号或单引号；支持 `//` 行注释
    //   - 以 `];` 结束
    //
    // 字段对应：
    //   REPAIR_DICT_SKILLS      → mydata[5][N][0] 技能名
    //   REPAIR_DICT_TASK_CHAINS → mydata.tasks.task_chains_progress 的 key
    //   REPAIR_DICT_STAGES      → mydata.others.物品来源缓存.discoveredStages[N]
    // 与 data/skills/skills.xml <Name> 字段权威同步 (66 项).
    // 修这个数组时同步改 launcher/data/save_repair_dict.json 的 skills 字段.
    public static var REPAIR_DICT_SKILLS:Array = [
        // 空手 / 武术 / 内力
        "拳脚攻击", "拳脚空中连招", "升龙拳", "裂地拳", "内力爆发", "小跳",
        "聚气", "铁布衫", "兴奋剂", "能量盾",
        "兽王崩拳", "虎拳", "组合拳", "日字冲拳", "寸拳", "径庭拳/黑闪",
        "觉醒霸体", "觉醒震地", "觉醒不坏金身", "地震", "震地", "霸体",
        "一瞬千击", "龟派气功", "不卸之力", "旋风腿", "火舞旋风", "踩人",
        "抱腿摔", "背摔",
        // 刀剑
        "刀剑攻击", "刀剑空中连招", "上挑", "下劈",
        "拔刀术", "凶斩", "龙斩", "瞬步斩", "迅斩", "空间斩",
        // 枪械
        "枪械攻击", "移动射击", "枪械师", "轰炸专家", "冲击连携",
        "追猎射击", "翻滚换弹", "战术目镜", "死亡绽放",
        // 特殊 / 主动
        "上帝之杖", "重力井", "重力场", "火力支援", "闪现", "时间停止",
        "气动波", "六连", "扭转乾坤",
        // 通用 (生活技能)
        "独行者", "口才", "铁匠", "逆向", "炼金", "驾驶", "烹饪", "解密"
    ];

    public static var REPAIR_DICT_TASK_CHAINS:Array = [
        "主线", "引导", "支线", "挑战", "废城",
        "彩蛋", "异形", "大学", "后勤", "预览", "铁枪会"
    ];

    public static var REPAIR_DICT_STAGES:Array = [
        // 训练 / 主线
        "A兵团试炼场", "深入禁区", "大学城周边", "废城环线", "贫民窟",
        "地铁站", "郊区", "超市废墟", "第三集结点", "夺取材料",
        // 摇滚公园 / 堕落城
        "摇滚公园", "压制摇滚公园", "摇滚内战", "堕落城下水道入口", "堕落城深处",
        // BOSS / 通缉
        "通缉任务之李小龙coser", "通缉任务之魔女", "通缉任务之尾上世莉架",
        "通缉任务之硬化僵尸", "通缉任务之异形", "挑战Andylaw",
        "铁血乱舞", "菲尼克斯Lv16", "锡蒙利Lv16",
        // 后期
        "密林深处", "密林中央", "AVP", "机器游荡区",
        "黑铁会", "黑铁会总堂", "军阀前线基地", "试验场", "决战之地"
    ];

    // ==================== 状态 ====================
    private var _dirtyMark:Boolean;
    private var _settingsMigrationPending:Boolean;
    private var _drugLoadoutMigrationPending:Boolean;
    private var _drugLoadoutSchemaRejected:Boolean;
    private var _rewardInboxMigrationPending:Boolean;
    private var _rewardInboxSchemaRejected:Boolean;
    private var _drugLoadoutMigrationSlot:String;
    private var _lastSaveHash:String;
    private var _liteJson:LiteJSON;
    private var _jsonParser:JSON;
    private var _prefetchedData:Object;
    private var _prefetchedSlot:String;
    private var _prefetchGen:Number;
    private var _prefetchInFlight:Boolean;

    // ==================== Debounce 状态（saveAll 尾防抖） ====================
    // _dispatchToken: undefined=无挂起；Number=EnhancedCooldownWheel 的 taskId
    private var _dispatchToken;
    private static var DEBOUNCE_MS:Number = 300;
    private var _saveInFlight:Boolean = false; // 重入护栏
    private var _beforeLocalCommitHookForTests:Function = null;
    private var _flushResultOverrideForTests:Object = undefined;
    // 存盘物理量分桶（存盘风暴止血 ADR 2026-09-03 Commit 0）：领域层调用计数
    // 之外的物理真相，防 wrapper 假通过；测试经专用访问器读取，生产只累计。
    private var _savePhysicalStats:Object = null;
    // R1 Slice 4：API 语义分桶（裁决 §5.2）。与 _savePhysicalStats 物理八分桶严格分离：
    // ingress/调度/origin/outcome/lane 只进本桶，物理八分桶名称与含义不变。
    // 生产只累计，测试经专用访问器读深拷贝快照。
    private var _saveApiStats:Object = null;
    // 测试模式有界 trace（裁决 §5.2：apiKind/reasonId/requestBatchId/physicalAttemptId/outcome）。
    // null=未开启（生产零开销）；开启后环形保留最近 64 条。
    private var _saveApiTrace:Array = null;

    // ==================== R1 四层 API：reason 注册表与调度状态 ====================
    // reason 注册表与 tools/save-api-migration/callsites.v1.json 的 reasonId 清单同源：
    // 新增/修改必须同轮更新 manifest 与本表（README「reasonId 冻结性质」），只接受低基数字符串。
    private static var SAVE_REASON_IDS:Array = [
        "safe_exit",
        "reward.supply_delivery", "reward.root_admission", "reward.terminal_ack",
        "reward.resume_pending", "reward.child_bridge", "reward.terminal",
        "reward.quarantine", "reward.pending_persist",
        "asset_tx.commit",
        "item_use.open_commit",
        "loot.claim_batch", "loot.standalone_claim", "loot.settlement_terminal",
        "stage.return_base",
        "scene.changed_safety_net",
        "character_creation.start_tutorial",
        "settings.apply", "settings.save",
        "character_build.finalize",
        "reward_ui.task_panel_close", "reward_ui.item_panel_close", "reward_ui.claim_all_close",
        "manual_save",
        "shop_legacy.close",
        "shop.panel_close", "shop.cart_edit",
        "ui.fade_out", "ui.safe_exit_open_legacy", "ui.taskbar_legacy_close",
        "ui.storage_money_button_close", "ui.storage_money_close", "ui.plastic_surgery_paid",
        "ui.tablet_close", "ui.pet_info_close", "ui.inventory_close", "ui.warehouse_close",
        "ui.warehouse_legacy_close", "ui.inventory_legacy_close", "ui.player_info_inventory_close"
    ];
    // transition barrier 固定 reason allowlist（裁决 §2.2/§3.1：A1/A6/B2）
    private static var TRANSITION_REASON_IDS:Array = [
        "safe_exit", "stage.return_base", "character_creation.start_tutorial"
    ];
    private static var _reasonRegistry:Object = null;
    private static var _transitionReasonAllowlist:Object = null;

    // requestSave 全局单 pending request：所有 reason 合并进同一个 300ms trailing 调度
    private var _pendingSaveOrigin:String = undefined;   // undefined=无 pending；"legacyDebounce"|"request"
    private var _pendingSaveReasons:Object = null;       // 注册 reason 集合（仅诊断合并）
    private var _requestBatchSeq:Number = 0;
    private var _pendingRequestBatchId:Number = 0;

    private static function saveReasonRegistry():Object {
        if (_reasonRegistry == null) {
            _reasonRegistry = {};
            for (var i:Number = 0; i < SAVE_REASON_IDS.length; i++) {
                _reasonRegistry[SAVE_REASON_IDS[i]] = true;
            }
        }
        return _reasonRegistry;
    }

    /** reason 注册表查询：R1 只接受低基数注册 ID，任意动态文本不得进入诊断集合。 */
    public static function isRegisteredSaveReason(reason:String):Boolean {
        return reason != undefined && saveReasonRegistry()[reason] === true;
    }

    /** transition barrier 固定 allowlist 查询（裁决 §2.2：A1/A6/B2 三个 reason）。 */
    public static function isTransitionReasonAllowed(reason:String):Boolean {
        if (_transitionReasonAllowlist == null) {
            _transitionReasonAllowlist = {};
            for (var i:Number = 0; i < TRANSITION_REASON_IDS.length; i++) {
                _transitionReasonAllowlist[TRANSITION_REASON_IDS[i]] = true;
            }
        }
        return reason != undefined && _transitionReasonAllowlist[reason] === true;
    }

    // ── Protocol 2 (launcher 存档决议) ──
    // 握手回调把 _root._launcher* 写入, preload() 一次性消费并转存到实例字段后 delete.
    // preload() 被 asLoader frame 4 + 主FLA frame 63 各调一次, _protocol2Consumed 保证幂等.
    private var _bootstrapSnapshot:Object = undefined;
    private var _bootstrapSnapshotSource:String = undefined;
    private var _skipPrefetch:Boolean = false;
    private var _protocol2Consumed:Boolean = false;
    private var _deferredResolutionAttempted:Boolean = false;
    private var _deferredDecisionSource:String = undefined;
    private var _runtimeSaveLoaded:Boolean = false;

    // ── C2-β: 修复挂起态 ──
    // saveDecision="repairable" 时, preload() 不立即把 snapshot 喂给 _root.mydata,
    // 而是 stash 起来 (作为 forced=true 的兜底), 拉起 _repairPending 让 _root.存档恢复等待中
    // 返回 true, asLoader 在 sendReady 前的 gate (asLoader.xml line 198) 会一直 yield.
    // BootstrapPanel 修复卡片走完后 launcher 推 task=repair_resolved, applyRepairResolved
    // 落地清洁 snapshot + 清 _repairPending, 帧循环下一个 tick 即放行 sendReady → 正常进游戏.
    private var _repairPending:Boolean = false;

    // ── C4: AS2 兜底 fffd 扫描 (loadAll 末尾) ──
    //   - C1a/C2-α 是「漏洞修了 + 启动时自动洗存档」的双保险, C4 是再加一层 paranoid:
    //     若仍因任何残留路径让 mydata 进游戏时还含 fffd, 至少给玩家 toast + launcher 留 log.
    //   - 单 session 最多跑一次 (避免每次 loadAll 都扫); 单次最多 20ms 时间预算, 超了退化为采样.
    private static var C4_SCAN_BUDGET_MS:Number = 20;
    private static var C4_MAX_PATHS_REPORTED:Number = 16;
    private var _c4Scanned:Boolean = false;
    private var _c4WarnedOnce:Boolean = false;

    // ==================== 构造 ====================
    private function SaveManager() {
        _dirtyMark = false;
        _settingsMigrationPending = false;
        _drugLoadoutMigrationPending = false;
        _drugLoadoutSchemaRejected = false;
        _rewardInboxMigrationPending = false;
        _rewardInboxSchemaRejected = false;
        _drugLoadoutMigrationSlot = undefined;
        _lastSaveHash = "";
        _liteJson = new LiteJSON();
        _jsonParser = new JSON(false);
        _prefetchGen = 0;
        _prefetchInFlight = false;
    }

    // ==================== killStats 子结构维护 ====================
    // 击杀统计对象除 total / byType 外还要承载 dropPRD（伪随机分布失败计数表）。
    // 每次 _root.killStats 被替换（newCharacter / loadGameState / deleteSlot）后必须
    // 调用本方法补齐子字段，并把新 dropPRD 引用重新挂回 _root.dropPRDEngine。
    // 注：本方法不创建 killStats 本身，调用方需保证 _root.killStats 已存在。
    private static function rebindKillStatsExtensions():Void {
        if (_root.killStats == null) return;
        if (_root.killStats.dropPRD == undefined) {
            _root.killStats.dropPRD = {};
        }
        if (_root.dropPRDEngine != undefined) {
            _root.dropPRDEngine.attachState(_root.killStats.dropPRD);
        }
    }

    // ==================== 测试专用 ====================
    // 仅供 BootstrapProtocolTest 使用。因为 SaveManager 是全局单例，正常运行
    // 期 _protocol2Consumed 单向拉起后 preload 不再响应决议；测试需要复位状态
    // 才能跑完 snapshot / deleted / empty / corrupt / needs_migration 五条分支。
    // 产品代码不得调用。
    public function _resetProtocol2ForTest():Void {
        _bootstrapSnapshot = undefined;
        _bootstrapSnapshotSource = undefined;
        _skipPrefetch = false;
        _protocol2Consumed = false;
        _deferredResolutionAttempted = false;
        _deferredDecisionSource = undefined;
        _runtimeSaveLoaded = false;
        _root._saveRuntimeLoaded = false;
        _root._saveRuntimeLoadedAttemptId = undefined;
        _prefetchedData = undefined;
        _prefetchedSlot = undefined;
        _prefetchGen++;
        _prefetchInFlight = false;
        _repairPending = false;
        _c4Scanned = false;
        _c4WarnedOnce = false;
        _drugLoadoutMigrationPending = false;
        _drugLoadoutSchemaRejected = false;
        _rewardInboxMigrationPending = false;
        _rewardInboxSchemaRejected = false;
        _drugLoadoutMigrationSlot = undefined;
    }

    /**
     * 存盘边界测试夹具：生产代码不得调用。
     * saveInFlight 用于覆盖重入拒绝，beforeLocalCommit 用于在 SharedObject.flush 前注入异常。
     * flushResult 用于覆盖 SharedObject.flush 的 false / pending 结果；undefined 恢复真实 flush。
     * 仅改写 config 显式携带的字段，便于测试观察 finally 是否自行复位 in-flight。
     */
    public function _configureSaveFlowForTest(config:Object):Void {
        if (config == null) return;
        if (config.hasOwnProperty("saveInFlight")) {
            _saveInFlight = (config.saveInFlight === true);
        }
        if (config.hasOwnProperty("beforeLocalCommit")) {
            _beforeLocalCommitHookForTests =
                (typeof config.beforeLocalCommit == "function")
                ? config.beforeLocalCommit
                : null;
        }
        if (config.hasOwnProperty("flushResult")) {
            _flushResultOverrideForTests = config.flushResult;
        }
        if (config.resetDirty === true) {
            _dirtyMark = false;
        }
        if (config.resetScheduler === true) {
            if (_dispatchToken != undefined) {
                EnhancedCooldownWheel.I().removeTask(_dispatchToken);
                _dispatchToken = undefined;
            }
            _pendingSaveOrigin = undefined;
            _pendingSaveReasons = null;
        }
    }

    /** 存盘 debounce 测试夹具：生产代码不得调用。 */
    public function _triggerDebounceForTest():Void {
        _onDebounceFire();
    }

    /** wheel 边界守卫路径测试夹具：与 timer 实际回调同路径，异常不得逃逸出本方法。 */
    public function _triggerDebounceGuardedForTest():Void {
        _onDebounceFireGuarded();
    }

    /** pending request 诊断查询（R1）：测试专用。 */
    public function _hasPendingSaveRequestForTest():Boolean {
        return _pendingSaveOrigin != undefined;
    }

    /**
     * 忠实模拟 EnhancedCooldownWheel 推进的测试探针：只有活动 token 才触发回调
     * （与生产 timer 同一目标方法）；被吸收/复位的 pending 没有活动 token，本方法
     * 什么都不做。用于"后续推进时间轮不再额外保存"的吸收门。生产代码不得调用。
     */
    public function _advanceDebounceWheelForTest():Void {
        if (_dispatchToken == undefined) return;
        _onDebounceFireGuarded();
    }

    private function savePhysicalStats():Object {
        if (_savePhysicalStats == null) {
            _savePhysicalStats = {packGameState:0, doSaveAll:0,
                flushAttempt:0, flushSuccess:0, flushPending:0, flushFalse:0,
                jsonStringify:0, shadowDispatch:0};
        }
        return _savePhysicalStats;
    }

    public function _getSavePhysicalStatsForTest():Object {
        var stats:Object = savePhysicalStats();
        return {packGameState:Number(stats.packGameState),
            doSaveAll:Number(stats.doSaveAll),
            flushAttempt:Number(stats.flushAttempt),
            flushSuccess:Number(stats.flushSuccess),
            flushPending:Number(stats.flushPending),
            flushFalse:Number(stats.flushFalse),
            jsonStringify:Number(stats.jsonStringify),
            shadowDispatch:Number(stats.shadowDispatch)};
    }

    public function _resetSavePhysicalStatsForTest():Void {
        _savePhysicalStats = null;
    }

    private function saveApiStats():Object {
        if (_saveApiStats == null) {
            _saveApiStats = {
                ingress: {legacySaveAll:0, legacyFlushNow:0, markDirty:0,
                    requestSave:0, flushDurableNow:0, flushBeforeTransition:0},
                request: {requestScheduled:0, requestCoalesced:0, requestFired:0,
                    requestAbsorbedByFence:0, requestRearmedInFlight:0,
                    requestRejectedDisabled:0},
                fullOrigin: {fullFromLegacyDebounce:0, fullFromRequest:0,
                    fullFromLegacyStrict:0, fullFromDurable:0, fullFromTransition:0},
                strict: {
                    legacy: newStrictOutcomeStats(),
                    durable: newStrictOutcomeStats(),
                    transition: newStrictOutcomeStats()
                },
                flushLane: {
                    full: newFlushLaneStats(),
                    shop_partial: newFlushLaneStats(),
                    delete_tombstone: newFlushLaneStats(),
                    preload_tombstone: newFlushLaneStats(),
                    read_migration: newFlushLaneStats()
                },
                reasons: {},
                reasonUnregistered: 0
            };
            // reason 只接受注册 ID：预置全部注册键为 0，任意动态文本永远不会成为 key。
            var registry:Object = saveReasonRegistry();
            for (var reasonId:String in registry) {
                _saveApiStats.reasons[reasonId] = 0;
            }
        }
        return _saveApiStats;
    }

    private static function newStrictOutcomeStats():Object {
        // AS2 编译器不接受保留字作对象字面量键（即使加引号），一律括号赋值
        var stats:Object = {success:0, pending:0, earlyReject:0};
        stats["false"] = 0;
        stats["throw"] = 0;
        return stats;
    }

    private static function newFlushLaneStats():Object {
        var stats:Object = {attempt:0, success:0, pending:0};
        stats["false"] = 0;
        return stats;
    }

    private static function copyBucketTree(node:Object):Object {
        if (node == null || typeof node != "object") return node;
        var copy:Object = {};
        for (var key:String in node) {
            var value:Object = node[key];
            copy[key] = (value != null && typeof value == "object") ? copyBucketTree(value) : value;
        }
        return copy;
    }

    /**
     * R1 Slice 4 测试访问器：返回 _saveApiStats 深拷贝快照与 pending 诊断，
     * 调用方改写快照不影响内部累计。生产代码不得调用。
     */
    public function _getSaveApiStatsForTest():Object {
        var snapshot:Object = copyBucketTree(saveApiStats());
        snapshot.pendingOrigin = _pendingSaveOrigin;
        snapshot.pendingRequestBatchId = _pendingRequestBatchId;
        var pendingReasons:Array = [];
        if (_pendingSaveReasons != null) {
            for (var reasonId:String in _pendingSaveReasons) {
                pendingReasons.push(reasonId);
            }
        }
        pendingReasons.sort();
        snapshot.pendingReasons = pendingReasons;
        return snapshot;
    }

    public function _resetSaveApiStatsForTest():Void {
        _saveApiStats = null;
    }

    /** 测试模式有界 trace：开启即清空；生产保持 null 零开销。 */
    public function _enableSaveApiTraceForTest():Void {
        _saveApiTrace = [];
    }

    public function _getSaveApiTraceForTest():Array {
        return (_saveApiTrace == null) ? [] : _saveApiTrace.slice();
    }

    private function recordSaveApiTrace(apiKind:String, reasonId:String, outcome:String):Void {
        if (_saveApiTrace == null) return;
        if (_saveApiTrace.length >= 64) _saveApiTrace.shift();
        _saveApiTrace.push({
            apiKind: apiKind,
            reasonId: (reasonId != undefined) ? reasonId : "",
            requestBatchId: _pendingRequestBatchId,
            physicalAttemptId: savePhysicalStats().doSaveAll,
            outcome: outcome
        });
    }

    // ==================== 预取管理 ====================

    public function getPrefetchStatus():Object {
        return { hasPrefetch: (_prefetchedData != undefined), slot: _prefetchedSlot, gen: _prefetchGen };
    }

    public function clearPrefetch():Void {
        _prefetchedData = undefined;
        _prefetchedSlot = undefined;
        _prefetchGen++;
        _prefetchInFlight = false;
    }

    public function receiveSavePush(response:Object):Void {
        var sm:ServerManager = ServerManager.getInstance();
        _prefetchGen++;
        var dataRaw = response.data;

        if (typeof dataRaw != "string") {
            sm.sendServerMessage("[SaveManager] receiveSavePush: data not string, type=" + typeof dataRaw);
            return;
        }

        var parsed:Object = _jsonParser.parse(dataRaw);
        if (_jsonParser.errors.length > 0) {
            sm.sendServerMessage("[SaveManager] receiveSavePush: parse errors=" + _jsonParser.errors.length);
            return;
        }
        if (!validateMydata(parsed)) {
            sm.sendServerMessage("[SaveManager] receiveSavePush: validate failed");
            return;
        }
        _prefetchedData = parsed;
        _prefetchedSlot = String(response.slot);
        sm.sendServerMessage("[SaveManager] receiveSavePush OK slot=" + _prefetchedSlot);
    }

    // ==================== 核心存/读 ====================

    /**
     * Plan A 落点：本方法是 debounce wrapper（300ms trailing edge）。
     * 真正落盘逻辑在 _doSaveAll；同步落盘走 flushNow（关键事件路径 + SceneChanged hook）。
     *
     * Plan B/C 路标：当本方法成为热点 #1 时，请考虑：
     *   (1) 在 _doSaveAll 入口加 `if (!_dirtyMark) return true;` 早退（Plan C）
     *   (2) 把 packGameState() 拆 section + 维护 sectionDirty（Plan B）
     * 禁止在本函数体内做组包/IO，任何"真正落盘"逻辑都应在 _doSaveAll 内。
     */
    public function saveAll():Boolean {
        saveApiStats().ingress.legacySaveAll++;
        if (_root.允许存档 !== true) {
            saveApiStats().request.requestRejectedDisabled++;
            recordSaveApiTrace("legacyDebounce", null, "rejectedDisabled");
            return false;
        }
        _requestSaveCore("legacyDebounce", null);
        return true;
    }

    /**
     * R1 四层 API · 最终请求层：300ms trailing 全局单 timer 合并，返回 Void 刻意
     * 不承诺 durability。不自动标脏；成功全量存盘才清 dirty/latch，失败保留。
     * reason 只接受 SAVE_REASON_IDS 注册表低基数字符串；同一窗口 reason 做集合合并，
     * 仅用于诊断。未注册 reason 不阻断调度（绝不因标签错误丢存盘），仅诊断留痕。
     */
    public function requestSave(reason:String):Void {
        saveApiStats().ingress.requestSave++;
        if (isRegisteredSaveReason(reason)) saveApiStats().reasons[reason]++;
        if (_root.允许存档 !== true) {
            saveApiStats().request.requestRejectedDisabled++;
            recordSaveApiTrace("request", reason, "rejectedDisabled");
            return;
        }
        _requestSaveCore("request", reason);
    }

    /**
     * 调度内核（R1）：saveAll 与 requestSave 分别进入本内核，public 之间严禁级联。
     * 全局单 pending request：重复调用取消旧 timer 重挂（trailing edge），origin 取
     * 本窗口首个调度方，reason 集合跨调用合并，仅作诊断。
     */
    private function _requestSaveCore(origin:String, reason:String):Void {
        // 立即转入实例字段，避免 token 调度期间 mark 被读后清零的 race
        if (_root.存档系统 != undefined && _root.存档系统.dirtyMark) _dirtyMark = true;
        if (origin == "request" && reason != undefined) {
            if (isRegisteredSaveReason(reason)) {
                if (_pendingSaveReasons == null) _pendingSaveReasons = {};
                _pendingSaveReasons[reason] = true;
            } else {
                // 未注册 reason：不拒绝存盘请求，仅诊断留痕（R1 防高基数）
                saveApiStats().reasonUnregistered++;
                ServerManager.getInstance().sendServerMessage(
                    "[SaveManager.requestSave] unregistered reason ignored for diagnostics: " + reason);
            }
        }
        // trailing edge：重复调用取消旧任务、重新调度；origin 保留本窗口首个调度方
        if (_dispatchToken != undefined) {
            saveApiStats().request.requestCoalesced++;
            EnhancedCooldownWheel.I().removeTask(_dispatchToken);
            _dispatchToken = undefined;
            recordSaveApiTrace(origin, reason, "coalesced");
        } else {
            saveApiStats().request.requestScheduled++;
            _pendingSaveOrigin = origin;
            _pendingRequestBatchId = ++_requestBatchSeq;
            recordSaveApiTrace(origin, reason, "scheduled");
        }
        _scheduleDebounceTimer();
    }

    private function _scheduleDebounceTimer():Void {
        _dispatchToken = EnhancedCooldownWheel.I().addDelayedTask(
            DEBOUNCE_MS,
            function():Void {
                // AS2 闭包陷阱规避：每次走 getInstance()，不闭包捕获 sm
                SaveManager.getInstance()._onDebounceFireGuarded();
            }
        );
    }

    /**
     * EnhancedCooldownWheel 契约（EnhancedCooldownWheel.as:232-241）：回调不得抛异常。
     * timer 边界统一由本守卫吞掉异常：sv:3 已在 _onDebounceFire 内部投影，
     * dirty/latch 保留（成功全量存盘才清），这里只做诊断记录，绝不 rethrow 给 wheel。
     */
    private function _onDebounceFireGuarded():Void {
        try {
            _onDebounceFire();
        } catch (saveError) {
            trace("[SaveManager.requestSave] scheduled save failed at wheel boundary: " + saveError);
            try {
                ServerManager.getInstance().sendServerMessage(
                    "[SaveManager.requestSave] scheduled save failed at wheel boundary: " + saveError);
            } catch (logError) {
            }
        }
    }

    private function _onDebounceFire():Void {
        _dispatchToken = undefined;
        if (_saveInFlight) {
            // in-flight 时 request 不得静默丢弃：重挂 pending（origin/reason 集合保留），
            // 下一个 trailing 窗口再触发（R1 Slice 3）。
            _rearmPendingRequest();
            return;
        }
        // 无条件触发（旧契约）：无 pending 的直触（测试夹具/防御路径）按 legacyDebounce
        // 归因；被吸收/复位的 pending 没有活动 token，生产 wheel 不会调到这里。
        // requestFired 只量度真实 pending request 的触发，不量度直触内核。
        var hadPending:Boolean = (_pendingSaveOrigin != undefined);
        var origin:String = hadPending ? _pendingSaveOrigin : "legacyDebounce";
        if (hadPending) {
            saveApiStats().request.requestFired++;
            recordSaveApiTrace(origin, null, "fired");
        }
        _saveInFlight = true;
        try {
            _doSaveAll(origin);
        } catch (saveError) {
            // 后台 saveAll 同样必须结束通用存盘指示；保留异常供既有诊断链处理。
            try {
                FrameBroadcaster.pushUiState("sv:3");
            } catch (uiStateError) {
            }
            throw saveError;
        } finally {
            _saveInFlight = false;
            _pendingSaveOrigin = undefined;
            _pendingSaveReasons = null;
        }
    }

    /**
     * 公开 API：立即同步落盘，绕过 debounce。
     * 关键事件路径（safeExit/升级/手动/商城checkout/商城claim/奖励）调用本入口。
     * SceneChanged hook 也调本入口（保证 pending 在 deactivateAll 前落盘）。
     * R1：本入口保留为 legacy strict，与 flushDurableNow/flushBeforeTransition
     * 分别进入同一私有内核 _strictFlushCore，public 之间严禁级联（防 ingress 双计数）。
     */
    public function flushNow():Boolean {
        saveApiStats().ingress.legacyFlushNow++;
        return _strictFlushCore("legacyStrict", null);
    }

    /**
     * R1 四层 API · durable cut：同步全量落盘。true 仅且仅代表本地
     * SharedObject.flush() === true；不合并 strict 调用、不 debounce、不 dirty 早退，
     * 完全 clean 状态同样全量组包。成功 strict fence 吸收此前 pending request。
     * reason 只接受注册表 ID（未注册仅诊断留痕，绝不因此丢 durable 存盘）。
     */
    public function flushDurableNow(reason:String):Boolean {
        saveApiStats().ingress.flushDurableNow++;
        if (isRegisteredSaveReason(reason)) {
            saveApiStats().reasons[reason]++;
        } else if (reason != undefined) {
            saveApiStats().reasonUnregistered++;
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.flushDurableNow] unregistered reason: " + reason);
        }
        return _strictFlushCore("durable", reason);
    }

    /**
     * R1 四层 API · transition barrier：与 flushDurableNow 同一私有同步落盘内核，
     * 不多一次写盘、不引入不同 dirty 行为；但有独立 ingress 与固定 reason allowlist。
     * reason 不在 TRANSITION_REASON_IDS 内时 fail-closed 返回 false（不发起存盘），
     * 调用方只能在返回 true 后执行 transition；false/"pending"/throw 均不得越过。
     */
    public function flushBeforeTransition(reason:String):Boolean {
        saveApiStats().ingress.flushBeforeTransition++;
        if (isRegisteredSaveReason(reason)) saveApiStats().reasons[reason]++;
        if (!isTransitionReasonAllowed(reason)) {
            // allowlist 拒绝从不到达物理内核：计入 transition 家族 earlyReject
            saveApiStats().strict.transition.earlyReject++;
            if (reason != undefined && !isRegisteredSaveReason(reason)) {
                saveApiStats().reasonUnregistered++;
            }
            recordSaveApiTrace("transition", reason, "earlyReject");
            FrameBroadcaster.pushUiState("sv:1");
            FrameBroadcaster.pushUiState("sv:3");
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.flushBeforeTransition] reason outside transition allowlist, fail-closed: " + reason);
            return false;
        }
        return _strictFlushCore("transition", reason);
    }

    /**
     * 私有同步落盘内核（R1）：三个 strict public 入口共用，可观察时序与原 flushNow
     * 完全兼容——每次同步尝试都先推进到 Saving。否则连续两次早拒绝只会产生相同 sv:3，
     * Host/Web 的状态去重会吞掉第二次失败，令已按“重试”复位的 UI 永久卡在 Saving。
     * 重入/禁用早拒绝不得先删原 pending request token（R1 Slice 3）；
     * 只有成功全量存盘才吸收 pending request。
     */
    private function _strictFlushCore(origin:String, reason:String):Boolean {
        FrameBroadcaster.pushUiState("sv:1");
        // 裁决 §5.2：strict outcome 按 durable/transition/legacy 三家族统计
        var outcomeStats:Object = saveApiStats().strict[(origin == "legacyStrict") ? "legacy" : origin];
        if (_root.允许存档 !== true) {
            FrameBroadcaster.pushUiState("sv:3");
            outcomeStats.earlyReject++;
            recordSaveApiTrace(origin, reason, "earlyReject");
            return false;
        }
        if (_saveInFlight) {
            FrameBroadcaster.pushUiState("sv:3");
            outcomeStats.earlyReject++;
            recordSaveApiTrace(origin, reason, "earlyReject");
            return false;
        }
        _saveInFlight = true;
        var ok:Boolean = false;
        var physicalStats:Object = savePhysicalStats();
        var flushPendingBefore:Number = Number(physicalStats.flushPending);
        var flushFalseBefore:Number = Number(physicalStats.flushFalse);
        try {
            ok = _doSaveAll(origin);
        } catch (saveError) {
            // 生产异常同样不得让安全退出永远停在 Saving；先投影失败，再保留原异常语义。
            try {
                FrameBroadcaster.pushUiState("sv:3");
            } catch (uiStateError) {
            }
            outcomeStats["throw"]++;
            recordSaveApiTrace(origin, reason, "throw");
            throw saveError;
        } finally {
            _saveInFlight = false;
        }
        if (ok) {
            outcomeStats.success++;
            recordSaveApiTrace(origin, reason, "success");
            _absorbPendingRequest();
        } else if (Number(physicalStats.flushPending) > flushPendingBefore) {
            outcomeStats.pending++;
            recordSaveApiTrace(origin, reason, "pending");
        } else if (Number(physicalStats.flushFalse) > flushFalseBefore) {
            outcomeStats["false"]++;
            recordSaveApiTrace(origin, reason, "false");
        } else {
            // _doSaveAll 内部写入门（角色名/等级校验）拒绝：未到达物理 flush
            outcomeStats.earlyReject++;
            recordSaveApiTrace(origin, reason, "earlyReject");
        }
        return ok;
    }

    /**
     * 成功 strict fence 吸收 pending request：取消 timer、清空 origin 与 reason 集合。
     * 只在全量存盘成功后调用；strict 失败/重入拒绝一律保留 pending（失败保留语义）。
     */
    private function _absorbPendingRequest():Void {
        if (_pendingSaveOrigin != undefined) {
            saveApiStats().request.requestAbsorbedByFence++;
            recordSaveApiTrace(_pendingSaveOrigin, null, "absorbedByFence");
        }
        if (_dispatchToken != undefined) {
            EnhancedCooldownWheel.I().removeTask(_dispatchToken);
            _dispatchToken = undefined;
        }
        _pendingSaveOrigin = undefined;
        _pendingSaveReasons = null;
    }

    /**
     * timer 触发遇 _saveInFlight 时重挂 pending request（R1 Slice 3）：
     * 不像旧 _onDebounceFire 一样直接丢弃。无 pending 时不重挂（防御）。
     */
    private function _rearmPendingRequest():Void {
        if (_pendingSaveOrigin == undefined) return;
        saveApiStats().request.requestRearmedInFlight++;
        recordSaveApiTrace(_pendingSaveOrigin, null, "rearmedInFlight");
        _scheduleDebounceTimer();
    }

    // origin ∈ legacyDebounce / request / legacyStrict / durable / transition，
    // 供 R1 Slice 4 full-save origin 分桶；不改变任何物理存盘行为。
    private function _doSaveAll(origin:String):Boolean {
        savePhysicalStats().doSaveAll++;
        // R1 Slice 4 full-save origin 分桶（闭集五桶；未知 origin 只诊断不计数，
        // 测试以 sum(fullOrigin) == doSaveAll 守门）
        var fullOriginStats:Object = saveApiStats().fullOrigin;
        if (origin == "request") fullOriginStats.fullFromRequest++;
        else if (origin == "legacyDebounce") fullOriginStats.fullFromLegacyDebounce++;
        else if (origin == "durable") fullOriginStats.fullFromDurable++;
        else if (origin == "transition") fullOriginStats.fullFromTransition++;
        else if (origin == "legacyStrict") fullOriginStats.fullFromLegacyStrict++;
        else {
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager._doSaveAll] unknown full-save origin: " + origin);
        }
        if (_root.允许存档 !== true) {
            FrameBroadcaster.pushUiState("sv:3");
            return false;
        }

        // 同步外部 dirtyMark
        if (_root.存档系统.dirtyMark) _dirtyMark = true;

        var sm:ServerManager = ServerManager.getInstance();
        sm.sendServerMessage("[SaveManager.saveAll] 角色=" + _root.角色名 + " 等级=" + _root.等级 + " 金钱=" + _root.金钱 + " savePath=" + _root.savePath);
        if (!canWriteCurrentRootState(sm)) {
            FrameBroadcaster.pushUiState("sv:3");
            return false;
        }

        FrameBroadcaster.pushUiState("sv:1");

        // 同步主线任务进度（确保 mydata[3] 与 task_chains_progress 一致）
        if (!isNaN(_root.task_chains_progress.主线)) {
            _root.主线任务进度 = _root.task_chains_progress.主线;
        }

        // 身价校正
        if (_root.身价 < 1000 * _root.等级) {
            _root.身价 = 1000 * _root.等级;
        }

        // 组包
        var mydata:Object = packGameState();
        var so:SharedObject = getSO();
        var soData:Object = so.data;

        // 写入新位置
        soData[SAVE_KEY] = mydata;
        // 清除删档墓碑（如果有）
        delete soData._deleted;

        // dual-write 顶层 key（读取优先层，空壳时允许回退 mydata）
        soData.tasks_to_do = _root.tasks_to_do;
        soData.tasks_finished = _root.tasks_finished;
        soData.task_chains_progress = _root.task_chains_progress;
        soData.战宠 = _root.宠物信息;
        soData.宠物领养限制 = _root.宠物领养限制;
        soData.商城已购买物品 = _root.商城已购买物品;
        soData.商城购物车 = _root.商城购物车;

        // 单次 flush。这里是本地 SharedObject 的唯一提交点；此前异常不得清 dirty。
        if (_beforeLocalCommitHookForTests != null) {
            _beforeLocalCommitHookForTests();
        }
        var ok:Boolean = flushSO(so, "full");
        if (ok) {
            _dirtyMark = false;
            _root.存档系统.dirtyMark = false;
            _root.存盘标志 = 1;
            _settingsMigrationPending = false;
            _drugLoadoutMigrationPending = false;
            _rewardInboxMigrationPending = false;
            KeyManager.clearPendingKeySettingsMigration();
        }

        _root.mydata = mydata;
        try {
            // sv:2 只代表 SharedObject.flush() 已确认成功；false / "pending"
            // 必须投影为失败态，安全退出面板据此禁止 EXIT_CONFIRM。
            FrameBroadcaster.pushUiState(ok ? "sv:2" : "sv:3");
        } catch (uiStateError) {
            reportPostFlushFailure(sm, "ui_state", uiStateError, ok);
        }
        try {
            _root.UpdateTaskProgress();
        } catch (taskProgressError) {
            reportPostFlushFailure(sm, "task_progress", taskProgressError, ok);
        }

        try {
            var _saLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
            sm.sendServerMessage("[SaveManager.saveAll] flush=" + ok + " version=" + mydata.version + " tasks_to_do.len=" + _saLen);
        } catch (saveLogError) {
            reportPostFlushFailure(sm, "save_log", saveLogError, ok);
        }

        // P3a: shadow 推送到 Launcher 落盘 + 回调确认
        try {
            sm.sendServerMessage("[SaveManager] shadow gate: ok=" + ok + " socket=" + sm.isSocketConnected);
        } catch (shadowGateLogError) {
            reportPostFlushFailure(sm, "shadow_gate_log", shadowGateLogError, ok);
        }
        if (ok && sm.isSocketConnected) {
            try {
                pushShadowWithConfirm(sm, mydata);
            } catch (shadowDispatchError) {
                reportPostFlushFailure(sm, "shadow_dispatch", shadowDispatchError, true);
            }
        }

        return ok;
    }

    /**
     * 本地 flush 已有确定结果后，通知/日志/shadow 的异常只能作为独立证据记录，
     * 不得覆盖 SharedObject 的成功或失败裁决。trace 是日志通道自身异常时的兜底。
     */
    private function reportPostFlushFailure(sm:ServerManager, stage:String, error:Object, localCommitted:Boolean):Void {
        var message:String = "[SaveManager.saveAll] post-flush failure stage=" + stage
            + " localCommitted=" + localCommitted + " error=" + error;
        trace(message);
        try {
            sm.sendServerMessage(message);
        } catch (reportError) {
        }
    }

    private function canWriteCurrentRootState(sm:ServerManager):Boolean {
        if (_root.斗兽标定禁存档 === true || _root._agentCalibrationNoSave === true) {
            sm.sendServerMessage("[SaveManager.saveAll] blocked: calibration no-save mode");
            return false;
        }
        if (_root.角色名 == undefined || _root.角色名 == null || String(_root.角色名).length == 0) {
            sm.sendServerMessage("[SaveManager.saveAll] blocked: invalid role name");
            return false;
        }
        if (_root.等级 == undefined || isNaN(Number(_root.等级))) {
            sm.sendServerMessage("[SaveManager.saveAll] blocked: invalid level");
            return false;
        }
        return true;
    }

    private function markRuntimeSaveLoaded(source:String):Void {
        _runtimeSaveLoaded = true;
        _root._saveRuntimeLoaded = true;
        _root._saveRuntimeLoadedAttemptId = _root._bootstrapAttemptId;
        publishRuntimeSaveStatus(true, source, undefined);
    }

    private function publishRuntimeSaveStatus(loaded:Boolean, source:String, reason:String):Void {
        var sm:ServerManager = ServerManager.getInstance();
        var payload:Object = {
            loaded: loaded,
            savePath: _root.savePath,
            attemptId: _root._bootstrapAttemptId,
            source: source,
            role: (_root.角色名 != undefined && _root.角色名 != null) ? String(_root.角色名) : "",
            level: _root.等级,
            reason: reason
        };
        if (sm.isSocketConnected) {
            sm.sendTaskToNode("agent_runtime_status", payload, null);
        }
        sm.sendServerMessage("[SaveManager.runtime] loaded=" + loaded + " source=" + source + " role=" + payload.role + " level=" + payload.level);
    }

    /**
     * Phase 1b hook (10a-1 stub / 10b implementation)：
     * preload 收到 launcher load 响应 error 以 "tombstoned:" 开头时调用本方法，
     * 对齐 SOL 墓碑（_deleted=true）。不变式 3：launcher tombstone 清除的唯一路径仍是 shadow。
     */
    public function handlePreloadTombstoned(slot:String):Void {
        // 不变式 3：launcher tombstone → 对齐 SOL 墓碑，清预取
        // （saveAll → shadow 是 tombstone 唯一安全清除路径；这里不碰 launcher tombstone）
        var safeSlot:String = (slot == undefined || slot.length == 0) ? _root.savePath : slot;
        var so:SharedObject = SharedObject.getLocal(safeSlot);
        if (so != null) {
            so.data._deleted = true;
            try { so.flush(); } catch (e:Error) {}
        }
        _prefetchedData = undefined;
        _prefetchedSlot = undefined;
        _prefetchInFlight = false;
        _prefetchGen++;
    }

    public function preload():Void {
        var sm:ServerManager = ServerManager.getInstance();
        _runtimeSaveLoaded = false;
        _root._saveRuntimeLoaded = false;
        _root._saveRuntimeLoadedAttemptId = undefined;

        // ── 幂等保护: asLoader frame 4 和主FLA frame 63 各调一次 ──
        if (_protocol2Consumed) {
            sm.sendServerMessage("[SaveManager.preload] idempotent skip (protocol 2 already consumed)");
            return;
        }

        // 新槽位从自身 schema 重新判定；同槽位重复 preload 不得覆盖即时 flush
        // 之后仍等待完整存盘的 migration latch。
        var drugMigrationSlot:String = String(_root.savePath);
        if (_drugLoadoutMigrationSlot != drugMigrationSlot) {
            _drugLoadoutMigrationSlot = drugMigrationSlot;
            _drugLoadoutMigrationPending = false;
            _drugLoadoutSchemaRejected = false;
            _rewardInboxMigrationPending = false;
            _rewardInboxSchemaRejected = false;
        }

        sm.sendServerMessage("[SaveManager.preload] savePath=" + _root.savePath);

        // ── Protocol 2 快路径: launcher 存档决议 ──
        var decision:String = _root._launcherSaveDecision;
        if (decision != undefined) {
            var snap:Object = _root._launcherSnapshot;
            var src:String = _root._launcherSnapshotSource;
            var corruptDetail:String = _root._launcherCorruptDetail;
            delete _root._launcherSaveDecision;
            delete _root._launcherSnapshot;
            delete _root._launcherSnapshotSource;
            delete _root._launcherCorruptDetail;

            _protocol2Consumed = true;
            clearPrefetch();
            sm.sendServerMessage("[SaveManager.preload] launcher decision=" + decision + " source=" + src);

            if (decision == "snapshot" && snap != undefined) {
                _root.mydata = snap;
                _bootstrapSnapshot = snap;
                _bootstrapSnapshotSource = (src != undefined) ? src : "unknown";
                return;
            }
            // C2-β: 存档残留 fffd, 进 RepairPending 挂起态等用户在 BootstrapPanel 卡片上做决策.
            // _root.mydata 暂不喂 snapshot — 等 applyRepairResolved 拿到 cleanedSnapshot 再喂.
            // forced=true 路径下没有 cleanedSnapshot, 用本次 stash 的原坏档 (_bootstrapSnapshot).
            if (decision == "repairable") {
                _bootstrapSnapshot = snap;  // 原 (含 fffd) 快照, 留给 forced 路径兜底
                _bootstrapSnapshotSource = (src != undefined) ? src : "unknown";
                _repairPending = true;
                _skipPrefetch = true;       // 不走 launcher 预取 — 避免覆盖 launcher 即将推过来的 cleanedSnapshot
                sm.sendServerMessage("[SaveManager.preload] repairable: pending user decision (source=" + _bootstrapSnapshotSource + ")");
                return;
            }
            if (decision == "deleted") {
                var soDel:SharedObject = getSO();
                soDel.clear();
                soDel.data._deleted = true;
                var flushOk:Boolean = flushSO(soDel, "preload_tombstone");
                if (!flushOk) {
                    sm.sendServerMessage("[SaveManager.preload] tombstone flush FAILED slot=" + _root.savePath);
                }
                _root.mydata = undefined;
                return;
            }
            if (decision == "empty") {
                _root.mydata = undefined;
                return;
            }
            if (decision == "corrupt") {
                sm.sendServerMessage("[SaveManager.preload] corrupt detail=" +
                    (corruptDetail != undefined ? corruptDetail : "unknown"));
                _deferredResolutionAttempted = true;
                _deferredDecisionSource = "corrupt";
                _skipPrefetch = true;
                // 穿透到同步 SOL 读取
            } else if (decision == "needs_migration") {
                sm.sendServerMessage("[SaveManager.preload] needs_migration/defer_to_flash, sync SOL path");
                _deferredResolutionAttempted = true;
                _deferredDecisionSource = "needs_migration";
                _skipPrefetch = true;
                // 穿透到同步 SOL 读取
            }
        }

        // P3a: 异步预取 — 无论 SOL 状态如何，都向 Launcher 请求 JSON 存档
        // 这确保了"本地档坏了还能靠 Launcher 恢复"的场景
        // Protocol 2 needs_migration/corrupt 路径显式跳过 (_skipPrefetch), 消除启动期 async 等待.
        if (_skipPrefetch) {
            _skipPrefetch = false;
        } else {
            _prefetchGen++;
            var currentGen:Number = _prefetchGen;
            var self:SaveManager = this;
            var requestedSlot:String = _root.savePath;
            if (sm.isSocketConnected) {
                _prefetchInFlight = true;
                sm.sendTaskWithCallback("archive", {op:"load", slot:requestedSlot}, null,
                    function(resp:Object):Void {
                        self._prefetchInFlight = false;
                        if (currentGen != self._prefetchGen) return;
                        if (resp.success != true || typeof resp.data != "string") {
                            // launcher 返回 tombstoned → 对齐 SOL 墓碑，避免"本地无墓碑而launcher已删"的状态分叉
                            if (resp.error != null && String(resp.error).indexOf("tombstoned") == 0) {
                                self.handlePreloadTombstoned(requestedSlot);
                            }
                            return;
                        }
                        var parsed:Object = self._jsonParser.parse(resp.data);
                        if (self._jsonParser.errors.length > 0) return;
                        if (!self.validateMydata(parsed)) return;
                        self._prefetchedData = parsed;
                        self._prefetchedSlot = requestedSlot;
                        sm.sendServerMessage("[SaveManager] prefetch OK slot=" + requestedSlot);
                    }
                );
            }
        }

        // SOL 读取
        var so:SharedObject = getSO();
        var raw:Object = so.data[SAVE_KEY];
        if (raw == undefined) {
            sm.sendServerMessage("[SaveManager.preload] 空槽位，mydata=undefined（Launcher 预取可能恢复）");
            _root.mydata = undefined;
            return;
        }
        _root.mydata = raw;

        // 结构校验：主角储存数据必须存在
        if (raw[0] == undefined) {
            sm.sendServerMessage("[SaveManager.preload] 存档结构异常: mydata[0]=undefined，跳过");
            _root.mydata = undefined;
            return;
        }

        sm.sendServerMessage("[SaveManager.preload] version=" + raw.version + " 角色名=" + raw[0][0] + " 等级=" + raw[0][3]);
        sm.sendServerMessage("[SaveManager.preload] 顶层key: tasks_to_do=" + (so.data.tasks_to_do != undefined) + " 战宠=" + (so.data.战宠 != undefined) + " 商城=" + (so.data.商城已购买物品 != undefined));
        sm.sendServerMessage("[SaveManager.preload] mydata内部: tasks=" + (raw.tasks != undefined) + " pets=" + (raw.pets != undefined) + " shop=" + (raw.shop != undefined));
        var changed:Boolean = migrate(_root.mydata, so.data);
        if (_drugLoadoutSchemaRejected) {
            sm.sendServerMessage("[SaveManager.preload] drugLoadout schema rejected");
            _root.mydata = undefined;
            return;
        }
        sm.sendServerMessage("[SaveManager.preload] migrate changed=" + changed + " newVersion=" + _root.mydata.version);
        if (changed) {
            syncTopLevelFromMydata(_root.mydata, so.data);
            if (flushSO(so, "read_migration")) {
                sm.sendServerMessage("[SaveManager.preload] 迁移已持久化");
            }
        }
    }

    public function loadAll():Boolean {
        var sm:ServerManager = ServerManager.getInstance();
        sm.sendServerMessage("[SaveManager.loadAll] savePath=" + _root.savePath);

        // ── Protocol 2: launcher snapshot 快路径 ──
        // snap 已在 preload 经 validator 校验 (launcher C# 侧),
        // 直接喂 loadFromMydata 即可跳过所有 SOL/JSON 合并逻辑.
        if (_bootstrapSnapshot != undefined) {
            var pSnap:Object = _bootstrapSnapshot;
            var pSrc:String = _bootstrapSnapshotSource;
            _bootstrapSnapshot = undefined;
            _bootstrapSnapshotSource = undefined;
            sm.sendServerMessage("[SaveManager.loadAll] using launcher snapshot source=" + pSrc);

            var pOk:Boolean = loadFromMydata(pSnap, "launcher_snapshot:" + pSrc);
            if (pOk) {
                _deferredResolutionAttempted = false;
                _deferredDecisionSource = undefined;
                _prefetchGen++;
                runC4LateScanIfApplicable();  // C4: 兜底扫一次, 残留 fffd 时通知玩家 + launcher
                return true;
            }
            if (_drugLoadoutSchemaRejected) {
                sm.sendServerMessage("[SaveManager.loadAll] launcher snapshot future drugLoadout rejected; fail closed");
                _root._saveRestoreError = true;
                return false;
            }
            // apply 失败 — source-aware 分流
            if (pSrc == "sol") {
                sm.sendServerMessage("[SaveManager.loadAll] sol snapshot apply failed, fallthrough to native SOL path");
                // fallthrough: _root.mydata 已被 preload 设为 snap, 但 snap 已被此处 apply 失败,
                // 下方 SOL 分支会重新赋值 _root.mydata = soData[SAVE_KEY] 并走原路径 migrate.
            } else {
                sm.sendServerMessage("[SaveManager.loadAll] json_shadow snapshot apply failed, restore error");
                _root._saveRestoreError = true;
                return false;
            }
        }

        // P3a: JSON 优先分支
        if (_prefetchedData != undefined) {
            var solMissing:Boolean = (_root.mydata == undefined);
            var solLastSaved:String = solMissing ? undefined : _root.mydata.lastSaved;
            var jsonLastSaved:String = _prefetchedData.lastSaved;

            var useJson:Boolean = false;
            var solDeleted:Boolean = (getSO().data._deleted == true);
            if (sanitizeSlot(_prefetchedSlot) != sanitizeSlot(_root.savePath)) {
                sm.sendServerMessage("[SaveManager.loadAll] slot 不匹配: prefetch=" + _prefetchedSlot + " savePath=" + _root.savePath);
            } else if (solDeleted) {
                // 墓碑存在 → 此槽位被主动删除，不允许 JSON 恢复
                sm.sendServerMessage("[SaveManager.loadAll] 槽位已删除（墓碑），不从 JSON 恢复");
            } else if (solMissing) {
                // SOL 完全缺失且无墓碑 → JSON 是唯一恢复源
                sm.sendServerMessage("[SaveManager.loadAll] SOL 缺失，尝试 JSON 恢复");
                useJson = true;
            } else if (solLastSaved == undefined) {
                // SOL 存在但无时间戳（刚迁移的存档）→ 保守，用 SOL
                sm.sendServerMessage("[SaveManager.loadAll] SOL 无时间戳，保守走 SOL");
            } else if (jsonLastSaved == undefined || jsonLastSaved < solLastSaved) {
                sm.sendServerMessage("[SaveManager.loadAll] 时间戳检查不通过: json=" + jsonLastSaved + " sol=" + solLastSaved);
            } else {
                useJson = true;
            }

            if (useJson) {
                sm.sendServerMessage("[SaveManager.loadAll] 使用 JSON 权威数据 ts=" + jsonLastSaved);
                var jsonData:Object = _prefetchedData;
                clearPrefetch();

                if (!_applyCore(jsonData)) {
                    if (_drugLoadoutSchemaRejected) {
                        sm.sendServerMessage("[SaveManager.loadAll] JSON future drugLoadout rejected; fail closed without SOL fallback");
                        _root._saveRestoreError = true;
                        return false;
                    }
                    sm.sendServerMessage("[SaveManager.loadAll] JSON applyCore 失败，降级 SOL");
                } else {
                    // SO 覆盖层：与 SOL 路径步骤一致
                    var jso:SharedObject = getSO();
                    var jsoData:Object = jso.data;

                    // tasks（优先非空顶层；空顶层回退到 mydata.tasks，并用 mydata[3] 修补旧档主线）
                    applyTaskBundleWithFallback(jsoData, _root.mydata.tasks, "loadAll.json");

                    // 宠物/商城（优先非空顶层；空顶层回退到 mydata）
                    applyPetsBundleWithFallback(jsoData, _root.mydata.pets, "loadAll.json");
                    applyShopBundleWithFallback(jsoData, _root.mydata.shop, "loadAll.json");

                    // lastsave + dirtyMark
                    if (_root.当前玩家总数 == 1) {
                        _root.lastsave = _root.mydata.toString();
                    }
                    _dirtyMark = false;
                    _root.存档系统.dirtyMark = false;

                    // 副作用链 — 严格复用 SOL 路径写法，保持直接调用
                    _root.UpdateTaskProgress();
                    _root.检查任务数据完整性();
                    _root.UI系统.防御性刷新等级经验();
                    _root.发布消息("游戏本地读取成功！");
                    _root.载入新佣兵库数据(0, 0, 0, 0, 0);
                    _root.是否达成任务检测();

                    var _jLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
                    var _jpLen = (_root.宠物信息 != undefined) ? _root.宠物信息.length : 0;
                    sm.sendServerMessage("[SaveManager.loadAll] JSON+SO 完成: " + _root.角色名 + " lv" + _root.等级 + " tasks=" + _jLen + " pets=" + _jpLen);
                    _deferredResolutionAttempted = false;
                    _deferredDecisionSource = undefined;
                    _prefetchGen++;
                    markRuntimeSaveLoaded("json_shadow");
                    return true;
                }
            } else {
                clearPrefetch();
            }
        } else if (sm.isSocketConnected) {
            sm.sendServerMessage("[SaveManager.loadAll] prefetch 未就绪，走 SOL");
        }

        // ─── SOL 路径（原有逻辑完全不变）───

        // 始终从 SO 鲜读
        var so:SharedObject = getSO();
        var soData:Object = so.data;
        _root.mydata = soData[SAVE_KEY];

        // 空槽位 guard
        if (_root.mydata == undefined) {
            sm.sendServerMessage("[SaveManager.loadAll] 空槽位，return false");
            _prefetchGen++;
            return false;
        }

        // 结构校验：主角储存数据必须存在
        if (_root.mydata[0] == undefined) {
            sm.sendServerMessage("[SaveManager.loadAll] 存档结构异常: mydata[0]=undefined，return false");
            _prefetchGen++;
            return false;
        }

        sm.sendServerMessage("[SaveManager.loadAll] version=" + _root.mydata.version + " 角色名=" + _root.mydata[0][0] + " 等级=" + _root.mydata[0][3]);

        // SOL 分支没有经过 _applyCore；切换角色时必须在解包当前存档前清掉
        // 上一角色留下的设置/键位迁移 latch。当前存档若确需迁移，下面的
        // migrate / unpackGameState 会按本档内容重新置位。
        _settingsMigrationPending = false;
        KeyManager.clearPendingKeySettingsMigration();

        // 迁移
        var changed:Boolean = migrate(_root.mydata, soData);
        if (_drugLoadoutSchemaRejected) {
            sm.sendServerMessage("[SaveManager.loadAll] drugLoadout schema rejected");
            _prefetchGen++;
            return false;
        }
        if (_rewardInboxSchemaRejected) {
            sm.sendServerMessage("[SaveManager.loadAll] rewardInbox schema rejected");
            _prefetchGen++;
            return false;
        }
        if (changed) {
            syncTopLevelFromMydata(_root.mydata, soData);
            if (flushSO(so, "read_migration")) {
                sm.sendServerMessage("[SaveManager.loadAll] 迁移已持久化");
            }
        }

        // 解包 mydata 内部数据（主角/装备/设置/物品栏等）
        if (!unpackGameState(_root.mydata)) {
            sm.sendServerMessage("[SaveManager.loadAll] unpackGameState 失败");
            _prefetchGen++;
            return false;
        }

        sm.sendServerMessage("[SaveManager.loadAll] unpack完成: 角色名=" + _root.角色名 + " 等级=" + _root.等级 + " 金钱=" + _root.金钱);

        // 从顶层 key 读取 tasks/pets/shop（优先非空顶层；空顶层回退到 mydata）
        applyTaskBundleWithFallback(soData, _root.mydata.tasks, "loadAll.sol");
        applyPetsBundleWithFallback(soData, _root.mydata.pets, "loadAll.sol");
        applyShopBundleWithFallback(soData, _root.mydata.shop, "loadAll.sol");

        var _ttdLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
        sm.sendServerMessage("[SaveManager.loadAll] 顶层tasks: tasks_to_do=" + (soData.tasks_to_do != undefined) + " len=" + _ttdLen);
        sm.sendServerMessage("[SaveManager.loadAll] 顶层pets: 战宠=" + (soData.战宠 != undefined) + " 宠物领养限制=" + soData.宠物领养限制);

        // lastsave 初始化
        if (_root.当前玩家总数 == 1) {
            _root.lastsave = _root.mydata.toString();
        }

        // 刚读取的存档是干净的，重置 dirtyMark
        _dirtyMark = false;
        _root.存档系统.dirtyMark = false;

        // 副作用链
        _root.UpdateTaskProgress();
        _root.检查任务数据完整性();
        _root.UI系统.防御性刷新等级经验();
        _root.发布消息("游戏本地读取成功！");
        _root.载入新佣兵库数据(0, 0, 0, 0, 0);
        _root.是否达成任务检测();

        var _laLen = (_root.tasks_to_do != undefined) ? _root.tasks_to_do.length : 0;
        var _lpLen = (_root.宠物信息 != undefined) ? _root.宠物信息.length : 0;
        sm.sendServerMessage("[SaveManager.loadAll] 完成: 主线进度=" + _root.主线任务进度 + " tasks_to_do.len=" + _laLen + " 宠物数=" + _lpLen);
        _deferredResolutionAttempted = false;
        _deferredDecisionSource = undefined;
        _prefetchGen++;
        markRuntimeSaveLoaded("sol");
        runC4LateScanIfApplicable();  // C4: 兜底扫一次, 残留 fffd 时通知玩家 + launcher
        return true;
    }

    public function deleteSlot():Void {
        // P3a: 清理预取缓存（防止删档后被内存缓存复活）
        clearPrefetch();

        var so:SharedObject = getSO();
        so.clear();

        // P3a: 写入墓碑——防止 Launcher JSON 复活已删存档
        // 墓碑**仅在 saveAll 写入新数据时清除**，不在 delete 回调中清除。
        // 原因：旧的 inflight shadow 可能晚于 delete 落地，重新写回 JSON 文件；
        // 如果 delete 回调清了墓碑，这个迟到的旧 shadow 就会在下次启动时复活已删存档。
        so.data._deleted = true;
        flushSO(so, "delete_tombstone");

        // 通知 Launcher 删除 shadow JSON（best-effort，墓碑是真正的防线）
        var sm:ServerManager = ServerManager.getInstance();
        if (sm.isSocketConnected) {
            sm.sendTaskWithCallback("archive", {op:"delete", slot:_root.savePath}, null,
                function(resp:Object):Void {
                    sm.sendServerMessage("[SaveManager] shadow delete: " + (resp.success == true));
                }
            );
        }

        resetPerCharacterMemory();
    }

    /**
     * 只清当前角色的内存权威，不读取或改写 SOL，也不发送 shadow/archive 命令。
     * deleteSlot() 在完成存储删除后复用；Web 建角在 reserve 成功后、写入新 draft
     * 前复用，避免 frame 91 未执行时把旧角色领域带入新存档。
     */
    private function resetPerCharacterMemory():Void {
        // 旧角色尚未触发的 debounce 不能在 fresh draft 写到一半时突然落盘。
        if (_dispatchToken != undefined) {
            EnhancedCooldownWheel.I().removeTask(_dispatchToken);
            _dispatchToken = undefined;
        }
        _pendingSaveOrigin = undefined;
        _pendingSaveReasons = null;

        // 技能、快捷栏与称号。
        // 不委托时间轴回调：Web 路径的 reset 必须自身建立完整 80 槽默认，
        // 也避免外部初始化器被旧状态、加载顺序或测试替身影响。
        _root.主角技能表 = new Array(80);
        for (var skillIndex:Number = 0; skillIndex < 80; skillIndex++) {
            _root.主角技能表[skillIndex] = ["", 0, false, "", true];
        }
        _root.主角被动技能 = {};
        for (var quickSkillIndex:Number = 1; quickSkillIndex <= 12;
                quickSkillIndex++) {
            _root["快捷技能栏" + quickSkillIndex] = "";
        }
        _root.快捷物品栏4 = "";
        _root.玩家称号 = "";

        // frame 91 与 deleteSlot 共有的容器/同伴边界。
        _root.物品栏 = initInventory();
        _root.收集品栏 = initCollection();
        _root.同伴数据 = [];
        _root.同伴数 = 0;
        _root.佣兵是否出战信息 = [0, 0, 0, 0, 0];
        _root.killStats = { total:0, byType:{} };
        rebindKillStatsExtensions();

        // 其余现役 per-character 存档领域。
        _root.宠物信息 = [[], [], [], [], []];
        _root.宠物领养限制 = 5;
        _root.tasks_to_do = [];
        _root.tasks_finished = {};
        _root.task_chains_progress = {};
        _root.主线任务进度 = 0;
        if (_root.基建系统 == undefined) _root.基建系统 = {};
        _root.基建系统.infrastructure = {};
        _root.商城已购买物品 = [];
        _root.商城购物车 = [];
        _root.easterEgg = undefined;
        var initialDrugFeature:Object = DrugSlotAffinityService.normalizeSavedFeature(
            null, {}, persistedDrugKeyValidator()).feature;
        _root._saveExt = {drugLoadout:initialDrugFeature};
        RewardInboxService.resetSession();
        _root.虚拟币 = 0;
        _root.全局健身HP加成 = 0;
        _root.全局健身MP加成 = 0;
        _root.全局健身空攻加成 = 0;
        _root.全局健身内力加成 = 0;
        _root.全局健身防御加成 = 0;
        ItemObtainIndex.getInstance().clearDynamicDiscoveries();
        DrugInputService.resetSession();
        _settingsMigrationPending = false;
        _drugLoadoutMigrationPending = false;
        _drugLoadoutSchemaRejected = false;
        _rewardInboxMigrationPending = false;
        _rewardInboxSchemaRejected = false;
        _drugLoadoutMigrationSlot = String(_root.savePath);
        KeyManager.clearPendingKeySettingsMigration();

        // 只清内存缓存；SharedObject/shadow 只能由各自显式存储边界处理。
        _root.mydata = undefined;
        if (_root.playerData == undefined) _root.playerData = [];
        _root.playerData[0] = undefined;
        _root.lastsave = "";
        _root.lastsave2 = [];
        _lastSaveHash = "";
        _runtimeSaveLoaded = false;
        _root._saveRuntimeLoaded = false;
        _root._saveRuntimeLoadedAttemptId = undefined;
        _root.存盘标志 = 0;

        // 调用方完成全量新角色初始化后才重新开放同步存盘。
        _root.允许存档 = false;
        _dirtyMark = false;
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = false;
    }

    public function hasSaveData():Boolean {
        // Protocol 2: launcher snapshot 已就绪 → 肯定有存档
        if (_bootstrapSnapshot != undefined) return true;

        var so:SharedObject = getSO();
        var raw:Object = so.data[SAVE_KEY];
        if (raw != undefined && raw[0] != undefined && raw[0][0] != undefined) {
            return true;
        }
        // 墓碑检查：此槽位被主动删除，不允许 JSON 恢复
        if (so.data._deleted == true) return false;
        // SOL 无有效数据 — 检查 Launcher 预取是否有可用恢复数据
        if (_prefetchedData != undefined && sanitizeSlot(_prefetchedSlot) == sanitizeSlot(_root.savePath)) {
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.hasSaveData] SOL 无数据，但 Launcher 预取可用 slot=" + _prefetchedSlot);
            return true;
        }

        // Protocol 2 双重失败升格: launcher 决议 needs_migration/corrupt, 本地 SOL 也读不出 →
        // 不能误送"重新游戏确认", 设 _saveRestoreError = true 让 frame 128/:3198/:3363 走"存档损坏" UI.
        if (_deferredResolutionAttempted) {
            var src:String = (_deferredDecisionSource != undefined) ? _deferredDecisionSource : "unknown";
            _deferredResolutionAttempted = false;
            _deferredDecisionSource = undefined;
            _root._saveRestoreError = true;
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.hasSaveData] deferred resolution double failure (source=" + src + ") → restore error");
        }
        return false;
    }

    /**
     * Launcher 异步预取是否正在进行中（SOL 缺失时帧脚本可轮询此状态）
     * true = 预取请求已发出且尚未返回（_prefetchInFlight），SOL 缺失，且未被主动删除
     * Protocol 2 下 snapshot 已就绪, 无需异步等待, 立即返回 false.
     *
     * C2-β: _repairPending 拉起后无条件返回 true — asLoader.xml 的 sendReady gate
     * (line 198) 据此 yield, 让用户在 BootstrapPanel 修复卡片上做决策, 期间 Flash 帧
     * 不进入主时间线、不 sendReady、保持加载画面挂起. applyRepairResolved 落地后清 flag.
     */
    public function isRecoveryPending():Boolean {
        if (_repairPending) return true;
        if (_bootstrapSnapshot != undefined) return false;
        if (_root.mydata != undefined) return false;
        if (_prefetchedData != undefined) return false;
        if (getSO().data._deleted == true) return false;
        return _prefetchInFlight;
    }

    /**
     * C2-β: launcher 推送 task=repair_resolved 时由 ServerManager 调本方法.
     *   resp = { success:Boolean, forced:Boolean, slot:String, cleanedSnapshot?:Object }
     *   - success && cleanedSnapshot 存在 → 用清洁版快照, validate 通过即喂 _root.mydata
     *   - success && forced=true → 用原坏档 (_bootstrapSnapshot, 已在 preload 阶段 stash).
     *     用户已在 UI 做过二次确认, 这里不再拦截.
     *   - success=false → 不动 mydata, 留 _repairPending=true (用户可在卡片上重试).
     */
    public function applyRepairResolved(resp:Object):Void {
        var sm:ServerManager = ServerManager.getInstance();
        if (resp == undefined) {
            sm.sendServerMessage("[SaveManager.applyRepairResolved] resp undefined");
            return;
        }
        if (!_repairPending) {
            sm.sendServerMessage("[SaveManager.applyRepairResolved] not pending, drop (repair already resolved or not initiated)");
            return;
        }
        if (resp.success != true) {
            sm.sendServerMessage("[SaveManager.applyRepairResolved] failed, stay pending: error="
                + (resp.error != undefined ? resp.error : "unknown"));
            return;
        }
        var forced:Boolean = (resp.forced == true);
        if (forced) {
            // forced 路径: 用 stash 的原坏档. _bootstrapSnapshot 在 preload "repairable" 分支已存好.
            if (_bootstrapSnapshot == undefined) {
                sm.sendServerMessage("[SaveManager.applyRepairResolved] forced but no stashed snapshot, abort");
                return;
            }
            _root.mydata = _bootstrapSnapshot;
            _repairPending = false;
            sm.sendServerMessage("[SaveManager.applyRepairResolved] forced=true: using original (fffd-tainted) snapshot");
            return;
        }
        // 正常路径: 用 launcher 修过的清洁快照.
        var cleaned:Object = resp.cleanedSnapshot;
        if (cleaned == undefined) {
            sm.sendServerMessage("[SaveManager.applyRepairResolved] success but no cleanedSnapshot, abort");
            return;
        }
        if (!validateMydata(cleaned)) {
            sm.sendServerMessage("[SaveManager.applyRepairResolved] cleanedSnapshot validate failed, abort");
            return;
        }
        _bootstrapSnapshot = cleaned;
        _root.mydata = cleaned;
        _repairPending = false;
        sm.sendServerMessage("[SaveManager.applyRepairResolved] applied cleanedSnapshot, pending cleared");
    }

    /** C2-β: 给外部（测试 / 帧脚本）查 RepairPending 状态. */
    public function isRepairPending():Boolean {
        return _repairPending;
    }

    // ──────────────────────── C4: 末尾兜底扫描 ────────────────────────
    // C1a 修了 socket 漏洞、C2-α 启动期 inline 修过、C2-β 用户决策修过, 这层只是 paranoid:
    // mydata 进游戏前最后扫一次, 残留 fffd → toast (一次性) + launcher save_corrupt_late log.
    // 单 session 最多跑一次. 时间预算 20ms, 超了立刻 bail (sampled=true), 不阻塞游戏启动.

    private function runC4LateScanIfApplicable():Void {
        if (_c4Scanned) return;
        _c4Scanned = true;
        if (_root.mydata == undefined) return;

        var sm:ServerManager = ServerManager.getInstance();
        var startMs:Number = getTimer();
        var ctx:Object = {
            startMs: startMs,
            budgetMs: C4_SCAN_BUDGET_MS,
            sampled: false,
            fffdCount: 0,
            keyHits: 0,
            paths: []
        };
        scanFffdRecursive(_root.mydata, [], ctx);
        var elapsedMs:Number = getTimer() - startMs;
        sm.sendServerMessage("[SaveManager.c4] scan done elapsed=" + elapsedMs
            + "ms sampled=" + ctx.sampled + " fffd=" + ctx.fffdCount + " keyHits=" + ctx.keyHits);
        if (ctx.fffdCount == 0) return;

        // 上报 launcher (fire-and-forget). C# 端 SaveCorruptLateHandler 仅记日志, 不阻断游戏.
        if (sm.isSocketConnected) {
            sm.sendTaskToNode("save_corrupt_late", {
                slot: _root.savePath,
                fffdCount: ctx.fffdCount,
                keyHits: ctx.keyHits,
                sampled: ctx.sampled,
                elapsedMs: elapsedMs,
                paths: ctx.paths
            }, null);
        }

        // 玩家提示 (一次性). 没有专用 _root.UI系统.状态栏 挂点, 降级到 _root.发布消息.
        if (!_c4WarnedOnce) {
            _c4WarnedOnce = true;
            if (typeof _root.发布消息 == "function") {
                _root.发布消息("[档异常] 检测到存档残留乱码字符 (" + ctx.fffdCount + " 处), 建议返回引导器修复。");
            }
        }
    }

    private function scanFffdRecursive(node:Object, path:Array, ctx:Object):Void {
        // 安全闸: 不能因为单个槽位的复杂度让全局耗时失控.
        if (ctx.sampled) return;
        if (ctx.fffdCount + ctx.keyHits >= 10000) return;
        if ((getTimer() - ctx.startMs) > ctx.budgetMs) {
            ctx.sampled = true;
            return;
        }

        if (typeof node == "string") {
            if (String(node).indexOf(SaveManager.FFFD_CHAR) >= 0) {
                ctx.fffdCount++;
                if (ctx.paths.length < SaveManager.C4_MAX_PATHS_REPORTED) {
                    ctx.paths.push(path.join("."));
                }
            }
            return;
        }
        if (node instanceof Array) {
            for (var i:Number = 0; i < node.length; i++) {
                path.push(String(i));
                scanFffdRecursive(node[i], path, ctx);
                path.pop();
                if (ctx.sampled) return;
            }
            return;
        }
        if (typeof node == "object" && node != null) {
            for (var k:String in node) {
                // object key 也可能含 fffd (e.g. byType / 装备栏 槽位 key)
                if (typeof k == "string" && k.indexOf(SaveManager.FFFD_CHAR) >= 0) {
                    ctx.keyHits++;
                    if (ctx.paths.length < SaveManager.C4_MAX_PATHS_REPORTED) {
                        path.push(k);
                        ctx.paths.push(path.join(".") + " (key)");
                        path.pop();
                    }
                }
                path.push(k);
                scanFffdRecursive(node[k], path, ctx);
                path.pop();
                if (ctx.sampled) return;
            }
            return;
        }
        // number / boolean / null / undefined: skip
    }

    // 单字符常量, 避免每次重新构造 String.fromCharCode (AS2 类静态字段在 ASO 缓存里复用)
    private static var FFFD_CHAR:String = String.fromCharCode(0xFFFD);

    /**
     * 旧时间轴兼容入口。旧 UI 仍保留 30 帧人工 SceneReady；Web 建角必须改走
     * prepareNewCharacter() -> flushNow() -> startNewCharacterTutorial(..., false, ...)，
     * 只采信场景加载完真实主角后发布的 SceneReady。
     */
    public function newCharacter():Boolean {
        if (_root.帧计时器 == undefined
                || typeof _root.帧计时器.添加单次任务 != "function") {
            return false;
        }
        var prepared:Object = prepareNewCharacter(null, "new_character");
        if (!prepared.success) return false;
        return startNewCharacterTutorial(String(prepared.startToken), true, null, null);
    }

    /**
     * 新角色事务第一段：先抢教学关 exact reservation，再执行一次初始化。
     * initialState 仅供已经完成权威校验的 CharacterCreationService 使用；null
     * 表示沿用旧时间轴已经写入 _root 的外观字段。
     */
    public function prepareNewCharacter(initialState:Object, reservationOwner:String):Object {
        var reservation:Object = reserveNewCharacterTutorial(reservationOwner);
        if (!reservation.success) return reservation;
        var tutorialStageName:String = String(reservation.stageName);
        var tutorialDifficulty:String = String(reservation.stageDifficulty);
        var startToken:String = String(reservation.startToken);

        try {
            // Web 路径停在 frame 81，不会经过 frame 91/deleteSlot。先清旧角色
            // 的全部内存领域与预取缓存，但绝不触碰当前 SOL/shadow。
            clearPrefetch();
            resetPerCharacterMemory();

            if (initialState != null) {
                _root.角色名 = initialState.characterName;
                _root.性别 = initialState.genderText;
                _root.身高 = initialState.height;
                _root.脸型 = initialState.faceIdentifier;
                _root.发型 = initialState.hairIdentifier;
                _root.上装装备 = initialState.upperIdentifier;
                _root.下装装备 = initialState.lowerIdentifier;
                _root.脚部装备 = initialState.footwearIdentifier;
                _root.难度 = initialState.difficultyText;
            }

            // 旧性别选择帧本来会写入这些基础值；收口到初始化边界后，Web 路径
            // 不需要先污染 _root，旧入口重复写入相同值也保持兼容。
            _root.金钱 = 0;
            _root.等级 = 1;
            _root.经验值 = 0;
            _root.技能点数 = 0;
            _root.身价 = _root.基础身价值;

            // deleteSlot() 禁用了存档，新建角色时恢复
            _root.允许存档 = true;

            // 初始装备
            if (_root.上装装备 != "") {
                _root.物品栏.装备栏.add("上装装备", BaseItem.create(_root.上装装备, 1));
            }
            if (_root.下装装备 != "") {
                _root.物品栏.装备栏.add("下装装备", BaseItem.create(_root.下装装备, 1));
            }
            if (_root.脚部装备 != "") {
                _root.物品栏.装备栏.add("脚部装备", BaseItem.create(_root.脚部装备, 1));
            }

            // 难度模式
            if (_root.难度 == "逆天模式（简单）") {
                _root.difficultyMode = 1;
            } else if (_root.难度 == "挑战模式（自限）") {
                _root.difficultyMode = 2;
            } else {
                _root.difficultyMode = 0;
            }

            _root.上装装备 = undefined;
            _root.下装装备 = undefined;
            _root.脚部装备 = undefined;
            _root.难度 = undefined;

            // 所有 per-character 默认与初装都已完成后才组包；这样 prepare 返回时
            // _root.mydata 本身也是干净候选，不依赖后续 flush 重新组包来纠偏。
            _root.mydata = packGameState();

            // 新出生标志
            _root.新出生 = false;
        } catch (initializationError) {
            trace("[SaveManager.prepareNewCharacter] initialization failed: "
                + initializationError);
            releaseNewCharacterReservation(startToken, null, "initialization_failed");
            return {success:false, error:"initialization_failed"};
        }

        return {
            success:true,
            startToken:startToken,
            stageName:tutorialStageName,
            stageDifficulty:tutorialDifficulty
        };
    }

    /**
     * durable 后教学关加载失败的重试入口：只重新抢 reservation，不碰角色数据。
     */
    public function reserveNewCharacterTutorial(reservationOwner:String):Object {
        var tutorialStageName:String = "教学关卡";
        var tutorialDifficulty:String = String(_root.当前关卡难度 || "简单");
        if (typeof _root.载入关卡数据 != "function"
                || _root.淡出动画 == undefined
                || typeof _root.淡出动画.淡出跳转帧 != "function") {
            return {success:false, error:"transition_unavailable"};
        }
        var startToken:String = "";
        try {
            startToken = org.flashNight.arki.scene.StageRunSession.reserveStageStart(
                reservationOwner == null || reservationOwner == ""
                    ? "new_character" : reservationOwner,
                tutorialStageName, tutorialDifficulty);
        } catch (reserveError) {
            trace("[SaveManager.reserveNewCharacterTutorial] reservation failed: "
                + reserveError);
            return {success:false, error:"stage_busy"};
        }
        if (startToken == "") return {success:false, error:"stage_busy"};
        return {
            success:true,
            startToken:startToken,
            stageName:tutorialStageName,
            stageDifficulty:tutorialDifficulty
        };
    }

    /**
     * 新角色事务第二段：只负责教学 XML 与淡出。调用方必须先持有
     * prepareNewCharacter() 返回的 exact token；本方法绝不重新初始化角色。
     */
    public function startNewCharacterTutorial(startToken:String,
            scheduleSyntheticSceneReady:Boolean,
            onTransitionAccepted:Function,
            onFailure:Function):Boolean {
        if (startToken == null || startToken == ""
                || typeof _root.载入关卡数据 != "function"
                || _root.淡出动画 == undefined
                || typeof _root.淡出动画.淡出跳转帧 != "function"
                || (scheduleSyntheticSceneReady
                    && (_root.帧计时器 == undefined
                        || typeof _root.帧计时器.添加单次任务 != "function"))) {
            releaseNewCharacterReservation(startToken, onFailure, "transition_unavailable");
            return false;
        }

        var tutorialStageName:String = "教学关卡";
        var tutorialDifficulty:String = String(_root.当前关卡难度 || "简单");
        var settled:Boolean = false;
        var failedSynchronously:Boolean = false;
        var loadCallReturned:Boolean = false;
        var failOnce:Function = function():Void {
            if (settled) return;
            settled = true;
            if (!loadCallReturned) failedSynchronously = true;
            SaveManager.getInstance().releaseNewCharacterReservation(
                startToken, onFailure, "stage_load_failed");
        };

        // XML/TimePool 成功前不停止 BGM、不调度 SceneReady、不淡出。
        // 异步 XML 失败按既有契约保留上方已完成的角色初始化写入。
        try {
            _root.载入关卡数据("无限过图", "data/stages/特殊/教学关卡.xml",
                function():Void {
                    if (settled) return;
                    if (!org.flashNight.arki.scene.StageRunSession
                            .isStageStartReservationValid(startToken)) {
                        failOnce();
                        return;
                    }
                    try {
                        _root.当前通关的关卡 = "";
                        _root.当前关卡名 = tutorialStageName;
                        _root.当前关卡难度 = tutorialDifficulty;
                        if (typeof _root.计算难度等级 == "function") {
                            _root.难度等级 = _root.计算难度等级(tutorialDifficulty);
                        }
                        _root.关卡类型 = "无限过图";
                        _root.关卡路径 = "data/stages/特殊/教学关卡.xml";
                        _root.场景进入位置名 = "出生地";
                    } catch (transitionPrepareError) {
                        trace("[SaveManager.newCharacter] tutorial transition prepare failed: "
                            + transitionPrepareError);
                        failOnce();
                        return;
                    }
                    try {
                        if (_root.soundEffectManager != undefined
                                && typeof _root.soundEffectManager.stopBGMForTransition == "function") {
                            _root.soundEffectManager.stopBGMForTransition();
                        }
                    } catch (bgmStopError) {
                        trace("[SaveManager.newCharacter] tutorial BGM projection failed: "
                            + bgmStopError);
                    }
                    try {
                        _root.淡出动画.淡出跳转帧("wuxianguotu_1");
                    } catch (fadeError) {
                        trace("[SaveManager.newCharacter] tutorial fade failed: " + fadeError);
                        failOnce();
                        return;
                    }

                    // fade 已接受即为转场提交点；先封闭回调，再调度 SceneReady，
                    // 调度器投影抛错不得反向撤销已接受的 fade/StageManager preload。
                    settled = true;
                    if (onTransitionAccepted != null) onTransitionAccepted();
                    if (scheduleSyntheticSceneReady) {
                        try {
                            _root.帧计时器.添加单次任务(function():Void {
                                EventBus.instance.publish("SceneReady");
                            }, 30);
                        } catch (sceneReadyScheduleError) {
                            trace("[SaveManager.newCharacter] SceneReady schedule failed: "
                                + sceneReadyScheduleError);
                        }
                    }
                }, failOnce, startToken);
        } catch (loadStartError) {
            trace("[SaveManager.newCharacter] tutorial load failed: " + loadStartError);
            failOnce();
        }
        loadCallReturned = true;
        return !failedSynchronously;
    }

    /** 释放教学关 prepared stage 与 reservation，并把失败投影回调用方。 */
    private function releaseNewCharacterReservation(startToken:String,
            onFailure:Function, errorCode:String):Void {
        try {
            var manager:org.flashNight.arki.scene.StageManager =
                org.flashNight.arki.scene.StageManager.instance;
            if (manager != null) manager.abortPreparedStage(startToken);
        } catch (preparedAbortError) {
            trace("[SaveManager.newCharacter] prepared stage abort failed: "
                + preparedAbortError);
        }
        try {
            org.flashNight.arki.scene.StageRunSession.cancelStageStart(startToken);
        } catch (reservationCancelError) {
            trace("[SaveManager.newCharacter] reservation cancel failed: "
                + reservationCancelError);
        }
        try {
            if (typeof _root.最上层发布文字提示 == "function") {
                _root.最上层发布文字提示("教学关卡加载失败，请返回标题后重试。");
            }
        } catch (failureNoticeError) {
            trace("[SaveManager.newCharacter] failure notice failed: "
                + failureNoticeError);
        }
        if (onFailure != null) onFailure(errorCode);
    }

    // ==================== 数据组包/解包 ====================

    /**
     * Plan B 落点：本方法当前一次性组装全量 mydata（~14KB）。
     * 未来分块 dirty 时把本函数拆成：
     *   packCharacterSection() / packEquipmentSection() / packInventorySection() /
     *   packCollectionSection() / packTasksSection() / packPetsSection() /
     *   packShopSection() / packKillStatsSection() / packOthersSection() /
     *   packInfrastructureSection()
     * 由 _doSaveAll 根据 _sectionDirty[name] 选择性调用；clean section 复用上次结果。
     * 注意：mydata.lastSaved / mydata.version 必须每次都更新（不可分块跳过）。
     */
    public function packGameState():Object {
        savePhysicalStats().packGameState++;
        _root.身价 = _root.基础身价值 * _root.等级;

        var 主角储存数据:Array = [
            _root.角色名, _root.性别, _root.金钱, _root.等级, _root.经验值,
            _root.身高, _root.技能点数, _root.玩家称号, _root.身价, _root.虚拟币,
            _root.键值设定, _root.difficultyMode, _root.佣兵是否出战信息, _root.easterEgg
        ];

        var 装备储存数据:Array = [
            _root.脸型, _root.发型,
            null, null, null, null, null, null, null, null, null, null, null,
            null, null, null,
            _root.快捷技能栏1, _root.快捷技能栏2, _root.快捷技能栏3, _root.快捷技能栏4,
            _root.快捷技能栏5, _root.快捷技能栏6, _root.快捷技能栏7, _root.快捷技能栏8,
            _root.快捷技能栏9, _root.快捷技能栏10, _root.快捷技能栏11, _root.快捷技能栏12,
            _root.快捷物品栏4
        ];

        var 物品储存数据:Object = {
            背包:   _root.物品栏.背包.toObject(),
            装备栏: _root.物品栏.装备栏.toObject(),
            药剂栏: _root.物品栏.药剂栏.toObject(),
            仓库:   _root.物品栏.仓库.toObject(),
            战备箱: _root.物品栏.战备箱.toObject()
        };

        var 收集品储存数据:Object = {
            材料: _root.收集品栏.材料.toObject(),
            情报: _root.收集品栏.情报.toObject()
        };

        if (_root.killStats == null) {
            _root.killStats = { total:0, byType:{} };
            rebindKillStatsExtensions();
        }

        var 其他存储数据:Object = {
            设置: packSettings(),
            击杀统计: _root.killStats,
            物品来源缓存: ItemObtainIndex.getInstance().exportToSave()
        };

        var mydata:Object = {};
        mydata.version = LATEST_VERSION;
        mydata[0] = 主角储存数据;
        mydata[1] = 装备储存数据;
        mydata[2] = null;
        mydata[3] = _root.主线任务进度;
        mydata[4] = [_root.同伴数据, _root.同伴数];
        mydata[5] = _root.主角技能表;
        mydata[6] = null;
        mydata[7] = [_root.全局健身HP加成, _root.全局健身MP加成, _root.全局健身空攻加成, _root.全局健身防御加成, _root.全局健身内力加成];
        mydata.inventory = 物品储存数据;
        mydata.collection = 收集品储存数据;
        mydata.infrastructure = _root.基建系统.infrastructure;
        mydata.lastSaved = packTimestamp();
        mydata.others = 其他存储数据;

        // 归一化：折入 tasks/pets/shop
        mydata.tasks = {
            tasks_to_do: _root.tasks_to_do,
            tasks_finished: _root.tasks_finished,
            task_chains_progress: _root.task_chains_progress
        };
        mydata.pets = {
            宠物信息: _root.宠物信息,
            宠物领养限制: _root.宠物领养限制
        };
        mydata.shop = {
            商城已购买物品: _root.商城已购买物品,
            商城购物车: _root.商城购物车
        };

        // 预留命名空间 — 透传已有数据，保证往返不丢
        if (_root._saveExt == undefined) _root._saveExt = {};
        var packedDrugFeature:Object = DrugSlotAffinityService.normalizeSavedFeature(
            _root._saveExt.drugLoadout, mydata.inventory.药剂栏,
            persistedDrugKeyValidator());
        if (packedDrugFeature.ok === true) {
            _root._saveExt.drugLoadout = packedDrugFeature.feature;
        } else {
            // 未知未来版本必须原样透传，禁止 pack 时静默降级或丢 affinity。
            trace("[SaveManager.packGameState] drugLoadout preserved: "
                + String(packedDrugFeature.error));
        }
        mydata.ext = _root._saveExt;
        mydata.reserved = {};

        return mydata;
    }

    // ==================== JSON 校验/装载 ====================

    /**
     * 校验 mydata 结构完整性 — 覆盖 unpackGameState + loadFromMydata 消费的全部字段。
     * 用于拦截截断/损坏的 JSON 数据（含边界截断导致尾部 tasks/pets/shop 丢失的场景）。
     */
    private function validateMydata(mydata:Object):Boolean {
        if (mydata == undefined) return false;
        if (mydata.version != "3.0") return false;
        if (mydata.lastSaved == undefined) return false;

        // 数组槽位（unpackGameState 消费的最大索引+1）
        if (!(mydata[0] instanceof Array) || mydata[0].length < 14) return false;
        if (mydata[0][0] == undefined || mydata[0][0] == null || String(mydata[0][0]).length == 0) return false;
        if (mydata[0][3] == undefined || isNaN(Number(mydata[0][3]))) return false;
        if (!(mydata[1] instanceof Array) || mydata[1].length < 28) return false;
        if (mydata[3] == undefined) return false;
        if (!(mydata[4] instanceof Array) || mydata[4].length < 2) return false;
        if (!(mydata[5] instanceof Array)) return false;
        if (!(mydata[7] instanceof Array) || mydata[7].length < 5) return false;

        // 对象字段
        if (mydata.inventory == undefined) return false;
        if (mydata.inventory.背包 == undefined) return false;
        if (mydata.inventory.装备栏 == undefined) return false;
        if (mydata.inventory.药剂栏 == undefined) return false;
        if (mydata.inventory.仓库 == undefined) return false;
        if (mydata.inventory.战备箱 == undefined) return false;
        if (mydata.collection == undefined) return false;
        if (mydata.collection.材料 == undefined) return false;
        if (mydata.collection.情报 == undefined) return false;
        if (mydata.infrastructure == undefined) return false;

        // 尾部字段校验 — 每个 loadFromMydata 消费的子字段都必须存在
        if (mydata.tasks == undefined) return false;
        if (mydata.tasks.tasks_to_do == undefined) return false;
        if (mydata.tasks.tasks_finished == undefined) return false;
        if (mydata.tasks.task_chains_progress == undefined) return false;
        if (mydata.pets == undefined) return false;
        if (mydata.pets.宠物信息 == undefined) return false;
        if (mydata.pets.宠物领养限制 == undefined) return false;
        if (mydata.shop == undefined) return false;
        if (mydata.shop.商城已购买物品 == undefined) return false;
        if (mydata.shop.商城购物车 == undefined) return false;

        return true;
    }

    /**
     * 无副作用的核心装载 — loadAll JSON 分支和 loadFromMydata 的共用内核。
     * 只做：validate → 设 _root.mydata → 归一化 → unpackGameState。
     * 不做：tasks/pets/shop、dirtyMark、副作用链。
     */
    private function _applyCore(mydata:Object):Boolean {
        if (!validateMydata(mydata)) return false;
        // 每次切换存档都从该存档重新判定迁移，不能继承上一个角色的待保存 latch。
        _settingsMigrationPending = false;
        _drugLoadoutMigrationPending = false;
        _drugLoadoutSchemaRejected = false;
        _rewardInboxMigrationPending = false;
        _rewardInboxSchemaRejected = false;
        _drugLoadoutMigrationSlot = String(_root.savePath);
        KeyManager.clearPendingKeySettingsMigration();
        var drugSchema:Object = normalizeDrugLoadoutSchema(mydata);
        if (!drugSchema.ok) {
            _drugLoadoutSchemaRejected = true;
            return false;
        }
        if (drugSchema.changed) _drugLoadoutMigrationPending = true;
        var rewardSchema:Object = RewardInboxService.normalizeSaveData(mydata);
        if (!rewardSchema.ok) {
            _rewardInboxSchemaRejected = true;
            return false;
        }
        if (rewardSchema.changed) _rewardInboxMigrationPending = true;
        // AMF0 空数组→空对象修复（幂等纯内存修复；修复结果随 _saveExt 与
        // tasks/pets 应用层进入运行时，下次存盘自然持久化）。
        org.flashNight.arki.scene.StageRunSession.normalizeSaveData(mydata);
        normalizeTaskAndPetShapes(mydata);
        _root.mydata = mydata;
        if (!(mydata[0][10] instanceof Array)) mydata[0][10] = [];
        if (!(mydata[0][12] instanceof Array)) mydata[0][12] = [];
        return unpackGameState(mydata);
    }

    /**
     * 独立公共 API — 从 mydata 对象恢复完整游戏状态。
     * 包含 tasks/pets/shop 处理 + 副作用链（带防御性 typeof 检查）。
     * loadAll 的 JSON 分支不调用此方法，而是用 _applyCore + SO 覆盖 + 副作用。
     */
    public function loadFromMydata(mydata:Object, source:String):Boolean {
        var sm:ServerManager = ServerManager.getInstance();

        if (!_applyCore(mydata)) {
            sm.sendServerMessage("[SaveManager.loadFromMydata] applyCore failed");
            return false;
        }

        // tasks（防御性默认化 — validateMydata 已保证字段存在，fallback 是二次防御）
        var t:Object = mydata.tasks;
        _root.tasks_to_do = (t != undefined && t.tasks_to_do != undefined) ? t.tasks_to_do : [];
        _root.tasks_finished = (t != undefined && t.tasks_finished != undefined) ? t.tasks_finished : {};
        _root.task_chains_progress = (t != undefined && t.task_chains_progress != undefined) ? t.task_chains_progress : {};

        // 宠物
        var p:Object = mydata.pets;
        _root.宠物信息 = (p != undefined && p.宠物信息 != undefined) ? p.宠物信息 : [[], [], [], [], []];
        _root.宠物领养限制 = (p != undefined && p.宠物领养限制 != undefined) ? p.宠物领养限制 : 5;

        // 商城
        var sh:Object = mydata.shop;
        _root.商城已购买物品 = (sh != undefined && sh.商城已购买物品 != undefined) ? sh.商城已购买物品 : [];
        _root.商城购物车 = (sh != undefined && sh.商城购物车 != undefined) ? sh.商城购物车 : [];

        // lastsave
        if (_root.当前玩家总数 == 1) {
            _root.lastsave = _root.mydata.toString();
        }
        // dirtyMark
        _dirtyMark = false;
        _root.存档系统.dirtyMark = false;

        // 副作用链（防御性检查 — loadFromMydata 是独立公共 API，可能在启动早期调用）
        if (typeof _root.UpdateTaskProgress == "function") _root.UpdateTaskProgress();
        if (typeof _root.检查任务数据完整性 == "function") _root.检查任务数据完整性();
        if (_root.UI系统 != undefined && typeof _root.UI系统.防御性刷新等级经验 == "function") _root.UI系统.防御性刷新等级经验();
        _root.发布消息("游戏本地读取成功！");
        if (typeof _root.载入新佣兵库数据 == "function") _root.载入新佣兵库数据(0, 0, 0, 0, 0);
        if (typeof _root.是否达成任务检测 == "function") _root.是否达成任务检测();

        sm.sendServerMessage("[SaveManager.loadFromMydata] OK: " + _root.角色名 + " lv" + _root.等级);
        markRuntimeSaveLoaded(source != undefined ? source : "mydata");
        return true;
    }

    /**
     * 解包 mydata 内部数据到 _root.*（纯 mydata 内部，不含 tasks/pets/shop）
     * tasks/pets/shop 由 loadAll() 走“优先非空顶层，空壳回退 mydata”的合并逻辑
     */
    public function unpackGameState(mydata:Object):Boolean {
        if (mydata == undefined) return false;

        var 主角储存数据:Array = mydata[0];
        var 装备储存数据:Array = mydata[1];
        var 健身储存数据:Array = mydata[7];

        if (主角储存数据 == undefined) return false;

        // 主角数据
        _root.角色名 = 主角储存数据[0];
        _root.性别 = 主角储存数据[1];
        _root.金钱 = Math.floor(Number(主角储存数据[2]));
        _root.等级 = Math.floor(Number(主角储存数据[3]));
        _root.经验值 = Math.floor(Number(主角储存数据[4]));
        _root.虚拟币 = Math.floor(Number(主角储存数据[9]));
        _root.身高 = Math.floor(Number(主角储存数据[5]));
        _root.技能点数 = Math.floor(Number(主角储存数据[6]));
        _root.玩家称号 = 主角储存数据[7];
        _root.身价 = Math.floor(Number(主角储存数据[8]));
        _root.easterEgg = 主角储存数据[13];

        // 健身加成
        _root.全局健身HP加成 = Math.floor(Number(健身储存数据[0]));
        _root.全局健身MP加成 = Math.floor(Number(健身储存数据[1]));
        _root.全局健身空攻加成 = Math.floor(Number(健身储存数据[2]));
        _root.全局健身防御加成 = Math.floor(Number(健身储存数据[3]));
        _root.全局健身内力加成 = Math.floor(Number(健身储存数据[4]));
        if (isNaN(_root.全局健身HP加成)) _root.全局健身HP加成 = 0;
        if (isNaN(_root.全局健身MP加成)) _root.全局健身MP加成 = 0;
        if (isNaN(_root.全局健身空攻加成)) _root.全局健身空攻加成 = 0;
        if (isNaN(_root.全局健身内力加成)) _root.全局健身内力加成 = 0;
        if (isNaN(_root.全局健身防御加成)) _root.全局健身防御加成 = 0;

        // 键值设定
        if (主角储存数据[10].length > 0) {
            _root.键值设定 = 主角储存数据[10];
        }
        // 读档后必须刷新逻辑键缓存与订阅的物理投影。旧实现只替换数组，
        // 导致 _root 键码和 KeyManager 仍停留在启动默认值。
        if (typeof _root.刷新键值设定 == "function") {
            _root.刷新键值设定();
        }

        // 难度模式
        if (主角储存数据[11] >= 0) {
            _root.difficultyMode = 主角储存数据[11];
        } else {
            _root.difficultyMode = 0;
        }

        // 佣兵出战信息
        if (主角储存数据[12].length > 0) {
            _root.佣兵是否出战信息 = 主角储存数据[12];
            var i:Number = 0;
            while (i < _root.佣兵是否出战信息.length) {
                if (_root.佣兵是否出战信息[i] == -1) {
                    _root.佣兵是否出战信息[i] = 1;
                }
                i++;
            }
        }

        // 经验值校验
        var tmp经验值:Number = _root.根据等级得升级所需经验(_root.等级);
        if (tmp经验值 < _root.经验值) {
            _root.经验值 = tmp经验值;
        }
        tmp经验值 = _root.根据等级得升级所需经验(_root.等级 - 1);
        if (tmp经验值 > _root.经验值) {
            _root.经验值 = tmp经验值;
        }

        // 强化等级重置
        _root.长枪强化等级 = undefined;
        _root.手枪强化等级 = undefined;
        _root.手枪2强化等级 = undefined;
        _root.刀强化等级 = undefined;

        // 装备数据
        _root.脸型 = 装备储存数据[0];
        _root.发型 = 装备储存数据[1];
        _root.快捷技能栏1 = 装备储存数据[16];
        _root.快捷技能栏2 = 装备储存数据[17];
        _root.快捷技能栏3 = 装备储存数据[18];
        _root.快捷技能栏4 = 装备储存数据[19];
        _root.快捷技能栏5 = 装备储存数据[20];
        _root.快捷技能栏6 = 装备储存数据[21];
        _root.快捷技能栏7 = 装备储存数据[22];
        _root.快捷技能栏8 = 装备储存数据[23];
        _root.快捷技能栏9 = 装备储存数据[24];
        _root.快捷技能栏10 = 装备储存数据[25];
        _root.快捷技能栏11 = 装备储存数据[26];
        _root.快捷技能栏12 = 装备储存数据[27];

        // 同伴
        _root.同伴数据 = mydata[4][0];
        _root.同伴数 = Math.floor(Number(mydata[4][1]));
        // 佣兵数据归一化（修复历史空洞档）：旧版解雇用 [] 占位且不压缩、旧版 handleHire 用
        // 同伴数据.push 追加，会让 同伴数据 出现中段墓碑或越过 [0,佣兵个数限制) 读窗口的尾项，
        // 表现为 issue #7 bug1「扣钱但不入可用列表」。此处把 同伴数据 / 佣兵是否出战信息 严格并行
        // 压实、令 同伴数 = 有效数，并回收越界尾项（最多保留 佣兵个数限制 个）。对干净档幂等。
        normalizeCompanionData();

        // 技能表
        _root.主角技能表 = mydata[5];
        _root.更新主角被动技能();

        // 物品栏
        _root.物品栏 = {
            背包: new ArrayInventory(mydata.inventory.背包, 50),
            装备栏: new EquipmentInventory(mydata.inventory.装备栏),
            药剂栏: new DrugInventory(mydata.inventory.药剂栏, 8),
            仓库: new ArrayInventory(mydata.inventory.仓库, 1200),
            战备箱: new ArrayInventory(mydata.inventory.战备箱, 400)
        };

        // 收集品栏
        _root.收集品栏 = {
            材料: new DictCollection(mydata.collection.材料),
            情报: new InformationCollection(mydata.collection.情报)
        };

        // 基建
        _root.基建系统.infrastructure = mydata.infrastructure;

        // 其他数据
        if (mydata.others) {
            if (mydata.others.设置) {
                applySettings(mydata.others.设置);
            }
            if (mydata.others.击杀统计) {
                _root.killStats = mydata.others.击杀统计;
            } else {
                _root.killStats = { total:0, byType:{} };
            }
            rebindKillStatsExtensions();
            if (mydata.others.物品来源缓存) {
                ItemObtainIndex.getInstance().loadFromSave(mydata.others.物品来源缓存);
            }
        } else {
            _root.killStats = { total:0, byType:{} };
            rebindKillStatsExtensions();
        }

        // 预留命名空间恢复
        _root._saveExt = (mydata.ext != undefined) ? mydata.ext : {};
        RewardInboxService.resetSession();

        // ext 与全部玩家资产均已重建后，恢复未完成的关卡结算 authority。
        // 畸形/未来记录保留原文并由 StageRunSession 阻止新关卡覆盖，不拖垮普通读档。
        org.flashNight.arki.scene.StageRunSession.resetForRestart();
        var settlementRestore:Object = null;
        try {
            settlementRestore = org.flashNight.arki.scene.StageRunSession.restorePendingSettlement();
        } catch (settlementRestoreError) {
            settlementRestore = null;
        }
        if (settlementRestore == null || settlementRestore.success !== true) {
            trace("[SaveManager.unpackGameState] pending stage settlement preserved but not restored");
        }

        // 主线任务进度（从 mydata[3]，后续 loadAll 会从 task_chains_progress 覆盖）
        _root.主线任务进度 = Math.floor(Number(mydata[3]));

        if (_root.角色名 == undefined) {
            _root.发布消息("游戏本地无存盘！");
            return false;
        }

        DrugInputService.resetSession();
        return true;
    }

    // ═══════════════════════════════════════════════════════════
    // normalizeCompanionData — 读档佣兵数据归一化（issue #7 bug1 修复）
    // 历史空洞档（旧版解雇用 [] 占位不压缩 / 旧版 handleHire 用 push 越界追加）会让
    // 同伴数据 出现中段墓碑、或越过 [0,佣兵个数限制) 读窗口的尾项 → 快照与进场都读不到，
    // 表现为「扣钱但不入可用列表」。此处把 同伴数据 / 佣兵是否出战信息 严格并行压实
    // （有效项判据 = 等级列 [0] 非 undefined，与 MercCensus/removeMerc 一致），令
    // 同伴数 = 有效数，最多保留 佣兵个数限制 个（回收越界尾项）。对干净档幂等。
    // ═══════════════════════════════════════════════════════════
    private function normalizeCompanionData():Void {
        var data:Array = _root.同伴数据;
        if (data == undefined) { _root.同伴数据 = []; _root.同伴数 = 0; return; }
        var deploy:Array = _root.佣兵是否出战信息;
        if (deploy == undefined) deploy = [];
        var cap:Number = Number(_root.佣兵个数限制) || 0;

        var compact:Array = [];
        var compactDeploy:Array = [];
        var n:Number = data.length;
        for (var i:Number = 0; i < n; i++) {
            var m:Array = data[i];
            if (m != undefined && m[0] != undefined) {
                if (cap > 0 && compact.length >= cap) break; // 不超过佣兵个数限制
                compact.push(m);
                compactDeploy.push(Number(deploy[i]) || 0);
            }
        }
        _root.同伴数据 = compact;
        _root.佣兵是否出战信息 = compactDeploy;
        _root.同伴数 = compact.length;
    }

    // ==================== 商城即时写入 ====================

    public function saveShopCart():Void {
        var so:SharedObject = getSO();
        var soData:Object = so.data;
        ensureShopNode(soData);
        soData[SAVE_KEY].shop.商城购物车 = _root.商城购物车;
        soData.商城购物车 = _root.商城购物车;
        flushSO(so, "shop_partial");
    }

    public function loadShopCart():Void {
        var soData:Object = getSO().data;
        var nestedShop:Object = (soData[SAVE_KEY] != undefined) ? soData[SAVE_KEY].shop : undefined;
        _root.商城购物车 = preferListLayer(soData.商城购物车,
                                          nestedShop != undefined ? nestedShop.商城购物车 : undefined,
                                          []);
    }

    public function saveShopPurchased():Void {
        var so:SharedObject = getSO();
        var soData:Object = so.data;
        ensureShopNode(soData);
        soData[SAVE_KEY].shop.商城已购买物品 = _root.商城已购买物品;
        soData.商城已购买物品 = _root.商城已购买物品;
        flushSO(so, "shop_partial");
    }

    public function loadShopPurchased():Void {
        var soData:Object = getSO().data;
        var nestedShop:Object = (soData[SAVE_KEY] != undefined) ? soData[SAVE_KEY].shop : undefined;
        _root.商城已购买物品 = preferListLayer(soData.商城已购买物品,
                                            nestedShop != undefined ? nestedShop.商城已购买物品 : undefined,
                                            []);
    }

    // ==================== Dirty 追踪 ====================

    /**
     * canonical 置位入口（R1 Slice 1）：所有持久化状态 mutator 的统一标脏 API。
     * 迁移期同时维护 _dirtyMark 与 _root.存档系统.dirtyMark 兼容镜像。
     * 幂等：只置位、绝不触发存盘；只有成功全量存盘（_doSaveAll 内 flush === true）才清。
     * 不得被当作"已请求存盘"或"已 durable"。
     */
    public function markDirty():Void {
        saveApiStats().ingress.markDirty++;
        recordSaveApiTrace("markDirty", null, "set");
        _dirtyMark = true;
        if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
    }

    /**
     * 安装 _root.存档系统 四层存档 API 委托（R1 Slice 1/2 逐层补全）。
     * 由 通信_lsy_原版存档系统.as 启动时同步调用一次；委托不闭包捕获实例，
     * 每次调用经 SaveManager.getInstance() 取单例，规避 asLoader 卸载闭包陷阱。
     * XFL 只引用 _root.存档系统.*，不直接引用 org.flashNight.* 类。
     */
    public function installSaveApiShims():Void {
        if (_root.存档系统 == undefined) _root.存档系统 = {};
        _root.存档系统.markDirty = function():Void {
            SaveManager.getInstance().markDirty();
        };
        _root.存档系统.requestSave = function(reason):Void {
            SaveManager.getInstance().requestSave(reason);
        };
        _root.存档系统.flushDurableNow = function(reason):Boolean {
            return SaveManager.getInstance().flushDurableNow(reason);
        };
        _root.存档系统.flushBeforeTransition = function(reason):Boolean {
            return SaveManager.getInstance().flushBeforeTransition(reason);
        };
    }

    public function isDirty():Boolean {
        return _dirtyMark;
    }

    /**
     * 无写副作用的全局待保存查询。
     * isDirty() 保留只读内部 latch 的历史语义；close/finalize 应使用本方法。
     * R1 Slice 1 补全：覆盖两个 dirty 镜像与设置/键位/药剂组/收件箱全部迁移 latch，
     * 四者同样只能由成功全量存盘清除。
     */
    public function hasPendingChanges():Boolean {
        return _dirtyMark || _root.存档系统.dirtyMark === true
            || _settingsMigrationPending
            || _drugLoadoutMigrationPending || _rewardInboxMigrationPending
            || KeyManager.hasPendingKeySettingsMigration();
    }

    // ==================== 迁移 ====================

    /**
     * 迁移存档数据。纯内存变换，不负责 flush。
     * 调用方（preload/loadAll）负责在 changed 时 syncTopLevel + flush。
     * @return 是否有变更
     */
    public function migrate(mydata:Object, soData:Object):Boolean {
        if (mydata == undefined) return false;
        _drugLoadoutSchemaRejected = false;
        _rewardInboxSchemaRejected = false;
        var changed:Boolean = false;
        var sm:ServerManager = ServerManager.getInstance();

        // Stage 1: unknown → 2.6（委托旧迁移函数）
        if (isNaN(mydata.version)) {
            sm.sendServerMessage("SaveManager: 将存档从未知版本更新至2.6");
            if (mydata[2] && !mydata.inventory) {
                _root.存档系统.convertInventory(mydata);
            }
            if (mydata.infrastructure == null) {
                mydata.infrastructure = {};
            }
            mydata.version = "2.6";
            changed = true;
        }

        // Stage 2: 2.6 → 2.7（委托旧迁移函数 + 修复：补上 version）
        if (mydata.version == "2.6") {
            sm.sendServerMessage("SaveManager: 将存档从2.6更新至2.7");
            _root.存档系统.convert_2_6(mydata);
            mydata.version = "2.7";
            changed = true;
        }

        // Stage 3: 2.7 → 3.0（归一化：拷贝顶层 key 到 mydata 内部）
        if (mydata.version == "2.7") {
            sm.sendServerMessage("SaveManager: 将存档从2.7更新至3.0");
            convert_2_7_to_3_0(mydata, soData);
            mydata.version = "3.0";
            changed = true;
        }

        var drugSchema:Object = normalizeDrugLoadoutSchema(mydata);
        if (!drugSchema.ok) {
            _drugLoadoutSchemaRejected = true;
            return changed;
        }
        if (drugSchema.changed) {
            _drugLoadoutMigrationPending = true;
            changed = true;
        }

        var rewardSchema:Object = RewardInboxService.normalizeSaveData(mydata);
        if (!rewardSchema.ok) {
            _rewardInboxSchemaRejected = true;
            return changed;
        }
        if (rewardSchema.changed) {
            _rewardInboxMigrationPending = true;
            changed = true;
        }

        // AMF0/JSON 往返把空数组磨成空对象 {}：结算持久态五个数组字段与
        // tasks_to_do / 宠物信息 内层空槽在此统一修复（详见各 normalizer 注释）。
        var settlementSchema:Object =
            org.flashNight.arki.scene.StageRunSession.normalizeSaveData(mydata);
        if (settlementSchema.changed) changed = true;
        if (normalizeTaskAndPetShapes(mydata)) changed = true;

        return changed;
    }

    /**
     * 双药剂组 affinity schema。全局存档版本保持 3.0；此方法同时供 SOL migrate 与
     * launcher snapshot / JSON shadow 的 _applyCore 使用。
     *
     * 无标记/旧标记只信任 0..3，防止容量 4 时代的越界 ghost 在扩到 8 后复活；
     * v2/v3 只信任 0..7。v3 affinity 由纯 normalizer 生成；未来版本 fail closed。
     */
    public function normalizeDrugLoadoutSchema(mydata:Object):Object {
        if (mydata == undefined || mydata.inventory == undefined
                || mydata.inventory.药剂栏 == undefined
                || typeof mydata.inventory.药剂栏 != "object") {
            return {ok:false, changed:false, error:"missing_drug_inventory"};
        }

        var changed:Boolean = false;
        if (mydata.ext == undefined || mydata.ext == null
                || typeof mydata.ext != "object") {
            mydata.ext = {};
            changed = true;
        }

        var feature:Object = mydata.ext.drugLoadout;
        var hasVersion:Boolean = feature != undefined && feature != null
            && feature.version != undefined;
        var version:Number = hasVersion ? Number(feature.version) : NaN;
        if (hasVersion && (isNaN(version) || Math.floor(version) != version)) {
            return {ok:false, changed:false, error:"invalid_drug_loadout_version"};
        }
        if (hasVersion && version > DrugSlotAffinityService.VERSION) {
            return {ok:false, changed:false, error:"future_drug_loadout_version"};
        }

        var legacy:Boolean = !hasVersion || version < 2;
        var maxExclusive:Number = legacy ? 4 : 8;
        var raw:Object = mydata.inventory.药剂栏;
        if (legacy || !hasOnlyCanonicalDrugSlots(raw, maxExclusive)) {
            var normalized:Object = {};
            for (var i:Number = 0; i < maxExclusive; i++) {
                var value:Object = raw[String(i)];
                if (value !== undefined) normalized[String(i)] = value;
            }
            mydata.inventory.药剂栏 = normalized;
            changed = true;
        }

        var normalizedFeature:Object = DrugSlotAffinityService.normalizeSavedFeature(
            feature, mydata.inventory.药剂栏, persistedDrugKeyValidator());
        if (normalizedFeature.ok !== true) {
            return {ok:false, changed:false, error:String(normalizedFeature.error)};
        }
        mydata.ext.drugLoadout = normalizedFeature.feature;
        if (normalizedFeature.changed === true) changed = true;
        return {ok:true, changed:changed,
            version:DrugSlotAffinityService.VERSION,
            diagnostics:normalizedFeature.diagnostics};
    }

    private static function persistedDrugKeyValidator():Function {
        return function(itemKey:String):Boolean {
            var data:Object = ItemUtil.getRawItemData(itemKey);
            return data != null && data.use === "药剂";
        };
    }

    private function hasOnlyCanonicalDrugSlots(raw:Object, maxExclusive:Number):Boolean {
        for (var key:String in raw) {
            var index:Number = Number(key);
            if (isNaN(index) || Math.floor(index) != index
                    || index < 0 || index >= maxExclusive
                    || String(index) != key) {
                return false;
            }
        }
        return true;
    }

    /**
     * AMF0/JSON 存档往返把空数组磨成空对象 {}：tasks_to_do 为空读回 {} 后
     * push/splice 静默失败（接/删/交任务丢操作）；宠物信息 内层空槽读回 {} 后
     * length==0 判空失效，空槽被当占用，买/领养报 slots_full。这里只把“空对象”
     * 修复为 []；带键非数组保持原样，交消费方按既有语义处理。字段集与 launcher
     * C# SaveMigrator.NormalizeTaskArray / NormalizePetSlot 的空槽修复对齐。
     * SOL migrate 与 Protocol 2 _applyCore 共用；返回是否有变更。
     */
    private function normalizeTaskAndPetShapes(mydata:Object):Boolean {
        var changed:Boolean = false;
        var tasks:Object = mydata.tasks;
        if (tasks != undefined && tasks != null && typeof tasks == "object") {
            var repairedTasks:Object = repairEmptyArrayShape(tasks.tasks_to_do);
            if (repairedTasks.changed) {
                tasks.tasks_to_do = repairedTasks.value;
                changed = true;
            }
        }
        var pets:Object = mydata.pets;
        if (pets != undefined && pets != null && typeof pets == "object"
                && pets.宠物信息 !== undefined) {
            var repairedPets:Object = repairPetsInfoShape(pets.宠物信息);
            if (repairedPets.changed) {
                pets.宠物信息 = repairedPets.info;
                changed = true;
            }
        }
        return changed;
    }

    /** 空对象 → [] 单值修复；带键非数组原样返回。 */
    private function repairEmptyArrayShape(value:Object):Object {
        if (value != null && typeof value == "object" && !(value instanceof Array)
                && isEmptyOwnObject(value)) {
            return {value:[], changed:true};
        }
        return {value:value, changed:false};
    }

    /**
     * 宠物信息 形状修复：整层被磨成空对象时恢复默认五槽空壳（与 C#
     * NormalizePetsInfo 补齐五槽对齐）；数组层的内层空槽空对象原地修复为 []。
     */
    private function repairPetsInfoShape(info:Object):Object {
        if (info == null || typeof info != "object") {
            return {info:info, changed:false};
        }
        if (!(info instanceof Array)) {
            if (isEmptyOwnObject(info)) return {info:defaultPetsInfo(), changed:true};
            return {info:info, changed:false};
        }
        var changed:Boolean = false;
        for (var i:Number = 0; i < info.length; i++) {
            var slot:Object = info[i];
            if (slot != null && typeof slot == "object" && !(slot instanceof Array)
                    && isEmptyOwnObject(slot)) {
                info[i] = [];
                changed = true;
            }
        }
        return {info:info, changed:changed};
    }

    private function isEmptyOwnObject(value:Object):Boolean {
        for (var key:String in value) return false;
        return true;
    }

    public function hasPendingDrugLoadoutMigration():Boolean {
        return _drugLoadoutMigrationPending;
    }

    public function hasPendingRewardInboxMigration():Boolean {
        return _rewardInboxMigrationPending;
    }

    /** focused fixture 使用；生产只由新存档边界或成功全量存盘清除。 */
    public function clearPendingRewardInboxMigration():Void {
        _rewardInboxMigrationPending = false;
        _rewardInboxSchemaRejected = false;
    }

    /** focused fixture 使用；生产只由新存档边界或成功全量存盘清除。 */
    public function clearPendingDrugLoadoutMigration():Void {
        _drugLoadoutMigrationPending = false;
        _drugLoadoutSchemaRejected = false;
    }

    /**
     * 2.7 → 3.0 迁移：将顶层 key 拷贝到 mydata 内部
     * 顶层 key 为 undefined 时用默认值
     */
    private function convert_2_7_to_3_0(mydata:Object, soData:Object):Void {
        if (mydata[3] == undefined || mydata[3] == null) {
            mydata[3] = 0;
        }
        if (mydata.tasks == undefined) {
            mydata.tasks = {
                tasks_to_do:          soData.tasks_to_do || [],
                tasks_finished:       soData.tasks_finished || {},
                task_chains_progress: buildMigratedTaskChainsProgress(soData.task_chains_progress, mydata[3])
            };
        }
        if (mydata.pets == undefined) {
            mydata.pets = {
                宠物信息:    soData.战宠 || [[], [], [], [], []],
                宠物领养限制: (soData.宠物领养限制 != undefined) ? soData.宠物领养限制 : 5
            };
        }
        if (mydata.shop == undefined) {
            mydata.shop = {
                商城已购买物品: soData.商城已购买物品 || [],
                商城购物车:    soData.商城购物车 || []
            };
        }
    }

    public function migrateAndSync(mydata:Object, soData:Object):Void {
        migrate(mydata, soData);
        if (_drugLoadoutSchemaRejected) {
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.migrateAndSync] future drugLoadout rejected; skip sync");
            return;
        }
        syncTopLevelFromMydata(mydata, soData);
    }

    public function syncTopLevelFromMydata(mydata:Object, soData:Object):Void {
        if (mydata == undefined) return;
        if (mydata.tasks != undefined) {
            ensureLegacyMainlineInTasks(mydata.tasks, mydata[3]);
            soData.tasks_to_do = mydata.tasks.tasks_to_do;
            soData.tasks_finished = mydata.tasks.tasks_finished;
            soData.task_chains_progress = mydata.tasks.task_chains_progress;
        }
        if (mydata.pets != undefined) {
            soData.战宠 = mydata.pets.宠物信息;
            soData.宠物领养限制 = mydata.pets.宠物领养限制;
        }
        if (mydata.shop != undefined) {
            soData.商城已购买物品 = mydata.shop.商城已购买物品;
            soData.商城购物车 = mydata.shop.商城购物车;
        }
    }

    private function buildMigratedTaskChainsProgress(source:Object, legacyMainValue:Object):Object {
        var result:Object = {};
        var key:String;
        if (source != undefined) {
            for (key in source) {
                result[key] = source[key];
            }
        }
        ensureLegacyMainlineInTasks({ task_chains_progress: result }, legacyMainValue);
        return result;
    }

    private function ensureLegacyMainlineInTasks(tasks:Object, legacyMainValue:Object):Void {
        if (tasks == undefined) return;
        if (tasks.task_chains_progress == undefined) {
            tasks.task_chains_progress = {};
        }
        var legacyMain:Number = Math.floor(Number(legacyMainValue));
        if (tasks.task_chains_progress.主线 == undefined && !isNaN(legacyMain)) {
            tasks.task_chains_progress.主线 = legacyMain;
        }
    }

    private function hasTaskEntries(value:Object):Boolean {
        if (value == undefined) return false;
        if (value.length != undefined) {
            return value.length > 0;
        }
        for (var key:String in value) {
            return true;
        }
        return false;
    }

    private function preferTaskLayer(primary:Object, fallback:Object, defaultValue:Object):Object {
        if (primary != undefined) {
            if (hasTaskEntries(primary) || fallback == undefined || !hasTaskEntries(fallback)) {
                return primary;
            }
        }
        if (fallback != undefined) return fallback;
        return defaultValue;
    }

    private function applyTaskBundleWithFallback(topData:Object, nestedTasks:Object, scope:String):Void {
        var nested:Object = (nestedTasks != undefined) ? nestedTasks : {};
        _root.tasks_to_do = preferTaskLayer(topData != undefined ? topData.tasks_to_do : undefined,
                                            nested.tasks_to_do, []);
        // 顶层 SO 与 mydata 嵌套层可能各自被 AMF0 磨出空对象，择优后对赢家兜底修复。
        _root.tasks_to_do = repairEmptyArrayShape(_root.tasks_to_do).value;
        _root.tasks_finished = preferTaskLayer(topData != undefined ? topData.tasks_finished : undefined,
                                               nested.tasks_finished, {});
        _root.task_chains_progress = preferTaskLayer(topData != undefined ? topData.task_chains_progress : undefined,
                                                     nested.task_chains_progress, {});
        ensureLegacyMainlineInTasks({ task_chains_progress: _root.task_chains_progress }, _root.主线任务进度);
        if (_root.tasks_to_do == undefined) _root.tasks_to_do = [];
        if (_root.tasks_finished == undefined) _root.tasks_finished = {};
        if (_root.task_chains_progress == undefined) _root.task_chains_progress = {};
        if (_root.task_chains_progress.主线 == undefined) {
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 主线任务链缺失且无法从 mydata[3] 回填");
        }
    }

    private function hasListEntries(value:Object):Boolean {
        return value != undefined && value.length != undefined && value.length > 0;
    }

    private function preferListLayer(primary:Object, fallback:Object, defaultValue:Object):Object {
        if (primary != undefined) {
            if (hasListEntries(primary) || fallback == undefined || !hasListEntries(fallback)) {
                return primary;
            }
        }
        if (fallback != undefined) return fallback;
        return defaultValue;
    }

    private function hasPetEntries(value:Object):Boolean {
        if (value == undefined || value.length == undefined) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var pet:Object = value[i];
            if (pet == undefined) continue;
            if (pet.length != undefined) {
                if (pet.length > 0) return true;
            } else if (hasTaskEntries(pet)) {
                return true;
            }
        }
        return false;
    }

    private function preferPetsInfoLayer(primary:Object, fallback:Object, defaultValue:Object):Object {
        if (primary != undefined) {
            if (hasPetEntries(primary) || fallback == undefined || !hasPetEntries(fallback)) {
                return primary;
            }
        }
        if (fallback != undefined) return fallback;
        return defaultValue;
    }

    private function defaultPetsInfo():Array {
        return [[], [], [], [], []];
    }

    private function applyPetsBundleWithFallback(topData:Object, nestedPets:Object, scope:String):Void {
        var nested:Object = (nestedPets != undefined) ? nestedPets : {};
        var topPets:Object = (topData != undefined) ? topData.战宠 : undefined;
        var nestedPetsInfo:Object = nested.宠物信息;
        var useTopPets:Boolean = topPets != undefined
            && (hasPetEntries(topPets) || nestedPetsInfo == undefined || !hasPetEntries(nestedPetsInfo));

        _root.宠物信息 = preferPetsInfoLayer(topPets, nestedPetsInfo, defaultPetsInfo());
        // 同上：内层空槽空对象兜底修复，避免空槽被 length 判空误当占用。
        _root.宠物信息 = repairPetsInfoShape(_root.宠物信息).info;
        if (useTopPets) {
            _root.宠物领养限制 = (topData != undefined && topData.宠物领养限制 != undefined)
                ? topData.宠物领养限制
                : (nested.宠物领养限制 != undefined ? nested.宠物领养限制 : 5);
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 宠物从顶层读取");
        } else if (nestedPetsInfo != undefined) {
            _root.宠物领养限制 = (nested.宠物领养限制 != undefined) ? nested.宠物领养限制 : 5;
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 顶层宠物为空，回退 mydata.pets");
        } else {
            _root.宠物领养限制 = (topData != undefined && topData.宠物领养限制 != undefined)
                ? topData.宠物领养限制
                : 5;
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 宠物用默认值");
        }
    }

    private function applyShopBundleWithFallback(topData:Object, nestedShop:Object, scope:String):Void {
        var nested:Object = (nestedShop != undefined) ? nestedShop : {};
        var topPurchased:Object = (topData != undefined) ? topData.商城已购买物品 : undefined;
        var topCart:Object = (topData != undefined) ? topData.商城购物车 : undefined;
        var nestedPurchased:Object = nested.商城已购买物品;
        var nestedCart:Object = nested.商城购物车;

        _root.商城已购买物品 = preferListLayer(topPurchased, nestedPurchased, []);
        _root.商城购物车 = preferListLayer(topCart, nestedCart, []);
        if (topPurchased != undefined && !hasListEntries(topPurchased) && hasListEntries(nestedPurchased)) {
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 顶层商城已购买物品为空，回退 mydata.shop");
        }
        if (topCart != undefined && !hasListEntries(topCart) && hasListEntries(nestedCart)) {
            ServerManager.getInstance().sendServerMessage("[SaveManager." + scope + "] 顶层商城购物车为空，回退 mydata.shop");
        }
    }

    // ==================== 设置/初始化 ====================

    public function packSettings():Object {
        var ws:WeatherSystem = WeatherSystem.getInstance();
        var sem:Object = _root.soundEffectManager;
        return {
            setGlobalVolume: sem.getGlobalVolume(),
            setBGMVolume: sem.getBGMVolume(),
            性能等级上限: _root.帧计时器.性能等级上限,
            是否阴影: _root.是否阴影,
            是否视觉元素: _root.是否视觉元素,
            cameraZoomToggle: _root.cameraZoomToggle,
            basicZoomScale: _root.basicZoomScale,
            开启昼夜系统: ws.enableDayNightCycle,
            暂停昼夜系统: ws.pauseDayNightCycle,
            使用滤镜渲染: ws.useFilterRendering,
            立绘类型: _root.立绘类型,
            jukeboxOverride: sem.getJukeboxOverride(),
            jukeboxTrueRandom: sem.getTrueRandom(),
            jukeboxPlayMode: sem.getPlayMode()
        };
    }

    public function applySettings(s:Object):Void {
        if (!s) return;
        if (!isNaN(s.setGlobalVolume)) _root.soundEffectManager.setGlobalVolume(s.setGlobalVolume);
        if (!isNaN(s.setBGMVolume)) _root.soundEffectManager.setBGMVolume(s.setBGMVolume);
        if (!isNaN(s.性能等级上限)) {
            var rawPerformance:Number = Number(s.性能等级上限);
            var cap:Number = Math.round(rawPerformance);
            cap = (cap >= 2) ? 1 : (cap < 0) ? 0 : cap;
            if (rawPerformance != cap) _settingsMigrationPending = true;
            _root.帧计时器.性能等级上限 = cap;
        }
        if (s.cameraZoomToggle || s.cameraZoomToggle === false) _root.cameraZoomToggle = s.cameraZoomToggle;
        if (!isNaN(s.basicZoomScale)) _root.basicZoomScale = s.basicZoomScale;
        if (s.是否阴影 || s.是否阴影 === false) _root.是否阴影 = s.是否阴影;
        if (s.是否视觉元素 || s.是否视觉元素 === false) _root.是否视觉元素 = s.是否视觉元素;
        var ws:WeatherSystem = WeatherSystem.getInstance();
        if (s.开启昼夜系统 || s.开启昼夜系统 === false) ws.enableDayNightCycle = s.开启昼夜系统;
        if (s.暂停昼夜系统 || s.暂停昼夜系统 === false) ws.pauseDayNightCycle = s.暂停昼夜系统;
        if (s.使用滤镜渲染 || s.使用滤镜渲染 === false) ws.useFilterRendering = s.使用滤镜渲染;
        if (s.立绘类型) _root.立绘类型 = s.立绘类型;
        var sem:Object = _root.soundEffectManager;
        if (s.jukeboxOverride || s.jukeboxOverride === false) sem.setJukeboxOverride(s.jukeboxOverride);
        if (s.jukeboxTrueRandom || s.jukeboxTrueRandom === false) sem.setTrueRandom(s.jukeboxTrueRandom);
        if (s.jukeboxPlayMode) sem.setPlayMode(s.jukeboxPlayMode);
    }

    /** 只读查询：设置读档归一是否仍未经过成功落盘。 */
    public function hasPendingSettingsMigration():Boolean {
        return _settingsMigrationPending;
    }

    /** 设置权威服务在读档外发现旧值时，通过同一 per-save latch 登记待持久化。 */
    public function markSettingsMigrationPending():Void {
        _settingsMigrationPending = true;
    }

    /** focused fixture 与权威存盘协调使用；生产清理由 _doSaveAll 成功分支负责。 */
    public function clearPendingSettingsMigration():Void {
        _settingsMigrationPending = false;
    }

    public function initInventory():Object {
        return {
            背包: new ArrayInventory(null, 50),
            装备栏: new EquipmentInventory(null),
            药剂栏: new DrugInventory(null, 8),
            仓库: new ArrayInventory(null, 1200),
            战备箱: new ArrayInventory(null, 400)
        };
    }

    public function initCollection():Object {
        return {
            材料: new DictCollection(null),
            情报: new InformationCollection(null)
        };
    }

    // ==================== SO 访问 ====================

    public function getSOData():Object {
        return getSO().data;
    }

    // ==================== Shadow 推送 ====================

    /**
     * 将 mydata 推送到 Launcher 做 shadow 备份。
     * 使用 fire-and-forget 模式：推送失败不影响 SOL 存盘结果。
     *
     * 实现要点：
     *   - 用 LiteJSON（无缓存）单独 stringify mydata，避免 FastJSON 缓存投毒
     *   - 手动拼外层 JSON 字符串，避免 sendTaskToNode 对深层嵌套对象二次 stringify
     *   - 直接调用 sendSocketMessage 发送，绕过 FastJSON 路径
     */
    private function pushShadow(sm:ServerManager, mydata:Object):Void {
        sm.sendServerMessage("[SaveManager] pushShadow enter");
        var dataJson:String = _jsonParser.stringify(mydata);
        if (dataJson == null || dataJson == "null") {
            sm.sendServerMessage("[SaveManager] shadow skipped: stringify returned " + dataJson);
            return;
        }
        sm.sendServerMessage("[SaveManager] shadow stringify ok, len=" + dataJson.length);

        // 手动拼装完整消息 JSON（外层结构简单，无需序列化器）
        var slot:String = _root.savePath;
        var msg:String = "{\"task\":\"archive\",\"payload\":{\"op\":\"shadow\",\"slot\":\"" + slot + "\",\"data\":" + dataJson + "}}";
        var ok:Boolean = sm.sendSocketMessage(msg);
        sm.sendServerMessage("[SaveManager] shadow sent slot=" + slot + " ok=" + ok);
    }

    private function pushShadowWithConfirm(sm:ServerManager, mydata:Object):Void {
        var stats:Object = savePhysicalStats();
        var dataJson:String = _jsonParser.stringify(mydata);
        if (dataJson == null || dataJson == "null") return;
        stats.jsonStringify++;
        stats.shadowDispatch++;
        sm.sendTaskWithCallback("archive",
            {op:"shadow", slot:_root.savePath, data:dataJson}, null,
            function(resp:Object):Void {
                sm.sendServerMessage("[SaveManager] shadow confirm: " + (resp.success == true));
            }
        );
    }

    // ==================== 私有方法 ====================

    /**
     * 与 ArchiveTask.SanitizeSlotName 对齐的槽位名规范化。
     * 非法字符（非 a-z A-Z 0-9 _ -）替换为 _。
     */
    private function sanitizeSlot(slot:String):String {
        if (slot == undefined || slot.length == 0) return "default";
        var result:String = "";
        var i:Number = 0;
        while (i < slot.length) {
            var c:Number = slot.charCodeAt(i);
            // a-z: 97-122, A-Z: 65-90, 0-9: 48-57, _: 95, -: 45
            if ((c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c == 45) {
                result += slot.charAt(i);
            } else {
                result += "_";
            }
            i++;
        }
        return (result.length == 0) ? "default" : result;
    }

    private function getSO():SharedObject {
        return SharedObject.getLocal(_root.savePath);
    }

    /**
     * flush SharedObject 并检查结果。
     * flush() 返回值：true=成功, "pending"=等待用户授权, false/其他=失败
     * 只有 true 才算成功落盘，"pending" 视为未完成（不清 dirtyMark）。
     */
    // lane 闭集：full / shop_partial / delete_tombstone / preload_tombstone / read_migration。
    // lane 只增不改：物理八分桶 flushAttempt/flushSuccess/flushPending/flushFalse 原样累计。
    private function flushSO(so:SharedObject, lane:String):Boolean {
        var stats:Object = savePhysicalStats();
        stats.flushAttempt++;
        var laneStats:Object = saveApiStats().flushLane[lane];
        if (laneStats == null) {
            ServerManager.getInstance().sendServerMessage(
                "[SaveManager.flushSO] unknown flush lane clamped to full: " + lane);
            laneStats = saveApiStats().flushLane.full;
        }
        laneStats.attempt++;
        var result:Object = _flushResultOverrideForTests !== undefined
            ? _flushResultOverrideForTests
            : so.flush();
        if (result === true) {
            stats.flushSuccess++;
            laneStats.success++;
            return true;
        }
        if (result == "pending") {
            stats.flushPending++;
            laneStats.pending++;
        } else {
            stats.flushFalse++;
            laneStats["false"]++;
        }
        var msg:String = (result == "pending")
            ? "SaveManager: flush pending (awaiting user authorization) for "
            : "SaveManager: flush failed (result=" + result + ") for ";
        ServerManager.getInstance().sendServerMessage(msg + _root.savePath);
        return false;
    }

    private function ensureShopNode(soData:Object):Object {
        if (soData[SAVE_KEY] == undefined) soData[SAVE_KEY] = {};
        if (soData[SAVE_KEY].shop == undefined) soData[SAVE_KEY].shop = {};
        return soData[SAVE_KEY].shop;
    }

    public function packTimestamp():String {
        var now:Date = new Date();
        var y:Number = now.getFullYear();
        var mo:Number = now.getMonth() + 1;
        var d:Number = now.getDate();
        var h:Number = now.getHours();
        var mi:Number = now.getMinutes();
        var s:Number = now.getSeconds();
        var pad:Function = function(n:Number):String {
            return (n < 10) ? "0" + n : String(n);
        };
        return y + "-" + pad(mo) + "-" + pad(d) + " " + pad(h) + ":" + pad(mi) + ":" + pad(s);
    }
}
