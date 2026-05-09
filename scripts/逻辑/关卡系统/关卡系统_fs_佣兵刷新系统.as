import org.flashNight.arki.merc.*;

// ════════════════════════════════════════════════════════════════════════════
// 佣兵刷新系统帧脚本
// ════════════════════════════════════════════════════════════════════════════
// 业务逻辑下沉到 org.flashNight.arki.merc.* 四个类：
//   - MercLibrary     佣兵数据层 (bundle cache / 列表加载 / 表达式查询 / 价格)
//   - MercHybridizer  杂交器（纯函数化，hybridize 返回杂交副本）
//   - MercSpawner     场景刷新链（含 emergent throttle 文档化注释）
//   - ArenaController 决斗场 + 佣兵库请求（callback 风格，不再用全局回调槽）
//
// 本文件只保留：
//   1. _root 状态变量初始化（外部 XML 读写的公共数组、计数器）
//   2. _root.X 适配器包装器（保持外部可见 API 不变）
//
// Step 5 移除：
//   - _root.随机可雇佣兵           （Hybridizer 改为返回值，调用方持有临时单元素库）
//   - _root.战队信息数组 init      （MercLibrary.bundle 接管；XML loader 仍写但已废）
//   - _root.佣兵请求成功/失败/中回调 槽位（callback 风格替代）
//   - _root.补充佣兵 适配器        （内部 helper，零外部调用）
//   - _root._mercDataRefCount      （bundle 由 MercLibrary 持有，session 级缓存）
//   - _root.佣兵不足时出阵人员 / _root.佣兵不足时进入决斗场
//                                  （死路径：mercs_list 202 条 vs 同伴上限 5，
//                                   hasEnoughFor 数学上不可能 false）
// ════════════════════════════════════════════════════════════════════════════


// ─── MercHybridizer 适配器 ─────────────────────────────────────────────────
_root.佣兵杂交序号 = function(n, 杂交几率, 杂交许可) {
    return MercHybridizer.pickHybridIndex(n, 杂交几率, 杂交许可);
};
_root.随机生成杂交佣兵名 = function() {
    return MercHybridizer.randomHybridName();
};
_root.检查并返回有效佣兵名称 = function(佣兵名称) {
    return MercHybridizer.validateName(佣兵名称);
};
_root.佣兵杂交名称 = function(n, 杂交许可, 战队信息) {
    return MercHybridizer.hybridName(n, 杂交许可, 战队信息);
};
_root.杂交许可 = function(输入字符串) {
    return MercHybridizer.allowHybrid(输入字符串);
};
_root.装备杂交许可 = function(杂交装备, 装备杂交几率) {
    return MercHybridizer.allowEquipHybrid(杂交装备, 装备杂交几率);
};
// 注意：原 _root.杂交可雇佣兵 写入 _root.随机可雇佣兵，调用方再读。
// Step 5 后 hybridize 返回值；适配器把返回值重新装入 _root.随机可雇佣兵 维持旧 API。
_root.杂交可雇佣兵 = function(n, 杂交几率, 杂交许可) {
    _root.随机可雇佣兵 = [MercHybridizer.hybridize(n, 杂交几率, 杂交许可)];
};


// ─── MercSpawner 适配器 ────────────────────────────────────────────────────
_root.删佣兵 = function(佣兵ID) {
    return MercSpawner.removeMerc(佣兵ID);
};
_root.初始化佣兵编号缓存 = function() {
    MercSpawner.initIndexCache();
};
_root.更新佣兵编号缓存 = function() {
    MercSpawner.updateIndexCache();
};
_root.获取随机佣兵编号 = function(已上场佣兵编号) {
    return MercSpawner.pickRandomMercIndex(已上场佣兵编号);
};
_root.生成游戏世界佣兵 = function(添加佣兵函数, 机率, 是否门口) {
    MercSpawner.spawnInWorld(添加佣兵函数, 机率, 是否门口);
};
// emergent throttle 文档详见 MercSpawner.spawnAtGate 注释
_root.门口刷可雇用玩家 = function(几率) {
    MercSpawner.spawnAtGate(几率);
};
_root.场景刷可雇用玩家 = function(机率) {
    MercSpawner.spawnInScene(机率);
};
_root.场景随机有效位置 = function() {
    return MercSpawner.randomValidPosition();
};
_root.创建佣兵实体 = function(n, 杂交几率) {
    return MercSpawner.createMercData(n, 杂交几率);
};
_root.创建佣兵实体对象 = function(佣兵数据, X, Y) {
    return MercSpawner.createMercEntity(佣兵数据, X, Y);
};
_root.添加门口佣兵 = function(n, X, Y) {
    MercSpawner.addGateMerc(n, X, Y);
};
_root.添加场上佣兵 = function(n) {
    MercSpawner.addCourtMerc(n);
};


// ─── ArenaController 适配器 ────────────────────────────────────────────────
_root.进入决斗场 = function(出阵表) {
    ArenaController.enter(出阵表);
};
_root.决斗场关闭 = function() {
    ArenaController.close();
};
_root.竞技场随机对手选择 = function(条件) {
    ArenaController.pickRandom(条件);
};
_root.竞技场对手请求 = function(请求表达式) {
    ArenaController.requestOpponent(请求表达式);
};
_root.更新重用限制 = function() {
    ArenaController.bumpReuseLimit();
};

// 旧 4-参数签名映射到 callback 风格。失败/中回调可能为 undefined（callback 风格不强制）。
_root.请求佣兵 = function(请求内容, 成功回调, 失败回调, 请求中回调) {
    if (请求中回调) 请求中回调();
    ArenaController.requestMerc(请求内容, function(response) {
        if (response.success) {
            if (成功回调) 成功回调();
        } else {
            if (失败回调) 失败回调();
        }
    });
};
_root.请求新佣兵 = function(条件, 回调函数, 回调参数) {
    MercLibrary.loadMoreByExpression(条件, 回调函数, 回调参数);
};


// ─── MercLibrary 适配器（数据层） ──────────────────────────────────────────
_root.确认佣兵库 = function(请求内容) {
    return MercLibrary.hasEnoughFor(请求内容);
};
_root.表达式解析器 = function(条件) {
    return MercLibrary.parseExpression(条件);
};
_root.佣兵库查询 = function(条件) {
    return MercLibrary.query(条件);
};
// 注意：SaveManager 用 _root.载入新佣兵库数据(0,0,0,0,0) 作"触发完整重载"调用，
// 5 个参数（含 0 占位）保留兼容。MercLibrary.loadMore 不读前 3 个 numeric 参数。
_root.载入新佣兵库数据 = function(人数, 等级下限, 等级上限, 回调函数, 回调参数) {
    MercLibrary.loadMore(人数, 等级下限, 等级上限, 回调函数, 回调参数);
};
_root.计算佣兵金币价格 = function(等级) {
    return MercLibrary.calculatePrice(等级);
};


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
