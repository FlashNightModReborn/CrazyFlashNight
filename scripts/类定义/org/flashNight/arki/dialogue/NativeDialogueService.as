import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.dialogue.NativeDialogueAppearance;

/**
 * =============================================================================
 *  NativeDialogueService — native_dialogue 无头对白会话服务（AS2 权威侧）
 * -----------------------------------------------------------------------------
 *  wire v2 契约（权威文本：docs/对白权威迁移-wire-v2协议与分期立项-2026-09-16.md
 *  v3 §4；v1 契约见 docs/对话框迁移与高清立绘治理-调研与施工准备-2026-09-12.md）：
 *
 *  能力握手（§4.1）：C# 每连接代经 ready-push 下发 {task:"dialogue_caps",
 *    modes:["snapshot","book"]}，ServerManager.onSocketData 专用分支调
 *    applyCaps()。闩按 socket generation 作用域（记录闩定时刻的 xmlSocket
 *    身份），onTransportDisconnected 先清闩再收口；未见本代 caps 不发 book。
 *    wireMode 按会话闩于 beginSession：本代 caps 含 "book" 且未 forceSnapshot
 *    → "v2"，否则 "v1"；v1 起头终身 v1，配置只影响新会话。
 *
 *  AS2→C# v2 帧（§4.2，task="native_dialogue"）：
 *    book   {version:2, op:"book", kind:"inline", requestId, sceneId, mode,
 *            epoch:1, startIndex:0, advanceKey?, lines:[{name,title,text,
 *            portrait:{kind:"static"|"doll",key,expression,appearance?},
 *            imageAction:"keep"|"show"|"clear",imagePath}]}
 *    append {version:2, op:"append", requestId, sceneId, baseEpoch, epoch,
 *            lines:[...], restartIndex:0}——发送前 s.epoch++，不等 C# ack；
 *            baseEpoch=递增前值，epoch=递增后值，restartIndex 维持"回第 0 句"
 *    set    {version:2, op:"set", requestId, sceneId, advanceKey}
 *            ——白名单字段低频变更，不动行集、不 bump epoch
 *    status {version:2, op:"status", requestId, sceneId, queryEpoch}
 *            ——mutation 应答超时后的只读裁决查询
 *    hide   v2 会话带 version:2，字段与 v1 同形（墓碑语义不变）
 *
 *  行物化：row==null → 跳过；char 缺失按 "" 处理 → portrait 落空静态槽
 *    {kind:"static",key:""}；规范化后空集 → 不发 book 直接 finishSession
 *    （孤儿 hide，与发送失败兜底同形）。name/title/text/portrait/imageAction/
 *    imagePath/advanceKey 物化与 v1 sendLine 同源（"角色名" 特判在物化期）。
 *    规范化行数 rowCount = 跳过 null 后的行数，是 finish.finalIndex 校验
 *    基准；ack/status 回执带 rowCount 时以 Host 裁决值回填。
 *
 *  mutation 确认（§4.3/§4.4）：book/append/set/status 一律走
 *    sendTaskWithCallback；异步应答先过五元校验——连接代（send 时刻
 *    xmlSocket 身份）+ 会话对象 + requestId + sceneId + 操作代际
 *    （pending seq / epoch），任一不符即忽略（旧 callback 不得撞新会话）。
 *    status:"applied" → 清该代际 pending 并补采用效果；"rejected" → 失败
 *    分类：set 恢复上一个有效 advanceKey 且不结束剧情，book 首次采用前
 *    降级到新 rid 的 v1 会话；append 同样移交全部内容与冻结立绘，
 *    保留 stage 义务且移交期间不发布事件。callback 超时 → 发 status 查询：
 *    查询冻结 maxOpSeq，只裁决此前发送的操作；超时操作保留至确认，
 *    旧代 rowCount 不覆盖后发追加。appliedEpoch 足够 → 补确认，否则回退；
 *    仍未知（无应答/会话已变/查询自身超时）→ 保留托管，绝不
 *    finishSession 伪装玩家已结束——连接故障由既有断线兜底收口。
 *
 *  终态（§4.5/§4.6）：C#→AS2 只收 verb:"finish"（requestId+sceneId+
 *    epoch+finalIndex+reason）。epoch 缺失/非整数/未来 → 拒绝；
 *    epoch < s.epoch → 拒绝旧终态（不释放 claim、不 publish、不补播）；
 *    epoch 相等且 finalIndex 合法（advance_past_end 须 = rowCount-1，
 *    close 须在 [0,rowCount-1]）→ finishSession 原顺序提交。
 *    对已提交过的旧 finish：requestId 命中 _recentFinished → 只重发匹配
 *    hide，绝不二次 publish（hide 丢失后 Host closing 依赖它收口）。
 *
 *  业务门禁（§4.6）：wire finish 走 ServerManager.handleGameCommand 既有
 *    rewardPending 门（未决奖励候选吞命令，C# closing 按冻结请求重试），
 *    到达 handleV2Action 的合法 finish 已过门禁、直接提交。**新增内部收口
 *    路径不得绕门禁**：空集 book、v1 回退通道也不可达等触发终态时，
 *    若 SaveManager.hasRewardCommitPending() 为真，落会话内 awaitingCommit
 *    标志（kind+epoch），待 pending 解除（ServerManager 帧泵逐帧调用
 *    tryAwaitingCommit）重新核验会话身份与 epoch 后再提交；epoch 已推进
 *    则丢弃旧义务。teardown/cancel/断线撤销义务（标志随会话销毁）。
 *    既有直接收口路径政策不变——断线兜底、facade 关闭、v1 sendLine 失败、
 *    advance 到尾仍直接 finishSession（既有政策差异显式保留）。
 *
 *  v1 契约（保留的回退协议）：
 *    出向：sendTaskToNode("native_dialogue", payload, null)
 *      payload: {version:1, op:"show"|"hide", requestId:"nd:<正整数>", sceneId,
 *                revision:Number(同请求严格递增), lineIndex(0 起), lineCount,
 *                name, title, text,
 *                portrait:{kind:"static"|"doll", key, expression, appearance},
 *                imageAction:"keep"|"show"|"clear", imagePath, advanceKey?,
 *                prefetch?:{portrait:同上结构, imageAction:"show", imagePath}}
 *      prefetch 可选，仅下一句存在时附加；下一句无立绘（key==""）不挂
 *      portrait，下一句配图非显式换新（keep/clear）不挂 imageAction/
 *      imagePath，两者皆无则 prefetch 不挂。Host 软解析，畸形整体丢弃。
 *      hide 只需 requestId+sceneId 匹配；hide 后同一 requestId 不得再 show。
 *    入向：_root.gameCommands["nativeDialogueAction"]({task:"cmd",
 *          action:"nativeDialogueAction", requestId, sceneId, revision,
 *          verb:"advance"|"close"})。Host 只发动词，不执行剧情/奖励。
 *
 *  语义（v1/v2 共用）：
 *    - AS2 权威持有句序、人物、暂停责任与 finish/cancel；v2 会话中普通
 *      换句由 C# 本地驱动，advance() 与 facade 下一句 均为 no-op（零 wire）。
 *    - 普通/任务对白不新增暂停；StageEvent 剧情对白经 beginStage() 持有
 *      PauseManager claim（OR 语义，见 PauseManager 头注释）。
 *    - finish（显式结束/末行 advance/发送失败兜底）：terminal→清 followingEvent
 *      →清会话→释放 claim→发 hide→最后才 publish 后续事件（重入安全，
 *      事件处理器再开对话时旧会话已不可见）。
 *    - cancel（场景取消/覆盖/compat 关闭）：terminal→清 followingEvent→释放
 *      claim→发 hide；绝不 publish。
 *    - followingEvent 永远只能由本服务在 finish 路径消费一次。
 *    - 临时失焦/Web 面板遮挡不发 hide（Host 侧 NativeHud 整体 Suspend）。
 *
 *  兼容面：
 *    _root.对话框界面 换成普通 Object facade（见 ensureCompat）；旧 authored
 *    MovieClip 由 初始化对话框界面 停住隐藏，AVM1 同路径重绑会重跑该初始化
 *    自动回到 facade。TaskPanelService 的 _visible 影子是惰性字段，不驱动会话。
 * =============================================================================
 */
