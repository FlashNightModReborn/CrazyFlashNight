using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Text;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;
using CF7Launcher.Data;
using CF7Launcher.Guardian;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// Single source of truth：全部活跃 task 的注册与元数据。
    /// httpCallable 标记在此统一声明，HttpApiServer 通过 IsHttpCallable() 查询。
    ///
    /// Task 清单：
    ///   frame        快车道 F 前缀   AS2→C#  (XmlSocketServer 直分发，不经 MessageRouter)
    ///   hn_reset     快车道 R 前缀   AS2→C#  (同上)
    ///   toast        JSON sync      AS2→C#  httpCallable=true
    ///   gomoku_eval  JSON async     AS2↔C#  httpCallable=true
    ///   data_query   JSON async     AS2↔C#  httpCallable=true
    ///   audio        JSON async     AS2↔C#  httpCallable=false
    ///   sfx          快车道 S 前缀   AS2→C#  (XmlSocketServer 直分发，不经 MessageRouter)
    ///   console      JSON push      C#→AS2  (HttpApiServer /console 专用端点)
    ///   console_result  JSON event  AS2→C#  (内部事件，触发 OnConsoleResult)
    ///   icon_bake       JSON sync   AS2↔C#  (图标烘焙：begin/chunk/end/complete)
    ///   archive         JSON async  AS2↔C#  httpCallable=true  (存档shadow备份/读取)
    ///   panel_request   JSON sync   AS2→C#  (旧 Flash UI 请求 WebView 打开面板: map / stage-select)
    ///   stage_select_response JSON async AS2↔C# (选关 Web panel 测试入口)
    ///   arena_response  JSON async AS2↔C# (角斗场 Web panel 测试入口)
    ///   hairdresser_response JSON async AS2↔C# (基地理发店 Web panel 运行态)
    ///   settings_response JSON async AS2↔C# (设置 Web panel 运行态)
    ///   pet_response    JSON async AS2↔C# (战宠 Web panel 运行态)
    ///   merc_response   JSON async AS2↔C# (佣兵 Web panel 运行态)
    ///   task_response   JSON async AS2↔C# (任务 Web panel 运行态)
    ///   intelligence_response JSON async AS2↔C# (情报 Web panel runtime 状态 / tooltip)
    ///   font_pack       JSON async AS2↔C#  httpCallable=true (字体包按需下载/状态查询)
    /// </summary>
    public static class TaskRegistry
    {
        private static readonly HashSet<string> _httpCallable = new HashSet<string>();
        private static readonly object _audioV2RoutesLock = new object();
        private static readonly ConditionalWeakTable<MessageRouter, AudioTask>
            _audioV2Routes =
                new ConditionalWeakTable<MessageRouter, AudioTask>();

        /// <summary>
        /// 检查 task 是否允许经 HTTP /task 端点调用。
        /// 唯一真相源：由 ToStatusJson 中的 AppendTask 声明自动收集。
        /// </summary>
        public static bool IsHttpCallable(string taskName)
        {
            return _httpCallable.Contains(taskName);
        }

        internal static bool TryReadPanelOpenRequestId(
            JObject request,
            string panel,
            string source,
            out string openRequestId,
            out string rejectionReason)
        {
            openRequestId =
                null;
            rejectionReason =
                null;
            if (request == null)
            {
                rejectionReason =
                    "invalid_request";
                return false;
            }

            JToken token =
                request["openRequestId"];
            JObject initData =
                request["initData"] as JObject;
            bool materialAttempt =
                IsMaterialPanelOpenAttempt(
                    request,
                    source);
            if (materialAttempt)
            {
                bool hasOpenRequestId =
                    request.Property(
                        "openRequestId") != null;
                if (!IsExactMaterialPanelRequest(
                        request,
                        hasOpenRequestId))
                {
                    rejectionReason =
                        "material_contract";
                    return false;
                }
                if (!hasOpenRequestId)
                    return true;
                if (token == null
                    || token.Type
                        != JTokenType.String)
                {
                    rejectionReason =
                        "invalid_open_request_id_type";
                    return false;
                }
                string materialValue =
                    token.Value<string>();
                if (!IsOpaqueOpenRequestId(
                        materialValue))
                {
                    rejectionReason =
                        "invalid_open_request_id";
                    return false;
                }
                openRequestId =
                    materialValue;
                return true;
            }
            bool nativeEquipmentTuningAttempt =
                IsNativeEquipmentTuningOpenAttempt(
                    request,
                    source);
            if (nativeEquipmentTuningAttempt)
            {
                bool hasOpenRequestId =
                    request.Property(
                        "openRequestId") != null;
                if (!IsExactNativeEquipmentTuningPanelRequest(
                        request,
                        hasOpenRequestId))
                {
                    rejectionReason =
                        "native_equipment_tuning_contract";
                    return false;
                }
                if (!hasOpenRequestId)
                {
                    rejectionReason =
                        "missing_open_request_id";
                    return false;
                }
                if (token == null
                    || token.Type
                        != JTokenType.String)
                {
                    rejectionReason =
                        "invalid_open_request_id_type";
                    return false;
                }
                string tuningValue =
                    token.Value<string>();
                if (!IsOpaqueOpenRequestId(
                        tuningValue))
                {
                    rejectionReason =
                        "invalid_open_request_id";
                    return false;
                }
                openRequestId =
                    tuningValue;
                return true;
            }
            bool exactNativeEquipmentBuild =
                string.Equals(
                    panel,
                    "workbench",
                    StringComparison.Ordinal)
                && string.Equals(
                    source,
                    "nativehud_equipment",
                    StringComparison.Ordinal)
                && initData != null
                && initData.Count == 2
                && initData["profile"] != null
                && initData["profile"].Type
                    == JTokenType.String
                && string.Equals(
                    initData.Value<string>("profile"),
                    "battlebox",
                    StringComparison.Ordinal)
                && initData["view"] != null
                && initData["view"].Type
                    == JTokenType.String
                && string.Equals(
                    initData.Value<string>("view"),
                    "build",
                    StringComparison.Ordinal);
            bool supportsOpenRequestId =
                string.Equals(
                    panel,
                    "skills",
                    StringComparison.Ordinal)
                || exactNativeEquipmentBuild;

            if (exactNativeEquipmentBuild
                && token == null)
            {
                rejectionReason =
                    "missing_open_request_id";
                return false;
            }
            if (token == null)
                return true;
            if (!supportsOpenRequestId)
            {
                rejectionReason =
                    "unexpected_open_request_id";
                return false;
            }
            if (token.Type != JTokenType.String)
            {
                rejectionReason =
                    "invalid_open_request_id_type";
                return false;
            }
            string value =
                token.Value<string>();
            if (!IsOpaqueOpenRequestId(value))
            {
                rejectionReason =
                    "invalid_open_request_id";
                return false;
            }
            openRequestId =
                value;
            return true;
        }

        private static bool IsOpaqueOpenRequestId(
            string value)
        {
            if (string.IsNullOrEmpty(value)
                || value.Length > 160)
            {
                return false;
            }
            for (int i = 0; i < value.Length; i++)
            {
                char c =
                    value[i];
                bool allowed =
                    (c >= 'A' && c <= 'Z')
                    || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9')
                    || c == '.'
                    || c == '_'
                    || c == '~'
                    || c == '-';
                if (!allowed)
                    return false;
            }
            return true;
        }

        private static bool IsNativeEquipmentTuningOpenAttempt(
            JObject request,
            string source)
        {
            if (string.Equals(
                    source,
                    "nativehud_equipment_tuning",
                    StringComparison.Ordinal))
            {
                return true;
            }
            JToken token =
                request == null
                    ? null
                    : request["openRequestId"];
            return token != null
                && token.Type == JTokenType.String
                && token.Value<string>()
                    .StartsWith(
                        "tuning.open.",
                        StringComparison.Ordinal);
        }

        private static bool IsExactNativeEquipmentTuningPanelRequest(
            JObject request,
            bool hasOpenRequestId)
        {
            if (request == null
                || request.Count
                    != (hasOpenRequestId ? 5 : 4)
                || request["task"] == null
                || request["task"].Type
                    != JTokenType.String
                || !string.Equals(
                    request.Value<string>("task"),
                    "panel_request",
                    StringComparison.Ordinal)
                || request["panel"] == null
                || request["panel"].Type
                    != JTokenType.String
                || !string.Equals(
                    request.Value<string>("panel"),
                    "workbench",
                    StringComparison.Ordinal)
                || request["source"] == null
                || request["source"].Type
                    != JTokenType.String
                || !string.Equals(
                    request.Value<string>("source"),
                    "nativehud_equipment_tuning",
                    StringComparison.Ordinal))
            {
                return false;
            }
            JObject initData =
                request["initData"] as JObject;
            return initData != null
                && initData.Count == 2
                && initData["profile"] != null
                && initData["profile"].Type
                    == JTokenType.String
                && string.Equals(
                    initData.Value<string>("profile"),
                    "battlebox",
                    StringComparison.Ordinal)
                && initData["view"] != null
                && initData["view"].Type
                    == JTokenType.String
                && string.Equals(
                    initData.Value<string>("view"),
                    "tuning",
                    StringComparison.Ordinal);
        }

        private static bool IsMaterialPanelOpenAttempt(
            JObject request,
            string source)
        {
            if (string.Equals(
                    source,
                    "nativehud_materials",
                    StringComparison.Ordinal))
            {
                return true;
            }
            JToken token =
                request == null
                    ? null
                    : request["openRequestId"];
            return token != null
                && token.Type == JTokenType.String
                && token.Value<string>()
                    .StartsWith(
                        "material.open.",
                        StringComparison.Ordinal);
        }

        private static bool IsExactMaterialPanelRequest(
            JObject request,
            bool hasOpenRequestId)
        {
            if (request == null
                || request.Count
                    != (hasOpenRequestId ? 5 : 4)
                || request["task"] == null
                || request["task"].Type
                    != JTokenType.String
                || !string.Equals(
                    request.Value<string>("task"),
                    "panel_request",
                    StringComparison.Ordinal)
                || request["panel"] == null
                || request["panel"].Type
                    != JTokenType.String
                || !string.Equals(
                    request.Value<string>("panel"),
                    "crafting",
                    StringComparison.Ordinal)
                || request["source"] == null
                || request["source"].Type
                    != JTokenType.String
                || !string.Equals(
                    request.Value<string>("source"),
                    "nativehud_materials",
                    StringComparison.Ordinal))
            {
                return false;
            }
            JObject initData =
                request["initData"] as JObject;
            return initData != null
                && initData.Count == 1
                && initData["view"] != null
                && initData["view"].Type
                    == JTokenType.String
                && string.Equals(
                    initData.Value<string>("view"),
                    "materials",
                    StringComparison.Ordinal);
        }

        /// <summary>
        /// Installs both Audio Platform v2 ingress paths against the same task/facade.
        /// The weak router binding lets XmlSocketServer route the S2 fast lane without
        /// introducing a process-global task; repeated registration of the same pair is
        /// idempotent so Program can install it before the listener is exposed.
        /// </summary>
        internal static void RegisterAudioV2(
            MessageRouter router,
            AudioTask audio)
        {
            if (router == null) throw new ArgumentNullException("router");
            if (audio == null) throw new ArgumentNullException("audio");

            lock (_audioV2RoutesLock)
            {
                AudioTask existing;
                if (!_audioV2Routes.TryGetValue(router, out existing) ||
                    !object.ReferenceEquals(existing, audio))
                {
                    router.RegisterAsync("audio", audio.HandleAsync);
                    _audioV2Routes.Remove(router);
                    _audioV2Routes.Add(router, audio);
                }
            }
            audio.BindAsProcessFacade();
        }

        /// <summary>
        /// Called only by the XMLSocket S2 prefix route.  The connection generation is
        /// intentionally absent: it remains a transport fence in XmlSocketServer.
        /// </summary>
        internal static bool TryDispatchAudioSfxV2(
            MessageRouter router,
            string message)
        {
            if (router == null) return false;
            AudioTask audio;
            if (!_audioV2Routes.TryGetValue(router, out audio)
                || audio == null)
            {
                return false;
            }
            return audio.HandleSfxFastLane(message);
        }

        /// <summary>
        /// 向 MessageRouter 注册所有 JSON 路由的 task（快车道 task 不在此注册）。
        /// </summary>
        public static void RegisterAll(
            MessageRouter router,
            GomokuTask gomoku,
            ToastTask toast,
            FrameTask frame,
            StageOutcomeTask stageOutcomeTask,
            DataQueryTask dataQuery,
            AudioTask audio,
            IconBakeTask iconBake,
            DollBakeTask dollBakeTask,
            ShopTask shopTask,
            InventoryTask inventoryTask,
            LootTask lootTask,
            LootFeedTask lootFeedTask,
            LootPanelCoordinator lootPanelCoordinator,
            NpcShopTask npcShopTask,
            CraftingTask craftingTask,
            MaterialShopAccessTask materialShopAccessTask,
            HairdresserTask hairdresserTask,
            SettingsTask settingsTask,
            EquipmentTuningTask equipmentTuningTask,
            CharacterBuildTask characterBuildTask,
            SkillTask skillTask,
            MapTask mapTask,
            StageSelectTask stageSelectTask,
            ArenaTask arenaTask,
            ArenaCalibrationTask arenaCalibrationTask,
            AgentControlTask agentControlTask,
            PetTask petTask,
            MercTask mercTask,
            TaskTask taskTask,
            IntelligenceTask intelligenceTask,
            BlackMarketTask blackMarketTask,
            ArchiveTask archiveTask,
            BenchTask benchTask,
            FontPackTask fontPackTask,
            WebOverlayForm webOverlay,
            LauncherCommandRouter commandRouter)
        {
            // JSON 路由 task（经 MessageRouter 分发）
            router.RegisterAsync("gomoku_eval", gomoku.HandleAsync);
            router.RegisterAsync("data_query", dataQuery.HandleAsync);
            router.RegisterSync("toast", toast.Handle);
            if (stageOutcomeTask != null)
                router.RegisterSync("stage_outcome", stageOutcomeTask.Handle);
            // loot feed（左下双向玩家物资/击杀播报）：与地图战利品箱的 "loot_response" 回包是两个域。
            // 仅 native HUD 路径构造了 widget/task；fallback 模式不注册，事件自然无路由。
            if (lootFeedTask != null)
                router.RegisterSync("loot", lootFeedTask.Handle);
            RegisterAudioV2(router, audio);
            router.RegisterSync("icon_bake", iconBake.Handle);
            // 纸娃娃烘焙结果（web→C#）：overlay doll-bake.js 渲染回传 → 原子落盘。
            // 与 loot feed 同域的运行时缓存写入；Web ingress 由 IsWebTaskRouterIngressAllowed 放行。
            if (dollBakeTask != null)
                router.RegisterSync("doll_bake_result", dollBakeTask.Handle);
            if (benchTask != null)
            {
                router.RegisterSync("bench_sync", benchTask.HandleSync);
                router.RegisterAsync("bench_async", benchTask.HandleAsync);
                router.RegisterSync("bench_push", benchTask.HandlePush);
            }

            // 商城面板回包路由
            if (shopTask != null)
                router.RegisterAsync("shop_response", shopTask.HandleFlashResponse);

            // 双栏工作台共享 inventory-domain 回包路由
            if (inventoryTask != null)
                router.RegisterAsync("inventory_response", inventoryTask.HandleFlashResponse);

            // 地图战利品箱专用 authority 回包；Web ingress 由 WebOverlayForm 直接交给
            // LootTask，以保留“仅 Web origin”边界，不能注册成通用 socket/http request task。
            if (lootTask != null)
                router.RegisterAsync("loot_response", lootTask.HandleFlashResponse);

            // NPC 金币商店 domain 回包路由
            if (npcShopTask != null)
                router.RegisterAsync("npcshop_response", npcShopTask.HandleFlashResponse);

            // 合成工作台 domain 回包路由
            if (craftingTask != null)
                router.RegisterAsync("crafting_response", craftingTask.HandleFlashResponse);

            // 材料档案 -> NPCShop 的 Host-only authority correlation。Web ingress 不注册
            // 通用 task；只有 dedicated AS2 response 能进入此 handler。
            if (materialShopAccessTask != null)
                router.RegisterAsync(
                    "material_shop_access_response",
                    materialShopAccessTask.HandleFlashResponse);

            // 基地理发店 domain 回包路由
            if (hairdresserTask != null)
                router.RegisterAsync("hairdresser_response", hairdresserTask.HandleFlashResponse);

            // 游戏设置 / 键位 / 调试救援 domain 回包路由
            if (settingsTask != null)
                router.RegisterAsync("settings_response", settingsTask.HandleFlashResponse);

            // 装备调制 domain 回包路由
            if (equipmentTuningTask != null)
                router.RegisterAsync("equipment_tuning_response", equipmentTuningTask.HandleFlashResponse);

            // 角色构筑 loadout domain 回包。Web ingress 只由 WebOverlayForm exact-instance
            // 路由进入，不能把它注册成通用 socket/http request task。
            if (characterBuildTask != null)
                router.RegisterAsync("loadout_response", characterBuildTask.HandleFlashResponse);

            // 独立技能面板 domain 回包路由
            if (skillTask != null)
                router.RegisterAsync("skill_response", skillTask.HandleFlashResponse);

            // 地图面板回包路由
            if (mapTask != null)
                router.RegisterAsync("map_response", mapTask.HandleFlashResponse);

            // 选关面板回包路由
            if (stageSelectTask != null)
                router.RegisterAsync("stage_select_response", stageSelectTask.HandleFlashResponse);

            // 角斗场面板回包路由
            if (arenaTask != null)
                router.RegisterAsync("arena_response", arenaTask.HandleFlashResponse);

            if (arenaCalibrationTask != null)
            {
                router.RegisterSync("arena_calibration", arenaCalibrationTask.HandleControl);
                router.RegisterAsync("arena_calibration_response", arenaCalibrationTask.HandleFlashResponse);
            }

            if (agentControlTask != null)
            {
                router.RegisterSync("agent_control", agentControlTask.Handle);
                router.RegisterSync("agent_runtime_status", agentControlTask.HandleRuntimeStatus);
            }

            // 战宠面板回包路由
            if (petTask != null)
                router.RegisterAsync("pet_response", petTask.HandleFlashResponse);

            // 佣兵面板回包路由
            if (mercTask != null)
                router.RegisterAsync("merc_response", mercTask.HandleFlashResponse);

            // 任务面板回包路由
            if (taskTask != null)
                router.RegisterAsync("task_response", taskTask.HandleFlashResponse);

            // 情报面板 runtime 回包路由
            if (intelligenceTask != null)
                router.RegisterAsync("intelligence_response", intelligenceTask.HandleFlashResponse);

            // 黑市鉴定（匿名影子测试）domain 回包路由
            if (blackMarketTask != null)
                router.RegisterAsync("blackmarket_response", blackMarketTask.HandleFlashResponse);

            // AS2 → C# 面板打开请求 (旧 Flash 地图界面按钮 / openTaskMap / stage-select 命令接入 WebView)
            if (webOverlay != null)
            {
                router.RegisterSync("cursor_control", webOverlay.HandleCursorControl);

                router.RegisterSync("panel_request", delegate(JObject msg)
                {
                    // fire-and-forget 旧入口字段位于顶层；需要可信 ack 的入口通过
                    // sendTaskWithCallback 放在 payload。两种线形共享同一白名单路由。
                    JObject callbackPayload = msg["payload"] as JObject;
                    JObject request = callbackPayload ?? msg;
                    string panel = request.Value<string>("panel") ?? "";
                    string source = request.Value<string>("source") ?? "as2_request";

                    // 这是生产 loot panel 唯一的 Flash ingress：使用 tracked PanelHost 与 exact identity。
                    // 专用协调器先对顶层 source 和 initData 分别做 exact-shape 校验；queue accepted 明确不是 bound。
                    if (panel == "loot")
                    {
                        if (lootPanelCoordinator == null)
                        {
                            return new JObject
                            {
                                ["success"] = false,
                                ["accepted"] = false,
                                ["bound"] = false,
                                ["panel"] = "loot",
                                ["error"] = "panel_unavailable"
                            }.ToString(Newtonsoft.Json.Formatting.None);
                        }
                        return lootPanelCoordinator.HandlePanelRequest(request);
                    }
                    string pageId = request.Value<string>("pageId") ?? "";
                    string frameLabel = request.Value<string>("frameLabel") ?? "";
                    string returnFrameLabel = request.Value<string>("returnFrameLabel") ?? "";
                    // returnTo 是 panel 嵌套返回路径：调用方（AS2）显式声明"关闭本 panel 后回到哪里"。
                    // 唯一调用方：StageSelectPanelService.requestOpenArenaPanel（returnTo="stage-select"
                    // + returnToInitData 含 frameLabel/returnFrameLabel）。其他 panel 传 null/空。
                    string returnToPanel = request.Value<string>("returnTo") ?? "";
                    JToken returnToInitDataToken = request["returnToInitData"];
                    string returnToInitDataJson = returnToInitDataToken != null
                        ? returnToInitDataToken.ToString(Newtonsoft.Json.Formatting.None)
                        : null;
                    // initData 是 panel-specific 额外字段，被 LauncherCommandRouter merge 到 base initData。
                    // 当前唯一用法：stage-select 角斗场重定向时携带 {difficulty:"冒险"}，让 arena enter
                    // 时能回传 difficulty 给 AS2，使任务系统 FinishStage 能匹配 stage#difficulty 规则。
                    JToken initDataToken = request["initData"];
                    string initDataExtrasJson = initDataToken != null
                        ? initDataToken.ToString(Newtonsoft.Json.Formatting.None)
                        : null;
                    string openRequestId;
                    string openRequestIdRejection;
                    if (!TryReadPanelOpenRequestId(
                            request,
                            panel,
                            source,
                            out openRequestId,
                            out openRequestIdRejection))
                    {
                        if (commandRouter != null
                            && IsNativeEquipmentTuningOpenAttempt(
                                request,
                                source))
                        {
                            commandRouter
                                .RejectPendingNativeEquipmentTuningPanelRequest(
                                    openRequestIdRejection);
                        }
                        if (commandRouter != null
                            && request.Property(
                                "openRequestId") != null
                            && IsMaterialPanelOpenAttempt(
                                request,
                                source))
                        {
                            commandRouter
                                .RejectPendingMaterialPanelRequest(
                                    openRequestIdRejection);
                        }
                        LogManager.Log(
                            "event=panel_open_rejected reason="
                            + openRequestIdRejection
                            + " panel=" + panel
                            + " source=" + source);
                        return null;
                    }

                    webOverlay.RequestOpenPanel(panel, source, pageId, frameLabel, returnFrameLabel,
                        returnToPanel, returnToInitDataJson, initDataExtrasJson,
                        openRequestId);
                    return null;
                });
            }

            // 存档 shadow 备份
            if (archiveTask != null)
                router.RegisterAsync("archive", archiveTask.HandleAsync);

            // 字体包按需下载
            if (fontPackTask != null)
                router.RegisterAsync("font_pack", fontPackTask.HandleAsync);

            // C4: AS2 兜底 fffd 扫描结果上报 (loadAll 末尾扫一次).
            //   载荷: { slot, fffdCount, keyHits, sampled, elapsedMs, paths }.
            //   仅记日志, 不阻断游戏 (fire-and-forget).
            router.RegisterSync("save_corrupt_late", delegate(JObject msg)
            {
                try
                {
                    string slot = msg.Value<string>("slot") ?? "?";
                    int fffd = msg.Value<int?>("fffdCount") ?? 0;
                    int keys = msg.Value<int?>("keyHits") ?? 0;
                    bool sampled = msg.Value<bool?>("sampled") ?? false;
                    int elapsed = msg.Value<int?>("elapsedMs") ?? -1;
                    JArray paths = msg.Value<JArray>("paths");
                    string pathsStr = (paths != null && paths.Count > 0)
                        ? string.Join(", ", paths.ToObject<string[]>())
                        : "(none)";
                    LogManager.Log("[SaveCorruptLate] slot=" + slot
                        + " fffd=" + fffd + " keyHits=" + keys
                        + " sampled=" + sampled + " elapsedMs=" + elapsed
                        + " paths=[" + pathsStr + "]");
                }
                catch (Exception ex)
                {
                    LogManager.Log("[SaveCorruptLate] handler exception: " + ex.Message);
                }
                return null;
            });

            // JSON 回退路径：frame/hn_reset 的 JSON 格式兼容入口
            // 正常流量走快车道（XmlSocketServer 前缀检测），此处仅作防御性保留
            router.RegisterSync("frame", frame.Handle);
            router.RegisterSync("hn_reset", delegate(JObject msg)
            {
                frame.HandleReset();
                return null;
            });

            // console / console_result 不在此注册：
            //   console_result 由 MessageRouter 内部特殊处理（OnConsoleResult 事件）
            //   console 是 HttpApiServer /console 端点主动推送到 AS2

            // 初始化 httpCallable 集合（与 ToStatusJson 元数据同步）
            BuildTaskMetadata();
        }

        /// <summary>
        /// 生成 /status 端点的 JSON 响应。
        /// </summary>
        public static string ToStatusJson(bool socketConnected, int httpPort, int socketPort)
        {
            StringBuilder sb = new StringBuilder(512);
            sb.Append("{\"ok\":true,\"socketConnected\":");
            sb.Append(socketConnected ? "true" : "false");
            sb.Append(",\"httpPort\":");
            sb.Append(httpPort);
            sb.Append(",\"socketPort\":");
            sb.Append(socketPort);
            sb.Append(",\"tasks\":[");

            BuildTaskList(sb);

            sb.Append("]}");
            return sb.ToString();
        }

        /// <summary>
        /// 全量 task 清单（含元数据）。httpCallable 标记在此声明，同时驱动
        /// _httpCallable 集合和 /status JSON 输出，消除双写不一致风险。
        /// </summary>
        private static void BuildTaskList(StringBuilder sb)
        {
            bool first = true;
            first = AppendTask(sb, "frame",          "fast_lane", "AS2->C#", false, first);
            first = AppendTask(sb, "hn_reset",       "fast_lane", "AS2->C#", false, first);
            first = AppendTask(sb, "toast",          "json_sync", "AS2->C#", true,  first);
            first = AppendTask(sb, "loot",           "json_sync", "AS2->C#", false, first);
            first = AppendTask(sb, "gomoku_eval",    "json_async","AS2<->C#",true,  first);
            first = AppendTask(sb, "data_query",     "json_async","AS2<->C#",true,  first);
            first = AppendTask(sb, "audio",          "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "sfx",            "fast_lane", "AS2->C#", false, first);
            first = AppendTask(sb, "console",        "json_push", "C#->AS2", false, first);
            first = AppendTask(sb, "console_result", "json_event","AS2->C#", false, first);
            first = AppendTask(sb, "icon_bake",      "json_sync", "AS2<->C#",false, first);
            first = AppendTask(sb, "shop_response",  "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "inventory_response","json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "loot_response",     "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "npcshop_response",  "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "crafting_response", "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "material_shop_access_response", "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "hairdresser_response","json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "settings_response",  "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "equipment_tuning_response","json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "loadout_response", "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "skill_response",    "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "map_response",   "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "stage_select_response","json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "arena_response",       "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "arena_calibration",    "json_sync", "AS2<->C#",true,  first);
            first = AppendTask(sb, "arena_calibration_response","json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "agent_control",        "json_sync", "HTTP->C#", true, first);
            first = AppendTask(sb, "agent_runtime_status", "json_sync", "AS2->C#", false, first);
            first = AppendTask(sb, "pet_response",         "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "merc_response",        "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "task_response",        "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "intelligence_response","json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "cursor_control", "json_sync", "AS2->C#", false, first);
            first = AppendTask(sb, "panel_request",  "json_sync", "AS2->C#", false, first);
            first = AppendTask(sb, "archive",        "json_async","AS2<->C#",true,  first);
            first = AppendTask(sb, "bench_sync",     "json_sync", "AS2<->C#",false, first);
            first = AppendTask(sb, "bench_async",    "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "bench_push",     "json_push", "AS2<->C#",false, first);
            first = AppendTask(sb, "font_pack",      "json_async","AS2<->C#",true,  first);
        }

        /// <summary>
        /// 从 BuildTaskList 中提取 httpCallable 集合。只在 RegisterAll 时调用一次。
        /// </summary>
        private static void BuildTaskMetadata()
        {
            _httpCallable.Clear();
            // 用 null sb 调用 AppendTask，仅收集 httpCallable 标记
            BuildTaskList(null);
        }

        private static bool AppendTask(StringBuilder sb, string name, string transport,
                                         string direction, bool httpCallable, bool first)
        {
            if (httpCallable)
                _httpCallable.Add(name);

            if (sb != null)
            {
                if (!first) sb.Append(",");
                sb.Append("{\"name\":\"").Append(name).Append("\"");
                sb.Append(",\"transport\":\"").Append(transport).Append("\"");
                sb.Append(",\"direction\":\"").Append(direction).Append("\"");
                sb.Append(",\"httpCallable\":").Append(httpCallable ? "true" : "false");
                sb.Append("}");
            }
            return false;
        }
    }
}
