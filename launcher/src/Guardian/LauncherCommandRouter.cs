using System;
using System.Windows.Forms;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 按钮命令唯一中枢。WebOverlayForm.HandleButtonClick 与 Phase 4+ 的 C# widget
    /// 都通过 Dispatch(key, rawJson) 路由到这里。
    ///
    /// 职责：
    /// - 透传 Flash 内功能键（Q/W/R/P/O）→ _onSendKey
    /// - 全屏 / 日志 / 强退 → _onToggleFullscreen / _onToggleLog / _onForceExit
    /// - 游戏命令 → _socketServer 直发
    /// - Panel 打开 → _panelHost.OpenPanel（Flag ON）或 PostToWeb panel_cmd open + 旧 state callback（Flag OFF / _panelHost==null）
    ///
    /// 关键不变量：
    /// - Phase 2+ 起 panel 打开必须走 _panelHost.OpenPanel 才能触发 backdrop/EX_STYLE/HUD-suspend 序列；
    ///   Flag OFF 走 PostToWeb fallback 保证回滚路径行为等价。
    /// - 路由本身不持任何业务状态（_activePanel 等仍在 WebOverlayForm 跟踪，与旧路径一致）。
    /// </summary>
    public class LauncherCommandRouter
    {
        private readonly Bus.XmlSocketServer _socketServer;
        private readonly Action<Keys> _onSendKey;
        private readonly Action _onToggleFullscreen;
        private readonly Action _onToggleLog;
        private readonly Action _onForceExit;
        private readonly Action<string> _postToWeb;
        private readonly Action<bool> _onPanelStateChanged;
        private readonly Action<string> _setActivePanel;
        private PanelHostController _panelHost;
        private string _activeFallbackPanelInstanceId;
        private string _activeFallbackPanelName;
        private string _deferredFallbackSkillInitData;
        private static long _fallbackPanelInstanceSequence;
        private SkillTask _skillTask;
        private EquipmentTuningTask _equipmentTuningTask;
        private CharacterBuildTask _characterBuildTask;
        private Func<string, bool> _fallbackVisualRetire;
        private Func<string, bool> _gameCommandSenderOverride;
        private Func<bool> _panelAdmissionGate;
        private readonly object _skillOpenLock = new object();
        private System.Threading.Timer _skillOpenTimer;
        private int _skillOpenGeneration;
        private bool _skillOpenPending;
        private string _skillOpenRequestId;
        private string _skillOpenOrigin;
        private string _skillOpenBaselinePanel;
        private string _skillOpenBaselineInstance;
        private readonly object _characterBuildSkillsNavigationLock =
            new object();
        private string _pendingCharacterBuildSkillsNavigationInstance;
        private Action _beforeCharacterBuildSkillsNavigationConsumeForTests;
        private readonly object _nativeEquipmentBuildOpenLock = new object();
        private System.Threading.Timer _nativeEquipmentBuildOpenTimer;
        private int _nativeEquipmentBuildOpenGeneration;
        private bool _nativeEquipmentBuildOpenPending;
        private string _nativeEquipmentBuildOpenBaselinePanel;
        private string _nativeEquipmentBuildOpenBaselineInstance;
        internal int SkillOpenTimeoutMs { get; set; } = 1800;
        internal int NativeEquipmentBuildOpenTimeoutMs { get; set; } = 1800;

        public LauncherCommandRouter(
            Bus.XmlSocketServer socketServer,
            Action<Keys> onSendKey,
            Action onToggleFullscreen,
            Action onToggleLog,
            Action onForceExit,
            Action<string> postToWeb,
            Action<bool> onPanelStateChanged,
            Action<string> setActivePanel)
        {
            _socketServer = socketServer;
            _onSendKey = onSendKey;
            _onToggleFullscreen = onToggleFullscreen;
            _onToggleLog = onToggleLog;
            _onForceExit = onForceExit;
            _postToWeb = postToWeb;
            _onPanelStateChanged = onPanelStateChanged;
            _setActivePanel = setActivePanel;
            WebInventoryWorkbenchEnabled = !string.Equals(
                Environment.GetEnvironmentVariable("CF7_WEB_INVENTORY_WORKBENCH"),
                "0",
                StringComparison.Ordinal);
        }

        /// <summary>二阶段注入：Program.cs 先 new Router，再 new PanelHostController(...)，最后 SetPanelHost 回注。</summary>
        public void SetPanelHost(PanelHostController host) { _panelHost = host; }
        public void SetSkillTask(SkillTask task) { _skillTask = task; }
        public void SetEquipmentTuningTask(EquipmentTuningTask task) { _equipmentTuningTask = task; }
        public void SetCharacterBuildTask(CharacterBuildTask task) { _characterBuildTask = task; }
        internal void SetFallbackVisualRetire(Func<string, bool> retire)
        {
            _fallbackVisualRetire = retire;
        }
        internal void SetGameCommandSenderForTests(Func<string, bool> sender) { _gameCommandSenderOverride = sender; }
        internal void SetBeforeCharacterBuildSkillsNavigationConsumeForTests(Action action)
        {
            _beforeCharacterBuildSkillsNavigationConsumeForTests = action;
        }
        internal void SetPanelAdmissionGate(Func<bool> gate)
        {
            _panelAdmissionGate = gate;
        }
        internal string ActiveFallbackPanelInstanceId { get { return _activeFallbackPanelInstanceId; } }
        internal string ActiveFallbackPanelName { get { return _activeFallbackPanelName; } }
        internal string PendingCharacterBuildSkillsNavigationInstance
        {
            get
            {
                lock (_characterBuildSkillsNavigationLock)
                    return _pendingCharacterBuildSkillsNavigationInstance;
            }
        }

        /// <summary>
        /// Arms the single exact-instance Character Build -> Skills intent.  The intent does not
        /// open either surface: WebOverlay must still run the normal CharacterBuild close barrier,
        /// visual retire, and acknowledged AS2 recovery before the coordinator-settled callback
        /// may send the existing skillPanelOpen preflight.
        /// </summary>
        internal bool TryArmCharacterBuildSkillsNavigation(
            string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId))
                return false;
            CharacterBuildTask task = _characterBuildTask;
            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : _activeFallbackPanelName;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : _activeFallbackPanelInstanceId;
            if (task == null
                || !task.IsBoundTo(panelInstanceId)
                || !task.CanRebind
                || task.RequiresDetachRecovery
                || !string.Equals(
                    activePanel, "workbench",
                    StringComparison.Ordinal)
                || !string.Equals(
                    activeInstance, panelInstanceId,
                    StringComparison.Ordinal))
            {
                return false;
            }
            lock (_characterBuildSkillsNavigationLock)
            {
                if (_pendingCharacterBuildSkillsNavigationInstance != null)
                    return false;
                if (!task.IsBoundTo(panelInstanceId)
                    || !task.CanRebind
                    || task.RequiresDetachRecovery)
                {
                    return false;
                }
                _pendingCharacterBuildSkillsNavigationInstance =
                    panelInstanceId;
            }
            LogManager.Log(
                "event=character_build_skills_navigation_armed panel_instance="
                + panelInstanceId);
            return true;
        }

        internal bool CancelCharacterBuildSkillsNavigation(
            string panelInstanceId,
            string reason)
        {
            if (string.IsNullOrEmpty(panelInstanceId))
                return false;
            lock (_characterBuildSkillsNavigationLock)
            {
                if (!string.Equals(
                    _pendingCharacterBuildSkillsNavigationInstance,
                    panelInstanceId,
                    StringComparison.Ordinal))
                {
                    return false;
                }
                ClearCharacterBuildSkillsNavigationLocked();
            }
            LogManager.Log(
                "event=character_build_skills_navigation_cancelled panel_instance="
                + panelInstanceId + " reason="
                + (reason ?? "unknown"));
            return true;
        }

        /// <summary>
        /// Called only from CharacterBuildTask's coordinator-settled callback.  A true result means
        /// an armed handoff was consumed and competing deferred opens must not be replayed for this
        /// edge-triggered navigation.
        /// </summary>
        internal bool TryCompleteCharacterBuildSkillsNavigation()
        {
            string panelInstanceId;
            lock (_characterBuildSkillsNavigationLock)
            {
                panelInstanceId =
                    _pendingCharacterBuildSkillsNavigationInstance;
                if (panelInstanceId == null) return false;
            }

            CharacterBuildTask task = _characterBuildTask;
            if (task == null
                || task.HasBoundPanel
                || task.RequiresDetachRecovery)
            {
                CancelCharacterBuildSkillsNavigation(
                    panelInstanceId,
                    "coordinator_not_settled");
                return false;
            }
            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : _activeFallbackPanelName;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : _activeFallbackPanelInstanceId;
            if (!string.IsNullOrEmpty(activePanel)
                || !string.IsNullOrEmpty(activeInstance))
            {
                CancelCharacterBuildSkillsNavigation(
                    panelInstanceId,
                    "visual_not_idle");
                return false;
            }

            Action beforeConsume =
                _beforeCharacterBuildSkillsNavigationConsumeForTests;
            if (beforeConsume != null)
                beforeConsume();

            lock (_characterBuildSkillsNavigationLock)
            {
                if (!string.Equals(
                    _pendingCharacterBuildSkillsNavigationInstance,
                    panelInstanceId,
                    StringComparison.Ordinal))
                {
                    return false;
                }
                _pendingCharacterBuildSkillsNavigationInstance =
                    null;
            }

            LogManager.Log(
                "event=skill_panel_open_requested source=character_build");
            if (_panelHost != null)
                _panelHost.DiscardDeferredBarrierOpen();
            string openRequestId;
            int generation = BeginSkillOpenWait(
                "character_build",
                out openRequestId);
            if (!TrySendSkillPanelOpenCommand(openRequestId))
            {
                CancelSkillOpenWait(generation);
                LogManager.Log(
                    "event=skill_panel_open_failed source=character_build reason=preflight_send");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"技能面板暂时不可用，请从旧物品界面进入\"}");
            }
            return true;
        }

        private void ClearCharacterBuildSkillsNavigationLocked()
        {
            _pendingCharacterBuildSkillsNavigationInstance = null;
        }

        internal void ClearFallbackPanelInstance()
        {
            _activeFallbackPanelInstanceId = null;
            _activeFallbackPanelName = null;
            _deferredFallbackSkillInitData = null;
        }

        internal void FlushDeferredFallbackSkillRebind()
        {
            if (_panelHost != null || _skillTask == null || !_skillTask.CanRebind) return;
            string initData = _deferredFallbackSkillInitData;
            if (initData == null) return;
            _deferredFallbackSkillInitData = null;
            OpenPanel("skills", initData);
        }

        /// <summary>
        /// SAFEEXIT click → 触发 SafeExitPanelWidget.Arm()。Program.cs 在 widget 实例化后注入。
        /// 必须在 SendGameCommand("safeExit") 之前调，否则 widget 收到 sv:1 时还没 armed，会忽略。
        /// </summary>
        public Action OnSafeExitArm { get; set; }

        /// <summary>
        /// safeExit 命令未送达时通知当前 Native SafeExit session 进入失败态。
        /// Web fallback 由 Router 同时发送 safe_exit_failed，不依赖此回调。
        /// </summary>
        public Action OnSafeExitSendFailed { get; set; }

        /// <summary>
        /// EXIT_CONFIRM 的唯一授权能力。只有当前 armed 且已收到本轮 sv:2 的
        /// SafeExit session 才能消费成功；消费必须是 exact one-shot。
        /// </summary>
        public Func<bool> TryConsumeSafeExitConfirm { get; set; }

        /// <summary>
        /// 来自刘海“地图开关”的 click → 切 C# 小地图显示/关闭。
        /// 地图卡片自己的尺寸按钮不走此路由，只在 compact / expanded 间切换。
        /// </summary>
        public Action OnMapHudToggle { get; set; }

        /// <summary>
        /// 刘海屏战备箱 Web 工作台开关。默认开启；环境变量 CF7_WEB_INVENTORY_WORKBENCH=0
        /// 或运行时显式置 false 时回退旧 Flash warehouse 命令。
        /// </summary>
        public bool WebInventoryWorkbenchEnabled { get; set; }

        public void Dispatch(string key) { Dispatch(key, null); }

        public void Dispatch(string key, string rawJson)
        {
            if (string.IsNullOrEmpty(key)) return;
            switch (key)
            {
                case "Q": SendKey(Keys.Q); break;
                case "W": SendKey(Keys.W); break;
                case "R": SendKey(Keys.R); break;
                case "F": ToggleFullscreen(); break;
                case "P": SendKey(Keys.P); break;
                case "O": SendKey(Keys.O); break;
                case "LOG": ToggleLog(); break;
                case "EXIT": ForceExit(); break;
                case "PAUSE": SendGameCommand("togglePause"); break;
                case "WAREHOUSE":
                    if (WebInventoryWorkbenchEnabled)
                    {
                        LogManager.Log("[Router] WAREHOUSE clicked -> web inventory workbench");
                        OpenInventoryWorkbench("nativehud", "{\"profile\":\"battlebox\",\"view\":\"storage\"}");
                    }
                    else
                    {
                        LogManager.Log("[Router] WAREHOUSE web workbench disabled -> Flash fallback");
                        SendGameCommand("warehouse");
                    }
                    break;
                case "SETTINGS": SendGameCommand("toggleSettings"); break;
                case "SHOP":
                    LogManager.Log("[Router] SHOP clicked");
                    if (TrySendGameCommand("shopPanelOpen"))
                        OpenPanel("kshop", null);
                    else
                    {
                        LogManager.Log("[Router] SHOP shopPanelOpen failed");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"商城暂时不可用\"}");
                    }
                    break;
                case "HELP": OpenPanel("help", null); break;
                case "SAFEEXIT":
                    // Phase 4.2：必须先 Arm widget（否则普通自动存盘也会拉起面板——sv 是通用事件）；再触发 AS2 存盘。
                    // widget Arm 后立即进 Saving 显示状态条；sv:1 推达后保持 Saving；sv:2 切到 Done 显示 取消/退出 按钮。
                    { Action arm = OnSafeExitArm; if (arm != null) arm(); }
                    RouteSafeExit();
                    break;
                case "TEAM":
                    LogManager.Log("[Router] TEAM clicked");
                    if (TrySendGameCommand("mercPanelOpen"))
                        OpenPanel("team", null);
                    else
                    {
                        LogManager.Log("[Router] TEAM mercPanelOpen failed");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"战队面板暂时不可用\"}");
                    }
                    break;
                // 隐藏兼容命令：旧入口仍可打开统一战队面板，但不再注册独立 pets/mercs panel。
                case "PETS":
                    if (TrySendGameCommand("mercPanelOpen"))
                        OpenPanel("team", "{\"initialTab\":\"partner\"}");
                    else
                        PostToWeb("{\"type\":\"toast\",\"text\":\"战队面板暂时不可用\"}");
                    break;
                case "MERCS":
                    if (TrySendGameCommand("mercPanelOpen"))
                        OpenPanel("team", "{\"initialTab\":\"mercenary\"}");
                    else
                        PostToWeb("{\"type\":\"toast\",\"text\":\"战队面板暂时不可用\"}");
                    break;
                case "TABLET": SendGameCommand("toggleTablet"); break;
                case "GAMESETTINGS": SendGameCommand("openSettings"); break;
                case "JUKEBOX": SendGameCommand("openJukebox"); break;
                case "JUKEBOX_EXPAND":
                    // Phase 5：launcher/web/modules/jukebox/jukebox-panel.js 已注册 Panels.register('jukebox')，
                    // OpenPanel 走完整 PanelHostController 序列（backdrop / EX_STYLE / HUD-suspend）。
                    OpenPanel("jukebox", null);
                    break;
                case "TASK_MAP": OpenMapPanel("task_map", null); break;
                case "MAPHUD_TOGGLE":
                    { Action h = OnMapHudToggle; if (h != null) h(); }
                    break;
                case "TASK_DELIVER":
                    {
                        string hotspotId = rawJson != null ? ExtractString(rawJson, "\"hotspotId\":\"") : null;
                        if (string.IsNullOrEmpty(hotspotId))
                        {
                            LogManager.Log("[Router] TASK_DELIVER missing hotspotId");
                            break;
                        }
                        SendGameCommand("navigateToHotspot",
                            "\"targetId\":\"" + EscapeJsonString(hotspotId) + "\"");
                    }
                    break;
                // 刘海屏「☰ 任务」按钮 (TASK_UI) 与旧 web notch「新任务界面」(NEW_TASK_UI)
                // 统一跳转到 web 端任务面板，不再走 AS2 openTaskUI 唤起。
                case "TASK_UI":
                case "NEW_TASK_UI":
                    LogManager.Log("[Router] task UI clicked -> web panel");
                    if (TrySendGameCommand("taskPanelOpen"))
                        OpenPanel("tasks", null);
                    else
                    {
                        LogManager.Log("[Router] task panel taskPanelOpen failed");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"任务面板暂时不可用\"}");
                    }
                    break;
                case "EQUIP_UI":
                    RouteEquipmentUi();
                    break;
                case "MATERIALS":
                    RouteMaterialUi();
                    break;
                case "INTELLIGENCE":
                    OpenPanel("intelligence", "{\"mode\":\"prod\",\"source\":\"runtime\",\"debug\":false}");
                    break;
                case "SKILLS":
                    LogManager.Log("[Router] SKILLS clicked");
                    LogManager.Log("event=skill_panel_open_requested source=notch");
                    string skillOpenRequestId;
                    int skillOpenGeneration = BeginSkillOpenWait(
                        "notch",
                        out skillOpenRequestId);
                    if (!TrySendSkillPanelOpenCommand(
                            skillOpenRequestId))
                    {
                        CancelSkillOpenWait(skillOpenGeneration);
                        LogManager.Log("[Router] SKILLS skillPanelOpen preflight failed");
                        LogManager.Log("event=skill_panel_open_failed reason=preflight_send");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"技能面板暂时不可用，请从旧物品界面进入\"}");
                    }
                    break;
                case "BAKE": SendGameCommand("bakeIcons"); break;
                case "BAKE10": SendGameCommand("bakeIcons", "\"maxCount\":10"); break;
                case "BAKE_SKILL": SendGameCommand("bakeSkillIcons"); break;
                case "LOCKBOX_TEST":
                    {
                        uint familySeed = unchecked((uint)Environment.TickCount);
                        string initData = "{\"mode\":\"dev\",\"profile\":\"standard\",\"source\":\"runtime\",\"familySeed\":" + familySeed + ",\"variantIndex\":0,\"debug\":true}";
                        OpenPanel("lockbox", initData);
                    }
                    break;
                case "PINALIGN_TEST":
                    OpenPanel("pinalign", "{\"mode\":\"dev\",\"specId\":\"mvp-3pin-v1\",\"masterSeed\":\"dev-default\",\"debug\":true}");
                    break;
                case "GOBANG_TEST":
                    OpenPanel("gobang", "{\"mode\":\"dev\",\"source\":\"runtime\",\"ruleset\":\"casual\",\"difficulty\":\"normal\",\"playerRole\":1,\"aiEnabled\":true,\"debug\":true}");
                    break;
                case "INTELLIGENCE_TEST":
                    OpenPanel("intelligence", "{\"mode\":\"dev\",\"source\":\"runtime\",\"itemName\":\"资料\",\"value\":99,\"decryptLevel\":10,\"pcName\":\"测试玩家\",\"debug\":true}");
                    break;
                case "STAGE_SELECT_TEST":
                    OpenPanel("stage-select", "{\"mode\":\"dev\",\"fixture\":\"mixed\",\"frameLabel\":\"基地门口\",\"debug\":true}");
                    break;
                case "DRESSUP_TEST":
                    OpenPanel("dressup", "{\"mode\":\"dev\",\"source\":\"runtime\",\"debug\":true}");
                    break;
                case "ARENA_TEST":
                    OpenPanel("arena", "{\"mode\":\"dev\",\"source\":\"runtime\",\"debug\":true}");
                    break;
                case "CUTSCENE_TEST":
                    // issue #7 bug2：动画测试面板（Ruffle 预览 flashswf/movies/ 过场）
                    OpenPanel("cutscene-test", "{\"mode\":\"dev\",\"source\":\"runtime\",\"debug\":true}");
                    break;
                case "EXIT_CONFIRM":
                    if (ConsumeSafeExitConfirmCapability())
                        ForceExit();
                    break;
                default:
                    LogManager.Log("[Router] unknown key=" + key);
                    break;
            }
        }

        /// <summary>
        /// AS2 → C# panel 打开请求（替代旧 WebOverlayForm.RequestOpenPanel 的 dispatch 段）。
        /// map 透传 pageId；stage-select 透传 frameLabel/returnFrameLabel；workbench 只接收 profile/view 枚举；
        /// npcshop 只接收 shopId；hairdresser 只接受 world_hairdresser 且重建固定 initData；
        /// 其他 panel 保持各自显式分支或 unsupported。
        /// loot 不经过此通用路由；其唯一 Flash ingress 是 TaskRegistry 的 panel_request 专用分支。
        /// </summary>
        public void RequestOpenPanel(string panelName, string source, string pageId)
        {
            RequestOpenPanel(panelName, source, pageId, null, null, null, null, null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId, string frameLabel)
        {
            RequestOpenPanel(panelName, source, pageId, frameLabel, null, null, null, null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId, string frameLabel, string returnFrameLabel)
        {
            RequestOpenPanel(panelName, source, pageId, frameLabel, returnFrameLabel, null, null, null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId, string frameLabel, string returnFrameLabel,
            string returnToPanel, string returnToInitDataJson)
        {
            RequestOpenPanel(panelName, source, pageId, frameLabel, returnFrameLabel, returnToPanel, returnToInitDataJson, null);
        }

        /// <summary>
        /// 完整签名：
        ///   - returnToPanel 非空时，关闭本 panel 后会自动 reopen returnTo（带 returnToInitDataJson）
        ///   - initDataExtrasJson 是 panel-specific 额外字段的 JSON object（例如 arena 接 stage-select
        ///     redirect 时附带的 {"difficulty":"冒险"}），由 caller 显式构造；各 panel 分支只提取自己的
        ///     白名单字段后重建 initData。base 字段（mode/source/debug）由本类负责，AS2 端不需要懂。
        /// </summary>
        public void RequestOpenPanel(string panelName, string source, string pageId, string frameLabel, string returnFrameLabel,
            string returnToPanel, string returnToInitDataJson, string initDataExtrasJson)
        {
            RequestOpenPanel(
                panelName,
                source,
                pageId,
                frameLabel,
                returnFrameLabel,
                returnToPanel,
                returnToInitDataJson,
                initDataExtrasJson,
                null);
        }

        public void RequestOpenPanel(string panelName, string source, string pageId, string frameLabel, string returnFrameLabel,
            string returnToPanel, string returnToInitDataJson, string initDataExtrasJson,
            string skillOpenRequestId)
        {
            if (string.IsNullOrEmpty(panelName)) return;
            string safeSource = string.IsNullOrEmpty(source) ? "as2_request" : source;
            if (string.Equals(panelName, "map", StringComparison.OrdinalIgnoreCase))
            {
                OpenMapPanel(safeSource, pageId);
                return;
            }
            if (string.Equals(panelName, "stage-select", StringComparison.OrdinalIgnoreCase))
            {
                OpenStageSelectPanel(safeSource, frameLabel, returnFrameLabel);
                return;
            }
            if (string.Equals(panelName, "loot", StringComparison.OrdinalIgnoreCase))
            {
                LogManager.Log("event=loot_panel_open_rejected reason=dedicated_panel_request_required");
                return;
            }
            if (string.Equals(panelName, "workbench", StringComparison.OrdinalIgnoreCase))
            {
                if (string.Equals(safeSource, "legacy_equipment_tuning", StringComparison.Ordinal))
                {
                    LogManager.Log("[Router] legacy AS2 equipment tuning redirect paused; keeping native renderer");
                    return;
                }
                OpenInventoryWorkbench(
                    safeSource,
                    initDataExtrasJson,
                    string.Equals(
                        panelName,
                        "workbench",
                        StringComparison.Ordinal));
                return;
            }
            if (string.Equals(panelName, "npcshop", StringComparison.OrdinalIgnoreCase))
            {
                OpenNpcShopPanel(safeSource, initDataExtrasJson);
                return;
            }
            if (string.Equals(panelName, "crafting", StringComparison.OrdinalIgnoreCase))
            {
                OpenCraftingPanel(safeSource, initDataExtrasJson);
                return;
            }
            if (string.Equals(panelName, "hairdresser", StringComparison.OrdinalIgnoreCase))
            {
                OpenHairdresserPanel(safeSource);
                return;
            }
            if (string.Equals(panelName, "skills", StringComparison.OrdinalIgnoreCase))
            {
                OpenSkillsPanel(
                    safeSource,
                    initDataExtrasJson,
                    skillOpenRequestId);
                return;
            }
            if (string.Equals(panelName, "arena", StringComparison.OrdinalIgnoreCase))
            {
                OpenArenaPanel(safeSource, initDataExtrasJson, returnToPanel, returnToInitDataJson);
                return;
            }
            if (string.Equals(panelName, "tasks", StringComparison.OrdinalIgnoreCase))
            {
                OpenTasksPanel(safeSource, initDataExtrasJson);
                return;
            }
            if (string.Equals(panelName, "team", StringComparison.OrdinalIgnoreCase))
            {
                OpenTeamPanel(safeSource, initDataExtrasJson);
                return;
            }
            LogManager.Log("[Router] RequestOpenPanel unsupported panel=" + panelName);
        }

        private void OpenMapPanel(string source, string pageId)
        {
            string initData = "{\"source\":\"" + EscapeJsonString(source) + "\",\"dev\":false";
            if (!string.IsNullOrEmpty(pageId))
                initData += ",\"page\":\"" + EscapeJsonString(pageId) + "\"";
            initData += "}";
            OpenPanel("map", initData);
        }

        private void OpenStageSelectPanel(string source, string frameLabel, string returnFrameLabel)
        {
            string safeFrameLabel = string.IsNullOrEmpty(frameLabel) ? "基地门口" : frameLabel;
            string safeReturnFrameLabel = string.IsNullOrEmpty(returnFrameLabel) ? safeFrameLabel : returnFrameLabel;
            string initData = "{\"mode\":\"runtime\",\"fixture\":\"mixed\",\"frameLabel\":\"" +
                EscapeJsonString(safeFrameLabel) + "\",\"returnFrameLabel\":\"" + EscapeJsonString(safeReturnFrameLabel) +
                "\",\"debug\":false,\"source\":\"" + EscapeJsonString(source) + "\"}";
            OpenPanel("stage-select", initData);
        }

        private bool OpenInventoryWorkbench(
            string source,
            string initDataExtrasJson,
            bool exactPanelName = true)
        {
            string profile = "battlebox";
            string view = "storage";
            JObject extras = null;
            if (!string.IsNullOrEmpty(initDataExtrasJson))
            {
                try
                {
                    extras = JObject.Parse(initDataExtrasJson);
                    string requested = extras.Value<string>("profile");
                    if (!string.IsNullOrEmpty(requested)) profile = requested;
                    string requestedView = extras.Value<string>("view");
                    if (!string.IsNullOrEmpty(requestedView)) view = requestedView;
                }
                catch (Exception ex)
                {
                    LogManager.Log("[Router] OpenInventoryWorkbench extras parse failed: " + ex.Message);
                    return false;
                }
            }
            if (!string.Equals(profile, "warehouse", StringComparison.Ordinal)
                && !string.Equals(profile, "battlebox", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected profile=" + profile);
                return false;
            }
            if (!string.Equals(view, "storage", StringComparison.Ordinal)
                && !string.Equals(view, "tuning", StringComparison.Ordinal)
                && !string.Equals(view, "build", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected view=" + view);
                return false;
            }
            if (view == "tuning" && !string.Equals(profile, "battlebox", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected tuning profile=" + profile);
                return false;
            }
            if (view == "build"
                && (!string.Equals(profile, "battlebox", StringComparison.Ordinal)
                    || (!string.Equals(source, "agent_control", StringComparison.Ordinal)
                        && !string.Equals(
                            source,
                            "nativehud_equipment",
                            StringComparison.Ordinal))))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected build admission profile="
                    + profile + " source=" + (source ?? "<null>"));
                return false;
            }
            if (view == "build"
                && string.Equals(
                    source,
                    "nativehud_equipment",
                    StringComparison.Ordinal))
            {
                string rejectionReason =
                    null;
                bool exactInitData =
                    extras != null
                    && extras.Count == 2
                    && extras["profile"] != null
                    && extras["profile"].Type
                        == JTokenType.String
                    && extras["view"] != null
                    && extras["view"].Type
                        == JTokenType.String;
                if (!exactPanelName
                    || !exactInitData
                    || !TryConsumeNativeEquipmentBuildOpenWait(
                        out rejectionReason))
                {
                    LogManager.Log(
                        "event=character_build_open_rejected source=nativehud_equipment reason="
                        + (!exactPanelName
                            ? "panel_contract"
                            : !exactInitData
                                ? "init_data_contract"
                                : rejectionReason));
                    return false;
                }
            }
            var initData = new JObject
            {
                ["mode"] = "runtime",
                ["profile"] = profile,
                ["view"] = view,
                ["source"] = source,
                ["debug"] = false
            };
            bool opened =
                OpenPanel(
                    "workbench",
                    initData.ToString(
                        Formatting.None));
            if (!opened
                && view == "build"
                && string.Equals(
                    source,
                    "nativehud_equipment",
                    StringComparison.Ordinal))
            {
                LogManager.Log(
                    "event=character_build_open_failed source=nativehud_equipment reason=host_gate");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"装备面板被当前操作阻止，请稍后重试\"}");
            }
            return opened;
        }

        private void OpenNpcShopPanel(string source, string initDataExtrasJson)
        {
            if (string.IsNullOrEmpty(initDataExtrasJson)) return;
            try
            {
                JObject extras = JObject.Parse(initDataExtrasJson);
                string shopId = extras.Value<string>("shopId");
                if (string.IsNullOrEmpty(shopId) || shopId.Length > 80) return;
                for (int i = 0; i < shopId.Length; i++) if (char.IsControl(shopId[i])) return;
                var initData = new JObject
                {
                    ["mode"] = "runtime",
                    ["shopId"] = shopId,
                    ["source"] = source,
                    ["debug"] = false
                };
                OpenPanel("npcshop", initData.ToString(Formatting.None));
            }
            catch (Exception ex)
            {
                LogManager.Log("[Router] OpenNpcShopPanel extras parse failed: " + ex.Message);
            }
        }

        private void OpenCraftingPanel(string source, string initDataExtrasJson)
        {
            if (string.IsNullOrEmpty(initDataExtrasJson)) return;
            try
            {
                JObject extras = JObject.Parse(initDataExtrasJson);
                string category = extras.Value<string>("category");
                if (!IsCraftingCategory(category))
                {
                    LogManager.Log("[Router] OpenCraftingPanel rejected category=" + category);
                    return;
                }
                var initData = new JObject
                {
                    ["mode"] = "runtime",
                    ["category"] = category,
                    ["source"] = source,
                    ["debug"] = false
                };
                OpenPanel("crafting", initData.ToString(Formatting.None));
            }
            catch (Exception ex)
            {
                LogManager.Log("[Router] OpenCraftingPanel extras parse failed: " + ex.Message);
            }
        }

        private void OpenHairdresserPanel(string source)
        {
            if (!string.Equals(source, "world_hairdresser", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenHairdresserPanel rejected source=" + source);
                return;
            }
            var initData = new JObject
            {
                ["mode"] = "runtime",
                ["source"] = "world_hairdresser",
                ["debug"] = false
            };
            OpenPanel("hairdresser", initData.ToString(Formatting.None));
        }

        private static bool IsCraftingCategory(string category)
        {
            switch (category)
            {
                case "铁枪会": case "属性武器": case "烹饪": case "化学生产":
                case "武器合成": case "饰品合成": case "进阶防具": case "基础防具":
                case "公社防具": case "黑白契约": case "插件合成": case "大学装备": return true;
                default: return false;
            }
        }

        private void OpenSkillsPanel(
            string source,
            string initDataExtrasJson,
            string skillOpenRequestId)
        {
            JObject initData;
            if (!TryBuildSkillsInitData(
                    source,
                    initDataExtrasJson,
                    out initData))
            {
                LogManager.Log("[Router] OpenSkillsPanel rejected extras");
                LogManager.Log("event=skill_panel_open_failed reason=invalid_panel_request");
                return;
            }
            string view =
                initData.Value<string>("view");
            string rejectionReason;
            string pendingOrigin;
            if (!TryAdmitSkillPanelRequest(
                    source,
                    view,
                    skillOpenRequestId,
                    out rejectionReason,
                    out pendingOrigin))
            {
                if (view == "trainer"
                    && _skillTask != null)
                {
                    _skillTask.RequestTrainerCleanup(
                        initData.Value<string>(
                            "trainerSession"));
                }
                LogManager.Log(
                    "event=skill_panel_open_rejected reason="
                    + rejectionReason
                    + " source=" + source
                    + " view=" + view
                    + " pending_origin="
                    + (pendingOrigin ?? "none"));
                return;
            }
            if (initData.Value<string>("view") == "trainer" && _skillTask != null && !_skillTask.CanOpenTrainer)
            {
                // 旧写状态/旧教师能力尚未安全清理时，不展示刚由 AS2 建立的新 session。
                // 先打开 manage 完成显式 reconcile；cleanup 落地后玩家可再次与教师交互。
                LogManager.Log("[Router] trainer open downgraded to manage until skill reconcile/cleanup settles");
                LogManager.Log("event=skill_panel_open_fallback reason=trainer_gate target=manage");
                _skillTask.RequestTrainerCleanup(initData.Value<string>("trainerSession"));
                initData = BuildSkillsManageInitData();
            }
            OpenPanel("skills", initData.ToString(Formatting.None));
            LogManager.Log("event=skill_panel_opened view=" + initData.Value<string>("view"));
        }

        internal bool RebindSkillsToManage(string expectedPanelInstanceId, string focusSkillKey)
        {
            string activeName = _panelHost != null ? _panelHost.ActivePanelName : _activeFallbackPanelName;
            string activeInstance = _panelHost != null ? _panelHost.ActivePanelInstanceId : _activeFallbackPanelInstanceId;
            if (_skillTask == null || activeName != "skills" || string.IsNullOrEmpty(activeInstance)
                || !string.Equals(activeInstance, expectedPanelInstanceId, StringComparison.Ordinal)
                || !IsPresentationSkillKey(focusSkillKey)
                || !_skillTask.TrySuspendTrainerForManage(activeInstance))
            {
                LogManager.Log("[Router] rejected stale/malformed skills manage rebind");
                return false;
            }
            OpenPanel("skills", BuildSkillsManageInitData(focusSkillKey).ToString(Formatting.None));
            LogManager.Log("event=skill_panel_rebound from=trainer to=manage");
            return true;
        }

        internal bool RebindSkillsToTrainer(string expectedPanelInstanceId, string focusSkillKey)
        {
            string activeName = _panelHost != null ? _panelHost.ActivePanelName : _activeFallbackPanelName;
            string activeInstance = _panelHost != null ? _panelHost.ActivePanelInstanceId : _activeFallbackPanelInstanceId;
            string trainerSession;
            if (_skillTask == null || activeName != "skills" || string.IsNullOrEmpty(activeInstance)
                || !string.Equals(activeInstance, expectedPanelInstanceId, StringComparison.Ordinal)
                || !IsPresentationSkillKey(focusSkillKey)
                || !_skillTask.TryGetTrainerReturnSession(activeInstance, out trainerSession))
            {
                LogManager.Log("[Router] rejected stale/malformed skills trainer return rebind");
                return false;
            }
            OpenPanel("skills", BuildSkillsTrainerReturnInitData(trainerSession, focusSkillKey).ToString(Formatting.None));
            LogManager.Log("event=skill_panel_rebound from=manage to=trainer source=trainer_return");
            return true;
        }

        private static JObject BuildSkillsManageInitData(string focusSkillKey = null)
        {
            JObject result = new JObject
            {
                ["mode"] = "runtime", ["source"] = "nativehud", ["debug"] = false, ["view"] = "manage"
            };
            if (!string.IsNullOrEmpty(focusSkillKey)) result["focusSkillKey"] = focusSkillKey;
            return result;
        }

        private static JObject BuildSkillsTrainerReturnInitData(string trainerSession, string focusSkillKey)
        {
            JObject result = new JObject
            {
                ["mode"] = "runtime", ["source"] = "world_skill_trainer", ["debug"] = false,
                ["view"] = "trainer", ["trainerSession"] = trainerSession
            };
            if (!string.IsNullOrEmpty(focusSkillKey)) result["focusSkillKey"] = focusSkillKey;
            return result;
        }

        internal static bool IsPresentationSkillKey(string value)
        {
            if (value == null || value.Length > 160) return false;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i]) || char.IsSurrogate(value[i])) return false;
            return true;
        }

        internal static bool TryBuildSkillsInitData(
            string source,
            string initDataExtrasJson,
            out JObject initData)
        {
            initData = null;
            if (string.IsNullOrEmpty(initDataExtrasJson)) return false;
            JObject extras;
            try { extras = JObject.Parse(initDataExtrasJson); }
            catch { return false; }
            string view = extras.Value<string>("view");
            if (view != "manage" && view != "trainer") return false;
            if ((view == "manage"
                    && !string.Equals(
                        source,
                        "nativehud",
                        StringComparison.Ordinal))
                || (view == "trainer"
                    && !string.Equals(
                        source,
                        "world_skill_trainer",
                        StringComparison.Ordinal)))
            {
                return false;
            }
            int expected = view == "trainer" ? 2 : 1;
            if (extras.Count != expected) return false;
            foreach (JProperty property in extras.Properties())
                if (property.Name != "view" && property.Name != "trainerSession") return false;
            string session = extras.Value<string>("trainerSession");
            if (view == "trainer")
            {
                if (!IsOpaqueToken(session)) return false;
            }
            else if (extras["trainerSession"] != null) return false;
            initData = new JObject
            {
                ["mode"] = "runtime",
                ["source"] = view == "trainer" ? "world_skill_trainer" : "nativehud",
                ["debug"] = false,
                ["view"] = view
            };
            if (view == "trainer") initData["trainerSession"] = session;
            return true;
        }

        private static bool IsOpaqueToken(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 160) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                bool allowed = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
                    || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '~' || c == '-';
                if (!allowed) return false;
            }
            return true;
        }

        // 副本任务（委托任务）：NPC「获得任务」→ AS2 openWebDungeon 发 panel_request panel="tasks"，
        // initData={view:"dungeon",taskId}。与刘海屏 TASK_UI 同走 OpenPanel("tasks", ...)，但携带
        // 副本上下文；task-panel.js onOpen 据 initData.view==="dungeon" 切副本 tab 加载该副本。
        // initDataExtrasJson = AS2 传来的 {view,taskId}（panel_request 的 initData 字段）。
        private void OpenTasksPanel(string source, string initDataExtrasJson)
        {
            JObject jo = new JObject();
            jo["source"] = source;
            if (!string.IsNullOrEmpty(initDataExtrasJson))
            {
                try
                {
                    JObject extras = JObject.Parse(initDataExtrasJson);
                    foreach (var prop in extras.Properties())
                    {
                        jo[prop.Name] = prop.Value;
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[Router] OpenTasksPanel extras parse failed: " + ex.Message);
                }
            }
            LogManager.Log("[Router] OpenTasksPanel view=" + (jo["view"] != null ? jo["view"].ToString() : "?")
                + " taskId=" + (jo["taskId"] != null ? jo["taskId"].ToString() : "?")
                + " boardId=" + (jo["boardId"] != null ? jo["boardId"].ToString() : "?"));
            OpenPanel("tasks", jo.ToString(Newtonsoft.Json.Formatting.None));
        }

        // 世界内雇佣（佣兵+战宠）：NPC「雇佣」→ AS2 openWebHire 发 panel_request panel="team"，
        // initData={view:"hire",kind,npcId,initialTab}。与刘海屏 TEAM 同走 OpenPanel("team", ...)，但携带
        // 雇佣上下文；team-panel.js onOpen 据 initData.view==="hire" 进单目标确认态（kind 决定 merc/pet tab）。
        private void OpenTeamPanel(string source, string initDataExtrasJson)
        {
            JObject jo = new JObject();
            jo["source"] = source;
            if (!string.IsNullOrEmpty(initDataExtrasJson))
            {
                try
                {
                    JObject extras = JObject.Parse(initDataExtrasJson);
                    foreach (var prop in extras.Properties())
                    {
                        jo[prop.Name] = prop.Value;
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[Router] OpenTeamPanel extras parse failed: " + ex.Message);
                }
            }
            LogManager.Log("[Router] OpenTeamPanel view=" + (jo["view"] != null ? jo["view"].ToString() : "?")
                + " kind=" + (jo["kind"] != null ? jo["kind"].ToString() : "?")
                + " npcId=" + (jo["npcId"] != null ? jo["npcId"].ToString() : "?"));
            OpenPanel("team", jo.ToString(Newtonsoft.Json.Formatting.None));
        }

        // arena 没有 frameLabel 概念；source 用于诊断（"stage_select_arena_redirect" 表示
        // 玩家在 stage-select 点了 DEATH MATCH 角斗场的难度按钮被路由过来）。mode=runtime
        // 与 stage-select 对齐。returnToPanel 非空时，关闭 arena 后由 PanelHostController
        // 自动 reopen returnTo（return stack 接管，调用方不需要管时序）。
        // initDataExtrasJson：caller (AS2 stage-select) 提供的 panel-specific 字段（如 difficulty），
        // merge 到 base initData 后下发给 web；arena-panel.js 通过 initData.difficulty 拿到值，
        // 在 enter 时回传给 AS2，让 ArenaPanelService 设 _root.当前关卡难度 让任务系统能匹配。
        private void OpenArenaPanel(string source, string initDataExtrasJson, string returnToPanel, string returnToInitDataJson)
        {
            JObject jo = new JObject();
            jo["mode"] = "runtime";
            jo["source"] = source;
            jo["debug"] = false;
            if (!string.IsNullOrEmpty(initDataExtrasJson))
            {
                try
                {
                    JObject extras = JObject.Parse(initDataExtrasJson);
                    foreach (var prop in extras.Properties())
                    {
                        jo[prop.Name] = prop.Value;
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[Router] OpenArenaPanel extras parse failed: " + ex.Message);
                }
            }
            OpenPanel("arena", jo.ToString(Formatting.None), returnToPanel, returnToInitDataJson);
        }

        /// <summary>
        /// 统一 panel 打开入口：Flag ON → _panelHost.OpenPanel（含 backdrop/EX_STYLE/HUD-suspend 序列）；
        /// Flag OFF → 旧 PostToWeb panel_cmd open + state callback（保留回滚路径）。
        /// </summary>
        private bool OpenPanel(string panelName, string initDataJson)
        {
            return OpenPanel(panelName, initDataJson, null, null);
        }

        /// <summary>
        /// returnTo 版本：关闭本 panel 后自动 reopen returnToPanel。仅 PanelHostController 路径支持；
        /// Flag OFF fallback 无 return stack 概念（旧路径已不再生产使用，returnTo 静默忽略）。
        /// </summary>
        private bool OpenPanel(string panelName, string initDataJson, string returnToPanel, string returnToInitDataJson)
        {
            if (!CanAdmitPanel("open:" + (panelName ?? "<null>")))
                return false;
            if (!string.Equals(
                    panelName,
                    "skills",
                    StringComparison.Ordinal))
            {
                CancelPendingSkillOpenIntent(
                    "competing_panel");
            }
            string currentPanel = _panelHost != null ? _panelHost.ActivePanelName : _activeFallbackPanelName;
            string currentInstance = _panelHost != null ? _panelHost.ActivePanelInstanceId
                : _activeFallbackPanelInstanceId;
            bool activeTuning = currentPanel == "workbench"
                && _equipmentTuningTask != null
                && !string.IsNullOrEmpty(currentInstance)
                && _equipmentTuningTask.PanelInstanceId
                    == currentInstance;
            // Any retained CharacterBuild binding still owns the exact AS2 pause authority, even
            // after finalize. A same-name storage/build rebind must first close and consume that
            // authority; otherwise its later name-only close can release the old lease behind a
            // replacement panel.
            if (_characterBuildTask != null
                && _characterBuildTask.HasBoundPanel)
            {
                if (activeTuning
                    && !_equipmentTuningTask.CanClose)
                {
                    LogManager.Log(
                        "[Router] panel open rejected: equipment tuning request/reconcile is pending behind character authority");
                    return false;
                }
                if (_characterBuildTask.RequiresDetachRecovery)
                {
                    LogManager.Log(
                        "[Router] panel open rejected: character build detach recovery "
                        + "status=" + _characterBuildTask.DetachRecoveryStatus
                        + " error="
                        + (_characterBuildTask.DetachRecoveryFailure ?? "none")
                        + "; caller must retry after recovery settles");
                    return false;
                }
                if (!_characterBuildTask.CanRebind)
                {
                    LogManager.Log(
                        "[Router] panel open rejected: character build finalize is unresolved; caller must retry");
                    return false;
                }
                return BeginCharacterBuildSwitchHandoff(
                    _characterBuildTask.PanelInstanceId,
                    currentPanel,
                    currentInstance,
                    panelName);
            }
            if (activeTuning && panelName != "workbench" && !_equipmentTuningTask.CanClose)
            {
                LogManager.Log("[Router] panel switch deferred: equipment tuning request/reconcile is pending");
                return false;
            }
            if (activeTuning && panelName == "workbench" && _panelHost == null
                && !_equipmentTuningTask.CanRebind)
            {
                LogManager.Log("[Router] fallback workbench rebind deferred: equipment tuning is pending");
                return false;
            }
            // 任意 web 面板打开 → 暂停游戏：玩家此时看不到 AS2 画面，游戏不该在背后继续跑
            // （NPC 离场 / 敌人攻击 / 计时推进）。幂等 lease（AS2 webPanelPause 只持一个），
            // 覆盖 panelHost + fallback 两条开面板路；关闭时 case "close" 的 webPanelUnpause 释放。
            TrySendGameCommand("webPanelPause");
            if (_panelHost != null)
            {
                return _panelHost.TryOpenPanel(
                    panelName, initDataJson, returnToPanel, returnToInitDataJson);
            }
            if (_postToWeb == null) return false;
            // Flag OFF fallback：行为与本 PR 之前等价；returnTo 在该路径下不生效
            if (activeTuning && panelName != "workbench"
                && !_equipmentTuningTask.HandlePanelClosed(currentInstance)) return false;
            if (_activeFallbackPanelName == "skills" && panelName != "skills" && _skillTask != null)
                _skillTask.HandleAuthoritativePanelClosed(_activeFallbackPanelInstanceId);
            if (panelName == "skills" && _skillTask != null
                && _activeFallbackPanelName == "skills" && !_skillTask.CanRebind)
            {
                // 保留旧 instance 供其 RequestMux 完成未知写对账；只记最后一次打开意图。
                _deferredFallbackSkillInitData = initDataJson;
                LogManager.Log("[Router] fallback skills rebind deferred");
                return false;
            }
            string instanceId = "fallback." + DateTime.UtcNow.Ticks.ToString("x") + "."
                + System.Threading.Interlocked.Increment(ref _fallbackPanelInstanceSequence).ToString("x");
            JObject init;
            if (panelName == "skills" && _skillTask != null)
                initDataJson = _skillTask.EnrichPanelInitData(initDataJson);
            try { init = string.IsNullOrEmpty(initDataJson) ? new JObject() : JObject.Parse(initDataJson); }
            catch { init = new JObject(); }
            init["panelInstanceId"] = instanceId;
            JObject msg = new JObject
            {
                ["type"] = "panel_cmd", ["cmd"] = "open", ["panel"] = panelName,
                ["panelInstanceId"] = instanceId, ["initData"] = init
            };
            PostToWeb(msg.ToString(Formatting.None));
            // Post 成功返回才切换 Host 盖章实例，避免旧 RequestMux 的在途 reconcile 被提前改绑。
            _activeFallbackPanelInstanceId = instanceId;
            _activeFallbackPanelName = panelName;
            if (panelName != "skills") _deferredFallbackSkillInitData = null;
            if (_setActivePanel != null) _setActivePanel(panelName);
            if (_onPanelStateChanged != null) _onPanelStateChanged(true);
            return true;
        }

        /// <summary>
        /// Switching away from a finalized character-build session is a two-request handoff.
        /// This request starts the Host-only acknowledged close and removes the old visual, but is
        /// deliberately rejected. A fresh request may open the target only after AS2 proves
        /// persistence, clean revisions and pause release and the coordinator consumes the binding.
        /// </summary>
        private bool BeginCharacterBuildSwitchHandoff(
            string boundInstance,
            string currentPanel,
            string currentInstance,
            string requestedPanel)
        {
            if (_characterBuildTask == null
                || !_characterBuildTask.BeginNormalCloseBarrier(
                    boundInstance))
            {
                LogManager.Log(
                    "[Router] panel switch rejected: character build close handoff lost exact binding; caller must retry");
                return false;
            }

            if (_panelHost != null)
            {
                _panelHost.ClearReturnStack();
                string retirePanel =
                    string.IsNullOrEmpty(currentPanel)
                        ? "workbench" : currentPanel;
                string retireInstance =
                    string.IsNullOrEmpty(currentInstance)
                        ? boundInstance : currentInstance;
                if (!_panelHost.TryRetirePanelVisualExact(
                    retirePanel,
                    retireInstance,
                    delegate(
                        PanelHostController.VisualRetireOutcome
                            outcome)
                    {
                        if (outcome
                                == PanelHostController
                                    .VisualRetireOutcome
                                    .RetiredExact
                            || outcome
                                == PanelHostController
                                    .VisualRetireOutcome
                                    .VisualAlreadyAbsent)
                        {
                            _characterBuildTask
                                .ContinueDetachRecoveryAfterVisualRetired(0);
                        }
                        else
                        {
                            LogManager.Log(
                                "[Router] character build recovery remains fenced: Host visual retire unavailable");
                        }
                    }))
                {
                    LogManager.Log(
                        "[Router] character build recovery remains fenced: Host visual retire was not queued");
                }
            }
            else
            {
                if (!string.IsNullOrEmpty(currentPanel)
                    && !string.IsNullOrEmpty(currentInstance))
                {
                    PostToWeb(new JObject
                    {
                        ["type"] = "panel_cmd",
                        ["cmd"] = "close",
                        ["panel"] = currentPanel,
                        ["panelInstanceId"] = currentInstance
                    }.ToString(Formatting.None));
                }
                ClearFallbackPanelInstance();
                if (_setActivePanel != null) _setActivePanel(null);
                if (_onPanelStateChanged != null)
                    _onPanelStateChanged(false);
                bool visualRetired = false;
                try
                {
                    visualRetired = _fallbackVisualRetire != null
                        && _fallbackVisualRetire(
                            "character_build_switch");
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[Router] fallback character visual retire failed: "
                        + ex.Message);
                }
                if (visualRetired)
                {
                    _characterBuildTask
                        .ContinueDetachRecoveryAfterVisualRetired(0);
                }
                else
                {
                    LogManager.Log(
                        "[Router] character build recovery remains fenced: fallback visual retire not confirmed");
                }
            }

            LogManager.Log(
                "[Router] panel switch rejected after starting acknowledged character build close; "
                + "requested=" + (requestedPanel ?? "<null>")
                + "; caller must retry after recovery settles");
            return false;
        }

        private void SendKey(Keys k) { if (_onSendKey != null) _onSendKey(k); }
        private void ToggleFullscreen() { if (_onToggleFullscreen != null) _onToggleFullscreen(); }
        private void ToggleLog() { if (_onToggleLog != null) _onToggleLog(); }
        private void ForceExit() { if (_onForceExit != null) _onForceExit(); }
        private void PostToWeb(string json) { if (_postToWeb != null) _postToWeb(json); }

        private void RouteSafeExit()
        {
            bool delivered = false;
            try
            {
                delivered = TrySendGameCommand("safeExit");
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[Router] SAFEEXIT send threw: " + ex.Message);
            }
            if (delivered) return;

            LogManager.Log(
                "[Router] SAFEEXIT command was not delivered; entering failed state");
            Action failed = OnSafeExitSendFailed;
            if (failed != null)
            {
                try { failed(); }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[Router] SAFEEXIT native failure callback threw: "
                        + ex.Message);
                }
            }
            try
            {
                PostToWeb(
                    "{\"type\":\"safe_exit_failed\"}");
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[Router] SAFEEXIT web failure notification threw: "
                    + ex.Message);
            }
        }

        private bool ConsumeSafeExitConfirmCapability()
        {
            Func<bool> consume =
                TryConsumeSafeExitConfirm;
            if (consume == null)
            {
                LogManager.Log(
                    "[Router] EXIT_CONFIRM rejected: no armed SafeExit capability");
                return false;
            }
            try
            {
                if (consume()) return true;
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[Router] EXIT_CONFIRM capability threw: "
                    + ex.Message);
                return false;
            }
            LogManager.Log(
                "[Router] EXIT_CONFIRM rejected: SafeExit session is not armed and done");
            return false;
        }

        private void RouteMaterialUi()
        {
            if (!CanAdmitPanel("materials"))
                return;
            bool characterRecovery =
                _characterBuildTask != null
                && _characterBuildTask.RequiresDetachRecovery;
            bool characterBound =
                _characterBuildTask != null
                && _characterBuildTask.HasBoundPanel;
            if (characterRecovery || characterBound)
            {
                LogManager.Log(
                    "[Router] MATERIALS rejected: character build authority is retained"
                    + (characterRecovery
                        ? " during detach recovery"
                        : ""));
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"请先完成当前装备面板操作\"}");
                return;
            }

            bool hostVisualActiveOrPending =
                _panelHost != null
                && !_panelHost.IsIdleForTrackedOpen;
            bool activeVisual =
                hostVisualActiveOrPending
                || !string.IsNullOrEmpty(
                    _activeFallbackPanelName)
                || !string.IsNullOrEmpty(
                    _activeFallbackPanelInstanceId);
            if (activeVisual)
            {
                string active =
                    hostVisualActiveOrPending
                        ? _panelHost.ActivePanelName
                        : _activeFallbackPanelName;
                LogManager.Log(
                    "[Router] MATERIALS rejected: active or pending Web panel visual="
                    + (active ?? "<unknown>"));
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"请先关闭当前面板\"}");
                return;
            }

            bool delivered = false;
            try
            {
                delivered =
                    TrySendGameCommand(
                        "openMaterialUI");
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[Router] MATERIALS openMaterialUI send threw: "
                    + ex.Message);
            }
            if (delivered) return;

            LogManager.Log(
                "[Router] MATERIALS openMaterialUI was not delivered");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"材料面板暂时不可用\"}");
        }

        private void RouteEquipmentUi()
        {
            if (!CanAdmitPanel("equipment"))
            {
                CancelNativeEquipmentBuildOpenWait();
                return;
            }
            if (!WebInventoryWorkbenchEnabled)
            {
                CancelNativeEquipmentBuildOpenWait();
                LogManager.Log(
                    "[Router] EQUIP_UI web workbench explicitly disabled -> Flash fallback");
                SendGameCommand(
                    "openEquipUI");
                return;
            }

            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : _activeFallbackPanelName;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : _activeFallbackPanelInstanceId;
            bool exactActiveBuild =
                string.Equals(
                    activePanel,
                    "workbench",
                    StringComparison.Ordinal)
                && !string.IsNullOrEmpty(
                    activeInstance)
                && _characterBuildTask != null
                && _characterBuildTask.IsBoundTo(
                    activeInstance);
            if (exactActiveBuild)
            {
                CancelNativeEquipmentBuildOpenWait();
                // Re-click is only a Web close request. CharacterBuild's existing
                // finalize/unknown barrier remains the sole authority that may later
                // acknowledge and retire this exact Host visual.
                PostToWeb(
                    "{\"type\":\"panel_esc\"}");
                return;
            }

            LogManager.Log(
                "event=character_build_open_requested source=nativehud_equipment");
            int generation;
            if (!TryBeginNativeEquipmentBuildOpenWait(
                    out generation))
            {
                LogManager.Log(
                    "event=character_build_open_suppressed source=nativehud_equipment reason=pending");
                return;
            }
            if (TrySendNativeEquipmentBuildPreflight())
                return;

            CancelNativeEquipmentBuildOpenWait(
                generation);
            LogManager.Log(
                "event=character_build_open_failed source=nativehud_equipment reason=preflight_send");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"装备面板暂时不可用，请稍后重试\"}");
        }

        private bool TrySendNativeEquipmentBuildPreflight()
        {
            const string payload =
                "{\"task\":\"cmd\",\"action\":\"openInventoryWorkbench\","
                + "\"profile\":\"battlebox\",\"view\":\"build\","
                + "\"source\":\"nativehud_equipment\"}\0";
            if (_gameCommandSenderOverride != null)
                return _gameCommandSenderOverride(
                    payload);
            if (_socketServer == null
                || !_socketServer.IsClientReady)
            {
                return false;
            }
            return _socketServer.TrySend(
                payload);
        }

        private bool CanAdmitPanel(string route)
        {
            Func<bool> gate =
                _panelAdmissionGate;
            if (gate == null) return true;
            try
            {
                if (gate()) return true;
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[Router] panel admission gate threw route="
                    + route + " ex=" + ex.Message);
                return false;
            }
            LogManager.Log(
                "[Router] panel admission rejected during shutdown route="
                + route);
            return false;
        }

        private bool TryBeginNativeEquipmentBuildOpenWait(
            out int generation)
        {
            generation = 0;
            lock (_nativeEquipmentBuildOpenLock)
            {
                if (_nativeEquipmentBuildOpenPending)
                    return false;
                generation =
                    ++_nativeEquipmentBuildOpenGeneration;
                _nativeEquipmentBuildOpenPending =
                    true;
                _nativeEquipmentBuildOpenBaselinePanel =
                    _panelHost != null
                        ? _panelHost.ActivePanelName
                        : _activeFallbackPanelName;
                _nativeEquipmentBuildOpenBaselineInstance =
                    _panelHost != null
                        ? _panelHost.ActivePanelInstanceId
                        : _activeFallbackPanelInstanceId;
                int timerGeneration =
                    generation;
                _nativeEquipmentBuildOpenTimer =
                    new System.Threading.Timer(
                        delegate
                        {
                            OnNativeEquipmentBuildOpenTimeout(
                                timerGeneration);
                        },
                        null,
                        Math.Max(
                            1,
                            NativeEquipmentBuildOpenTimeoutMs),
                        System.Threading.Timeout.Infinite);
                return true;
            }
        }

        private bool TryConsumeNativeEquipmentBuildOpenWait(
            out string rejectionReason)
        {
            System.Threading.Timer timer;
            lock (_nativeEquipmentBuildOpenLock)
            {
                if (!_nativeEquipmentBuildOpenPending)
                {
                    rejectionReason =
                        "missing_preflight";
                    return false;
                }
                string activePanel =
                    _panelHost != null
                        ? _panelHost.ActivePanelName
                        : _activeFallbackPanelName;
                string activeInstance =
                    _panelHost != null
                        ? _panelHost.ActivePanelInstanceId
                        : _activeFallbackPanelInstanceId;
                if (!string.Equals(
                        activePanel,
                        _nativeEquipmentBuildOpenBaselinePanel,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        activeInstance,
                        _nativeEquipmentBuildOpenBaselineInstance,
                        StringComparison.Ordinal))
                {
                    timer =
                        ClearNativeEquipmentBuildOpenWaitLocked();
                    rejectionReason =
                        "competing_panel";
                }
                else
                {
                    timer =
                        ClearNativeEquipmentBuildOpenWaitLocked();
                    rejectionReason =
                        null;
                }
            }
            if (timer != null)
                timer.Dispose();
            return rejectionReason == null;
        }

        private void OnNativeEquipmentBuildOpenTimeout(
            int generation)
        {
            System.Threading.Timer timer;
            string activePanel;
            lock (_nativeEquipmentBuildOpenLock)
            {
                if (!_nativeEquipmentBuildOpenPending
                    || generation
                        != _nativeEquipmentBuildOpenGeneration)
                {
                    return;
                }
                activePanel =
                    _panelHost != null
                        ? _panelHost.ActivePanelName
                        : _activeFallbackPanelName;
                timer =
                    ClearNativeEquipmentBuildOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            if (!string.IsNullOrEmpty(activePanel))
            {
                LogManager.Log(
                    "event=character_build_open_failed source=nativehud_equipment "
                    + "reason=panel_request_timeout active_panel="
                    + activePanel
                    + " toast=suppressed");
                return;
            }
            LogManager.Log(
                "event=character_build_open_failed source=nativehud_equipment reason=panel_request_timeout");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"装备服务未就绪，请稍后重试\"}");
        }

        private void CancelNativeEquipmentBuildOpenWait(
            int expectedGeneration = 0)
        {
            System.Threading.Timer timer;
            lock (_nativeEquipmentBuildOpenLock)
            {
                if (!_nativeEquipmentBuildOpenPending
                    || (expectedGeneration != 0
                        && expectedGeneration
                            != _nativeEquipmentBuildOpenGeneration))
                {
                    return;
                }
                timer =
                    ClearNativeEquipmentBuildOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
        }

        private System.Threading.Timer ClearNativeEquipmentBuildOpenWaitLocked()
        {
            _nativeEquipmentBuildOpenPending =
                false;
            _nativeEquipmentBuildOpenGeneration++;
            _nativeEquipmentBuildOpenBaselinePanel =
                null;
            _nativeEquipmentBuildOpenBaselineInstance =
                null;
            System.Threading.Timer timer =
                _nativeEquipmentBuildOpenTimer;
            _nativeEquipmentBuildOpenTimer =
                null;
            return timer;
        }

        private void SendGameCommand(string action)
        {
            string payload = "{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0";
            if (_gameCommandSenderOverride != null) { _gameCommandSenderOverride(payload); return; }
            if (_socketServer == null) return;
            _socketServer.Send(payload);
        }

        private void SendGameCommand(string action, string extraJsonFields)
        {
            if (_socketServer == null) return;
            _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"," + extraJsonFields + "}\0");
        }

        private bool TrySendGameCommand(string action)
        {
            // 与 WebOverlayForm.TrySendGameCommand 一致：先校验 IsClientReady，再走 TrySend 真实回传 false。
            // 不能依赖 Send() —— Send 在无连接时只是 return（不抛），会让 router 误判 panel 打开成功。
            string payload = "{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0";
            if (_gameCommandSenderOverride != null) return _gameCommandSenderOverride(payload);
            if (_socketServer == null || !_socketServer.IsClientReady) return false;
            return _socketServer.TrySend(payload);
        }

        private bool TrySendSkillPanelOpenCommand(
            string openRequestId)
        {
            if (!IsOpaqueToken(openRequestId))
                return false;
            string payload =
                "{\"task\":\"cmd\",\"action\":\"skillPanelOpen\","
                + "\"openRequestId\":\""
                + EscapeJsonString(openRequestId)
                + "\"}\0";
            if (_gameCommandSenderOverride != null)
                return _gameCommandSenderOverride(payload);
            if (_socketServer == null
                || !_socketServer.IsClientReady)
            {
                return false;
            }
            return _socketServer.TrySend(payload);
        }

        private int BeginSkillOpenWait(
            string origin,
            out string openRequestId)
        {
            System.Threading.Timer previous;
            int generation;
            lock (_skillOpenLock)
            {
                generation = ++_skillOpenGeneration;
                previous = _skillOpenTimer;
                openRequestId =
                    "skill.open."
                    + generation.ToString("x")
                    + "."
                    + Guid.NewGuid().ToString("N");
                _skillOpenPending = true;
                _skillOpenRequestId =
                    openRequestId;
                _skillOpenOrigin =
                    string.IsNullOrEmpty(origin)
                        ? "unknown"
                        : origin;
                _skillOpenBaselinePanel =
                    _panelHost != null
                        ? _panelHost.ActivePanelName
                        : _activeFallbackPanelName;
                _skillOpenBaselineInstance =
                    _panelHost != null
                        ? _panelHost.ActivePanelInstanceId
                        : _activeFallbackPanelInstanceId;
                _skillOpenTimer = new System.Threading.Timer(delegate { OnSkillOpenTimeout(generation); },
                    null, Math.Max(1, SkillOpenTimeoutMs), System.Threading.Timeout.Infinite);
            }
            if (previous != null) previous.Dispose();
            return generation;
        }

        private bool TryAdmitSkillPanelRequest(
            string source,
            string view,
            string openRequestId,
            out string rejectionReason,
            out string pendingOrigin)
        {
            System.Threading.Timer timer =
                null;
            bool admitted =
                false;
            lock (_skillOpenLock)
            {
                pendingOrigin =
                    _skillOpenPending
                        ? _skillOpenOrigin
                        : null;
                if (view == "trainer")
                {
                    if (_skillOpenPending)
                    {
                        rejectionReason =
                            "manage_preflight_pending";
                    }
                    else if (!string.IsNullOrEmpty(
                        openRequestId))
                    {
                        rejectionReason =
                            "unexpected_open_request_id";
                    }
                    else if (string.Equals(
                        _panelHost != null
                            ? _panelHost.ActivePanelName
                            : _activeFallbackPanelName,
                        "skills",
                        StringComparison.Ordinal))
                    {
                        // A trainer panel_request is only an external world-entry edge. Once
                        // Skills is active, trainer/manage transitions must use exact-instance
                        // panel-control rebind; a delayed NPC request may never replace the
                        // just-opened manage surface.
                        rejectionReason =
                            "skills_already_active";
                    }
                    else
                    {
                        rejectionReason =
                            null;
                        admitted =
                            true;
                    }
                }
                else if (!_skillOpenPending)
                {
                    rejectionReason =
                        "missing_preflight";
                }
                else if (!string.Equals(
                    source,
                    "nativehud",
                    StringComparison.Ordinal)
                    || !string.Equals(
                        view,
                        "manage",
                        StringComparison.Ordinal))
                {
                    rejectionReason =
                        "preflight_contract";
                }
                else if (!IsOpaqueToken(
                        openRequestId)
                    || !string.Equals(
                        openRequestId,
                        _skillOpenRequestId,
                        StringComparison.Ordinal))
                {
                    rejectionReason =
                        "preflight_nonce";
                }
                else
                {
                    string activePanel =
                        _panelHost != null
                            ? _panelHost.ActivePanelName
                            : _activeFallbackPanelName;
                    string activeInstance =
                        _panelHost != null
                            ? _panelHost.ActivePanelInstanceId
                            : _activeFallbackPanelInstanceId;
                    if (!string.Equals(
                            activePanel,
                            _skillOpenBaselinePanel,
                            StringComparison.Ordinal)
                        || !string.Equals(
                            activeInstance,
                            _skillOpenBaselineInstance,
                            StringComparison.Ordinal))
                    {
                        rejectionReason =
                            "competing_panel";
                        timer =
                            ClearSkillOpenWaitLocked();
                    }
                    else
                    {
                        rejectionReason =
                            null;
                        admitted =
                            true;
                        timer =
                            ClearSkillOpenWaitLocked();
                    }
                }
            }
            if (timer != null)
                timer.Dispose();
            return admitted;
        }

        private void OnSkillOpenTimeout(int generation)
        {
            System.Threading.Timer timer;
            bool showToast;
            string origin;
            lock (_skillOpenLock)
            {
                if (!_skillOpenPending
                    || generation != _skillOpenGeneration)
                {
                    return;
                }
                string active = _panelHost != null ? _panelHost.ActivePanelName : _activeFallbackPanelName;
                showToast = active != "skills";
                origin =
                    _skillOpenOrigin;
                timer =
                    ClearSkillOpenWaitLocked();
            }
            if (timer != null) timer.Dispose();
            if (!showToast) return;
            LogManager.Log("[Router] SKILLS panel_request timeout generation=" + generation);
            LogManager.Log(
                "event=skill_panel_open_fallback reason=panel_request_timeout target=legacy_inventory source="
                + (origin ?? "unknown"));
            PostToWeb("{\"type\":\"toast\",\"text\":\"技能服务未就绪，请从旧物品界面进入\"}");
        }

        private void CancelSkillOpenWait(int expectedGeneration = 0)
        {
            System.Threading.Timer timer;
            lock (_skillOpenLock)
            {
                if (!_skillOpenPending
                    || (expectedGeneration != 0
                        && expectedGeneration
                            != _skillOpenGeneration))
                {
                    return;
                }
                timer =
                    ClearSkillOpenWaitLocked();
            }
            if (timer != null) timer.Dispose();
        }

        internal bool CancelPendingSkillOpenIntent(
            string reason)
        {
            System.Threading.Timer timer;
            string origin;
            lock (_skillOpenLock)
            {
                if (!_skillOpenPending)
                    return false;
                origin =
                    _skillOpenOrigin;
                timer =
                    ClearSkillOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=skill_panel_open_cancelled reason="
                + (reason ?? "unknown")
                + " source="
                + (origin ?? "unknown"));
            return true;
        }

        private System.Threading.Timer ClearSkillOpenWaitLocked()
        {
            _skillOpenPending =
                false;
            _skillOpenGeneration++;
            _skillOpenRequestId =
                null;
            _skillOpenOrigin =
                null;
            _skillOpenBaselinePanel =
                null;
            _skillOpenBaselineInstance =
                null;
            System.Threading.Timer timer =
                _skillOpenTimer;
            _skillOpenTimer =
                null;
            return timer;
        }

        private static string EscapeJsonString(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }

        private static string ExtractString(string json, string keyToken)
        {
            if (string.IsNullOrEmpty(json) || string.IsNullOrEmpty(keyToken)) return null;
            int idx = json.IndexOf(keyToken, StringComparison.Ordinal);
            if (idx < 0) return null;
            int start = idx + keyToken.Length;
            int end = json.IndexOf('"', start);
            if (end <= start) return null;
            return json.Substring(start, end - start);
        }
    }
}
