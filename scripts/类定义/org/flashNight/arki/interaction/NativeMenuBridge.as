/** * org.flashNight.arki.interaction.NativeMenuBridge
 * NPC 功能菜单迁原生（C# 浮层）的 AS2 兼容桥。
 *
 * 旧世界：主时间轴 frame134+ 的 _root.NPC功能菜单（Symbol 1770 MC）持有
 *   _visible/_x/_y/当前NPC/刷新显示；全部 NPC 素材 on(release) 统一写
 *   「_visible=1 → _x=_root._xmouse → _y=_root._ymouse → 当前NPC=this._name
 *   → 刷新显示()」五连。调用方分布在各素材 SWF 内，不改写。
 * 新世界：attachCompat 在 MC onClipEvent(load) 时把 _parent[name] 改指
 *   plain compat 对象（同名承接），MC 自身 _visible=false 退役可见 UI。
 *   _x/_y/当前NPC 只落存储；仅 刷新显示() 显式发布 menu.show；
 *   _visible=false 写、onClipEvent(unload)、SceneChanged teardown 发 hide。
 *   占位菜单 查看详细菜单(Symbol 2017)/修改详细菜单(Symbol 2020) 同法承接，
 *   但 __nativeExt.enabled=false 永不发布（仅保留同名兼容对象与未启用扩展入口）。
 *
 * wire 出：sendTaskToNode("native_interaction",
 *   {kind:"menu", op:"show"|"hide", version:1, requestId:"ni:<n>", sceneId,
 *    x, y, targetName, title, actions:[{id,label,enabled}]})。
 * wire 入：_root.gameCommands["nativeInteractionAction"|"nativeInteractionCancel"]，
 *   校验 version/requestId/sceneId/活场景身份/目标存活/动作仍 enabled，
 *   先消费请求再执行原路由，拒绝迟到/重复/伪造。
 */
class org.flashNight.arki.interaction.NativeMenuBridge {
    private static var _installed:Boolean = false;
    private static var _compatByName:Object = null;

    // 单 pending 菜单请求（NPC功能菜单是唯一发布者）
    private static var _openRequestId:String = null;
    private static var _openSceneId:String = null;
    private static var _openTargetName:String = null;
    private static var _openTargetToken:Object = null; // 目标本体普通对象 token（非 MovieClip 引用）
    private static var _openCompat:Object = null;

    private static var MENU_NAME:String = "NPC功能菜单";
    private static var EXT_VIEW:String = "npc.viewDetail";
    private static var EXT_MODIFY:String = "npc.modifyDetail";

    // ═══════════════════════════════════════════════════════════
    // install — BootSequencer S_SYNCLOGIC 末段调用；attachCompat 内惰性兜底
    // ═══════════════════════════════════════════════════════════
    public static function install():Void {
        if (_installed) return;
        _installed = true;
        _compatByName = {};
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["nativeInteractionAction"] = function(params:Object):Void {
            org.flashNight.arki.interaction.NativeMenuBridge.handleAction(params);
        };
        _root.gameCommands["nativeInteractionCancel"] = function(params:Object):Void {
            org.flashNight.arki.interaction.NativeMenuBridge.handleCancel(params);
        };
        // 主 XFL 实例脚本只认 _root shim（沿用 _root._bootstrap 惯例，不静态引类）：
        // 旧 SWF/无 asLoader 时 shim 不存在，MC 脚本跳过即回退原 Flash 菜单行为。
        _root.__nativeMenu = {
            attach: function(name:String, clip:MovieClip):Void {
                org.flashNight.arki.interaction.NativeMenuBridge.attachCompat(name, clip);
            },
            detach: function(name:String, clip:MovieClip):Void {
                org.flashNight.arki.interaction.NativeMenuBridge.detachCompat(name, clip);
            }
        };
        org.flashNight.arki.interaction.NativeInteractionContext.install();
        org.flashNight.arki.interaction.NativeInteractionContext.onSceneTeardown(onSceneTeardown);
        // content 岗位接线：静态引用把 NativeTooltipBridge 编入 asLoader.swf；
        // 其 install() 经 _global 解析共享上下文并向其注册场景 teardown。
        org.flashNight.gesh.tooltip.NativeTooltipBridge.install();
    }

