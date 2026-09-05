using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// GameStage 外层军阀 SubStage 的 Host 权威绑定。
    ///
    /// 本类只拥有 outer binding、Host panel instance 与单次 terminal 投递；
    /// 不复用/扩写 WarlordBattleTask 的 battle v1，也不裁决整关胜负或奖励。
    /// </summary>
    public sealed class WarlordStageTask
    {
        internal const string BindingSchema =
            "warlord.stage-outer-binding.v1";
        internal const string TerminalSchema =
            "warlord.stage-outer-terminal.v1";
        internal const string AttemptSchema =
            "warlord.stage-outer-attempt.v1";
        internal const string OuterCancellationTaskName =
            "warlord_stage_outer_cancelled";
        internal const string OuterCancellationSchema =
            "warlord.stage-outer-cancellation.v1";
        internal const string ResumeAppliedSchema =
            "warlord.as2-resume-apply.v1";
        internal const string PlayerAvatarPortraitSchema =
            "warlord.player-avatar-portrait.v1";
        internal const string AllowedScenarioRef =
            "warlord_tutorial_v1";
        internal const string Demo2ScenarioRef =
            "warlord_demo_02_v1";
        internal const long InitialRevision = 0;
        internal const int MaximumTerminalHistory = 64;

        internal enum TerminalPrepareDisposition
        {
            Prepared,
            Duplicate,
            Rejected
        }

        internal sealed class PreparedTerminal
        {
            internal object OwnerToken;
            internal string PanelInstanceId;
            internal JObject Envelope;
        }

        internal delegate bool TryOpenStagePanel(
            JObject binding,
            JObject playerAvatarPortrait,
            JObject resumeCheckpoint,
            string reservedPanelInstanceId,
            Func<bool> executionGate,
            Action<PanelHostController.TrackedOpenOutcome> completed);

        private enum Phase
        {
            Opening,
            AwaitingTerminal,
            TerminalPrepared
        }

        private sealed class ActiveStage
        {
            internal JObject Binding;
            internal JObject PlayerAvatarPortrait;
            internal string PanelInstanceId;
            internal Phase Phase;
            internal PreparedTerminal Prepared;
            internal bool VisualCloseObserved;
            internal bool BattleHandoffClosePermit;
            internal bool AwaitingBattleResume;
            internal bool AwaitingBattleResumeApply;
            internal string BattleHandoffToken;
            internal JObject ResumeCheckpoint;
            internal JObject ResumeAppliedReceipt;
        }

        private sealed class TerminalTombstone
        {
            internal JObject Binding;
            internal string PanelInstanceId;
            internal JObject Envelope;
            internal string DeliveryState;
        }

        private static readonly Regex OpaqueIdPattern =
            new Regex(
                "^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$",
                RegexOptions.Compiled);
        private static readonly HashSet<string> TerminalKinds =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "CompleteSubStage",
                "FailStage",
                "Suspended",
                "Unknown"
            };
        private static readonly string[] BindingKeys =
        {
            "schema", "runId", "subStageId", "scenarioRef", "callId",
            "revision"
        };
        private static readonly string[] PlayerAvatarPortraitKeys =
        {
            "schema", "gender", "face", "hair", "equipment"
        };
        private static readonly string[] PlayerAvatarEquipmentKeys =
        {
            "head", "body", "hand", "leg", "foot", "neck"
        };
        private static readonly string[] TerminalKeys =
        {
            "schema", "runId", "subStageId", "scenarioRef", "callId",
            "revision", "terminal", "reasonCode"
        };
        private static readonly string[] OuterCancellationKeys =
        {
            "schema", "binding", "reasonCode"
        };
        private static readonly string[] ResumeAppliedKeys =
        {
            "schema", "status", "inputDigest", "sessionId", "requestId",
            "stageOuterBinding"
        };

        private readonly object _lock = new object();
        private readonly Func<JObject, bool> _trySendResult;
        private readonly Dictionary<string, TerminalTombstone>
            _terminalHistory =
                new Dictionary<string, TerminalTombstone>(
                    StringComparer.Ordinal);
        private TryOpenStagePanel _tryOpenStagePanel;
        private ActiveStage _active;
        private TerminalTombstone _terminalTombstone;
        private bool _terminalHistoryOverflowed;

        public WarlordStageTask(XmlSocketServer socket)
            : this(delegate(JObject command)
            {
                return socket != null
                    && socket.IsClientReady
                    && socket.TrySend(
                        command.ToString(Formatting.None) + "\0");
            })
        {
        }

        internal WarlordStageTask(Func<JObject, bool> trySendResult)
        {
            _trySendResult = trySendResult ?? delegate { return false; };
        }

        internal void SetOpenHandler(TryOpenStagePanel handler)
        {
            _tryOpenStagePanel = handler;
        }

        /// <summary>
        /// AS2 fire-and-forget ingress：exact {task,payload}。
        /// 明确未开始时不返回裸 response，而沿 warlord_stage_result 发 exact attempt，
        /// 避免 MessageRouter 包装字段污染 outer envelope。
        /// </summary>
        public string HandleStart(JObject message)
        {
            JObject binding;
            JObject playerAvatarPortrait;
            string rejection;
            if (!TryParseStartMessage(
                    message,
                    out binding,
                    out playerAvatarPortrait,
                    out rejection))
            {
                LogManager.Log(
                    "event=warlord_stage_start_rejected reason=" + rejection);
                return null;
            }

            if (!IsAllowedScenarioRef(
                    binding.Value<string>("scenarioRef")))
            {
                LogManager.Log(
                    "event=warlord_stage_start_rejected reason=unsupported_scenario");
                return null;
            }

            var candidate = new ActiveStage
            {
                Binding = (JObject)binding.DeepClone(),
                PlayerAvatarPortrait =
                    (JObject)playerAvatarPortrait.DeepClone(),
                PanelInstanceId =
                    "warlord.stage." + Guid.NewGuid().ToString("N"),
                Phase = Phase.Opening
            };
            bool busy = false;
            bool duplicate = false;
            string protocolRejection = null;
            lock (_lock)
            {
                if (_terminalHistoryOverflowed)
                {
                    protocolRejection = "terminal_history_overflow";
                }
                else if (_active != null)
                {
                    duplicate = SameBinding(_active.Binding, binding);
                    busy = !duplicate;
                }
                else
                {
                    string historyKey = IdentityKey(binding);
                    TerminalTombstone history;
                    if (_terminalHistory.TryGetValue(
                            historyKey,
                            out history))
                    {
                        if (SameBinding(history.Binding, binding))
                        {
                            // A duplicate of an already-terminal generation never opens a
                            // second game. Startup failures are terminal for this parent
                            // GameStage too; the player must leave and start a fresh run.
                            duplicate = true;
                        }
                        else
                        {
                            protocolRejection =
                                "invalid_initial_revision";
                        }
                    }
                    else if (binding.Value<long>("revision")
                        != InitialRevision)
                    {
                        protocolRejection =
                            "invalid_initial_revision";
                    }
                    else if (_terminalHistory.Count
                        >= MaximumTerminalHistory)
                    {
                        _terminalHistoryOverflowed = true;
                        protocolRejection =
                            "terminal_history_overflow";
                    }
                    else
                    {
                        _active = candidate;
                    }
                }
            }
            if (protocolRejection != null)
            {
                LogManager.Log(
                    "event=warlord_stage_start_rejected reason="
                    + protocolRejection);
                return null;
            }
            if (duplicate)
            {
                LogManager.Log(
                    "event=warlord_stage_start_duplicate disposition=idempotent");
                return null;
            }
            if (busy)
            {
                SendAttempt(binding, "stage.host-busy");
                return null;
            }

            TryOpenStagePanel open = _tryOpenStagePanel;
            if (open == null)
            {
                CompleteKnownNotStarted(candidate, "stage.host-unavailable");
                return null;
            }

            bool queued = false;
            bool openThrew = false;
            try
            {
                queued = open(
                    (JObject)candidate.Binding.DeepClone(),
                    (JObject)candidate.PlayerAvatarPortrait.DeepClone(),
                    CloneObject(candidate.ResumeCheckpoint),
                    candidate.PanelInstanceId,
                    delegate
                    {
                        lock (_lock)
                        {
                            return ReferenceEquals(_active, candidate)
                                && candidate.Phase == Phase.Opening;
                        }
                    },
                    delegate(PanelHostController.TrackedOpenOutcome outcome)
                    {
                        OnOpenCompleted(candidate, outcome);
                    });
            }
            catch (Exception ex)
            {
                openThrew = true;
                LogManager.Log(
                    "event=warlord_stage_open_exception type="
                    + ex.GetType().Name);
            }
            if (openThrew)
                CompleteOpenUncertain(
                    candidate,
                    "stage.open-exception");
            else if (!queued)
                CompleteKnownNotStarted(candidate, "stage.open-not-started");
            return null;
        }

        internal static bool IsAllowedScenarioRef(string scenarioRef)
        {
            return string.Equals(
                    scenarioRef,
                    AllowedScenarioRef,
                    StringComparison.Ordinal)
                || string.Equals(
                    scenarioRef,
                    Demo2ScenarioRef,
                    StringComparison.Ordinal);
        }

        private void OnOpenCompleted(
            ActiveStage candidate,
            PanelHostController.TrackedOpenOutcome outcome)
        {
            JObject notStarted = null;
            JObject uncertain = null;
            lock (_lock)
            {
                if (!ReferenceEquals(_active, candidate)
                    || candidate.Phase != Phase.Opening)
                    return;

                if (outcome == PanelHostController.TrackedOpenOutcome.OpenPosted)
                {
                    // OpenPosted is emitted only after the exact reserved instance is
                    // Host-active and its Web post was accepted. Queue admission alone
                    // never reaches this state.
                    candidate.Phase = Phase.AwaitingTerminal;
                    LogManager.Log(
                        "event=warlord_stage_open_bound instance="
                        + candidate.PanelInstanceId);
                    return;
                }

                _active = null;
                if (outcome
                        == PanelHostController.TrackedOpenOutcome.PreExecutionRejected
                    || outcome == PanelHostController.TrackedOpenOutcome.PanelBusy
                    || outcome
                        == PanelHostController.TrackedOpenOutcome.PostNotDelivered)
                {
                    notStarted = BuildAttempt(
                        candidate.Binding,
                        "stage.open-not-started");
                    StoreTerminalTombstoneLocked(new TerminalTombstone
                    {
                        Binding = (JObject)candidate.Binding.DeepClone(),
                        PanelInstanceId = candidate.PanelInstanceId,
                        Envelope = (JObject)notStarted.DeepClone(),
                        DeliveryState = "not_started"
                    });
                }
                else
                {
                    uncertain = BuildTerminal(
                        candidate.Binding,
                        "Unknown",
                        "stage.open-uncertain");
                    StoreTerminalTombstoneLocked(new TerminalTombstone
                    {
                        Binding = (JObject)candidate.Binding.DeepClone(),
                        PanelInstanceId = candidate.PanelInstanceId,
                        Envelope = (JObject)uncertain.DeepClone(),
                        DeliveryState = "sending"
                    });
                }
            }
            if (notStarted != null) TrySendOuterEvent(notStarted);
            if (uncertain != null)
                FinishTerminalDelivery(uncertain, TrySendOuterEvent(uncertain));
        }

        private void CompleteKnownNotStarted(
            ActiveStage candidate,
            string reasonCode)
        {
            JObject attempt = null;
            lock (_lock)
            {
                if (!ReferenceEquals(_active, candidate)) return;
                _active = null;
                attempt = BuildAttempt(candidate.Binding, reasonCode);
                StoreTerminalTombstoneLocked(new TerminalTombstone
                {
                    Binding = (JObject)candidate.Binding.DeepClone(),
                    PanelInstanceId = candidate.PanelInstanceId,
                    Envelope = (JObject)attempt.DeepClone(),
                    DeliveryState = "not_started"
                });
            }
            TrySendOuterEvent(attempt);
        }

        private void CompleteOpenUncertain(
            ActiveStage candidate,
            string reasonCode)
        {
            JObject unknown = null;
            lock (_lock)
            {
                if (!ReferenceEquals(_active, candidate)) return;
                _active = null;
                unknown = BuildTerminal(
                    candidate.Binding,
                    "Unknown",
                    reasonCode);
                StoreTerminalTombstoneLocked(new TerminalTombstone
                {
                    Binding = (JObject)candidate.Binding.DeepClone(),
                    PanelInstanceId = candidate.PanelInstanceId,
                    Envelope = (JObject)unknown.DeepClone(),
                    DeliveryState = "sending"
                });
            }
            FinishTerminalDelivery(unknown, TrySendOuterEvent(unknown));
        }

        internal bool OwnsPanelInstance(string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_lock)
            {
                return (_active != null
                            && string.Equals(
                                _active.PanelInstanceId,
                                panelInstanceId,
                                StringComparison.Ordinal))
                    || FindTombstoneByPanelInstanceLocked(
                        panelInstanceId) != null;
            }
        }

        internal bool TryGetActiveOuterRunId(
            string panelInstanceId,
            out string outerRunId)
        {
            outerRunId = null;
            if (string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_lock)
            {
                if (_active == null
                    || !string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _active.Binding == null)
                {
                    return false;
                }
                string candidate = _active.Binding.Value<string>("runId");
                if (!OpaqueIdPattern.IsMatch(candidate ?? "")) return false;
                outerRunId = candidate;
                return true;
            }
        }

        internal bool TryGetActivePlayerAvatarPortrait(
            string panelInstanceId,
            out JObject playerAvatarPortrait)
        {
            playerAvatarPortrait = null;
            if (string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_lock)
            {
                if (_active == null
                    || !string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _active.PlayerAvatarPortrait == null)
                {
                    return false;
                }
                playerAvatarPortrait =
                    (JObject)_active.PlayerAvatarPortrait.DeepClone();
                return true;
            }
        }

        internal bool TryGetActiveBinding(
            string panelInstanceId,
            out JObject binding)
        {
            binding = null;
            if (string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_lock)
            {
                if (_active == null
                    || !string.Equals(_active.PanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)
                    || _active.Binding == null) return false;
                binding = (JObject)_active.Binding.DeepClone();
                return true;
            }
        }

        internal bool TryPermitBattleHandoffClose(
            string panelInstanceId,
            JObject binding,
            out string handoffToken)
        {
            handoffToken = null;
            JObject safeBinding;
            string ignored;
            if (!TryNormalizeBinding(binding, out safeBinding, out ignored)
                || string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_lock)
            {
                if (_active == null || _active.Phase != Phase.AwaitingTerminal
                    || _active.VisualCloseObserved || _active.BattleHandoffClosePermit
                    || _active.AwaitingBattleResumeApply
                    || !string.Equals(_active.PanelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    || !SameBinding(_active.Binding, safeBinding)) return false;
                _active.BattleHandoffClosePermit = true;
                _active.BattleHandoffToken = "warlord.handoff."
                    + Guid.NewGuid().ToString("N");
                handoffToken = _active.BattleHandoffToken;
                return true;
            }
        }

        internal void CancelBattleHandoffClosePermit(
            string panelInstanceId,
            JObject binding,
            string handoffToken)
        {
            lock (_lock)
            {
                if (_active != null && _active.BattleHandoffClosePermit
                    && string.Equals(_active.PanelInstanceId, panelInstanceId, StringComparison.Ordinal)
                    && SameBinding(_active.Binding, binding)
                    && string.Equals(_active.BattleHandoffToken, handoffToken,
                        StringComparison.Ordinal))
                {
                    _active.BattleHandoffClosePermit = false;
                    _active.BattleHandoffToken = null;
                }
            }
        }

        // This is the PanelHost execution gate's irrevocable capability consumption.  It
        // deliberately checks and commits under one lock: no transport callback can clear
        // the active owner between a successful decision and the state transition that
        // permits DoClose.
        internal bool TryCommitBattleHandoffClose(
            string panelInstanceId,
            JObject binding,
            string handoffToken)
        {
            lock (_lock)
            {
                if (_active == null || _active.Phase != Phase.AwaitingTerminal
                    || _active.VisualCloseObserved
                    || !_active.BattleHandoffClosePermit
                    || _active.AwaitingBattleResume
                    || !string.Equals(_active.PanelInstanceId, panelInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(_active.BattleHandoffToken, handoffToken,
                        StringComparison.Ordinal)
                    || !SameBinding(_active.Binding, binding)) return false;
                _active.BattleHandoffClosePermit = false;
                _active.AwaitingBattleResume = true;
                return true;
            }
        }

        internal bool CanAdoptBattleResumePanel(
            JObject binding,
            string retiredPanelInstanceId,
            string handoffToken)
        {
            lock (_lock)
            {
                return _active != null && _active.Phase == Phase.AwaitingTerminal
                    && _active.AwaitingBattleResume
                    && !_active.BattleHandoffClosePermit
                    && string.Equals(_active.PanelInstanceId, retiredPanelInstanceId,
                        StringComparison.Ordinal)
                    && string.Equals(_active.BattleHandoffToken, handoffToken,
                        StringComparison.Ordinal)
                    && SameBinding(_active.Binding, binding);
            }
        }

        internal bool TryAdoptBattleResumePanel(
            JObject binding,
            string retiredPanelInstanceId,
            string resumedPanelInstanceId,
            string handoffToken,
            JObject resumeCheckpoint)
        {
            JObject safeBinding;
            JObject safeCheckpoint;
            string ignored;
            if (!TryNormalizeBinding(binding, out safeBinding, out ignored)
                || !LauncherCommandRouter.TryBuildWarlordResumeInitData(
                    resumeCheckpoint,
                    out safeCheckpoint,
                    out ignored)
                || !IsStageResumeCheckpoint(
                    safeCheckpoint,
                    safeBinding,
                    retiredPanelInstanceId)
                || !OpaqueIdPattern.IsMatch(retiredPanelInstanceId ?? "")
                || !OpaqueIdPattern.IsMatch(resumedPanelInstanceId ?? "")
                || string.Equals(retiredPanelInstanceId, resumedPanelInstanceId,
                    StringComparison.Ordinal)) return false;
            lock (_lock)
            {
                if (_active == null || _active.Phase != Phase.AwaitingTerminal
                    || !_active.AwaitingBattleResume || _active.BattleHandoffClosePermit
                    || !string.Equals(_active.PanelInstanceId, retiredPanelInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(_active.BattleHandoffToken, handoffToken,
                        StringComparison.Ordinal)
                    || !SameBinding(_active.Binding, safeBinding)) return false;
                _active.PanelInstanceId = resumedPanelInstanceId;
                _active.VisualCloseObserved = false;
                _active.AwaitingBattleResume = false;
                _active.AwaitingBattleResumeApply = true;
                _active.BattleHandoffToken = null;
                _active.ResumeCheckpoint = (JObject)safeCheckpoint.DeepClone();
                _active.ResumeAppliedReceipt = null;
                return true;
            }
        }

        internal bool IsPanelReadyForGameplay(string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId)) return false;
            lock (_lock)
            {
                return _active != null
                    && _active.Phase == Phase.AwaitingTerminal
                    && !_active.AwaitingBattleResume
                    && !_active.AwaitingBattleResumeApply
                    && string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal);
            }
        }

        internal bool TryAcceptBattleResumeApplied(
            JObject message,
            string activePanelName,
            string activePanelInstanceId,
            out string rejectionReason)
        {
            string panelInstanceId;
            JObject receipt;
            if (!TryParseResumeAppliedMessage(
                    message,
                    out panelInstanceId,
                    out receipt,
                    out rejectionReason))
            {
                return false;
            }
            if (!string.Equals(activePanelName, "warlord", StringComparison.Ordinal)
                || !string.Equals(
                    activePanelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal))
            {
                rejectionReason = "panel_instance_expired";
                return false;
            }

            lock (_lock)
            {
                if (_active == null
                    || !string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    rejectionReason = "late_event";
                    return false;
                }
                if (!_active.AwaitingBattleResumeApply)
                {
                    if (_active.ResumeAppliedReceipt != null
                        && JToken.DeepEquals(
                            _active.ResumeAppliedReceipt,
                            receipt))
                    {
                        rejectionReason = null;
                        return true;
                    }
                    rejectionReason = "resume_apply_not_expected";
                    return false;
                }
                if (!MatchesResumeCheckpoint(
                        _active.ResumeCheckpoint,
                        _active.Binding,
                        receipt))
                {
                    rejectionReason = "resume_apply_identity_drift";
                    return false;
                }
                _active.AwaitingBattleResumeApply = false;
                _active.ResumeAppliedReceipt =
                    (JObject)receipt.DeepClone();
                rejectionReason = null;
                return true;
            }
        }

        internal void FreezeBattleResumeUnknown(
            JObject binding,
            string retiredPanelInstanceId,
            string handoffToken,
            string reason)
        {
            JObject unknown = null;
            lock (_lock)
            {
                if (_active == null || !_active.AwaitingBattleResume
                    || !string.Equals(_active.PanelInstanceId, retiredPanelInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(_active.BattleHandoffToken, handoffToken,
                        StringComparison.Ordinal)
                    || !SameBinding(_active.Binding, binding)) return;
                unknown = BuildTerminal(_active.Binding, "Unknown",
                    reason ?? "stage.battle-resume-unavailable");
                StoreTerminalTombstoneLocked(new TerminalTombstone
                {
                    Binding = (JObject)_active.Binding.DeepClone(),
                    PanelInstanceId = _active.PanelInstanceId,
                    Envelope = (JObject)unknown.DeepClone(),
                    DeliveryState = "sending"
                });
                _active = null;
            }
            if (unknown != null) FinishTerminalDelivery(unknown, TrySendOuterEvent(unknown));
        }

        internal TerminalPrepareDisposition TryPrepareWebTerminal(
            JObject message,
            string activePanelName,
            string activePanelInstanceId,
            out PreparedTerminal prepared,
            out string rejectionReason)
        {
            prepared = null;
            JObject terminal;
            string panelInstanceId;
            if (!TryParseWebTerminalMessage(
                    message,
                    out panelInstanceId,
                    out terminal,
                    out rejectionReason))
            {
                return TerminalPrepareDisposition.Rejected;
            }
            if (!string.Equals(activePanelName, "warlord", StringComparison.Ordinal)
                || !string.Equals(
                    activePanelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal))
            {
                rejectionReason = "panel_instance_expired";
                return TerminalPrepareDisposition.Rejected;
            }

            lock (_lock)
            {
                TerminalTombstone tombstone =
                    FindTombstoneByPanelInstanceLocked(
                        panelInstanceId);
                if (tombstone != null)
                {
                    if (SameTerminal(tombstone.Envelope, terminal))
                        return TerminalPrepareDisposition.Duplicate;
                    rejectionReason = "terminal_conflict";
                    return TerminalPrepareDisposition.Rejected;
                }
                if (_active == null
                    || !string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    rejectionReason = "late_event";
                    return TerminalPrepareDisposition.Rejected;
                }
                if (_active.Phase == Phase.Opening)
                {
                    rejectionReason = "panel_not_bound";
                    return TerminalPrepareDisposition.Rejected;
                }
                if (_active.AwaitingBattleResumeApply)
                {
                    rejectionReason = "resume_apply_pending";
                    return TerminalPrepareDisposition.Rejected;
                }
                if (!SameIdentity(_active.Binding, terminal))
                {
                    rejectionReason = "identity_drift";
                    return TerminalPrepareDisposition.Rejected;
                }
                if (_active.Phase == Phase.TerminalPrepared)
                {
                    if (_active.Prepared != null
                        && SameTerminal(_active.Prepared.Envelope, terminal))
                        return TerminalPrepareDisposition.Duplicate;
                    rejectionReason = "terminal_conflict";
                    return TerminalPrepareDisposition.Rejected;
                }

                prepared = new PreparedTerminal
                {
                    OwnerToken = _active,
                    PanelInstanceId = panelInstanceId,
                    Envelope = (JObject)terminal.DeepClone()
                };
                _active.Prepared = prepared;
                _active.Phase = Phase.TerminalPrepared;
                rejectionReason = null;
                return TerminalPrepareDisposition.Prepared;
            }
        }

        internal TerminalPrepareDisposition TryPrepareSuspendedClose(
            string panelInstanceId,
            out PreparedTerminal prepared,
            out string rejectionReason)
        {
            prepared = null;
            rejectionReason = null;
            lock (_lock)
            {
                if (FindTombstoneByPanelInstanceLocked(
                        panelInstanceId) != null)
                    return TerminalPrepareDisposition.Duplicate;
                if (_active == null
                    || !string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    rejectionReason = "late_event";
                    return TerminalPrepareDisposition.Rejected;
                }
                if (_active.Phase == Phase.TerminalPrepared)
                    return TerminalPrepareDisposition.Duplicate;

                prepared = new PreparedTerminal
                {
                    OwnerToken = _active,
                    PanelInstanceId = panelInstanceId,
                    Envelope = BuildTerminal(
                        _active.Binding,
                        "Suspended",
                        "stage.panel-closed")
                };
                _active.Prepared = prepared;
                _active.Phase = Phase.TerminalPrepared;
                return TerminalPrepareDisposition.Prepared;
            }
        }

        internal void CommitPreparedTerminal(PreparedTerminal prepared)
        {
            JObject terminal = null;
            lock (_lock)
            {
                ActiveStage owner = prepared != null
                    ? prepared.OwnerToken as ActiveStage
                    : null;
                if (owner == null
                    || !ReferenceEquals(_active, owner)
                    || !ReferenceEquals(owner.Prepared, prepared)
                    || owner.Phase != Phase.TerminalPrepared)
                    return;
                _active = null;
                terminal = (JObject)prepared.Envelope.DeepClone();
                StoreTerminalTombstoneLocked(new TerminalTombstone
                {
                    Binding = (JObject)owner.Binding.DeepClone(),
                    PanelInstanceId = owner.PanelInstanceId,
                    Envelope = (JObject)terminal.DeepClone(),
                    DeliveryState = "sending"
                });
            }
            FinishTerminalDelivery(terminal, TrySendOuterEvent(terminal));
        }

        internal void FreezePreparedCloseUnknown(
            PreparedTerminal prepared,
            string reason)
        {
            lock (_lock)
            {
                ActiveStage owner = prepared != null
                    ? prepared.OwnerToken as ActiveStage
                    : null;
                if (owner == null
                    || !ReferenceEquals(_active, owner)
                    || !ReferenceEquals(owner.Prepared, prepared))
                    return;
                _active = null;
                StoreTerminalTombstoneLocked(new TerminalTombstone
                {
                    Binding = (JObject)owner.Binding.DeepClone(),
                    PanelInstanceId = owner.PanelInstanceId,
                    Envelope = (JObject)prepared.Envelope.DeepClone(),
                    DeliveryState = "close_unknown"
                });
            }
            LogManager.Log(
                "event=warlord_stage_terminal_frozen reason="
                + (reason ?? "close_unknown"));
        }

        internal void HandleAuthoritativePanelClosed(
            string panelName,
            string panelInstanceId)
        {
            if (!string.Equals(panelName, "warlord", StringComparison.Ordinal)
                || string.IsNullOrEmpty(panelInstanceId))
                return;

            JObject suspended = null;
            lock (_lock)
            {
                if (_active == null
                    || !string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                    return;
                _active.VisualCloseObserved = true;
                if (_active.AwaitingBattleResume
                    && !_active.BattleHandoffClosePermit
                    && !string.IsNullOrEmpty(_active.BattleHandoffToken))
                {
                    // The Host had already committed this exact battle handoff before
                    // DoClose.  PanelClosed is intentionally best-effort and may arrive
                    // after the AS2 terminal/resume path; it must never synthesize
                    // Suspended for the retired instance.
                    return;
                }
                // A permit alone is not a committed handoff.  The only legal battle
                // path flips AwaitingBattleResume in PanelHost's commitNoFail before
                // DoClose.  If an unexpected close arrives while merely permitted,
                // it remains an ordinary terminal close instead of wedging stage state.
                if (_active.Phase == Phase.TerminalPrepared)
                    return;

                bool opening = _active.Phase == Phase.Opening;
                suspended = BuildTerminal(
                    _active.Binding,
                    opening ? "Unknown" : "Suspended",
                    opening
                        ? "stage.open-retired"
                        : "stage.panel-retired");
                StoreTerminalTombstoneLocked(new TerminalTombstone
                {
                    Binding = (JObject)_active.Binding.DeepClone(),
                    PanelInstanceId = panelInstanceId,
                    Envelope = (JObject)suspended.DeepClone(),
                    DeliveryState = "sending"
                });
                _active = null;
            }
            FinishTerminalDelivery(suspended, TrySendOuterEvent(suspended));
        }

        internal void HandleTransportDisconnected(string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId)) return;
            lock (_lock)
            {
                if (_active == null
                    || !string.Equals(
                        _active.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                    return;
                JObject unknown = BuildTerminal(
                    _active.Binding,
                    "Unknown",
                    "stage.transport-disconnected");
                StoreTerminalTombstoneLocked(new TerminalTombstone
                {
                    Binding = (JObject)_active.Binding.DeepClone(),
                    PanelInstanceId = panelInstanceId,
                    Envelope = unknown,
                    DeliveryState = "transport_unknown"
                });
                _active = null;
            }
            LogManager.Log(
                "event=warlord_stage_terminal_frozen reason=transport_disconnected");
        }

        internal void HandleTransportDisconnected()
        {
            string panelInstanceId = null;
            lock (_lock)
            {
                if (_active != null)
                    panelInstanceId = _active.PanelInstanceId;
            }
            if (panelInstanceId != null)
                HandleTransportDisconnected(panelInstanceId);
        }

        /// <summary>
        /// 父 GameStage 销毁前发送的唯一 outer 生命周期退役入口。消息必须携带
        /// exact 六字段 binding；这里只退休 Host owner，不回送业务 terminal，
        /// 也不裁决场景、战略结果或通用 stage_outcome。
        /// </summary>
        public string HandleOuterCancellation(JObject message)
        {
            JObject binding;
            string reasonCode;
            string rejection;
            if (!TryParseOuterCancellationMessage(
                    message,
                    out binding,
                    out reasonCode,
                    out rejection))
            {
                LogManager.Log(
                    "event=warlord_stage_outer_cancel_rejected reason="
                    + rejection);
                return null;
            }

            bool retired = RetireExactOuterBinding(binding, reasonCode);
            LogManager.Log(
                "event=warlord_stage_outer_cancel disposition="
                + (retired ? "accepted" : "stale")
                + " reason=" + reasonCode);
            return null;
        }

        private bool RetireExactOuterBinding(
            JObject inputBinding,
            string reasonCode)
        {
            JObject binding;
            string rejection;
            if (!TryNormalizeBinding(
                    inputBinding,
                    out binding,
                    out rejection)) return false;

            bool retired = false;
            lock (_lock)
            {
                if (_active != null
                    && SameBinding(_active.Binding, binding))
                {
                    StoreTerminalTombstoneLocked(new TerminalTombstone
                    {
                        Binding = (JObject)_active.Binding.DeepClone(),
                        PanelInstanceId = _active.PanelInstanceId,
                        // This is a technical owner-retirement receipt, not a
                        // Warlord business terminal and is never sent to AS2.
                        Envelope = new JObject
                        {
                            ["schema"] = OuterCancellationSchema,
                            ["binding"] = binding.DeepClone(),
                            ["reasonCode"] = reasonCode
                        },
                        DeliveryState = "outer_cancelled"
                    });
                    _active = null;
                    retired = true;
                }
                else
                {
                    TerminalTombstone history;
                    if (_terminalHistory.TryGetValue(
                            IdentityKey(binding),
                            out history)
                        && history != null
                        && SameBinding(history.Binding, binding))
                    {
                        return true;
                    }
                }
            }
            return retired;
        }

        private void FinishTerminalDelivery(JObject terminal, bool sent)
        {
            lock (_lock)
            {
                TerminalTombstone history;
                if (terminal != null
                    && _terminalHistory.TryGetValue(
                        IdentityKey(terminal),
                        out history)
                    && SameTerminal(history.Envelope, terminal))
                {
                    history.DeliveryState = sent
                        ? "delivered"
                        : "delivery_unknown";
                    _terminalTombstone = history;
                }
            }
            LogManager.Log(
                "event=warlord_stage_result_terminal delivery="
                + (sent ? "sent" : "unknown"));
        }

        private void SendAttempt(JObject binding, string reasonCode)
        {
            TrySendOuterEvent(BuildAttempt(binding, reasonCode));
        }

        private bool TrySendOuterEvent(JObject outerEvent)
        {
            var command = new JObject
            {
                ["task"] = "cmd",
                ["action"] = "warlord_stage_result",
                ["payload"] = outerEvent != null
                    ? outerEvent.DeepClone()
                    : JValue.CreateNull()
            };
            bool sent = false;
            try { sent = _trySendResult(command); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "event=warlord_stage_result_send_exception type="
                    + ex.GetType().Name);
            }
            if (!sent)
                LogManager.Log(
                    "event=warlord_stage_result_send_failed delivery=unknown");
            return sent;
        }

        internal static JObject BuildAttempt(
            JObject binding,
            string reasonCode)
        {
            JObject attempt = CopyIdentity(binding);
            attempt["schema"] = AttemptSchema;
            attempt["result"] = "not_started";
            attempt["reasonCode"] = reasonCode;
            return attempt;
        }

        internal static JObject BuildTerminal(
            JObject binding,
            string terminal,
            string reasonCode)
        {
            JObject result = CopyIdentity(binding);
            result["schema"] = TerminalSchema;
            result["terminal"] = terminal;
            result["reasonCode"] = reasonCode;
            return result;
        }

        private static JObject CopyIdentity(JObject binding)
        {
            return new JObject
            {
                ["schema"] = BindingSchema,
                ["runId"] = binding["runId"].DeepClone(),
                ["subStageId"] = binding["subStageId"].DeepClone(),
                ["scenarioRef"] = binding["scenarioRef"].DeepClone(),
                ["callId"] = binding["callId"].DeepClone(),
                ["revision"] = binding["revision"].DeepClone()
            };
        }

        internal static bool TryNormalizeBinding(
            JObject input,
            out JObject binding,
            out string rejectionReason)
        {
            binding = null;
            rejectionReason = "invalid_binding";
            if (!HasExactProperties(input, BindingKeys)
                || !IsExactString(input["schema"], BindingSchema)
                || !IsOpaque(input["runId"])
                || !IsOpaque(input["subStageId"])
                || !IsOpaque(input["scenarioRef"])
                || !IsOpaque(input["callId"])
                || !IsSafeRevision(input["revision"]))
                return false;
            binding = CopyIdentity(input);
            rejectionReason = null;
            return true;
        }

        private static bool TryParseStartMessage(
            JObject message,
            out JObject binding,
            out JObject playerAvatarPortrait,
            out string rejectionReason)
        {
            binding = null;
            playerAvatarPortrait = null;
            rejectionReason = "invalid_envelope";
            if (!HasExactProperties(message, new[] { "task", "payload" })
                || !IsExactString(message["task"], "warlord_stage_start"))
                return false;
            JObject payload = message["payload"] as JObject;
            if (!HasExactProperties(
                    payload,
                    new[] { "binding", "playerAvatarPortrait" }))
            {
                return false;
            }
            if (!TryNormalizeBinding(
                    payload["binding"] as JObject,
                    out binding,
                    out rejectionReason))
            {
                return false;
            }
            return TryNormalizePlayerAvatarPortrait(
                payload["playerAvatarPortrait"] as JObject,
                out playerAvatarPortrait,
                out rejectionReason);
        }

        private static bool TryParseOuterCancellationMessage(
            JObject message,
            out JObject binding,
            out string reasonCode,
            out string rejectionReason)
        {
            binding = null;
            reasonCode = null;
            rejectionReason = "invalid_outer_cancellation_envelope";
            if (!HasExactProperties(message, new[] { "task", "payload" })
                || !IsExactString(
                    message["task"],
                    OuterCancellationTaskName))
            {
                return false;
            }
            JObject payload = message["payload"] as JObject;
            if (!HasExactProperties(payload, OuterCancellationKeys)
                || !IsExactString(
                    payload["schema"],
                    OuterCancellationSchema)
                || !IsOpaque(payload["reasonCode"]))
            {
                return false;
            }
            if (!TryNormalizeBinding(
                    payload["binding"] as JObject,
                    out binding,
                    out rejectionReason))
            {
                return false;
            }
            reasonCode = payload.Value<string>("reasonCode");
            rejectionReason = null;
            return true;
        }

        internal static bool TryNormalizePlayerAvatarPortrait(
            JObject input,
            out JObject playerAvatarPortrait,
            out string rejectionReason)
        {
            playerAvatarPortrait = null;
            rejectionReason = "invalid_player_avatar_portrait";
            if (!HasExactProperties(input, PlayerAvatarPortraitKeys)
                || !IsExactString(input["schema"], PlayerAvatarPortraitSchema)
                || !IsExactString(input["gender"], "男")
                    && !IsExactString(input["gender"], "女"))
            {
                return false;
            }
            string face = ReadBoundedPortraitString(input["face"]);
            string hair = ReadBoundedPortraitString(input["hair"]);
            JObject equipment = input["equipment"] as JObject;
            if (face == null || hair == null
                || !HasExactProperties(equipment, PlayerAvatarEquipmentKeys))
            {
                return false;
            }
            var safeEquipment = new JObject();
            for (int i = 0; i < PlayerAvatarEquipmentKeys.Length; i++)
            {
                string key = PlayerAvatarEquipmentKeys[i];
                string value = ReadBoundedPortraitString(equipment[key]);
                if (value == null) return false;
                safeEquipment[key] = value;
            }
            playerAvatarPortrait = new JObject
            {
                ["schema"] = PlayerAvatarPortraitSchema,
                ["gender"] = input.Value<string>("gender"),
                ["face"] = face,
                ["hair"] = hair,
                ["equipment"] = safeEquipment
            };
            rejectionReason = null;
            return true;
        }

        private static JObject CloneObject(JObject value)
        {
            return value == null ? null : (JObject)value.DeepClone();
        }

        private static bool IsStageResumeCheckpoint(
            JObject checkpoint,
            JObject binding,
            string retiredPanelInstanceId)
        {
            return checkpoint != null
                && binding != null
                && IsExactString(checkpoint["source"], "game_stage")
                && IsExactString(checkpoint["mode"], "stage-v1")
                && SameBinding(
                    checkpoint["stageOuterBinding"] as JObject,
                    binding)
                && string.Equals(
                    checkpoint.Value<string>(
                        "stageResumeFromPanelInstanceId"),
                    retiredPanelInstanceId,
                    StringComparison.Ordinal);
        }

        private static bool MatchesResumeCheckpoint(
            JObject checkpoint,
            JObject activeBinding,
            JObject receipt)
        {
            if (checkpoint == null || activeBinding == null || receipt == null
                || !SameBinding(
                    receipt["stageOuterBinding"] as JObject,
                    activeBinding))
            {
                return false;
            }

            JObject resume = checkpoint["resume"] as JObject;
            JObject request = resume != null
                ? resume["request"] as JObject : null;
            JObject battleReceipt = resume != null
                ? resume["receipt"] as JObject : null;
            if (request == null || battleReceipt == null) return false;
            string expectedStatus = string.Equals(
                    battleReceipt.Value<string>("status"),
                    "unknown",
                    StringComparison.Ordinal)
                ? "frozen"
                : "applied";
            return IsExactString(receipt["schema"], ResumeAppliedSchema)
                && IsExactString(receipt["status"], expectedStatus)
                && string.Equals(
                    receipt.Value<string>("inputDigest"),
                    resume.Value<string>("inputDigest"),
                    StringComparison.Ordinal)
                && string.Equals(
                    receipt.Value<string>("sessionId"),
                    request.Value<string>("sessionId"),
                    StringComparison.Ordinal)
                && string.Equals(
                    receipt.Value<string>("requestId"),
                    request.Value<string>("requestId"),
                    StringComparison.Ordinal);
        }

        private static bool TryParseResumeAppliedMessage(
            JObject message,
            out string panelInstanceId,
            out JObject receipt,
            out string rejectionReason)
        {
            panelInstanceId = null;
            receipt = null;
            rejectionReason = "invalid_resume_apply_envelope";
            if (!HasExactProperties(
                    message,
                    new[]
                    {
                        "type", "panel", "cmd", "panelInstanceId", "payload"
                    })
                || !IsExactString(message["type"], "panel")
                || !IsExactString(message["panel"], "warlord")
                || !IsExactString(message["cmd"], "minigame_session")
                || !IsOpaque(message["panelInstanceId"]))
            {
                return false;
            }
            JObject payload = message["payload"] as JObject;
            JObject data = payload != null ? payload["data"] as JObject : null;
            JObject binding;
            string ignored;
            string status = data != null
                ? data.Value<string>("status") : null;
            string digest = data != null
                ? data.Value<string>("inputDigest") : null;
            if (!HasExactProperties(payload, new[] { "game", "kind", "data" })
                || !IsExactString(payload["game"], "warlord")
                || !IsExactString(payload["kind"], "battle_resume_applied")
                || !HasExactProperties(data, ResumeAppliedKeys)
                || !IsExactString(data["schema"], ResumeAppliedSchema)
                || (status != "applied" && status != "frozen")
                || digest == null
                || digest.Length != 71
                || !digest.StartsWith("sha256:", StringComparison.Ordinal)
                || !IsOpaque(data["sessionId"])
                || !IsOpaque(data["requestId"])
                || !TryNormalizeBinding(
                    data["stageOuterBinding"] as JObject,
                    out binding,
                    out ignored))
            {
                return false;
            }

            receipt = new JObject
            {
                ["schema"] = ResumeAppliedSchema,
                ["status"] = status,
                ["inputDigest"] = digest,
                ["sessionId"] = data.Value<string>("sessionId"),
                ["requestId"] = data.Value<string>("requestId"),
                ["stageOuterBinding"] = binding
            };
            panelInstanceId = message.Value<string>("panelInstanceId");
            rejectionReason = null;
            return true;
        }

        private static bool TryParseWebTerminalMessage(
            JObject message,
            out string panelInstanceId,
            out JObject terminal,
            out string rejectionReason)
        {
            panelInstanceId = null;
            terminal = null;
            rejectionReason = "invalid_web_envelope";
            if (!HasExactProperties(
                    message,
                    new[]
                    {
                        "type", "panel", "cmd", "panelInstanceId", "payload"
                    })
                || !IsExactString(message["type"], "panel")
                || !IsExactString(message["panel"], "warlord")
                || !IsExactString(message["cmd"], "minigame_session")
                || !IsOpaque(message["panelInstanceId"]))
                return false;
            JObject payload = message["payload"] as JObject;
            if (!HasExactProperties(payload, new[] { "game", "kind", "data" })
                || !IsExactString(payload["game"], "warlord")
                || !IsExactString(payload["kind"], "stage_terminal"))
                return false;
            JObject data = payload["data"] as JObject;
            if (!TryNormalizeTerminal(data, out terminal, out rejectionReason))
                return false;
            panelInstanceId = message.Value<string>("panelInstanceId");
            rejectionReason = null;
            return true;
        }

        internal static bool TryNormalizeTerminal(
            JObject input,
            out JObject terminal,
            out string rejectionReason)
        {
            terminal = null;
            rejectionReason = "invalid_terminal";
            if (!HasExactProperties(input, TerminalKeys)
                || !IsExactString(input["schema"], TerminalSchema)
                || !IsOpaque(input["runId"])
                || !IsOpaque(input["subStageId"])
                || !IsOpaque(input["scenarioRef"])
                || !IsOpaque(input["callId"])
                || !IsSafeRevision(input["revision"])
                || input["terminal"] == null
                || input["terminal"].Type != JTokenType.String
                || !TerminalKinds.Contains(
                    input.Value<string>("terminal") ?? "")
                || !IsOpaque(input["reasonCode"]))
                return false;
            terminal = new JObject
            {
                ["schema"] = TerminalSchema,
                ["runId"] = input["runId"].DeepClone(),
                ["subStageId"] = input["subStageId"].DeepClone(),
                ["scenarioRef"] = input["scenarioRef"].DeepClone(),
                ["callId"] = input["callId"].DeepClone(),
                ["revision"] = input["revision"].DeepClone(),
                ["terminal"] = input["terminal"].DeepClone(),
                ["reasonCode"] = input["reasonCode"].DeepClone()
            };
            rejectionReason = null;
            return true;
        }

        private static bool SameIdentity(JObject binding, JObject outerEvent)
        {
            return binding != null && outerEvent != null
                && string.Equals(
                    binding.Value<string>("runId"),
                    outerEvent.Value<string>("runId"),
                    StringComparison.Ordinal)
                && string.Equals(
                    binding.Value<string>("subStageId"),
                    outerEvent.Value<string>("subStageId"),
                    StringComparison.Ordinal)
                && string.Equals(
                    binding.Value<string>("scenarioRef"),
                    outerEvent.Value<string>("scenarioRef"),
                    StringComparison.Ordinal)
                && string.Equals(
                    binding.Value<string>("callId"),
                    outerEvent.Value<string>("callId"),
                    StringComparison.Ordinal)
                && binding.Value<long>("revision")
                    == outerEvent.Value<long>("revision");
        }

        private static bool SameBinding(JObject left, JObject right)
        {
            return SameIdentity(left, right);
        }

        private static bool SameTerminal(JObject left, JObject right)
        {
            return left != null && right != null
                && JToken.DeepEquals(left, right);
        }

        private static string IdentityKey(JObject binding)
        {
            if (binding == null) return "";
            return (binding.Value<string>("runId") ?? "") + "|"
                + (binding.Value<string>("subStageId") ?? "") + "|"
                + (binding.Value<string>("scenarioRef") ?? "");
        }

        private void StoreTerminalTombstoneLocked(
            TerminalTombstone tombstone)
        {
            if (tombstone == null || tombstone.Binding == null) return;
            string key = IdentityKey(tombstone.Binding);
            if (!_terminalHistory.ContainsKey(key)
                && _terminalHistory.Count >= MaximumTerminalHistory)
            {
                // Never evict authority history. Once the bounded set is full,
                // all later starts fail closed until a fresh Host process owns it.
                _terminalHistoryOverflowed = true;
                _terminalTombstone = tombstone;
                return;
            }
            _terminalHistory[key] = tombstone;
            _terminalTombstone = tombstone;
        }

        private TerminalTombstone FindTombstoneByPanelInstanceLocked(
            string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId)) return null;
            foreach (TerminalTombstone history in _terminalHistory.Values)
            {
                if (string.Equals(
                        history.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                    return history;
            }
            if (_terminalTombstone != null
                && string.Equals(
                    _terminalTombstone.PanelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal))
                return _terminalTombstone;
            return null;
        }

        private static bool HasExactProperties(
            JObject value,
            string[] expected)
        {
            if (value == null || value.Count != expected.Length) return false;
            for (int i = 0; i < expected.Length; i++)
                if (value.Property(expected[i]) == null) return false;
            return true;
        }

        private static bool IsExactString(JToken token, string expected)
        {
            return token != null
                && token.Type == JTokenType.String
                && string.Equals(
                    token.Value<string>(),
                    expected,
                    StringComparison.Ordinal);
        }

        private static bool IsOpaque(JToken token)
        {
            return token != null
                && token.Type == JTokenType.String
                && OpaqueIdPattern.IsMatch(token.Value<string>() ?? "");
        }

        private static string ReadBoundedPortraitString(JToken token)
        {
            if (token == null || token.Type != JTokenType.String) return null;
            string value = token.Value<string>();
            if (value == null || value.Length > 128) return null;
            for (int i = 0; i < value.Length; i++)
            {
                if (char.IsControl(value[i]) || value[i] == '\\' || value[i] == '\"')
                    return null;
            }
            return value;
        }

        private static bool IsSafeRevision(JToken token)
        {
            if (token == null || token.Type != JTokenType.Integer) return false;
            long value;
            try { value = token.Value<long>(); }
            catch { return false; }
            return value >= 0 && value <= 9007199254740991L;
        }
    }
}
