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
        private Func<string, bool> _gameCommandSenderOverride;
        private readonly object _skillOpenLock = new object();
        private System.Threading.Timer _skillOpenTimer;
        private int _skillOpenGeneration;
        internal int SkillOpenTimeoutMs { get; set; } = 1800;

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
        internal void SetGameCommandSenderForTests(Func<string, bool> sender) { _gameCommandSenderOverride = sender; }
        internal string ActiveFallbackPanelInstanceId { get { return _activeFallbackPanelInstanceId; } }
        internal string ActiveFallbackPanelName { get { return _activeFallbackPanelName; } }
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
                    SendGameCommand("safeExit");
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
                // D9：刘海装备键永远打开旧装备主界面；Web 调制仅从 battlebox 收纳箱反馈入口进入。
                case "EQUIP_UI": SendGameCommand("openEquipUI"); break;
                case "INTELLIGENCE":
                    OpenPanel("intelligence", "{\"mode\":\"prod\",\"source\":\"runtime\",\"debug\":false}");
                    break;
                case "SKILLS":
                    LogManager.Log("[Router] SKILLS clicked");
                    LogManager.Log("event=skill_panel_open_requested source=notch");
                    int skillOpenGeneration = BeginSkillOpenWait();
                    if (!TrySendGameCommand("skillPanelOpen"))
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
                case "EXIT_CONFIRM": ForceExit(); break;
                default:
                    LogManager.Log("[Router] unknown key=" + key);
                    break;
            }
        }

        /// <summary>
        /// AS2 → C# panel 打开请求（替代旧 WebOverlayForm.RequestOpenPanel 的 dispatch 段）。
        /// map 透传 pageId；stage-select 透传 frameLabel/returnFrameLabel；workbench 只接收 profile/view 枚举；npcshop 只接收 shopId；其他 panel 保持各自显式分支或 unsupported。
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
                OpenInventoryWorkbench(safeSource, initDataExtrasJson);
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
            if (string.Equals(panelName, "skills", StringComparison.OrdinalIgnoreCase))
            {
                OpenSkillsPanel(initDataExtrasJson);
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

        private bool OpenInventoryWorkbench(string source, string initDataExtrasJson)
        {
            string profile = "battlebox";
            string view = "storage";
            if (!string.IsNullOrEmpty(initDataExtrasJson))
            {
                try
                {
                    JObject extras = JObject.Parse(initDataExtrasJson);
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
                && !string.Equals(view, "tuning", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected view=" + view);
                return false;
            }
            if (view == "tuning" && !string.Equals(profile, "battlebox", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected tuning profile=" + profile);
                return false;
            }
            var initData = new JObject
            {
                ["mode"] = "runtime",
                ["profile"] = profile,
                ["view"] = view,
                ["source"] = source,
                ["debug"] = false
            };
            return OpenPanel("workbench", initData.ToString(Formatting.None));
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

        private void OpenSkillsPanel(string initDataExtrasJson)
        {
            JObject initData;
            if (!TryBuildSkillsInitData(initDataExtrasJson, out initData))
            {
                LogManager.Log("[Router] OpenSkillsPanel rejected extras");
                LogManager.Log("event=skill_panel_open_failed reason=invalid_panel_request");
                return;
            }
            CancelSkillOpenWait();
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

        internal static bool TryBuildSkillsInitData(string initDataExtrasJson, out JObject initData)
        {
            initData = null;
            if (string.IsNullOrEmpty(initDataExtrasJson)) return false;
            JObject extras;
            try { extras = JObject.Parse(initDataExtrasJson); }
            catch { return false; }
            string view = extras.Value<string>("view");
            if (view != "manage" && view != "trainer") return false;
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
            string currentPanel = _panelHost != null ? _panelHost.ActivePanelName : _activeFallbackPanelName;
            string currentInstance = _panelHost != null ? _panelHost.ActivePanelInstanceId
                : _activeFallbackPanelInstanceId;
            bool activeTuning = currentPanel == "workbench" && _equipmentTuningTask != null
                && !string.IsNullOrEmpty(currentInstance)
                && _equipmentTuningTask.PanelInstanceId == currentInstance;
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

        private void SendKey(Keys k) { if (_onSendKey != null) _onSendKey(k); }
        private void ToggleFullscreen() { if (_onToggleFullscreen != null) _onToggleFullscreen(); }
        private void ToggleLog() { if (_onToggleLog != null) _onToggleLog(); }
        private void ForceExit() { if (_onForceExit != null) _onForceExit(); }
        private void PostToWeb(string json) { if (_postToWeb != null) _postToWeb(json); }

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

        private int BeginSkillOpenWait()
        {
            System.Threading.Timer previous;
            int generation;
            lock (_skillOpenLock)
            {
                generation = ++_skillOpenGeneration;
                previous = _skillOpenTimer;
                _skillOpenTimer = new System.Threading.Timer(delegate { OnSkillOpenTimeout(generation); },
                    null, Math.Max(1, SkillOpenTimeoutMs), System.Threading.Timeout.Infinite);
            }
            if (previous != null) previous.Dispose();
            return generation;
        }

        private void OnSkillOpenTimeout(int generation)
        {
            System.Threading.Timer timer;
            bool showToast;
            lock (_skillOpenLock)
            {
                if (generation != _skillOpenGeneration) return;
                string active = _panelHost != null ? _panelHost.ActivePanelName : _activeFallbackPanelName;
                showToast = active != "skills";
                _skillOpenGeneration++;
                timer = _skillOpenTimer;
                _skillOpenTimer = null;
            }
            if (timer != null) timer.Dispose();
            if (!showToast) return;
            LogManager.Log("[Router] SKILLS panel_request timeout generation=" + generation);
            LogManager.Log("event=skill_panel_open_fallback reason=panel_request_timeout target=legacy_inventory");
            PostToWeb("{\"type\":\"toast\",\"text\":\"技能服务未就绪，请从旧物品界面进入\"}");
        }

        private void CancelSkillOpenWait(int expectedGeneration = 0)
        {
            System.Threading.Timer timer;
            lock (_skillOpenLock)
            {
                if (expectedGeneration != 0 && expectedGeneration != _skillOpenGeneration) return;
                _skillOpenGeneration++;
                timer = _skillOpenTimer;
                _skillOpenTimer = null;
            }
            if (timer != null) timer.Dispose();
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
