import org.flashNight.arki.unit.*;

/**
 * ContainerSpec — 容器化 attachMovie 调用点的纯函数决定层
 *
 * 4 类容器（unarmed / weapon / skill / battleSkill）共享 attachMovie 模板：
 *   var linkageName = "<容器前缀>-" + <actionName>;
 *   var initObj     = <ContainerInitScratch.getXxx(container)>;
 *   var man         = unit.attachMovie(linkageName, "man", 0, initObj);
 *   if (man == undefined) { <fallback 策略>; }
 *
 * 本类抽出可纯函数化的两块：
 *   1) linkageName 字符串拼接（防止 4 处调用点散落 "技能容器-" / "战技容器-" / ... typo）
 *   2) missing symbol 时的 fallback 策略选择（abort vs silent_continue）
 *
 * 真正的 `unit.attachMovie(...)` 调用留在 5 处业务调用点，因为它依赖
 * MovieClip 实例方法语义，executor 测试需要 fake unit + attachMovie spy，
 * 那是独立工程（attachMovie 黑箱边界完整测试，参考 [[feedback-routing-runtime-adapter-surface]]
 * 的 frozen surface 思路）。本阶段只把"纯函数决定"部分集中。
 *
 * 字段对齐：以下 4 个 kind 与生产 attachMovie 调用点一一对应。
 * 任何新增容器都必须在此注册并扩展 ContainerSpecTest。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerSpec {

    // ════════════════════════════════════════════════════════════════════
    // Kind 标识（取自调用点业务语义，与 _root.<X>路由 字典名严格对齐）
    // ════════════════════════════════════════════════════════════════════
    public static var KIND_UNARMED:String      = "unarmed";
    public static var KIND_WEAPON:String       = "weapon";
    public static var KIND_SKILL:String        = "skill";
    public static var KIND_BATTLE_SKILL:String = "battleSkill";

    // ════════════════════════════════════════════════════════════════════
    // Linkage 前缀 — 与 Flash 库里 attachMovie 容器元件名严格对齐
    // ════════════════════════════════════════════════════════════════════
    public static var LINKAGE_PREFIX_UNARMED:String      = "空手攻击容器";
    public static var LINKAGE_PREFIX_WEAPON:String       = "兵器攻击容器";
    public static var LINKAGE_PREFIX_SKILL:String        = "技能容器";
    public static var LINKAGE_PREFIX_BATTLE_SKILL:String = "战技容器";

    // ════════════════════════════════════════════════════════════════════
    // Missing symbol fallback 策略
    //   ABORT            — attachMovie 失败时调用方直接 return，常见于空手/兵器
    //                      （misiing 通常是数据错配，让用户感知比静默失败好）
    //   SILENT_CONTINUE  — attachMovie 失败时调用方继续后续业务（man = undefined），
    //                      技能/战技当前用此策略 — 注意 handleFloat / bindEndCleanup
    //                      在 undefined man 上是 no-op safe，但隐式语义需后续审计
    // ════════════════════════════════════════════════════════════════════
    public static var FALLBACK_ABORT:String           = "abort";
    public static var FALLBACK_SILENT_CONTINUE:String = "silent_continue";

    /**
     * 拼出 attachMovie 用的 linkage 名："<前缀>-<actionName>"。
     */
    public static function buildLinkageName(kind:String, actionName:String):String {
        return getLinkagePrefix(kind) + "-" + actionName;
    }

    /**
     * Linkage 前缀查表。未知 kind 返回 undefined（让调用方早爆而非静默写错）。
     */
    public static function getLinkagePrefix(kind:String):String {
        if (kind === KIND_UNARMED)      return LINKAGE_PREFIX_UNARMED;
        if (kind === KIND_WEAPON)       return LINKAGE_PREFIX_WEAPON;
        if (kind === KIND_SKILL)        return LINKAGE_PREFIX_SKILL;
        if (kind === KIND_BATTLE_SKILL) return LINKAGE_PREFIX_BATTLE_SKILL;
        return undefined;
    }

    /**
     * Missing symbol fallback 策略查表。documents 现状，不强制 unify。
     *   unarmed / weapon → ABORT
     *   skill / battleSkill → SILENT_CONTINUE
     */
    public static function getMissingFallback(kind:String):String {
        if (kind === KIND_UNARMED)      return FALLBACK_ABORT;
        if (kind === KIND_WEAPON)       return FALLBACK_ABORT;
        if (kind === KIND_SKILL)        return FALLBACK_SILENT_CONTINUE;
        if (kind === KIND_BATTLE_SKILL) return FALLBACK_SILENT_CONTINUE;
        return undefined;
    }

    /**
     * 4 kind 集合，便于测试遍历 + 防止注册漏。
     */
    public static function allKinds():Array {
        return [KIND_UNARMED, KIND_WEAPON, KIND_SKILL, KIND_BATTLE_SKILL];
    }
}
