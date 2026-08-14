using System;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Local automation control plane for unattended runtime workflows.
    /// Keep this task thin: it exposes launcher lifecycle decisions, while
    /// long waits, UI observation, batch polling, analysis, and recovery live in tooling.
    /// </summary>
    public sealed class AgentControlTask
    {
        internal delegate void StartGameHandler(string slot, bool fresh, bool deferJsReveal, bool requireFlashReveal);

        private static readonly Regex UnsafeSlotChars = new Regex(@"[\\/:\*\?""<>\|\r\n]", RegexOptions.Compiled);
        private static readonly Regex AgentAutomationSlot = new Regex(
            @"^cf7_agent_[A-Za-z0-9_-]+$",
            RegexOptions.Compiled);

        private readonly Func<bool> _isSocketReady;
        private readonly Func<JObject> _getArenaStatus;
        private readonly Action<string> _rememberSlot;
        private readonly object _gate = new object();

        private Func<string> _getLaunchState;
        private StartGameHandler _startGame;
        private Action _revealOk;
        private Action _cancelLaunch;
        private Action _shutdown;
        private Func<bool> _isRevealPerformed;
        private Func<JObject> _getLaunchSaveStatus;
        private Func<bool> _openEquipmentTuning;
        private Func<bool> _openCharacterBuild;
        private Func<bool> _openArena;
        private Func<JObject> _getActivePanelStatus;
        private JObject _runtimeSaveStatus;
        private bool _gameEnteredObserved;
        private string _gameEnteredAttemptId;

        public AgentControlTask(
            Func<bool> isSocketReady,
            Func<JObject> getArenaStatus,
            Action<string> rememberSlot)
        {
            _isSocketReady = isSocketReady ?? delegate { return false; };
            _getArenaStatus = getArenaStatus ?? delegate { return null; };
            _rememberSlot = rememberSlot;
            _getLaunchState = delegate { return "Unavailable"; };
            _isRevealPerformed = delegate { return false; };
            _getLaunchSaveStatus = delegate { return null; };
        }

        internal AgentControlTask(
            Func<string> getLaunchState,
            Func<bool> isSocketReady,
            Func<bool> isRevealPerformed,
            StartGameHandler startGame,
            Action revealOk,
            Action cancelLaunch,
            Func<JObject> getArenaStatus,
            Action shutdown,
            Action<string> rememberSlot,
            Func<JObject> getLaunchSaveStatus = null)
            : this(isSocketReady, getArenaStatus, rememberSlot)
        {
            _getLaunchState = getLaunchState ?? delegate { return "Unavailable"; };
            _isRevealPerformed = isRevealPerformed ?? delegate { return false; };
            _startGame = startGame;
            _revealOk = revealOk;
            _cancelLaunch = cancelLaunch;
            _shutdown = shutdown;
            _getLaunchSaveStatus = getLaunchSaveStatus ?? delegate { return null; };
        }

        public void SetLaunchFlow(GameLaunchFlow launchFlow)
        {
            lock (_gate)
            {
                if (launchFlow == null)
                {
                    _getLaunchState = delegate { return "Unavailable"; };
                    _isRevealPerformed = delegate { return false; };
                    _getLaunchSaveStatus = delegate { return null; };
                    _startGame = null;
                    _revealOk = null;
                    _cancelLaunch = null;
                    return;
                }

                _getLaunchState = delegate { return launchFlow.CurrentState; };
                _isRevealPerformed = delegate { return launchFlow.RevealPerformed; };
                _getLaunchSaveStatus = delegate { return launchFlow.BuildAgentSaveStatus(); };
                _startGame = delegate(string slot, bool fresh, bool deferJsReveal, bool requireFlashReveal)
                {
                    if (fresh) launchFlow.StartFreshGame(slot, deferJsReveal, requireFlashReveal);
                    else launchFlow.StartGame(slot, deferJsReveal, requireFlashReveal);
                };
                _revealOk = delegate { launchFlow.OnJsRevealOk(); };
                _cancelLaunch = delegate
                {
                    if (launchFlow.CurrentState != "Idle")
                        launchFlow.Reset(null, "agent_cancel");
                };
            }
        }

        public void SetShutdownAction(Action shutdown)
        {
            lock (_gate) { _shutdown = shutdown; }
        }

        /// <summary>
        /// Injects the narrow C# -&gt; AS2 opener used by unattended equipment-tuning tests.
        /// The delegate must only send the fixed openInventoryWorkbench command
        /// (profile=battlebox, view=tuning, source=agent_control); this task deliberately
        /// does not accept a panel name or arbitrary initData from HTTP.
        /// </summary>
        public void SetEquipmentTuningOpenAction(Func<bool> openEquipmentTuning)
        {
            lock (_gate) { _openEquipmentTuning = openEquipmentTuning; }
        }

        /// <summary>
        /// Injects the fixed agent-only character-build opener. The delegate owns the exact
        /// profile=battlebox/view=build/source=agent_control payload; HTTP cannot choose any of it.
        /// </summary>
        public void SetCharacterBuildOpenAction(Func<bool> openCharacterBuild)
        {
            lock (_gate) { _openCharacterBuild = openCharacterBuild; }
        }

        /// <summary>
        /// Injects the fixed agent-only AS2 arena opener. The delegate may only send
        /// openArenaForAgent; AS2 remains responsible for emitting the production
        /// stage_select_arena_redirect panel_request and HTTP cannot choose a panel,
        /// difficulty, authority card, or initData.
        /// </summary>
        public void SetArenaOpenAction(Func<bool> openArena)
        {
            lock (_gate) { _openArena = openArena; }
        }

        /// <summary>Read-only panel observation for outer runners; never opens or mutates a panel.</summary>
        public void SetActivePanelStatusProvider(Func<JObject> getActivePanelStatus)
        {
            lock (_gate) { _getActivePanelStatus = getActivePanelStatus; }
        }

        public string Handle(JObject msg)
        {
            string action = msg.Value<string>("action") ?? "status";
            try
            {
                switch (action)
                {
                    case "status":
                        return BuildStatus(true, null).ToString(Newtonsoft.Json.Formatting.None);
                    case "start":
                        return Start(msg).ToString(Newtonsoft.Json.Formatting.None);
                    case "revealOk":
                        return RevealOk().ToString(Newtonsoft.Json.Formatting.None);
                    case "cancel":
                        return Cancel().ToString(Newtonsoft.Json.Formatting.None);
                    case "shutdown":
                        return Shutdown().ToString(Newtonsoft.Json.Formatting.None);
                    case "openEquipmentTuning":
                        return OpenEquipmentTuning(msg).ToString(Newtonsoft.Json.Formatting.None);
                    case "openCharacterBuild":
                        return OpenCharacterBuild(msg).ToString(Newtonsoft.Json.Formatting.None);
                    case "openArena":
                        return OpenArena(msg).ToString(Newtonsoft.Json.Formatting.None);
                    default:
                        return BuildError("unsupported_action", "unsupported action: " + action).ToString(Newtonsoft.Json.Formatting.None);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[AgentControlTask] control exception: " + ex);
                return BuildError("exception", ex.Message).ToString(Newtonsoft.Json.Formatting.None);
            }
        }

        public string HandleRuntimeStatus(JObject msg)
        {
            JObject payload = msg.Value<JObject>("payload") ?? msg;
            JObject copy = payload != null ? (JObject)payload.DeepClone() : new JObject();
            lock (_gate)
            {
                _runtimeSaveStatus = copy;
            }

            JObject result = new JObject();
            result["success"] = true;
            result["ok"] = true;
            result["task"] = "agent_runtime_status";
            return result.ToString(Newtonsoft.Json.Formatting.None);
        }

        /// <summary>
        /// Observes the already parsed AS2 UI-state packet shared by the Host tee.
        /// The last s field in one packet wins, matching the ordered snapshot update
        /// semantics used by the HUD consumers.
        /// </summary>
        public void ObserveUiData(UiDataPacket packet)
        {
            if (packet == null || packet.IsLegacy || packet.Pairs == null) return;

            bool? observed = null;
            string observedAttemptId = null;
            string[] pairs = packet.Pairs;
            for (int i = 0; i < pairs.Length; i++)
            {
                string pair = pairs[i];
                if (pair == null) continue;
                if (pair.StartsWith("s:", StringComparison.Ordinal))
                {
                    string value = pair.Substring(2);
                    if (string.Equals(value, "1", StringComparison.Ordinal)) observed = true;
                    else if (string.Equals(value, "0", StringComparison.Ordinal)) observed = false;
                }
                else if (pair.StartsWith("ga:", StringComparison.Ordinal))
                {
                    observedAttemptId = pair.Substring(3);
                }
            }

            if (!observed.HasValue) return;
            lock (_gate)
            {
                _gameEnteredObserved = observed.Value && !string.IsNullOrEmpty(observedAttemptId);
                _gameEnteredAttemptId = _gameEnteredObserved ? observedAttemptId : null;
            }
        }

        internal bool IsExactRuntimeReady(
            string expectedSlot,
            string expectedAttemptId)
        {
            if (string.IsNullOrEmpty(expectedSlot)
                || string.IsNullOrEmpty(expectedAttemptId))
            {
                return false;
            }

            JObject status = BuildStatus(true, null);
            if (!(status.Value<bool?>("readyForRuntimeAutomation")
                    ?? false))
            {
                return false;
            }

            JObject save = status.Value<JObject>("save");
            JObject runtime = status.Value<JObject>("saveRuntime");
            return save != null
                && runtime != null
                && string.Equals(
                    save.Value<string>("slot"),
                    expectedSlot,
                    StringComparison.Ordinal)
                && string.Equals(
                    save.Value<string>("attemptId"),
                    expectedAttemptId,
                    StringComparison.Ordinal)
                && string.Equals(
                    runtime.Value<string>("savePath"),
                    expectedSlot,
                    StringComparison.Ordinal)
                && string.Equals(
                    runtime.Value<string>("attemptId"),
                    expectedAttemptId,
                    StringComparison.Ordinal)
                && string.Equals(
                    status.Value<string>("gameEnteredAttemptId"),
                    expectedAttemptId,
                    StringComparison.Ordinal);
        }

        private JObject Start(JObject msg)
        {
            string slot = msg.Value<string>("slot");
            if (!IsSafeSlot(slot))
                return BuildError("invalid_slot", "slot is required and must not contain path separators or reserved path characters");

            StartGameHandler startGame;
            lock (_gate) { startGame = _startGame; }
            if (startGame == null)
                return BuildError("launch_flow_unavailable", "GameLaunchFlow is not initialized");

            bool fresh = msg.Value<bool?>("fresh") ?? false;
            bool deferJsReveal = msg.Value<bool?>("deferReveal") ?? false;
            bool requireFlashReveal = msg.Value<bool?>("requireFlashReveal") ?? true;
            bool rememberSlot = msg.Value<bool?>("rememberSlot") ?? false;

            if (rememberSlot && _rememberSlot != null)
                _rememberSlot(slot);

            // A new launch attempt must prove its own s:1 receipt. Never inherit a
            // game-enter observation from the previous Flash/runtime session.
            lock (_gate)
            {
                _gameEnteredObserved = false;
                _gameEnteredAttemptId = null;
            }
            startGame(slot, fresh, deferJsReveal, requireFlashReveal);
            return BuildStatus(true, fresh ? "fresh_start_requested" : "start_requested");
        }

        private JObject RevealOk()
        {
            Action revealOk;
            lock (_gate) { revealOk = _revealOk; }
            if (revealOk == null)
                return BuildError("launch_flow_unavailable", "GameLaunchFlow is not initialized");
            revealOk();
            return BuildStatus(true, "reveal_ok_sent");
        }

        private JObject Cancel()
        {
            Action cancel;
            lock (_gate) { cancel = _cancelLaunch; }
            if (cancel == null)
                return BuildError("launch_flow_unavailable", "GameLaunchFlow is not initialized");
            cancel();
            return BuildStatus(true, "cancel_requested");
        }

        private JObject Shutdown()
        {
            Action shutdown;
            lock (_gate) { shutdown = _shutdown; }
            if (shutdown == null)
                return BuildError("shutdown_unavailable", "shutdown action is not initialized");
            shutdown();
            return BuildStatus(true, "shutdown_requested");
        }

        private JObject OpenEquipmentTuning(JObject msg)
        {
            return OpenAgentPanel(msg, "equipment_tuning");
        }

        private JObject OpenCharacterBuild(JObject msg)
        {
            return OpenAgentPanel(msg, "character_build");
        }

        private JObject OpenArena(JObject msg)
        {
            return OpenAgentPanel(msg, "arena");
        }

        private JObject OpenAgentPanel(JObject msg, string panelKind)
        {
            JToken expectedSlotToken = msg["expectedSlot"];
            string expectedSlot = expectedSlotToken != null && expectedSlotToken.Type == JTokenType.String
                ? expectedSlotToken.Value<string>()
                : null;
            if (!IsAgentAutomationSlot(expectedSlot))
            {
                return BuildError(
                    "invalid_expected_slot",
                    "expectedSlot is required and must be a dedicated cf7_agent_* slot");
            }

            JToken expectedAttemptToken = msg["expectedAttemptId"];
            string expectedAttempt = expectedAttemptToken != null && expectedAttemptToken.Type == JTokenType.String
                ? expectedAttemptToken.Value<string>()
                : null;
            if (string.IsNullOrEmpty(expectedAttempt))
            {
                return BuildError(
                    "invalid_expected_attempt",
                    "expectedAttemptId is required");
            }

            JObject status = BuildStatus(true, null);
            JArray runtimeBlockers = status.Value<JArray>("runtimeReadyBlockedBy");
            if (runtimeBlockers == null || runtimeBlockers.Count != 0)
            {
                JObject error = BuildError(
                    "runtime_not_ready",
                    "runtime automation readiness gates have not passed");
                error["runtimeReadyBlockedBy"] = runtimeBlockers != null
                    ? (JToken)runtimeBlockers.DeepClone()
                    : new JArray("runtime_status_unavailable");
                return error;
            }

            JObject save = status["save"] as JObject;
            JObject runtimeSave = status["saveRuntime"] as JObject;
            string currentSlot = save != null ? save.Value<string>("slot") : null;
            string runtimeSlot = runtimeSave != null ? runtimeSave.Value<string>("savePath") : null;
            if (!IsAgentAutomationSlot(currentSlot)
                || !string.Equals(expectedSlot, currentSlot, StringComparison.Ordinal)
                || !string.Equals(expectedSlot, runtimeSlot, StringComparison.Ordinal))
            {
                return BuildError(
                    "agent_slot_mismatch",
                    "expectedSlot must match the current dedicated launcher and runtime save slot");
            }

            string currentAttempt = save != null ? save.Value<string>("attemptId") : null;
            string runtimeAttempt = runtimeSave != null ? runtimeSave.Value<string>("attemptId") : null;
            if (!string.Equals(expectedAttempt, currentAttempt, StringComparison.Ordinal)
                || !string.Equals(expectedAttempt, runtimeAttempt, StringComparison.Ordinal))
            {
                return BuildError(
                    "agent_attempt_mismatch",
                    "expectedAttemptId must match the current launcher and runtime save attempt");
            }

            Func<bool> open;
            lock (_gate)
            {
                open = panelKind == "character_build"
                    ? _openCharacterBuild
                    : panelKind == "arena"
                        ? _openArena
                        : _openEquipmentTuning;
            }
            if (open == null)
            {
                return BuildError(
                    panelKind + "_open_unavailable",
                    panelKind.Replace('_', ' ') + " opener is not initialized");
            }

            bool sent;
            try { sent = open(); }
            catch (Exception ex)
            {
                LogManager.Log("[AgentControlTask] " + panelKind.Replace('_', ' ')
                    + " opener exception: " + ex);
                return BuildError(
                    panelKind + "_open_exception",
                    ex.Message);
            }
            if (!sent)
            {
                return BuildError(
                    panelKind + "_open_failed",
                    panelKind == "arena"
                        ? "AS2 openArenaForAgent command was not sent"
                        : "AS2 openInventoryWorkbench command was not sent");
            }

            return BuildStatus(
                true,
                panelKind + "_panel_open_requested");
        }

        private JObject BuildStatus(bool success, string note)
        {
            string launchState;
            Func<string> getLaunchState;
            lock (_gate) { getLaunchState = _getLaunchState; }
            try { launchState = getLaunchState != null ? getLaunchState() : "Unavailable"; }
            catch (Exception ex) { launchState = "Error:" + ex.Message; }

            bool socketReady = false;
            try { socketReady = _isSocketReady(); } catch { }

            JObject arena = null;
            try { arena = _getArenaStatus(); } catch (Exception ex) { arena = BuildError("arena_status_exception", ex.Message); }
            bool revealPerformed = false;
            Func<bool> isRevealPerformed;
            lock (_gate) { isRevealPerformed = _isRevealPerformed; }
            try { revealPerformed = isRevealPerformed != null && isRevealPerformed(); } catch { }
            bool arenaStatusReadable = arena != null
                && ((arena.Value<bool?>("success") ?? arena.Value<bool?>("ok")) ?? false);

            JObject save = null;
            Func<JObject> getLaunchSaveStatus;
            JObject runtimeSave;
            bool gameEnteredObserved;
            string gameEnteredAttemptId;
            lock (_gate)
            {
                getLaunchSaveStatus = _getLaunchSaveStatus;
                runtimeSave = _runtimeSaveStatus != null ? (JObject)_runtimeSaveStatus.DeepClone() : null;
                gameEnteredObserved = _gameEnteredObserved;
                gameEnteredAttemptId = _gameEnteredAttemptId;
            }
            try { save = getLaunchSaveStatus != null ? getLaunchSaveStatus() : null; }
            catch (Exception ex) { save = BuildError("save_status_exception", ex.Message); }

            string currentAttemptId = save != null ? save.Value<string>("attemptId") : null;
            gameEnteredObserved = gameEnteredObserved
                && !string.IsNullOrEmpty(currentAttemptId)
                && string.Equals(gameEnteredAttemptId, currentAttemptId, StringComparison.Ordinal);

            bool saveDecisionSafe = IsSaveDecisionSafe(save);
            bool runtimeSaveLoaded = IsRuntimeSaveLoaded(save, runtimeSave);
            JArray runtimeReadyBlockedBy = BuildRuntimeReadyBlockers(
                socketReady,
                revealPerformed,
                launchState,
                saveDecisionSafe,
                runtimeSaveLoaded,
                gameEnteredObserved);
            JArray readyBlockedBy = BuildReadyBlockers(
                socketReady,
                revealPerformed,
                launchState,
                arenaStatusReadable,
                saveDecisionSafe,
                runtimeSaveLoaded,
                gameEnteredObserved);

            JObject status = new JObject();
            status["success"] = success;
            status["ok"] = success;
            status["task"] = "agent_control";
            status["note"] = note;
            status["launchState"] = launchState;
            status["revealPerformed"] = revealPerformed;
            status["socketConnected"] = socketReady;
            status["gameEnteredObserved"] = gameEnteredObserved;
            status["gameEnteredAttemptId"] = gameEnteredAttemptId != null
                ? (JToken)gameEnteredAttemptId
                : JValue.CreateNull();
            status["readyForRuntimeAutomation"] = runtimeReadyBlockedBy.Count == 0;
            status["runtimeReadyBlockedBy"] = runtimeReadyBlockedBy;
            status["readyForArenaCalibration"] = readyBlockedBy.Count == 0;
            status["readyBlockedBy"] = readyBlockedBy;
            status["save"] = save != null ? (JToken)save : JValue.CreateNull();
            status["saveRuntime"] = runtimeSave != null ? (JToken)runtimeSave : JValue.CreateNull();
            status["arenaCalibration"] = arena != null ? (JToken)arena : JValue.CreateNull();
            Func<JObject> getActivePanelStatus;
            lock (_gate) { getActivePanelStatus = _getActivePanelStatus; }
            JObject activePanel = null;
            try { activePanel = getActivePanelStatus != null ? getActivePanelStatus() : null; }
            catch (Exception ex) { activePanel = BuildError("active_panel_status_exception", ex.Message); }
            status["activePanel"] = activePanel != null ? (JToken)activePanel : JValue.CreateNull();
            return status;
        }

        private static JObject BuildError(string code, string message)
        {
            JObject error = new JObject();
            error["success"] = false;
            error["ok"] = false;
            error["task"] = "agent_control";
            error["error"] = code;
            error["message"] = message;
            return error;
        }

        private static bool IsSafeSlot(string slot)
        {
            if (string.IsNullOrEmpty(slot))
                return false;
            if (slot == "." || slot == ".." || slot.IndexOf("..", StringComparison.Ordinal) >= 0)
                return false;
            return !UnsafeSlotChars.IsMatch(slot);
        }

        private static bool IsAgentAutomationSlot(string slot)
        {
            return IsSafeSlot(slot) && AgentAutomationSlot.IsMatch(slot);
        }

        private static bool IsSaveDecisionSafe(JObject save)
        {
            if (save == null) return false;
            string decision = save.Value<string>("decision");
            string kind = save.Value<string>("kind");
            return string.Equals(decision, "snapshot", StringComparison.Ordinal)
                && string.Equals(kind, "Snapshot", StringComparison.Ordinal);
        }

        private static bool IsRuntimeSaveLoaded(JObject save, JObject runtime)
        {
            if (save == null || runtime == null) return false;
            if ((runtime.Value<bool?>("loaded") ?? false) != true) return false;

            string expectedAttempt = save.Value<string>("attemptId");
            string actualAttempt = runtime.Value<string>("attemptId");
            if (string.IsNullOrEmpty(expectedAttempt)
                || !string.Equals(expectedAttempt, actualAttempt, StringComparison.Ordinal))
                return false;

            string expectedSlot = save.Value<string>("slot");
            string actualSlot = runtime.Value<string>("savePath");
            if (string.IsNullOrEmpty(expectedSlot)
                || !string.Equals(expectedSlot, actualSlot, StringComparison.Ordinal))
                return false;

            string role = runtime.Value<string>("role");
            if (string.IsNullOrEmpty(role)) return false;

            JToken levelToken = runtime["level"];
            if (levelToken == null || levelToken.Type == JTokenType.Null) return false;
            double level;
            try { level = levelToken.Value<double>(); }
            catch { return false; }
            return !double.IsNaN(level);
        }

        private static JArray BuildReadyBlockers(
            bool socketReady,
            bool revealPerformed,
            string launchState,
            bool arenaStatusReadable,
            bool saveDecisionSafe,
            bool runtimeSaveLoaded,
            bool gameEnteredObserved)
        {
            JArray blockers = new JArray();
            if (!socketReady) blockers.Add("socket_not_connected");
            if (!revealPerformed) blockers.Add("flash_not_revealed");
            if (!string.Equals(launchState, "Ready", StringComparison.Ordinal)) blockers.Add("launcher_not_ready");
            if (!arenaStatusReadable) blockers.Add("arena_status_unreadable");
            if (!saveDecisionSafe) blockers.Add("save_decision_unsafe");
            if (!runtimeSaveLoaded) blockers.Add("runtime_save_not_loaded");
            if (!gameEnteredObserved) blockers.Add("game_enter_not_observed");
            return blockers;
        }

        private static JArray BuildRuntimeReadyBlockers(
            bool socketReady,
            bool revealPerformed,
            string launchState,
            bool saveDecisionSafe,
            bool runtimeSaveLoaded,
            bool gameEnteredObserved)
        {
            JArray blockers = new JArray();
            if (!socketReady) blockers.Add("socket_not_connected");
            if (!revealPerformed) blockers.Add("flash_not_revealed");
            if (!string.Equals(launchState, "Ready", StringComparison.Ordinal)) blockers.Add("launcher_not_ready");
            if (!saveDecisionSafe) blockers.Add("save_decision_unsafe");
            if (!runtimeSaveLoaded) blockers.Add("runtime_save_not_loaded");
            if (!gameEnteredObserved) blockers.Add("game_enter_not_observed");
            return blockers;
        }
    }
}
