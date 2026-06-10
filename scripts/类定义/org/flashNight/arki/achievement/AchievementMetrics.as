/**
 * 文件：org/flashNight/arki/achievement/AchievementMetrics.as
 * 说明：成就系统经济计数器的【唯一记账入口】（设计：docs/成就系统-A轮-设计-2026-06-10.md §4.2/§4.3）。
 *
 * 12 个经济埋点站点（商城/物品栏/宠物/佣兵）统一调 record(metric, delta) 落账到
 * _root._saveExt.成就.cnt[metric]（随 mydata.ext 透传存档，SaveManager 零改动）。
 * 否决各站点直写 ext 或走 EventBus 记账：单一写入点保证白名单/isNaN 口径唯一，
 * 且 `AchievementMetrics.record(` 可 grep 审计全部埋点。
 *
 * 硬约束：
 *  - VALID 白名单 = economyCount 成就 counter 的唯一权威键集。
 *    tools/derive-achievement-catalog.js 直接正则解析本文件 VALID 块做校验（单源，禁 JS 副本）。
 *  - 本类只建 {v:1, cnt:{}} 骨架，绝不碰 base/unl/claimed——基线快照只归
 *    AchievementService.ensureInit()（禁过早拍基线红线，设计 D1）。
 */
class org.flashNight.arki.achievement.AchievementMetrics {

    // economyCount counter 白名单。derive-achievement-catalog.js 正则解析 buildValid 函数体，
    // 格式勿改：一行一键 v["键"] = true;（⚠Flash CS6 AS2 类编译器不接受对象字面量字符串键，
    // 帧脚本可以、类体不行——故用赋值式构建）。新增指标 = 此处加键 + 埋点站点调 record。
    public static var VALID:Object = buildValid();

    private static function buildValid():Object {
        var v:Object = {};
        v["商城结账次数"] = true;
        v["商城花费K点"] = true;
        v["商城领取次数"] = true;
        v["购买物品次数"] = true;
        v["购买花费金币"] = true;
        v["出售次数"] = true;
        v["出售所得金币"] = true;
        v["装备强化次数"] = true;
        v["装备进阶次数"] = true;
        v["配件安装次数"] = true;
        v["宠物领养次数"] = true;
        v["宠物领养花费金币"] = true;
        v["宠物进阶次数"] = true;
        v["宠物培养次数"] = true;
        v["佣兵雇佣次数"] = true;
        v["佣兵雇佣花费金币"] = true;
        return v;
    }

    /**
     * 记一笔经济计数。
     * @param metric VALID 白名单内的指标键；未知键丢弃（防 ext 无界键污染）
     * @param delta  增量；缺省/非法 → 1
     */
    public static function record(metric:String, delta:Number):Void {
        if (VALID == undefined) VALID = buildValid(); // 静态初始化次序兜底（AS2 静态 var 调静态方法的初始化时机不保证）
        if (VALID[metric] != true) {
            // 白名单守卫：有界键拍板的执行点。丢弃 + 服务器日志可审计（不 trace，asLoader 发布无 trace）
            var sm = org.flashNight.neur.Server.ServerManager.getInstance();
            if (sm != undefined && sm.isSocketConnected) {
                sm.sendServerMessage("[AchievementMetrics] 丢弃未知指标: " + metric);
            }
            return;
        }

        var d:Number = Number(delta);
        if (delta == undefined || isNaN(d)) d = 1;

        // 惰性建容器（照 PetPanelService 宠物购买次数范式；只建骨架，不碰 base/unl/claimed）
        if (_root._saveExt == undefined) _root._saveExt = {};
        var a:Object = _root._saveExt.成就;
        if (a == undefined) a = _root._saveExt.成就 = {v:1, cnt:{}};
        if (a.v == undefined) a.v = 1;
        if (a.cnt == undefined) a.cnt = {};

        var c:Number = Number(a.cnt[metric]);
        a.cnt[metric] = (isNaN(c) ? 0 : c) + d;

        _root.存档系统.dirtyMark = true;
    }
}