class org.flashNight.arki.dialogue.NativeDialogueService {

    private static var _installed:Boolean = false;
    private static var _reqSeq:Number = 0;

    // 会话：{requestId, sceneId, revision, lines:Array, portraits:Array,
    //        index:Number, mode:"ordinary"|"stage", leaseId:String|null,
    //        followingEvent:Object|null, terminal:Boolean,
    //        wire:"v1"|"v2", epoch:Number, rowCount:Number,
    //        opSeq:Number, pendingOps:Object, bookSettled:Boolean,
    //        setPending:Boolean, statusQuery:Object|undefined,
    //        advanceKey, desiredAdvanceKey,
    //        awaitingCommit:{epoch,kind}|null（§4.6 等待业务提交义务）}
    private static var _session:Object = null;

    // _root.对话框界面 facade（普通 Object，持于 _root.__nativeDialogueCompat）
    private static var _compat:Object = null;

    // 装到旧 MC 上的关闭桩：只做本地停住隐藏；持引用供 cancelActive 识别，
    // 防止 MC 分支回调桩自身造成无限递归。
    private static var _clipCloseStub:Function = null;

    // wire v2 caps 闩：modes 字典 + 闩定时刻的连接身份（sm.xmlSocket 对象），
    // 按 socket generation 作用域；null/undefined = 本代未见 caps。
    private static var _capsModes:Object = null;
    private static var _capsConn:Object = undefined;

    // true → 新会话强制 v1 快照路径；只在 beginSession 闩定时刻读取，
    // 不改变活跃会话的 wireMode。
    public static var forceSnapshot:Boolean = false;

    // mutation 应答墙钟期限（毫秒；ServerManager.sendTaskWithCallback 按
    // getTimer 实际时间差判定，非帧计数）。
    private static var MUTATION_ACK_TIMEOUT_MS:Number = 3000;

    // 已发送过 hide 的会话墓碑：旧 finish 凭它只补发匹配 hide、绝不二次
    // publish；容量有界 FIFO（requestId 单调发号，远超窗口的旧 rid 自然淘汰）。
    private static var _recentFinished:Array = [];
    private static var RECENT_FINISHED_MAX:Number = 16;

    // ── 安装 ────────────────────────────────────────────────────

    /** 幂等安装：场景 teardown 订阅 + cmd 路由 + facade 就位 + 改键传播钩子。 */
    public static function install():Void {
        if (_installed) return;
        _installed = true;
        NativeInteractionContext.install();
        NativeInteractionContext.onSceneTeardown(onSceneTeardown);
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["nativeDialogueAction"] = function(params:Object):Void {
            org.flashNight.arki.dialogue.NativeDialogueService.handleAction(params);
        };
        // v2 低频变更入口：互动键被改写时尝试向 v2 会话发 set。
        // _root.watch 每属性仅一个槽位——他方如需占用请合并回调，勿覆盖。
        _root.watch("互动键", function(prop:String, oldVal, newVal) {
            org.flashNight.arki.dialogue.NativeDialogueService
                .notifyAdvanceKeyChanged(newVal);
            return newVal;
        });
        // §4.6 待提交义务由 ServerManager 帧泵每帧调用 tryAwaitingCommit 冲刷；
        // 不在 PauseManager 订阅回调里收口——claim 释放嵌套在暂停 watch 分发内
        // 会被外层折叠回 true（暂停卡死），必须离开 watch 上下文执行。
        ensureCompat();
    }

    public static function isInstalled():Boolean {
        return _installed;
    }

    /** 测试/诊断只读观测面：活动会话的浅快照或 null；不暴露可变内部引用。 */
    public static function getSessionSnapshot():Object {
        var s:Object = _session;
        if (s == null) return null;
        var pendingCount:Number = 0;
        if (s.pendingOps != null) {
            for (var k:String in s.pendingOps) pendingCount++;
        }
        return {
            requestId: s.requestId, sceneId: s.sceneId, revision: s.revision,
            index: s.index, lineCount: s.lines.length, mode: s.mode,
            terminal: s.terminal,
            wire: s.wire, epoch: s.epoch, rowCount: s.rowCount,
            bookSettled: s.bookSettled === true,
            setPending: s.setPending === true,
            pendingCount: pendingCount,
            advanceKey: s.advanceKey,
            awaitingCommit: s.awaitingCommit != null
        };
    }