    // ═══════════════════════════════════════════════════════════
    // 同名兼容对象生命周期 — 由 authored MC 的 onClipEvent(load/unload) 驱动
    // ═══════════════════════════════════════════════════════════
    public static function attachCompat(name:String, clip:MovieClip):Void {
        install();
        if (name == undefined || name == "" || clip == undefined) return;
        var parent:Object = clip._parent;
        if (parent == undefined) return;
        clip._visible = false;              // 退役可见 UI（含占位菜单的「开发中」按钮）
        var old:Object = _compatByName[name];
        if (old != undefined) old.__nativeDead = true;
        closePending();                     // 同名实例重建时收敛上一周期在途请求
        var compat:Object = buildCompat(name, clip);
        var tok:Object = {};                // 本装载周期身份：普通对象，不做 MC 引用比较
        clip.__nativeAttachToken = tok;
        compat.__nativeAttachToken = tok;
        parent[name] = compat;              // 同名对象承接：60 处旧调用原样落点
        _compatByName[name] = compat;
    }

    public static function detachCompat(name:String, clip:MovieClip):Void {
        var compat:Object = (_compatByName == undefined) ? undefined : _compatByName[name];
        if (compat == undefined) return;
        // 同路径重建防护：只清本装载周期的 compat。迟到的旧实例 unload 若晚于
        // 新实例 load 触发，clip 携带的旧 token 与当前注册 compat 的 token 不是
        // 同一普通对象 → 跳过；不比较 MC 引用（AVM1 会把旧引用重绑到新实例）。
        var clipTok:Object = (clip != undefined) ? clip.__nativeAttachToken : undefined;
        if (clipTok == undefined || clipTok !== compat.__nativeAttachToken) return;
        compat.__nativeDead = true;
        var parent:Object = (clip._parent != undefined) ? clip._parent : _root;
        if (parent[name] === compat) delete parent[name];
        delete _compatByName[name];
        if (_openCompat === compat) closePending();
    }

    private static function buildCompat(name:String, clip:MovieClip):Object {
        var compat:Object = {};
        compat.__nativeMenuName = name;
        compat.__nativeClip = clip;   // 仅作无宿主时的 Flash 回退渲染体，不作身份判定
        compat.__nativeDead = false;
        compat.__compatVisible = false;
        compat._x = 0;
        compat._y = 0;
        compat.当前NPC = "";
        compat.物品栏 = [];
        compat.NPC任务_任务 = [];
        compat.刷新显示 = function():Void {
            org.flashNight.arki.interaction.NativeMenuBridge.refreshCompat(this);
        };
        // _visible 经 addProperty 承接：true 仅武装（显式刷新才发布），
        // false 关闭在途请求并发 hide。
        compat.addProperty("_visible",
            function() { return this.__compatVisible; },
            function(v) {
                this.__compatVisible = (v == true);
                org.flashNight.arki.interaction.NativeMenuBridge.onCompatVisible(this, this.__compatVisible);
            });
        if (name != MENU_NAME) {
            compat.__nativeExt = {
                id: (name == "查看详细菜单") ? EXT_VIEW : EXT_MODIFY,
                enabled: false
            };
        }
        return compat;
    }

    // ═══════════════════════════════════════════════════════════
    // compat → wire：唯一发布触发点是显式 刷新显示()
    // ═══════════════════════════════════════════════════════════
    public static function refreshCompat(compat:Object):Void {
        if (compat == undefined || compat.__nativeDead === true) return;
        if (compat.__nativeExt != undefined) return;       // 占位菜单退役，不发布
        if (compat.__compatVisible !== true) return;       // 未武装：镜像旧 MC 隐藏态刷新
        publishShow(compat);
    }

    public static function onCompatVisible(compat:Object, now:Boolean):Void {
        if (compat == undefined || compat.__nativeDead === true) return;
        if (compat.__nativeExt != undefined) return;
        if (now !== true) {
            if (_openCompat === compat) closePending();
            var clip:Object = compat.__nativeClip;
            if (clip != undefined) clip._visible = false;  // 同步收敛 Flash 回退体
        }
    }

