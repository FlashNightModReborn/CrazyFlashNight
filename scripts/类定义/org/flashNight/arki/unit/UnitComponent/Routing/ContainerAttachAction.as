import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * ContainerAttachAction — 容器化 attachMovie 5 调用点的高层 adapter
 *
 * 把"linkage 拼接 + RoutingRuntime.attachMovie + missing symbol fallback 决议"
 * 这条样板流程集中到一处，5 个生产调用点只剩下：
 *
 *   var result:Object = ContainerAttachAction.attach(unit, kind, actionName, initObj);
 *   if (result.status === ContainerAttachAction.STATUS_MISSING_ABORT) {
 *       return ...;                  // 兵器 / 空手 路径
 *   }
 *   var man:MovieClip = result.man;  // 技能 / 战技 容忍 undefined（handleFloat / bindEndCleanup no-op safe）
 *
 * 返回值约定：
 *   { man, linkage, status }
 *     - man:MovieClip|undefined  — RoutingRuntime.attachMovie 的返回
 *     - linkage:String           — ContainerSpec.buildLinkageName 输出（便于诊断）
 *     - status:String            — 见下方 STATUS_* 常量
 *
 * status 由 ContainerSpec.getMissingFallback(kind) 决定：
 *   man != undefined                                 → STATUS_OK
 *   man == undefined ∧ fallback === ABORT            → STATUS_MISSING_ABORT
 *   man == undefined ∧ fallback === SILENT_CONTINUE  → STATUS_MISSING_SILENT_CONTINUE
 *   man == undefined ∧ fallback 未注册               → STATUS_MISSING_ABORT（防御退化）
 *
 * 设计依据：
 *   - 低层 attachMovie 注入面在 RoutingRuntime（[[feedback-routing-runtime-adapter-surface]] frozen surface）
 *   - missing fallback 现状已经被 ContainerSpec.getMissingFallback 纯函数化，本类只做装配
 *   - 第三阶段 MockMovieClip 端到端测试通过 RoutingRuntime.setAttachMovieAdapterForTest 注入
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerAttachAction {

    public static var STATUS_OK:String                       = "ok";
    public static var STATUS_MISSING_ABORT:String            = "missing_abort";
    public static var STATUS_MISSING_SILENT_CONTINUE:String  = "missing_silent_continue";

    /**
     * 容器化 attachMovie 入口 — 5 个调用点统一通道。
     *
     * @param unit       untyped    attachMovie 的 parent（兵器/空手/技能/战技容器都挂在 unit 下）；
     *                              生产路径传 MovieClip，testloader 传 fake unit object，故 untyped
     * @param kind       :String    ContainerSpec.KIND_* 之一
     * @param actionName :String    招式名（动作名 / 技能名 / 兵器攻击名）
     * @param initObj    :Object    attachMovie 的 initObject（由各路由的 ContainerInitScratch 装配）
     * @return :Object              { man, linkage, status }
     */
    public static function attach(unit, kind:String, actionName:String, initObj:Object):Object {
        var linkage:String = ContainerSpec.buildLinkageName(kind, actionName);
        var man:MovieClip = RoutingRuntime.attachMovie(unit, linkage, "man", 0, initObj);

        var result:Object = {};
        result.man = man;
        result.linkage = linkage;

        if (man != undefined) {
            result.status = STATUS_OK;
            return result;
        }

        var fb:String = ContainerSpec.getMissingFallback(kind);
        if (fb === ContainerSpec.FALLBACK_SILENT_CONTINUE) {
            result.status = STATUS_MISSING_SILENT_CONTINUE;
        } else {
            // ABORT 或未注册 kind 都退到 ABORT（防御 ContainerSpec 漏注册）
            result.status = STATUS_MISSING_ABORT;
        }
        return result;
    }
}