    // ── wire v2：caps 闩 ────────────────────────────────────────

    /**
     * 本连接代的能力下发（ServerManager.onSocketData 的 dialogue_caps 分支调用）。
     * 闩按 socket generation 作用域：记录闩定时刻的 xmlSocket 对象身份；
     * 连接代轮换由 onTransportDisconnected 清闩，新代须重新下发才认。
     */
    public static function applyCaps(modes:Array):Void {
        var set:Object = {};
        if (modes != null) {
            for (var i:Number = 0; i < modes.length; i++) {
                set[String(modes[i])] = true;
            }
        }
        _capsModes = set;
        var sm:Object = _root.server;
        _capsConn = (sm != undefined) ? sm.xmlSocket : undefined;
    }

    /** 本连接代是否被授权 book；未见本代 caps / 无连接身份可核对 → false。 */
    private static function capsAllowsBook():Boolean {
        if (_capsModes == null || _capsModes["book"] !== true) return false;
        var sm:Object = _root.server;
        var conn:Object = (sm != undefined) ? sm.xmlSocket : undefined;
        // 拿不到连接身份就无法核对代际，fail-closed 回 v1
        return conn !== undefined && conn !== null && conn === _capsConn;
    }

    // ── 会话入口 ────────────────────────────────────────────────

    /**
     * 两个数组赋值入口的服务路由（对话文本.as 调用）。
     * @param rows      已归一化 7 元组行数组
     * @param overwrite true=覆盖（旧会话作废，不消费其 followingEvent）
     * @return 恒 true：服务一旦安装即接管，不走 legacy MovieClip 路径
     */
    public static function handleAssign(rows:Array, overwrite:Boolean):Boolean {
        install();
        tryAwaitingCommit();   // 入向活动顺带核验待提交义务（§4.6）
        if (rows == null) return true;
        if (_session != null && !_session.terminal) {
            if (overwrite === true) {
                // 旧 MovieClip 覆盖正文仍保留剧情后续；移交暂停责任，避免覆盖吞事件。
                if (_session.mode == "stage") {
                    var follow:Object = _session.followingEvent;
                    var leaseId:String = _session.leaseId;
                    _session.leaseId = null;
                    cancelSession("replace_stage_text");
                    beginSession(rows, "stage", follow, leaseId);
                    return true;
                }
                cancelSession("overwrite");
            } else {
                var s:Object = _session;
                var incomingPortraits:Array = capturePortraits(rows);
                for (var i:Number = 0; i < rows.length; i++) {
                    s.lines.push(rows[i]);
                    s.portraits.push(incomingPortraits[i]);
                }
                if (s.wire == "v2") {
                    // 连续代际追加：发送前推进 epoch（不等 C# ack）；
                    // restartIndex 维持"回第 0 句"语义，规范化行数按跳过 null 后累计。
                    var appended:Array = materializeLines(rows, incomingPortraits);
                    var base:Number = s.epoch;
                    s.epoch = base + 1;
                    s.rowCount += appended.length;
                    s.index = 0;
                    syncCompat();
                    var frame:Object = {
                        version: 2, op: "append",
                        requestId: s.requestId, sceneId: s.sceneId,
                        baseEpoch: base, epoch: s.epoch,
                        lines: appended, restartIndex: 0
                    };
                    if (!sendMutation(s, "append", frame, s.epoch, undefined)) {
                        replaceWithSnapshot(s, "append_send_failed", 0);
                    }
                } else {
                    // 旧入口追加数组后回到第 0 句；保持其行为，并递增 revision 拒绝旧行输入。
                    if (!sendLine(0)) finishSession();
                }
                return true;
            }
        }
        beginSession(rows, "ordinary", null);
        return true;
    }

    /**
     * StageEvent 剧情对白：AS2 侧持有可释放的暂停责任（claim），
     * followingEvent 只在显式 finish 时消费一次。
     * @param rawRows parseSingleDialogue 产出的原始行对象数组
     *        （{name,title,char,text,target,imageurl}），本函数内经
     *        _root.组装单次对话 归一化为 7 元组。
     */
    public static function beginStage(rawRows:Array, followingEvent:Object):Void {
        install();
        if (_session != null && !_session.terminal) cancelSession("superseded");
        var rows:Array = null;
        if (rawRows != null && rawRows.length > 0
                && typeof _root.组装单次对话 == "function") {
            rows = _root.组装单次对话(rawRows);
        }
        if (rows == null || rows.length == 0) {
            // 空对白不能软锁关卡：直接按 finish 语义消费一次后续事件
            publishFollow(followingEvent);
            return;
        }
        beginSession(rows, "stage", followingEvent);
    }

    // ── Host 入向动词 ───────────────────────────────────────────

    public static function handleAction(params:Object):Void {
        if (params == null) return;
        if (params.action != "nativeDialogueAction") return;
        tryAwaitingCommit();   // 入向命令顺带核验待提交义务（§4.6）
        var s:Object = _session;
        if (s != null && !s.terminal
                && params.requestId === s.requestId
                && params.sceneId === s.sceneId) {
            if (s.wire == "v2") {
                handleV2Action(s, params);
                return;
            }
            // v1：requestId+sceneId+revision 三重校验，advance/close 动词
            if (params.revision !== s.revision) return;
            if (params.verb == "advance") {
                advance();
            } else if (params.verb == "close") {
                finishSession();
            }
            return;
        }
        // 非活跃会话：已提交过的旧 finish 只补发匹配 hide，绝不二次 publish
        if (params.verb == "finish") resendFinishedHide(params);
    }

