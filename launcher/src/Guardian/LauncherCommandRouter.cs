using System;
using System.Windows.Forms;

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
                case "SAFEEXIT": SendGameCommand("safeExit"); break;
                case "PETS": SendGameCommand("togglePets"); break;
                case "MERCS": SendGameCommand("toggleMercs"); break;
                case "TABLET": SendGameCommand("toggleTablet"); break;
                case "GAMESETTINGS": SendGameCommand("openSettings"); break;
                case "JUKEBOX": SendGameCommand("openJukebox"); break;
                case "TASK_MAP": OpenMapPanel("task_map", null); break;
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
                case "TASK_UI": SendGameCommand("openTaskUI"); break;
                case "EQUIP_UI": SendGameCommand("openEquipUI"); break;
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
                case "EXIT_CONFIRM": ForceExit(); break;
                default:
                    LogManager.Log("[Router] unknown key=" + key);
                    break;
            }
        }

        /// <summary>
        /// AS2 → C# panel 打开请求（替代旧 WebOverlayForm.RequestOpenPanel 的 dispatch 段）。
        /// 仅 source/pageId 透传给 OpenMapPanel；其他 panel name 由 OpenPanel 通用路径。
        /// </summary>
        public void RequestOpenPanel(string panelName, string source, string pageId)
        {
            if (string.IsNullOrEmpty(panelName)) return;
            string safeSource = string.IsNullOrEmpty(source) ? "as2_request" : source;
            if (string.Equals(panelName, "map", StringComparison.OrdinalIgnoreCase))
            {
                OpenMapPanel(safeSource, pageId);
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

        /// <summary>
        /// 统一 panel 打开入口：Flag ON → _panelHost.OpenPanel（含 backdrop/EX_STYLE/HUD-suspend 序列）；
        /// Flag OFF → 旧 PostToWeb panel_cmd open + state callback（保留回滚路径）。
        /// </summary>
        private void OpenPanel(string panelName, string initDataJson)
        {
            if (_panelHost != null)
            {
                _panelHost.OpenPanel(panelName, initDataJson);
                return;
            }
            // Flag OFF fallback：行为与本 PR 之前等价
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
            if (_socketServer == null) return false;
            try
            {
                _socketServer.Send("{\"task\":\"cmd\",\"action\":\"" + action + "\"}\0");
                return true;
            }
            catch { return false; }
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
