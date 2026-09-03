using System;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.Tasks;
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
    /// - Panel 打开 → _panelHost.OpenPanel
    ///
    /// 关键不变量：
    /// - panel 打开必须走 _panelHost.OpenPanel 才能触发 backdrop/EX_STYLE/HUD-suspend 序列；
    ///   _panelHost 未注入（装配前窗口期）时打开请求直接拒绝。
    /// - 路由本身不持任何业务状态（_activePanel 等仍在 WebOverlayForm 跟踪，与旧路径一致）。
    /// </summary>
    public class LauncherCommandRouter
    {
        /// <summary>
        /// 固定 opener 共享的机械 wait 容器。
        /// 它不保存 tuple、source 或路由 handler，不能扩展为动态 opener registry。
        /// </summary>
        private sealed class FixedPanelOpenWait
        {
            internal System.Threading.Timer Timer;
            internal int Generation;
            internal bool Pending;
            internal string RequestId;
            internal string Origin;
            internal string BaselinePanel;
            internal string BaselineInstance;
            internal bool HasHostAdmission;
            internal long HostAdmission;
            internal int LifecycleEpoch;

            internal System.Threading.Timer Clear()
            {
                Pending = false;
                Generation++;
                RequestId = null;
                Origin = null;
                BaselinePanel = null;
                BaselineInstance = null;
                HasHostAdmission = false;
                HostAdmission = 0;
                LifecycleEpoch = 0;
                System.Threading.Timer timer = Timer;
                Timer = null;
                return timer;
            }
        }

        internal enum CharacterBuildPreparationTarget
        {
            Skills,
            Materials,
            Intelligence
        }

        private enum CharacterBuildPreparationPhase
        {
            None,
            Armed,
            RollbackAfterSettle
        }

        /// <summary>
        /// Character Build 离场后的固定整备目标意图。它只保存相关性和阶段，
        /// 不保存 handler、panelName/initData 或任意可注册 destination。
        /// </summary>
        private sealed class CharacterBuildPreparationNavigationIntent
        {
            internal CharacterBuildPreparationTarget Target;
            internal string PanelInstanceId;
            internal CharacterBuildPreparationPhase Phase;
            internal int Generation;
            internal int LifecycleEpoch;
            internal System.Threading.Timer Timer;

            internal bool Pending
            {
                get { return Phase != CharacterBuildPreparationPhase.None; }
            }

            internal System.Threading.Timer Clear()
            {
                Target = CharacterBuildPreparationTarget.Skills;
                PanelInstanceId = null;
                Phase = CharacterBuildPreparationPhase.None;
                Generation++;
                LifecycleEpoch = 0;
                System.Threading.Timer timer = Timer;
                Timer = null;
                return timer;
            }
        }

        private enum PreparationChildReturnPhase
        {
            None,
            PendingInstanceBind,
            Active,
            Returning
        }

        /// <summary>
        /// Host-owned one-shot capability for Materials/Intelligence -> Character Build.
        /// The browser receives only a presentation hint; authorization remains bound here to
        /// the exact child panel name, Host-issued instance and navigation lifecycle epoch.
        /// </summary>
        private sealed class PreparationChildReturnCapability
        {
            internal string PanelName;
            internal string PanelInstanceId;
            internal PreparationChildReturnPhase Phase;
            internal int Generation;
            internal int LifecycleEpoch;
            internal System.Threading.Timer Timer;

            internal bool Pending
            {
                get { return Phase != PreparationChildReturnPhase.None; }
            }

            internal System.Threading.Timer Clear()
            {
                PanelName = null;
                PanelInstanceId = null;
                Phase = PreparationChildReturnPhase.None;
                Generation++;
                LifecycleEpoch = 0;
                System.Threading.Timer timer = Timer;
                Timer = null;
                return timer;
            }
        }

        internal enum MaterialShopCharacterCapsulePhase
        {
            PreparedForward,
            ForwardCommitting,
            SuspendedInShop,
            PreparedReverse,
            ReverseCommitting,
            ReturnedToMaterials,
            Consumed
        }

        /// <summary>
        /// Fixed CharacterBuild -> materials -> NPCShop -> materials capability. It is not a
        /// generic return stack and never contains an arbitrary destination or initData payload.
        /// </summary>
        internal sealed class MaterialShopCharacterCapsule
        {
            internal int LifecycleEpoch;
            internal int PreparationChildGeneration;
            internal string SourceCraftingInstance;
            internal string NpcShopInstance;
            internal string ReturnCraftingInstance;
            internal MaterialShopCharacterCapsulePhase Phase;
        }

        private readonly Bus.XmlSocketServer _socketServer;
        private readonly Action<Keys> _onSendKey;
        private readonly Action _onToggleFullscreen;
        private readonly Action _onToggleLog;
        private readonly Action _onForceExit;
        private readonly Action<string> _postToWeb;
        private readonly bool _preparationNavigationV1;
        private PanelHostController _panelHost;
        private LootPanelCoordinator _lootPanelCoordinator;
        private SkillTask _skillTask;
        private EquipmentTuningTask _equipmentTuningTask;
        private CharacterBuildTask _characterBuildTask;
        private Func<string, bool> _gameCommandSenderOverride;
        private Func<bool> _panelAdmissionGate;
        private readonly object _panelNavigationLifecycleLock =
            new object();
        private int _panelNavigationLifecycleEpoch;
        private System.Threading.Timer _skillOpenTimer;
        private int _skillOpenGeneration;
        private bool _skillOpenPending;
        private string _skillOpenRequestId;
        private string _skillOpenOrigin;
        private string _skillOpenBaselinePanel;
        private string _skillOpenBaselineInstance;
        private bool _skillOpenHasHostAdmission;
        private long _skillOpenHostAdmission;
        private int _skillOpenLifecycleEpoch;
        private readonly CharacterBuildPreparationNavigationIntent
            _characterBuildPreparationNavigation =
                new CharacterBuildPreparationNavigationIntent();
        private Action _beforeCharacterBuildPreparationNavigationConsumeForTests;
        private Action _beforeSkillsCharacterBuildNavigationConsumeForTests;
        private Action _afterSkillOpenTimeoutClearedForTests;
        private System.Threading.Timer _skillsCharacterBuildNavigationTimer;
        private int _skillsCharacterBuildNavigationGeneration;
        private string _pendingSkillsCharacterBuildNavigationInstance;
        private readonly PreparationChildReturnCapability
            _preparationChildReturn =
                new PreparationChildReturnCapability();
        private MaterialShopCharacterCapsule _materialShopCharacterCapsule;
        private readonly FixedPanelOpenWait
            _nativeEquipmentBuildOpen =
                new FixedPanelOpenWait();
        private readonly FixedPanelOpenWait
            _nativeEquipmentTuningOpen =
                new FixedPanelOpenWait();
        private readonly FixedPanelOpenWait
            _materialOpen =
                new FixedPanelOpenWait();
        private int _lastAdmittedMaterialOpenGeneration;
        private string _lastAdmittedMaterialOpenRequestId;
        private string _lastSuccessfulNativeEquipmentTuningOpenRequestId;
        internal int SkillOpenTimeoutMs { get; set; } = 1800;
        internal int MaterialPanelOpenTimeoutMs { get; set; } = 1800;
        internal int NativeEquipmentBuildOpenTimeoutMs { get; set; } = 1800;
        internal int NativeEquipmentTuningOpenTimeoutMs { get; set; } = 1800;
        internal int CharacterBuildPreparationNavigationTimeoutMs
        {
            get;
            set;
        } = 5000;
        internal int SkillsCharacterBuildNavigationTimeoutMs { get; set; } = 5000;
        internal int PreparationChildCharacterBuildNavigationTimeoutMs
        {
            get;
            set;
        } = 5000;

        public LauncherCommandRouter(
            Bus.XmlSocketServer socketServer,
            Action<Keys> onSendKey,
            Action onToggleFullscreen,
            Action onToggleLog,
            Action onForceExit,
            Action<string> postToWeb,
            bool preparationNavigationV1 = false)
        {
            _socketServer = socketServer;
            _onSendKey = onSendKey;
            _onToggleFullscreen = onToggleFullscreen;
            _onToggleLog = onToggleLog;
            _onForceExit = onForceExit;
            _postToWeb = postToWeb;
            _preparationNavigationV1 = preparationNavigationV1;
        }

        /// <summary>二阶段注入：Program.cs 先 new Router，再 new PanelHostController(...)，最后 SetPanelHost 回注。</summary>
        public void SetPanelHost(PanelHostController host)
        {
            if (_panelHost != null
                && !object.ReferenceEquals(_panelHost, host))
            {
                _panelHost.SetSecurityInitDataEnricher(null);
            }
            _panelHost = host;
            if (host != null)
            {
                host.SetSecurityInitDataEnricher(
                    EnrichPreparationChildReturnInitData);
            }
        }
        public void SetSkillTask(SkillTask task) { _skillTask = task; }
        public void SetEquipmentTuningTask(EquipmentTuningTask task) { _equipmentTuningTask = task; }
        public void SetCharacterBuildTask(CharacterBuildTask task) { _characterBuildTask = task; }
        public void SetLootPanelCoordinator(LootPanelCoordinator coordinator)
        {
            _lootPanelCoordinator = coordinator;
        }
        internal bool PreparationNavigationV1
        {
            get { return _preparationNavigationV1; }
        }
        internal void SetGameCommandSenderForTests(Func<string, bool> sender) { _gameCommandSenderOverride = sender; }
        internal void SetBeforeCharacterBuildSkillsNavigationConsumeForTests(Action action)
        {
            SetBeforeCharacterBuildPreparationNavigationConsumeForTests(
                action);
        }
        internal void SetBeforeCharacterBuildPreparationNavigationConsumeForTests(
            Action action)
        {
            _beforeCharacterBuildPreparationNavigationConsumeForTests =
                action;
        }
        internal void SetBeforeSkillsCharacterBuildNavigationConsumeForTests(
            Action action)
        {
            _beforeSkillsCharacterBuildNavigationConsumeForTests =
                action;
        }
        internal void SetAfterSkillOpenTimeoutClearedForTests(
            Action action)
        {
            _afterSkillOpenTimeoutClearedForTests =
                action;
        }
        internal void SetPanelAdmissionGate(Func<bool> gate)
        {
            _panelAdmissionGate = gate;
        }

        internal bool TryOpenAgentPanel(string panelName)
        {
            switch (panelName)
            {
                case "help":
                case "map":
                case "tasks":
                case "team":
                case "jukebox":
                    return OpenPanel(panelName, null);
                case "settings":
                    return OpenPanel(
                        "settings",
                        new JObject
                        {
                            ["source"] = "agent_runtime_settings",
                            ["dev"] = false
                        }.ToString(Formatting.None));
                case "settings_camera_preview":
                    return OpenPanel(
                        "settings",
                        new JObject
                        {
                            ["source"] = "agent_runtime_settings",
                            ["dev"] = false,
                            ["initialView"] = "camera_preview"
                        }.ToString(Formatting.None));
                case "materials":
                    return RouteMaterialUi();
                default:
                    return false;
            }
        }

        /// <summary>
        /// WarlordBattleTask 完成 AS2 战斗后的专用恢复能力。
        /// 该入口不暴露给通用 panel_request；只接受 Host 生成的 v1 恢复包，
        /// 重建外层白名单字段后再经统一 PanelHost 打开军阀演习。
        /// </summary>
        internal bool TryOpenWarlordResumePanel(JObject initData)
        {
            JObject safeInitData;
            string rejectionReason;
            if (!TryBuildWarlordResumeInitData(
                    initData,
                    out safeInitData,
                    out rejectionReason))
            {
                LogManager.Log(
                    "event=warlord_resume_open_rejected reason="
                    + rejectionReason);
                return false;
            }

            bool opened = OpenPanel(
                "warlord",
                safeInitData.ToString(Formatting.None));
            LogManager.Log(
                "event=warlord_resume_open_result result="
                + (opened ? "opened" : "host_gate"));
            return opened;
        }

        private static bool TryBuildWarlordResumeInitData(
            JObject input,
            out JObject output,
            out string rejectionReason)
        {
            output = null;
            rejectionReason = "invalid_envelope";
            if (input == null || input.Count != 12)
                return false;
            if (!HasExactWarlordResumeRootProperties(input))
                return false;
            if (!IsExactString(input["mode"], "phase-c-as2")
                || !IsExactString(input["source"], "as2_battle_resume")
                || !IsExactString(input["battleAuthority"], "as2")
                || !IsExactBoolean(input["productionWrites"], false)
                || !IsExactBoolean(input["as2BattleSession"], true))
            {
                rejectionReason = "authority_contract";
                return false;
            }

            string seed = ReadBoundedWarlordString(input["seed"], 160);
            string preset = ReadBoundedWarlordString(input["preset"], 32);
            string difficulty = ReadBoundedWarlordString(input["difficulty"], 32);
            string mapTheme = ReadBoundedWarlordString(input["mapTheme"], 32);
            if (seed == null
                || (preset != "standard" && preset != "all-units")
                || (difficulty != "easy" && difficulty != "normal"
                    && difficulty != "hard" && difficulty != "extreme")
                || (mapTheme != "desert" && mapTheme != "tundra")
                || input["forceWebglFailure"].Type != JTokenType.Boolean)
            {
                rejectionReason = "client_context_contract";
                return false;
            }

            JArray transitions = input["aiSeenTransitions"] as JArray;
            if (transitions == null || transitions.Count > 256)
            {
                rejectionReason = "client_context_contract";
                return false;
            }
            foreach (JToken transition in transitions)
            {
                if (ReadBoundedWarlordString(transition, 256, true) == null)
                {
                    rejectionReason = "client_context_contract";
                    return false;
                }
            }

            JObject resume = input["resume"] as JObject;
            bool hasHandoffError = resume != null
                && resume.Property("handoffError") != null;
            if (resume == null
                || resume.Count != (hasHandoffError ? 8 : 7)
                || !HasRequiredWarlordResumeProperties(resume)
                || !IsExactString(
                    resume["schema"],
                    "warlord.as2-resume.v1"))
            {
                rejectionReason = "resume_shape";
                return false;
            }

            JObject request = resume["request"] as JObject;
            JObject state = resume["state"] as JObject;
            JObject command = resume["command"] as JObject;
            JObject receipt = resume["receipt"] as JObject;
            JObject resumeClientContext = resume["clientContext"] as JObject;
            string digest = ReadBoundedWarlordString(
                resume["inputDigest"],
                71);
            string receiptStatus = receipt != null
                ? receipt.Value<string>("status")
                : null;
            if (request == null || state == null || command == null
                || receipt == null || resumeClientContext == null
                || !IsExactString(
                    request["schema"],
                    "warlord.as2-battle-request.v1")
                || !IsExactString(
                    receipt["schema"],
                    "warlord.as2-battle-receipt.v1")
                || digest == null
                || !digest.StartsWith("sha256:", StringComparison.Ordinal)
                || digest.Length != 71
                || !string.Equals(
                    WarlordBattleTask.Sha256OfToken(request),
                    digest,
                    StringComparison.Ordinal)
                || !JToken.DeepEquals(request["state"], state)
                || !JToken.DeepEquals(request["command"], command)
                || !string.Equals(
                    request.Value<string>("sessionId"),
                    receipt.Value<string>("sessionId"),
                    StringComparison.Ordinal)
                || !string.Equals(
                    request.Value<string>("requestId"),
                    receipt.Value<string>("requestId"),
                    StringComparison.Ordinal)
                || !string.Equals(
                    digest,
                    receipt.Value<string>("inputDigest"),
                    StringComparison.Ordinal)
                || (receiptStatus != "accepted"
                    && receiptStatus != "unknown"
                    && receiptStatus != "not_started")
                || (receiptStatus == "accepted" && hasHandoffError)
                || (receiptStatus != "accepted" && !hasHandoffError))
            {
                rejectionReason = "resume_authority_contract";
                return false;
            }
            if (hasHandoffError
                && ReadBoundedWarlordString(
                    resume["handoffError"],
                    160) == null)
            {
                rejectionReason = "resume_authority_contract";
                return false;
            }

            JObject normalizedClientContext = new JObject
            {
                ["seed"] = seed,
                ["preset"] = preset,
                ["difficulty"] = difficulty,
                ["mapTheme"] = mapTheme,
                ["forceWebglFailure"] = input.Value<bool>(
                    "forceWebglFailure"),
                ["aiSeenTransitions"] = transitions.DeepClone()
            };
            if (!JToken.DeepEquals(
                    normalizedClientContext,
                    resumeClientContext))
            {
                rejectionReason = "client_context_mismatch";
                return false;
            }

            output = new JObject
            {
                ["seed"] = seed,
                ["preset"] = preset,
                ["difficulty"] = difficulty,
                ["mapTheme"] = mapTheme,
                ["forceWebglFailure"] = input.Value<bool>(
                    "forceWebglFailure"),
                ["aiSeenTransitions"] = transitions.DeepClone(),
                ["mode"] = "phase-c-as2",
                ["source"] = "as2_battle_resume",
                ["productionWrites"] = false,
                ["battleAuthority"] = "as2",
                ["as2BattleSession"] = true,
                ["resume"] = resume.DeepClone()
            };
            rejectionReason = null;
            return true;
        }

        private static bool HasExactWarlordResumeRootProperties(
            JObject input)
        {
            string[] names =
            {
                "seed", "preset", "difficulty", "mapTheme",
                "forceWebglFailure", "aiSeenTransitions", "mode",
                "source", "productionWrites", "battleAuthority",
                "as2BattleSession", "resume"
            };
            for (int i = 0; i < names.Length; i++)
                if (input.Property(names[i]) == null) return false;
            return true;
        }

        private static bool HasRequiredWarlordResumeProperties(
            JObject resume)
        {
            string[] names =
            {
                "schema", "request", "state", "command", "inputDigest",
                "receipt", "clientContext"
            };
            for (int i = 0; i < names.Length; i++)
                if (resume.Property(names[i]) == null) return false;
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

        private static bool IsExactBoolean(JToken token, bool expected)
        {
            return token != null
                && token.Type == JTokenType.Boolean
                && token.Value<bool>() == expected;
        }

        private static string ReadBoundedWarlordString(
            JToken token,
            int maximumLength,
            bool allowEmpty = false)
        {
            if (token == null || token.Type != JTokenType.String)
                return null;
            string value = token.Value<string>();
            if (value == null || value.Length > maximumLength
                || (!allowEmpty && value.Length == 0))
                return null;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i]))
                    return null;
            return value;
        }

        internal string PendingCharacterBuildSkillsNavigationInstance
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _characterBuildPreparationNavigation.Pending
                        && _characterBuildPreparationNavigation.Target
                            == CharacterBuildPreparationTarget.Skills
                        ? _characterBuildPreparationNavigation.PanelInstanceId
                        : null;
            }
        }
        internal string PendingCharacterBuildPreparationNavigationInstance
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _characterBuildPreparationNavigation.Pending
                        ? _characterBuildPreparationNavigation.PanelInstanceId
                        : null;
            }
        }
        internal string PendingCharacterBuildPreparationTarget
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _characterBuildPreparationNavigation.Pending
                        ? CharacterBuildPreparationTargetName(
                            _characterBuildPreparationNavigation.Target)
                        : null;
            }
        }
        internal string PendingCharacterBuildPreparationPhase
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return CharacterBuildPreparationPhaseName(
                        _characterBuildPreparationNavigation.Phase);
            }
        }
        internal string PendingSkillsCharacterBuildNavigationInstance
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _pendingSkillsCharacterBuildNavigationInstance;
            }
        }
        internal string PendingPreparationChildReturnPanelName
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _preparationChildReturn.Pending
                        ? _preparationChildReturn.PanelName
                        : null;
            }
        }
        internal string PendingPreparationChildReturnInstance
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _preparationChildReturn.Pending
                        ? _preparationChildReturn.PanelInstanceId
                        : null;
            }
        }
        internal string PendingMaterialOpenRequestId
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _materialOpen.Pending
                        ? _materialOpen.RequestId
                        : null;
            }
        }
        internal string PendingMaterialOpenOrigin
        {
            get
            {
                lock (_panelNavigationLifecycleLock)
                    return _materialOpen.Pending
                        ? _materialOpen.Origin
                        : null;
            }
        }

        internal static bool TryParseCharacterBuildPreparationCloseReason(
            string reason,
            out CharacterBuildPreparationTarget target)
        {
            switch (reason)
            {
                case "navigate_skills":
                    target = CharacterBuildPreparationTarget.Skills;
                    return true;
                case "navigate_materials":
                    target = CharacterBuildPreparationTarget.Materials;
                    return true;
                case "navigate_intelligence":
                    target = CharacterBuildPreparationTarget.Intelligence;
                    return true;
                default:
                    target = CharacterBuildPreparationTarget.Skills;
                    return false;
            }
        }

        internal static bool IsCharacterBuildPreparationTargetEnabled(
            CharacterBuildPreparationTarget target)
        {
            return target == CharacterBuildPreparationTarget.Skills
                || target == CharacterBuildPreparationTarget.Materials
                || target == CharacterBuildPreparationTarget.Intelligence;
        }

        internal static JObject BuildIntelligenceProductionInitData()
        {
            return new JObject
            {
                ["mode"] = "prod",
                ["source"] = "runtime",
                ["debug"] = false
            };
        }

        internal static bool TryNormalizeCharacterBuildReturnFocusAction(
            string value,
            out string normalized)
        {
            if (string.Equals(
                    value,
                    "skills",
                    StringComparison.Ordinal)
                || string.Equals(
                    value,
                    "preparation-menu",
                    StringComparison.Ordinal))
            {
                normalized = value;
                return true;
            }
            normalized = null;
            return false;
        }

        private static string CharacterBuildPreparationTargetName(
            CharacterBuildPreparationTarget target)
        {
            switch (target)
            {
                case CharacterBuildPreparationTarget.Skills:
                    return "skills";
                case CharacterBuildPreparationTarget.Materials:
                    return "materials";
                case CharacterBuildPreparationTarget.Intelligence:
                    return "intelligence";
                default:
                    return "unknown";
            }
        }

        private static string PreparationChildPanelName(
            CharacterBuildPreparationTarget target)
        {
            switch (target)
            {
                case CharacterBuildPreparationTarget.Materials:
                    return "crafting";
                case CharacterBuildPreparationTarget.Intelligence:
                    return "intelligence";
                default:
                    return null;
            }
        }

        private static string PreparationChildReturnOrigin(
            string panelName)
        {
            if (string.Equals(
                    panelName,
                    "crafting",
                    StringComparison.Ordinal))
            {
                return "materials_return";
            }
            if (string.Equals(
                    panelName,
                    "intelligence",
                    StringComparison.Ordinal))
            {
                return "intelligence_return";
            }
            return null;
        }

        internal static bool IsPreparationChildPanelName(
            string panelName)
        {
            return PreparationChildReturnOrigin(panelName)
                != null;
        }

        private static string CharacterBuildPreparationPhaseName(
            CharacterBuildPreparationPhase phase)
        {
            switch (phase)
            {
                case CharacterBuildPreparationPhase.Armed:
                    return "arm_to_settled";
                case CharacterBuildPreparationPhase.RollbackAfterSettle:
                    return "rollback_after_settle";
                default:
                    return null;
            }
        }

        private bool TryArmPreparationChildReturnCapabilityLocked(
            CharacterBuildPreparationTarget target)
        {
            string panelName =
                PreparationChildPanelName(target);
            if (panelName == null
                || _preparationChildReturn.Pending)
            {
                return false;
            }
            _preparationChildReturn.Generation++;
            _preparationChildReturn.PanelName =
                panelName;
            _preparationChildReturn.PanelInstanceId =
                null;
            _preparationChildReturn.Phase =
                PreparationChildReturnPhase.PendingInstanceBind;
            _preparationChildReturn.LifecycleEpoch =
                _panelNavigationLifecycleEpoch;
            return true;
        }

        private System.Threading.Timer
            ClearPreparationChildReturnLocked()
        {
            return _preparationChildReturn.Clear();
        }

        internal bool TryPrepareMaterialShopCharacterForward(
            string sourceCraftingInstance,
            string targetNpcShopInstance,
            out MaterialShopCharacterCapsule capsule)
        {
            capsule = null;
            if (string.IsNullOrEmpty(sourceCraftingInstance)
                || string.IsNullOrEmpty(targetNpcShopInstance))
            {
                return false;
            }
            lock (_panelNavigationLifecycleLock)
            {
                if (_materialShopCharacterCapsule != null)
                    return false;
                if (_preparationChildReturn.Phase
                        != PreparationChildReturnPhase.Active)
                {
                    return true;
                }
                if (_preparationChildReturn.LifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || !string.Equals(
                        _preparationChildReturn.PanelName,
                        "crafting",
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _preparationChildReturn.PanelInstanceId,
                        sourceCraftingInstance,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                capsule = new MaterialShopCharacterCapsule
                {
                    LifecycleEpoch = _panelNavigationLifecycleEpoch,
                    PreparationChildGeneration = _preparationChildReturn.Generation,
                    SourceCraftingInstance = sourceCraftingInstance,
                    NpcShopInstance = targetNpcShopInstance,
                    Phase = MaterialShopCharacterCapsulePhase.PreparedForward
                };
                return true;
            }
        }

        internal bool IsMaterialShopCharacterForwardCurrent(
            MaterialShopCharacterCapsule capsule,
            string sourceCraftingInstance,
            string targetNpcShopInstance)
        {
            lock (_panelNavigationLifecycleLock)
            {
                if (capsule == null)
                {
                    return _materialShopCharacterCapsule == null
                        && !(_preparationChildReturn.Phase
                                == PreparationChildReturnPhase.Active
                            && string.Equals(
                                _preparationChildReturn.PanelName,
                                "crafting",
                                StringComparison.Ordinal)
                            && string.Equals(
                                _preparationChildReturn.PanelInstanceId,
                                sourceCraftingInstance,
                                StringComparison.Ordinal));
                }
                return _materialShopCharacterCapsule == null
                    && capsule.Phase
                        == MaterialShopCharacterCapsulePhase.PreparedForward
                    && capsule.LifecycleEpoch == _panelNavigationLifecycleEpoch
                    && capsule.PreparationChildGeneration
                        == _preparationChildReturn.Generation
                    && _preparationChildReturn.Phase
                        == PreparationChildReturnPhase.Active
                    && string.Equals(
                        capsule.SourceCraftingInstance,
                        sourceCraftingInstance,
                        StringComparison.Ordinal)
                    && string.Equals(
                        capsule.NpcShopInstance,
                        targetNpcShopInstance,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _preparationChildReturn.PanelName,
                        "crafting",
                        StringComparison.Ordinal)
                    && string.Equals(
                        _preparationChildReturn.PanelInstanceId,
                        sourceCraftingInstance,
                        StringComparison.Ordinal);
            }
        }

        internal void CommitMaterialShopCharacterForwardNoFail(
            MaterialShopCharacterCapsule capsule)
        {
            if (capsule == null) return;
            System.Threading.Timer timer = null;
            lock (_panelNavigationLifecycleLock)
            {
                if (!ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    || capsule.Phase
                        != MaterialShopCharacterCapsulePhase.ForwardCommitting)
                {
                    return;
                }
                timer = ClearPreparationChildReturnLocked();
                capsule.LifecycleEpoch = _panelNavigationLifecycleEpoch;
                capsule.Phase = MaterialShopCharacterCapsulePhase.SuspendedInShop;
            }
            if (timer != null)
            {
                try { timer.Dispose(); }
                catch { }
            }
        }

        internal bool TrySealMaterialShopCharacterForwardCommit(
            MaterialShopCharacterCapsule capsule,
            string sourceCraftingInstance,
            string targetNpcShopInstance)
        {
            if (capsule == null)
            {
                return IsMaterialShopCharacterForwardCurrent(
                    null,
                    sourceCraftingInstance,
                    targetNpcShopInstance);
            }
            lock (_panelNavigationLifecycleLock)
            {
                if (!IsMaterialShopCharacterForwardCurrentLocked(capsule)
                    || !string.Equals(
                        capsule.SourceCraftingInstance,
                        sourceCraftingInstance,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        capsule.NpcShopInstance,
                        targetNpcShopInstance,
                        StringComparison.Ordinal)) return false;
                capsule.Phase =
                    MaterialShopCharacterCapsulePhase.ForwardCommitting;
                _materialShopCharacterCapsule = capsule;
                return true;
            }
        }

        internal void AbortMaterialShopCharacterForwardNoFail(
            MaterialShopCharacterCapsule capsule,
            string sourceCraftingInstance,
            string targetNpcShopInstance)
        {
            if (capsule == null) return;
            lock (_panelNavigationLifecycleLock)
            {
                if (!ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    || capsule.Phase
                        != MaterialShopCharacterCapsulePhase.ForwardCommitting
                    || !string.Equals(
                        capsule.SourceCraftingInstance,
                        sourceCraftingInstance,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        capsule.NpcShopInstance,
                        targetNpcShopInstance,
                        StringComparison.Ordinal)) return;
                _materialShopCharacterCapsule = null;
                _preparationChildReturn.Generation++;
                _preparationChildReturn.PanelName = "crafting";
                _preparationChildReturn.PanelInstanceId = sourceCraftingInstance;
                _preparationChildReturn.Phase =
                    PreparationChildReturnPhase.Active;
                _preparationChildReturn.LifecycleEpoch =
                    _panelNavigationLifecycleEpoch;
                _preparationChildReturn.Timer = null;
                capsule.LifecycleEpoch = _panelNavigationLifecycleEpoch;
                capsule.PreparationChildGeneration =
                    _preparationChildReturn.Generation;
                capsule.Phase =
                    MaterialShopCharacterCapsulePhase.PreparedForward;
            }
        }

        internal bool TryPrepareMaterialShopCharacterReverse(
            MaterialShopCharacterCapsule capsule,
            string sourceNpcShopInstance,
            string targetCraftingInstance)
        {
            if (capsule == null) return true;
            if (string.IsNullOrEmpty(sourceNpcShopInstance)
                || string.IsNullOrEmpty(targetCraftingInstance)) return false;
            lock (_panelNavigationLifecycleLock)
            {
                bool current = ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    && capsule.Phase
                        == MaterialShopCharacterCapsulePhase.SuspendedInShop
                    && capsule.LifecycleEpoch == _panelNavigationLifecycleEpoch
                    && string.Equals(
                        capsule.NpcShopInstance,
                        sourceNpcShopInstance,
                        StringComparison.Ordinal);
                if (!current) return false;
                capsule.ReturnCraftingInstance = targetCraftingInstance;
                capsule.Phase = MaterialShopCharacterCapsulePhase.PreparedReverse;
                return true;
            }
        }

        internal bool IsMaterialShopCharacterReverseCurrent(
            MaterialShopCharacterCapsule capsule,
            string sourceNpcShopInstance,
            string targetCraftingInstance)
        {
            if (capsule == null) return true;
            lock (_panelNavigationLifecycleLock)
            {
                return ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    && capsule.Phase
                        == MaterialShopCharacterCapsulePhase.PreparedReverse
                    && capsule.LifecycleEpoch == _panelNavigationLifecycleEpoch
                    && string.Equals(
                        capsule.NpcShopInstance,
                        sourceNpcShopInstance,
                        StringComparison.Ordinal)
                    && string.Equals(
                        capsule.ReturnCraftingInstance,
                        targetCraftingInstance,
                        StringComparison.Ordinal);
            }
        }

        internal bool TrySealMaterialShopCharacterReverseCommit(
            MaterialShopCharacterCapsule capsule,
            string sourceNpcShopInstance,
            string targetCraftingInstance)
        {
            if (capsule == null) return true;
            lock (_panelNavigationLifecycleLock)
            {
                if (!ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    || capsule.Phase
                        != MaterialShopCharacterCapsulePhase.PreparedReverse
                    || !string.Equals(
                        capsule.NpcShopInstance,
                        sourceNpcShopInstance,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        capsule.ReturnCraftingInstance,
                        targetCraftingInstance,
                        StringComparison.Ordinal)) return false;
                capsule.Phase =
                    MaterialShopCharacterCapsulePhase.ReverseCommitting;
                return true;
            }
        }

        internal void AbortMaterialShopCharacterReverseNoFail(
            MaterialShopCharacterCapsule capsule,
            string sourceNpcShopInstance,
            string targetCraftingInstance)
        {
            if (capsule == null) return;
            lock (_panelNavigationLifecycleLock)
            {
                if (!ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    || (capsule.Phase
                            != MaterialShopCharacterCapsulePhase.PreparedReverse
                        && capsule.Phase
                            != MaterialShopCharacterCapsulePhase.ReverseCommitting)
                    || !string.Equals(
                        capsule.NpcShopInstance,
                        sourceNpcShopInstance,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        capsule.ReturnCraftingInstance,
                        targetCraftingInstance,
                        StringComparison.Ordinal))
                {
                    return;
                }
                capsule.ReturnCraftingInstance = null;
                capsule.LifecycleEpoch = _panelNavigationLifecycleEpoch;
                capsule.Phase = MaterialShopCharacterCapsulePhase.SuspendedInShop;
            }
        }

        internal void CommitMaterialShopCharacterReverseNoFail(
            MaterialShopCharacterCapsule capsule,
            string targetCraftingInstance)
        {
            if (capsule == null) return;
            lock (_panelNavigationLifecycleLock)
            {
                if (!ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    || capsule.Phase
                        != MaterialShopCharacterCapsulePhase.ReverseCommitting)
                {
                    return;
                }
                _materialShopCharacterCapsule = null;
                capsule.ReturnCraftingInstance = targetCraftingInstance;
                capsule.Phase = MaterialShopCharacterCapsulePhase.ReturnedToMaterials;
                _preparationChildReturn.Generation++;
                _preparationChildReturn.PanelName = "crafting";
                _preparationChildReturn.PanelInstanceId = targetCraftingInstance;
                _preparationChildReturn.Phase = PreparationChildReturnPhase.Active;
                _preparationChildReturn.LifecycleEpoch = _panelNavigationLifecycleEpoch;
                _preparationChildReturn.Timer = null;
            }
        }

        internal void ConsumeMaterialShopCharacterOnNpcShopCloseNoFail(
            MaterialShopCharacterCapsule capsule,
            string npcShopInstance)
        {
            if (capsule == null) return;
            lock (_panelNavigationLifecycleLock)
            {
                if (!ReferenceEquals(_materialShopCharacterCapsule, capsule)
                    || !string.Equals(
                        capsule.NpcShopInstance,
                        npcShopInstance,
                        StringComparison.Ordinal))
                {
                    return;
                }
                _materialShopCharacterCapsule = null;
                capsule.Phase = MaterialShopCharacterCapsulePhase.Consumed;
            }
        }

        private bool IsMaterialShopCharacterForwardCurrentLocked(
            MaterialShopCharacterCapsule capsule)
        {
            return capsule != null
                && _materialShopCharacterCapsule == null
                && capsule.Phase
                    == MaterialShopCharacterCapsulePhase.PreparedForward
                && capsule.LifecycleEpoch == _panelNavigationLifecycleEpoch
                && capsule.PreparationChildGeneration
                    == _preparationChildReturn.Generation
                && _preparationChildReturn.Phase
                    == PreparationChildReturnPhase.Active
                && string.Equals(
                    _preparationChildReturn.PanelName,
                    "crafting",
                    StringComparison.Ordinal)
                && string.Equals(
                    _preparationChildReturn.PanelInstanceId,
                    capsule.SourceCraftingInstance,
                    StringComparison.Ordinal);
        }

        private static bool IsMaterialShopCharacterCommitPermittedLocked(
            MaterialShopCharacterCapsule capsule)
        {
            return capsule != null
                && (capsule.Phase
                        == MaterialShopCharacterCapsulePhase.ForwardCommitting
                    || capsule.Phase
                        == MaterialShopCharacterCapsulePhase.ReverseCommitting);
        }

        private void CancelUnboundPreparationChildReturnForOrdinaryOpen(
            string panelName)
        {
            System.Threading.Timer timer =
                null;
            bool cancelled =
                false;
            lock (_panelNavigationLifecycleLock)
            {
                if (_preparationChildReturn.Phase
                        == PreparationChildReturnPhase.PendingInstanceBind
                    && string.Equals(
                        _preparationChildReturn.PanelName,
                        panelName,
                        StringComparison.Ordinal))
                {
                    timer =
                        ClearPreparationChildReturnLocked();
                    cancelled =
                        true;
                }
            }
            if (timer != null)
                timer.Dispose();
            if (cancelled)
            {
                LogManager.Log(
                    "event=preparation_child_return_capability_cancelled panel="
                    + (panelName ?? "unknown")
                    + " reason=ordinary_same_panel_open");
            }
        }

        private string EnrichPreparationChildReturnInitData(
            string panelName,
            string initDataJson,
            string panelInstanceId)
        {
            if (!IsPreparationChildPanelName(panelName))
            {
                System.Threading.Timer competingTimer =
                    null;
                lock (_panelNavigationLifecycleLock)
                {
                    if (_preparationChildReturn.Pending)
                    {
                        competingTimer =
                            ClearPreparationChildReturnLocked();
                    }
                    if (_materialShopCharacterCapsule != null
                        && !IsMaterialShopCharacterCommitPermittedLocked(
                            _materialShopCharacterCapsule))
                    {
                        _materialShopCharacterCapsule.Phase =
                            MaterialShopCharacterCapsulePhase.Consumed;
                        _materialShopCharacterCapsule =
                            null;
                    }
                }
                if (competingTimer != null)
                    competingTimer.Dispose();
                return initDataJson;
            }

            bool grant =
                false;
            System.Threading.Timer staleTimer =
                null;
            lock (_panelNavigationLifecycleLock)
            {
                if (_preparationChildReturn.Pending
                    && (_preparationChildReturn.LifecycleEpoch
                            != _panelNavigationLifecycleEpoch
                        || _preparationChildReturn.Phase
                            != PreparationChildReturnPhase.PendingInstanceBind
                        || !string.Equals(
                            _preparationChildReturn.PanelName,
                            panelName,
                            StringComparison.Ordinal)
                        || string.IsNullOrEmpty(panelInstanceId)))
                {
                    staleTimer =
                        ClearPreparationChildReturnLocked();
                }
                else if (_preparationChildReturn.Phase
                        == PreparationChildReturnPhase.PendingInstanceBind
                    && string.Equals(
                        _preparationChildReturn.PanelName,
                        panelName,
                        StringComparison.Ordinal)
                    && !string.IsNullOrEmpty(panelInstanceId))
                {
                    _preparationChildReturn.PanelInstanceId =
                        panelInstanceId;
                    _preparationChildReturn.Phase =
                        PreparationChildReturnPhase.Active;
                    grant =
                        true;
                }
            }
            if (staleTimer != null)
                staleTimer.Dispose();

            JObject initData;
            try
            {
                initData =
                    string.IsNullOrEmpty(initDataJson)
                        ? new JObject()
                        : JObject.Parse(initDataJson);
            }
            catch (JsonException)
            {
                initData =
                    new JObject();
            }
            // These fields are presentation hints only. Strip any untrusted source value and add
            // them back exclusively when the Host has bound the exact issued instance above.
            initData.Remove("canReturnCharacterBuild");
            initData.Remove("navigationOrigin");
            if (grant)
            {
                initData["canReturnCharacterBuild"] =
                    true;
                initData["navigationOrigin"] =
                    "character_build";
                LogManager.Log(
                    "event=preparation_child_return_capability_bound panel="
                    + panelName + " panel_instance="
                    + panelInstanceId);
            }
            return initData.ToString(
                Formatting.None);
        }

        /// <summary>
        /// Arms one exact-instance Character Build post-close target. The fixed switch remains
        /// closed over Skills, Materials and Intelligence; it is not a destination registry.
        /// </summary>
        internal bool TryArmCharacterBuildPreparationNavigation(
            string panelInstanceId,
            CharacterBuildPreparationTarget target)
        {
            if (string.IsNullOrEmpty(panelInstanceId)
                || !IsCharacterBuildPreparationTargetEnabled(target))
                return false;
            CharacterBuildTask task = _characterBuildTask;
            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : null;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : null;
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
            lock (_panelNavigationLifecycleLock)
            {
                if (_characterBuildPreparationNavigation.Pending)
                    return false;
                if (!task.IsBoundTo(panelInstanceId)
                    || !task.CanRebind
                    || task.RequiresDetachRecovery)
                {
                    return false;
                }
                int generation =
                    ++_characterBuildPreparationNavigation.Generation;
                int lifecycleEpoch =
                    _panelNavigationLifecycleEpoch;
                _characterBuildPreparationNavigation.Target =
                    target;
                _characterBuildPreparationNavigation.PanelInstanceId =
                    panelInstanceId;
                _characterBuildPreparationNavigation.Phase =
                    CharacterBuildPreparationPhase.Armed;
                _characterBuildPreparationNavigation.LifecycleEpoch =
                    lifecycleEpoch;
                _characterBuildPreparationNavigation.Timer =
                    new System.Threading.Timer(
                        delegate
                        {
                            OnCharacterBuildPreparationNavigationTimeout(
                                generation,
                                lifecycleEpoch,
                                panelInstanceId,
                                target);
                        },
                        null,
                        Math.Max(
                            1,
                            CharacterBuildPreparationNavigationTimeoutMs),
                        System.Threading.Timeout.Infinite);
            }
            LogManager.Log(
                "event=character_build_preparation_navigation_armed target="
                + CharacterBuildPreparationTargetName(target)
                + " panel_instance=" + panelInstanceId);
            return true;
        }

        internal bool TryArmCharacterBuildSkillsNavigation(
            string panelInstanceId)
        {
            return TryArmCharacterBuildPreparationNavigation(
                panelInstanceId,
                CharacterBuildPreparationTarget.Skills);
        }

        internal bool CancelCharacterBuildPreparationNavigation(
            string panelInstanceId,
            CharacterBuildPreparationTarget? expectedTarget,
            string reason)
        {
            if (string.IsNullOrEmpty(panelInstanceId))
                return false;
            System.Threading.Timer timer;
            CharacterBuildPreparationTarget target;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_characterBuildPreparationNavigation.Pending
                    || !string.Equals(
                        _characterBuildPreparationNavigation.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || (expectedTarget.HasValue
                        && _characterBuildPreparationNavigation.Target
                            != expectedTarget.Value))
                {
                    return false;
                }
                target =
                    _characterBuildPreparationNavigation.Target;
                timer =
                    ClearCharacterBuildPreparationNavigationLocked();
            }
            if (timer != null) timer.Dispose();
            LogManager.Log(
                "event=character_build_preparation_navigation_cancelled target="
                + CharacterBuildPreparationTargetName(target)
                + " panel_instance=" + panelInstanceId + " reason="
                + (reason ?? "unknown"));
            return true;
        }

        internal bool CancelCharacterBuildSkillsNavigation(
            string panelInstanceId,
            string reason)
        {
            return CancelCharacterBuildPreparationNavigation(
                panelInstanceId,
                CharacterBuildPreparationTarget.Skills,
                reason);
        }

        /// <summary>
        /// Called only from CharacterBuildTask's coordinator-settled callback. The arm timer is
        /// consumed under the same lifecycle lock before the target-specific wait is installed.
        /// </summary>
        internal bool TryCompleteCharacterBuildPreparationNavigation()
        {
            string panelInstanceId;
            CharacterBuildPreparationTarget target;
            CharacterBuildPreparationPhase phase;
            int intentGeneration;
            int intentLifecycleEpoch;
            lock (_panelNavigationLifecycleLock)
            {
                panelInstanceId =
                    _characterBuildPreparationNavigation.PanelInstanceId;
                if (panelInstanceId == null) return false;
                target =
                    _characterBuildPreparationNavigation.Target;
                phase =
                    _characterBuildPreparationNavigation.Phase;
                intentGeneration =
                    _characterBuildPreparationNavigation.Generation;
                intentLifecycleEpoch =
                    _characterBuildPreparationNavigation.LifecycleEpoch;
            }

            CharacterBuildTask task = _characterBuildTask;
            if (phase
                    == CharacterBuildPreparationPhase.RollbackAfterSettle
                && task != null
                && (task.HasBoundPanel
                    || task.RequiresDetachRecovery))
            {
                return false;
            }
            if (task == null
                || task.HasBoundPanel
                || task.RequiresDetachRecovery)
            {
                CancelCharacterBuildPreparationNavigation(
                    panelInstanceId,
                    target,
                    "coordinator_not_settled");
                return false;
            }
            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : null;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : null;
            if (!string.IsNullOrEmpty(activePanel)
                || !string.IsNullOrEmpty(activeInstance))
            {
                CancelCharacterBuildPreparationNavigation(
                    panelInstanceId,
                    target,
                    "visual_not_idle");
                return false;
            }

            if (phase
                == CharacterBuildPreparationPhase.RollbackAfterSettle)
            {
                System.Threading.Timer expiredTimer;
                lock (_panelNavigationLifecycleLock)
                {
                    if (!_characterBuildPreparationNavigation.Pending
                        || _characterBuildPreparationNavigation.Phase
                            != CharacterBuildPreparationPhase.RollbackAfterSettle
                        || _characterBuildPreparationNavigation.Generation
                            != intentGeneration
                        || _characterBuildPreparationNavigation.LifecycleEpoch
                            != intentLifecycleEpoch
                        || intentLifecycleEpoch
                            != _panelNavigationLifecycleEpoch
                        || !string.Equals(
                            _characterBuildPreparationNavigation.PanelInstanceId,
                            panelInstanceId,
                            StringComparison.Ordinal)
                        || _characterBuildPreparationNavigation.Target
                            != target)
                    {
                        return false;
                    }
                    expiredTimer =
                        ClearCharacterBuildPreparationNavigationLocked();
                }
                if (expiredTimer != null) expiredTimer.Dispose();
                HandleCharacterBuildPreparationOpenFailure(
                    target,
                    "settle_timeout",
                    intentLifecycleEpoch);
                return true;
            }

            if (phase != CharacterBuildPreparationPhase.Armed)
                return false;

            Action beforeConsume =
                _beforeCharacterBuildPreparationNavigationConsumeForTests;
            if (beforeConsume != null)
                beforeConsume();

            string openRequestId =
                null;
            int generation =
                0;
            bool preflightArmed;
            string preflightFailureReason =
                "preflight_admission";
            int failedLifecycleEpoch =
                0;
            System.Threading.Timer armTimer;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_characterBuildPreparationNavigation.Pending
                    || _characterBuildPreparationNavigation.Phase
                        != CharacterBuildPreparationPhase.Armed
                    || _characterBuildPreparationNavigation.Generation
                        != intentGeneration
                    || _characterBuildPreparationNavigation.LifecycleEpoch
                        != intentLifecycleEpoch
                    || intentLifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || !string.Equals(
                        _characterBuildPreparationNavigation.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _characterBuildPreparationNavigation.Target
                        != target)
                {
                    return false;
                }
                if (_panelHost != null)
                    _panelHost.DiscardDeferredBarrierOpen();
                // End the arm phase before installing the target-specific wait. Both operations
                // are linearized by this same lifecycle lock, so the expired arm callback cannot
                // race the new target timer or observe an in-between externally visible state.
                armTimer =
                    ClearCharacterBuildPreparationNavigationLocked();
                switch (target)
                {
                    case CharacterBuildPreparationTarget.Skills:
                        preflightArmed =
                            TryBeginSkillOpenWait(
                                "character_build",
                                false,
                                out generation,
                                out openRequestId);
                        break;
                    case CharacterBuildPreparationTarget.Materials:
                        preflightArmed =
                            TryBeginMaterialOpenWait(
                                "character_build",
                                false,
                                out generation,
                                out openRequestId);
                        break;
                    case CharacterBuildPreparationTarget.Intelligence:
                        string baselinePanel;
                        string baselineInstance;
                        bool hasHostAdmission;
                        long hostAdmission;
                        if (!TryCapturePanelOpenBaseline(
                                out baselinePanel,
                                out baselineInstance,
                                out hasHostAdmission,
                                out hostAdmission)
                            || !hasHostAdmission
                            || !string.IsNullOrEmpty(baselinePanel)
                            || !string.IsNullOrEmpty(baselineInstance))
                        {
                            preflightArmed =
                                false;
                            break;
                        }
                        if (!TryArmPreparationChildReturnCapabilityLocked(
                                target))
                        {
                            preflightFailureReason =
                                "return_capability_busy";
                            preflightArmed =
                                false;
                            break;
                        }
                        try
                        {
                            preflightArmed =
                                OpenPanel(
                                    "intelligence",
                                    BuildIntelligenceProductionInitData()
                                        .ToString(Formatting.None),
                                    null,
                                    null,
                                    true,
                                    hostAdmission,
                                    true);
                            if (!preflightArmed)
                            {
                                preflightFailureReason =
                                    "exact_admission";
                            }
                        }
                        catch (Exception ex)
                        {
                            preflightArmed =
                                false;
                            preflightFailureReason =
                                "open_exception";
                            LogManager.Log(
                                "event=character_build_preparation_open_exception target=intelligence ex="
                                + ex.Message);
                        }
                        if (!preflightArmed)
                        {
                            System.Threading.Timer capabilityTimer =
                                ClearPreparationChildReturnLocked();
                            if (capabilityTimer != null)
                                capabilityTimer.Dispose();
                        }
                        break;
                    default:
                        preflightArmed = false;
                        break;
                }
                if (!preflightArmed)
                {
                    failedLifecycleEpoch =
                        intentLifecycleEpoch;
                }
            }
            if (armTimer != null) armTimer.Dispose();
            if (!preflightArmed)
            {
                LogManager.Log(
                    "event=character_build_preparation_open_failed target="
                    + CharacterBuildPreparationTargetName(target) + " "
                    + "reason=" + preflightFailureReason);
                HandleCharacterBuildPreparationOpenFailure(
                    target,
                    preflightFailureReason,
                    failedLifecycleEpoch);
                return true;
            }

            if (target
                == CharacterBuildPreparationTarget.Intelligence)
            {
                LogManager.Log(
                    "event=intelligence_panel_open_accepted source=character_build");
                return true;
            }

            if (target == CharacterBuildPreparationTarget.Skills)
            {
                LogManager.Log(
                    "event=skill_panel_open_requested source=character_build");
                bool skillIntentCurrent;
                if (!TrySendSkillPanelOpenCommandIfCurrent(
                        generation,
                        openRequestId,
                        out skillIntentCurrent))
                {
                    if (!skillIntentCurrent)
                        return true;
                    int lifecycleEpoch;
                    if (!CancelSkillOpenWait(
                            generation,
                            out lifecycleEpoch))
                    {
                        // A synchronous exact ACK (or a newer cancellation) already consumed the
                        // generation; a late false transport result must not report a contradiction.
                        return true;
                    }
                    LogManager.Log(
                        "event=skill_panel_open_failed source=character_build reason=preflight_send");
                    HandleCharacterBuildPreparationOpenFailure(
                        target,
                        "preflight_send",
                        lifecycleEpoch);
                }
                return true;
            }

            LogManager.Log(
                "event=material_panel_open_requested source=character_build");
            bool materialIntentCurrent;
            if (!TrySendMaterialPanelOpenCommandIfCurrent(
                    generation,
                    openRequestId,
                    out materialIntentCurrent))
            {
                if (!materialIntentCurrent)
                    return true;
                int lifecycleEpoch;
                if (!CancelMaterialOpenWait(
                        generation,
                        out lifecycleEpoch))
                {
                    // A synchronous exact ACK (or a newer cancellation) already consumed the
                    // generation; a late false transport result must not report a contradiction.
                    return true;
                }
                LogManager.Log(
                    "event=material_panel_open_failed source=character_build reason=preflight_send");
                HandleCharacterBuildPreparationOpenFailure(
                    target,
                    "preflight_send",
                    lifecycleEpoch);
            }
            return true;
        }

        internal bool TryCompleteCharacterBuildSkillsNavigation()
        {
            return TryCompleteCharacterBuildPreparationNavigation();
        }

        private System.Threading.Timer
            ClearCharacterBuildPreparationNavigationLocked()
        {
            return _characterBuildPreparationNavigation.Clear();
        }

        private void OnCharacterBuildPreparationNavigationTimeout(
            int generation,
            int lifecycleEpoch,
            string panelInstanceId,
            CharacterBuildPreparationTarget target)
        {
            System.Threading.Timer timer;
            bool rollbackNow = false;
            bool rollbackAfterSettle = false;
            bool preserveBuild = false;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_characterBuildPreparationNavigation.Pending
                    || _characterBuildPreparationNavigation.Phase
                        != CharacterBuildPreparationPhase.Armed
                    || _characterBuildPreparationNavigation.Generation
                        != generation
                    || _characterBuildPreparationNavigation.LifecycleEpoch
                        != lifecycleEpoch
                    || lifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || _characterBuildPreparationNavigation.Target
                        != target
                    || !string.Equals(
                        _characterBuildPreparationNavigation.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }

                CharacterBuildTask task =
                    _characterBuildTask;
                if (task != null
                    && task.RequiresDetachRecovery)
                {
                    // The destructive close has started but the coordinator still owns the exact
                    // binding. Retain only a rollback-after-settle phase; the timed-out target can
                    // no longer open, and the eventual settled callback can roll back once.
                    timer =
                        _characterBuildPreparationNavigation.Timer;
                    _characterBuildPreparationNavigation.Timer =
                        null;
                    _characterBuildPreparationNavigation.Phase =
                        CharacterBuildPreparationPhase.RollbackAfterSettle;
                    _characterBuildPreparationNavigation.Generation++;
                    rollbackAfterSettle = true;
                }
                else
                {
                    string activePanel =
                        _panelHost != null
                            ? _panelHost.ActivePanelName
                            : null;
                    string activeInstance =
                        _panelHost != null
                            ? _panelHost.ActivePanelInstanceId
                            : null;
                    bool hostIdle =
                        string.IsNullOrEmpty(activePanel)
                        && string.IsNullOrEmpty(activeInstance)
                        && (_panelHost == null
                            || _panelHost.IsIdleForTrackedOpen);
                    rollbackNow =
                        task != null
                        && !task.HasBoundPanel
                        && hostIdle;
                    preserveBuild =
                        task != null
                        && task.IsBoundTo(panelInstanceId)
                        && string.Equals(
                            activePanel,
                            "workbench",
                            StringComparison.Ordinal)
                        && string.Equals(
                            activeInstance,
                            panelInstanceId,
                            StringComparison.Ordinal);
                    timer =
                        ClearCharacterBuildPreparationNavigationLocked();
                }
            }
            if (timer != null) timer.Dispose();

            LogManager.Log(
                "event=character_build_preparation_navigation_timeout target="
                + CharacterBuildPreparationTargetName(target)
                + " panel_instance=" + panelInstanceId
                + " phase="
                + (rollbackAfterSettle
                    ? "rollback_after_settle"
                    : rollbackNow
                        ? "rollback_now"
                        : preserveBuild
                            ? "build_preserved"
                            : "cancelled"));
            if (rollbackAfterSettle)
                return;
            if (rollbackNow)
            {
                HandleCharacterBuildPreparationOpenFailure(
                    target,
                    "settle_timeout",
                    lifecycleEpoch);
                return;
            }
            if (preserveBuild)
            {
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"整备导航等待超时，角色构筑保持打开\"}");
            }
        }

        /// <summary>
        /// Arms the inverse Skills -> Character Build intent. The Host capability is consumed here,
        /// but the AS2 workbench preflight is withheld until both the exact Skills visual and every
        /// SkillTask write/reconcile/cleanup obligation have settled.
        /// </summary>
        internal bool TryArmSkillsCharacterBuildNavigation(
            string panelInstanceId)
        {
            if (string.IsNullOrEmpty(panelInstanceId)
                || _skillTask == null)
            {
                return false;
            }
            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : null;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : null;
            if (!string.Equals(activePanel, "skills", StringComparison.Ordinal)
                || !string.Equals(activeInstance, panelInstanceId, StringComparison.Ordinal))
            {
                return false;
            }

            lock (_panelNavigationLifecycleLock)
            {
                if (_pendingSkillsCharacterBuildNavigationInstance != null)
                {
                    return false;
                }
                _skillTask.BindPanelInstance(panelInstanceId);
                if (!_skillTask
                        .TryConsumeCharacterBuildReturnCapability(
                            panelInstanceId))
                {
                    return false;
                }
                int generation =
                    ++_skillsCharacterBuildNavigationGeneration;
                _pendingSkillsCharacterBuildNavigationInstance =
                    panelInstanceId;
                _skillsCharacterBuildNavigationTimer =
                    new System.Threading.Timer(
                        delegate
                        {
                            OnSkillsCharacterBuildNavigationTimeout(
                                generation,
                                panelInstanceId);
                        },
                        null,
                        Math.Max(
                            1,
                            SkillsCharacterBuildNavigationTimeoutMs),
                        System.Threading.Timeout.Infinite);
            }
            LogManager.Log(
                "event=skills_character_build_navigation_armed panel_instance="
                + panelInstanceId);
            return true;
        }

        internal bool CancelSkillsCharacterBuildNavigation(
            string panelInstanceId,
            string reason)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                if (string.IsNullOrEmpty(
                        _pendingSkillsCharacterBuildNavigationInstance)
                    || (!string.IsNullOrEmpty(panelInstanceId)
                        && !string.Equals(
                            _pendingSkillsCharacterBuildNavigationInstance,
                            panelInstanceId,
                            StringComparison.Ordinal)))
                {
                    return false;
                }
                panelInstanceId =
                    _pendingSkillsCharacterBuildNavigationInstance;
                timer =
                    ClearSkillsCharacterBuildNavigationLocked();
            }
            if (timer != null) timer.Dispose();
            LogManager.Log(
                "event=skills_character_build_navigation_cancelled panel_instance="
                + panelInstanceId + " reason="
                + (reason ?? "unknown"));
            return true;
        }

        internal bool TryCompleteSkillsCharacterBuildNavigation()
        {
            string panelInstanceId;
            lock (_panelNavigationLifecycleLock)
            {
                panelInstanceId =
                    _pendingSkillsCharacterBuildNavigationInstance;
                if (panelInstanceId == null) return false;
            }

            if (_skillTask == null)
            {
                CancelSkillsCharacterBuildNavigation(
                    panelInstanceId,
                    "coordinator_unavailable");
                return false;
            }
            if (!_skillTask.IsClosedAndSettled)
                return false;

            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : null;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : null;
            if (string.Equals(activePanel, "skills", StringComparison.Ordinal)
                && string.Equals(activeInstance, panelInstanceId, StringComparison.Ordinal))
            {
                return false;
            }
            if (!string.IsNullOrEmpty(activePanel)
                || !string.IsNullOrEmpty(activeInstance)
                || (_panelHost != null
                    && !_panelHost.IsIdleForTrackedOpen))
            {
                CancelSkillsCharacterBuildNavigation(
                    panelInstanceId,
                    "competing_panel");
                return false;
            }

            System.Threading.Timer timer;
            int generation;
            string openRequestId;
            bool preflightArmed;
            lock (_panelNavigationLifecycleLock)
            {
                if (!string.Equals(
                    _pendingSkillsCharacterBuildNavigationInstance,
                    panelInstanceId,
                    StringComparison.Ordinal))
                {
                    return false;
                }
                Action beforeConsume =
                    _beforeSkillsCharacterBuildNavigationConsumeForTests;
                if (beforeConsume != null)
                    beforeConsume();
                preflightArmed =
                    TryBeginNativeEquipmentBuildOpenWait(
                        "skills_return",
                        false,
                        out generation,
                        out openRequestId);
                timer =
                    ClearSkillsCharacterBuildNavigationLocked();
            }
            if (timer != null) timer.Dispose();

            LogManager.Log(
                "event=character_build_open_requested source=skills_return");
            if (!preflightArmed)
            {
                LogManager.Log(
                    "event=character_build_open_failed source=skills_return reason=preflight_busy");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"返回构筑失败，请从装备入口重试\"}");
                return true;
            }
            bool nativeIntentCurrent;
            if (!TrySendNativeEquipmentBuildPreflightIfCurrent(
                    generation,
                    openRequestId,
                    out nativeIntentCurrent))
            {
                if (!nativeIntentCurrent)
                    return true;
                if (!CancelNativeEquipmentBuildOpenWait(
                        generation))
                {
                    return true;
                }
                LogManager.Log(
                    "event=character_build_open_failed source=skills_return reason=preflight_send");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"返回构筑失败，请从装备入口重试\"}");
            }
            return true;
        }

        /// <summary>
        /// Starts a fresh Character Build session for the fixed Reward Inbox return edge. While
        /// the exact Loot binding is still active this preserves its inherited pause lease and
        /// prepares an in-place Host replacement; after a fallback close it reuses the same nonce
        /// preflight from PanelHost's idle baseline.
        /// </summary>
        internal bool TryOpenCharacterBuildAfterRewardInbox()
        {
            return TryOpenCharacterBuildAfterRewardInbox(null);
        }

        internal bool TryOpenCharacterBuildAfterRewardInbox(
            LootPanelCoordinator.Binding binding)
        {
            const string origin = "reward_inbox_return";
            if (binding != null
                && binding.SourceKind
                    != LootPanelCoordinator.RewardInboxSource)
            {
                return false;
            }
            if (!CanAdmitPanel(origin))
            {
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + origin + " reason=admission_closed");
                return false;
            }

            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : null;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : null;
            bool replacingActiveRewardInbox =
                _panelHost != null
                && _lootPanelCoordinator != null
                && string.Equals(
                    activePanel,
                    LootPanelCoordinator.PanelName,
                    StringComparison.Ordinal)
                && binding != null
                && string.Equals(
                    activeInstance,
                    binding.PanelInstanceId,
                    StringComparison.Ordinal)
                && _lootPanelCoordinator
                    .IsRewardInboxReplacementPendingExact(
                        binding.PanelInstanceId);
            bool reopeningAfterFallback =
                _panelHost != null
                && string.IsNullOrEmpty(activePanel)
                && string.IsNullOrEmpty(activeInstance)
                && _panelHost.IsIdleForTrackedOpen;
            if (!replacingActiveRewardInbox
                && !reopeningAfterFallback)
            {
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + origin + " reason=competing_panel");
                return false;
            }

            int generation;
            string openRequestId;
            if (!TryBeginNativeEquipmentBuildOpenWait(
                    origin,
                    false,
                    out generation,
                    out openRequestId))
            {
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + origin + " reason=preflight_busy");
                return false;
            }

            LogManager.Log(
                "event=character_build_open_requested source="
                + origin);
            bool intentCurrent;
            if (TrySendNativeEquipmentBuildPreflightIfCurrent(
                    generation,
                    openRequestId,
                    out intentCurrent))
            {
                return true;
            }
            if (!intentCurrent)
                return false;
            if (!CancelNativeEquipmentBuildOpenWait(generation))
                return false;

            LogManager.Log(
                "event=character_build_open_failed source="
                + origin + " reason=preflight_send");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"奖励已保存；返回角色构筑失败，请从装备入口重试\"}");
            return false;
        }

        private void OnSkillsCharacterBuildNavigationTimeout(
            int generation,
            string panelInstanceId)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                if (generation
                        != _skillsCharacterBuildNavigationGeneration
                    || !string.Equals(
                        _pendingSkillsCharacterBuildNavigationInstance,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                timer =
                    ClearSkillsCharacterBuildNavigationLocked();
            }
            if (timer != null) timer.Dispose();
            LogManager.Log(
                "event=skills_character_build_navigation_cancelled panel_instance="
                + panelInstanceId + " reason=settle_timeout");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"技能状态仍在结算，请从装备入口重新打开构筑\"}");
        }

        private System.Threading.Timer
            ClearSkillsCharacterBuildNavigationLocked()
        {
            _pendingSkillsCharacterBuildNavigationInstance =
                null;
            _skillsCharacterBuildNavigationGeneration++;
            System.Threading.Timer timer =
                _skillsCharacterBuildNavigationTimer;
            _skillsCharacterBuildNavigationTimer =
                null;
            return timer;
        }

        internal bool TryArmPreparationChildCharacterBuildNavigation(
            string panelName,
            string panelInstanceId)
        {
            if (!IsPreparationChildPanelName(panelName)
                || string.IsNullOrEmpty(panelInstanceId))
            {
                return false;
            }
            string activePanel =
                _panelHost != null
                    ? _panelHost.ActivePanelName
                    : null;
            string activeInstance =
                _panelHost != null
                    ? _panelHost.ActivePanelInstanceId
                    : null;
            if (!string.Equals(
                    activePanel,
                    panelName,
                    StringComparison.Ordinal)
                || !string.Equals(
                    activeInstance,
                    panelInstanceId,
                    StringComparison.Ordinal))
            {
                return false;
            }

            lock (_panelNavigationLifecycleLock)
            {
                if (_preparationChildReturn.Phase
                        != PreparationChildReturnPhase.Active
                    || _preparationChildReturn.LifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || !string.Equals(
                        _preparationChildReturn.PanelName,
                        panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _preparationChildReturn.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                int generation =
                    ++_preparationChildReturn.Generation;
                int lifecycleEpoch =
                    _preparationChildReturn.LifecycleEpoch;
                _preparationChildReturn.Phase =
                    PreparationChildReturnPhase.Returning;
                _preparationChildReturn.Timer =
                    new System.Threading.Timer(
                        delegate
                        {
                            OnPreparationChildCharacterBuildNavigationTimeout(
                                generation,
                                lifecycleEpoch,
                                panelName,
                                panelInstanceId);
                        },
                        null,
                        Math.Max(
                            1,
                            PreparationChildCharacterBuildNavigationTimeoutMs),
                        System.Threading.Timeout.Infinite);
            }
            LogManager.Log(
                "event=preparation_child_character_build_navigation_armed panel="
                + panelName + " panel_instance="
                + panelInstanceId);
            return true;
        }

        internal bool CancelPreparationChildCharacterBuildNavigation(
            string panelName,
            string panelInstanceId,
            string reason)
        {
            System.Threading.Timer timer;
            string boundPanel;
            string boundInstance;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_preparationChildReturn.Pending
                    || (!string.IsNullOrEmpty(panelName)
                        && !string.Equals(
                            _preparationChildReturn.PanelName,
                            panelName,
                            StringComparison.Ordinal))
                    || (!string.IsNullOrEmpty(panelInstanceId)
                        && !string.Equals(
                            _preparationChildReturn.PanelInstanceId,
                            panelInstanceId,
                            StringComparison.Ordinal)))
                {
                    return false;
                }
                boundPanel =
                    _preparationChildReturn.PanelName;
                boundInstance =
                    _preparationChildReturn.PanelInstanceId;
                timer =
                    ClearPreparationChildReturnLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=preparation_child_character_build_navigation_cancelled panel="
                + (boundPanel ?? "unknown")
                + " panel_instance="
                + (boundInstance ?? "unbound")
                + " reason=" + (reason ?? "unknown"));
            return true;
        }

        internal bool TryCompletePreparationChildCharacterBuildNavigation(
            string panelName,
            string panelInstanceId)
        {
            if (!IsPreparationChildPanelName(panelName)
                || string.IsNullOrEmpty(panelInstanceId))
            {
                return false;
            }
            lock (_panelNavigationLifecycleLock)
            {
                if (_preparationChildReturn.Phase
                        != PreparationChildReturnPhase.Returning
                    || _preparationChildReturn.LifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || !string.Equals(
                        _preparationChildReturn.PanelName,
                        panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _preparationChildReturn.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return false;
                }
            }

            string activePanel =
                _panelHost != null
                    ? _panelHost.ActivePanelName
                    : null;
            string activeInstance =
                _panelHost != null
                    ? _panelHost.ActivePanelInstanceId
                    : null;
            if (string.Equals(
                    activePanel,
                    panelName,
                    StringComparison.Ordinal)
                && string.Equals(
                    activeInstance,
                    panelInstanceId,
                    StringComparison.Ordinal))
            {
                return false;
            }
            if (!string.IsNullOrEmpty(activePanel)
                || !string.IsNullOrEmpty(activeInstance)
                || (_panelHost != null
                    && !_panelHost.IsIdleForTrackedOpen))
            {
                CancelPreparationChildCharacterBuildNavigation(
                    panelName,
                    panelInstanceId,
                    "competing_panel");
                return false;
            }

            System.Threading.Timer timer;
            int generation;
            string openRequestId;
            string origin =
                PreparationChildReturnOrigin(panelName);
            bool preflightArmed;
            lock (_panelNavigationLifecycleLock)
            {
                if (_preparationChildReturn.Phase
                        != PreparationChildReturnPhase.Returning
                    || _preparationChildReturn.LifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || !string.Equals(
                        _preparationChildReturn.PanelName,
                        panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _preparationChildReturn.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                timer =
                    ClearPreparationChildReturnLocked();
                preflightArmed =
                    TryBeginNativeEquipmentBuildOpenWait(
                        origin,
                        false,
                        out generation,
                        out openRequestId);
            }
            if (timer != null)
                timer.Dispose();

            LogManager.Log(
                "event=character_build_open_requested source="
                + origin);
            if (!preflightArmed)
            {
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + origin + " reason=preflight_busy");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"返回装备失败，请从装备入口重试\"}");
                return true;
            }
            bool nativeIntentCurrent;
            if (!TrySendNativeEquipmentBuildPreflightIfCurrent(
                    generation,
                    openRequestId,
                    out nativeIntentCurrent))
            {
                if (!nativeIntentCurrent)
                    return true;
                if (!CancelNativeEquipmentBuildOpenWait(
                        generation))
                {
                    return true;
                }
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + origin + " reason=preflight_send");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"返回装备失败，请从装备入口重试\"}");
            }
            return true;
        }

        private void
            OnPreparationChildCharacterBuildNavigationTimeout(
                int generation,
                int lifecycleEpoch,
                string panelName,
                string panelInstanceId)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                if (_preparationChildReturn.Phase
                        != PreparationChildReturnPhase.Returning
                    || _preparationChildReturn.Generation
                        != generation
                    || _preparationChildReturn.LifecycleEpoch
                        != lifecycleEpoch
                    || lifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || !string.Equals(
                        _preparationChildReturn.PanelName,
                        panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _preparationChildReturn.PanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                timer =
                    ClearPreparationChildReturnLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=preparation_child_character_build_navigation_cancelled panel="
                + panelName + " panel_instance="
                + panelInstanceId + " reason=visual_retire_timeout");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"返回装备超时，请从装备入口重试\"}");
        }

        private void HandleCharacterBuildPreparationOpenFailure(
            CharacterBuildPreparationTarget target,
            string reason,
            int lifecycleEpoch)
        {
            if (!IsCharacterBuildPreparationTargetEnabled(target))
            {
                LogManager.Log(
                    "event=character_build_preparation_open_failed target="
                    + CharacterBuildPreparationTargetName(target)
                    + " reason=" + (reason ?? "unknown")
                    + " gate=target_not_enabled");
                return;
            }
            bool superseded;
            if (TryStartCharacterBuildRollback(
                    reason,
                    lifecycleEpoch,
                    out superseded)
                || superseded)
            {
                return;
            }
            PostToWeb(
                target == CharacterBuildPreparationTarget.Materials
                    ? "{\"type\":\"toast\",\"text\":\"材料面板未打开；请从装备入口重新打开构筑\"}"
                    : target
                        == CharacterBuildPreparationTarget.Intelligence
                        ? "{\"type\":\"toast\",\"text\":\"情报面板未打开；请从装备入口重新打开构筑\"}"
                        : "{\"type\":\"toast\",\"text\":\"技能面板未打开；请从装备入口重新打开构筑\"}");
        }

        private bool TryStartCharacterBuildRollback(
            string reason,
            int expectedLifecycleEpoch,
            out bool superseded)
        {
            int generation;
            string openRequestId;
            lock (_panelNavigationLifecycleLock)
            {
                superseded =
                    expectedLifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || _skillOpenPending
                    || _materialOpen.Pending
                    || _nativeEquipmentBuildOpen.Pending
                    || _nativeEquipmentTuningOpen.Pending
                    || _characterBuildPreparationNavigation.Pending
                    || _pendingSkillsCharacterBuildNavigationInstance
                        != null
                    || _preparationChildReturn.Pending;
                if (superseded)
                {
                    LogManager.Log(
                        "event=character_build_rollback_skipped reason="
                        + (reason ?? "unknown")
                        + " gate=newer_navigation_intent");
                    return false;
                }
                string activePanel = _panelHost != null
                    ? _panelHost.ActivePanelName
                    : null;
                string activeInstance = _panelHost != null
                    ? _panelHost.ActivePanelInstanceId
                    : null;
                if (!string.IsNullOrEmpty(activePanel)
                    || !string.IsNullOrEmpty(activeInstance)
                    || (_panelHost != null
                        && !_panelHost.IsIdleForTrackedOpen)
                    || (_characterBuildTask != null
                        && _characterBuildTask.HasBoundPanel))
                {
                    LogManager.Log(
                        "event=character_build_rollback_skipped reason="
                        + (reason ?? "unknown")
                        + " gate=host_not_idle");
                    return false;
                }

                if (!TryBeginNativeEquipmentBuildOpenWait(
                        "skill_open_rollback",
                        false,
                        out generation,
                        out openRequestId))
                {
                    LogManager.Log(
                        "event=character_build_rollback_skipped reason="
                        + (reason ?? "unknown")
                        + " gate=preflight_busy");
                    return false;
                }
            }
            bool intentCurrent;
            if (TrySendNativeEquipmentBuildPreflightIfCurrent(
                    generation,
                    openRequestId,
                    out intentCurrent))
            {
                LogManager.Log(
                    "event=character_build_rollback_requested reason="
                    + (reason ?? "unknown"));
                return true;
            }
            if (!intentCurrent)
                return true;
            if (!CancelNativeEquipmentBuildOpenWait(
                    generation))
            {
                return true;
            }
            LogManager.Log(
                "event=character_build_rollback_failed reason="
                + (reason ?? "unknown")
                + " gate=preflight_send");
            return false;
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
                    LogManager.Log("[Router] WAREHOUSE clicked -> web inventory workbench");
                    OpenInventoryWorkbench("nativehud", "{\"profile\":\"battlebox\",\"view\":\"storage\"}");
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
                case "GAMESETTINGS": OpenSettingsPanel("nativehud_settings"); break;
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
                case "EQUIPMENT_TUNING":
                    RouteEquipmentTuning();
                    break;
                case "MATERIALS":
                    RouteMaterialUi();
                    break;
                case "INTELLIGENCE":
                    OpenPanel(
                        "intelligence",
                        BuildIntelligenceProductionInitData()
                            .ToString(Formatting.None));
                    break;
                case "SKILLS":
                    LogManager.Log("[Router] SKILLS clicked");
                    LogManager.Log("event=skill_panel_open_requested source=notch");
                    string skillOpenRequestId;
                    int skillOpenGeneration;
                    if (!TryBeginSkillOpenWait(
                            "notch",
                            true,
                            out skillOpenGeneration,
                            out skillOpenRequestId))
                    {
                        LogManager.Log(
                            "event=skill_panel_open_failed reason=host_not_idle");
                        PostToWeb(
                            "{\"type\":\"toast\",\"text\":\"请先关闭当前面板\"}");
                        break;
                    }
                    bool notchSkillIntentCurrent;
                    if (!TrySendSkillPanelOpenCommandIfCurrent(
                            skillOpenGeneration,
                            skillOpenRequestId,
                            out notchSkillIntentCurrent))
                    {
                        if (!notchSkillIntentCurrent)
                            break;
                        if (!CancelSkillOpenWait(
                                skillOpenGeneration))
                        {
                            break;
                        }
                        LogManager.Log("[Router] SKILLS skillPanelOpen preflight failed");
                        LogManager.Log("event=skill_panel_open_failed reason=preflight_send");
                        PostToWeb("{\"type\":\"toast\",\"text\":\"技能面板暂时不可用，请稍后重试\"}");
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
                case "BLACKMARKET_TEST":
                    {
                        // O1 是临时手动诊断入口，默认关闭。环境变量只决定是否把
                        // 只读 heartbeat capability 下发给当前 blackmarket document；
                        // 不改变面板业务、socket、pause、scene 或关闭语义。
                        bool softlockObservation =
                            WebOverlayForm.IsBlackMarketSoftlockObservationEnabled(
                                Environment.GetEnvironmentVariable(
                                    "CF7_BLACKMARKET_SOFTLOCK_OBSERVATION"));
                        OpenPanel(
                            "blackmarket",
                            "{\"mode\":\"dev\",\"source\":\"runtime\",\"shadowOnly\":true,\"debug\":true"
                                + (softlockObservation
                                    ? ",\"softlockObservation\":true"
                                    : "")
                                + "}");
                    }
                    break;
                case "WARLORD_TEST":
                    OpenPanel("warlord", "{\"mode\":\"phase-c-as2\",\"source\":\"runtime\",\"seed\":\"warlord-demo-seed-001\",\"preset\":\"standard\",\"difficulty\":\"normal\",\"mapTheme\":\"desert\",\"battleAuthority\":\"as2\",\"productionWrites\":false}");
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
            string openRequestId)
        {
            if (string.IsNullOrEmpty(panelName)) return;
            string safeSource = string.IsNullOrEmpty(source) ? "as2_request" : source;
            bool exactNativeTuningSource =
                string.Equals(
                    safeSource,
                    "nativehud_equipment_tuning",
                    StringComparison.Ordinal);
            bool carriesPendingNativeTuningNonce =
                IsPendingNativeEquipmentTuningOpenRequestId(
                    openRequestId);
            bool exactMaterialSource =
                string.Equals(
                    safeSource,
                    "nativehud_materials",
                    StringComparison.Ordinal);
            bool carriesMaterialNonce =
                IsMaterialOpenRequestIdCandidate(
                    openRequestId);
            if ((exactNativeTuningSource
                    || carriesPendingNativeTuningNonce)
                && !string.Equals(
                    panelName,
                    "workbench",
                    StringComparison.Ordinal))
            {
                RejectPendingNativeEquipmentTuningPanelRequest(
                    "panel_contract");
                return;
            }
            if ((exactMaterialSource
                    || carriesMaterialNonce)
                && !string.Equals(
                    panelName,
                    "crafting",
                    StringComparison.Ordinal))
            {
                if (!string.IsNullOrEmpty(openRequestId))
                {
                    RejectPendingMaterialPanelRequest(
                        "panel_contract");
                }
                LogManager.Log(
                    "event=material_panel_open_rejected reason=panel_contract"
                    + " panel=" + panelName
                    + " source=" + safeSource);
                return;
            }
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
                OpenInventoryWorkbench(
                    safeSource,
                    initDataExtrasJson,
                    string.Equals(
                        panelName,
                        "workbench",
                        StringComparison.Ordinal),
                    openRequestId);
                return;
            }
            if (string.Equals(panelName, "npcshop", StringComparison.OrdinalIgnoreCase))
            {
                OpenNpcShopPanel(safeSource, initDataExtrasJson);
                return;
            }
            if (string.Equals(panelName, "crafting", StringComparison.OrdinalIgnoreCase))
            {
                OpenCraftingPanel(
                    safeSource,
                    initDataExtrasJson,
                    string.Equals(
                        panelName,
                        "crafting",
                        StringComparison.Ordinal),
                    openRequestId);
                return;
            }
            if (string.Equals(panelName, "hairdresser", StringComparison.OrdinalIgnoreCase))
            {
                OpenHairdresserPanel(safeSource);
                return;
            }
            if (string.Equals(panelName, "settings", StringComparison.OrdinalIgnoreCase))
            {
                OpenSettingsPanel(safeSource);
                return;
            }
            if (string.Equals(panelName, "skills", StringComparison.OrdinalIgnoreCase))
            {
                OpenSkillsPanel(
                    safeSource,
                    initDataExtrasJson,
                    openRequestId);
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
            bool exactPanelName = true,
            string openRequestId = null)
        {
            bool exactNativeTuningSource =
                string.Equals(
                    source,
                    "nativehud_equipment_tuning",
                    StringComparison.Ordinal);
            bool carriesPendingNativeTuningNonce =
                IsPendingNativeEquipmentTuningOpenRequestId(
                    openRequestId);
            bool nativeTuningIngress =
                exactNativeTuningSource
                || carriesPendingNativeTuningNonce;
            if (!nativeTuningIngress
                && TryRejectUncorrelatedNativeEquipmentTuningPanelRequest())
            {
                return false;
            }
            if (!string.Equals(
                    source,
                    "nativehud_equipment",
                    StringComparison.Ordinal))
            {
                CancelPendingNativeEquipmentBuildOpenIntent(
                    "competing_workbench");
            }
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
                    if (nativeTuningIngress)
                    {
                        RejectPendingNativeEquipmentTuningPanelRequest(
                            "init_data_contract");
                    }
                    return false;
                }
            }
            if (!string.Equals(profile, "warehouse", StringComparison.Ordinal)
                && !string.Equals(profile, "battlebox", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected profile=" + profile);
                if (nativeTuningIngress)
                {
                    RejectPendingNativeEquipmentTuningPanelRequest(
                        "profile_contract");
                }
                return false;
            }
            if (!string.Equals(view, "storage", StringComparison.Ordinal)
                && !string.Equals(view, "tuning", StringComparison.Ordinal)
                && !string.Equals(view, "build", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected view=" + view);
                if (nativeTuningIngress)
                {
                    RejectPendingNativeEquipmentTuningPanelRequest(
                        "view_contract");
                }
                return false;
            }
            if (view == "tuning" && !string.Equals(profile, "battlebox", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenInventoryWorkbench rejected tuning profile=" + profile);
                if (nativeTuningIngress)
                {
                    RejectPendingNativeEquipmentTuningPanelRequest(
                        "profile_contract");
                }
                return false;
            }
            bool exactNativeTuning =
                view == "tuning"
                && string.Equals(
                    profile,
                    "battlebox",
                    StringComparison.Ordinal)
                && exactNativeTuningSource;
            bool exactNativeTuningInit =
                exactNativeTuning
                && extras != null
                && extras.Count == 2
                && extras["profile"] != null
                && extras["profile"].Type
                    == JTokenType.String
                && extras["view"] != null
                && extras["view"].Type
                    == JTokenType.String;
            if (nativeTuningIngress
                && !exactNativeTuning)
            {
                RejectPendingNativeEquipmentTuningPanelRequest(
                    "tuple_contract");
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
            bool exactNativeBuild =
                view == "build"
                && string.Equals(
                    source,
                    "nativehud_equipment",
                    StringComparison.Ordinal);
            bool exactNativeBuildInit =
                exactNativeBuild
                && extras != null
                && extras.Count == 2
                && extras["profile"] != null
                && extras["profile"].Type
                    == JTokenType.String
                && extras["view"] != null
                && extras["view"].Type
                    == JTokenType.String;

            if (!exactNativeBuild
                && !exactNativeTuning
                && openRequestId != null)
            {
                LogManager.Log(
                    "event=character_build_open_rejected source="
                    + (source ?? "unknown")
                    + " reason=unexpected_open_request_id");
                return false;
            }
            if (string.Equals(
                    source,
                    "nativehud_equipment",
                    StringComparison.Ordinal)
                && !exactNativeBuild)
            {
                // A legitimate storage/tuning request from the same source is a newer workbench
                // intent and must invalidate any older native-build preflight.
                CancelPendingNativeEquipmentBuildOpenIntent(
                    "competing_native_workbench");
            }

            var initData = new JObject
            {
                ["mode"] = "runtime",
                ["profile"] = profile,
                ["view"] = view,
                ["source"] = source,
                ["debug"] = false
            };
            if (_preparationNavigationV1
                && string.Equals(
                    view,
                    "build",
                    StringComparison.Ordinal))
            {
                initData["preparationNavigationV1"] = true;
            }

            bool opened;
            if (exactNativeTuning)
            {
                if (!exactPanelName
                    || !exactNativeTuningInit)
                {
                    RejectPendingNativeEquipmentTuningPanelRequest(
                        !exactPanelName
                            ? "panel_contract"
                            : "init_data_contract");
                    return false;
                }

                string rejectionReason;
                bool hasHostAdmission;
                long hostAdmission;
                int lifecycleEpoch;
                if (!TryConsumeNativeEquipmentTuningOpenWait(
                        openRequestId,
                        out rejectionReason,
                        out hasHostAdmission,
                        out hostAdmission,
                        out lifecycleEpoch))
                {
                    LogManager.Log(
                        "event=equipment_tuning_open_rejected source=nativehud_equipment_tuning reason="
                        + (rejectionReason ?? "unknown"));
                    if (string.Equals(
                            rejectionReason,
                            "missing_preflight",
                            StringComparison.Ordinal)
                        && IsSuccessfulNativeEquipmentTuningDuplicate(
                            openRequestId))
                    {
                        LogManager.Log(
                            "event=equipment_tuning_open_duplicate_ignored source=nativehud_equipment_tuning reason=already_active_bound");
                        return false;
                    }
                    NotifyNativeEquipmentTuningOpenFailure(
                        rejectionReason);
                    return false;
                }
                lock (_panelNavigationLifecycleLock)
                {
                    if (lifecycleEpoch
                        != _panelNavigationLifecycleEpoch)
                    {
                        NotifyNativeEquipmentTuningOpenFailure(
                            "lifecycle_epoch");
                        return false;
                    }
                    opened =
                        OpenPanel(
                            "workbench",
                            initData.ToString(
                                Formatting.None),
                            null,
                            null,
                            hasHostAdmission,
                            hostAdmission);
                }
            }
            else if (exactNativeBuild)
            {
                string rejectionReason =
                    null;
                string openOrigin =
                    null;
                string baselinePanel =
                    null;
                string baselineInstance =
                    null;
                bool hasHostAdmission =
                    false;
                long hostAdmission =
                    0;
                int lifecycleEpoch =
                    0;
                bool replaceRewardInbox =
                    false;
                lock (_panelNavigationLifecycleLock)
                {
                    if (_nativeEquipmentBuildOpen.Pending)
                    {
                        baselinePanel =
                            _nativeEquipmentBuildOpen.BaselinePanel;
                        baselineInstance =
                            _nativeEquipmentBuildOpen.BaselineInstance;
                    }
                    if (!exactPanelName
                        || !exactNativeBuildInit
                        || !TryConsumeNativeEquipmentBuildOpenWait(
                            openRequestId,
                            out openOrigin,
                            out rejectionReason,
                            out hasHostAdmission,
                            out hostAdmission,
                            out lifecycleEpoch))
                    {
                        LogManager.Log(
                            "event=character_build_open_rejected source=nativehud_equipment reason="
                            + (!exactPanelName
                                ? "panel_contract"
                                : !exactNativeBuildInit
                                    ? "init_data_contract"
                                    : rejectionReason));
                        return false;
                    }
                    if (string.Equals(
                            openOrigin,
                            "skills_return",
                            StringComparison.Ordinal)
                        || string.Equals(
                            openOrigin,
                            "skill_open_rollback",
                            StringComparison.Ordinal)
                        || string.Equals(
                            openOrigin,
                            "materials_return",
                            StringComparison.Ordinal)
                        || string.Equals(
                            openOrigin,
                            "intelligence_return",
                            StringComparison.Ordinal))
                    {
                        string returnFocusAction;
                        if (!TryNormalizeCharacterBuildReturnFocusAction(
                                _preparationNavigationV1
                                    ? "preparation-menu"
                                    : "skills",
                                out returnFocusAction))
                        {
                            return false;
                        }
                        initData["navigationOrigin"] =
                            openOrigin;
                        initData["returnFocusAction"] =
                            returnFocusAction;
                    }
                    replaceRewardInbox =
                        string.Equals(
                            openOrigin,
                            "reward_inbox_return",
                            StringComparison.Ordinal)
                        && string.Equals(
                            baselinePanel,
                            LootPanelCoordinator.PanelName,
                            StringComparison.Ordinal)
                        && !string.IsNullOrEmpty(
                            baselineInstance);
                    if (replaceRewardInbox)
                    {
                        initData["navigationOrigin"] =
                            openOrigin;
                    }
                    if (lifecycleEpoch
                        != _panelNavigationLifecycleEpoch)
                    {
                        return false;
                    }
                    opened = replaceRewardInbox
                        ? false
                        : OpenPanel(
                            "workbench",
                            initData.ToString(
                                Formatting.None),
                            null,
                            null,
                            hasHostAdmission,
                            hostAdmission);
                }
                if (replaceRewardInbox)
                {
                    opened =
                        TryReplaceRewardInboxWithCharacterBuild(
                            baselineInstance,
                            initData,
                            lifecycleEpoch);
                }
            }
            else
            {
                opened =
                    OpenPanel(
                        "workbench",
                        initData.ToString(
                            Formatting.None));
            }
            if (!opened
                && exactNativeBuild)
            {
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + (initData.Value<string>(
                        "navigationOrigin")
                        ?? "nativehud_equipment")
                    + " reason=host_gate");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"装备面板被当前操作阻止，请稍后重试\"}");
            }
            else if (!opened
                && exactNativeTuning)
            {
                LogManager.Log(
                    "event=equipment_tuning_open_failed source=nativehud_equipment_tuning reason=host_gate");
                NotifyNativeEquipmentTuningOpenFailure(
                    "host_gate");
            }
            else if (opened
                && exactNativeTuning)
            {
                RememberSuccessfulNativeEquipmentTuningOpen(
                    openRequestId);
            }
            return opened;
        }

        private bool TryReplaceRewardInboxWithCharacterBuild(
            string sourcePanelInstanceId,
            JObject initData,
            int lifecycleEpoch)
        {
            LootPanelCoordinator coordinator =
                _lootPanelCoordinator;
            PanelHostController host =
                _panelHost;
            if (coordinator == null
                || host == null
                || initData == null
                || !coordinator
                    .IsRewardInboxReplacementPendingExact(
                        sourcePanelInstanceId))
            {
                return false;
            }

            string targetPanelInstanceId;
            try
            {
                targetPanelInstanceId =
                    OpaqueIdGenerator.Create("panel");
            }
            catch
            {
                targetPanelInstanceId = null;
            }
            if (string.IsNullOrEmpty(targetPanelInstanceId))
            {
                coordinator
                    .CancelRewardInboxReplacementAndCloseExact(
                        sourcePanelInstanceId);
                return false;
            }

            var plan = new PreparedPanelReplace(
                "workbench",
                targetPanelInstanceId,
                initData.ToString(Formatting.None),
                delegate
                {
                    coordinator
                        .CompleteRewardInboxReplacementExact(
                            sourcePanelInstanceId);
                },
                delegate
                {
                    coordinator
                        .CancelRewardInboxReplacementAndCloseExact(
                            sourcePanelInstanceId);
                });
            bool queued = host.TryReplacePanelExact(
                LootPanelCoordinator.PanelName,
                sourcePanelInstanceId,
                plan,
                delegate
                {
                    lock (_panelNavigationLifecycleLock)
                    {
                        return lifecycleEpoch
                                == _panelNavigationLifecycleEpoch
                            && (_characterBuildTask == null
                                || !_characterBuildTask.HasBoundPanel)
                            && coordinator
                                .IsRewardInboxReplacementPendingExact(
                                    sourcePanelInstanceId);
                    }
                },
                delegate(
                    PanelHostController.ExactReplaceOutcome outcome)
                {
                    LogManager.Log(
                        "event=reward_inbox_character_build_replace outcome="
                        + outcome.ToString());
                });
            if (!queued)
            {
                LogManager.Log(
                    "event=reward_inbox_character_build_replace outcome=not_queued");
            }
            return queued;
        }

        private void OpenNpcShopPanel(string source, string initDataExtrasJson)
        {
            if (string.IsNullOrEmpty(initDataExtrasJson)) return;
            try
            {
                JObject extras = JObject.Parse(initDataExtrasJson);
                if (extras.Count != 1
                    || extras.Property("shopId") == null
                    || extras["shopId"].Type != JTokenType.String)
                {
                    LogManager.Log(
                        "[Router] OpenNpcShopPanel rejected non-whitelisted extras");
                    return;
                }
                string shopId = extras.Value<string>("shopId");
                if (string.IsNullOrEmpty(shopId)
                    || shopId.Length > 80
                    || string.IsNullOrWhiteSpace(shopId)
                    || string.Equals(
                        shopId.Trim(),
                        "undefined",
                        StringComparison.OrdinalIgnoreCase)) return;
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

        private void OpenCraftingPanel(
            string source,
            string initDataExtrasJson,
            bool exactPanelName,
            string openRequestId)
        {
            bool exactMaterialSource =
                string.Equals(
                    source,
                    "nativehud_materials",
                    StringComparison.Ordinal);
            bool carriesOpenRequestId =
                openRequestId != null;
            if (string.IsNullOrEmpty(initDataExtrasJson))
            {
                if (carriesOpenRequestId)
                {
                    RejectPendingMaterialPanelRequest(
                        "init_data_contract");
                }
                LogManager.Log(
                    "[Router] OpenCraftingPanel rejected missing extras");
                return;
            }
            try
            {
                JObject extras = JObject.Parse(initDataExtrasJson);
                JToken viewToken =
                    extras["view"];
                string view =
                    viewToken != null
                    && viewToken.Type == JTokenType.String
                        ? viewToken.Value<string>()
                        : null;
                bool materialIngress =
                    exactMaterialSource
                    || carriesOpenRequestId
                    || viewToken != null;
                if (materialIngress)
                {
                    bool exactMaterialContract =
                        exactPanelName
                        && exactMaterialSource
                        && extras.Count == 1
                        && string.Equals(
                            view,
                            "materials",
                            StringComparison.Ordinal);
                    if (!exactMaterialContract)
                    {
                        // A nonce-bearing near match is a target failure. A missing-nonce
                        // legacy envelope never consumes/replaces an armed/current material wait.
                        if (carriesOpenRequestId)
                        {
                            RejectPendingMaterialPanelRequest(
                                "tuple_contract");
                        }
                        LogManager.Log(
                            "event=material_panel_open_rejected reason=tuple_contract"
                            + " source=" + source
                            + " view=" + (view ?? "<null>"));
                        return;
                    }

                    if (openRequestId == null)
                    {
                        if (HasArmedMaterialIntentOrOpenWait())
                        {
                            LogManager.Log(
                                "event=material_panel_open_rejected reason=missing_open_request_id"
                                + " pending_preserved=true");
                            PostToWeb(
                                "{\"type\":\"toast\",\"text\":\"正在打开材料，请稍候\"}");
                            return;
                        }
                        var legacyMaterialInitData =
                            BuildMaterialsInitData();
                        OpenPanel(
                            "crafting",
                            legacyMaterialInitData.ToString(
                                Formatting.None));
                        LogManager.Log(
                            "event=material_panel_open_accepted source=legacy_nativehud");
                        return;
                    }

                    string rejectionReason;
                    string pendingOrigin;
                    bool hasHostAdmission;
                    long hostAdmission;
                    int lifecycleEpoch;
                    bool recoverCharacterBuild;
                    if (!TryAdmitMaterialPanelRequest(
                            source,
                            view,
                            openRequestId,
                            out rejectionReason,
                            out pendingOrigin,
                            out hasHostAdmission,
                            out hostAdmission,
                            out lifecycleEpoch,
                            out recoverCharacterBuild))
                    {
                        LogManager.Log(
                            "event=material_panel_open_rejected reason="
                            + (rejectionReason ?? "unknown")
                            + " source=" + source
                            + " pending_origin="
                            + (pendingOrigin ?? "none"));
                        if (recoverCharacterBuild)
                        {
                            HandleCharacterBuildPreparationOpenFailure(
                                CharacterBuildPreparationTarget.Materials,
                                "material_request_"
                                    + (rejectionReason
                                        ?? "rejected"),
                                lifecycleEpoch);
                        }
                        else if (pendingOrigin != null)
                        {
                            NotifyMaterialOpenFailure(
                                rejectionReason);
                        }
                        return;
                    }

                    JObject materialInitData =
                        BuildMaterialsInitData();
                    bool opened;
                    System.Threading.Timer failedCapabilityTimer =
                        null;
                    lock (_panelNavigationLifecycleLock)
                    {
                        bool needsReturnCapability =
                            string.Equals(
                                pendingOrigin,
                                "character_build",
                                StringComparison.Ordinal);
                        bool capabilityArmed =
                            !needsReturnCapability
                            || TryArmPreparationChildReturnCapabilityLocked(
                                CharacterBuildPreparationTarget.Materials);
                        opened =
                            lifecycleEpoch
                                == _panelNavigationLifecycleEpoch
                            && capabilityArmed
                            && OpenPanel(
                                "crafting",
                                materialInitData.ToString(
                                    Formatting.None),
                                null,
                                null,
                                hasHostAdmission,
                                hostAdmission,
                                needsReturnCapability);
                        if (!opened
                            && needsReturnCapability
                            && capabilityArmed)
                        {
                            failedCapabilityTimer =
                                ClearPreparationChildReturnLocked();
                        }
                    }
                    if (failedCapabilityTimer != null)
                        failedCapabilityTimer.Dispose();
                    if (!opened)
                    {
                        LogManager.Log(
                            "event=material_panel_open_failed reason=host_gate source="
                            + (pendingOrigin ?? source));
                        if (string.Equals(
                                pendingOrigin,
                                "character_build",
                                StringComparison.Ordinal))
                        {
                            HandleCharacterBuildPreparationOpenFailure(
                                CharacterBuildPreparationTarget.Materials,
                                "material_host_gate",
                                lifecycleEpoch);
                        }
                        else
                        {
                            NotifyMaterialOpenFailure(
                                "host_gate");
                        }
                        return;
                    }
                    LogManager.Log(
                        "event=material_panel_open_accepted source="
                        + (pendingOrigin ?? source));
                    return;
                }
                if (HasArmedMaterialIntentOrOpenWait())
                {
                    LogManager.Log(
                        "event=crafting_panel_open_rejected reason=material_navigation_pending");
                    return;
                }
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
                if (carriesOpenRequestId)
                {
                    RejectPendingMaterialPanelRequest(
                        "init_data_contract");
                }
            }
        }

        private static JObject BuildMaterialsInitData()
        {
            return new JObject
            {
                ["mode"] = "runtime",
                ["view"] = "materials",
                ["source"] = "nativehud_materials",
                ["debug"] = false
            };
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

        private void OpenSettingsPanel(string source)
        {
            if (!string.Equals(source, "as2_settings_request", StringComparison.Ordinal)
                && !string.Equals(source, "nativehud_settings", StringComparison.Ordinal))
            {
                LogManager.Log("[Router] OpenSettingsPanel rejected source=" + source);
                return;
            }
            var initData = new JObject
            {
                ["source"] = source,
                ["dev"] = false
            };
            OpenPanel("settings", initData.ToString(Formatting.None));
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
            string openRequestId)
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
            bool hasHostAdmission;
            long hostAdmission;
            int lifecycleEpoch;
            bool recoverCharacterBuild;
            if (!TryAdmitSkillPanelRequest(
                    source,
                    view,
                    openRequestId,
                    out rejectionReason,
                    out pendingOrigin,
                    out hasHostAdmission,
                    out hostAdmission,
                    out lifecycleEpoch,
                    out recoverCharacterBuild))
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
                if (recoverCharacterBuild)
                {
                    HandleCharacterBuildPreparationOpenFailure(
                        CharacterBuildPreparationTarget.Skills,
                        "skill_request_"
                            + (rejectionReason
                                ?? "rejected"),
                        lifecycleEpoch);
                }
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
            if (string.Equals(
                    pendingOrigin,
                    "character_build",
                    StringComparison.Ordinal)
                && initData.Value<string>("view")
                    == "manage")
            {
                initData["canReturnCharacterBuild"] =
                    true;
            }
            bool opened;
            lock (_panelNavigationLifecycleLock)
            {
                opened =
                    lifecycleEpoch
                        == _panelNavigationLifecycleEpoch
                    && OpenPanel(
                        "skills",
                        initData.ToString(
                            Formatting.None),
                        null,
                        null,
                        hasHostAdmission,
                        hostAdmission);
            }
            if (!opened)
            {
                if (_skillTask != null)
                    _skillTask
                        .DiscardUnboundPanelInitContext();
                LogManager.Log(
                    "event=skill_panel_open_failed reason=host_gate view="
                    + initData.Value<string>("view")
                    + " source="
                    + (pendingOrigin
                        ?? source));
                if (string.Equals(
                        pendingOrigin,
                        "character_build",
                        StringComparison.Ordinal))
                {
                    HandleCharacterBuildPreparationOpenFailure(
                        CharacterBuildPreparationTarget.Skills,
                        "skill_host_gate",
                        lifecycleEpoch);
                }
                return;
            }
            LogManager.Log(
                "event=skill_panel_open_accepted view="
                + initData.Value<string>("view")
                + " source="
                + (pendingOrigin ?? source));
        }

        internal bool RebindSkillsToManage(string expectedPanelInstanceId, string focusSkillKey)
        {
            string activeName = _panelHost != null ? _panelHost.ActivePanelName : null;
            string activeInstance = _panelHost != null ? _panelHost.ActivePanelInstanceId : null;
            if (_skillTask == null || activeName != "skills" || string.IsNullOrEmpty(activeInstance)
                || !string.Equals(activeInstance, expectedPanelInstanceId, StringComparison.Ordinal)
                || !IsPresentationSkillKey(focusSkillKey)
                || !_skillTask.TrySuspendTrainerForManage(activeInstance))
            {
                LogManager.Log("[Router] rejected stale/malformed skills manage rebind");
                return false;
            }
            if (!OpenPanel("skills", BuildSkillsManageInitData(focusSkillKey).ToString(Formatting.None)))
            {
                _skillTask.DiscardUnboundPanelInitContext();
                LogManager.Log("event=skill_panel_rebind_failed from=trainer to=manage");
                return false;
            }
            LogManager.Log("event=skill_panel_rebound from=trainer to=manage");
            return true;
        }

        internal bool RebindSkillsToTrainer(string expectedPanelInstanceId, string focusSkillKey)
        {
            string activeName = _panelHost != null ? _panelHost.ActivePanelName : null;
            string activeInstance = _panelHost != null ? _panelHost.ActivePanelInstanceId : null;
            string trainerSession;
            if (_skillTask == null || activeName != "skills" || string.IsNullOrEmpty(activeInstance)
                || !string.Equals(activeInstance, expectedPanelInstanceId, StringComparison.Ordinal)
                || !IsPresentationSkillKey(focusSkillKey)
                || !_skillTask.TryGetTrainerReturnSession(activeInstance, out trainerSession))
            {
                LogManager.Log("[Router] rejected stale/malformed skills trainer return rebind");
                return false;
            }
            if (!OpenPanel("skills", BuildSkillsTrainerReturnInitData(trainerSession, focusSkillKey).ToString(Formatting.None)))
            {
                _skillTask.DiscardUnboundPanelInitContext();
                LogManager.Log("event=skill_panel_rebind_failed from=manage to=trainer");
                return false;
            }
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
        /// 统一 panel 打开入口：_panelHost.OpenPanel（含 backdrop/EX_STYLE/HUD-suspend 序列）。
        /// _panelHost 未注入时拒绝打开。
        /// </summary>
        private bool OpenPanel(string panelName, string initDataJson)
        {
            return OpenPanel(panelName, initDataJson, null, null);
        }

        /// <summary>
        /// returnTo 版本：关闭本 panel 后自动 reopen returnToPanel。仅 PanelHostController 路径支持。
        /// </summary>
        private bool OpenPanel(
            string panelName,
            string initDataJson,
            string returnToPanel,
            string returnToInitDataJson,
            bool requireOpenAdmission = false,
            long openAdmission = 0,
            bool preservePendingPreparationChildReturn = false)
        {
            if (!preservePendingPreparationChildReturn)
            {
                CancelUnboundPreparationChildReturnForOrdinaryOpen(
                    panelName);
            }
            if (!CanAdmitPanel("open:" + (panelName ?? "<null>")))
                return false;
            if (!string.Equals(
                    panelName,
                    "skills",
                    StringComparison.Ordinal))
            {
                CancelPendingSkillOpenIntent(
                    "competing_panel");
                CancelSkillsCharacterBuildNavigation(
                    null,
                    "competing_panel");
            }
            if (!string.Equals(
                    panelName,
                    "workbench",
                    StringComparison.Ordinal))
            {
                CancelPendingNativeEquipmentBuildOpenIntent(
                    "competing_panel");
                CancelPendingNativeEquipmentTuningOpenIntent(
                    "competing_panel");
            }
            if (!string.Equals(
                    panelName,
                    "crafting",
                    StringComparison.Ordinal))
            {
                CancelPendingMaterialOpenIntent(
                    "competing_panel");
            }
            string currentPanel = _panelHost != null ? _panelHost.ActivePanelName : null;
            string currentInstance = _panelHost != null ? _panelHost.ActivePanelInstanceId
                : null;
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
            if (_panelHost != null)
            {
                bool accepted;
                if (requireOpenAdmission)
                {
                    accepted = _panelHost.TryOpenPanelFromAdmission(
                        openAdmission,
                        currentPanel,
                        currentInstance,
                        panelName,
                        initDataJson,
                        returnToPanel,
                        returnToInitDataJson);
                }
                else
                {
                    accepted = _panelHost.TryOpenPanel(
                        panelName,
                        initDataJson,
                        returnToPanel,
                        returnToInitDataJson);
                }
                // Host admission only reserves the queued command. Geometry can still be
                // explicit-invalid when the UI-thread pump executes (for example during
                // minimize). PanelHost is therefore the sole pause publisher: it asserts the
                // lease only after valid geometry and owns failure cleanup.
                if (accepted)
                {
                    ClearSuccessfulNativeEquipmentTuningOpenProof();
                }
                return accepted;
            }
            // PanelHost 未注入（仅装配前窗口期可达）→ 拒绝打开，不再走 PostToWeb panel_cmd 兜底。
            return false;
        }

        private static bool IsMaterialOpenRequestIdCandidate(
            string value)
        {
            return !string.IsNullOrEmpty(value)
                && value.StartsWith(
                    "material.open.",
                    StringComparison.Ordinal);
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

        private bool RouteMaterialUi()
        {
            if (!CanAdmitPanel("materials"))
                return false;
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
                return false;
            }

            bool activeVisual =
                _panelHost != null
                && !_panelHost.IsIdleForTrackedOpen;
            if (activeVisual)
            {
                string active = _panelHost.ActivePanelName;
                LogManager.Log(
                    "[Router] MATERIALS rejected: active or pending Web panel visual="
                    + (active ?? "<unknown>"));
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"请先关闭当前面板\"}");
                return false;
            }

            int generation;
            string openRequestId;
            if (!TryBeginMaterialOpenWait(
                    "nativehud_materials",
                    true,
                    out generation,
                    out openRequestId))
            {
                LogManager.Log(
                    "[Router] MATERIALS rejected: material preflight admission failed");
                PostToWeb(
                    "{\"type\":\"toast\",\"text\":\"材料面板暂时不可用\"}");
                return false;
            }

            bool delivered = false;
            bool intentCurrent = false;
            try
            {
                delivered =
                    TrySendMaterialPanelOpenCommandIfCurrent(
                        generation,
                        openRequestId,
                        out intentCurrent);
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[Router] MATERIALS openMaterialUI send threw: "
                    + ex.Message);
            }
            if (delivered
                || WasMaterialOpenAdmitted(
                    generation,
                    openRequestId))
                return true;

            int lifecycleEpoch;
            if (!CancelMaterialOpenWait(
                    generation,
                    out lifecycleEpoch))
            {
                return false;
            }

            LogManager.Log(
                "[Router] MATERIALS openMaterialUI was not delivered");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"材料面板暂时不可用\"}");
            return false;
        }

        private void RouteEquipmentUi()
        {
            if (!CanAdmitPanel("equipment"))
            {
                CancelNativeEquipmentBuildOpenWait();
                return;
            }
            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : null;
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : null;
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
                    "{\"type\":\"panel_esc\",\"reason\":\"toggle\"}");
                return;
            }

            LogManager.Log(
                "event=character_build_open_requested source=nativehud_equipment");
            int generation;
            string openRequestId;
            if (!TryBeginNativeEquipmentBuildOpenWait(
                    "nativehud_equipment",
                    true,
                    out generation,
                    out openRequestId))
            {
                LogManager.Log(
                    "event=character_build_open_suppressed source=nativehud_equipment reason=pending");
                return;
            }
            bool nativeIntentCurrent;
            if (TrySendNativeEquipmentBuildPreflightIfCurrent(
                    generation,
                    openRequestId,
                    out nativeIntentCurrent))
                return;
            if (!nativeIntentCurrent)
                return;

            if (!CancelNativeEquipmentBuildOpenWait(
                    generation))
            {
                return;
            }
            LogManager.Log(
                "event=character_build_open_failed source=nativehud_equipment reason=preflight_send");
            PostToWeb(
                "{\"type\":\"toast\",\"text\":\"装备面板暂时不可用，请稍后重试\"}");
        }

        private void RouteEquipmentTuning()
        {
            if (!CanAdmitPanel("equipment_tuning"))
            {
                CancelPendingNativeEquipmentTuningOpenIntent(
                    "host_admission");
                NotifyNativeEquipmentTuningOpenFailure(
                    "host_admission");
                return;
            }
            LogManager.Log(
                "event=equipment_tuning_open_requested source=nativehud_equipment_tuning");
            int generation;
            string openRequestId;
            if (!TryBeginNativeEquipmentTuningOpenWait(
                    out generation,
                    out openRequestId))
            {
                LogManager.Log(
                    "event=equipment_tuning_open_rejected source=nativehud_equipment_tuning reason=host_not_idle");
                NotifyNativeEquipmentTuningOpenFailure(
                    "host_not_idle");
                return;
            }

            bool intentCurrent;
            if (TrySendNativeEquipmentTuningPreflightIfCurrent(
                    generation,
                    openRequestId,
                    out intentCurrent))
            {
                return;
            }
            if (!intentCurrent)
                return;
            if (!CancelNativeEquipmentTuningOpenWait(
                    generation))
            {
                return;
            }
            LogManager.Log(
                "event=equipment_tuning_open_failed source=nativehud_equipment_tuning reason=preflight_send");
            NotifyNativeEquipmentTuningOpenFailure(
                "preflight_send");
        }

        private bool TrySendNativeEquipmentTuningPreflight(
            string openRequestId)
        {
            if (!IsOpaqueToken(openRequestId))
                return false;
            string payload =
                "{\"task\":\"cmd\",\"action\":\"openInventoryWorkbench\","
                + "\"profile\":\"battlebox\",\"view\":\"tuning\","
                + "\"source\":\"nativehud_equipment_tuning\","
                + "\"openRequestId\":\""
                + EscapeJsonString(openRequestId)
                + "\"}\0";
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

        private bool TrySendNativeEquipmentTuningPreflightIfCurrent(
            int generation,
            string openRequestId,
            out bool intentCurrent)
        {
            lock (_panelNavigationLifecycleLock)
            {
                intentCurrent =
                    _nativeEquipmentTuningOpen.Pending
                    && generation
                        == _nativeEquipmentTuningOpen.Generation
                    && string.Equals(
                        openRequestId,
                        _nativeEquipmentTuningOpen.RequestId,
                        StringComparison.Ordinal);
                if (!intentCurrent)
                    return false;
                return TrySendNativeEquipmentTuningPreflight(
                    openRequestId);
            }
        }

        private bool TryBeginNativeEquipmentTuningOpenWait(
            out int generation,
            out string openRequestId)
        {
            generation = 0;
            openRequestId = null;
            lock (_panelNavigationLifecycleLock)
            {
                if (_nativeEquipmentTuningOpen.Pending
                    || _nativeEquipmentBuildOpen.Pending
                    || _skillOpenPending
                    || _materialOpen.Pending
                    || _characterBuildPreparationNavigation.Pending
                    || _pendingSkillsCharacterBuildNavigationInstance
                        != null
                    || _preparationChildReturn.Pending
                    || (_equipmentTuningTask != null
                        && _equipmentTuningTask.HasBoundPanel))
                {
                    return false;
                }

                string activePanel;
                string activeInstance;
                bool hasHostAdmission;
                long hostAdmission;
                if (!TryCapturePanelOpenBaseline(
                        out activePanel,
                        out activeInstance,
                        out hasHostAdmission,
                        out hostAdmission)
                    || !string.IsNullOrEmpty(activePanel)
                    || !string.IsNullOrEmpty(activeInstance))
                {
                    return false;
                }

                _panelNavigationLifecycleEpoch++;
                ArmNativeEquipmentWorkbenchOpenWaitLocked(
                    _nativeEquipmentTuningOpen,
                    "tuning.open.",
                    "nativehud_equipment_tuning",
                    activePanel,
                    activeInstance,
                    hasHostAdmission,
                    hostAdmission,
                    NativeEquipmentTuningOpenTimeoutMs,
                    OnNativeEquipmentTuningOpenTimeout,
                    out generation,
                    out openRequestId);
            }
            return true;
        }

        private bool TryConsumeNativeEquipmentWorkbenchOpenWait(
            FixedPanelOpenWait wait,
            string openRequestId,
            bool clearOnNonceMismatch,
            out string origin,
            out string rejectionReason,
            out bool hasHostAdmission,
            out long hostAdmission,
            out int lifecycleEpoch)
        {
            System.Threading.Timer timer =
                null;
            lock (_panelNavigationLifecycleLock)
            {
                origin =
                    wait.Pending
                        ? wait.Origin
                        : null;
                hasHostAdmission =
                    false;
                hostAdmission =
                    0;
                lifecycleEpoch =
                    0;
                if (!wait.Pending)
                {
                    rejectionReason =
                        "missing_preflight";
                    return false;
                }
                if (!IsOpaqueToken(openRequestId)
                    || !string.Equals(
                        openRequestId,
                        wait.RequestId,
                        StringComparison.Ordinal))
                {
                    if (clearOnNonceMismatch)
                        timer = wait.Clear();
                    rejectionReason =
                        "preflight_nonce";
                }
                else
                {
                    string activePanel =
                        _panelHost != null
                            ? _panelHost.ActivePanelName
                            : null;
                    string activeInstance =
                        _panelHost != null
                            ? _panelHost.ActivePanelInstanceId
                            : null;
                    if (wait.LifecycleEpoch
                            != _panelNavigationLifecycleEpoch)
                    {
                        timer = wait.Clear();
                        rejectionReason =
                            "lifecycle_epoch";
                    }
                    else if (!string.Equals(
                            activePanel,
                            wait.BaselinePanel,
                            StringComparison.Ordinal)
                        || !string.Equals(
                            activeInstance,
                            wait.BaselineInstance,
                            StringComparison.Ordinal))
                    {
                        timer = wait.Clear();
                        rejectionReason =
                            "competing_panel";
                    }
                    else if (wait.HasHostAdmission
                        && (_panelHost == null
                            || !_panelHost
                                .IsOpenAdmissionCurrent(
                                    wait.HostAdmission,
                                    wait.BaselinePanel,
                                    wait.BaselineInstance)))
                    {
                        timer = wait.Clear();
                        rejectionReason =
                            "competing_host_lifecycle";
                    }
                    else
                    {
                        hasHostAdmission =
                            wait.HasHostAdmission;
                        hostAdmission =
                            wait.HostAdmission;
                        lifecycleEpoch =
                            wait.LifecycleEpoch;
                        timer = wait.Clear();
                        rejectionReason =
                            null;
                    }
                }
            }
            if (timer != null)
                timer.Dispose();
            return rejectionReason == null;
        }

        private bool TryConsumeNativeEquipmentTuningOpenWait(
            string openRequestId,
            out string rejectionReason,
            out bool hasHostAdmission,
            out long hostAdmission,
            out int lifecycleEpoch)
        {
            string ignoredOrigin;
            return TryConsumeNativeEquipmentWorkbenchOpenWait(
                _nativeEquipmentTuningOpen,
                openRequestId,
                true,
                out ignoredOrigin,
                out rejectionReason,
                out hasHostAdmission,
                out hostAdmission,
                out lifecycleEpoch);
        }

        private void OnNativeEquipmentTuningOpenTimeout(
            int generation,
            int lifecycleEpoch)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_nativeEquipmentTuningOpen.Pending
                    || generation
                        != _nativeEquipmentTuningOpen.Generation
                    || lifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || lifecycleEpoch
                        != _nativeEquipmentTuningOpen.LifecycleEpoch)
                {
                    return;
                }
                timer =
                    ClearNativeEquipmentTuningOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=equipment_tuning_open_failed source=nativehud_equipment_tuning reason=panel_request_timeout");
            NotifyNativeEquipmentTuningOpenFailure(
                "panel_request_timeout");
        }

        private bool CancelNativeEquipmentTuningOpenWait(
            int expectedGeneration = 0)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_nativeEquipmentTuningOpen.Pending
                    || (expectedGeneration != 0
                        && expectedGeneration
                            != _nativeEquipmentTuningOpen.Generation))
                {
                    return false;
                }
                timer =
                    ClearNativeEquipmentTuningOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            return true;
        }

        private bool IsPendingNativeEquipmentTuningOpenRequestId(
            string openRequestId)
        {
            lock (_panelNavigationLifecycleLock)
            {
                return _nativeEquipmentTuningOpen.Pending
                    && string.Equals(
                        openRequestId,
                        _nativeEquipmentTuningOpen.RequestId,
                        StringComparison.Ordinal);
            }
        }

        internal bool CancelPendingNativeEquipmentTuningOpenIntent(
            string reason)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_nativeEquipmentTuningOpen.Pending)
                    return false;
                timer =
                    ClearNativeEquipmentTuningOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=equipment_tuning_open_cancelled source=nativehud_equipment_tuning reason="
                + (reason ?? "unknown"));
            return true;
        }

        private bool TryRejectUncorrelatedNativeEquipmentTuningPanelRequest()
        {
            if (!CancelPendingNativeEquipmentTuningOpenIntent(
                    "uncorrelated_workbench"))
            {
                return false;
            }
            LogManager.Log(
                "event=equipment_tuning_open_rejected source=nativehud_equipment_tuning reason=uncorrelated_workbench pending_cleared=true");
            NotifyNativeEquipmentTuningOpenFailure(
                "uncorrelated_workbench");
            return true;
        }

        private void RememberSuccessfulNativeEquipmentTuningOpen(
            string openRequestId)
        {
            lock (_panelNavigationLifecycleLock)
            {
                _lastSuccessfulNativeEquipmentTuningOpenRequestId =
                    openRequestId;
            }
        }

        private void ClearSuccessfulNativeEquipmentTuningOpenProof()
        {
            lock (_panelNavigationLifecycleLock)
            {
                ClearSuccessfulNativeEquipmentTuningOpenProofLocked();
            }
        }

        private void ClearSuccessfulNativeEquipmentTuningOpenProofLocked()
        {
            _lastSuccessfulNativeEquipmentTuningOpenRequestId =
                null;
        }

        private bool IsSuccessfulNativeEquipmentTuningDuplicate(
            string openRequestId)
        {
            lock (_panelNavigationLifecycleLock)
            {
                if (!string.Equals(
                        openRequestId,
                        _lastSuccessfulNativeEquipmentTuningOpenRequestId,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                string activePanel =
                    _panelHost != null
                        ? _panelHost.ActivePanelName
                        : null;
                string activeInstance =
                    _panelHost != null
                        ? _panelHost.ActivePanelInstanceId
                        : null;
                if (!string.Equals(
                        activePanel,
                        "workbench",
                        StringComparison.Ordinal)
                    || string.IsNullOrEmpty(
                        activeInstance)
                    || _equipmentTuningTask == null
                    || !_equipmentTuningTask.HasBoundPanel
                    || !string.Equals(
                        _equipmentTuningTask.PanelInstanceId,
                        activeInstance,
                        StringComparison.Ordinal))
                {
                    return false;
                }
                return true;
            }
        }

        internal bool RejectPendingNativeEquipmentTuningPanelRequest(
            string reason)
        {
            bool cleared =
                CancelPendingNativeEquipmentTuningOpenIntent(
                    reason);
            LogManager.Log(
                "event=equipment_tuning_open_rejected source=nativehud_equipment_tuning reason="
                + (reason ?? "unknown")
                + " pending_cleared="
                + (cleared ? "true" : "false"));
            NotifyNativeEquipmentTuningOpenFailure(
                reason);
            return cleared;
        }

        private void NotifyNativeEquipmentTuningOpenFailure(
            string reason)
        {
            string text =
                string.Equals(
                    reason,
                    "host_not_idle",
                    StringComparison.Ordinal)
                || string.Equals(
                    reason,
                    "competing_panel",
                    StringComparison.Ordinal)
                    ? "请先关闭当前面板或等待当前操作完成"
                    : string.Equals(
                        reason,
                        "uncorrelated_workbench",
                        StringComparison.Ordinal)
                        ? "当前操作发生冲突，请重试"
                        : string.Equals(
                            reason,
                            "missing_preflight",
                            StringComparison.Ordinal)
                            ? "装备调制请求已处理或过期"
                    : string.Equals(
                        reason,
                        "panel_request_timeout",
                        StringComparison.Ordinal)
                        ? "装备调制服务未就绪，请稍后重试"
                        : "装备调制未打开，请重试";
            PostToWeb(
                new JObject
                {
                    ["type"] = "toast",
                    ["text"] = text
                }.ToString(Formatting.None));
        }

        private bool TrySendNativeEquipmentBuildPreflight(
            string openRequestId)
        {
            if (!IsOpaqueToken(openRequestId))
                return false;
            string payload =
                "{\"task\":\"cmd\",\"action\":\"openInventoryWorkbench\","
                + "\"profile\":\"battlebox\",\"view\":\"build\","
                + "\"source\":\"nativehud_equipment\","
                + "\"openRequestId\":\""
                + EscapeJsonString(openRequestId)
                + "\"}\0";
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

        private bool TrySendNativeEquipmentBuildPreflightIfCurrent(
            int generation,
            string openRequestId,
            out bool intentCurrent)
        {
            lock (_panelNavigationLifecycleLock)
            {
                intentCurrent =
                    _nativeEquipmentBuildOpen.Pending
                    && generation
                        == _nativeEquipmentBuildOpen.Generation
                    && string.Equals(
                        openRequestId,
                        _nativeEquipmentBuildOpen.RequestId,
                        StringComparison.Ordinal);
                if (!intentCurrent)
                    return false;
                return TrySendNativeEquipmentBuildPreflight(
                    openRequestId);
            }
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

        private bool TryCapturePanelOpenBaseline(
            out string activePanel,
            out string activeInstance,
            out bool hasHostAdmission,
            out long hostAdmission)
        {
            hasHostAdmission = _panelHost != null;
            hostAdmission = 0;
            if (_panelHost != null)
            {
                return _panelHost.TryCaptureOpenAdmission(
                    out hostAdmission,
                    out activePanel,
                    out activeInstance);
            }
            activePanel = null;
            activeInstance = null;
            return true;
        }

        private void ArmNativeEquipmentWorkbenchOpenWaitLocked(
            FixedPanelOpenWait wait,
            string requestIdPrefix,
            string origin,
            string activePanel,
            string activeInstance,
            bool hasHostAdmission,
            long hostAdmission,
            int timeoutMs,
            Action<int, int> onTimeout,
            out int generation,
            out string openRequestId)
        {
            generation =
                ++wait.Generation;
            openRequestId =
                requestIdPrefix
                + generation.ToString("x")
                + "."
                + Guid.NewGuid().ToString("N");
            wait.Pending =
                true;
            wait.RequestId =
                openRequestId;
            wait.Origin =
                origin;
            wait.BaselinePanel =
                activePanel;
            wait.BaselineInstance =
                activeInstance;
            wait.HasHostAdmission =
                hasHostAdmission;
            wait.HostAdmission =
                hostAdmission;
            wait.LifecycleEpoch =
                _panelNavigationLifecycleEpoch;
            int timerGeneration =
                generation;
            int timerLifecycleEpoch =
                wait.LifecycleEpoch;
            wait.Timer =
                new System.Threading.Timer(
                    delegate
                    {
                        onTimeout(
                            timerGeneration,
                            timerLifecycleEpoch);
                    },
                    null,
                    Math.Max(
                        1,
                        timeoutMs),
                    System.Threading.Timeout.Infinite);
        }

        private bool TryBeginNativeEquipmentBuildOpenWait(
            string origin,
            bool isDirectUserIntent,
            out int generation,
            out string openRequestId)
        {
            generation = 0;
            openRequestId = null;
            System.Threading.Timer cancelledSkillTimer =
                null;
            System.Threading.Timer cancelledMaterialTimer =
                null;
            System.Threading.Timer supersededForwardTimer =
                null;
            System.Threading.Timer supersededReverseTimer =
                null;
            System.Threading.Timer supersededPreparationChildTimer =
                null;
            lock (_panelNavigationLifecycleLock)
            {
                if (_nativeEquipmentBuildOpen.Pending
                    || _nativeEquipmentTuningOpen.Pending
                    || (!isDirectUserIntent
                        && (_materialOpen.Pending
                            || _preparationChildReturn.Pending)))
                    return false;

                string activePanel;
                string activeInstance;
                bool hasHostAdmission;
                long hostAdmission;
                if (!TryCapturePanelOpenBaseline(
                        out activePanel,
                        out activeInstance,
                        out hasHostAdmission,
                        out hostAdmission))
                {
                    bool capturedRewardReplacement =
                        string.Equals(
                            origin,
                            "reward_inbox_return",
                            StringComparison.Ordinal)
                        && _panelHost != null
                        && _panelHost
                            .TryCaptureExactReplaceBaseline(
                                out activePanel,
                                out activeInstance);
                    if (!capturedRewardReplacement)
                        return false;
                    hasHostAdmission = false;
                    hostAdmission = 0;
                }

                if (isDirectUserIntent)
                {
                    // A direct user action is newer than either half-completed cross-panel
                    // navigation.  Advance the shared epoch so a timeout/rollback already in
                    // flight cannot recreate the superseded intent.
                    _panelNavigationLifecycleEpoch++;
                    if (_characterBuildPreparationNavigation.Pending)
                    {
                        supersededForwardTimer =
                            ClearCharacterBuildPreparationNavigationLocked();
                    }
                    if (_pendingSkillsCharacterBuildNavigationInstance
                        != null)
                    {
                        supersededReverseTimer =
                            ClearSkillsCharacterBuildNavigationLocked();
                    }
                    if (_preparationChildReturn.Pending)
                    {
                        supersededPreparationChildTimer =
                            ClearPreparationChildReturnLocked();
                    }
                }

                // A newer native-build intent wins over an older Skills preflight.
                if (_skillOpenPending)
                    cancelledSkillTimer =
                        ClearSkillOpenWaitLocked();
                if (isDirectUserIntent
                    && _materialOpen.Pending)
                {
                    cancelledMaterialTimer =
                        ClearMaterialOpenWaitLocked();
                }

                ArmNativeEquipmentWorkbenchOpenWaitLocked(
                    _nativeEquipmentBuildOpen,
                    "workbench.open.",
                    string.IsNullOrEmpty(origin)
                        ? "unknown"
                        : origin,
                    activePanel,
                    activeInstance,
                    hasHostAdmission,
                    hostAdmission,
                    NativeEquipmentBuildOpenTimeoutMs,
                    OnNativeEquipmentBuildOpenTimeout,
                    out generation,
                    out openRequestId);
            }
            if (cancelledSkillTimer != null)
                cancelledSkillTimer.Dispose();
            if (cancelledMaterialTimer != null)
                cancelledMaterialTimer.Dispose();
            if (supersededForwardTimer != null)
                supersededForwardTimer.Dispose();
            if (supersededReverseTimer != null)
                supersededReverseTimer.Dispose();
            if (supersededPreparationChildTimer != null)
                supersededPreparationChildTimer.Dispose();
            return true;
        }

        private bool TryConsumeNativeEquipmentBuildOpenWait(
            string openRequestId,
            out string origin,
            out string rejectionReason,
            out bool hasHostAdmission,
            out long hostAdmission,
            out int lifecycleEpoch)
        {
            return TryConsumeNativeEquipmentWorkbenchOpenWait(
                _nativeEquipmentBuildOpen,
                openRequestId,
                false,
                out origin,
                out rejectionReason,
                out hasHostAdmission,
                out hostAdmission,
                out lifecycleEpoch);
        }

        private void OnNativeEquipmentBuildOpenTimeout(
            int generation,
            int lifecycleEpoch)
        {
            System.Threading.Timer timer;
            string activePanel;
            string origin;
            string baselinePanel;
            string baselineInstance;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_nativeEquipmentBuildOpen.Pending
                    || generation
                        != _nativeEquipmentBuildOpen.Generation
                    || lifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || lifecycleEpoch
                        != _nativeEquipmentBuildOpen.LifecycleEpoch)
                {
                    return;
                }
                activePanel =
                    _panelHost != null
                        ? _panelHost.ActivePanelName
                        : null;
                origin =
                    _nativeEquipmentBuildOpen.Origin;
                baselinePanel =
                    _nativeEquipmentBuildOpen.BaselinePanel;
                baselineInstance =
                    _nativeEquipmentBuildOpen.BaselineInstance;
                timer =
                    ClearNativeEquipmentBuildOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            if (string.Equals(
                    origin,
                    "reward_inbox_return",
                    StringComparison.Ordinal)
                && string.Equals(
                    baselinePanel,
                    LootPanelCoordinator.PanelName,
                    StringComparison.Ordinal)
                && _lootPanelCoordinator != null
                && _lootPanelCoordinator
                    .CancelRewardInboxReplacementAndCloseExact(
                        baselineInstance))
            {
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + origin
                    + " reason=panel_request_timeout fallback=loot_close");
                return;
            }
            if (!string.IsNullOrEmpty(activePanel))
            {
                LogManager.Log(
                    "event=character_build_open_failed source="
                    + (origin ?? "unknown")
                    + " "
                    + "reason=panel_request_timeout active_panel="
                    + activePanel
                    + " toast=suppressed");
                return;
            }
            LogManager.Log(
                "event=character_build_open_failed source="
                + (origin ?? "unknown")
                + " reason=panel_request_timeout");
            PostToWeb(
                string.Equals(
                    origin,
                    "skills_return",
                    StringComparison.Ordinal)
                    ? "{\"type\":\"toast\",\"text\":\"返回构筑失败，请从装备入口重试\"}"
                    : string.Equals(
                        origin,
                        "materials_return",
                        StringComparison.Ordinal)
                        || string.Equals(
                            origin,
                            "intelligence_return",
                            StringComparison.Ordinal)
                        ? "{\"type\":\"toast\",\"text\":\"返回装备失败，请从装备入口重试\"}"
                    : "{\"type\":\"toast\",\"text\":\"装备服务未就绪，请稍后重试\"}");
        }

        private bool CancelNativeEquipmentBuildOpenWait(
            int expectedGeneration = 0)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_nativeEquipmentBuildOpen.Pending
                    || (expectedGeneration != 0
                        && expectedGeneration
                            != _nativeEquipmentBuildOpen.Generation))
                {
                    return false;
                }
                timer =
                    ClearNativeEquipmentBuildOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            return true;
        }

        internal bool CancelPendingNativeEquipmentBuildOpenIntent(
            string reason)
        {
            System.Threading.Timer timer;
            string origin;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_nativeEquipmentBuildOpen.Pending)
                    return false;
                origin =
                    _nativeEquipmentBuildOpen.Origin;
                timer =
                    ClearNativeEquipmentBuildOpenWaitLocked();
            }
            if (timer != null) timer.Dispose();
            LogManager.Log(
                "event=character_build_open_cancelled source="
                + (origin ?? "unknown")
                + " reason=" + (reason ?? "unknown"));
            return true;
        }

        internal void CancelAllPanelNavigationIntents(
            string reason)
        {
            System.Threading.Timer skillTimer =
                null;
            System.Threading.Timer nativeTimer =
                null;
            System.Threading.Timer tuningTimer =
                null;
            System.Threading.Timer materialTimer =
                null;
            System.Threading.Timer forwardTimer =
                null;
            System.Threading.Timer reverseTimer =
                null;
            System.Threading.Timer preparationChildTimer =
                null;
            string skillOrigin =
                null;
            string nativeOrigin =
                null;
            bool tuningPending =
                false;
            string materialOrigin =
                null;
            string forwardInstance =
                null;
            string forwardTarget =
                null;
            string reverseInstance =
                null;
            string preparationChildPanel =
                null;
            string preparationChildInstance =
                null;
            MaterialShopCharacterCapsule materialShopCapsule =
                null;
            lock (_panelNavigationLifecycleLock)
            {
                // This increment is the linearization barrier: any delayed transition carrying an
                // older epoch must fail rather than creating a fresh wait after cancellation.
                _panelNavigationLifecycleEpoch++;
                if (_skillOpenPending)
                {
                    skillOrigin =
                        _skillOpenOrigin;
                    skillTimer =
                        ClearSkillOpenWaitLocked();
                }
                if (_nativeEquipmentBuildOpen.Pending)
                {
                    nativeOrigin =
                        _nativeEquipmentBuildOpen.Origin;
                    nativeTimer =
                        ClearNativeEquipmentBuildOpenWaitLocked();
                }
                if (_nativeEquipmentTuningOpen.Pending)
                {
                    tuningPending =
                        true;
                    tuningTimer =
                        ClearNativeEquipmentTuningOpenWaitLocked();
                }
                if (_materialOpen.Pending)
                {
                    materialOrigin =
                        _materialOpen.Origin;
                    materialTimer =
                        ClearMaterialOpenWaitLocked();
                }
                ClearSuccessfulNativeEquipmentTuningOpenProofLocked();
                if (_characterBuildPreparationNavigation.Pending)
                {
                    forwardInstance =
                        _characterBuildPreparationNavigation.PanelInstanceId;
                    forwardTarget =
                        CharacterBuildPreparationTargetName(
                            _characterBuildPreparationNavigation.Target);
                    forwardTimer =
                        ClearCharacterBuildPreparationNavigationLocked();
                }
                reverseInstance =
                    _pendingSkillsCharacterBuildNavigationInstance;
                if (reverseInstance != null)
                    reverseTimer =
                        ClearSkillsCharacterBuildNavigationLocked();
                if (_preparationChildReturn.Pending)
                {
                    preparationChildPanel =
                        _preparationChildReturn.PanelName;
                    preparationChildInstance =
                        _preparationChildReturn.PanelInstanceId;
                    preparationChildTimer =
                        ClearPreparationChildReturnLocked();
                }
                materialShopCapsule =
                    _materialShopCharacterCapsule;
                if (IsMaterialShopCharacterCommitPermittedLocked(
                        materialShopCapsule))
                {
                    materialShopCapsule = null;
                }
                else
                {
                    _materialShopCharacterCapsule =
                        null;
                    if (materialShopCapsule != null)
                        materialShopCapsule.Phase =
                            MaterialShopCharacterCapsulePhase.Consumed;
                }
            }
            if (skillTimer != null) skillTimer.Dispose();
            if (nativeTimer != null) nativeTimer.Dispose();
            if (tuningTimer != null) tuningTimer.Dispose();
            if (materialTimer != null) materialTimer.Dispose();
            if (forwardTimer != null) forwardTimer.Dispose();
            if (reverseTimer != null) reverseTimer.Dispose();
            if (preparationChildTimer != null)
                preparationChildTimer.Dispose();
            if (skillOrigin != null)
            {
                LogManager.Log(
                    "event=skill_panel_open_cancelled reason="
                    + (reason ?? "unknown")
                    + " source=" + skillOrigin);
            }
            if (nativeOrigin != null)
            {
                LogManager.Log(
                    "event=character_build_open_cancelled source="
                    + nativeOrigin + " reason="
                    + (reason ?? "unknown"));
            }
            if (tuningPending)
            {
                LogManager.Log(
                    "event=equipment_tuning_open_cancelled source=nativehud_equipment_tuning reason="
                    + (reason ?? "unknown"));
            }
            if (materialOrigin != null)
            {
                LogManager.Log(
                    "event=material_panel_open_cancelled source="
                    + materialOrigin + " reason="
                    + (reason ?? "unknown"));
            }
            if (forwardInstance != null)
            {
                LogManager.Log(
                    "event=character_build_preparation_navigation_cancelled target="
                    + (forwardTarget ?? "unknown")
                    + " panel_instance=" + forwardInstance + " reason="
                    + (reason ?? "unknown"));
            }
            if (reverseInstance != null)
            {
                LogManager.Log(
                    "event=skills_character_build_navigation_cancelled panel_instance="
                    + reverseInstance + " reason="
                    + (reason ?? "unknown"));
            }
            if (preparationChildPanel != null)
            {
                LogManager.Log(
                    "event=preparation_child_character_build_navigation_cancelled panel="
                    + preparationChildPanel
                    + " panel_instance="
                    + (preparationChildInstance ?? "unbound")
                    + " reason=" + (reason ?? "unknown"));
            }
            if (materialShopCapsule != null)
            {
                LogManager.Log(
                    "event=material_shop_character_capsule_cancelled reason="
                    + (reason ?? "unknown"));
            }
        }

        private System.Threading.Timer ClearNativeEquipmentBuildOpenWaitLocked()
        {
            return _nativeEquipmentBuildOpen.Clear();
        }

        private System.Threading.Timer ClearNativeEquipmentTuningOpenWaitLocked()
        {
            return _nativeEquipmentTuningOpen.Clear();
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

        private bool TrySendMaterialPanelOpenCommand(
            string openRequestId)
        {
            if (!IsOpaqueToken(openRequestId))
                return false;
            string payload =
                "{\"task\":\"cmd\",\"action\":\"openMaterialUI\","
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

        private bool TrySendMaterialPanelOpenCommandIfCurrent(
            int generation,
            string openRequestId,
            out bool intentCurrent)
        {
            lock (_panelNavigationLifecycleLock)
            {
                intentCurrent =
                    _materialOpen.Pending
                    && generation
                        == _materialOpen.Generation
                    && string.Equals(
                        openRequestId,
                        _materialOpen.RequestId,
                        StringComparison.Ordinal);
                if (!intentCurrent)
                    return false;
                return TrySendMaterialPanelOpenCommand(
                    openRequestId);
            }
        }

        private bool TryBeginMaterialOpenWait(
            string origin,
            bool isDirectUserIntent,
            out int generation,
            out string openRequestId)
        {
            System.Threading.Timer previousMaterialTimer =
                null;
            System.Threading.Timer cancelledSkillTimer =
                null;
            System.Threading.Timer cancelledNativeTimer =
                null;
            System.Threading.Timer supersededForwardTimer =
                null;
            System.Threading.Timer supersededReverseTimer =
                null;
            System.Threading.Timer supersededPreparationChildTimer =
                null;
            generation =
                0;
            openRequestId =
                null;
            lock (_panelNavigationLifecycleLock)
            {
                if (_nativeEquipmentTuningOpen.Pending)
                    return false;
                if (!isDirectUserIntent
                    && (_materialOpen.Pending
                        || _skillOpenPending
                        || _nativeEquipmentBuildOpen.Pending
                        || _preparationChildReturn.Pending))
                {
                    return false;
                }

                string activePanel;
                string activeInstance;
                bool hasHostAdmission;
                long hostAdmission;
                if (!TryCapturePanelOpenBaseline(
                        out activePanel,
                        out activeInstance,
                        out hasHostAdmission,
                        out hostAdmission)
                    || !string.IsNullOrEmpty(activePanel)
                    || !string.IsNullOrEmpty(activeInstance))
                {
                    return false;
                }

                if (isDirectUserIntent)
                {
                    _panelNavigationLifecycleEpoch++;
                    if (_characterBuildPreparationNavigation.Pending)
                    {
                        supersededForwardTimer =
                            ClearCharacterBuildPreparationNavigationLocked();
                    }
                    if (_pendingSkillsCharacterBuildNavigationInstance
                        != null)
                    {
                        supersededReverseTimer =
                            ClearSkillsCharacterBuildNavigationLocked();
                    }
                    if (_preparationChildReturn.Pending)
                    {
                        supersededPreparationChildTimer =
                            ClearPreparationChildReturnLocked();
                    }
                    if (_materialOpen.Pending)
                        previousMaterialTimer =
                            ClearMaterialOpenWaitLocked();
                    if (_skillOpenPending)
                        cancelledSkillTimer =
                            ClearSkillOpenWaitLocked();
                    if (_nativeEquipmentBuildOpen.Pending)
                        cancelledNativeTimer =
                            ClearNativeEquipmentBuildOpenWaitLocked();
                }

                generation =
                    ++_materialOpen.Generation;
                _lastAdmittedMaterialOpenGeneration =
                    0;
                _lastAdmittedMaterialOpenRequestId =
                    null;
                openRequestId =
                    "material.open."
                    + generation.ToString("x")
                    + "."
                    + Guid.NewGuid().ToString("N");
                _materialOpen.Pending =
                    true;
                _materialOpen.RequestId =
                    openRequestId;
                _materialOpen.Origin =
                    string.IsNullOrEmpty(origin)
                        ? "unknown"
                        : origin;
                _materialOpen.BaselinePanel =
                    activePanel;
                _materialOpen.BaselineInstance =
                    activeInstance;
                _materialOpen.HasHostAdmission =
                    hasHostAdmission;
                _materialOpen.HostAdmission =
                    hostAdmission;
                _materialOpen.LifecycleEpoch =
                    _panelNavigationLifecycleEpoch;
                int timerGeneration =
                    generation;
                int timerLifecycleEpoch =
                    _materialOpen.LifecycleEpoch;
                _materialOpen.Timer =
                    new System.Threading.Timer(
                        delegate
                        {
                            OnMaterialOpenTimeout(
                                timerGeneration,
                                timerLifecycleEpoch);
                        },
                        null,
                        Math.Max(
                            1,
                            MaterialPanelOpenTimeoutMs),
                        System.Threading.Timeout.Infinite);
            }
            if (previousMaterialTimer != null)
                previousMaterialTimer.Dispose();
            if (cancelledSkillTimer != null)
                cancelledSkillTimer.Dispose();
            if (cancelledNativeTimer != null)
                cancelledNativeTimer.Dispose();
            if (supersededForwardTimer != null)
                supersededForwardTimer.Dispose();
            if (supersededReverseTimer != null)
                supersededReverseTimer.Dispose();
            if (supersededPreparationChildTimer != null)
                supersededPreparationChildTimer.Dispose();
            return true;
        }

        private bool TryAdmitMaterialPanelRequest(
            string source,
            string view,
            string openRequestId,
            out string rejectionReason,
            out string pendingOrigin,
            out bool hasHostAdmission,
            out long hostAdmission,
            out int lifecycleEpoch,
            out bool recoverCharacterBuild)
        {
            System.Threading.Timer timer =
                null;
            bool admitted =
                false;
            lock (_panelNavigationLifecycleLock)
            {
                pendingOrigin =
                    _materialOpen.Pending
                        ? _materialOpen.Origin
                        : null;
                hasHostAdmission =
                    false;
                hostAdmission =
                    0;
                lifecycleEpoch =
                    _panelNavigationLifecycleEpoch;
                recoverCharacterBuild =
                    false;
                if (!_materialOpen.Pending)
                {
                    rejectionReason =
                        "missing_preflight";
                }
                else
                {
                    lifecycleEpoch =
                        _materialOpen.LifecycleEpoch;
                    recoverCharacterBuild =
                        string.Equals(
                            _materialOpen.Origin,
                            "character_build",
                            StringComparison.Ordinal);
                    if (!string.Equals(
                            source,
                            "nativehud_materials",
                            StringComparison.Ordinal)
                        || !string.Equals(
                            view,
                            "materials",
                            StringComparison.Ordinal))
                    {
                        rejectionReason =
                            "preflight_contract";
                        timer =
                            ClearMaterialOpenWaitLocked();
                    }
                    else if (!IsOpaqueToken(
                            openRequestId)
                        || !string.Equals(
                            openRequestId,
                            _materialOpen.RequestId,
                            StringComparison.Ordinal))
                    {
                        rejectionReason =
                            "preflight_nonce";
                        timer =
                            ClearMaterialOpenWaitLocked();
                    }
                    else
                    {
                        string activePanel =
                            _panelHost != null
                                ? _panelHost.ActivePanelName
                                : null;
                        string activeInstance =
                            _panelHost != null
                                ? _panelHost.ActivePanelInstanceId
                                : null;
                        if (_materialOpen.LifecycleEpoch
                                != _panelNavigationLifecycleEpoch)
                        {
                            rejectionReason =
                                "lifecycle_epoch";
                            timer =
                                ClearMaterialOpenWaitLocked();
                        }
                        else if (!string.Equals(
                                activePanel,
                                _materialOpen.BaselinePanel,
                                StringComparison.Ordinal)
                            || !string.Equals(
                                activeInstance,
                                _materialOpen.BaselineInstance,
                                StringComparison.Ordinal))
                        {
                            rejectionReason =
                                "competing_panel";
                            timer =
                                ClearMaterialOpenWaitLocked();
                        }
                        else if (_materialOpen.HasHostAdmission
                            && (_panelHost == null
                                || !_panelHost
                                    .IsOpenAdmissionCurrent(
                                        _materialOpen.HostAdmission,
                                        _materialOpen.BaselinePanel,
                                        _materialOpen.BaselineInstance)))
                        {
                            rejectionReason =
                                "competing_host_lifecycle";
                            timer =
                                ClearMaterialOpenWaitLocked();
                        }
                        else
                        {
                            rejectionReason =
                                null;
                            admitted =
                                true;
                            _lastAdmittedMaterialOpenGeneration =
                                _materialOpen.Generation;
                            _lastAdmittedMaterialOpenRequestId =
                                _materialOpen.RequestId;
                            hasHostAdmission =
                                _materialOpen.HasHostAdmission;
                            hostAdmission =
                                _materialOpen.HostAdmission;
                            timer =
                                ClearMaterialOpenWaitLocked();
                        }
                    }
                }
            }
            if (timer != null)
                timer.Dispose();
            return admitted;
        }

        private bool WasMaterialOpenAdmitted(
            int generation,
            string openRequestId)
        {
            lock (_panelNavigationLifecycleLock)
            {
                return generation != 0
                    && generation
                        == _lastAdmittedMaterialOpenGeneration
                    && string.Equals(
                        openRequestId,
                        _lastAdmittedMaterialOpenRequestId,
                        StringComparison.Ordinal);
            }
        }

        private bool HasArmedMaterialIntentOrOpenWait()
        {
            lock (_panelNavigationLifecycleLock)
            {
                return _materialOpen.Pending
                    || (_characterBuildPreparationNavigation.Pending
                        && _characterBuildPreparationNavigation.Target
                            == CharacterBuildPreparationTarget.Materials);
            }
        }

        private void OnMaterialOpenTimeout(
            int generation,
            int lifecycleEpoch)
        {
            System.Threading.Timer timer;
            string origin;
            int intentLifecycleEpoch;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_materialOpen.Pending
                    || generation
                        != _materialOpen.Generation
                    || lifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || lifecycleEpoch
                        != _materialOpen.LifecycleEpoch)
                {
                    return;
                }
                origin =
                    _materialOpen.Origin;
                intentLifecycleEpoch =
                    _materialOpen.LifecycleEpoch;
                timer =
                    ClearMaterialOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=material_panel_open_failed reason=panel_request_timeout source="
                + (origin ?? "unknown"));
            if (string.Equals(
                    origin,
                    "character_build",
                    StringComparison.Ordinal))
            {
                HandleCharacterBuildPreparationOpenFailure(
                    CharacterBuildPreparationTarget.Materials,
                    "material_panel_request_timeout",
                    intentLifecycleEpoch);
                return;
            }
            NotifyMaterialOpenFailure(
                "panel_request_timeout");
        }

        private bool CancelMaterialOpenWait(
            int expectedGeneration,
            out int lifecycleEpoch)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                lifecycleEpoch =
                    0;
                if (!_materialOpen.Pending
                    || (expectedGeneration != 0
                        && expectedGeneration
                            != _materialOpen.Generation))
                {
                    return false;
                }
                lifecycleEpoch =
                    _materialOpen.LifecycleEpoch;
                timer =
                    ClearMaterialOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            return true;
        }

        internal bool CancelPendingMaterialOpenIntent(
            string reason)
        {
            System.Threading.Timer timer;
            string origin;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_materialOpen.Pending)
                    return false;
                origin =
                    _materialOpen.Origin;
                timer =
                    ClearMaterialOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=material_panel_open_cancelled reason="
                + (reason ?? "unknown")
                + " source="
                + (origin ?? "unknown"));
            return true;
        }

        internal bool RejectPendingMaterialPanelRequest(
            string reason)
        {
            System.Threading.Timer timer;
            string origin;
            int lifecycleEpoch;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_materialOpen.Pending)
                {
                    LogManager.Log(
                        "event=material_panel_open_rejected reason="
                        + (reason ?? "unknown")
                        + " pending_cleared=false");
                    return false;
                }
                origin =
                    _materialOpen.Origin;
                lifecycleEpoch =
                    _materialOpen.LifecycleEpoch;
                timer =
                    ClearMaterialOpenWaitLocked();
            }
            if (timer != null)
                timer.Dispose();
            LogManager.Log(
                "event=material_panel_open_rejected reason="
                + (reason ?? "unknown")
                + " pending_cleared=true source="
                + (origin ?? "unknown"));
            if (string.Equals(
                    origin,
                    "character_build",
                    StringComparison.Ordinal))
            {
                HandleCharacterBuildPreparationOpenFailure(
                    CharacterBuildPreparationTarget.Materials,
                    "material_request_"
                        + (reason ?? "rejected"),
                    lifecycleEpoch);
            }
            else
            {
                NotifyMaterialOpenFailure(
                    reason);
            }
            return true;
        }

        private void NotifyMaterialOpenFailure(
            string reason)
        {
            string text =
                string.Equals(
                    reason,
                    "missing_preflight",
                    StringComparison.Ordinal)
                    ? "材料请求已处理或过期"
                    : string.Equals(
                        reason,
                        "panel_request_timeout",
                        StringComparison.Ordinal)
                        ? "材料服务未就绪，请稍后重试"
                        : "材料面板未打开，请重试";
            PostToWeb(
                new JObject
                {
                    ["type"] = "toast",
                    ["text"] = text
                }.ToString(Formatting.None));
        }

        private System.Threading.Timer ClearMaterialOpenWaitLocked()
        {
            return _materialOpen.Clear();
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

        private bool TrySendSkillPanelOpenCommandIfCurrent(
            int generation,
            string openRequestId,
            out bool intentCurrent)
        {
            lock (_panelNavigationLifecycleLock)
            {
                intentCurrent =
                    _skillOpenPending
                    && generation
                        == _skillOpenGeneration
                    && string.Equals(
                        openRequestId,
                        _skillOpenRequestId,
                        StringComparison.Ordinal);
                if (!intentCurrent)
                    return false;
                return TrySendSkillPanelOpenCommand(
                    openRequestId);
            }
        }

        private bool TryBeginSkillOpenWait(
            string origin,
            bool isDirectUserIntent,
            out int generation,
            out string openRequestId)
        {
            System.Threading.Timer previous;
            System.Threading.Timer cancelledNativeTimer =
                null;
            System.Threading.Timer cancelledMaterialTimer =
                null;
            System.Threading.Timer supersededForwardTimer =
                null;
            System.Threading.Timer supersededReverseTimer =
                null;
            System.Threading.Timer supersededPreparationChildTimer =
                null;
            generation =
                0;
            openRequestId =
                null;
            lock (_panelNavigationLifecycleLock)
            {
                if (_nativeEquipmentTuningOpen.Pending
                    || (!isDirectUserIntent
                        && (_materialOpen.Pending
                            || _preparationChildReturn.Pending)))
                    return false;
                string activePanel;
                string activeInstance;
                bool hasHostAdmission;
                long hostAdmission;
                if (!TryCapturePanelOpenBaseline(
                        out activePanel,
                        out activeInstance,
                        out hasHostAdmission,
                        out hostAdmission))
                {
                    return false;
                }

                if (isDirectUserIntent)
                {
                    // The notch click is a new user intent, not a continuation of an older
                    // Character Build handoff.  Invalidate both armed directions before the
                    // new preflight is installed.
                    _panelNavigationLifecycleEpoch++;
                    if (_characterBuildPreparationNavigation.Pending)
                    {
                        supersededForwardTimer =
                            ClearCharacterBuildPreparationNavigationLocked();
                    }
                    if (_pendingSkillsCharacterBuildNavigationInstance
                        != null)
                    {
                        supersededReverseTimer =
                            ClearSkillsCharacterBuildNavigationLocked();
                    }
                    if (_preparationChildReturn.Pending)
                    {
                        supersededPreparationChildTimer =
                            ClearPreparationChildReturnLocked();
                    }
                    if (_materialOpen.Pending)
                    {
                        cancelledMaterialTimer =
                            ClearMaterialOpenWaitLocked();
                    }
                }

                // A newer Skills intent wins over an older native-build preflight.
                if (_nativeEquipmentBuildOpen.Pending)
                    cancelledNativeTimer =
                        ClearNativeEquipmentBuildOpenWaitLocked();

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
                    activePanel;
                _skillOpenBaselineInstance =
                    activeInstance;
                _skillOpenHasHostAdmission =
                    hasHostAdmission;
                _skillOpenHostAdmission =
                    hostAdmission;
                _skillOpenLifecycleEpoch =
                    _panelNavigationLifecycleEpoch;
                int timerGeneration =
                    generation;
                int timerLifecycleEpoch =
                    _skillOpenLifecycleEpoch;
                _skillOpenTimer = new System.Threading.Timer(
                    delegate
                    {
                        OnSkillOpenTimeout(
                            timerGeneration,
                            timerLifecycleEpoch);
                    },
                    null, Math.Max(1, SkillOpenTimeoutMs), System.Threading.Timeout.Infinite);
            }
            if (previous != null) previous.Dispose();
            if (cancelledNativeTimer != null)
                cancelledNativeTimer.Dispose();
            if (cancelledMaterialTimer != null)
                cancelledMaterialTimer.Dispose();
            if (supersededForwardTimer != null)
                supersededForwardTimer.Dispose();
            if (supersededReverseTimer != null)
                supersededReverseTimer.Dispose();
            if (supersededPreparationChildTimer != null)
                supersededPreparationChildTimer.Dispose();
            return true;
        }

        private bool TryAdmitSkillPanelRequest(
            string source,
            string view,
            string openRequestId,
            out string rejectionReason,
            out string pendingOrigin,
            out bool hasHostAdmission,
            out long hostAdmission,
            out int lifecycleEpoch,
            out bool recoverCharacterBuild)
        {
            System.Threading.Timer timer =
                null;
            bool admitted =
                false;
            lock (_panelNavigationLifecycleLock)
            {
                hasHostAdmission =
                    false;
                hostAdmission =
                    0;
                lifecycleEpoch =
                    _panelNavigationLifecycleEpoch;
                recoverCharacterBuild =
                    false;
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
                            : null,
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
                            : null;
                    string activeInstance =
                        _panelHost != null
                            ? _panelHost.ActivePanelInstanceId
                            : null;
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
                        lifecycleEpoch =
                            _skillOpenLifecycleEpoch;
                        recoverCharacterBuild =
                            string.Equals(
                                _skillOpenOrigin,
                                "character_build",
                                StringComparison.Ordinal);
                        timer =
                            ClearSkillOpenWaitLocked();
                    }
                    else if (_skillOpenHasHostAdmission
                        && (_panelHost == null
                            || !_panelHost
                                .IsOpenAdmissionCurrent(
                                    _skillOpenHostAdmission,
                                    _skillOpenBaselinePanel,
                                    _skillOpenBaselineInstance)))
                    {
                        rejectionReason =
                            "competing_host_lifecycle";
                        lifecycleEpoch =
                            _skillOpenLifecycleEpoch;
                        recoverCharacterBuild =
                            string.Equals(
                                _skillOpenOrigin,
                                "character_build",
                                StringComparison.Ordinal);
                        timer =
                            ClearSkillOpenWaitLocked();
                    }
                    else
                    {
                        rejectionReason =
                            null;
                        admitted =
                            true;
                        hasHostAdmission =
                            _skillOpenHasHostAdmission;
                        hostAdmission =
                            _skillOpenHostAdmission;
                        lifecycleEpoch =
                            _skillOpenLifecycleEpoch;
                        timer =
                            ClearSkillOpenWaitLocked();
                    }
                }
            }
            if (timer != null)
                timer.Dispose();
            return admitted;
        }

        private void OnSkillOpenTimeout(
            int generation,
            int lifecycleEpoch)
        {
            System.Threading.Timer timer;
            bool showToast;
            string origin;
            int intentLifecycleEpoch;
            lock (_panelNavigationLifecycleLock)
            {
                if (!_skillOpenPending
                    || generation != _skillOpenGeneration
                    || lifecycleEpoch
                        != _panelNavigationLifecycleEpoch
                    || lifecycleEpoch
                        != _skillOpenLifecycleEpoch)
                {
                    return;
                }
                string active = _panelHost != null ? _panelHost.ActivePanelName : null;
                showToast = active != "skills";
                origin =
                    _skillOpenOrigin;
                intentLifecycleEpoch =
                    _skillOpenLifecycleEpoch;
                timer =
                    ClearSkillOpenWaitLocked();
            }
            if (timer != null) timer.Dispose();
            if (!showToast) return;
            if (string.Equals(
                    origin,
                    "character_build",
                    StringComparison.Ordinal))
            {
                Action afterCleared =
                    _afterSkillOpenTimeoutClearedForTests;
                if (afterCleared != null)
                    afterCleared();
            }
            LogManager.Log("[Router] SKILLS panel_request timeout generation=" + generation);
            LogManager.Log(
                "event=skill_panel_open_failed reason=panel_request_timeout source="
                    + (origin ?? "unknown"));
            if (string.Equals(
                    origin,
                    "character_build",
                    StringComparison.Ordinal))
            {
                HandleCharacterBuildPreparationOpenFailure(
                    CharacterBuildPreparationTarget.Skills,
                    "skill_panel_request_timeout",
                    intentLifecycleEpoch);
                return;
            }
            PostToWeb(
                string.Equals(
                    origin,
                    "character_build",
                    StringComparison.Ordinal)
                    ? "{\"type\":\"toast\",\"text\":\"技能面板未打开；请从装备入口重新打开构筑\"}"
                    : "{\"type\":\"toast\",\"text\":\"技能服务未就绪，请稍后重试\"}");
        }

        private bool CancelSkillOpenWait(
            int expectedGeneration = 0)
        {
            int lifecycleEpoch;
            return CancelSkillOpenWait(
                expectedGeneration,
                out lifecycleEpoch);
        }

        private bool CancelSkillOpenWait(
            int expectedGeneration,
            out int lifecycleEpoch)
        {
            System.Threading.Timer timer;
            lock (_panelNavigationLifecycleLock)
            {
                lifecycleEpoch =
                    0;
                if (!_skillOpenPending
                    || (expectedGeneration != 0
                        && expectedGeneration
                            != _skillOpenGeneration))
                {
                    return false;
                }
                lifecycleEpoch =
                    _skillOpenLifecycleEpoch;
                timer =
                    ClearSkillOpenWaitLocked();
            }
            if (timer != null) timer.Dispose();
            return true;
        }

        internal bool CancelPendingSkillOpenIntent(
            string reason)
        {
            System.Threading.Timer timer;
            string origin;
            lock (_panelNavigationLifecycleLock)
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
            _skillOpenHasHostAdmission =
                false;
            _skillOpenHostAdmission =
                0;
            _skillOpenLifecycleEpoch =
                0;
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