    /**
     * v2 终态线性化裁决：verb 只收 "finish"；epoch 缺失/非整数/未来 → 拒绝；
     * epoch < 会话 epoch → 拒绝旧终态（不放 claim、不 publish、不补播）；
     * epoch 相等且 finalIndex 合法 → finishSession 原顺序提交。
     */
    private static function handleV2Action(s:Object, params:Object):Void {
        if (params.verb != "finish") {
            trace("[NativeDialogueService] v2 reject: verb=" + params.verb);
            return;
        }
        var e = params.epoch;
        if (typeof e != "number" || isNaN(e) || e != Math.floor(e)) {
            trace("[NativeDialogueService] v2 finish reject: bad epoch " + e);
            return;
        }
        if (e < s.epoch) {
            trace("[NativeDialogueService] v2 finish reject: stale epoch "
                + e + " < " + s.epoch);
            return;
        }
        if (e > s.epoch) {
            trace("[NativeDialogueService] v2 finish reject: future epoch "
                + e + " > " + s.epoch);
            return;
        }
        var fi = params.finalIndex;
        var fiInt:Boolean = (typeof fi == "number" && !isNaN(fi)
            && fi == Math.floor(fi));
        var reason:String = params.reason;
        if (reason == "advance_past_end") {
            if (!fiInt || fi != s.rowCount - 1) {
                trace("[NativeDialogueService] v2 finish reject: finalIndex "
                    + fi + " != rowCount-1 " + (s.rowCount - 1));
                return;
            }
        } else if (reason == "close") {
            if (!fiInt || fi < 0 || fi >= s.rowCount) {
                trace("[NativeDialogueService] v2 finish reject: close finalIndex "
                    + fi + " out of [0," + (s.rowCount - 1) + "]");
                return;
            }
        } else {
            trace("[NativeDialogueService] v2 finish reject: unknown reason "
                + reason);
            return;
        }
        finishSession();
    }

    /** 旧 rid 的 finish：命中墓碑则补发匹配 hide（不重放事件/不放 claim）。 */
    private static function resendFinishedHide(params:Object):Void {
        for (var i:Number = 0; i < _recentFinished.length; i++) {
            var rec:Object = _recentFinished[i];
            if (rec.requestId === params.requestId) {
                if (rec.sceneId === params.sceneId) {
                    send({
                        version: (rec.wire == "v2") ? 2 : 1,
                        op: "hide",
                        requestId: rec.requestId,
                        sceneId: rec.sceneId
                    });
                    trace("[NativeDialogueService] duplicate finish on terminal "
                        + rec.requestId + ": hide resent, no republish");
                }
                return;
            }
        }
    }

    // ── 取消（场景切换 / compat 关闭 / 覆盖）────────────────────

    /** 供场景清理与 facade 调用：取消活动会话；服务缺席时兼容旧 MC 关闭。 */
    public static function cancelActive(reason:String):Void {
        if (_session != null && !_session.terminal) {
            cancelSession(reason);
            return;
        }
        var cur = _root.对话框界面;
        if (cur != null && cur !== _compat && typeof cur == "movieclip") {
            cur.followingEvent = null;
            if (typeof cur.关闭 == "function" && cur.关闭 !== _clipCloseStub) {
                cur.关闭();
            }
        }
    }

    // ── compat facade ───────────────────────────────────────────

    /**
     * 幂等建立/重绑 _root.对话框界面 facade（普通 Object）。
     * authored MovieClip（含 AVM1 同路径重绑回来的实例）停住+隐藏，
     * 其交互与 onClose 钩子全部换成安全桩——旧 onClose 裸写暂停并发布
     * followingEvent 的路径在 headless 下禁止复活。
     */
    public static function ensureCompat():Object {
        if (_compat == null) _compat = makeCompat();
        _root.__nativeDialogueCompat = _compat;
        if (_clipCloseStub == null) {
            // 只做 MC 本地收尾：停住+隐藏，不触发 onClose/暂停写/事件发布。
            _clipCloseStub = function():Void {
                this.stop();
                this._visible = false;
            };
        }
        var cur = _root.对话框界面;
        if (cur !== _compat && cur != null && typeof cur == "movieclip") {
            cur.stop();
            cur._visible = false;
            cur.刷新内容 = function():Void {};
            cur.打字 = function():Void {};
            cur.结束打字 = function():Void {};
            cur.下一句 = function():Void {};
            cur.onClose = function():Void {};
            cur.关闭 = _clipCloseStub;
        }
        _root.对话框界面 = _compat;
        syncCompat();
        return _compat;
    }

    private static function makeCompat():Object {
        var c:Object = {};
        c.本轮对话内容 = [];
        c.对话进度 = 0;
        c.对话条数 = 0;
        c.followingEvent = null;
        c._visible = false;
        c.gotoAndStop = function(label):Void {
            if (label == "close") {
                org.flashNight.arki.dialogue.NativeDialogueService.cancelActive("compat_close");
            }
        };
        c.刷新内容 = function():Void {};
        c.打字 = function():Void {};
        c.结束打字 = function():Void {};
        c.下一句 = function():Void {
            var svc = org.flashNight.arki.dialogue.NativeDialogueService;
            if (svc._session != null && !svc._session.terminal) svc.advance();
        };
        c.关闭 = function():Void {
            org.flashNight.arki.dialogue.NativeDialogueService.cancelActive("compat_close");
        };
        c.onClose = function():Void {
            org.flashNight.arki.dialogue.NativeDialogueService.finishSession();
        };
        c.刷新立绘 = function():Void {};
        c.刷新外部导入立绘 = function():Void {};
        return c;
    }

    private static function syncCompat():Void {
        if (_compat == null) return;
        var s:Object = _session;
        if (s != null && !s.terminal) {
            _compat.本轮对话内容 = s.lines;
            _compat.对话条数 = s.lines.length;
            _compat.对话进度 = s.index;
            _compat._visible = true;
        } else {
            _compat.本轮对话内容 = [];
            _compat.对话条数 = 0;
            _compat.对话进度 = 0;
            _compat._visible = false;
        }
    }

    // ── 内部：会话生命周期 ──────────────────────────────────────

