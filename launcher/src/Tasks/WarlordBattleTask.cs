using System;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Data;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 军阀战术演习 Web 战略态到 AS2 真实战斗的单次 handoff 协调器。
    ///
    /// Web 只提交冻结的战略快照与 MOVE_OR_ATTACK 意图。Host 复验 exact owner、
    /// canonical digest、棋子/节点/战宠目录身份后，自行投影 fresh Action encounter；
    /// AS2 回执只描述隔离战斗结果，本类不写玩家战宠、经验、货币或存档。
    /// </summary>
    public sealed class WarlordBattleTask
    {
        internal sealed class PreparedBattle
        {
            public string PanelInstanceId;
            public string WebCallId;
            public string SessionId;
            public string OuterRunId;
            public string EncounterId;
            public string RequestId;
            public string InputDigest;
            public JObject FrozenRequest;
            public JObject FrozenState;
            public JObject Command;
            public JObject ClientContext;
            public JObject PlayerAvatarPortrait;
            public JObject StageOuterBinding;
            // Host-private, one-shot capability for moving a GameStage owner from
            // the retired battle panel to the tracked resume panel.  Never serialized.
            public string StageHandoffToken;
            public JArray Attackers;
            public JArray Defenders;
            public JObject ActionEncounterControl;
            public JObject ActionEncounterBinding;
            public JObject AcceptedActionTerminal;
            public JObject ResumeInitData;
            // Single transport claim, not a parallel encounter lifecycle. It is set
            // before dispatch so a synchronous exact terminal can safely consume _active.
            public bool ActionDispatchClaimed;
            // A successful socket write is not an AS2 receipt.  The first generation is
            // frozen here so bounded retries can never cross a Flash reconnect.
            public bool ActionTransportGenerationCaptured;
            public int ActionTransportGeneration;
            public int ActionDispatchAttempts;
            public bool ActionAdmissionReceived;
            public IDisposable ActionAdmissionRetry;
            // Absorbing parent-exit fence. It suppresses a terminal/resume callback that
            // was queued immediately before the exact cancellation arrived.
            public bool ParentRetired;
        }

        private sealed class EncounterNodeDefinition
        {
            public readonly string Kind;
            public readonly int AttackWidth;
            public readonly string ProfileRef;
            public readonly string DistanceBand;
            public readonly int SpawnDistance;

            public EncounterNodeDefinition(
                string kind,
                int attackWidth,
                string profileRef,
                string distanceBand,
                int spawnDistance)
            {
                Kind = kind;
                AttackWidth = attackWidth;
                ProfileRef = profileRef;
                DistanceBand = distanceBand;
                SpawnDistance = spawnDistance;
            }
        }

        private sealed class EncounterProjection
        {
            public readonly string Mode;
            public readonly string MapDefinitionId;
            public readonly string StrategicConfigDigest;
            public readonly string DefinitionId;
            public readonly string RulesVersion;
            public readonly string ConfigDigest;
            public readonly string ProfileRef;
            public readonly string DistanceBand;
            public readonly int SpawnDistance;

            public EncounterProjection(
                string mode,
                string mapDefinitionId,
                string strategicConfigDigest,
                string definitionId,
                string rulesVersion,
                string configDigest,
                string profileRef,
                string distanceBand,
                int spawnDistance)
            {
                Mode = mode;
                MapDefinitionId = mapDefinitionId;
                StrategicConfigDigest = strategicConfigDigest;
                DefinitionId = definitionId;
                RulesVersion = rulesVersion;
                ConfigDigest = configDigest;
                ProfileRef = profileRef;
                DistanceBand = distanceBand;
                SpawnDistance = spawnDistance;
            }
        }

        private sealed class PlayerAvatarProjectionAuthority
        {
            public readonly bool CommanderSidecarPresent;
            public readonly string PieceId;

            public PlayerAvatarProjectionAuthority(
                bool commanderSidecarPresent,
                string pieceId)
            {
                CommanderSidecarPresent = commanderSidecarPresent;
                PieceId = pieceId;
            }
        }

        private const int MaximumRequestBytes = 512 * 1024;
        private const int MaximumUnitsPerSide = 64;
        internal const string ActionEncounterBindingSchema =
            "warlord.action-encounter-binding.v2";
        internal const string ActionEncounterTerminalSchema =
            "warlord.action-encounter-terminal.v2";
        internal const string ActionEncounterAdmissionSchema =
            "warlord.action-encounter-admission.v1";
        internal const string ActionEncounterCancellationSchema =
            "warlord.action-encounter-cancellation.v1";
        private const int ActionAdmissionRetryDelayMilliseconds = 1000;
        private const int MaximumActionDispatchAttempts = 4;
        private static readonly Regex OpaqueIdPattern =
            new Regex("^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$", RegexOptions.Compiled);
        private static readonly Regex CanonicalDigestPattern =
            new Regex("^sha256:[0-9a-f]{64}$", RegexOptions.Compiled);
        private static readonly string[] ActionEncounterTerminalKeys =
        {
            "schema", "outerRunId", "encounterId", "requestId", "inputDigest",
            "status", "reasonCode", "result"
        };
        private static readonly string[] ActionEncounterBindingKeys =
        {
            "schema", "outerRunId", "encounterId", "requestId", "inputDigest"
        };
        private static readonly string[] ActionEncounterCancellationKeys =
        {
            "schema", "actionBinding", "stageOuterBinding", "reasonCode"
        };
        private static readonly string[] ActionEncounterAdmissionKeys =
        {
            "schema", "binding", "disposition", "phase"
        };
        private static readonly HashSet<string> ActionAdmissionDispositions =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "accepted", "duplicate"
            };
        private static readonly HashSet<string> ActionAdmissionPhases =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "prepared", "entering", "activating", "active", "returning", "terminal"
            };
        private static readonly HashSet<string> ActionCancellationReasons =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "parent_return_base", "parent_restart", "stage_exit"
            };
        private static readonly Regex PieceIdPattern =
            new Regex("^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", RegexOptions.Compiled);
        private static readonly HashSet<string> AllowedDifficulties =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "easy", "normal", "hard", "extreme"
            };
        private static readonly HashSet<string> AllowedPresets =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "standard", "all-units"
            };
        private static readonly HashSet<string> AllowedActionFormations =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "line", "column", "wedge", "shield", "grid"
            };
        private const string Demo1OrganizationDefinitionId = "demo1-organizations";
        private const string Demo1OrganizationRulesVersion = "warlord.organization.v1";
        private const string Demo1OrganizationConfigDigest =
            "sha256:7FBBFE6B24592A7356B6AC9CACB14D49803FBA2214D8A9FFBD71599211114DA3";
        private const string Demo1RulesVersion = "wargame-demo-v0.1.1";
        private const string Demo1ScenarioId = "warlord_tutorial_v1";
        private const string Demo1MapDefinitionId = "demo-nine-node";
        private const string Demo2ScenarioId = "warlord_demo_02_v1";
        private const string Demo2MapDefinitionId = "demo2-thick-x-80";
        private const string Demo2PlayerFactionId = "player";
        private const string Demo2PlayerCommanderId = "commander.player";
        private const string Demo2PlayerCharacterId = "character.player-avatar";
        private const int Demo2PlayerCommanderCardId = 83;
        private const string PetProjectionKind = "pet_projection";
        private const string PlayerAvatarProjectionKind = "player_avatar";
        private const string Demo1StrategicConfigDigest =
            "sha256:9DA8013D3B7D1C1F5C5B27BDA813F1ADC9E2C8C5C80F3680B9FFDF773A9B76B0";
        private const string Demo1EncounterDefinitionId = "demo1-encounter-distance";
        private const string Demo1EncounterRulesVersion = "warlord.encounter-distance.v1";
        private const string Demo1EncounterConfigDigest =
            "sha256:6D94E0ABCA11BE5AE1574219D30E4E8E1E3890293496FB2192E081AB24DFE29E";
        private static readonly Dictionary<string, EncounterNodeDefinition> Demo1EncounterNodes =
            new Dictionary<string, EncounterNodeDefinition>(StringComparer.Ordinal)
            {
                ["R-HQ"] = new EncounterNodeDefinition("hq", 3, "encounter.near", "near", 180),
                ["R-Supply"] = new EncounterNodeDefinition("supply", 3, "encounter.medium", "medium", 360),
                ["R-Economy"] = new EncounterNodeDefinition("economy", 3, "encounter.medium", "medium", 360),
                ["North-Choke"] = new EncounterNodeDefinition("choke", 2, "encounter.far", "far", 650),
                ["Center-Command"] = new EncounterNodeDefinition("command", 4, "encounter.far", "far", 650),
                ["South-Depot"] = new EncounterNodeDefinition("depot", 3, "encounter.far", "far", 650),
                ["B-Economy"] = new EncounterNodeDefinition("economy", 3, "encounter.medium", "medium", 360),
                ["B-Supply"] = new EncounterNodeDefinition("supply", 3, "encounter.medium", "medium", 360),
                ["B-HQ"] = new EncounterNodeDefinition("hq", 3, "encounter.near", "near", 180)
            };
        private static readonly Dictionary<string, EncounterNodeDefinition> Demo2EncounterNodes =
            BuildDemo2EncounterNodes();
        private static readonly HashSet<string> StrategicPromotionNames =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "基础训练", "强化药剂", "超级血清"
            };
        private static readonly Dictionary<string, int> StrategicPromotionLevels =
            new Dictionary<string, int>(StringComparer.Ordinal)
            {
                ["基础训练"] = 10,
                ["强化药剂"] = 25,
                ["超级血清"] = 50
            };

        private readonly PetCatalog _petCatalog;
        private readonly WarlordScenarioAuthorityCatalog _scenarioAuthorityCatalog;
        private readonly Func<JObject, bool> _trySendActionEncounter;
        private Func<int?> _tryGetActionTransportGeneration;
        private Func<JObject, int, bool> _trySendActionEncounterIfGeneration;
        private Func<Action, int, IDisposable> _scheduleActionAdmissionRetry;
        private Func<int, bool> _forceCloseActionTransportIfGeneration;
        private readonly object _lock = new object();
        private Action<JObject> _openResumePanel;
        private Action<JObject, PreparedBattle> _openResumePanelWithPrepared;
        private Action<Action> _invokeOnUI;
        private PreparedBattle _active;
        private PreparedBattle _lastCompleted;
        private JObject _lastCancellation;

        public WarlordBattleTask(XmlSocketServer socket, string projectRoot)
            : this(
                PetCatalogLoader.Load(projectRoot),
                WarlordScenarioAuthorityCatalog.CreateDefault(),
                delegate { return false; })
        {
            _tryGetActionTransportGeneration = delegate
            {
                int generation;
                return socket != null
                    && socket.TryGetReadyGeneration(out generation)
                    ? (int?)generation
                    : null;
            };
            _trySendActionEncounterIfGeneration = delegate(
                JObject command, int generation)
            {
                return socket != null && socket.TrySendIfGen(
                    command.ToString(Formatting.None) + "\0",
                    generation);
            };
            _scheduleActionAdmissionRetry = delegate(Action callback, int delay)
            {
                return new System.Threading.Timer(
                    delegate { callback(); },
                    null,
                    delay,
                    System.Threading.Timeout.Infinite);
            };
            _forceCloseActionTransportIfGeneration = delegate(int generation)
            {
                return socket != null
                    && socket.ForceCloseCurrentClientIfGen(generation);
            };
        }

        internal WarlordBattleTask(
            PetCatalog petCatalog,
            Func<JObject, bool> trySendActionEncounter)
            : this(
                petCatalog,
                WarlordScenarioAuthorityCatalog.CreateDefault(),
                trySendActionEncounter)
        {
        }

        internal WarlordBattleTask(
            PetCatalog petCatalog,
            WarlordScenarioAuthorityCatalog scenarioAuthorityCatalog,
            Func<JObject, bool> trySendActionEncounter)
        {
            _petCatalog = petCatalog
                ?? throw new ArgumentNullException(nameof(petCatalog));
            _scenarioAuthorityCatalog = scenarioAuthorityCatalog
                ?? throw new ArgumentNullException(nameof(scenarioAuthorityCatalog));
            _trySendActionEncounter = trySendActionEncounter
                ?? delegate { return false; };
        }

        /// <summary>
        /// Deterministic retry seam for focused tests. Production wiring always comes from
        /// XmlSocketServer and therefore remains generation-bound.
        /// </summary>
        internal void SetActionAdmissionRetryInfrastructureForTests(
            Func<int?> tryGetGeneration,
            Func<JObject, int, bool> trySendIfGeneration,
            Func<Action, int, IDisposable> scheduleOnce,
            Func<int, bool> forceCloseIfGeneration)
        {
            _tryGetActionTransportGeneration = tryGetGeneration;
            _trySendActionEncounterIfGeneration = trySendIfGeneration;
            _scheduleActionAdmissionRetry = scheduleOnce;
            _forceCloseActionTransportIfGeneration = forceCloseIfGeneration;
        }

        public void SetResumeOpenHandler(Action<JObject> handler)
        {
            _openResumePanel = handler;
        }

        internal void SetResumeOpenHandler(
            Action<JObject, PreparedBattle> handler)
        {
            _openResumePanelWithPrepared = handler;
        }

        public void SetInvoker(Action<Action> invoker)
        {
            _invokeOnUI = invoker;
        }

        public bool HasActiveBattle
        {
            get { lock (_lock) return _active != null; }
        }

        internal JObject Prepare(
            JObject envelope,
            string activePanelInstanceId,
            out PreparedBattle prepared)
        {
            return Prepare(
                envelope,
                activePanelInstanceId,
                null,
                null,
                out prepared);
        }

        internal JObject Prepare(
            JObject envelope,
            string activePanelInstanceId,
            string outerRunId,
            out PreparedBattle prepared)
        {
            return Prepare(
                envelope,
                activePanelInstanceId,
                outerRunId,
                null,
                null,
                out prepared);
        }

        internal JObject Prepare(
            JObject envelope,
            string activePanelInstanceId,
            string outerRunId,
            JObject trustedPlayerAvatarPortrait,
            out PreparedBattle prepared)
        {
            return Prepare(
                envelope,
                activePanelInstanceId,
                outerRunId,
                null,
                trustedPlayerAvatarPortrait,
                out prepared);
        }

        internal JObject Prepare(
            JObject envelope,
            string activePanelInstanceId,
            string outerRunId,
            JObject trustedStageOuterBinding,
            JObject trustedPlayerAvatarPortrait,
            out PreparedBattle prepared)
        {
            prepared = null;
            try
            {
                if (!OpaqueIdPattern.IsMatch(activePanelInstanceId ?? ""))
                    return Error(envelope, "panel_not_active", "warlord panel is not active");
                if (envelope == null
                    || !string.Equals(envelope.Value<string>("panel"), "warlord", StringComparison.Ordinal)
                    || !string.Equals(envelope.Value<string>("cmd"), "battle_start", StringComparison.Ordinal)
                    || !string.Equals(envelope.Value<string>("panelInstanceId"), activePanelInstanceId, StringComparison.Ordinal))
                    return Error(envelope, "panel_instance_expired", "warlord panel owner is stale");

                string callId = envelope.Value<string>("callId") ?? "";
                if (!OpaqueIdPattern.IsMatch(callId))
                    return Error(envelope, "invalid_call_id", "callId is invalid");

                JObject request = envelope["request"] as JObject;
                string suppliedDigest = envelope.Value<string>("inputDigest") ?? "";
                if (request == null)
                    return Error(envelope, "invalid_request", "request must be an object");
                string compact = request.ToString(Formatting.None);
                if (Encoding.UTF8.GetByteCount(compact) > MaximumRequestBytes)
                    return Error(envelope, "request_too_large", "request exceeds the 512 KiB bound");

                string digest = Sha256OfToken(request);
                if (!FixedTimeEquals(digest, suppliedDigest))
                    return Error(envelope, "input_digest_mismatch", "canonical input digest mismatch");

                JObject safePlayerAvatarPortrait = null;
                JObject safeStageOuterBinding = null;
                string portraitRejection;
                if (trustedPlayerAvatarPortrait != null
                    && !WarlordStageTask.TryNormalizePlayerAvatarPortrait(
                        trustedPlayerAvatarPortrait,
                        out safePlayerAvatarPortrait,
                        out portraitRejection))
                {
                    return Error(
                        envelope,
                        portraitRejection ?? "invalid_player_avatar_portrait",
                        "Host player avatar portrait is invalid");
                }
                if (trustedStageOuterBinding != null
                    && !WarlordStageTask.TryNormalizeBinding(
                        trustedStageOuterBinding,
                        out safeStageOuterBinding,
                        out portraitRejection))
                {
                    return Error(envelope,
                        portraitRejection ?? "invalid_stage_outer_binding",
                        "Host stage binding is invalid");
                }
                if (safeStageOuterBinding != null
                    && (!string.Equals(
                            safeStageOuterBinding.Value<string>("runId"),
                            outerRunId,
                            StringComparison.Ordinal)
                        || safePlayerAvatarPortrait == null))
                {
                    return Error(envelope, "stage_binding_mismatch",
                        "Host stage binding does not match the active battle");
                }
                PreparedBattle candidate = NormalizeRequest(
                    request,
                    activePanelInstanceId,
                    callId,
                    digest,
                    outerRunId);
                candidate.PlayerAvatarPortrait = safePlayerAvatarPortrait;
                candidate.StageOuterBinding = safeStageOuterBinding;
                candidate.ActionEncounterBinding = BuildActionEncounterBinding(candidate);
                lock (_lock)
                {
                    if (_active != null)
                        return Error(envelope, "battle_already_running", "another warlord battle handoff is active");
                    _active = candidate;
                }
                prepared = candidate;
                return SuccessEnvelope(candidate, "prepared");
            }
            catch (Exception ex)
            {
                LogManager.Log("[WarlordBattleTask] prepare rejected: " + ex.Message);
                return Error(envelope, "invalid_request", ex.Message);
            }
        }

        internal bool CancelPrepared(PreparedBattle prepared, string reason)
        {
            lock (_lock)
            {
                if (_active == null || !ReferenceEquals(_active, prepared)
                    || _active.ActionDispatchClaimed) return false;
                CancelActionAdmissionRetryLocked(_active);
                _active = null;
            }
            LogManager.Log("[WarlordBattleTask] prepared handoff cancelled: " + (reason ?? "unknown"));
            return true;
        }

        internal bool CancelAndResume(PreparedBattle prepared, string code, string message)
        {
            if (!CancelPrepared(prepared, code)) return false;
            OpenResume(BuildNotStartedResume(prepared, code, message), prepared);
            return true;
        }

        internal JObject StartPrepared(PreparedBattle prepared)
        {
            lock (_lock)
            {
                if (_active == null || !ReferenceEquals(_active, prepared)
                    || _active.ActionDispatchClaimed)
                    return ErrorForPrepared(prepared, "handoff_expired", "prepared handoff is no longer current");
                // Claim under the same lock that protects _active. The transport can
                // synchronously deliver terminal before its send call returns.
                _active.ActionDispatchClaimed = true;
            }

            bool started = DispatchActionEncounter(prepared);
            if (!started)
            {
                bool stillOwned;
                lock (_lock)
                {
                    stillOwned = ReferenceEquals(_active, prepared);
                    if (stillOwned)
                    {
                        _active = null;
                        _lastCompleted = prepared;
                        CancelActionAdmissionRetryLocked(prepared);
                    }
                }
                // Transport may synchronously deliver and consume an exact terminal
                // before returning false. That terminal is authoritative; never open a
                // second not_started resume over it.
                if (!stillOwned)
                    return SuccessEnvelope(prepared, "terminal_completed_synchronously");
                JObject resume = BuildNotStartedResume(
                    prepared,
                    "action_encounter_dispatch_failed",
                    "fresh Action encounter was not delivered");
                prepared.ResumeInitData = (JObject)resume.DeepClone();
                OpenResume(resume, prepared);
                return ErrorForPrepared(
                    prepared,
                    "action_encounter_dispatch_failed",
                    "fresh Action encounter did not start");
            }

            ScheduleActionAdmissionRetry(prepared);
            return SuccessEnvelope(prepared, "awaiting_admission");
        }

        private PreparedBattle NormalizeRequest(
            JObject request,
            string panelInstanceId,
            string callId,
            string digest,
            string suppliedOuterRunId)
        {
            if (!string.Equals(
                request.Value<string>("schema"),
                "warlord.as2-battle-request.v1",
                StringComparison.Ordinal))
                throw new InvalidOperationException("unsupported warlord battle request schema");

            string sessionId = RequiredOpaque(request, "sessionId");
            string requestId = RequiredOpaque(request, "requestId");
            string outerRunId = string.IsNullOrEmpty(suppliedOuterRunId)
                ? sessionId
                : suppliedOuterRunId;
            if (!OpaqueIdPattern.IsMatch(outerRunId))
                throw new InvalidOperationException("outer Warlord runId is invalid");
            string encounterId = "encounter."
                + digest.Substring("sha256:".Length, 40).ToLowerInvariant();
            JObject state = request["state"] as JObject
                ?? throw new InvalidOperationException("state must be an object");
            JObject command = request["command"] as JObject
                ?? throw new InvalidOperationException("command must be an object");
            JObject clientContext = NormalizeClientContext(request["clientContext"] as JObject);

            if (state.Value<int?>("schemaVersion") != 1)
                throw new InvalidOperationException("unsupported strategic state schemaVersion");
            if (!string.Equals(command.Value<string>("type"), "MOVE_OR_ATTACK", StringComparison.Ordinal))
                throw new InvalidOperationException("only MOVE_OR_ATTACK may enter AS2 battle authority");

            string attackerFaction = RequiredFactionId(
                command.Value<string>("factionId"),
                "command.factionId");
            string phase = state.Value<string>("phase") ?? "";
            if (phase != "FIRST_FACTION_ACTION" && phase != "SECOND_FACTION_ACTION")
                throw new InvalidOperationException("state is not in an action phase");
            if (!string.Equals(
                state.Value<string>("activeFactionId"),
                attackerFaction,
                StringComparison.Ordinal))
                throw new InvalidOperationException("command faction is not the active faction");
            string originNodeId = RequiredSafe(command, "originNodeId", 96);
            string targetNodeId = RequiredSafe(command, "targetNodeId", 96);
            if (originNodeId == targetNodeId)
                throw new InvalidOperationException("origin and target must differ");

            JObject map = state["map"] as JObject
                ?? throw new InvalidOperationException("state.map is missing");
            JObject nodes = map["nodes"] as JObject
                ?? throw new InvalidOperationException("state.map.nodes is missing");
            JObject originNode = nodes[originNodeId] as JObject
                ?? throw new InvalidOperationException("origin node is missing");
            JObject targetNode = nodes[targetNodeId] as JObject
                ?? throw new InvalidOperationException("target node is missing");
            if (!HasEdge(map["edges"] as JArray, originNodeId, targetNodeId))
                throw new InvalidOperationException("target node is not adjacent");
            EncounterProjection encounter = ResolveEncounterProjection(
                state,
                nodes,
                targetNodeId);

            JArray pieceIds = command["pieceIds"] as JArray
                ?? throw new InvalidOperationException("command.pieceIds must be an array");
            if (pieceIds.Count == 0 || pieceIds.Count > MaximumUnitsPerSide)
                throw new InvalidOperationException("attacker count is outside the supported bound");
            int attackWidth = PositiveInt(targetNode["attackWidth"], "target.attackWidth", MaximumUnitsPerSide);
            if (pieceIds.Count > attackWidth)
                throw new InvalidOperationException("attacker count exceeds target attackWidth");

            JObject pieces = state["pieces"] as JObject
                ?? throw new InvalidOperationException("state.pieces is missing");
            HashSet<string> originMembership = ReadUniquePieceIds(
                originNode["pieceIds"] as JArray,
                "origin node pieceIds");
            JObject factions = state["factions"] as JObject
                ?? throw new InvalidOperationException("state.factions is missing");
            bool legacyRedBlueAuthority;
            WarlordScenarioAuthorityDefinition scenarioAuthority = ResolveScenarioAuthority(
                state,
                factions,
                out legacyRedBlueAuthority);
            if (legacyRedBlueAuthority)
            {
                if (attackerFaction != "red" && attackerFaction != "blue")
                    throw new InvalidOperationException("legacy Demo1 command faction must be red or blue");
            }
            else if (!scenarioAuthority.ContainsFaction(attackerFaction))
            {
                throw new InvalidOperationException(
                    "command faction is outside the trusted scenario authority");
            }
            PlayerAvatarProjectionAuthority playerAvatarAuthority =
                ResolveDemo2PlayerAvatarAuthority(
                    state,
                    pieces,
                    scenarioAuthority,
                    legacyRedBlueAuthority);
            JObject attackerFactionState = factions[attackerFaction] as JObject
                ?? throw new InvalidOperationException("attacker faction state is missing");
            int actionPoints = NonNegativeInt(attackerFactionState["actionPoints"], "attacker.actionPoints");

            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            JArray attackers = new JArray();
            foreach (JToken token in pieceIds)
            {
                string pieceId = token.Type == JTokenType.String ? token.Value<string>() : null;
                if (!PieceIdPattern.IsMatch(pieceId ?? "") || !seen.Add(pieceId))
                    throw new InvalidOperationException("attacker piece identity is invalid or duplicated");
                if (!originMembership.Contains(pieceId))
                    throw new InvalidOperationException("attacker is absent from origin node membership: " + pieceId);
                attackers.Add(ProjectParticipant(
                    state,
                    pieces,
                    pieceId,
                    attackerFaction,
                    originNodeId,
                    targetNodeId,
                    playerAvatarAuthority));
            }

            JArray targetPieceIds = targetNode["pieceIds"] as JArray
                ?? throw new InvalidOperationException("target node pieceIds is missing");
            List<string> defenderIds = new List<string>();
            HashSet<string> targetMembership = new HashSet<string>(StringComparer.Ordinal);
            string defenderFaction = null;
            foreach (JToken token in targetPieceIds)
            {
                string pieceId = token.Type == JTokenType.String ? token.Value<string>() : null;
                if (!PieceIdPattern.IsMatch(pieceId ?? "") || !targetMembership.Add(pieceId))
                    throw new InvalidOperationException("target piece identity is invalid or duplicated");
                JObject piece = pieces[pieceId] as JObject
                    ?? throw new InvalidOperationException("target piece is missing: " + pieceId);
                if (Number(piece["hp"], "piece.hp") <= 0) continue;
                string factionId = RequiredFactionId(
                    piece.Value<string>("factionId"),
                    "piece.factionId");
                if (factionId == attackerFaction)
                    throw new InvalidOperationException("target node contains mixed friendly and enemy units");
                if (defenderFaction == null) defenderFaction = factionId;
                else if (!string.Equals(defenderFaction, factionId, StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "target node living garrison contains multiple defender factions");
                }
                defenderIds.Add(pieceId);
            }
            defenderIds.Sort(StringComparer.Ordinal);
            if (defenderIds.Count == 0 || defenderIds.Count > MaximumUnitsPerSide)
                throw new InvalidOperationException("defender count is outside the supported bound");

            ValidateBattleRelationship(
                scenarioAuthority,
                legacyRedBlueAuthority,
                attackerFaction,
                defenderFaction);

            JArray defenders = new JArray();
            foreach (string pieceId in defenderIds)
                defenders.Add(ProjectParticipant(
                    state,
                    pieces,
                    pieceId,
                    defenderFaction,
                    targetNodeId,
                    null,
                    playerAvatarAuthority));

            string blueFormation = "wedge";
            string redFormation = "line";
            int attackerCommandLoad = pieceIds.Count;
            JProperty organizationProperty = state.Property("organization");
            if (organizationProperty != null)
            {
                JObject organization = organizationProperty.Value as JObject
                    ?? throw new InvalidOperationException("state.organization must be an object when present");
                ValidateOrganizationSidecar(state, organization);
                blueFormation = ResolveUniformSideFormation(
                    organization,
                    attackers,
                    attackerFaction,
                    originNodeId,
                    "attacker");
                redFormation = ResolveUniformSideFormation(
                    organization,
                    defenders,
                    defenderFaction,
                    targetNodeId,
                    "defender");
            }
            if (actionPoints < attackerCommandLoad)
                throw new InvalidOperationException(
                    "attacker action points are insufficient for selected members");

            string playerControlledSide = ResolvePlayerControlledSide(
                attackers, defenders);

            JObject authorityContext = new JObject
            {
                ["schema"] = "warlord.as2-authority-context.v1",
                ["sessionId"] = sessionId,
                ["requestId"] = requestId,
                ["inputDigest"] = digest,
                ["attackerFactionId"] = attackerFaction,
                ["defenderFactionId"] = defenderFaction,
                ["originNodeId"] = originNodeId,
                ["targetNodeId"] = targetNodeId,
                ["mapDefinitionId"] = StringOrNull(encounter.MapDefinitionId),
                ["strategicConfigDigest"] = StringOrNull(encounter.StrategicConfigDigest),
                ["encounterProjectionMode"] = encounter.Mode,
                ["encounterDefinitionId"] = StringOrNull(encounter.DefinitionId),
                ["encounterRulesVersion"] = StringOrNull(encounter.RulesVersion),
                ["encounterConfigDigest"] = StringOrNull(encounter.ConfigDigest),
                ["encounterProfileRef"] = StringOrNull(encounter.ProfileRef),
                ["encounterDistanceBand"] = encounter.DistanceBand,
                ["encounterSpawnDistance"] = encounter.SpawnDistance,
                ["economyMode"] = "observe_only",
                ["petProjectionProfile"] = "catalog_identifier+strategic_progression_v1",
                ["playerPetSnapshotUsed"] = false,
                ["participantProjectionProfile"] =
                    "discriminated_player_avatar+catalog_pet_v1",
                ["playerAvatarProjectionProfile"] =
                    "trusted_demo2_commander_v1",
                ["playerPersistentSnapshotUsed"] = false
            };

            string batchId = "warlord-" + digest.Substring("sha256:".Length, 40);
            JObject actionEncounterControl = new JObject
            {
                ["schema"] = "warlord.action-encounter-control.v2",
                ["battleId"] = batchId,
                ["blueRoster"] = ToActionEncounterRoster(attackers),
                ["redRoster"] = ToActionEncounterRoster(defenders),
                ["timeoutFrames"] = 3600,
                ["spawnDistance"] = encounter.SpawnDistance,
                ["blueFormation"] = blueFormation,
                ["redFormation"] = redFormation,
                ["formationSpacing"] = 54,
                ["playerControlledSide"] = playerControlledSide,
                ["authorityContext"] = authorityContext
            };

            return new PreparedBattle
            {
                PanelInstanceId = panelInstanceId,
                WebCallId = callId,
                SessionId = sessionId,
                OuterRunId = outerRunId,
                EncounterId = encounterId,
                RequestId = requestId,
                InputDigest = digest,
                FrozenRequest = (JObject)request.DeepClone(),
                FrozenState = (JObject)state.DeepClone(),
                Command = (JObject)command.DeepClone(),
                ClientContext = clientContext,
                Attackers = attackers,
                Defenders = defenders,
                ActionEncounterControl = actionEncounterControl,
                ActionDispatchClaimed = false
            };
        }

        private WarlordScenarioAuthorityDefinition ResolveScenarioAuthority(
            JObject state,
            JObject factions,
            out bool legacyRedBlueAuthority)
        {
            legacyRedBlueAuthority = false;
            if (IsImplicitLegacyDemo1Identity(state))
            {
                ValidateFactionStateSet(
                    factions,
                    new[] { "red", "blue" },
                    "legacy Demo1");
                legacyRedBlueAuthority = true;
                return null;
            }

            WarlordScenarioAuthorityDefinition authority;
            if (!_scenarioAuthorityCatalog.TryResolve(
                state.Value<string>("scenarioId"),
                state.Value<string>("rulesVersion"),
                state.Value<string>("mapDefinitionId"),
                state.Value<string>("configDigest"),
                out authority))
            {
                throw new InvalidOperationException(
                    "state strategic identity is not present in the trusted scenario authority catalog");
            }

            ValidateFactionStateSet(factions, authority.FactionIds, "trusted scenario");
            JProperty relationsProperty = state.Property("relations");
            if (relationsProperty == null)
            {
                if (IsExactDemo1Identity(state)
                    && authority.FactionIds.Count == 2
                    && authority.ContainsFaction("red")
                    && authority.ContainsFaction("blue"))
                {
                    legacyRedBlueAuthority = true;
                    return authority;
                }
                throw new InvalidOperationException(
                    "state.relations is required for a trusted N-faction scenario");
            }

            JObject relations = relationsProperty.Value as JObject
                ?? throw new InvalidOperationException("state.relations must be an object");
            ValidateRelationMatrix(relations, authority);
            return authority;
        }

        private static bool IsImplicitLegacyDemo1Identity(JObject state)
        {
            return state.Property("relations") == null
                && state.Property("scenarioId") == null
                && state.Property("mapDefinitionId") == null
                && state.Property("configDigest") == null
                && string.Equals(
                    state.Value<string>("rulesVersion"),
                    "wargame-demo-v0.1",
                    StringComparison.Ordinal);
        }

        private static bool IsExactDemo1Identity(JObject state)
        {
            return string.Equals(
                    state.Value<string>("scenarioId"),
                    Demo1ScenarioId,
                    StringComparison.Ordinal)
                && string.Equals(
                    state.Value<string>("rulesVersion"),
                    Demo1RulesVersion,
                    StringComparison.Ordinal)
                && string.Equals(
                    state.Value<string>("mapDefinitionId"),
                    Demo1MapDefinitionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    state.Value<string>("configDigest"),
                    Demo1StrategicConfigDigest,
                    StringComparison.Ordinal);
        }

        private static void ValidateFactionStateSet(
            JObject factions,
            IEnumerable<string> expectedFactionIds,
            string authorityName)
        {
            HashSet<string> expected = new HashSet<string>(
                expectedFactionIds,
                StringComparer.Ordinal);
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (JProperty property in factions.Properties())
            {
                string factionId = RequiredFactionId(
                    property.Name,
                    "state.factions factionId");
                if (!expected.Contains(factionId))
                {
                    throw new InvalidOperationException(
                        "state.factions contains a faction outside " + authorityName + ": " + factionId);
                }
                if (!(property.Value is JObject))
                {
                    throw new InvalidOperationException(
                        "state.factions entry must be an object: " + factionId);
                }
                seen.Add(factionId);
            }
            if (seen.Count != expected.Count)
                throw new InvalidOperationException("state.factions does not match " + authorityName);
            foreach (string factionId in expected)
            {
                if (!seen.Contains(factionId))
                    throw new InvalidOperationException("state.factions is missing faction: " + factionId);
            }
        }

        private static void ValidateRelationMatrix(
            JObject relations,
            WarlordScenarioAuthorityDefinition authority)
        {
            IReadOnlyList<string> factionIds = authority.FactionIds;
            if (CountProperties(relations) != factionIds.Count)
                throw new InvalidOperationException("state.relations row set is incomplete or contains an unknown faction");

            foreach (JProperty rowProperty in relations.Properties())
            {
                string rowFactionId = RequiredFactionId(
                    rowProperty.Name,
                    "state.relations row factionId");
                if (!authority.ContainsFaction(rowFactionId))
                    throw new InvalidOperationException("state.relations contains an unknown faction row");
                JObject row = rowProperty.Value as JObject
                    ?? throw new InvalidOperationException(
                        "state.relations row must be an object: " + rowFactionId);
                if (CountProperties(row) != factionIds.Count)
                {
                    throw new InvalidOperationException(
                        "state.relations row is incomplete or contains an unknown faction: " + rowFactionId);
                }
                foreach (JProperty valueProperty in row.Properties())
                {
                    string columnFactionId = RequiredFactionId(
                        valueProperty.Name,
                        "state.relations column factionId");
                    if (!authority.ContainsFaction(columnFactionId)
                        || valueProperty.Value.Type != JTokenType.String)
                    {
                        throw new InvalidOperationException(
                            "state.relations contains an invalid relation entry");
                    }
                }
            }

            for (int leftIndex = 0; leftIndex < factionIds.Count; leftIndex++)
            {
                string leftFactionId = factionIds[leftIndex];
                JObject leftRow = relations[leftFactionId] as JObject
                    ?? throw new InvalidOperationException(
                        "state.relations is missing faction row: " + leftFactionId);
                for (int rightIndex = leftIndex; rightIndex < factionIds.Count; rightIndex++)
                {
                    string rightFactionId = factionIds[rightIndex];
                    JObject rightRow = relations[rightFactionId] as JObject
                        ?? throw new InvalidOperationException(
                            "state.relations is missing faction row: " + rightFactionId);
                    JToken forwardToken = leftRow[rightFactionId];
                    JToken reverseToken = rightRow[leftFactionId];
                    if (forwardToken == null
                        || reverseToken == null
                        || forwardToken.Type != JTokenType.String
                        || reverseToken.Type != JTokenType.String)
                    {
                        throw new InvalidOperationException(
                            "state.relations must contain both directions for every faction pair");
                    }
                    string forward = forwardToken.Value<string>();
                    string reverse = reverseToken.Value<string>();
                    if (!string.Equals(forward, reverse, StringComparison.Ordinal))
                    {
                        throw new InvalidOperationException(
                            "state.relations must be symmetric for every faction pair");
                    }
                    string expected;
                    if (!authority.TryGetRelation(leftFactionId, rightFactionId, out expected)
                        || !string.Equals(forward, expected, StringComparison.Ordinal))
                    {
                        throw new InvalidOperationException(
                            "state.relations does not match the trusted scenario authority");
                    }
                }
            }
        }

        private static void ValidateBattleRelationship(
            WarlordScenarioAuthorityDefinition authority,
            bool legacyRedBlueAuthority,
            string attackerFaction,
            string defenderFaction)
        {
            if (legacyRedBlueAuthority)
            {
                string expectedDefender = attackerFaction == "red" ? "blue" : "red";
                if (!string.Equals(defenderFaction, expectedDefender, StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "legacy Demo1 defender must be the opposing red or blue faction");
                }
                return;
            }

            if (authority == null || !authority.ContainsFaction(defenderFaction))
            {
                throw new InvalidOperationException(
                    "target node defender is outside the trusted scenario authority");
            }
            string relation;
            if (!authority.TryGetRelation(attackerFaction, defenderFaction, out relation)
                || !string.Equals(relation, "hostile", StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "attacker and target defender must have a hostile trusted relation");
            }
        }

        private static int CountProperties(JObject value)
        {
            int count = 0;
            foreach (JProperty ignored in value.Properties()) count++;
            return count;
        }

        private static PlayerAvatarProjectionAuthority ResolveDemo2PlayerAvatarAuthority(
            JObject state,
            JObject pieces,
            WarlordScenarioAuthorityDefinition scenarioAuthority,
            bool legacyRedBlueAuthority)
        {
            if (legacyRedBlueAuthority
                || scenarioAuthority == null
                || !string.Equals(
                    scenarioAuthority.ScenarioId,
                    Demo2ScenarioId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    scenarioAuthority.MapDefinitionId,
                    Demo2MapDefinitionId,
                    StringComparison.Ordinal))
            {
                return null;
            }

            if (!string.Equals(
                state.Value<string>("playerFactionId"),
                Demo2PlayerFactionId,
                StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Demo2 playerFactionId does not match Host commander authority");
            }

            JProperty commandersProperty = state.Property("commanders");
            if (commandersProperty == null)
                return new PlayerAvatarProjectionAuthority(false, null);
            JObject commanders = commandersProperty.Value as JObject
                ?? throw new InvalidOperationException("state.commanders must be an object");
            JObject commander = commanders[Demo2PlayerCommanderId] as JObject
                ?? throw new InvalidOperationException(
                    "Demo2 trusted player commander is missing");
            RequireExactProperties(
                commander,
                "state.commanders[commander.player]",
                "commanderId",
                "characterId",
                "factionId",
                "role",
                "cardId",
                "status",
                "pieceInstanceId",
                "nodeId",
                "apContribution",
                "productionGoldCost",
                "productionRounds",
                "remainingProductionRounds",
                "readyFromRound");

            if (!string.Equals(
                    commander.Value<string>("commanderId"),
                    Demo2PlayerCommanderId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    commander.Value<string>("characterId"),
                    Demo2PlayerCharacterId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    commander.Value<string>("factionId"),
                    Demo2PlayerFactionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    commander.Value<string>("role"),
                    PlayerAvatarProjectionKind,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Demo2 player commander identity does not match Host authority");
            }
            if (PositiveInt(
                    commander["cardId"],
                    "player commander.cardId",
                    1000000) != Demo2PlayerCommanderCardId
                || PositiveInt(
                    commander["apContribution"],
                    "player commander.apContribution",
                    64) != 1
                || NonNegativeInt(
                    commander["productionGoldCost"],
                    "player commander.productionGoldCost") != 0
                || NonNegativeInt(
                    commander["productionRounds"],
                    "player commander.productionRounds") != 0
                || NonNegativeInt(
                    commander["remainingProductionRounds"],
                    "player commander.remainingProductionRounds") != 0)
            {
                throw new InvalidOperationException(
                    "Demo2 player commander economy profile does not match Host authority");
            }
            PositiveInt(
                commander["readyFromRound"],
                "player commander.readyFromRound",
                1000000);

            string status = commander.Value<string>("status") ?? "";
            string pieceId = commander.Value<string>("pieceInstanceId");
            JToken nodeToken = commander["nodeId"];
            if (string.Equals(status, "fielded", StringComparison.Ordinal))
            {
                if (commander["pieceInstanceId"] == null
                    || commander["pieceInstanceId"].Type != JTokenType.String
                    || !PieceIdPattern.IsMatch(pieceId ?? ""))
                    throw new InvalidOperationException(
                        "Demo2 fielded player commander piece binding is invalid");
                string nodeId = nodeToken != null && nodeToken.Type == JTokenType.String
                    ? nodeToken.Value<string>() : null;
                if (string.IsNullOrEmpty(nodeId) || nodeId.Length > 96 || HasControl(nodeId))
                    throw new InvalidOperationException(
                        "Demo2 fielded player commander node binding is invalid");
                JObject piece = pieces[pieceId] as JObject
                    ?? throw new InvalidOperationException(
                        "Demo2 fielded player commander piece is missing");
                if (!string.Equals(
                        piece.Value<string>("pieceId"),
                        pieceId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        piece.Value<string>("factionId"),
                        Demo2PlayerFactionId,
                        StringComparison.Ordinal)
                    || piece.Value<int?>("cardId") != Demo2PlayerCommanderCardId
                    || !string.Equals(
                        piece.Value<string>("nodeId"),
                        nodeId,
                        StringComparison.Ordinal)
                    || Number(piece["hp"], "player commander piece.hp") <= 0)
                {
                    throw new InvalidOperationException(
                        "Demo2 player commander piece binding does not match Host authority");
                }
            }
            else
            {
                if (!string.Equals(status, "downed", StringComparison.Ordinal)
                    && !string.Equals(status, "rear", StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "Demo2 player commander status is unsupported");
                }
                if ((commander["pieceInstanceId"] != null
                        && commander["pieceInstanceId"].Type != JTokenType.Null)
                    || (nodeToken != null && nodeToken.Type != JTokenType.Null))
                {
                    throw new InvalidOperationException(
                        "non-fielded Demo2 player commander must not retain a piece binding");
                }
                pieceId = null;
            }

            foreach (JProperty property in commanders.Properties())
            {
                if (string.Equals(
                    property.Name,
                    Demo2PlayerCommanderId,
                    StringComparison.Ordinal)) continue;
                JObject other = property.Value as JObject
                    ?? throw new InvalidOperationException(
                        "state.commanders entry must be an object: " + property.Name);
                if (string.Equals(
                        other.Value<string>("role"),
                        PlayerAvatarProjectionKind,
                        StringComparison.Ordinal)
                    || string.Equals(
                        other.Value<string>("characterId"),
                        Demo2PlayerCharacterId,
                        StringComparison.Ordinal)
                    || (!string.IsNullOrEmpty(pieceId)
                        && string.Equals(
                            other.Value<string>("pieceInstanceId"),
                            pieceId,
                            StringComparison.Ordinal)))
                {
                    throw new InvalidOperationException(
                        "Demo2 player commander identity or piece binding is aliased");
                }
            }
            return new PlayerAvatarProjectionAuthority(true, pieceId);
        }

        private static string ResolvePlayerControlledSide(
            JArray attackers, JArray defenders)
        {
            // 控制权属于实际参战的主角投影，不属于我方阵营。普通部队与
            // 敌指挥官交战时双方均由 AI 驱动，沿用 v2 的 none 旁观合同。
            string controlledSide = "none";
            JArray[] sides = { attackers, defenders };
            for (int side = 0; side < sides.Length; side++)
            {
                foreach (JObject participant in sides[side])
                {
                    if (participant.Value<string>("projectionKind") != "player_avatar")
                        continue;
                    if (controlledSide != "none")
                        throw new InvalidOperationException("encounter contains multiple player avatars");
                    controlledSide = side == 0 ? "blue" : "red";
                }
            }
            return controlledSide;
        }

        private static void RequireExactProperties(
            JObject value,
            string context,
            params string[] expectedNames)
        {
            HashSet<string> expected = new HashSet<string>(
                expectedNames,
                StringComparer.Ordinal);
            if (CountProperties(value) != expected.Count)
                throw new InvalidOperationException(context + " property set is invalid");
            foreach (JProperty property in value.Properties())
            {
                if (!expected.Contains(property.Name))
                    throw new InvalidOperationException(
                        context + " contains an unsupported field: " + property.Name);
            }
        }

        private JObject ProjectParticipant(
            JObject state,
            JObject pieces,
            string pieceId,
            string expectedFaction,
            string expectedNode,
            string forbiddenAssaultTarget,
            PlayerAvatarProjectionAuthority playerAvatarAuthority)
        {
            JObject piece = pieces[pieceId] as JObject
                ?? throw new InvalidOperationException("piece is missing: " + pieceId);
            string factionId = RequiredFactionId(
                piece.Value<string>("factionId"),
                "piece.factionId");
            if (factionId != expectedFaction)
                throw new InvalidOperationException("piece faction mismatch: " + pieceId);
            if (!string.Equals(piece.Value<string>("nodeId"), expectedNode, StringComparison.Ordinal))
                throw new InvalidOperationException("piece node mismatch: " + pieceId);
            if (piece.Property("projectionKind") != null
                || piece.Property("commanderId") != null
                || piece.Property("characterId") != null)
            {
                throw new InvalidOperationException(
                    "strategic piece may not declare encounter projection identity: " + pieceId);
            }
            JArray failedAssaultLocks = piece["failedAssaultLocks"] as JArray;
            if (failedAssaultLocks == null)
                throw new InvalidOperationException("piece.failedAssaultLocks must be an array: " + pieceId);
            foreach (JToken token in failedAssaultLocks)
            {
                string lockedNode = token.Type == JTokenType.String ? token.Value<string>() : null;
                if (lockedNode == null || lockedNode.Length == 0 || HasControl(lockedNode))
                    throw new InvalidOperationException("piece.failedAssaultLocks contains an invalid node id");
                if (forbiddenAssaultTarget != null
                    && string.Equals(lockedNode, forbiddenAssaultTarget, StringComparison.Ordinal))
                    throw new InvalidOperationException("piece cannot re-enter a failed assault: " + pieceId);
            }

            int cardId = PositiveInt(piece["cardId"], "piece.cardId", 1000000);

            double hp = Number(piece["hp"], "piece.hp");
            double maxHp = Number(piece["maxHp"], "piece.maxHp");
            if (hp <= 0 || maxHp <= 0 || hp > maxHp)
                throw new InvalidOperationException("piece hp projection is invalid: " + pieceId);
            int hpPermille = (int)Math.Round(hp * 1000.0 / maxHp, MidpointRounding.AwayFromZero);
            if (hpPermille < 1) hpPermille = 1;
            if (hpPermille > 1000) hpPermille = 1000;

            int strategicGoldValue = BoundedInt(
                piece["productionGoldValue"],
                "piece.productionGoldValue",
                0,
                1000000);
            bool isDemo2PlayerCommanderCard = playerAvatarAuthority != null
                && string.Equals(
                    factionId,
                    Demo2PlayerFactionId,
                    StringComparison.Ordinal)
                && cardId == Demo2PlayerCommanderCardId;
            if (isDemo2PlayerCommanderCard
                && !playerAvatarAuthority.CommanderSidecarPresent)
            {
                throw new InvalidOperationException(
                    "Demo2 player commander card requires the trusted commander sidecar");
            }
            if (playerAvatarAuthority != null
                && !string.IsNullOrEmpty(playerAvatarAuthority.PieceId)
                && string.Equals(
                    pieceId,
                    playerAvatarAuthority.PieceId,
                    StringComparison.Ordinal))
            {
                return new JObject
                {
                    ["pieceId"] = pieceId,
                    ["factionId"] = factionId,
                    ["projectionKind"] = PlayerAvatarProjectionKind,
                    ["commanderId"] = Demo2PlayerCommanderId,
                    ["characterId"] = Demo2PlayerCharacterId,
                    ["hpPermille"] = hpPermille,
                    ["strategicGoldValue"] = strategicGoldValue
                };
            }

            int petId = cardId;
            PetDef pet;
            if (!_petCatalog.PetsById.TryGetValue(petId, out pet))
                throw new InvalidOperationException("piece cardId does not resolve to pets.xml: " + petId);
            if (string.IsNullOrEmpty(pet.Identifier))
                throw new InvalidOperationException("pet identifier is empty: " + petId);

            JObject factions = state["factions"] as JObject;
            JObject faction = factions != null ? factions[factionId] as JObject : null;
            JObject cards = faction != null ? faction["cards"] as JObject : null;
            JObject card = cards != null ? cards[petId.ToString()] as JObject : null;
            int level = PositiveInt(card != null ? card["level"] : null, "card.level", 50);
            JArray strategicPromotions = NormalizeStrategicPromotions(
                card,
                pet,
                level,
                "card.purchasedPromotions");

            return new JObject
            {
                ["pieceId"] = pieceId,
                ["factionId"] = factionId,
                ["projectionKind"] = PetProjectionKind,
                ["petId"] = petId,
                ["identifier"] = pet.Identifier,
                ["rosterType"] = pet.RosterType,
                ["level"] = level,
                ["hpPermille"] = hpPermille,
                ["strategicPromotions"] = strategicPromotions,
                ["strategicGoldValue"] = strategicGoldValue,
                ["catalogName"] = pet.Name,
                ["basePrice"] = pet.Price,
                ["kPrice"] = pet.KPrice,
                ["increasePrice"] = pet.IncreasePrice
            };
        }

        private static JArray ToActionEncounterRoster(JArray participants)
        {
            JArray roster = new JArray();
            foreach (JObject participant in participants)
            {
                string projectionKind = participant.Value<string>("projectionKind");
                if (string.Equals(
                    projectionKind,
                    PlayerAvatarProjectionKind,
                    StringComparison.Ordinal))
                {
                    roster.Add(new JObject
                    {
                        ["projectionKind"] = PlayerAvatarProjectionKind,
                        ["sourceId"] = participant.Value<string>("pieceId"),
                        ["commanderId"] = participant.Value<string>("commanderId"),
                        ["characterId"] = participant.Value<string>("characterId"),
                        ["factionId"] = participant.Value<string>("factionId"),
                        ["hpPermille"] = participant.Value<int>("hpPermille")
                    });
                    continue;
                }
                if (!string.Equals(
                    projectionKind,
                    PetProjectionKind,
                    StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "participant projection kind is unsupported");
                }
                roster.Add(new JObject
                {
                    ["projectionKind"] = PetProjectionKind,
                    ["sourceId"] = participant.Value<string>("pieceId"),
                    ["petId"] = participant.Value<int>("petId"),
                    ["identifier"] = participant.Value<string>("identifier"),
                    ["rosterType"] = participant.Value<string>("rosterType"),
                    ["level"] = participant.Value<int>("level"),
                    ["hpPermille"] = participant.Value<int>("hpPermille"),
                    ["strategicPromotions"] = participant["strategicPromotions"].DeepClone()
                });
            }
            return roster;
        }

        private static JObject BuildActionEncounterBinding(PreparedBattle prepared)
        {
            return new JObject
            {
                ["schema"] = ActionEncounterBindingSchema,
                ["outerRunId"] = prepared.OuterRunId,
                ["encounterId"] = prepared.EncounterId,
                ["requestId"] = prepared.RequestId,
                ["inputDigest"] = prepared.InputDigest
            };
        }

        private static bool TryNormalizeActionEncounterBinding(
            JObject value,
            out JObject normalized)
        {
            normalized = null;
            if (value == null
                || CountProperties(value) != ActionEncounterBindingKeys.Length
                || !string.Equals(
                    value.Value<string>("schema"),
                    ActionEncounterBindingSchema,
                    StringComparison.Ordinal)
                || !OpaqueIdPattern.IsMatch(
                    value.Value<string>("outerRunId") ?? "")
                || !OpaqueIdPattern.IsMatch(
                    value.Value<string>("encounterId") ?? "")
                || !OpaqueIdPattern.IsMatch(
                    value.Value<string>("requestId") ?? "")
                || !CanonicalDigestPattern.IsMatch(
                    value.Value<string>("inputDigest") ?? ""))
            {
                return false;
            }
            foreach (JProperty property in value.Properties())
            {
                if (Array.IndexOf(
                        ActionEncounterBindingKeys,
                        property.Name) < 0) return false;
            }
            normalized = (JObject)value.DeepClone();
            return true;
        }

        private static bool TryNormalizeActionEncounterAdmission(
            JObject message,
            out JObject normalized)
        {
            normalized = null;
            if (message == null
                || CountProperties(message) != 2
                || !string.Equals(
                    message.Value<string>("task"),
                    "warlord_action_encounter_admitted",
                    StringComparison.Ordinal)
                || !(message["payload"] is JObject)) return false;

            JObject payload = (JObject)message["payload"];
            if (CountProperties(payload) != ActionEncounterAdmissionKeys.Length
                || !string.Equals(
                    payload.Value<string>("schema"),
                    ActionEncounterAdmissionSchema,
                    StringComparison.Ordinal)) return false;
            foreach (JProperty property in payload.Properties())
            {
                if (Array.IndexOf(
                        ActionEncounterAdmissionKeys,
                        property.Name) < 0) return false;
            }

            JObject binding;
            string disposition = payload.Value<string>("disposition") ?? "";
            string phase = payload.Value<string>("phase") ?? "";
            if (!TryNormalizeActionEncounterBinding(
                    payload["binding"] as JObject,
                    out binding)
                || !ActionAdmissionDispositions.Contains(disposition)
                || !ActionAdmissionPhases.Contains(phase)) return false;

            normalized = new JObject
            {
                ["schema"] = ActionEncounterAdmissionSchema,
                ["binding"] = binding,
                ["disposition"] = disposition,
                ["phase"] = phase
            };
            return true;
        }

        private static bool TryNormalizeActionEncounterCancellation(
            JObject message,
            out JObject normalized)
        {
            normalized = null;
            if (message == null
                || CountProperties(message) != 2
                || !string.Equals(
                    message.Value<string>("task"),
                    "warlord_action_encounter_cancelled",
                    StringComparison.Ordinal)
                || !(message["payload"] is JObject)) return false;

            JObject payload = (JObject)message["payload"];
            if (CountProperties(payload) != ActionEncounterCancellationKeys.Length
                || !string.Equals(
                    payload.Value<string>("schema"),
                    ActionEncounterCancellationSchema,
                    StringComparison.Ordinal)) return false;
            foreach (JProperty property in payload.Properties())
            {
                if (Array.IndexOf(
                        ActionEncounterCancellationKeys,
                        property.Name) < 0) return false;
            }

            JObject actionBinding;
            JObject stageOuterBinding;
            string rejection;
            string reasonCode = payload.Value<string>("reasonCode") ?? "";
            if (!TryNormalizeActionEncounterBinding(
                    payload["actionBinding"] as JObject,
                    out actionBinding)
                || !WarlordStageTask.TryNormalizeBinding(
                    payload["stageOuterBinding"] as JObject,
                    out stageOuterBinding,
                    out rejection)
                || !ActionCancellationReasons.Contains(reasonCode)
                || !string.Equals(
                    actionBinding.Value<string>("outerRunId"),
                    stageOuterBinding.Value<string>("runId"),
                    StringComparison.Ordinal)) return false;

            normalized = new JObject
            {
                ["schema"] = ActionEncounterCancellationSchema,
                ["actionBinding"] = actionBinding,
                ["stageOuterBinding"] = stageOuterBinding,
                ["reasonCode"] = reasonCode
            };
            return true;
        }

        private static bool TryNormalizeActionEncounterTerminal(
            JObject value,
            out JObject normalized)
        {
            normalized = null;
            if (value == null
                || CountProperties(value) != ActionEncounterTerminalKeys.Length
                || !string.Equals(
                    value.Value<string>("schema"),
                    ActionEncounterTerminalSchema,
                    StringComparison.Ordinal)
                || !OpaqueIdPattern.IsMatch(value.Value<string>("outerRunId") ?? "")
                || !OpaqueIdPattern.IsMatch(value.Value<string>("encounterId") ?? "")
                || !OpaqueIdPattern.IsMatch(value.Value<string>("requestId") ?? "")
                || !CanonicalDigestPattern.IsMatch(value.Value<string>("inputDigest") ?? "")
                || !OpaqueIdPattern.IsMatch(value.Value<string>("reasonCode") ?? ""))
            {
                return false;
            }
            foreach (JProperty property in value.Properties())
            {
                if (Array.IndexOf(ActionEncounterTerminalKeys, property.Name) < 0)
                    return false;
            }
            string status = value.Value<string>("status");
            JToken result = value["result"];
            if (status == "completed")
            {
                if (result == null || result.Type != JTokenType.Object) return false;
            }
            else if (status == "not_started")
            {
                if (result == null || result.Type != JTokenType.Null) return false;
            }
            else if (status == "unknown")
            {
                if (result == null || result.Type != JTokenType.Null) return false;
            }
            else
            {
                return false;
            }
            normalized = (JObject)value.DeepClone();
            return true;
        }

        private static bool SameActionEncounterIdentity(
            PreparedBattle prepared,
            JObject terminal)
        {
            return prepared != null && terminal != null
                && string.Equals(prepared.OuterRunId,
                    terminal.Value<string>("outerRunId"), StringComparison.Ordinal)
                && string.Equals(prepared.EncounterId,
                    terminal.Value<string>("encounterId"), StringComparison.Ordinal)
                && string.Equals(prepared.RequestId,
                    terminal.Value<string>("requestId"), StringComparison.Ordinal)
                && FixedTimeEquals(prepared.InputDigest,
                    terminal.Value<string>("inputDigest") ?? "");
        }

        private static bool SameActionEncounterBinding(
            JObject left,
            JObject right)
        {
            return left != null && right != null
                && string.Equals(
                    left.Value<string>("outerRunId"),
                    right.Value<string>("outerRunId"),
                    StringComparison.Ordinal)
                && string.Equals(
                    left.Value<string>("encounterId"),
                    right.Value<string>("encounterId"),
                    StringComparison.Ordinal)
                && string.Equals(
                    left.Value<string>("requestId"),
                    right.Value<string>("requestId"),
                    StringComparison.Ordinal)
                && FixedTimeEquals(
                    left.Value<string>("inputDigest") ?? "",
                    right.Value<string>("inputDigest") ?? "");
        }

        private bool DispatchActionEncounter(PreparedBattle prepared)
        {
            JObject command;
            int attempt;
            int? generation = null;
            lock (_lock)
            {
                if (prepared == null || !ReferenceEquals(_active, prepared)
                    || prepared.ActionEncounterBinding == null
                    || prepared.ActionEncounterControl == null
                    || !prepared.ActionDispatchClaimed
                    || prepared.ActionAdmissionReceived
                    || prepared.ParentRetired)
                {
                    return false;
                }
                if (_tryGetActionTransportGeneration != null
                    && _trySendActionEncounterIfGeneration != null)
                {
                    if (!prepared.ActionTransportGenerationCaptured)
                    {
                        int? readyGeneration = _tryGetActionTransportGeneration();
                        if (!readyGeneration.HasValue) return false;
                        prepared.ActionTransportGeneration = readyGeneration.Value;
                        prepared.ActionTransportGenerationCaptured = true;
                    }
                    generation = prepared.ActionTransportGeneration;
                }
                prepared.ActionDispatchAttempts++;
                attempt = prepared.ActionDispatchAttempts;
                command = new JObject
                {
                    ["task"] = "cmd",
                    ["action"] = "warlord_action_encounter_start",
                    ["binding"] = prepared.ActionEncounterBinding.DeepClone(),
                    ["encounter"] = prepared.ActionEncounterControl.DeepClone()
                };
            }
            try
            {
                string compact = command.ToString(Formatting.None);
                int byteCount = Encoding.UTF8.GetByteCount(compact) + 1;
                LogManager.Log(
                    "event=warlord_action_dispatch_attempt requestId="
                    + prepared.RequestId
                    + " encounterId=" + prepared.EncounterId
                    + " attempt=" + attempt.ToString(CultureInfo.InvariantCulture)
                    + " generation=" + (generation.HasValue
                        ? generation.Value.ToString(CultureInfo.InvariantCulture)
                        : "legacy")
                    + " bytes=" + byteCount.ToString(CultureInfo.InvariantCulture));
                bool sent = generation.HasValue
                    ? _trySendActionEncounterIfGeneration(command, generation.Value)
                    : _trySendActionEncounter(command);
                LogManager.Log(
                    "event=warlord_action_dispatch_return requestId="
                    + prepared.RequestId
                    + " attempt=" + attempt.ToString(CultureInfo.InvariantCulture)
                    + " sent=" + (sent ? "true" : "false"));
                return sent;
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[WarlordBattleTask] fresh Action dispatch failed: "
                    + ex.GetType().Name);
                return false;
            }
        }

        private void ScheduleActionAdmissionRetry(PreparedBattle prepared)
        {
            Exception schedulingError = null;
            lock (_lock)
            {
                if (prepared == null || !ReferenceEquals(_active, prepared)
                    || prepared.ActionAdmissionReceived
                    || prepared.ParentRetired
                    || !prepared.ActionTransportGenerationCaptured
                    || _scheduleActionAdmissionRetry == null) return;
                CancelActionAdmissionRetryLocked(prepared);
                try
                {
                    prepared.ActionAdmissionRetry = _scheduleActionAdmissionRetry(
                        delegate { OnActionAdmissionRetryDue(prepared); },
                        ActionAdmissionRetryDelayMilliseconds);
                }
                catch (Exception ex)
                {
                    // Scheduling is diagnostic/reliability infrastructure after the first
                    // generation-bound write.  Never let a Timer allocation failure escape
                    // the panel-close callback and tear down the Launcher UI thread.
                    schedulingError = ex;
                    prepared.ActionAdmissionRetry = null;
                }
            }
            if (schedulingError != null)
            {
                LogManager.Log(
                    "event=warlord_action_admission_retry_schedule_failed requestId="
                    + prepared.RequestId + " error="
                    + schedulingError.GetType().Name);
                FenceUnconfirmedActionTransport(
                    prepared,
                    "retry_schedule_failed");
            }
        }

        private void OnActionAdmissionRetryDue(PreparedBattle prepared)
        {
            bool exhausted;
            IDisposable fired = null;
            lock (_lock)
            {
                if (prepared != null)
                {
                    fired = prepared.ActionAdmissionRetry;
                    prepared.ActionAdmissionRetry = null;
                }
                if (prepared == null || !ReferenceEquals(_active, prepared)
                    || prepared.ActionAdmissionReceived
                    || prepared.ParentRetired
                    || !prepared.ActionTransportGenerationCaptured)
                {
                    DisposeBestEffort(fired);
                    return;
                }
                exhausted = prepared.ActionDispatchAttempts
                    >= MaximumActionDispatchAttempts;
            }
            DisposeBestEffort(fired);

            if (!exhausted)
            {
                DispatchActionEncounter(prepared);
                ScheduleActionAdmissionRetry(prepared);
                return;
            }

            FenceUnconfirmedActionTransport(prepared, "attempts_exhausted");
        }

        private void FenceUnconfirmedActionTransport(
            PreparedBattle prepared,
            string reason)
        {
            int generation;
            int attempts;
            lock (_lock)
            {
                if (prepared == null || !ReferenceEquals(_active, prepared)
                    || prepared.ActionAdmissionReceived
                    || prepared.ParentRetired
                    || !prepared.ActionTransportGenerationCaptured) return;
                generation = prepared.ActionTransportGeneration;
                attempts = prepared.ActionDispatchAttempts;
            }

            LogManager.Log(
                "event=warlord_action_admission_fence requestId="
                + prepared.RequestId
                + " encounterId=" + prepared.EncounterId
                + " generation=" + generation.ToString(CultureInfo.InvariantCulture)
                + " attempts=" + attempts.ToString(CultureInfo.InvariantCulture)
                + " reason=" + (reason ?? "unknown"));
            bool closed = false;
            try
            {
                closed = _forceCloseActionTransportIfGeneration != null
                    && _forceCloseActionTransportIfGeneration(generation);
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "event=warlord_action_admission_fence_failed generation="
                    + generation.ToString(CultureInfo.InvariantCulture)
                    + " error=" + ex.GetType().Name);
            }
            LogManager.Log(
                "event=warlord_action_admission_fence_result generation="
                + generation.ToString(CultureInfo.InvariantCulture)
                + " closed=" + (closed ? "true" : "false"));
        }

        private static void DisposeBestEffort(IDisposable disposable)
        {
            if (disposable == null) return;
            try { disposable.Dispose(); } catch { }
        }

        private static void CancelActionAdmissionRetryLocked(
            PreparedBattle prepared)
        {
            if (prepared == null || prepared.ActionAdmissionRetry == null) return;
            IDisposable pending = prepared.ActionAdmissionRetry;
            prepared.ActionAdmissionRetry = null;
            DisposeBestEffort(pending);
        }

        public string HandleActionEncounterAdmission(JObject message)
        {
            JObject admission;
            if (!TryNormalizeActionEncounterAdmission(message, out admission))
                return ActionAdmissionResponse(false, "invalid_admission", null);

            JObject binding = admission["binding"] as JObject;
            bool accepted = false;
            bool duplicate = false;
            lock (_lock)
            {
                if (_active != null
                    && _active.ActionDispatchClaimed
                    && SameActionEncounterIdentity(_active, binding))
                {
                    duplicate = _active.ActionAdmissionReceived;
                    _active.ActionAdmissionReceived = true;
                    CancelActionAdmissionRetryLocked(_active);
                    accepted = true;
                }
            }
            if (!accepted)
                return ActionAdmissionResponse(false, "stale_admission", null);

            LogManager.Log(
                "event=warlord_action_admitted requestId="
                + binding.Value<string>("requestId")
                + " encounterId=" + binding.Value<string>("encounterId")
                + " disposition=" + (duplicate ? "duplicate" : "accepted")
                + " as2Disposition=" + admission.Value<string>("disposition")
                + " phase=" + admission.Value<string>("phase"));
            return ActionAdmissionResponse(
                true,
                duplicate ? "duplicate" : "accepted",
                admission);
        }

        /// <summary>
        /// AS2 父 GameStage 已进入退出/重启后，以 action + outer 双 exact binding
        /// 吸收 Action correlation。outer owner 由独立的 outer cancellation task
        /// 退休；这里不生成战斗结果、不恢复 Web，也不裁决场景。
        /// </summary>
        public string HandleActionEncounterCancellation(JObject message)
        {
            JObject cancellation;
            if (!TryNormalizeActionEncounterCancellation(
                    message,
                    out cancellation))
            {
                return ActionCancellationResponse(
                    false, "invalid_cancellation", null);
            }
            JObject actionBinding =
                (JObject)cancellation["actionBinding"];
            JObject stageOuterBinding =
                (JObject)cancellation["stageOuterBinding"];
            bool duplicate = false;
            bool conflict = false;
            bool accepted = false;
            lock (_lock)
            {
                JObject previousAction = _lastCancellation != null
                    ? _lastCancellation["actionBinding"] as JObject
                    : null;
                if (previousAction != null
                    && SameActionEncounterBinding(
                        previousAction,
                        actionBinding))
                {
                    duplicate = JToken.DeepEquals(
                        _lastCancellation,
                        cancellation);
                    conflict = !duplicate;
                }
                else
                {
                    PreparedBattle candidate = null;
                    if (_active != null
                        && SameActionEncounterIdentity(
                            _active,
                            actionBinding)) candidate = _active;
                    else if (_lastCompleted != null
                        && SameActionEncounterIdentity(
                            _lastCompleted,
                            actionBinding)) candidate = _lastCompleted;

                    if (candidate != null)
                    {
                        if (candidate.StageOuterBinding == null
                            || !JToken.DeepEquals(
                                candidate.StageOuterBinding,
                                stageOuterBinding))
                        {
                            conflict = true;
                        }
                        else
                        {
                            candidate.ParentRetired = true;
                            CancelActionAdmissionRetryLocked(candidate);
                            if (ReferenceEquals(_active, candidate))
                                _active = null;
                            if (ReferenceEquals(_lastCompleted, candidate))
                                _lastCompleted = null;
                            _lastCancellation =
                                (JObject)cancellation.DeepClone();
                            accepted = true;
                        }
                    }
                }
            }

            if (conflict)
            {
                return ActionCancellationResponse(
                    false, "cancellation_conflict", null);
            }
            if (!accepted && !duplicate)
            {
                return ActionCancellationResponse(
                    false, "stale_cancellation", null);
            }

            LogManager.Log(
                "event=warlord_action_cancelled disposition="
                + (duplicate ? "duplicate" : "accepted"));
            return ActionCancellationResponse(
                true,
                duplicate ? "duplicate" : "cancelled",
                cancellation);
        }

        internal void HandleTransportDisconnected()
        {
            bool cleared = false;
            lock (_lock)
            {
                if (_active != null)
                {
                    _active.ParentRetired = true;
                    CancelActionAdmissionRetryLocked(_active);
                    _active = null;
                    cleared = true;
                }
                if (_lastCompleted != null)
                {
                    _lastCompleted.ParentRetired = true;
                    CancelActionAdmissionRetryLocked(_lastCompleted);
                    _lastCompleted = null;
                    cleared = true;
                }
                _lastCancellation = null;
            }
            if (cleared)
            {
                LogManager.Log(
                    "event=warlord_action_correlation_cleared reason=transport_disconnected");
            }
        }

        public string HandleActionEncounterTerminal(JObject message)
        {
            if (message == null
                || CountProperties(message) != 2
                || !string.Equals(
                    message.Value<string>("task"),
                    "warlord_action_encounter_terminal",
                    StringComparison.Ordinal)
                || !(message["payload"] is JObject))
            {
                return ActionTerminalResponse(false, "invalid_envelope", null);
            }

            JObject terminal;
            if (!TryNormalizeActionEncounterTerminal(
                    (JObject)message["payload"], out terminal))
            {
                return ActionTerminalResponse(false, "invalid_terminal", null);
            }

            PreparedBattle prepared = null;
            bool duplicate = false;
            bool conflict = false;
            bool cancelled = false;
            lock (_lock)
            {
                JObject cancelledBinding = _lastCancellation != null
                    ? _lastCancellation["actionBinding"] as JObject
                    : null;
                if (cancelledBinding != null
                    && SameActionEncounterBinding(
                        cancelledBinding,
                        terminal))
                {
                    cancelled = true;
                }
                else if (_active != null
                    && _active.ActionDispatchClaimed
                    && SameActionEncounterIdentity(_active, terminal))
                {
                    prepared = _active;
                    CancelActionAdmissionRetryLocked(prepared);
                    prepared.AcceptedActionTerminal = (JObject)terminal.DeepClone();
                    _active = null;
                    _lastCompleted = prepared;
                }
                else if (_active == null && _lastCompleted != null
                    && SameActionEncounterIdentity(_lastCompleted, terminal))
                {
                    prepared = _lastCompleted;
                    duplicate = JToken.DeepEquals(
                        prepared.AcceptedActionTerminal, terminal);
                    conflict = !duplicate;
                }
            }

            if (conflict)
                return ActionTerminalResponse(false, "terminal_conflict", null);
            if (cancelled)
                return ActionTerminalResponse(true, "cancelled", terminal);
            if (duplicate)
            {
                if (prepared.ResumeInitData != null)
                    OpenResume((JObject)prepared.ResumeInitData.DeepClone(), prepared);
                return ActionTerminalResponse(true, "duplicate", terminal);
            }
            if (prepared == null)
                return ActionTerminalResponse(false, "stale_terminal", null);

            string status = terminal.Value<string>("status");
            JObject resume;
            if (status == "not_started")
            {
                resume = BuildNotStartedResume(
                    prepared,
                    terminal.Value<string>("reasonCode")
                        ?? "action_encounter_not_started",
                    "fresh Action encounter did not start; strategic state was not consumed");
            }
            else if (status == "unknown")
            {
                resume = BuildUnknownResume(
                    prepared,
                    terminal.Value<string>("reasonCode")
                        ?? "action_encounter_unknown",
                    "Action encounter returned an unknown combat proof; strategic state was not consumed");
            }
            else
            {
                try
                {
                    resume = BuildResume(prepared, terminal);
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[WarlordBattleTask] Action proof validation failed: " + ex);
                    resume = BuildUnknownResume(prepared, "receipt_invalid", ex.Message);
                }
            }
            prepared.ResumeInitData = (JObject)resume.DeepClone();
            OpenResume(resume, prepared);
            return ActionTerminalResponse(true, status, terminal);
        }

        private JObject BuildResume(PreparedBattle prepared, JObject terminal)
        {
            JObject last = terminal != null ? terminal["result"] as JObject : null;
            if (last == null)
                throw new InvalidOperationException("Action encounter terminal has no battle result");
            string status = last.Value<string>("status") ?? "";
            if (status != "finished" && status != "timeout")
                return BuildUnknownResume(
                    prepared,
                    status.Length > 0 ? status : "as2_failed",
                    FirstError(last["errors"] as JArray));

            JObject authority = last["authorityContext"] as JObject;
            if (authority == null
                || authority.Value<string>("sessionId") != prepared.SessionId
                || authority.Value<string>("requestId") != prepared.RequestId
                || !FixedTimeEquals(authority.Value<string>("inputDigest") ?? "", prepared.InputDigest))
                throw new InvalidOperationException("AS2 authority context does not match the frozen request");
            ValidateFormationEcho(prepared, last);
            ValidateEncounterEcho(prepared, last);
            ValidatePlayerControlledSideEcho(prepared, last);

            JArray attackerResults = ValidateUnitResults(
                prepared.Attackers,
                last["blueUnitResults"] as JArray,
                "attacker");
            JArray defenderResults = ValidateUnitResults(
                prepared.Defenders,
                last["redUnitResults"] as JArray,
                "defender");
            string as2Winner = last.Value<string>("winner") ?? "none";
            bool validRawWinner = status == "finished"
                ? as2Winner == "blue" || as2Winner == "red" || as2Winner == "draw"
                : as2Winner == "timeout";
            if (!validRawWinner)
                throw new InvalidOperationException(
                    "AS2 raw winner fact is inconsistent with status: "
                    + status + "/" + as2Winner);
            JObject receipt = new JObject
            {
                ["schema"] = "warlord.as2-battle-receipt.v2",
                ["status"] = "accepted",
                ["sessionId"] = prepared.SessionId,
                ["requestId"] = prepared.RequestId,
                ["inputDigest"] = prepared.InputDigest,
                ["batchId"] = last.Value<string>("batchId") ?? "",
                ["manifestHash"] = last.Value<string>("manifestHash") ?? "",
                ["caseHash"] = last.Value<string>("caseHash") ?? "",
                ["as2Status"] = status,
                ["petProjectionProfile"] = "catalog_identifier+strategic_progression_v1",
                ["playerPetSnapshotUsed"] = false,
                ["participantProjectionProfile"] =
                    "discriminated_player_avatar+catalog_pet_v1",
                ["playerAvatarProjectionProfile"] =
                    "trusted_demo2_commander_v1",
                ["playerPersistentSnapshotUsed"] = false,
                ["playerControlledSide"] =
                    prepared.ActionEncounterControl.Value<string>("playerControlledSide"),
                ["as2Winner"] = as2Winner,
                ["sideMap"] = new JObject
                {
                    ["blue"] = "attacker",
                    ["red"] = "defender"
                },
                ["frames"] = NonNegativeWholeNumber(last["frames"], "last.frames"),
                ["durationMs"] = NonNegativeNumber(last["durationMs"], "last.durationMs"),
                ["attackerUnits"] = attackerResults,
                ["defenderUnits"] = defenderResults,
                ["economyObservation"] = BuildEconomyObservation(
                    prepared,
                    attackerResults,
                    defenderResults),
                ["errors"] = last["errors"] is JArray
                    ? last["errors"].DeepClone() : new JArray()
            };
            AddEncounterReceiptAudit(receipt, prepared, last);
            return BuildResumeEnvelope(prepared, receipt, null);
        }

        private EncounterProjection ResolveEncounterProjection(
            JObject state,
            JObject nodes,
            string targetNodeId)
        {
            JProperty encounterProperty = state.Property("encounter");
            if (encounterProperty == null)
            {
                WarlordScenarioAuthorityDefinition demo2Authority;
                if (TryResolveDemo2Authority(state, out demo2Authority))
                {
                    throw new InvalidOperationException(
                        "Demo2 requires the complete state.encounter sidecar");
                }
                foreach (JProperty nodeProperty in nodes.Properties())
                {
                    JObject node = nodeProperty.Value as JObject;
                    if (node != null && HasEncounterNodeField(node))
                    {
                        throw new InvalidOperationException(
                            "encounter node fields require the complete state.encounter sidecar");
                    }
                }
                return new EncounterProjection(
                    "legacy_v1_default",
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    "far",
                    650);
            }

            JObject encounter = encounterProperty.Value as JObject
                ?? throw new InvalidOperationException("state.encounter must be an object when present");
            int encounterFieldCount = 0;
            foreach (JProperty property in encounter.Properties())
            {
                encounterFieldCount++;
                if (property.Name != "definitionId"
                    && property.Name != "rulesVersion"
                    && property.Name != "configDigest")
                {
                    throw new InvalidOperationException(
                        "state.encounter contains an unsupported field: " + property.Name);
                }
            }
            if (encounterFieldCount != 3
                || !string.Equals(
                    encounter.Value<string>("definitionId"),
                    Demo1EncounterDefinitionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    encounter.Value<string>("rulesVersion"),
                    Demo1EncounterRulesVersion,
                    StringComparison.Ordinal)
                || !string.Equals(
                    encounter.Value<string>("configDigest"),
                    Demo1EncounterConfigDigest,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException("state.encounter identity is unsupported or incomplete");
            }

            if (IsExactDemo1Identity(state))
            {
                return ResolveDemo1EncounterProjection(
                    nodes,
                    targetNodeId);
            }

            WarlordScenarioAuthorityDefinition authority;
            if (!TryResolveDemo2Authority(state, out authority))
            {
                throw new InvalidOperationException(
                    "state strategic identity does not match a supported encounter contract");
            }

            EncounterNodeDefinition demo2Target;
            if (!Demo2EncounterNodes.TryGetValue(targetNodeId, out demo2Target))
            {
                throw new InvalidOperationException(
                    "target node has no supported Demo2 encounter profile");
            }
            JObject targetNode = nodes[targetNodeId] as JObject
                ?? throw new InvalidOperationException(
                    "Demo2 target encounter node must be an object: " + targetNodeId);
            ValidateEncounterNode(
                targetNode,
                targetNodeId,
                demo2Target,
                "Demo2 target node");

            return new EncounterProjection(
                "demo2_target_exact_v1",
                Demo2MapDefinitionId,
                authority.HasConfigDigestAuthority
                    ? authority.ConfigDigest
                    : null,
                Demo1EncounterDefinitionId,
                Demo1EncounterRulesVersion,
                Demo1EncounterConfigDigest,
                demo2Target.ProfileRef,
                demo2Target.DistanceBand,
                demo2Target.SpawnDistance);
        }

        private static EncounterProjection ResolveDemo1EncounterProjection(
            JObject nodes,
            string targetNodeId)
        {
            HashSet<string> seenNodeIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (JProperty nodeProperty in nodes.Properties())
            {
                EncounterNodeDefinition expected;
                if (!Demo1EncounterNodes.TryGetValue(nodeProperty.Name, out expected))
                    throw new InvalidOperationException("unsupported Demo1 encounter node: " + nodeProperty.Name);
                if (!seenNodeIds.Add(nodeProperty.Name))
                    throw new InvalidOperationException("duplicate Demo1 encounter node: " + nodeProperty.Name);

                JObject node = nodeProperty.Value as JObject
                    ?? throw new InvalidOperationException("Demo1 encounter node must be an object: " + nodeProperty.Name);
                ValidateEncounterNode(
                    node,
                    nodeProperty.Name,
                    expected,
                    "Demo1 encounter node");
            }
            if (seenNodeIds.Count != Demo1EncounterNodes.Count)
                throw new InvalidOperationException("Demo1 encounter node set is incomplete");

            EncounterNodeDefinition target;
            if (!Demo1EncounterNodes.TryGetValue(targetNodeId, out target))
                throw new InvalidOperationException("target node has no supported Demo1 encounter profile");
            return new EncounterProjection(
                "demo1_exact_v1",
                Demo1MapDefinitionId,
                Demo1StrategicConfigDigest,
                Demo1EncounterDefinitionId,
                Demo1EncounterRulesVersion,
                Demo1EncounterConfigDigest,
                target.ProfileRef,
                target.DistanceBand,
                target.SpawnDistance);
        }

        private bool TryResolveDemo2Authority(
            JObject state,
            out WarlordScenarioAuthorityDefinition authority)
        {
            authority = null;
            if (!string.Equals(
                    state.Value<string>("scenarioId"),
                    Demo2ScenarioId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    state.Value<string>("rulesVersion"),
                    Demo1RulesVersion,
                    StringComparison.Ordinal)
                || !string.Equals(
                    state.Value<string>("mapDefinitionId"),
                    Demo2MapDefinitionId,
                    StringComparison.Ordinal))
                return false;

            return _scenarioAuthorityCatalog.TryResolve(
                Demo2ScenarioId,
                Demo1RulesVersion,
                Demo2MapDefinitionId,
                state.Value<string>("configDigest"),
                out authority);
        }

        private static void ValidateEncounterNode(
            JObject node,
            string nodeId,
            EncounterNodeDefinition expected,
            string contractName)
        {
            int attackWidth = PositiveInt(
                node["attackWidth"],
                "state.map.nodes[" + nodeId + "].attackWidth",
                MaximumUnitsPerSide);
            int spawnDistance = PositiveInt(
                node["spawnDistance"],
                "state.map.nodes[" + nodeId + "].spawnDistance",
                750);
            if (!string.Equals(
                    node.Value<string>("kind"),
                    expected.Kind,
                    StringComparison.Ordinal)
                || attackWidth != expected.AttackWidth
                || !string.Equals(
                    node.Value<string>("encounterProfileRef"),
                    expected.ProfileRef,
                    StringComparison.Ordinal)
                || !string.Equals(
                    node.Value<string>("distanceBand"),
                    expected.DistanceBand,
                    StringComparison.Ordinal)
                || spawnDistance != expected.SpawnDistance)
            {
                throw new InvalidOperationException(
                    contractName
                    + " does not match its canonical profile: "
                    + nodeId);
            }
        }

        private static Dictionary<string, EncounterNodeDefinition>
            BuildDemo2EncounterNodes()
        {
            var nodes = new Dictionary<string, EncounterNodeDefinition>(
                StringComparer.Ordinal);
            string[] homeKeys =
            {
                "player", "pact-a", "independent", "pact-b"
            };
            string[] homeKinds =
            {
                "hq", "supply", "barracks", "economy", "command",
                "depot", "field", "field", "industry", "relay",
                "industry", "frontier", "frontier", "logistics"
            };
            foreach (string homeKey in homeKeys)
            {
                for (int ordinal = 1; ordinal <= homeKinds.Length; ordinal++)
                {
                    bool near = ordinal <= 3;
                    nodes[
                        "d2-" + homeKey + "-"
                        + ordinal.ToString("00", CultureInfo.InvariantCulture)] =
                        new EncounterNodeDefinition(
                            homeKinds[ordinal - 1],
                            ordinal == 1 ? 4 : 3,
                            near ? "encounter.near" : "encounter.medium",
                            near ? "near" : "medium",
                            near ? 180 : 360);
                }

                for (int ordinal = 1; ordinal <= 4; ordinal++)
                {
                    bool far = ordinal >= 3;
                    nodes[
                        "d2-arm-" + homeKey + "-"
                        + ordinal.ToString("00", CultureInfo.InvariantCulture)] =
                        new EncounterNodeDefinition(
                            far
                                ? "contested-industry"
                                : "contested-frontier",
                            far ? 4 : 3,
                            far ? "encounter.far" : "encounter.medium",
                            far ? "far" : "medium",
                            far ? 650 : 360);
                }
            }

            for (int ordinal = 1; ordinal <= 8; ordinal++)
            {
                bool far = ordinal % 2 == 1;
                nodes[
                    "d2-central-"
                    + ordinal.ToString("00", CultureInfo.InvariantCulture)] =
                    new EncounterNodeDefinition(
                        "central-industry",
                        4,
                        far ? "encounter.far" : "encounter.medium",
                        far ? "far" : "medium",
                        far ? 650 : 360);
            }
            if (nodes.Count != 80)
                throw new InvalidOperationException(
                    "Demo2 encounter target catalog must contain exactly 80 nodes");
            return nodes;
        }

        private static bool HasEncounterNodeField(JObject node)
        {
            return node.Property("encounterProfileRef") != null
                || node.Property("distanceBand") != null
                || node.Property("spawnDistance") != null;
        }

        private static void ValidateOrganizationSidecar(JObject state, JObject organization)
        {
            if (!string.Equals(
                    organization.Value<string>("definitionId"),
                    Demo1OrganizationDefinitionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    organization.Value<string>("rulesVersion"),
                    Demo1OrganizationRulesVersion,
                    StringComparison.Ordinal)
                || !string.Equals(
                    organization.Value<string>("configDigest"),
                    Demo1OrganizationConfigDigest,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException("state.organization definition identity is unsupported");
            }

            JObject commandElements = organization["commandElements"] as JObject
                ?? throw new InvalidOperationException("state.organization.commandElements must be an object");
            JObject memberToElement = organization["memberToElementId"] as JObject
                ?? throw new InvalidOperationException("state.organization.memberToElementId must be an object");
            JObject pieces = state["pieces"] as JObject
                ?? throw new InvalidOperationException("state.pieces is missing");
            HashSet<string> seenMembers = new HashSet<string>(StringComparer.Ordinal);

            foreach (JProperty elementProperty in commandElements.Properties())
            {
                string elementId = elementProperty.Name;
                if (elementId.Length == 0 || elementId.Length > 160 || HasControl(elementId))
                    throw new InvalidOperationException("organization command element identity is invalid");
                JObject element = elementProperty.Value as JObject
                    ?? throw new InvalidOperationException("organization command element must be an object: " + elementId);
                if (!string.Equals(element.Value<string>("elementId"), elementId, StringComparison.Ordinal))
                    throw new InvalidOperationException("organization command element key does not match elementId: " + elementId);

                string kind = element.Value<string>("kind") ?? "";
                if (kind != "singleton" && kind != "task_group")
                    throw new InvalidOperationException("organization command element kind is invalid: " + elementId);
                string factionId = RequiredFactionId(
                    element.Value<string>("factionId"),
                    "organization.commandElements[" + elementId + "].factionId");
                string nodeId = RequiredSafe(
                    element,
                    "nodeId",
                    96);
                string formation = element.Value<string>("formationProfileId") ?? "";
                if (!AllowedActionFormations.Contains(formation))
                    throw new InvalidOperationException("organization formationProfileId is unsupported: " + elementId);

                JArray memberIds = element["memberIds"] as JArray
                    ?? throw new InvalidOperationException("organization command element memberIds must be an array: " + elementId);
                HashSet<string> uniqueMembers = ReadUniquePieceIds(
                    memberIds,
                    "organization.commandElements[" + elementId + "].memberIds");
                if (uniqueMembers.Count == 0)
                    throw new InvalidOperationException("organization command element must contain a member: " + elementId);
                if (kind == "singleton" && uniqueMembers.Count != 1)
                    throw new InvalidOperationException("organization singleton must contain exactly one member: " + elementId);
                if (kind == "task_group")
                {
                    string templateId = element.Value<string>("taskGroupTemplateId") ?? "";
                    if (templateId.Length == 0 || templateId.Length > 160 || HasControl(templateId))
                        throw new InvalidOperationException("organization task group template is invalid: " + elementId);
                }

                foreach (string memberId in uniqueMembers)
                {
                    if (!seenMembers.Add(memberId))
                        throw new InvalidOperationException("organization member belongs to multiple command elements: " + memberId);
                    JToken reverseToken = memberToElement[memberId];
                    if (reverseToken == null
                        || reverseToken.Type != JTokenType.String
                        || !string.Equals(reverseToken.Value<string>(), elementId, StringComparison.Ordinal))
                    {
                        throw new InvalidOperationException("organization reverse index does not match command element: " + memberId);
                    }

                    JObject piece = pieces[memberId] as JObject
                        ?? throw new InvalidOperationException("organization member piece is missing: " + memberId);
                    if (Number(piece["hp"], "piece.hp") <= 0)
                        throw new InvalidOperationException("organization command element contains a non-living member: " + memberId);
                    if (!string.Equals(piece.Value<string>("factionId"), factionId, StringComparison.Ordinal)
                        || !string.Equals(piece.Value<string>("nodeId"), nodeId, StringComparison.Ordinal))
                    {
                        throw new InvalidOperationException("organization member faction or node diverges from command element: " + memberId);
                    }
                }
            }

            foreach (JProperty pieceProperty in pieces.Properties())
            {
                JObject piece = pieceProperty.Value as JObject
                    ?? throw new InvalidOperationException("state piece must be an object: " + pieceProperty.Name);
                if (Number(piece["hp"], "piece.hp") > 0 && !seenMembers.Contains(pieceProperty.Name))
                    throw new InvalidOperationException("living piece is absent from organization sidecar: " + pieceProperty.Name);
            }

            foreach (JProperty reverseProperty in memberToElement.Properties())
            {
                string memberId = reverseProperty.Name;
                if (!PieceIdPattern.IsMatch(memberId)
                    || reverseProperty.Value.Type != JTokenType.String)
                    throw new InvalidOperationException("organization reverse index contains an invalid identity");
                string elementId = reverseProperty.Value.Value<string>();
                JObject element = commandElements[elementId] as JObject;
                JObject piece = pieces[memberId] as JObject;
                JArray members = element != null ? element["memberIds"] as JArray : null;
                if (element == null || piece == null || members == null
                    || Number(piece["hp"], "piece.hp") <= 0
                    || !seenMembers.Contains(memberId)
                    || !ArrayContainsString(members, memberId))
                {
                    throw new InvalidOperationException("organization reverse index is dangling or not bidirectional: " + memberId);
                }
            }
        }

        private static string ResolveUniformSideFormation(
            JObject organization,
            JArray participants,
            string expectedFaction,
            string expectedNode,
            string sideName)
        {
            JObject commandElements = (JObject)organization["commandElements"];
            JObject memberToElement = (JObject)organization["memberToElementId"];
            HashSet<string> participantIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (JObject participant in participants)
            {
                string pieceId = participant != null ? participant.Value<string>("pieceId") : null;
                if (!PieceIdPattern.IsMatch(pieceId ?? "") || !participantIds.Add(pieceId))
                    throw new InvalidOperationException(sideName + " participant identity is invalid or duplicated");
            }

            HashSet<string> visitedElements = new HashSet<string>(StringComparer.Ordinal);
            string uniformFormation = null;
            foreach (string participantId in participantIds)
            {
                string elementId = memberToElement.Value<string>(participantId);
                JObject element = !string.IsNullOrEmpty(elementId)
                    ? commandElements[elementId] as JObject : null;
                if (element == null)
                    throw new InvalidOperationException(sideName + " participant has no active command element: " + participantId);
                if (!visitedElements.Add(elementId)) continue;
                if (!string.Equals(element.Value<string>("factionId"), expectedFaction, StringComparison.Ordinal)
                    || !string.Equals(element.Value<string>("nodeId"), expectedNode, StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(sideName + " command element faction or node does not match the battle");
                }

                JArray memberIds = (JArray)element["memberIds"];
                foreach (JToken memberToken in memberIds)
                {
                    string memberId = memberToken.Value<string>();
                    if (!participantIds.Contains(memberId))
                        throw new InvalidOperationException(sideName + " selection contains a partial command element: " + elementId);
                }

                string formation = element.Value<string>("formationProfileId") ?? "";
                if (!AllowedActionFormations.Contains(formation))
                    throw new InvalidOperationException(sideName + " formation is unsupported: " + formation);
                if (uniformFormation == null) uniformFormation = formation;
                else if (!string.Equals(uniformFormation, formation, StringComparison.Ordinal))
                    throw new InvalidOperationException(sideName + " command elements must use one uniform formation");
            }

            if (uniformFormation == null)
                throw new InvalidOperationException(sideName + " has no formation projection");
            return uniformFormation;
        }

        private static void ValidateFormationEcho(PreparedBattle prepared, JObject last)
        {
            JObject control = prepared != null
                ? prepared.ActionEncounterControl : null;
            if (control == null)
                throw new InvalidOperationException("prepared Action encounter control is missing");
            string expectedBlue = control.Value<string>("blueFormation") ?? "";
            string expectedRed = control.Value<string>("redFormation") ?? "";
            int expectedSpacing = NonNegativeWholeNumber(
                control["formationSpacing"],
                "actionEncounterControl.formationSpacing");
            string actualBlue = last["blueFormation"] != null
                && last["blueFormation"].Type == JTokenType.String
                ? last.Value<string>("blueFormation") : "";
            string actualRed = last["redFormation"] != null
                && last["redFormation"].Type == JTokenType.String
                ? last.Value<string>("redFormation") : "";
            int actualSpacing = NonNegativeWholeNumber(
                last["formationSpacing"],
                "last.formationSpacing");
            if (!string.Equals(actualBlue, expectedBlue, StringComparison.Ordinal)
                || !string.Equals(actualRed, expectedRed, StringComparison.Ordinal)
                || actualSpacing != expectedSpacing)
            {
                throw new InvalidOperationException("AS2 formation echo does not match the prepared Action encounter control");
            }
        }

        private static void ValidateEncounterEcho(PreparedBattle prepared, JObject last)
        {
            JObject control = prepared != null
                ? prepared.ActionEncounterControl : null;
            JObject expectedAuthority = control != null
                ? control["authorityContext"] as JObject : null;
            JObject actualAuthority = last != null
                ? last["authorityContext"] as JObject : null;
            if (control == null || expectedAuthority == null || actualAuthority == null)
                throw new InvalidOperationException("prepared encounter authority context is missing");

            string[] auditFields =
            {
                "mapDefinitionId",
                "strategicConfigDigest",
                "encounterProjectionMode",
                "encounterDefinitionId",
                "encounterRulesVersion",
                "encounterConfigDigest",
                "encounterProfileRef",
                "encounterDistanceBand",
                "encounterSpawnDistance"
            };
            foreach (string field in auditFields)
            {
                if (!JToken.DeepEquals(expectedAuthority[field], actualAuthority[field]))
                {
                    throw new InvalidOperationException(
                        "AS2 encounter authority echo does not match the frozen request: " + field);
                }
            }

            int expectedDistance = NonNegativeWholeNumber(
                control["spawnDistance"],
                "actionEncounterControl.spawnDistance");
            int requestedDistance = NonNegativeWholeNumber(
                last["requestedSpawnDistance"],
                "last.requestedSpawnDistance");
            int actualDistance = NonNegativeWholeNumber(
                last["spawnDistance"],
                "last.spawnDistance");
            if (expectedDistance <= 0
                || requestedDistance != expectedDistance
                || actualDistance != expectedDistance)
            {
                throw new InvalidOperationException(
                    "AS2 spawnDistance echo does not match the prepared encounter profile");
            }
        }

        private static void ValidatePlayerControlledSideEcho(
            PreparedBattle prepared,
            JObject last)
        {
            JObject control = prepared != null
                ? prepared.ActionEncounterControl : null;
            string expected = control != null
                ? control.Value<string>("playerControlledSide") : null;
            string actual = last != null
                ? last.Value<string>("playerControlledSide") : null;
            if ((expected != "blue" && expected != "red" && expected != "none")
                || !string.Equals(expected, actual, StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "AS2 playerControlledSide echo does not match the frozen request");
            }
        }

        private static void AddEncounterReceiptAudit(
            JObject receipt,
            PreparedBattle prepared,
            JObject last)
        {
            JObject control = prepared != null
                ? prepared.ActionEncounterControl : null;
            JObject authority = control != null
                ? control["authorityContext"] as JObject : null;
            if (receipt == null || control == null || authority == null)
                throw new InvalidOperationException("prepared encounter audit is missing");

            string[] auditFields =
            {
                "mapDefinitionId",
                "strategicConfigDigest",
                "encounterProjectionMode",
                "encounterDefinitionId",
                "encounterRulesVersion",
                "encounterConfigDigest",
                "encounterProfileRef",
                "encounterDistanceBand",
                "encounterSpawnDistance"
            };
            foreach (string field in auditFields)
            {
                JToken value = authority[field];
                receipt[field] = value != null ? value.DeepClone() : JValue.CreateNull();
            }
            receipt["requestedSpawnDistance"] = NonNegativeWholeNumber(
                control["spawnDistance"],
                "actionEncounterControl.spawnDistance");
            if (last != null)
            {
                receipt["spawnDistance"] = NonNegativeWholeNumber(
                    last["spawnDistance"],
                    "last.spawnDistance");
            }
        }

        private static bool ArrayContainsString(JArray values, string expected)
        {
            foreach (JToken value in values)
            {
                if (value.Type == JTokenType.String
                    && string.Equals(value.Value<string>(), expected, StringComparison.Ordinal)) return true;
            }
            return false;
        }

        private static JArray ValidateUnitResults(
            JArray participants,
            JArray results,
            string side)
        {
            if (results == null || results.Count != participants.Count)
                throw new InvalidOperationException(side + " unit result count mismatch");
            Dictionary<string, JObject> byId = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (JObject result in results)
            {
                string sourceId = result != null ? result.Value<string>("sourceId") : null;
                if (!PieceIdPattern.IsMatch(sourceId ?? "") || byId.ContainsKey(sourceId))
                    throw new InvalidOperationException(side + " unit result identity is invalid or duplicated");
                byId[sourceId] = result;
            }

            JArray normalized = new JArray();
            foreach (JObject participant in participants)
            {
                string pieceId = participant.Value<string>("pieceId");
                JObject source;
                if (!byId.TryGetValue(pieceId, out source))
                    throw new InvalidOperationException(side + " result is missing piece " + pieceId);
                string projectionKind = participant.Value<string>("projectionKind");
                if (!string.Equals(
                    source.Value<string>("projectionKind"),
                    projectionKind,
                    StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        side + " projection kind changed for " + pieceId);
                }

                int runtimeLevel = 0;
                if (string.Equals(
                    projectionKind,
                    PetProjectionKind,
                    StringComparison.Ordinal))
                {
                    RequireExactProperties(
                        source,
                        side + " pet result",
                        "projectionKind",
                        "sourceId",
                        "petId",
                        "identifier",
                        "resolvedType",
                        "level",
                        "strategicPromotions",
                        "strategicPromotionsValid",
                        "startMaxHp",
                        "remainHp",
                        "hpPermille",
                        "alive");
                    if (source.Property("commanderId") != null
                        || source.Property("characterId") != null
                        || source.Property("runtimeLevel") != null
                        || source.Value<int?>("petId") != participant.Value<int>("petId")
                        || source.Value<string>("identifier") != participant.Value<string>("identifier")
                        || source.Value<string>("resolvedType") != participant.Value<string>("identifier")
                        || source.Value<int?>("level") != participant.Value<int>("level"))
                    {
                        throw new InvalidOperationException(
                            side + " pet identity changed for " + pieceId);
                    }
                    JArray sourcePromotions = source["strategicPromotions"] as JArray;
                    if (source.Value<bool?>("strategicPromotionsValid") != true
                        || !JToken.DeepEquals(
                            sourcePromotions,
                            participant["strategicPromotions"] as JArray))
                    {
                        throw new InvalidOperationException(
                            side + " strategic promotion projection changed for " + pieceId);
                    }
                }
                else if (string.Equals(
                    projectionKind,
                    PlayerAvatarProjectionKind,
                    StringComparison.Ordinal))
                {
                    RequireExactProperties(
                        source,
                        side + " player avatar result",
                        "projectionKind",
                        "sourceId",
                        "commanderId",
                        "characterId",
                        "factionId",
                        "runtimeLevel",
                        "startMaxHp",
                        "remainHp",
                        "hpPermille",
                        "alive");
                    if (source.Property("petId") != null
                        || source.Property("identifier") != null
                        || source.Property("level") != null
                        || source.Property("strategicPromotions") != null
                        || source.Property("strategicPromotionsValid") != null
                        || !string.Equals(
                            source.Value<string>("commanderId"),
                            participant.Value<string>("commanderId"),
                            StringComparison.Ordinal)
                        || !string.Equals(
                            source.Value<string>("characterId"),
                            participant.Value<string>("characterId"),
                            StringComparison.Ordinal)
                        || !string.Equals(
                            source.Value<string>("factionId"),
                            participant.Value<string>("factionId"),
                            StringComparison.Ordinal))
                    {
                        throw new InvalidOperationException(
                            side + " player avatar identity changed for " + pieceId);
                    }
                    runtimeLevel = PositiveInt(
                        source["runtimeLevel"],
                        side + ".runtimeLevel",
                        9999);
                }
                else
                {
                    throw new InvalidOperationException(
                        side + " participant projection kind is unsupported");
                }

                int hpPermille = BoundedInt(
                    source["hpPermille"],
                    side + ".hpPermille",
                    0,
                    1000);
                bool alive = source.Value<bool?>("alive") == true;
                if (alive != (hpPermille > 0))
                    throw new InvalidOperationException(side + " alive/hpPermille mismatch for " + pieceId);
                double startMaxHp = NonNegativeNumber(
                    source["startMaxHp"],
                    side + ".startMaxHp");
                double remainHp = NonNegativeNumber(
                    source["remainHp"],
                    side + ".remainHp");
                if (startMaxHp <= 0 || remainHp > startMaxHp || alive != (remainHp > 0))
                    throw new InvalidOperationException(side + " hp totals are inconsistent for " + pieceId);
                int expectedPermille = remainHp > 0
                    ? Math.Max(1, (int)Math.Round(
                        remainHp * 1000.0 / startMaxHp,
                        MidpointRounding.AwayFromZero))
                    : 0;
                if (expectedPermille > 1000) expectedPermille = 1000;
                if (hpPermille != expectedPermille)
                    throw new InvalidOperationException(side + " hp ratio is inconsistent for " + pieceId);
                JObject normalizedUnit = new JObject
                {
                    ["pieceId"] = pieceId,
                    ["factionId"] = participant.Value<string>("factionId"),
                    ["projectionKind"] = projectionKind,
                    ["hpPermille"] = hpPermille,
                    ["alive"] = alive,
                    ["startMaxHp"] = startMaxHp,
                    ["remainHp"] = remainHp
                };
                if (string.Equals(
                    projectionKind,
                    PlayerAvatarProjectionKind,
                    StringComparison.Ordinal))
                {
                    normalizedUnit["commanderId"] =
                        participant.Value<string>("commanderId");
                    normalizedUnit["characterId"] =
                        participant.Value<string>("characterId");
                    normalizedUnit["runtimeLevel"] = runtimeLevel;
                }
                else
                {
                    normalizedUnit["petId"] = participant.Value<int>("petId");
                    normalizedUnit["identifier"] =
                        participant.Value<string>("identifier");
                    normalizedUnit["level"] = participant.Value<int>("level");
                    normalizedUnit["strategicPromotions"] =
                        participant["strategicPromotions"].DeepClone();
                    normalizedUnit["resolvedType"] =
                        source.Value<string>("resolvedType") ?? "";
                }
                normalized.Add(normalizedUnit);
            }
            return normalized;
        }

        private static JObject BuildEconomyObservation(
            PreparedBattle prepared,
            JArray attackerResults,
            JArray defenderResults)
        {
            return new JObject
            {
                ["schema"] = "warlord.pet-economy-observation.v1",
                ["mode"] = "observe_only",
                ["writesPlayerState"] = false,
                ["settlementPolicy"] = "none",
                ["catalogAuthority"] = "data/merc/pets.xml",
                ["catalogPriceBasis"] = "xml_base_price",
                ["currentAs2SessionPriceSampled"] = false,
                ["strategicValueBasis"] = "piece.productionGoldValue",
                ["catalogCurrencyUnit"] = "player_gold",
                ["strategicCurrencyUnit"] = "warlord_gold",
                ["attacker"] = BuildEconomySide(prepared.Attackers, attackerResults),
                ["defender"] = BuildEconomySide(prepared.Defenders, defenderResults)
            };
        }

        private static JObject BuildEconomySide(JArray participants, JArray results)
        {
            Dictionary<string, JObject> resultById = new Dictionary<string, JObject>(StringComparer.Ordinal);
            foreach (JObject result in results)
                resultById[result.Value<string>("pieceId")] = result;
            long catalogBaseExposureGold = 0;
            long catalogBaseLostGold = 0;
            long catalogBaseExposureK = 0;
            long catalogBaseLostK = 0;
            long strategicExposureGold = 0;
            long strategicLostGold = 0;
            JArray units = new JArray();
            foreach (JObject participant in participants)
            {
                string pieceId = participant.Value<string>("pieceId");
                JObject result = resultById[pieceId];
                int strategicGoldValue = participant.Value<int>("strategicGoldValue");
                bool lost = result.Value<bool?>("alive") != true;
                strategicExposureGold += strategicGoldValue;
                if (lost)
                {
                    strategicLostGold += strategicGoldValue;
                }
                string projectionKind = participant.Value<string>("projectionKind");
                if (string.Equals(
                    projectionKind,
                    PlayerAvatarProjectionKind,
                    StringComparison.Ordinal))
                {
                    units.Add(new JObject
                    {
                        ["pieceId"] = pieceId,
                        ["projectionKind"] = PlayerAvatarProjectionKind,
                        ["commanderId"] = participant.Value<string>("commanderId"),
                        ["characterId"] = participant.Value<string>("characterId"),
                        ["catalogEligible"] = false,
                        ["strategicGoldValue"] = strategicGoldValue,
                        ["lost"] = lost,
                        ["hpPermille"] = result.Value<int>("hpPermille")
                    });
                    continue;
                }

                int price = participant.Value<int>("basePrice");
                int kPrice = participant.Value<int>("kPrice");
                catalogBaseExposureGold += price;
                catalogBaseExposureK += kPrice;
                if (lost)
                {
                    catalogBaseLostGold += price;
                    catalogBaseLostK += kPrice;
                }
                units.Add(new JObject
                {
                    ["pieceId"] = pieceId,
                    ["projectionKind"] = PetProjectionKind,
                    ["petId"] = participant.Value<int>("petId"),
                    ["identifier"] = participant.Value<string>("identifier"),
                    ["catalogName"] = participant.Value<string>("catalogName"),
                    ["rosterType"] = participant.Value<string>("rosterType"),
                    ["strategicPromotions"] = participant["strategicPromotions"].DeepClone(),
                    ["catalogEligible"] = true,
                    ["strategicGoldValue"] = strategicGoldValue,
                    ["basePrice"] = price,
                    ["kPrice"] = kPrice,
                    ["increasePrice"] = participant.Value<int>("increasePrice"),
                    ["lost"] = lost,
                    ["hpPermille"] = result.Value<int>("hpPermille")
                });
            }
            return new JObject
            {
                ["catalogBaseExposureGold"] = catalogBaseExposureGold,
                ["catalogBaseLostGold"] = catalogBaseLostGold,
                ["catalogBaseExposureK"] = catalogBaseExposureK,
                ["catalogBaseLostK"] = catalogBaseLostK,
                ["strategicExposureGold"] = strategicExposureGold,
                ["strategicLostGold"] = strategicLostGold,
                ["units"] = units
            };
        }

        private JObject BuildUnknownResume(
            PreparedBattle prepared,
            string code,
            string message)
        {
            JObject receipt = new JObject
            {
                ["schema"] = "warlord.as2-battle-receipt.v2",
                ["status"] = "unknown",
                ["sessionId"] = prepared.SessionId,
                ["requestId"] = prepared.RequestId,
                ["inputDigest"] = prepared.InputDigest,
                ["error"] = code ?? "unknown",
                ["message"] = message ?? "AS2 battle result is unknown",
                ["economyObservation"] = new JObject
                {
                    ["schema"] = "warlord.pet-economy-observation.v1",
                    ["mode"] = "observe_only",
                    ["writesPlayerState"] = false,
                    ["settlementPolicy"] = "none",
                    ["status"] = "not_settled"
                }
            };
            AddEncounterReceiptAudit(receipt, prepared, null);
            return BuildResumeEnvelope(prepared, receipt, code);
        }

        private JObject BuildNotStartedResume(
            PreparedBattle prepared,
            string code,
            string message)
        {
            JObject receipt = new JObject
            {
                ["schema"] = "warlord.as2-battle-receipt.v2",
                ["status"] = "not_started",
                ["sessionId"] = prepared.SessionId,
                ["requestId"] = prepared.RequestId,
                ["inputDigest"] = prepared.InputDigest,
                ["error"] = code ?? "not_started",
                ["message"] = message ?? "AS2 battle was not dispatched",
                ["economyObservation"] = new JObject
                {
                    ["schema"] = "warlord.pet-economy-observation.v1",
                    ["mode"] = "observe_only",
                    ["writesPlayerState"] = false,
                    ["settlementPolicy"] = "none",
                    ["status"] = "not_settled"
                }
            };
            AddEncounterReceiptAudit(receipt, prepared, null);
            return BuildResumeEnvelope(prepared, receipt, code);
        }

        private static JObject BuildResumeEnvelope(
            PreparedBattle prepared,
            JObject receipt,
            string handoffError)
        {
            JObject resume = new JObject
            {
                ["schema"] = "warlord.as2-resume.v1",
                ["request"] = prepared.FrozenRequest.DeepClone(),
                ["state"] = prepared.FrozenState.DeepClone(),
                ["command"] = prepared.Command.DeepClone(),
                ["inputDigest"] = prepared.InputDigest,
                ["receipt"] = receipt,
                ["clientContext"] = prepared.ClientContext.DeepClone()
            };
            if (prepared.PlayerAvatarPortrait != null)
            {
                resume["playerAvatarPortrait"] =
                    prepared.PlayerAvatarPortrait.DeepClone();
            }
            if (prepared.StageOuterBinding != null)
            {
                resume["stageOuterBinding"] = prepared.StageOuterBinding.DeepClone();
                resume["stageResumeFromPanelInstanceId"] = prepared.PanelInstanceId;
            }
            if (!string.IsNullOrEmpty(handoffError)) resume["handoffError"] = handoffError;

            JObject init = (JObject)prepared.ClientContext.DeepClone();
            init["mode"] = "phase-c-as2";
            init["source"] = "as2_battle_resume";
            init["productionWrites"] = false;
            init["battleAuthority"] = "as2";
            init["as2BattleSession"] = true;
            if (prepared.PlayerAvatarPortrait != null)
            {
                init["playerAvatarPortrait"] =
                    prepared.PlayerAvatarPortrait.DeepClone();
            }
            if (prepared.StageOuterBinding != null)
            {
                init["stageOuterBinding"] = prepared.StageOuterBinding.DeepClone();
                init["stageResumeFromPanelInstanceId"] = prepared.PanelInstanceId;
                init["mode"] = "stage-v1";
                init["source"] = "game_stage";
            }
            init["resume"] = resume;
            return init;
        }

        private void OpenResume(JObject initData, PreparedBattle prepared = null)
        {
            Action open = delegate
            {
                if (prepared != null && IsParentRetired(prepared))
                {
                    LogManager.Log(
                        "event=warlord_resume_suppressed reason=parent_retired");
                    return;
                }
                Action<JObject, PreparedBattle> preparedHandler =
                    _openResumePanelWithPrepared;
                if (preparedHandler != null)
                {
                    try
                    {
                        preparedHandler(initData, prepared);
                    }
                    catch (Exception ex)
                    {
                        LogManager.Log(
                            "event=warlord_resume_dispatch_failed reason=prepared_handler_exception exception="
                            + ex.GetType().Name);
                    }
                    return;
                }
                Action<JObject> handler = _openResumePanel;
                if (handler == null)
                {
                    LogManager.Log(
                        "event=warlord_resume_dispatch_failed reason=handler_unavailable");
                    return;
                }
                try
                {
                    handler(initData);
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "event=warlord_resume_dispatch_failed reason=handler_exception exception="
                        + ex.GetType().Name);
                }
            };
            Action<Action> invoker = _invokeOnUI;
            if (invoker != null)
            {
                try
                {
                    invoker(open);
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "event=warlord_resume_dispatch_failed reason=invoker_exception exception="
                        + ex.GetType().Name);
                }
            }
            else open();
        }

        private bool IsParentRetired(PreparedBattle prepared)
        {
            lock (_lock)
            {
                return prepared != null && prepared.ParentRetired;
            }
        }

        private static JObject NormalizeClientContext(JObject input)
        {
            input = input ?? new JObject();
            string seed = input.Value<string>("seed") ?? "warlord-demo-seed-001";
            if (seed.Length == 0 || seed.Length > 160 || HasControl(seed))
                throw new InvalidOperationException("clientContext.seed is invalid");
            string preset = input.Value<string>("preset") ?? "standard";
            if (!AllowedPresets.Contains(preset))
                throw new InvalidOperationException("clientContext.preset is invalid");
            string difficulty = input.Value<string>("difficulty") ?? "normal";
            if (!AllowedDifficulties.Contains(difficulty))
                throw new InvalidOperationException("clientContext.difficulty is invalid");
            string mapTheme = input.Value<string>("mapTheme") == "tundra" ? "tundra" : "desert";
            JArray transitions = new JArray();
            JArray sourceTransitions = input["aiSeenTransitions"] as JArray;
            if (sourceTransitions != null)
            {
                if (sourceTransitions.Count > 256)
                    throw new InvalidOperationException("clientContext.aiSeenTransitions is too large");
                foreach (JToken token in sourceTransitions)
                {
                    string transition = token.Type == JTokenType.String ? token.Value<string>() : null;
                    if (transition == null || transition.Length > 256 || HasControl(transition))
                        throw new InvalidOperationException("clientContext.aiSeenTransitions contains an invalid entry");
                    transitions.Add(transition);
                }
            }
            return new JObject
            {
                ["seed"] = seed,
                ["preset"] = preset,
                ["difficulty"] = difficulty,
                ["mapTheme"] = mapTheme,
                ["forceWebglFailure"] = input.Value<bool?>("forceWebglFailure") == true,
                ["aiSeenTransitions"] = transitions
            };
        }

        private static bool HasEdge(JArray edges, string a, string b)
        {
            if (edges == null) return false;
            foreach (JObject edge in edges)
            {
                if (edge == null) continue;
                string left = edge.Value<string>("a");
                string right = edge.Value<string>("b");
                if ((left == a && right == b) || (left == b && right == a)) return true;
            }
            return false;
        }

        private static HashSet<string> ReadUniquePieceIds(JArray input, string fieldName)
        {
            if (input == null)
                throw new InvalidOperationException(fieldName + " must be an array");
            HashSet<string> output = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in input)
            {
                string pieceId = token.Type == JTokenType.String ? token.Value<string>() : null;
                if (!PieceIdPattern.IsMatch(pieceId ?? "") || !output.Add(pieceId))
                    throw new InvalidOperationException(fieldName + " contains an invalid or duplicate identity");
            }
            return output;
        }

        private static JArray NormalizeStrategicPromotions(
            JObject card,
            PetDef pet,
            int level,
            string fieldName)
        {
            JArray purchased = card != null ? card["purchasedPromotions"] as JArray : null;
            if (purchased == null)
                throw new InvalidOperationException(fieldName + " must be an array");

            List<string> expected = new List<string>();
            for (int i = 0; i < pet.Promotions.Count; i++)
            {
                string name = pet.Promotions[i] ?? "";
                if (StrategicPromotionNames.Contains(name)) expected.Add(name);
            }
            if (purchased.Count > expected.Count)
                throw new InvalidOperationException(fieldName + " exceeds the pets.xml strategic progression chain");

            JArray normalized = new JArray();
            for (int i = 0; i < purchased.Count; i++)
            {
                string name = purchased[i].Type == JTokenType.String
                    ? purchased[i].Value<string>() : null;
                if (name == null || !StrategicPromotionNames.Contains(name)
                    || !string.Equals(name, expected[i], StringComparison.Ordinal))
                    throw new InvalidOperationException(fieldName + " is not a valid pets.xml progression prefix");
                if (level < StrategicPromotionLevels[name])
                    throw new InvalidOperationException(
                        fieldName + " contains a promotion above the frozen card level");
                normalized.Add(name);
            }
            return normalized;
        }

        private static string FirstError(JArray errors)
        {
            JObject first = errors != null && errors.Count > 0 ? errors[0] as JObject : null;
            return first != null
                ? first.Value<string>("message") ?? first.Value<string>("code") ?? "AS2 battle failed"
                : "AS2 battle failed";
        }

        private static string ActionTerminalResponse(
            bool success,
            string disposition,
            JObject receipt)
        {
            return new JObject
            {
                ["success"] = success,
                ["disposition"] = disposition ?? "unknown",
                ["receipt"] = receipt == null
                    ? JValue.CreateNull()
                    : receipt.DeepClone()
            }.ToString(Formatting.None);
        }

        private static string ActionAdmissionResponse(
            bool success,
            string disposition,
            JObject admission)
        {
            return new JObject
            {
                ["success"] = success,
                ["disposition"] = disposition ?? "unknown",
                ["admission"] = admission == null
                    ? JValue.CreateNull()
                    : admission.DeepClone()
            }.ToString(Formatting.None);
        }

        private static string ActionCancellationResponse(
            bool success,
            string disposition,
            JObject cancellation)
        {
            return new JObject
            {
                ["success"] = success,
                ["disposition"] = disposition ?? "unknown",
                ["cancellation"] = cancellation == null
                    ? JValue.CreateNull()
                    : cancellation.DeepClone()
            }.ToString(Formatting.None);
        }

        private static JObject SuccessEnvelope(PreparedBattle prepared, string note)
        {
            return new JObject
            {
                ["success"] = true,
                ["ok"] = true,
                ["type"] = "panel_resp",
                ["panel"] = "warlord",
                ["cmd"] = "battle_start",
                ["callId"] = prepared.WebCallId,
                ["requestId"] = prepared.RequestId,
                ["inputDigest"] = prepared.InputDigest,
                ["note"] = note
            };
        }

        private static JObject Error(JObject envelope, string code, string message)
        {
            return new JObject
            {
                ["success"] = false,
                ["ok"] = false,
                ["type"] = "panel_resp",
                ["panel"] = "warlord",
                ["cmd"] = "battle_start",
                ["callId"] = envelope != null ? envelope.Value<string>("callId") ?? "" : "",
                ["error"] = code,
                ["message"] = message
            };
        }

        private static JObject ErrorForPrepared(PreparedBattle prepared, string code, string message)
        {
            return Error(new JObject { ["callId"] = prepared != null ? prepared.WebCallId : "" }, code, message);
        }

        private static string RequiredOpaque(JObject source, string fieldName)
        {
            string value = source.Value<string>(fieldName) ?? "";
            if (!OpaqueIdPattern.IsMatch(value))
                throw new InvalidOperationException(fieldName + " is invalid");
            return value;
        }

        private static string RequiredSafe(JObject source, string fieldName, int maximumLength)
        {
            string value = source.Value<string>(fieldName) ?? "";
            if (value.Length == 0 || value.Length > maximumLength || HasControl(value))
                throw new InvalidOperationException(fieldName + " is invalid");
            return value;
        }

        private static string RequiredFactionId(string value, string fieldName)
        {
            if (!OpaqueIdPattern.IsMatch(value ?? ""))
                throw new InvalidOperationException(fieldName + " is invalid");
            return value;
        }

        private static JToken StringOrNull(string value)
        {
            return value != null ? (JToken)new JValue(value) : JValue.CreateNull();
        }

        private static bool HasControl(string value)
        {
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i])) return true;
            return false;
        }

        private static int PositiveInt(JToken token, string fieldName, int maximum)
        {
            int value;
            if (!TryReadInteger(token, out value)
                || value <= 0 || value > maximum)
                throw new InvalidOperationException(fieldName + " must be a positive integer");
            return value;
        }

        private static int NonNegativeInt(JToken token, string fieldName)
        {
            int value;
            if (!TryReadInteger(token, out value) || value < 0)
                throw new InvalidOperationException(fieldName + " must be a non-negative integer");
            return value;
        }

        private static int NonNegativeWholeNumber(JToken token, string fieldName)
        {
            double value;
            if (!TryReadNumber(token, out value)
                || double.IsNaN(value)
                || double.IsInfinity(value)
                || value < 0
                || value > int.MaxValue
                || Math.Truncate(value) != value)
            {
                throw new InvalidOperationException(
                    fieldName + " must be a non-negative whole number");
            }
            return (int)value;
        }

        private static int BoundedInt(JToken token, string fieldName, int minimum, int maximum)
        {
            int value;
            if (!TryReadInteger(token, out value)
                || value < minimum || value > maximum)
                throw new InvalidOperationException(fieldName + " is outside the allowed range");
            return value;
        }

        private static double Number(JToken token, string fieldName)
        {
            double value;
            if (!TryReadNumber(token, out value)
                || double.IsNaN(value) || double.IsInfinity(value))
                throw new InvalidOperationException(fieldName + " must be a finite number");
            return value;
        }

        private static double NonNegativeNumber(JToken token, string fieldName)
        {
            double value;
            if (!TryReadNumber(token, out value)
                || double.IsNaN(value) || double.IsInfinity(value) || value < 0)
                throw new InvalidOperationException(fieldName + " must be a non-negative finite number");
            return value;
        }

        private static bool TryReadInteger(JToken token, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long raw;
            if (!long.TryParse(
                token.ToString(Formatting.None),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out raw)
                || raw < int.MinValue || raw > int.MaxValue) return false;
            value = (int)raw;
            return true;
        }

        private static bool TryReadNumber(JToken token, out double value)
        {
            value = 0;
            if (token == null
                || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float)) return false;
            return double.TryParse(
                token.ToString(Formatting.None),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out value);
        }

        internal static string Sha256OfToken(JToken token)
        {
            string canonicalJson = Canonicalize(token).ToString(Formatting.None);
            byte[] bytes = Encoding.UTF8.GetBytes(canonicalJson);
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(bytes);
                StringBuilder builder = new StringBuilder("sha256:");
                foreach (byte value in hash) builder.Append(value.ToString("x2"));
                return builder.ToString();
            }
        }

        internal static JToken Canonicalize(JToken token)
        {
            if (token is JObject)
            {
                JObject source = (JObject)token;
                List<JProperty> properties = new List<JProperty>(source.Properties());
                properties.Sort(delegate(JProperty a, JProperty b)
                {
                    return string.CompareOrdinal(a.Name, b.Name);
                });
                JObject result = new JObject();
                foreach (JProperty property in properties)
                    result[property.Name] = Canonicalize(property.Value);
                return result;
            }
            if (token is JArray)
            {
                JArray result = new JArray();
                foreach (JToken item in (JArray)token) result.Add(Canonicalize(item));
                return result;
            }
            return token.DeepClone();
        }

        private static bool FixedTimeEquals(string left, string right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            int diff = 0;
            for (int i = 0; i < left.Length; i++) diff |= left[i] ^ right[i];
            return diff == 0;
        }
    }
}
