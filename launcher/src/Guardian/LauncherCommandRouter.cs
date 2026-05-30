using System;
using System.Windows.Forms;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

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
        }

        /// <summary>二阶段注入：Program.cs 先 new Router，再 new PanelHostController(...)，最后 SetPanelHost 回注。</summary>
        public void SetPanelHost(PanelHostController host) { _panelHost = host; }

        /// <summary>
        /// SAFEEXIT click → 触发 SafeExitPanelWidget.Arm()。Program.cs 在 widget 实例化后注入。
        /// 必须在 SendGameCommand("safeExit") 之前调，否则 widget 收到 sv:1 时还没 armed，会忽略。
        /// </summary>
        public Action OnSafeExitArm { get; set; }

        /// <summary>
        /// 来自 web `#quest-row > #map-hud-toggle` 的 click → 切 C# MapHudWidget 折叠态。
        /// Program.cs 在 widget 实例化后注入 `() => mapHudWidget.ToggleCollapsed()`。
        /// </summary>
        public Action OnMapHudToggle { get; set; }

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
                case "WAREHOUSE": SendGameCommand("warehouse"); break;
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
                case "PETS":
                    LogManager.Log("[Router] PETS clicked");
                    if (TrySendGameCommand("petPanelOpen"))
                        OpenPanel("pets", null);
                    else
                    {
                        LogManager.Log("[Router] PETS petPanelOpen failed");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"战宠面板暂时不可用\"}");
                    }
                    break;
                case "MERCS":
                    LogManager.Log("[Router] MERCS clicked");
                    if (TrySendGameCommand("mercPanelOpen"))
                        OpenPanel("mercs", null);
                    else
                    {
                        LogManager.Log("[Router] MERCS mercPanelOpen failed");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"佣兵面板暂时不可用\"}");
                    }
                    break;
                case "TABLET": SendGameCommand("toggleTablet"); break;
                case "GAMESETTINGS": SendGameCommand("openSettings"); break;
                case "JUKEBOX": SendGameCommand("openJukebox"); break;
                case "JUKEBOX_EXPAND":
                    // Phase 5：launcher/web/modules/panels/jukebox-panel.js 已注册 Panels.register('jukebox')，
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
                case "NEW_TASK_UI":
                    LogManager.Log("[Router] NEW_TASK_UI clicked");
                    if (TrySendGameCommand("taskPanelOpen"))
                        OpenPanel("tasks", null);
                    else
                    {
                        LogManager.Log("[Router] NEW_TASK_UI taskPanelOpen failed");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"任务面板暂时不可用\"}");
                    }
                    break;
                case "TASK_UI": SendGameCommand("openTaskUI"); break;
                case "EQUIP_UI": SendGameCommand("openEquipUI"); break;
                case "INTELLIGENCE":
                    OpenPanel("intelligence", "{\"mode\":\"prod\",\"source\":\"runtime\",\"debug\":false}");
                    break;
                case "BAKE": SendGameCommand("bakeIcons"); break;
                case "BAKE10": SendGameCommand("bakeIcons", "\"maxCount\":10"); break;
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
                case "ARENA_TEST":
                    OpenPanel("arena", "{\"mode\":\"dev\",\"source\":\"runtime\",\"debug\":true}");
                    break;
                case "EXIT_CONFIRM": ForceExit(); break;
                default:
                    LogManager.Log("[Router] unknown key=" + key);
                    break;
            }
        }

        /// <summary>
        /// AS2 → C# panel 打开请求（替代旧 WebOverlayForm.RequestOpenPanel 的 dispatch 段）。
        /// map 透传 pageId；stage-select 透传 frameLabel/returnFrameLabel（mode 固化为 runtime）；其他 panel 保持 unsupported。
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
        ///     redirect 时附带的 {"difficulty":"冒险"}），由 caller 显式构造，C# 端 merge 到 base initData
        ///     后透传给 web。base 字段（mode/source/debug）由本类负责，AS2 端不需要懂。
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
            if (string.Equals(panelName, "arena", StringComparison.OrdinalIgnoreCase))
            {
                OpenArenaPanel(safeSource, initDataExtrasJson, returnToPanel, returnToInitDataJson);
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
        private void OpenPanel(string panelName, string initDataJson)
        {
            OpenPanel(panelName, initDataJson, null, null);
        }

        /// <summary>
        /// returnTo 版本：关闭本 panel 后自动 reopen returnToPanel。仅 PanelHostController 路径支持；
        /// Flag OFF fallback 无 return stack 概念（旧路径已不再生产使用，returnTo 静默忽略）。
        /// </summary>
        private void OpenPanel(string panelName, string initDataJson, string returnToPanel, string returnToInitDataJson)
        {
            if (_panelHost != null)
            {
                _panelHost.OpenPanel(panelName, initDataJson, returnToPanel, returnToInitDataJson);
                return;
            }
            // Flag OFF fallback：行为与本 PR 之前等价；returnTo 在该路径下不生效
            string msg;
            if (string.IsNullOrEmpty(initDataJson))
                msg = "{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"" + panelName + "\"}";
            else
                msg = "{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"" + panelName + "\",\"initData\":" + initDataJson + "}";
            PostToWeb(msg);
            if (_setActivePanel != null) _setActivePanel(panelName);
            if (_onPanelStateChanged != null) _onPanelStateChanged(true);
        }

        private void SendKey(Keys k) { if (_onSendKey != null) _onSendKey(k); }
        private void ToggleFullscreen() { if (_onToggleFullscreen != null) _onToggleFullscreen(); }
        private void ToggleLog() { if (_onToggleLog != null) _onToggleLog(); }
        private void ForceExit() { if (_onForceExit != null) _onForceExit(); }
        private void PostToWeb(string json) { if (_postToWeb != null) _postToWeb(json); }

        private void SendGameCommand(string action)
        {
            if (_socketServer == null) return;
            _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0");
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
            if (_socketServer == null || !_socketServer.IsClientReady) return false;
            return _socketServer.TrySend("{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0");
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