    private static function beginSession(rows:Array, mode:String, followingEvent:Object,
                                         inheritedLease:String, frozenPortraits:Array,
                                         snapshotOnly:Boolean):Void {
        _reqSeq++;
        var s:Object = {
            requestId: "nd:" + _reqSeq,
            sceneId: NativeInteractionContext.getSceneId(),
            revision: 0,
            // NPC 会传持久对白数组；会话追加不能改写作者数据。
            lines: rows.concat(),
            portraits: frozenPortraits == undefined ? capturePortraits(rows) : frozenPortraits.concat(),
            index: 0,
            mode: mode,
            leaseId: inheritedLease == undefined ? null : inheritedLease,
            followingEvent: followingEvent,
            terminal: false,
            // wireMode 闩定于会话起点：v1 起头终身 v1
            wire: (snapshotOnly !== true && capsAllowsBook() && forceSnapshot !== true) ? "v2" : "v1",
            epoch: 0,
            rowCount: countNormalized(rows),
            opSeq: 0,
            pendingOps: {},
            bookSettled: false,
            setPending: false,
            statusQuery: undefined,
            advanceKey: undefined,
            desiredAdvanceKey: undefined,
            awaitingCommit: null
        };
        _session = s;
        if (mode == "stage" && s.leaseId == null) {
            s.leaseId = PauseManager.lease(true, "dialogue");
        }
        syncCompat();
        if (s.wire == "v2") {
            sendBook(s);
        } else if (!sendLine(0)) {
            if (snapshotOnly === true) gatedFinishSession(s, "snapshot_fallback_send_failed");
            else finishSession(); // 既有 v1 不可达兜底
        }
    }

    /**
     * 回退只移交内容与责任，不提交剧情终态。旧 rid 墓碑先落，新 rid 强制 v1；
     * 沿用入口冻结的立绘，跳过 book 本就不发送的 null 行，取消旧 pending 回调。
     * start>0 只用于 v1 的 4096 行窗口续播，继续持有同一 claim/followingEvent。
     */
    private static function replaceWithSnapshot(s:Object, reason:String, start:Number):Void {
        if (s == null || s.terminal || _session !== s) return;
        var rows:Array = [];
        var portraits:Array = [];
        var carriedImage:String = "";
        for (var prior:Number = 0; prior < start; prior++) {
            var priorRow:Array = s.lines[prior];
            if (priorRow != null && typeof priorRow[6] == "string" && priorRow[6] != "") {
                carriedImage = priorRow[6];
            }
        }
        for (var i:Number = start; i < s.lines.length; i++) {
            if (s.lines[i] == null) continue;
            rows.push(s.lines[i]);
            portraits.push(s.portraits[i]);
        }
        if (rows.length > 0 && carriedImage != ""
                && (typeof rows[0][6] != "string" || rows[0][6] == "")) {
            rows[0] = rows[0].concat();
            rows[0][6] = carriedImage; // 新窗口恢复 keep 配图，不改作者行数组
        }
        var follow:Object = s.followingEvent != null ? s.followingEvent
            : (_compat != null ? _compat.followingEvent : null);
        var leaseId:String = s.leaseId;
        s.leaseId = null; // cancel 不释放：避免移交期间出现未暂停的一帧
        cancelSession("snapshot_fallback");
        trace("[NativeDialogueService] snapshot fallback: " + reason);
        beginSession(rows, s.mode, follow, leaseId, portraits, true);
    }

    /**
     * v1：推进到下一句或终态。
     * v2：换句由 Host 本地驱动，本方法明确 no-op（不发任何 wire）；
     * facade 下一句 经此同样无效化。
     */
    public static function advance():Void {
        var s:Object = _session;
        if (s == null || s.terminal) return;
        if (s.wire == "v2") return;
        var next:Number = s.index + 1;
        if (next >= s.lines.length) {
            finishSession();
        } else if (next >= 4096) {
            // v1 也限制 lineCount<=4096；累计追加超限时分窗口续播，不丢尾部。
            replaceWithSnapshot(s, "snapshot_next_window", next);
        } else if (!sendLine(next)) {
            finishSession();
        }
    }

    /** finish：terminal→清事件→清会话→放 claim→hide→publish（唯一消费点）。 */
    public static function finishSession():Void {
        var s:Object = _session;
        if (s == null || s.terminal) return;
        s.terminal = true;
        // 终态后在途 mutation/status 应答一律由身份校验丢弃
        s.pendingOps = {};
        s.statusQuery = undefined;
        var ev:Object = (s.followingEvent != null) ? s.followingEvent
                        : ((_compat != null) ? _compat.followingEvent : null);
        s.followingEvent = null;
        if (_compat != null) _compat.followingEvent = null;
        _session = null;
        if (s.leaseId != null) PauseManager.releaseLease(s.leaseId);
        sendHide(s);
        syncCompat();
        publishFollow(ev);
    }

    /** cancel：terminal→清事件→清会话→放 claim→hide；绝不 publish。 */
    private static function cancelSession(reason:String):Void {
        var s:Object = _session;
        if (s == null || s.terminal) return;
        s.terminal = true;
        s.pendingOps = {};
        s.statusQuery = undefined;
        s.awaitingCommit = null;   // cancel/teardown 撤销等待业务提交义务
        s.followingEvent = null;
        if (_compat != null) _compat.followingEvent = null;
        _session = null;
        if (s.leaseId != null) PauseManager.releaseLease(s.leaseId);
        sendHide(s);
        syncCompat();
    }

    private static function onSceneTeardown():Void {
        cancelActive("scene_teardown");
    }

    /** 对端已不可达：先清本代 caps 闩再按发送失败语义收口，不留不可见暂停责任。 */
    public static function onTransportDisconnected():Void {
        // 清闩先于断线收口可能引发的重入：旧代能力不得泄漏到新连接
        _capsModes = null;
        _capsConn = undefined;
        finishSession();
    }

    // ── 内部：v2 mutation 发送与确认 ────────────────────────────