    private static function publishShow(compat:Object):Void {
        var targetName:String = String(compat.当前NPC || "");
        var gw:Object = _root.gameworld;
        var npc:Object = (gw == undefined) ? undefined : gw[targetName];
        if (targetName == "" || npc == undefined) { closePending(); fallbackToClip(compat); return; }

        var requestId:String = org.flashNight.arki.interaction.NativeInteractionContext.nextRequestId();
        var sceneId:String = org.flashNight.arki.interaction.NativeInteractionContext.getSceneId();
        closePending();                     // 换目标/连点：先按旧身份发 hide，宿主无孤儿浮层
        _openRequestId = requestId;
        _openSceneId = sceneId;
        _openTargetName = targetName;
        _openTargetToken = targetToken(npc);
        _openCompat = compat;

        var sx:Number = Number(compat._x);
        var sy:Number = Number(compat._y);
        var payload:Object = {
            kind:"menu", op:"show", version:1,
            requestId:requestId, sceneId:sceneId,
            x:(isNaN(sx) ? 0 : sx), y:(isNaN(sy) ? 0 : sy),
            targetName:targetName,
            title:(npc.名字 != undefined ? String(npc.名字) : targetName),
            actions:buildActions(npc)
        };
        if (send(payload)) {
            var clip2:Object = compat.__nativeClip;
            if (clip2 != undefined) clip2._visible = false;   // 原生接管：收敛上次 Flash 回退
        } else {
            clearOpen();   // 无 socket：不持有永远无法兑现的请求
            fallbackToClip(compat);
        }
    }

    // 无宿主/发送失败回退：把承接状态回灌 authored MC 并显示——
    // Flash 单跑（无 launcher）时保留原菜单，旧 SWF 行为不被退役。
    private static function fallbackToClip(compat:Object):Void {
        if (compat.__nativeDead === true) return;
        var clip:Object = compat.__nativeClip;
        if (clip == undefined) return;
        clip._x = compat._x;
        clip._y = compat._y;
        clip.当前NPC = compat.当前NPC;
        clip.物品栏 = compat.物品栏;
        clip.NPC任务_任务 = compat.NPC任务_任务;
        if (typeof clip.刷新显示 == "function") clip.刷新显示();
        clip._visible = true;
    }

    // ═══════════════════════════════════════════════════════════
    // wire 入：action / cancel
    // ═══════════════════════════════════════════════════════════
    public static function handleAction(params:Object):Void {
        if (params == undefined || Number(params.version) != 1) return;
        if (_openRequestId == null) return;
        if (String(params.requestId) !== _openRequestId) return;
        if (String(params.sceneId) !== _openSceneId) return;
        var targetName:String = _openTargetName;
        var targetTok:Object = _openTargetToken;
        var compat:Object = _openCompat;
        var actionId:String = String(params.actionId);
        clearOpen();                        // 身份匹配即消费，防重入/重复/迟到
        if (compat == undefined || compat.__nativeDead === true) return;
        var gw:Object = _root.gameworld;
        if (!org.flashNight.arki.interaction.NativeInteractionContext.isCurrentWorld(gw)) return;
        var npc:Object = gw[targetName];
        // 同名重建防护：只读比对 show 时快照的普通对象 token，不新建、不存 MC 引用
        if (npc == undefined || targetTok == undefined
                || npc.__nativeInteractionTargetToken !== targetTok) return;
        if (!actionAllowed(npc, actionId)) return;
        runAction(npc, targetName, actionId);
    }

    public static function handleCancel(params:Object):Void {
        if (params == undefined || Number(params.version) != 1) return;
        if (_openRequestId == null) return;
        if (String(params.requestId) !== _openRequestId) return;
        if (String(params.sceneId) !== _openSceneId) return;
        clearOpen();                        // host 侧已撤销，不回发 hide
    }

    // ═══════════════════════════════════════════════════════════
    // 场景切换 teardown（NativeInteractionContext 注册序回调，先于身份轮换）
    // ═══════════════════════════════════════════════════════════
    private static function onSceneTeardown():Void {
        closePending();
    }

    private static function closePending():Void {
        if (_openRequestId == null) return;
        var rid:String = _openRequestId;
        var sid:String = _openSceneId;
        clearOpen();
        send({kind:"menu", op:"hide", version:1, requestId:rid, sceneId:sid});
    }

    private static function clearOpen():Void {
        _openRequestId = null;
        _openSceneId = null;
        _openTargetName = null;
        _openTargetToken = null;
        _openCompat = null;
    }

    // 目标本体身份：token 挂在 NPC 对象上的普通对象，同路径重建的新 MC 不携带，
    // 天然区分新旧实例（同 StageReturnFlow.worldIdentity 模式）。
    private static function targetToken(npc:Object):Object {
        if (npc.__nativeInteractionTargetToken == undefined) npc.__nativeInteractionTargetToken = {};
        return npc.__nativeInteractionTargetToken;
    }

