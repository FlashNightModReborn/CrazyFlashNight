using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.AgentHarness
{
    /// <summary>
    /// Host-side coordinator for `--agent-harness` sessions.
    /// Owns AS2 command correlation, slot entry, save-and-exit barriers, panel/Web actions,
    /// event/log queries, and headless/lock-screen presentation scene-fence tracking.
    /// </summary>
    internal sealed class AgentHarnessController : IDisposable
    {
        private const uint DesktopReadObjects = 0x0001;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesiredAccess);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool CloseDesktop(IntPtr hDesktop);

        private readonly AgentHarnessPolicy _policy;
        private readonly GuardianForm _form;
        private readonly GameLaunchFlow _launchFlow;
        private readonly AgentControlTask _agentControl;
        private readonly XmlSocketServer _socketServer;
        private readonly AgentHarnessEventHub _events;
        private readonly AgentHarnessWebBridge _webBridge;
        private readonly AgentHarnessPanelOpener _panelOpener;
        private readonly PanelHostController _panelHost;
        private readonly ModifierOverlay _modifierOverlay;
        private readonly FrameTask _frameTask;
        private readonly Func<Process> _flashProcessProvider;
        private readonly Func<uint, Action> _captureDialogueKey;
        private readonly Func<bool> _clickVictoryReturn;

        private readonly long _sessionStartUtcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        private long _reqCounter;
        private long _fenceLockCounter;
        private int _lastFenceScene = -1;
        private long _lastFenceArmedUtcMs;
        private int _lastHeadlessSatisfiedScene = -1;
        private string _boundAs2Slot;
        private volatile bool _disposed;

        internal AgentHarnessController(
            AgentHarnessPolicy policy,
            GuardianForm form,
            GameLaunchFlow launchFlow,
            AgentControlTask agentControl,
            XmlSocketServer socketServer,
            AgentHarnessEventHub events,
            AgentHarnessWebBridge webBridge,
            AgentHarnessPanelOpener panelOpener,
            PanelHostController panelHost,
            ModifierOverlay modifierOverlay,
            FrameTask frameTask,
            Func<Process> flashProcessProvider, Func<uint, Action> captureDialogueKey = null,
            Func<bool> clickVictoryReturn = null)
        {
            _policy = policy ?? throw new ArgumentNullException(nameof(policy));
            _form = form ?? throw new ArgumentNullException(nameof(form));
            _launchFlow = launchFlow ?? throw new ArgumentNullException(nameof(launchFlow));
            _agentControl = agentControl ?? throw new ArgumentNullException(nameof(agentControl));
            _socketServer = socketServer ?? throw new ArgumentNullException(nameof(socketServer));
            _events = events ?? throw new ArgumentNullException(nameof(events));
            _webBridge = webBridge ?? throw new ArgumentNullException(nameof(webBridge));
            _panelOpener = panelOpener ?? throw new ArgumentNullException(nameof(panelOpener));
            _panelHost = panelHost;
            _modifierOverlay = modifierOverlay;
            _frameTask = frameTask;
            _flashProcessProvider = flashProcessProvider;
            _captureDialogueKey = captureDialogueKey;
            _clickVictoryReturn = clickVictoryReturn;
        }

        internal static bool IsInputDesktopLocked()
        {
            try
            {
                IntPtr desktop = OpenInputDesktop(0, false, DesktopReadObjects);
                if (desktop == IntPtr.Zero) return true;
                CloseDesktop(desktop);
                return false;
            }
            catch
            {
                return false;
            }
        }

        internal bool IsDesktopLockedOrMinimized()
        {
            if (_form == null || _form.IsDisposed) return false;
            bool formLocked = _form.IsSessionLocked;
            bool minimized = false;
            try
            {
                if (!_form.InvokeRequired)
                    minimized = _form.WindowState == FormWindowState.Minimized || !_form.Visible;
            }
            catch { }
            return formLocked || minimized || IsInputDesktopLocked();
        }

        internal void NotifyTransitionFrameRequired(int scene)
        {
            if (scene <= 0) return;
            Volatile.Write(ref _lastFenceScene, scene);
            Volatile.Write(ref _lastFenceArmedUtcMs, DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
        }

        internal bool ShouldSatisfySceneFenceHeadless(int scene)
        {
            if (_disposed || !_policy.AllowHeadlessFallback || scene <= 0)
                return false;
            if (!IsDesktopLockedOrMinimized())
                return false;

            long armedAt = (Volatile.Read(ref _lastFenceScene) == scene)
                ? Volatile.Read(ref _lastFenceArmedUtcMs)
                : _sessionStartUtcMs;
            long elapsed = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - armedAt;
            if (elapsed < _policy.HeadlessSceneFallbackDelayMs)
                return false;

            int prev = Interlocked.Exchange(ref _lastHeadlessSatisfiedScene, scene);
            if (prev != scene)
            {
                LogManager.Log("event=harness_headless_scene_fence_satisfied scene=" + scene
                    + " locked=" + (_form.IsSessionLocked || IsInputDesktopLocked())
                    + " elapsedMs=" + elapsed);
            }
            return true;
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

        internal async Task<JObject> SendAs2CommandAsync(JObject payload, int timeoutMs = 8000, CancellationToken ct = default)
        {
            if (_disposed)
                return new JObject { ["ok"] = false, ["error"] = "controller_disposed" };
            if (_socketServer == null || !_socketServer.IsClientReady)
                return new JObject { ["ok"] = false, ["error"] = "xmlsocket_not_ready" };

            if (timeoutMs < 250) timeoutMs = 250;
            if (timeoutMs > 60000) timeoutMs = 60000;

            string reqId = "ah_" + Interlocked.Increment(ref _reqCounter);
            JObject envelope = payload != null ? (JObject)payload.DeepClone() : new JObject();
            envelope["task"] = "cmd";
            envelope["action"] = "agentHarnessCmd";
            envelope["requestId"] = reqId;

            TaskCompletionSource<JObject> waiter = _events.RegisterAs2Waiter(reqId);
            string wire = envelope.ToString(Newtonsoft.Json.Formatting.None) + "\0";
            if (!_socketServer.TrySend(wire))
            {
                _events.RemoveAs2Waiter(reqId);
                return new JObject { ["ok"] = false, ["error"] = "xmlsocket_send_failed", ["requestId"] = reqId };
            }

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(timeoutMs);
            using var reg = cts.Token.Register(() => waiter.TrySetCanceled());
            try
            {
                return await waiter.Task.ConfigureAwait(false);
            }
            catch (TaskCanceledException)
            {
                _events.RemoveAs2Waiter(reqId);
                return new JObject { ["ok"] = false, ["error"] = "as2_command_timeout", ["requestId"] = reqId };
            }
        }

        private async Task<JObject> BindAs2Async(string slot, int timeoutMs, CancellationToken ct)
        {
            if (!AgentHarnessPolicy.IsValidAgentSlot(slot))
                return new JObject { ["ok"] = false, ["error"] = "invalid_agent_slot" };

            DateTime deadline = DateTime.UtcNow.AddMilliseconds(Math.Max(500, timeoutMs));
            JObject last = null;
            while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
            {
                if (_socketServer != null && _socketServer.IsClientReady)
                {
                    last = await SendAs2CommandAsync(new JObject
                    {
                        ["sub"] = "bind",
                        ["slot"] = slot,
                        ["sessionEpoch"] = _policy.SessionEpoch
                    }, 2000, ct).ConfigureAwait(false);

                    if (last != null && last.Value<bool?>("ok") == true)
                    {
                        _boundAs2Slot = slot;
                        return last;
                    }
                }
                await Task.Delay(150, ct).ConfigureAwait(false);
            }
            return last ?? new JObject { ["ok"] = false, ["error"] = "as2_bind_timeout" };
        }

        private JObject ReadLaunchStatusSnapshot()
        {
            try
            {
                string raw = _agentControl.Handle(new JObject { ["action"] = "status" });
                return JObject.Parse(raw);
            }
            catch (Exception ex)
            {
                return new JObject
                {
                    ["ok"] = false,
                    ["error"] = "status_read_failed",
                    ["message"] = ex.Message
                };
            }
        }

        internal async Task<JObject> BuildStatusPayloadAsync(CancellationToken ct = default)
        {
            bool formVisible = false;
            string windowState = "Unknown";
            try
            {
                if (_form != null && !_form.IsDisposed && _form.IsHandleCreated)
                {
                    var ui = await RunOnUiAsync(
                        () => (_form.Visible, _form.WindowState.ToString()), ct).ConfigureAwait(false);
                    formVisible = ui.Visible;
                    windowState = ui.Item2;
                }
            }
            catch { }
            return BuildStatusPayload(formVisible, windowState);
        }

        internal JObject BuildStatusPayload(bool? uiVisible = null, string uiWindowState = null)
        {
            JObject launch = ReadLaunchStatusSnapshot();
            Process flashProc = null;
            try { flashProc = _flashProcessProvider?.Invoke(); } catch { }
            int flashPid = 0;
            try { if (flashProc != null && !flashProc.HasExited) flashPid = flashProc.Id; } catch { }

            bool desktopLocked = _form.IsSessionLocked || IsInputDesktopLocked();
            bool formVisible = uiVisible ?? false;
            string windowState = uiWindowState ?? "Unknown";
            if (!uiVisible.HasValue)
            {
                try
                {
                    if (!_form.IsDisposed && !_form.InvokeRequired)
                    {
                        formVisible = _form.Visible;
                        windowState = _form.WindowState.ToString();
                    }
                }
                catch { }
            }
            return new JObject
            {
                ["ok"] = true,
                ["pid"] = Process.GetCurrentProcess().Id,
                ["flashPid"] = flashPid,
                ["sessionEpoch"] = _policy.SessionEpoch,
                ["boundAs2Slot"] = _boundAs2Slot ?? "",
                ["desktopLocked"] = desktopLocked,
                ["desktop"] = new JObject
                {
                    ["desktopLocked"] = desktopLocked,
                    ["sessionLocked"] = _form.IsSessionLocked,
                    ["inputDesktopLocked"] = IsInputDesktopLocked(),
                    ["formVisible"] = formVisible,
                    ["windowState"] = windowState,
                    ["allowHeadlessFallback"] = _policy.AllowHeadlessFallback
                },
                ["runtimeIdentity"] = _policy.RuntimeIdentity?.DeepClone(),
                ["launch"] = launch,
                ["activePanel"] = _panelHost?.ActivePanelName ?? "",
                ["activePanelInstanceId"] = _panelHost?.ActivePanelInstanceId ?? "",
                ["modifierOpen"] = _modifierOverlay?.IsOpen == true,
                ["eventSeq"] = _events.CurrentEventSeq,
                ["logSeq"] = _events.CurrentLogSeq
            };
        }

        internal async Task<(JObject Result, Action OnResponseWritten)> HandleRpcAsync(
            string method,
            JObject @params,
            CancellationToken ct)
        {
            if (_disposed)
                return (new JObject { ["ok"] = false, ["error"] = "controller_disposed" }, null);

            switch (method)
            {
                case "session.ping":
                case "session.status":
                    return (await BuildStatusPayloadAsync(ct).ConfigureAwait(false), null);

                case "session.enter_slot":
                    return (await HandleEnterSlotAsync(@params, ct).ConfigureAwait(false), null);

                case "session.save_and_exit":
                    return await HandleSaveAndExitAsync(@params, ct).ConfigureAwait(false);

                case "session.shutdown":
                    return await HandleShutdownAsync(@params, ct).ConfigureAwait(false);

                case "panel.open":
                    return (await _panelOpener.OpenAsync(@params, ct).ConfigureAwait(false), null);

                case "panel.close":
                    return (await _panelOpener.CloseAsync(@params, ct).ConfigureAwait(false), null);

                case "web.snapshot":
                    return (await _webBridge.SnapshotAsync(@params, ct).ConfigureAwait(false), null);

                case "web.act":
                    return (await _webBridge.ActAsync(@params, ct).ConfigureAwait(false), null);

                case "web.screenshot":
                    return (await _webBridge.ScreenshotAsync(@params, ct).ConfigureAwait(false), null);

                case "world.snapshot":
                    return (await HandleWorldSnapshotAsync(@params, ct).ConfigureAwait(false), null);

                case "world.act":
                    return (await HandleWorldActAsync(@params, ct).ConfigureAwait(false), null);

                case "combat.hit_ledger":
                    {
                        if (_frameTask == null)
                            return (new JObject { ["ok"] = false, ["error"] = "frame_task_unavailable" }, null);
                        int offset = @params?.Value<int?>("offset") ?? 0;
                        int limit = @params?.Value<int?>("limit") ?? 100;
                        JObject page = _frameTask.BuildHitNumberLedgerPage(offset, limit);
                        page["ok"] = true;
                        return (page, null);
                    }

                case "events.wait_for":
                    return (await HandleEventsWaitForAsync(@params, ct).ConfigureAwait(false), null);

                case "logs.query":
                    {
                        long sinceSeq = @params?.Value<long?>("sinceSeq") ?? 0;
                        int limit = @params?.Value<int?>("limit") ?? 100;
                        string contains = @params?.Value<string>("contains");
                        string regex = @params?.Value<string>("regex");
                        JObject res = _events.QueryLogs(sinceSeq, limit, contains, regex);
                        res["ok"] = true;
                        return (res, null);
                    }

                default:
                    return (new JObject
                    {
                        ["ok"] = false,
                        ["error"] = "unknown_rpc_method",
                        ["method"] = method ?? ""
                    }, null);
            }
        }

        private async Task<JObject> EnsureBoundForCurrentSlotAsync(CancellationToken ct)
        {
            if (!string.IsNullOrEmpty(_boundAs2Slot))
                return null;

            JObject status = ReadLaunchStatusSnapshot();
            string runtimeSlot = status["saveRuntime"]?["savePath"]?.Value<string>()
                ?? status["save"]?["slot"]?.Value<string>();
            if (!AgentHarnessPolicy.IsValidAgentSlot(runtimeSlot))
                return new JObject { ["ok"] = false, ["error"] = "no_valid_agent_slot_loaded", ["slot"] = runtimeSlot ?? "" };

            JObject bindResp = await BindAs2Async(runtimeSlot, 4000, ct).ConfigureAwait(false);
            if (bindResp.Value<bool?>("ok") != true)
                return bindResp;
            return null;
        }

        private async Task<JObject> HandleWorldSnapshotAsync(JObject @params, CancellationToken ct)
        {
            JObject bindErr = await EnsureBoundForCurrentSlotAsync(ct).ConfigureAwait(false);
            if (bindErr != null) return bindErr;

            var cmd = new JObject { ["sub"] = "world_snapshot" };
            if (@params?["includePlayer"] != null)
                cmd["includePlayer"] = @params["includePlayer"].DeepClone();
            int timeoutMs = @params?.Value<int?>("timeoutMs") ?? 6000;
            return await SendAs2CommandAsync(cmd, timeoutMs, ct).ConfigureAwait(false);
        }

        private async Task<JObject> HandleWorldActAsync(JObject @params, CancellationToken ct)
        {
            JObject bindErr = await EnsureBoundForCurrentSlotAsync(ct).ConfigureAwait(false);
            if (bindErr != null) return bindErr;

            // These inputs belong to the native window. Flash owns movement and combat keys.
            string action = (string)@params?["act"];
            if (action == "advance_dialogue" || action == "return_after_victory")
            {
                return await RunOnUiAsync(() =>
                {
                    string currentSlot = (string)ReadLaunchStatusSnapshot()["saveRuntime"]?["savePath"];
                    if (!AgentHarnessPolicy.IsValidAgentSlot(currentSlot) || currentSlot != _boundAs2Slot)
                        return new JObject { ["ok"] = false, ["error"] = "no_valid_agent_slot_loaded" };
                    if (action == "return_after_victory")
                    {
                        if (_clickVictoryReturn?.Invoke() != true)
                            return new JObject { ["ok"] = false, ["error"] = "victory_return_not_available" };
                        return new JObject { ["ok"] = true, ["act"] = action };
                    }
                    Action pressEnter = _captureDialogueKey?.Invoke(13);
                    if (pressEnter == null) return new JObject { ["ok"] = false, ["error"] = "dialogue_not_ready" };
                    pressEnter();
                    return new JObject { ["ok"] = true, ["act"] = "advance_dialogue" };
                }, ct).ConfigureAwait(false);
            }

            JObject cmd = @params != null ? (JObject)@params.DeepClone() : new JObject();
            cmd["sub"] = "world_act";
            int timeoutMs = @params?.Value<int?>("timeoutMs") ?? 8000;
            return await SendAs2CommandAsync(cmd, timeoutMs, ct).ConfigureAwait(false);
        }

        internal async Task<JObject> EnterSlotInternalAsync(string slot, bool fresh, int timeoutMs, CancellationToken ct)
        {
            if (!AgentHarnessPolicy.IsValidAgentSlot(slot))
                return new JObject { ["ok"] = false, ["error"] = "invalid_agent_slot", ["slot"] = slot ?? "" };
            if (timeoutMs < 5000) timeoutMs = 5000;

            await RunOnUiAsync(() => { _form.EnsureNonActivatingBackgroundVisible(); return true; }, ct).ConfigureAwait(false);

            JObject existing = ReadLaunchStatusSnapshot();
            if (existing.Value<bool?>("readyForRuntimeAutomation") == true
                && string.Equals(existing["save"]?["slot"]?.Value<string>(), slot, StringComparison.Ordinal))
            {
                JObject bindExisting = await BindAs2Async(slot, 4000, ct).ConfigureAwait(false);
                JObject snapExisting = bindExisting.Value<bool?>("ok") == true
                    ? await SendAs2CommandAsync(new JObject { ["sub"] = "world_snapshot" }, 3000, ct).ConfigureAwait(false)
                    : null;
                return new JObject
                {
                    ["ok"] = true,
                    ["alreadyEntered"] = true,
                    ["slot"] = slot,
                    ["status"] = ReadLaunchStatusSnapshot(),
                    ["bind"] = bindExisting,
                    ["world"] = snapExisting?["data"]
                };
            }

            // Wait briefly for LaunchFlow to finish initial Idle transition if launched immediately.
            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
            {
                string ls = existing.Value<string>("launchState");
                if (ls == "Idle" || ls == "Error") break;
                await Task.Delay(100, ct).ConfigureAwait(false);
                existing = ReadLaunchStatusSnapshot();
            }

            long sinceSeq = _events.CurrentEventSeq;
            JObject startResult = await RunOnUiAsync(() =>
            {
                string raw = _agentControl.Handle(new JObject
                {
                    ["action"] = "start",
                    ["slot"] = slot,
                    ["fresh"] = fresh,
                    ["rememberSlot"] = false,
                    ["deferReveal"] = false,
                    ["requireFlashReveal"] = true
                });
                return JObject.Parse(raw);
            }, ct).ConfigureAwait(false);

            if (startResult.Value<bool?>("success") != true)
                return startResult;

            JObject status = ReadLaunchStatusSnapshot();
            while (DateTime.UtcNow < deadline && !ct.IsCancellationRequested)
            {
                if (status.Value<bool?>("readyForRuntimeAutomation") == true)
                    break;

                string ls = status.Value<string>("launchState");
                if (string.Equals(ls, "Error", StringComparison.Ordinal))
                {
                    return new JObject
                    {
                        ["ok"] = false,
                        ["error"] = "launch_flow_error",
                        ["slot"] = slot,
                        ["status"] = status
                    };
                }

                int slice = Math.Max(50, Math.Min(250, (int)(deadline - DateTime.UtcNow).TotalMilliseconds));
                await _events.WaitForAsync(sinceSeq, null, slice, ct).ConfigureAwait(false);
                sinceSeq = _events.CurrentEventSeq;
                status = ReadLaunchStatusSnapshot();
            }

            if (status.Value<bool?>("readyForRuntimeAutomation") != true)
            {
                return new JObject
                {
                    ["ok"] = false,
                    ["error"] = "enter_slot_timeout",
                    ["slot"] = slot,
                    ["status"] = status
                };
            }

            int remainMs = Math.Max(3000, (int)(deadline - DateTime.UtcNow).TotalMilliseconds);
            JObject bindRes = await BindAs2Async(slot, remainMs, ct).ConfigureAwait(false);
            if (bindRes.Value<bool?>("ok") != true)
            {
                return new JObject
                {
                    ["ok"] = false,
                    ["error"] = "as2_bind_failed",
                    ["slot"] = slot,
                    ["bind"] = bindRes,
                    ["status"] = ReadLaunchStatusSnapshot()
                };
            }

            // Wait briefly for gameworld to instantiate after the "读盘" frame jump.
            JObject worldResp = null;
            DateTime worldDeadline = DateTime.UtcNow.AddMilliseconds(Math.Min(8000, Math.Max(2000, (int)(deadline - DateTime.UtcNow).TotalMilliseconds)));
            while (DateTime.UtcNow < worldDeadline && !ct.IsCancellationRequested)
            {
                worldResp = await SendAs2CommandAsync(new JObject { ["sub"] = "world_snapshot" }, 3000, ct).ConfigureAwait(false);
                if (worldResp.Value<bool?>("ok") == true
                    && worldResp["data"]?["worldPresent"]?.Value<bool?>() == true
                    && worldResp["data"]?["hero"]?["present"]?.Value<bool?>() == true)
                {
                    break;
                }
                await Task.Delay(120, ct).ConfigureAwait(false);
            }

            _events.RecordEvent("harness_slot_entered", "slot=" + slot, new JObject { ["slot"] = slot });
            return new JObject
            {
                ["ok"] = true,
                ["slot"] = slot,
                ["status"] = ReadLaunchStatusSnapshot(),
                ["bind"] = bindRes,
                ["world"] = worldResp?["data"]
            };
        }

        private Task<JObject> HandleEnterSlotAsync(JObject @params, CancellationToken ct)
        {
            string slot = @params?.Value<string>("slot") ?? _policy.AutoStartSlot;
            bool fresh = @params?.Value<bool?>("fresh") ?? false;
            int timeoutMs = @params?.Value<int?>("timeoutMs") ?? 45000;
            return EnterSlotInternalAsync(slot, fresh, timeoutMs, ct);
        }

        private async Task<(JObject Result, Action OnResponseWritten)> HandleSaveAndExitAsync(
            JObject @params,
            CancellationToken ct)
        {
            bool flushSave = @params?.Value<bool?>("flushSave") ?? true;
            bool closePanelsFirst = @params?.Value<bool?>("closePanelsFirst") ?? true;
            int timeoutMs = @params?.Value<int?>("timeoutMs") ?? 12000;

            if (closePanelsFirst && (_modifierOverlay?.IsOpen == true || !string.IsNullOrEmpty(_panelHost?.ActivePanelName)))
            {
                JObject closeRes = await _panelOpener.CloseAsync(new JObject { ["timeoutMs"] = 4000 }, ct).ConfigureAwait(false);
                if (closeRes.Value<bool?>("success") != true && @params?.Value<bool?>("strictClose") == true)
                    return (closeRes, null);
            }

            JObject status = ReadLaunchStatusSnapshot();
            string currentSlot = status["saveRuntime"]?["savePath"]?.Value<string>()
                ?? status["save"]?["slot"]?.Value<string>();
            bool runtimeLoaded = status["saveRuntime"]?["loaded"]?.Value<bool?>() == true;

            JObject flushResp = null;
            bool shadowConfirmed = false;
            if (flushSave && runtimeLoaded && _socketServer != null && _socketServer.IsClientReady)
            {
                if (!AgentHarnessPolicy.IsValidAgentSlot(currentSlot))
                {
                    return (new JObject
                    {
                        ["ok"] = false,
                        ["error"] = "unsafe_slot_refused_save_and_exit",
                        ["slot"] = currentSlot ?? ""
                    }, null);
                }

                long saveEvSeq = _events.CurrentEventSeq;
                JObject bindErr = await EnsureBoundForCurrentSlotAsync(ct).ConfigureAwait(false);
                if (bindErr == null)
                {
                    flushResp = await SendAs2CommandAsync(new JObject { ["sub"] = "flush_save" }, Math.Min(timeoutMs, 7000), ct)
                        .ConfigureAwait(false);
                    if (flushResp.Value<bool?>("ok") == true)
                    {
                        var shadowWait = await _events.WaitForAsync(
                            saveEvSeq,
                            ev => ev.Kind == "archive_shadow_saved"
                                && string.Equals(ev.Data?["slot"]?.Value<string>(), currentSlot, StringComparison.Ordinal),
                            4000,
                            ct).ConfigureAwait(false);
                        shadowConfirmed = shadowWait.Matched;
                    }
                }
                else
                {
                    flushResp = bindErr;
                }
            }

            string actionId = "ah_exit_" + Interlocked.Increment(ref _fenceLockCounter);
            bool prepared = await RunOnUiAsync(() => _form.TryPrepareAgentRuntimeExit(actionId), ct).ConfigureAwait(false);
            if (!prepared)
            {
                return (new JObject
                {
                    ["ok"] = false,
                    ["error"] = "shutdown_fence_blocked",
                    ["slot"] = currentSlot ?? "",
                    ["flush"] = flushResp
                }, null);
            }

            var result = new JObject
            {
                ["ok"] = true,
                ["actionId"] = actionId,
                ["slot"] = currentSlot ?? "",
                ["flush"] = flushResp,
                ["shadowConfirmed"] = shadowConfirmed
            };
            return (result, () => _form.CompleteAgentRuntimeExit(actionId));
        }

        private async Task<(JObject Result, Action OnResponseWritten)> HandleShutdownAsync(
            JObject @params,
            CancellationToken ct)
        {
            string actionId = "ah_quit_" + Interlocked.Increment(ref _fenceLockCounter);
            bool prepared = await RunOnUiAsync(() => _form.TryPrepareAgentRuntimeExit(actionId), ct).ConfigureAwait(false);
            var result = new JObject
            {
                ["ok"] = true,
                ["actionId"] = actionId,
                ["prepared"] = prepared
            };
            Action onWritten = prepared
                ? (Action)(() => _form.CompleteAgentRuntimeExit(actionId))
                : (Action)(() =>
                {
                    try
                    {
                        if (!_form.IsDisposed && _form.IsHandleCreated)
                            _form.BeginInvoke(new Action(() => _form.ForceExit()));
                    }
                    catch { }
                });
            return (result, onWritten);
        }

        private async Task<JObject> HandleEventsWaitForAsync(JObject @params, CancellationToken ct)
        {
            long sinceSeq = @params?.Value<long?>("sinceSeq") ?? 0;
            int timeoutMs = @params?.Value<int?>("timeoutMs") ?? 10000;
            if (timeoutMs < 0) timeoutMs = 0;
            if (timeoutMs > 120000) timeoutMs = 120000;

            JObject filter = @params?["filter"] as JObject ?? @params;
            Predicate<AgentHarnessEvent> pred = AgentHarnessEventHub.BuildFilter(filter);
            var res = await _events.WaitForAsync(sinceSeq, pred, timeoutMs, ct).ConfigureAwait(false);
            return new JObject
            {
                ["ok"] = true,
                ["matched"] = res.Matched,
                ["lastSeq"] = res.LastSeq,
                ["event"] = res.Event != null ? (JToken)res.Event.ToJson() : JValue.CreateNull()
            };
        }

        public void Dispose()
        {
            _disposed = true;
        }
    }
}