    /**
     * book/append/set 一律经 sendTaskWithCallback 确认通道发送。
     * rec 捕获五元校验身份：连接代（send 时刻 xmlSocket 对象）+ 会话对象 +
     * 操作代际 seq/epoch（requestId/sceneId 在应答时对照会话）。
     * @return false = 传输层不具备回调发送能力（未连接/无该方法），未入队
     */
    private static function sendMutation(s:Object, op:String, payload:Object,
                                         opEpoch:Number, prevKey):Boolean {
        var sm:Object = _root.server;
        if (sm == undefined || !sm.isSocketConnected
                || typeof sm.sendTaskWithCallback != "function") return false;
        var rec:Object = {
            sess: s, conn: sm.xmlSocket,
            seq: ++s.opSeq, op: op, epoch: opEpoch,
            prevKey: prevKey
        };
        s.pendingOps[rec.seq] = rec;
        var svc = org.flashNight.arki.dialogue.NativeDialogueService;
        sm.sendTaskWithCallback("native_dialogue", payload, null,
            function(resp:Object):Void { svc.onMutationAck(rec, resp); },
            MUTATION_ACK_TIMEOUT_MS);
        return true;
    }

    /** v2 mutation 应答：五元校验 → applied 清 pending / rejected 分类 / 超时查 status。 */
    private static function onMutationAck(rec:Object, resp:Object):Void {
        var s:Object = rec.sess;
        if (s == null || s.terminal || _session !== s) return;        // 会话对象身份
        if (s.pendingOps == null || s.pendingOps[rec.seq] !== rec) return; // 操作代际（已决）
        var sm:Object = _root.server;
        var conn:Object = (sm != undefined) ? sm.xmlSocket : undefined;
        if (conn !== rec.conn) return;                                 // 连接代
        if (resp == null) return;
        if (resp.success === false) {
            if (resp.error == "callback timeout") {
                queryMutationStatus(s, rec);
            } else {
                delete s.pendingOps[rec.seq];
                classifyMutationFailure(s, rec, String(resp.error));
            }
            return;
        }
        // 成功回执须携带匹配的 requestId + sceneId（+代际回显）
        if (resp.requestId !== s.requestId || resp.sceneId !== s.sceneId) return;
        if (resp.op != undefined && resp.op !== rec.op) return;
        if (rec.epoch != undefined && resp.requestedEpoch != undefined
                && resp.requestedEpoch !== rec.epoch) return;
        if (resp.status == "applied") {
            delete s.pendingOps[rec.seq];
            onMutationApplied(s, rec, resp);
        } else if (resp.status == "rejected") {
            delete s.pendingOps[rec.seq];
            classifyMutationFailure(s, rec,
                resp.reason == undefined ? "rejected" : String(resp.reason));
        } else {
            // 回执缺少可判定 status → 结果未知：转 status 查询裁决
            queryMutationStatus(s, rec);
        }
    }

    private static function onMutationApplied(s:Object, rec:Object, resp:Object):Void {
        // 旧代回包不能覆盖已在 AS2 追加的新代行数。
        if (resp != null && resp.appliedEpoch === s.epoch
                && typeof resp.rowCount == "number" && resp.rowCount >= 0
                && resp.rowCount == Math.floor(resp.rowCount)) {
            s.rowCount = resp.rowCount;
        }
        if (rec.op == "book") {
            s.bookSettled = true;
        } else if (rec.op == "set") {
            s.setPending = false;
        }
        flushAdvanceKey(s);
    }

    /**
     * 失败分类：set → 恢复上一个有效值不结束剧情；book 首次采用前 →
     * 降级回 v1 快照序列；append → 新 rid 的 v1 会话保留合并内容、冻结立绘
     * 与 stage 义务，移交期间不发布事件。
     */
    private static function classifyMutationFailure(s:Object, rec:Object,
                                                    reason:String):Void {
        trace("[NativeDialogueService] v2 " + rec.op + " failed/rejected: "
            + reason);
        if (rec.op == "set") {
            if (rec.prevKey !== undefined) s.advanceKey = rec.prevKey;
            s.desiredAdvanceKey = s.advanceKey;   // 防恢复后又被自动重发成回环
            s.setPending = false;
            return;
        }
        replaceWithSnapshot(s, rec.op + ":" + reason, 0);
    }

    /**
     * mutation 应答超时（墙钟）：超时只证明"结果未知"——发只读 status 查询
     * 沿同一采用队列串行裁决；查询不可发/已有在途 → 保留托管。
     */
    private static function queryMutationStatus(s:Object, rec:Object):Void {
        // 超时仍未知，不能先删操作；另一查询在途时保留它，供后续查询确认。
        rec.awaitingStatus = true;
        if (s.statusQuery != undefined) return;
        var sm:Object = _root.server;
        if (sm == undefined || !sm.isSocketConnected
                || typeof sm.sendTaskWithCallback != "function") return;
        var q:Object = {
            sess: s, conn: sm.xmlSocket, maxOpSeq: s.opSeq, queryEpoch: s.epoch
        };
        s.statusQuery = q;
        var svc = org.flashNight.arki.dialogue.NativeDialogueService;
        sm.sendTaskWithCallback("native_dialogue",
            {
                version: 2, op: "status",
                requestId: s.requestId, sceneId: s.sceneId,
                queryEpoch: q.queryEpoch
            },
            null,
            function(resp:Object):Void { svc.onStatusAck(q, resp); },
            MUTATION_ACK_TIMEOUT_MS);
    }

    /**
     * status 应答：appliedEpoch 对带代际操作给出确定裁决（采用队列串行语义），
     * 只确认查询发送前的 mutation；无代际的 set 无法由 appliedEpoch 裁决 →
     * 解除等待、保留托管；查询自身超时/缺 appliedEpoch → 仍未知，托管不 finish。
     */
    private static function onStatusAck(q:Object, resp:Object):Void {
        var s:Object = q.sess;
        if (s == null || s.terminal || _session !== s) return;
        if (s.statusQuery !== q) return;
        var sm:Object = _root.server;
        var conn:Object = (sm != undefined) ? sm.xmlSocket : undefined;
        if (conn !== q.conn) return;
        s.statusQuery = undefined;
        if (resp == null || resp.success === false) {
            trace("[NativeDialogueService] v2 status query unresolved; custody retained");
            return;
        }
        if (resp.requestId !== s.requestId || resp.sceneId !== s.sceneId) return;
        var applied = resp.appliedEpoch;
        if (typeof applied != "number" || isNaN(applied) || applied < 0
                || applied != Math.floor(applied) || applied > q.queryEpoch) {
            trace("[NativeDialogueService] v2 status query indeterminate; custody retained");
            return;
        }
        var pending:Array = [];
        for (var k:String in s.pendingOps) {
            var rec:Object = s.pendingOps[k];
            if (rec.seq <= q.maxOpSeq) pending.push(rec);
        }
        for (var i:Number = 0; i < pending.length; i++) {
            resolveByEpoch(s, pending[i], applied, resp);
            if (s == null || s.terminal || _session !== s) return;
        }
        flushAdvanceKey(s);
        // 查询后发出的操作若也超时，另发一次查询；绝不用旧结果猜它未采用。
        for (var nextKey:String in s.pendingOps) {
            var nextRec:Object = s.pendingOps[nextKey];
            if (nextRec.awaitingStatus === true) {
                queryMutationStatus(s, nextRec);
                return;
            }
        }
    }

