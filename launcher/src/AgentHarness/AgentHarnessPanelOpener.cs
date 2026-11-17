using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.AgentHarness
{
    /// <summary>
    /// Unified opener/closer for all registered game Web panels and AS2-backed world panels
    /// under an active `--agent-harness` session.
    /// </summary>
    internal sealed class AgentHarnessPanelOpener
    {
        private readonly GuardianForm _form;
        private readonly LauncherCommandRouter _commandRouter;
        private readonly PanelHostController _panelHost;
        private readonly ModifierOverlay _modifierOverlay;
        private readonly EquipmentTuningTask _equipmentTuningTask;
        private readonly CharacterBuildTask _characterBuildTask;
        private readonly AgentHarnessEventHub _events;
        private readonly Func<JObject, int, Task<JObject>> _sendAs2Cmd;
        private readonly Func<DateTime, CancellationToken, Task<bool>> _waitForWebHydrated;

        internal AgentHarnessPanelOpener(
            GuardianForm form,
            LauncherCommandRouter commandRouter,
            PanelHostController panelHost,
            ModifierOverlay modifierOverlay,
            EquipmentTuningTask equipmentTuningTask,
            CharacterBuildTask characterBuildTask,
            AgentHarnessEventHub events,
            Func<JObject, int, Task<JObject>> sendAs2Cmd,
            Func<DateTime, CancellationToken, Task<bool>> waitForWebHydrated = null)
        {
            _form = form;
            _commandRouter = commandRouter;
            _panelHost = panelHost;
            _modifierOverlay = modifierOverlay;
            _equipmentTuningTask = equipmentTuningTask;
            _characterBuildTask = characterBuildTask;
            _events = events;
            _sendAs2Cmd = sendAs2Cmd;
            _waitForWebHydrated = waitForWebHydrated;
        }

        private Task<T> RunOnUiAsync<T>(Func<T> func, CancellationToken ct)
        {
            var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
            if (_form == null || _form.IsDisposed || !_form.IsHandleCreated)
            {
                tcs.TrySetException(new InvalidOperationException("host_form_unavailable"));
                return tcs.Task;
            }
            void Run()
            {
                try
                {
                    ct.ThrowIfCancellationRequested();
                    tcs.TrySetResult(func());
                }
                catch (Exception ex)
                {
                    tcs.TrySetException(ex);
                }
            }
            if (!_form.InvokeRequired) Run();
            else
            {
                try { _form.BeginInvoke(new Action(Run)); }
                catch (Exception ex) { tcs.TrySetException(ex); }
            }
            return tcs.Task;
        }

        internal async Task<JObject> OpenAsync(JObject options, CancellationToken ct)
        {
            string panel = options?.Value<string>("panel") ?? "";
            if (string.IsNullOrWhiteSpace(panel))
                return new JObject { ["success"] = false, ["error"] = "missing_panel_name" };

            int timeoutMs = options?.Value<int?>("timeoutMs") ?? 8000;
            if (timeoutMs < 500) timeoutMs = 500;
            string expectedPanelName = NormalizeExpectedPanelName(panel);

            if (!string.IsNullOrEmpty(_panelHost?.ActivePanelName)
                && string.Equals(_panelHost.ActivePanelName, expectedPanelName, StringComparison.Ordinal)
                && options?.Value<bool?>("reopenIfOpen") != true)
            {
                return new JObject
                {
                    ["success"] = true,
                    ["alreadyOpen"] = true,
                    ["panel"] = _panelHost.ActivePanelName,
                    ["panelInstanceId"] = _panelHost.ActivePanelInstanceId ?? ""
                };
            }

            if (!string.IsNullOrEmpty(_panelHost?.ActivePanelName) && options?.Value<bool?>("closeCurrentFirst") == true)
            {
                JObject closed = await CloseAsync(new JObject { ["timeoutMs"] = 4000 }, ct);
                if (closed.Value<bool?>("success") != true)
                    return closed;
            }

            await RunOnUiAsync(() => { _form.EnsureNonActivatingBackgroundVisible(); return true; }, ct);

            DateTime openDeadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            long sinceSeq = _events.CurrentEventSeq;
            bool dispatched = false;
            string dispatchError = null;

            switch (panel)
            {
                case "help":
                case "map":
                case "tasks":
                case "team":
                case "jukebox":
                case "materials":
                case "intelligence":
                case "meridians":
                case "settings_camera_preview":
                    dispatched = await RunOnUiAsync(() => _commandRouter.TryOpenAgentPanel(panel), ct);
                    break;
                case "kshop":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("SHOP"); return true; }, ct);
                    break;
                case "skills":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("SKILLS"); return true; }, ct);
                    break;
                case "tablet":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("TABLET"); return true; }, ct);
                    break;
                case "warehouse":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("WAREHOUSE"); return true; }, ct);
                    break;
                case "asset-workbench":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("ASSET_WORKBENCH"); return true; }, ct);
                    break;
                case "map-workbench":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("MAP_WORKBENCH"); return true; }, ct);
                    break;
                case "lockbox":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("LOCKBOX_TEST"); return true; }, ct);
                    break;
                case "pinalign":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("PINALIGN_TEST"); return true; }, ct);
                    break;
                case "gobang":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("GOBANG_TEST"); return true; }, ct);
                    break;
                case "blackmarket":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("BLACKMARKET_TEST"); return true; }, ct);
                    break;
                case "warlord-test":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("WARLORD_TEST"); return true; }, ct);
                    break;
                case "stage-select-test":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("STAGE_SELECT_TEST"); return true; }, ct);
                    break;
                case "dressup":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("DRESSUP_TEST"); return true; }, ct);
                    break;
                case "arena-test":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("ARENA_TEST"); return true; }, ct);
                    break;
                case "cutscene-test":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("CUTSCENE_TEST"); return true; }, ct);
                    break;
                case "lut-lab":
                    dispatched = await RunOnUiAsync(() => { _commandRouter.Dispatch("LUT_LAB_TEST"); return true; }, ct);
                    break;
                case "settings":
                case "workbench":
                case "arena":
                case "gym":
                case "bookshelf":
                case "npcshop":
                case "crafting":
                case "stage-select":
                case "subway":
                case "egg-stage-select":
                case "hairdresser":
                case "surgery":
                case "garage":
                case "sleep":
                case "modifier":
                    {
                        var as2Args = new JObject
                        {
                            ["sub"] = "world_act",
                            ["act"] = "open_panel",
                            ["panel"] = panel
                        };
                        if (options != null)
                        {
                            foreach (string k in new[] { "view", "profile", "shopId", "category", "frameLabel", "returnFrameLabel", "vehicleId" })
                            {
                                if (options[k] != null) as2Args[k] = options[k].DeepClone();
                            }
                        }
                        JObject as2Resp = await _sendAs2Cmd(as2Args, timeoutMs);
                        dispatched = as2Resp.Value<bool?>("ok") == true;
                        dispatchError = as2Resp.Value<string>("error");
                        break;
                    }
                default:
                    return new JObject { ["success"] = false, ["error"] = "unsupported_panel", ["panel"] = panel };
            }

            if (!dispatched)
            {
                return new JObject
                {
                    ["success"] = false,
                    ["error"] = string.IsNullOrEmpty(dispatchError) ? "panel_open_dispatch_failed" : dispatchError,
                    ["panel"] = panel
                };
            }

            if (panel == "modifier")
            {
                var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
                while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
                {
                    if (_modifierOverlay != null && _modifierOverlay.IsOpen)
                        return new JObject { ["success"] = true, ["panel"] = "modifier", ["panelInstanceId"] = "modifier" };
                    await Task.Delay(50, ct);
                }
                return new JObject { ["success"] = false, ["error"] = "modifier_open_timeout", ["panel"] = "modifier" };
            }

            if (string.Equals(_panelHost?.ActivePanelName, expectedPanelName, StringComparison.Ordinal))
            {
                await Task.Delay(120, ct);
                return new JObject
                {
                    ["success"] = true,
                    ["panel"] = _panelHost.ActivePanelName,
                    ["panelInstanceId"] = _panelHost.ActivePanelInstanceId ?? ""
                };
            }

            bool canRetryWarmup = panel == "help" || panel == "intelligence";
            for (;;)
            {
                int remainMs = Math.Max(200, (int)(openDeadline - DateTime.UtcNow).TotalMilliseconds);
                var waitRes = await _events.WaitForAsync(
                    sinceSeq,
                    ev => (ev.Kind == "panel_changed" && string.Equals(ev.Data?["panel"]?.Value<string>(), expectedPanelName, StringComparison.Ordinal))
                        || (ev.Kind == "panel_open_rejected" && string.Equals(ev.Data?["panel"]?.Value<string>(), expectedPanelName, StringComparison.Ordinal)),
                    remainMs,
                    ct);

                if (!waitRes.Matched)
                {
                    return new JObject
                    {
                        ["success"] = string.Equals(_panelHost?.ActivePanelName, expectedPanelName, StringComparison.Ordinal),
                        ["error"] = string.Equals(_panelHost?.ActivePanelName, expectedPanelName, StringComparison.Ordinal) ? "" : "panel_open_timeout",
                        ["panel"] = _panelHost?.ActivePanelName ?? expectedPanelName,
                        ["panelInstanceId"] = _panelHost?.ActivePanelInstanceId ?? ""
                    };
                }

                if (waitRes.Event.Kind == "panel_open_rejected")
                {
                    string rejectReason = waitRes.Event.Data?["reason"]?.Value<string>() ?? "unknown";
                    if (canRetryWarmup && rejectReason == "open_failed" && DateTime.UtcNow.AddMilliseconds(350) < openDeadline)
                    {
                        await Task.Delay(250, ct);
                        sinceSeq = _events.CurrentEventSeq;
                        bool retried = await RunOnUiAsync(() => _commandRouter.TryOpenAgentPanel(panel), ct);
                        if (retried)
                            continue;
                    }
                    return new JObject
                    {
                        ["success"] = false,
                        ["error"] = "panel_open_rejected",
                        ["reason"] = rejectReason,
                        ["panel"] = expectedPanelName
                    };
                }
                break;
            }

            bool hydrated = true;
            if (_waitForWebHydrated != null)
            {
                DateTime hydrateDeadline = DateTime.UtcNow.AddMilliseconds(4500);
                if (openDeadline < hydrateDeadline) hydrateDeadline = openDeadline;
                hydrated = await _waitForWebHydrated(hydrateDeadline, ct);
            }
            else
            {
                await Task.Delay(150, ct);
            }
            return new JObject
            {
                ["success"] = true,
                ["hydrated"] = hydrated,
                ["panel"] = _panelHost?.ActivePanelName ?? expectedPanelName,
                ["panelInstanceId"] = _panelHost?.ActivePanelInstanceId ?? ""
            };
        }

        internal async Task<JObject> CloseAsync(JObject options, CancellationToken ct)
        {
            int timeoutMs = options?.Value<int?>("timeoutMs") ?? 5000;
            bool force = options?.Value<bool?>("force") ?? false;

            if (_modifierOverlay != null && _modifierOverlay.IsOpen)
            {
                await RunOnUiAsync(() => { _modifierOverlay.CloseFromHost(); return true; }, ct);
                return new JObject { ["success"] = true, ["closed"] = "modifier" };
            }

            string priorPanel = _panelHost?.ActivePanelName;
            string priorInstance = _panelHost?.ActivePanelInstanceId;
            if (string.IsNullOrEmpty(priorPanel))
                return new JObject { ["success"] = true, ["alreadyClosed"] = true };

            await RunOnUiAsync(() => { _form.EnsureNonActivatingBackgroundVisible(); return true; }, ct);

            long sinceSeq = _events.CurrentEventSeq;
            await RunOnUiAsync(() =>
            {
                if (!force && _panelHost.PostEscapeForHarness())
                    return true;
                _panelHost.ClosePanel();
                return true;
            }, ct);

            var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
            {
                bool panelCleared = string.IsNullOrEmpty(_panelHost?.ActivePanelName);
                bool tuningCleared = _equipmentTuningTask == null || !_equipmentTuningTask.HasBoundPanel;
                bool buildCleared = _characterBuildTask == null || !_characterBuildTask.HasBoundPanel;
                if (panelCleared && tuningCleared && buildCleared)
                {
                    return new JObject
                    {
                        ["success"] = true,
                        ["closedPanel"] = priorPanel,
                        ["closedInstanceId"] = priorInstance ?? ""
                    };
                }
                int remain = Math.Max(50, Math.Min(250, (int)(deadline - DateTime.UtcNow).TotalMilliseconds));
                await _events.WaitForAsync(
                    sinceSeq,
                    ev => ev.Kind == "panel_changed" || ev.Kind == "panel_closed",
                    remain,
                    ct);
                sinceSeq = _events.CurrentEventSeq;
            }

            return new JObject
            {
                ["success"] = string.IsNullOrEmpty(_panelHost?.ActivePanelName),
                ["error"] = string.IsNullOrEmpty(_panelHost?.ActivePanelName) ? "" : "panel_close_timeout",
                ["activePanel"] = _panelHost?.ActivePanelName ?? ""
            };
        }

        private static string NormalizeExpectedPanelName(string panel)
        {
            switch (panel)
            {
                case "settings_camera_preview": return "settings";
                case "materials": return "crafting";
                case "warehouse": return "workbench";
                case "warlord-test":
                case "stage-select-test":
                    return "stage-select";
                case "arena-test":
                    return "arena";
                default:
                    return panel;
            }
        }
    }
}
