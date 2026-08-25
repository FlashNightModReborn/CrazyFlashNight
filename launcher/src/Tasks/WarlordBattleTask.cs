using System;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Data;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 军阀战术演习 Web 战略态到 AS2 真实战斗的单次 handoff 协调器。
    ///
    /// Web 只提交冻结的战略快照与 MOVE_OR_ATTACK 意图。Host 复验 exact owner、
    /// canonical digest、棋子/节点/战宠目录身份后，自行投影 ArenaCalibration roster；
    /// AS2 回执只描述隔离战斗结果，本类不写玩家战宠、经验、货币或存档。
    /// </summary>
    public sealed class WarlordBattleTask
    {
        internal sealed class PreparedBattle
        {
            public string PanelInstanceId;
            public string WebCallId;
            public string SessionId;
            public string RequestId;
            public string InputDigest;
            public JObject FrozenRequest;
            public JObject FrozenState;
            public JObject Command;
            public JObject ClientContext;
            public JArray Attackers;
            public JArray Defenders;
            public JObject CalibrationControl;
            public string LifecycleState;
        }

        private const int MaximumRequestBytes = 512 * 1024;
        private const int MaximumUnitsPerSide = 64;
        private static readonly Regex OpaqueIdPattern =
            new Regex("^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$", RegexOptions.Compiled);
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

        private readonly ArenaCalibrationTask _calibrationTask;
        private readonly PetCatalog _petCatalog;
        private readonly object _lock = new object();
        private Action<JObject> _openResumePanel;
        private Action<Action> _invokeOnUI;
        private PreparedBattle _active;
        private bool _returnBasePending;

        public WarlordBattleTask(ArenaCalibrationTask calibrationTask, string projectRoot)
            : this(calibrationTask, PetCatalogLoader.Load(projectRoot))
        {
        }

        internal WarlordBattleTask(
            ArenaCalibrationTask calibrationTask,
            PetCatalog petCatalog)
        {
            _calibrationTask = calibrationTask
                ?? throw new ArgumentNullException(nameof(calibrationTask));
            _petCatalog = petCatalog
                ?? throw new ArgumentNullException(nameof(petCatalog));
        }

        public void SetResumeOpenHandler(Action<JObject> handler)
        {
            _openResumePanel = handler;
        }

        public void SetInvoker(Action<Action> invoker)
        {
            _invokeOnUI = invoker;
        }

        public bool HasActiveBattle
        {
            get { lock (_lock) return _active != null; }
        }

        public bool ConsumeReturnBaseOnFinalClose()
        {
            lock (_lock)
            {
                if (_active != null) return false;
                bool pending = _returnBasePending;
                _returnBasePending = false;
                return pending;
            }
        }

        internal JObject Prepare(
            JObject envelope,
            string activePanelInstanceId,
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

                PreparedBattle candidate = NormalizeRequest(
                    request,
                    activePanelInstanceId,
                    callId,
                    digest);
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
                    || _active.LifecycleState != "prepared") return false;
                _active = null;
            }
            LogManager.Log("[WarlordBattleTask] prepared handoff cancelled: " + (reason ?? "unknown"));
            return true;
        }

        internal bool CancelAndResume(PreparedBattle prepared, string code, string message)
        {
            if (!CancelPrepared(prepared, code)) return false;
            OpenResume(BuildNotStartedResume(prepared, code, message));
            return true;
        }

        internal JObject StartPrepared(PreparedBattle prepared)
        {
            lock (_lock)
            {
                if (_active == null || !ReferenceEquals(_active, prepared)
                    || _active.LifecycleState != "prepared")
                    return ErrorForPrepared(prepared, "handoff_expired", "prepared handoff is no longer current");
                _active.LifecycleState = "starting";
            }

            Action startWorker;
            JObject started = _calibrationTask.StartSingleDeferred(
                prepared.CalibrationControl,
                null,
                delegate(JObject terminal) { OnCalibrationCompleted(prepared, terminal); },
                out startWorker);
            if (started.Value<bool?>("success") != true || startWorker == null)
            {
                lock (_lock)
                {
                    if (ReferenceEquals(_active, prepared)) _active = null;
                }
                JObject resume = BuildNotStartedResume(
                    prepared,
                    started.Value<string>("error") ?? "calibration_start_failed",
                    started.Value<string>("message") ?? "AS2 calibration did not start");
                OpenResume(resume);
                return started;
            }

            lock (_lock)
            {
                if (ReferenceEquals(_active, prepared)) _active.LifecycleState = "running";
            }
            startWorker();
            return SuccessEnvelope(prepared, "started");
        }

        private PreparedBattle NormalizeRequest(
            JObject request,
            string panelInstanceId,
            string callId,
            string digest)
        {
            if (!string.Equals(
                request.Value<string>("schema"),
                "warlord.as2-battle-request.v1",
                StringComparison.Ordinal))
                throw new InvalidOperationException("unsupported warlord battle request schema");

            string sessionId = RequiredOpaque(request, "sessionId");
            string requestId = RequiredOpaque(request, "requestId");
            JObject state = request["state"] as JObject
                ?? throw new InvalidOperationException("state must be an object");
            JObject command = request["command"] as JObject
                ?? throw new InvalidOperationException("command must be an object");
            JObject clientContext = NormalizeClientContext(request["clientContext"] as JObject);

            if (state.Value<int?>("schemaVersion") != 1)
                throw new InvalidOperationException("unsupported strategic state schemaVersion");
            if (!string.Equals(command.Value<string>("type"), "MOVE_OR_ATTACK", StringComparison.Ordinal))
                throw new InvalidOperationException("only MOVE_OR_ATTACK may enter AS2 battle authority");

            string attackerFaction = RequiredFaction(command.Value<string>("factionId"), "command.factionId");
            string defenderFaction = attackerFaction == "red" ? "blue" : "red";
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
            JObject attackerFactionState = factions[attackerFaction] as JObject
                ?? throw new InvalidOperationException("attacker faction state is missing");
            int actionPoints = NonNegativeInt(attackerFactionState["actionPoints"], "attacker.actionPoints");
            if (actionPoints < pieceIds.Count)
                throw new InvalidOperationException("attacker action points are insufficient");

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
                    targetNodeId));
            }

            JArray targetPieceIds = targetNode["pieceIds"] as JArray
                ?? throw new InvalidOperationException("target node pieceIds is missing");
            List<string> defenderIds = new List<string>();
            HashSet<string> targetMembership = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in targetPieceIds)
            {
                string pieceId = token.Type == JTokenType.String ? token.Value<string>() : null;
                if (!PieceIdPattern.IsMatch(pieceId ?? "") || !targetMembership.Add(pieceId))
                    throw new InvalidOperationException("target piece identity is invalid or duplicated");
                JObject piece = pieces[pieceId] as JObject;
                if (piece == null || Number(piece["hp"], "piece.hp") <= 0) continue;
                string factionId = RequiredFaction(piece.Value<string>("factionId"), "piece.factionId");
                if (factionId == attackerFaction)
                    throw new InvalidOperationException("target node contains mixed friendly and enemy units");
                if (factionId != defenderFaction)
                    throw new InvalidOperationException("target node contains an unknown faction");
                defenderIds.Add(pieceId);
            }
            defenderIds.Sort(StringComparer.Ordinal);
            if (defenderIds.Count == 0 || defenderIds.Count > MaximumUnitsPerSide)
                throw new InvalidOperationException("defender count is outside the supported bound");

            JArray defenders = new JArray();
            foreach (string pieceId in defenderIds)
                defenders.Add(ProjectParticipant(
                    state,
                    pieces,
                    pieceId,
                    defenderFaction,
                    targetNodeId,
                    null));

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
                ["economyMode"] = "observe_only",
                ["petProjectionProfile"] = "catalog_identifier+strategic_progression_v1",
                ["playerPetSnapshotUsed"] = false
            };

            string batchId = "warlord-" + digest.Substring("sha256:".Length, 40);
            JObject calibrationCase = new JObject
            {
                ["caseId"] = "warlord-battle",
                ["blueRoster"] = ToCalibrationRoster(attackers),
                ["redRoster"] = ToCalibrationRoster(defenders),
                ["repeat"] = 1,
                ["timeoutFrames"] = 3600,
                ["spawnDistance"] = 650,
                ["blueFormation"] = "wedge",
                ["redFormation"] = "line",
                ["formationSpacing"] = 54,
                ["authorityContext"] = authorityContext
            };
            JObject calibrationControl = new JObject
            {
                ["batchId"] = batchId,
                ["createdAt"] = DateTime.UtcNow.ToString("o"),
                ["buildCommit"] = "warlord-as2-battle-v1",
                ["calibrationCase"] = calibrationCase
            };

            return new PreparedBattle
            {
                PanelInstanceId = panelInstanceId,
                WebCallId = callId,
                SessionId = sessionId,
                RequestId = requestId,
                InputDigest = digest,
                FrozenRequest = (JObject)request.DeepClone(),
                FrozenState = (JObject)state.DeepClone(),
                Command = (JObject)command.DeepClone(),
                ClientContext = clientContext,
                Attackers = attackers,
                Defenders = defenders,
                CalibrationControl = calibrationControl,
                LifecycleState = "prepared"
            };
        }

        private JObject ProjectParticipant(
            JObject state,
            JObject pieces,
            string pieceId,
            string expectedFaction,
            string expectedNode,
            string forbiddenAssaultTarget)
        {
            JObject piece = pieces[pieceId] as JObject
                ?? throw new InvalidOperationException("piece is missing: " + pieceId);
            string factionId = RequiredFaction(piece.Value<string>("factionId"), "piece.factionId");
            if (factionId != expectedFaction)
                throw new InvalidOperationException("piece faction mismatch: " + pieceId);
            if (!string.Equals(piece.Value<string>("nodeId"), expectedNode, StringComparison.Ordinal))
                throw new InvalidOperationException("piece node mismatch: " + pieceId);
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

            int petId = PositiveInt(piece["cardId"], "piece.cardId", 1000000);
            PetDef pet;
            if (!_petCatalog.PetsById.TryGetValue(petId, out pet))
                throw new InvalidOperationException("piece cardId does not resolve to pets.xml: " + petId);
            if (string.IsNullOrEmpty(pet.Identifier))
                throw new InvalidOperationException("pet identifier is empty: " + petId);

            double hp = Number(piece["hp"], "piece.hp");
            double maxHp = Number(piece["maxHp"], "piece.maxHp");
            if (hp <= 0 || maxHp <= 0 || hp > maxHp)
                throw new InvalidOperationException("piece hp projection is invalid: " + pieceId);
            int hpPermille = (int)Math.Round(hp * 1000.0 / maxHp, MidpointRounding.AwayFromZero);
            if (hpPermille < 1) hpPermille = 1;
            if (hpPermille > 1000) hpPermille = 1000;

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
            int strategicGoldValue = BoundedInt(
                piece["productionGoldValue"],
                "piece.productionGoldValue",
                0,
                1000000);

            return new JObject
            {
                ["pieceId"] = pieceId,
                ["factionId"] = factionId,
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

        private static JArray ToCalibrationRoster(JArray participants)
        {
            JArray roster = new JArray();
            foreach (JObject participant in participants)
            {
                roster.Add(new JObject
                {
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

        private void OnCalibrationCompleted(PreparedBattle prepared, JObject terminal)
        {
            bool owns;
            lock (_lock)
            {
                owns = ReferenceEquals(_active, prepared);
                if (owns)
                {
                    _active = null;
                    _returnBasePending = true;
                }
            }
            if (!owns)
            {
                LogManager.Log("[WarlordBattleTask] ignored terminal callback for stale request "
                    + prepared.RequestId);
                return;
            }

            JObject resume;
            try
            {
                resume = BuildResume(prepared, terminal);
            }
            catch (Exception ex)
            {
                LogManager.Log("[WarlordBattleTask] receipt validation failed: " + ex);
                resume = BuildUnknownResume(prepared, "receipt_invalid", ex.Message);
            }
            OpenResume(resume);
        }

        private JObject BuildResume(PreparedBattle prepared, JObject terminal)
        {
            JObject last = terminal != null ? terminal["lastResult"] as JObject : null;
            if (last == null)
                throw new InvalidOperationException("calibration terminal status has no lastResult");
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

            JArray attackerResults = ValidateUnitResults(
                prepared.Attackers,
                last["blueUnitResults"] as JArray,
                "attacker");
            JArray defenderResults = ValidateUnitResults(
                prepared.Defenders,
                last["redUnitResults"] as JArray,
                "defender");
            string as2Winner = last.Value<string>("winner") ?? "none";
            string winner;
            string reason;
            bool attackersDead = AllDead(attackerResults);
            bool defendersDead = AllDead(defenderResults);
            if (attackersDead && defendersDead)
            {
                winner = "defender";
                reason = "mutual_wipe";
            }
            else if (status == "timeout")
            {
                winner = "defender";
                reason = "battle_round_limit";
            }
            else if (as2Winner == "blue" && defendersDead && !attackersDead)
            {
                winner = "attacker";
                reason = "wiped";
            }
            else if (as2Winner == "red" && attackersDead && !defendersDead)
            {
                winner = "defender";
                reason = "wiped";
            }
            else
            {
                throw new InvalidOperationException(
                    "AS2 winner does not match the per-unit survival result: " + as2Winner);
            }
            JObject receipt = new JObject
            {
                ["schema"] = "warlord.as2-battle-receipt.v1",
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
                ["winner"] = winner,
                ["reason"] = reason,
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
            return BuildResumeEnvelope(prepared, receipt, null);
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
                if (source.Value<int?>("petId") != participant.Value<int>("petId")
                    || source.Value<string>("identifier") != participant.Value<string>("identifier")
                    || source.Value<string>("resolvedType") != participant.Value<string>("identifier")
                    || source.Value<int?>("level") != participant.Value<int>("level"))
                    throw new InvalidOperationException(side + " pet identity changed for " + pieceId);
                JArray sourcePromotions = source["strategicPromotions"] as JArray;
                if (source.Value<bool?>("strategicPromotionsValid") != true
                    || !JToken.DeepEquals(
                    sourcePromotions,
                    participant["strategicPromotions"] as JArray))
                    throw new InvalidOperationException(side + " strategic promotion projection changed for " + pieceId);

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
                normalized.Add(new JObject
                {
                    ["pieceId"] = pieceId,
                    ["factionId"] = participant.Value<string>("factionId"),
                    ["petId"] = participant.Value<int>("petId"),
                    ["identifier"] = participant.Value<string>("identifier"),
                    ["level"] = participant.Value<int>("level"),
                    ["hpPermille"] = hpPermille,
                    ["alive"] = alive,
                    ["strategicPromotions"] = participant["strategicPromotions"].DeepClone(),
                    ["startMaxHp"] = startMaxHp,
                    ["remainHp"] = remainHp,
                    ["resolvedType"] = source.Value<string>("resolvedType") ?? ""
                });
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
                int price = participant.Value<int>("basePrice");
                int kPrice = participant.Value<int>("kPrice");
                int strategicGoldValue = participant.Value<int>("strategicGoldValue");
                bool lost = result.Value<bool?>("alive") != true;
                catalogBaseExposureGold += price;
                catalogBaseExposureK += kPrice;
                strategicExposureGold += strategicGoldValue;
                if (lost)
                {
                    catalogBaseLostGold += price;
                    catalogBaseLostK += kPrice;
                    strategicLostGold += strategicGoldValue;
                }
                units.Add(new JObject
                {
                    ["pieceId"] = pieceId,
                    ["petId"] = participant.Value<int>("petId"),
                    ["identifier"] = participant.Value<string>("identifier"),
                    ["catalogName"] = participant.Value<string>("catalogName"),
                    ["rosterType"] = participant.Value<string>("rosterType"),
                    ["strategicPromotions"] = participant["strategicPromotions"].DeepClone(),
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
                ["schema"] = "warlord.as2-battle-receipt.v1",
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
            return BuildResumeEnvelope(prepared, receipt, code);
        }

        private JObject BuildNotStartedResume(
            PreparedBattle prepared,
            string code,
            string message)
        {
            JObject receipt = new JObject
            {
                ["schema"] = "warlord.as2-battle-receipt.v1",
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
            if (!string.IsNullOrEmpty(handoffError)) resume["handoffError"] = handoffError;

            JObject init = (JObject)prepared.ClientContext.DeepClone();
            init["mode"] = "phase-c-as2";
            init["source"] = "as2_battle_resume";
            init["productionWrites"] = false;
            init["battleAuthority"] = "as2";
            init["as2BattleSession"] = true;
            init["resume"] = resume;
            return init;
        }

        private void OpenResume(JObject initData)
        {
            Action open = delegate
            {
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

        private static bool AllDead(JArray results)
        {
            foreach (JObject result in results)
                if (result.Value<bool?>("alive") == true) return false;
            return true;
        }

        private static string FirstError(JArray errors)
        {
            JObject first = errors != null && errors.Count > 0 ? errors[0] as JObject : null;
            return first != null
                ? first.Value<string>("message") ?? first.Value<string>("code") ?? "AS2 battle failed"
                : "AS2 battle failed";
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

        private static string RequiredFaction(string value, string fieldName)
        {
            if (value != "red" && value != "blue")
                throw new InvalidOperationException(fieldName + " is invalid");
            return value;
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