    private static function resolveByEpoch(s:Object, rec:Object, applied:Number,
                                           resp:Object):Void {
        if (rec == null) return;
        if (s.pendingOps != null && s.pendingOps[rec.seq] === rec) {
            delete s.pendingOps[rec.seq];
        }
        if (rec.epoch == undefined) {
            // set 不携带行集代际，appliedEpoch 无法裁决 → 解除等待、保留托管
            s.setPending = false;
            return;
        }
        if (applied >= rec.epoch) {
            onMutationApplied(s, rec, resp);
        } else {
            classifyMutationFailure(s, rec, "status:appliedEpoch=" + applied);
        }
    }

    // ── 内部：v2 wire 帧 ────────────────────────────────────────

    /**
     * v2 会话入口帧：行物化（跳过 null 行）→ book。
     * 规范化后空集 → 不发 book，经门禁收尾（孤儿 hide 同发送失败兜底）；
     * 传输不具备回调通道 → 降级 v1 快照序列。
     */
    private static function sendBook(s:Object):Void {
        var lines:Array = materializeLines(s.lines, s.portraits);
        if (lines.length == 0) {
            // 异步空集完成：新增收口路径，不得绕业务门禁
            gatedFinishSession(s, "empty_book");
            return;
        }
        s.epoch = 1;
        var payload:Object = {
            version: 2, op: "book", kind: "inline",
            requestId: s.requestId, sceneId: s.sceneId,
            mode: s.mode, epoch: 1, startIndex: 0,
            lines: lines
        };
        var keyCode:Number = org.flashNight.arki.key.KeyManager.getKeySetting("互动键");
        if (!isNaN(keyCode)) {
            payload.advanceKey = keyCode;
            s.advanceKey = keyCode;
            s.desiredAdvanceKey = keyCode;
        }
        if (!sendMutation(s, "book", payload, 1, undefined)) {
            replaceWithSnapshot(s, "book_transport_unavailable", 0);
        }
    }

    /** 规范化行数 = 跳过 null 后的行数（finalIndex 校验基准）。 */
    private static function countNormalized(rows:Array):Number {
        var n:Number = 0;
        for (var i:Number = 0; i < rows.length; i++) {
            if (rows[i] != null) n++;
        }
        return n;
    }

    /**
     * 7 元组行 → v2 line 物化（与 sendLine 同源）：
     * row==null 跳过；"角色名" 特判在物化期解析；char 缺失已由
     * capturePortraits 落到 {kind:"static",key:""} 空静态槽。
     */
    private static function materializeLines(rows:Array, portraits:Array):Array {
        var out:Array = [];
        for (var i:Number = 0; i < rows.length; i++) {
            var row:Array = rows[i];
            if (row == null) continue;
            var img = row[6];
            var imageAction:String = "keep";
            var imagePath:String = "";
            if (typeof img == "string" && img != "") {
                if (img == "close") imageAction = "clear";
                else { imageAction = "show"; imagePath = img; }
            }
            var portrait:Object =
                (portraits != null && i < portraits.length) ? portraits[i] : null;
            if (portrait == null) {
                portrait = {kind: "static", key: "", expression: "普通"};
            }
            out.push({
                name: row[0] == "角色名" ? String(_root.角色名)
                        : ((row[0] != undefined) ? String(row[0]) : ""),
                title: (row[1] != undefined) ? String(row[1]) : "",
                text: (row[3] != undefined) ? String(row[3]) : "",
                portrait: portrait,
                imageAction: imageAction,
                imagePath: imagePath
            });
        }
        return out;
    }

    // ── 内部：v2 set（低频白名单字段变更）────────────────────────

    /**
     * 互动键变更传播入口（_root.watch 钩子与外部调用方共用）：
     * 仅在 v2 会话上经 set 低频下发；不动行集、不 bump epoch。
     */
    public static function notifyAdvanceKeyChanged(newVal):Void {
        var code:Number = Number(newVal);
        if (isNaN(code)) return;
        var s:Object = _session;
        if (s == null || s.terminal || s.wire != "v2") return;
        s.desiredAdvanceKey = code;
        flushAdvanceKey(s);
    }

    /**
     * 把 desiredAdvanceKey 与已下发值的差量收敛成一个在途 set：
     * book 未采用前挂起（book 已带键值）、在途 set 期间合并变更、
     * applied/rejected 后在应答路径上重新收敛。
     */
    private static function flushAdvanceKey(s:Object):Void {
        if (s == null || s.terminal || s.wire != "v2") return;
        if (s.bookSettled !== true || s.setPending === true) return;
        var code = s.desiredAdvanceKey;
        if (code === undefined || code === s.advanceKey) return;
        var prev = s.advanceKey;
        s.advanceKey = code;
        s.setPending = true;
        var payload:Object = {
            version: 2, op: "set",
            requestId: s.requestId, sceneId: s.sceneId,
            advanceKey: code
        };
        if (!sendMutation(s, "set", payload, undefined, prev)) {
            s.setPending = false;
            s.advanceKey = prev;
            s.desiredAdvanceKey = prev;
        }
    }

    // ── 内部：业务门禁（§4.6 等待业务提交）──────────────────────

