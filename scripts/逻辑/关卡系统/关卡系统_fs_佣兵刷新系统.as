
// ════════════════════════════════════════════════════════════════════════════
// 佣兵刷新系统帧脚本
// ════════════════════════════════════════════════════════════════════════════
// 业务逻辑全部下沉到 org.flashNight.arki.merc.*：
//   - MercLibrary     数据层 (bundle cache / 列表加载 / 表达式查询 / 价格)
//   - MercHybridizer  杂交器（纯函数化，hybridize 返回杂交副本）
//   - MercSpawner     场景刷新链（单步赤字驱动 + frame 29 周期触发）
//   - ArenaController 决斗场 + 佣兵库请求（callback 风格）
//   - MercBudget      驻留预算（sqrt 密度模型 + 遥测）
//   - MercCensus      场上人员普查（只读）
//
// 本文件只保留：
//   1. _root 状态变量初始化（外部 XML 读写的数组 / 计数器）
//   2. 真有外部 XML / SaveManager / 其他帧脚本调用的 _root.X 适配器
//
// 新代码请直接调类静态方法，不要再写 _root.X 包装。
// 调试 / 标定 入口（场上佣兵人数 / 佣兵预算 / 佣兵遥测 等）已移除——
// 需要时直接在 console 调 MercCensus.dump() / MercBudget.targetAlive() /
// MercBudget.telemetryEnabled = true。
// ════════════════════════════════════════════════════════════════════════════


// ─── _root 状态初始化 ─────────────────────────────────────────────────────
// 这些数组/计数器被外部 XML 直接读写，初始化在帧脚本里以保证启动时存在。
_root.可雇佣兵 = [];
_root.隐藏的可雇佣兵 = [];
_root.杂交佣兵几率 = 50;
_root.竞技场佣兵重用基数 = 2;
_root.当前佣兵重用数 = 0;
_root.重用基数成长率 = 2;
_root.出阵人员 = [];
_root.生成佣兵计数 = 0;


// ─── 外部调用入口 ─────────────────────────────────────────────────────────

// Symbol 889 / 997 / 914（卸下佣兵 UI）
_root.删佣兵 = function(佣兵ID) {
    return MercSpawner.removeMerc(佣兵ID);
};

// Symbol 2396 frame 29：周期门口刷新触发器（random(几率)==0 已在 frame 内做）。
// 几率参数已废弃但保留签名兼容旧 site。
_root.门口刷可雇用玩家 = function(几率) {
    MercSpawner.spawnAtGate(几率);
};

// 关卡系统_lsy_add2map_加载背景：场景加载时 Initial 进场批量。
// 数量 = XML Initial 字段（语义现在是"尝试数"，受 MercBudget 上限收敛）。
_root.场景刷可雇用玩家 = function(数量) {
    MercSpawner.spawnInScene(数量);
};

// 关卡系统_lsy_非人形佣兵刷新系统：复用场景碰撞箱避让。
_root.场景随机有效位置 = function() {
    return MercSpawner.randomValidPosition();
};

// 角斗场选择界面.xml：玩家退出决斗场。
_root.决斗场关闭 = function() {
    ArenaController.close();
};

// Symbol 3394：决斗场对手抽签。
_root.竞技场对手请求 = function(请求表达式) {
    ArenaController.requestOpponent(请求表达式);
};

// SaveManager.as ×3：以 (0,0,0,0,0) 调用作"触发完整重载"。
// 前 3 参数无意义，5 参签名保留兼容外部调用方。
_root.载入新佣兵库数据 = function(人数, 等级下限, 等级上限, 回调函数, 回调参数) {
    MercLibrary.refreshPool(回调函数, 回调参数);
};