    private static function send(payload:Object):Boolean {
        var sm:Object = _root.server;
        if (sm == undefined || sm.isSocketConnected != true) return false;
        return sm.sendTaskToNode("native_interaction", payload, null);
    }

    // ═══════════════════════════════════════════════════════════
    // 动作门控（Symbol 1770 刷新显示 原判定，按 NPC 现况重估）
    // ═══════════════════════════════════════════════════════════
    private static function actionAllowed(npc:Object, actionId:String):Boolean {
        if (actionId == "dialogue") return !!npc.默认对话;
        if (actionId == "shop") return !!npc.物品栏;
        if (actionId == "hire") return npc.佣兵数据 != null
            && (npc.受雇欲望 > _root.受雇欲望基准 - 1);
        if (actionId == "task") return !!npc.NPC任务_任务_关卡路径;
        if (actionId == "train") return !!npc.可学的技能;
        return false;
    }

    private static function buildActions(npc:Object):Array {
        return [
            {id:"dialogue", label:labelOf("对话"),     enabled:actionAllowed(npc, "dialogue")},
            {id:"shop",     label:labelOf("买卖物品"), enabled:actionAllowed(npc, "shop")},
            {id:"hire",     label:labelOf("雇佣"),     enabled:actionAllowed(npc, "hire")},
            {id:"task",     label:labelOf("获得任务"), enabled:actionAllowed(npc, "task")},
            {id:"train",    label:labelOf("学习技能"), enabled:actionAllowed(npc, "train")}
        ];
    }

    private static function labelOf(s:String):String {
        return (typeof _root.获得翻译 == "function") ? String(_root.获得翻译(s)) : s;
    }

    // ═══════════════════════════════════════════════════════════
    // 动作执行 — 逐字复用 Symbol 1770 五个按钮的原路由（bt2 拆 shop/hire）
    // ═══════════════════════════════════════════════════════════
    private static function runAction(npc:Object, targetName:String, actionId:String):Void {
        if (actionId == "dialogue") {
            if (npc.默认对话 != undefined) {
                if (!npc.对话index || npc.对话index >= npc.默认对话.length) {
                    _root.数组洗牌(npc.默认对话);
                    npc.对话index = 0;
                }
                var dlgArr = npc.默认对话[npc.对话index];
                npc.对话index += 1;
                _root.对话赋值到对话框(dlgArr);
            }
            return;
        }
        if (actionId == "shop") {
            if (npc.物品栏 != undefined) {
                var opened:Boolean = false;
                var shopId:String = String(npc.NPC商店检索名);
                var shopSvc:Object = _root.UI系统 == undefined ? undefined : _root.UI系统.NPC商店WebView;
                if (shopId == "" && shopSvc != undefined && shopSvc.resolveShopIdByCatalog != undefined) {
                    shopId = shopSvc.resolveShopIdByCatalog(npc.物品栏);
                }
                if (_root.gameCommands != undefined && _root.gameCommands["openNpcShop"] != undefined) {
                    opened = shopId != "" && _root.gameCommands["openNpcShop"]({shopId:shopId, source:"world_npc_dialogue"});
                }
                if (!opened) {
                    _root.发布消息("商店面板暂时不可用");
                }
            }
            return;
        }
        if (actionId == "hire") {
            if (npc.佣兵数据 != undefined
                    && _root.gameCommands != undefined && _root.gameCommands.openWebHire != undefined) {
                _root.gameCommands.openWebHire({npcId: targetName});
            }
            return;
        }
        if (actionId == "task") {
            if (npc.NPC任务_任务_关卡路径) {
                var taskData:Object = _root.getTaskData(npc.NPC任务_任务_关卡路径);
                if (_root.gameCommands.openWebDungeon != undefined) {
                    _root.gameCommands.openWebDungeon({taskId: taskData.id});
                }
            }
            return;
        }
        if (actionId == "train") {
            if (npc.可学的技能 != undefined) {
                var openResult:Object = {success:false, opened:false};
                if (typeof _root.openSkillTrainer == "function") {
                    openResult = _root.openSkillTrainer(npc, "world_skill_trainer");
                }
                if (!openResult.success || !openResult.opened) {
                    _root.发布消息("技能面板暂时不可用");
                }
            }
            return;
        }
    }
}