    /**
     * 与 ServerManager.handleGameCommand 同一谓词：真正未决的奖励候选
     * 在 pending 期间禁止竞争写入。SaveManager 子系统缺席 → 无候选可决，
     * 视为无 pending（缺席不等于"未知"，否则永久悬挂成软锁）。
     */
    private static function businessCommitPending():Boolean {
        var smg = org.flashNight.neur.Server.SaveManager;
        if (smg == undefined || smg == null) return false;
        if (typeof smg.getInstance != "function") return false;
        var inst:Object = smg.getInstance();
        if (inst == null || typeof inst.hasRewardCommitPending != "function") {
            return false;
        }
        return inst.hasRewardCommitPending() === true;
    }

    /**
     * 新增收口路径的门禁包装：rewardCommit pending 中不得直接
     * finishSession/publishFollow（事件发布会穿透暂停帧产生业务副作用）。
     * pending 中落会话内"等待业务提交"标志（kind+epoch），由
     * tryAwaitingCommit 在解除后重新核验身份与 epoch 再提交；
     * teardown/cancel/断线撤销义务（标志随会话销毁）。
     */
    private static function gatedFinishSession(s:Object, kind:String):Void {
        if (s == null || s.terminal || _session !== s) return;
        if (businessCommitPending()) {
            s.awaitingCommit = {epoch: s.epoch, kind: kind};
            trace("[NativeDialogueService] " + kind
                + " deferred: reward commit pending");
            return;
        }
        finishSession();
    }

    /**
     * 待提交义务冲刷：ServerManager 帧泵逐帧调用 + 入向活动顺带核验。
     * 重新核验会话身份与 epoch——代际已推进则丢弃旧义务（旧代终态裁决
     * 不得压过新代内容）。不得在暂停 watch 分发内调用 finishSession
     * （claim 释放会被外层折叠回 true）。
     */
    public static function tryAwaitingCommit():Void {
        var s:Object = _session;
        if (s == null || s.terminal || s.awaitingCommit == null) return;
        if (businessCommitPending()) return;
        var pending:Object = s.awaitingCommit;
        s.awaitingCommit = null;
        if (_session !== s || s.epoch !== pending.epoch) {
            trace("[NativeDialogueService] awaiting commit dropped: epoch moved");
            return;
        }
        trace("[NativeDialogueService] awaiting commit flushed: " + pending.kind);
        finishSession();
    }

    // ── 内部：wire ──────────────────────────────────────────────

    private static function sendLine(index:Number):Boolean {
        var s:Object = _session;
        if (s == null || s.terminal) return false;
        var row:Array = s.lines[index];
        if (row == null) return false;
        s.revision++;
        s.index = index;
        var img = row[6];
        var imageAction:String = "keep";
        var imagePath:String = "";
        if (typeof img == "string" && img != "") {
            if (img == "close") imageAction = "clear";
            else { imageAction = "show"; imagePath = img; }
        }
        var payload:Object = {
            version: 1,
            op: "show",
            requestId: s.requestId,
            sceneId: s.sceneId,
            revision: s.revision,
            lineIndex: index,
            lineCount: Math.min(4096, s.lines.length),
            name: row[0] == "角色名" ? String(_root.角色名) : ((row[0] != undefined) ? String(row[0]) : ""),
            title: (row[1] != undefined) ? String(row[1]) : "",
            text: (row[3] != undefined) ? String(row[3]) : "",
            portrait: s.portraits[index],
            imageAction: imageAction,
            imagePath: imagePath
        };
        var keyCode:Number = org.flashNight.arki.key.KeyManager.getKeySetting("互动键");
        if (!isNaN(keyCode)) payload.advanceKey = keyCode;
        // 下一句存在时捎带预取描述：立绘直接引用冻结快照（sendTaskToNode 即时
        // 序列化，无需克隆）；仅显式换新配图才带 imageAction/imagePath。
        var nextIndex:Number = index + 1;
        if (nextIndex < s.lines.length && s.lines[nextIndex] != null) {
            var pf:Object = null;
            var np:Object = s.portraits[nextIndex];
            if (np != null && np.key != undefined && String(np.key) != "") {
                pf = {};
                pf.portrait = np;
            }
            var nImg = s.lines[nextIndex][6];
            if (typeof nImg == "string" && nImg != "" && nImg != "close") {
                if (pf == null) pf = {};
                pf.imageAction = "show";
                pf.imagePath = nImg;
            }
            if (pf != null) payload.prefetch = pf;
        }
        syncCompat();
        return send(payload);
    }

    private static function sendHide(s:Object):Void {
        send({
            version: (s.wire == "v2") ? 2 : 1,
            op: "hide",
            requestId: s.requestId,
            sceneId: s.sceneId
        });
        // 记录墓碑：此后同 rid 的重复 finish 只补发本 hide，不再 publish
        recordFinished(s);
    }

    private static function recordFinished(s:Object):Void {
        for (var i:Number = 0; i < _recentFinished.length; i++) {
            if (_recentFinished[i].requestId === s.requestId) return;
        }
        _recentFinished.push({
            requestId: s.requestId, sceneId: s.sceneId, wire: s.wire
        });
        if (_recentFinished.length > RECENT_FINISHED_MAX) {
            _recentFinished.shift();
        }
    }

    /** 入口即冻结每位说话人的独立外观；后续换行不再追已卸载或换装的 MC。 */
    private static function capturePortraits(rows:Array):Array {
        var result:Array = [];
        for (var i:Number = 0; i < rows.length; i++) {
            var row:Array = rows[i];
            if (row == null) { result.push(null); continue; }
            result.push(NativeDialogueAppearance.build(row[2], row[4], row[5],
                row[0] == undefined ? "" : String(row[0])));
        }
        return result;
    }

    private static function send(payload:Object):Boolean {
        var sm:Object = _root.server;
        if (sm == undefined || !sm.isSocketConnected
                || typeof sm.sendTaskToNode != "function") return false;
        return sm.sendTaskToNode("native_dialogue", payload, null) === true;
    }

    private static function publishFollow(ev:Object):Void {
        if (ev == null || ev.name == null || ev.name == "") return;
        var d:Object = (_root.gameworld != null) ? _root.gameworld.dispatcher : null;
        if (d == null) return;
        if (ev.args != null && ev.args.length > 0) {
            d.publish.apply(d, [String(ev.name)].concat(ev.args));
        } else {
            d.publish(String(ev.name));
        }
    }
}
