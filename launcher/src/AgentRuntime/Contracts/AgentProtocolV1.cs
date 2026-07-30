using System.Collections.Generic;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CF7Launcher.AgentRuntime.Contracts
{
    public static class AgentProtocolV1
    {
        public const string Version = "1.0";
        public const string FrameMagic = "CF7A";
        public const byte JsonRpcFrameKind = 1;
        public const byte BinaryChunkFrameKind = 2;
        public const int FrameHeaderBytes = 12;
        public const int MaximumJsonFrameBytes = 1_048_576;
        public const int MaximumBinaryChunkBytes = 4_194_304;
        public const int BinaryChunkMetadataLengthBytes = 4;
        public const int MaximumBinaryChunkMetadataBytes = 1_024;
        public const int MaximumBinaryReadCount =
            MaximumBinaryChunkBytes - BinaryChunkMetadataLengthBytes;
        public const int MaximumBinaryObjectBytes = 16_777_216;
        public const int MinimumOpaqueIdCharacters = 22;
        public const int MaximumOpaqueIdCharacters = 128;
        public const int MaximumReasonCharacters = 512;
        public const int MaximumActionDeadlineMs = 30_000;
        public const int MaximumConnectionTicketTtlMs = 30_000;
        public const int MaximumContentHandleTtlMs = 15_000;
        public const int MaximumObservationTtlMs = 10_000;
        public const int MaximumObservationGrantTtlMs = 900_000;
        public const int MaximumTargetScopeItems = 32;
        public const int MaximumClientQueueDepth = 16;
        public const int MaximumConcurrentRequestsPerClient = 4;
        public const int MaximumRequestsPerMinute = 120;

        private static readonly JsonSerializerOptions SerializerOptions = CreateSerializerOptions();

        public static JsonSerializerOptions JsonOptions
        {
            get { return SerializerOptions; }
        }

        private static JsonSerializerOptions CreateSerializerOptions()
        {
            var options = new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                DictionaryKeyPolicy = JsonNamingPolicy.CamelCase,
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                PropertyNameCaseInsensitive = false,
                ReadCommentHandling = JsonCommentHandling.Disallow,
                AllowTrailingCommas = false,
                UnmappedMemberHandling =
                    JsonUnmappedMemberHandling.Disallow,
                MaxDepth = 32,
                WriteIndented = false
            };
            options.Converters.Add(
                new JsonStringEnumConverter(
                    JsonNamingPolicy.SnakeCaseLower,
                    allowIntegerValues: false));
            return options;
        }
    }

    public static class AgentCapabilitiesV1
    {
        public const string ListWindows = "window.list";
        public const string GetWindow = "window.get";
        public const string ListApps = "app.list";
        public const string LaunchApp = "app.launch";
        public const string GetWindowState = "window.state";
        public const string Click = "input.click";
        public const string PressKey = "input.press_key";
        public const string TypeText = "input.type_text";
        public const string Scroll = "input.scroll";
        public const string SetValue = "semantic.set_value";
        public const string Drag = "input.drag";
        public const string PerformSecondaryAction = "semantic.secondary_action";
        public const string ActivateWindow = "window.activate";

        public static readonly IReadOnlyList<string> GuiCapabilitySet = new[]
        {
            ListWindows,
            GetWindow,
            ListApps,
            LaunchApp,
            GetWindowState,
            Click,
            PressKey,
            TypeText,
            Scroll,
            SetValue,
            Drag,
            PerformSecondaryAction,
            ActivateWindow
        };

        public const string SessionStatus = "session.status";
        public const string SessionDiscover = "session.discover";
        public const string SessionAttach = "session.attach";
        public const string SessionDetach = "session.detach";
        public const string SessionShutdown = "session.shutdown";
        public const string LifecycleReveal = "lifecycle.reveal";
        public const string LifecycleCancel = "lifecycle.cancel";
        public const string PanelOpen = "panel.open";
        public const string LeaseAcquire = "lease.acquire";
        public const string LeaseRenew = "lease.renew";
        public const string LeaseRelease = "lease.release";
        public const string TraceExport = "trace.export";
        public const string AppearanceHairChange = "domain.appearance.hair.change.v1";
        public const string ObservationGrantManage =
            "observation.grant.manage";
        public const string ObservationCapture =
            "observation.capture";
        public const string ContentRead = "content.read";
        public const string ActionGet = "action.get";

        public static readonly IReadOnlySet<string> All = new HashSet<string>(
            new[]
            {
                ListWindows,
                GetWindow,
                ListApps,
                LaunchApp,
                GetWindowState,
                Click,
                PressKey,
                TypeText,
                Scroll,
                SetValue,
                Drag,
                PerformSecondaryAction,
                ActivateWindow,
                SessionStatus,
                SessionDiscover,
                SessionAttach,
                SessionDetach,
                SessionShutdown,
                LifecycleReveal,
                LifecycleCancel,
                PanelOpen,
                LeaseAcquire,
                LeaseRenew,
                LeaseRelease,
                TraceExport,
                AppearanceHairChange,
                ObservationGrantManage,
                ObservationCapture,
                ContentRead,
                ActionGet
            },
            System.StringComparer.Ordinal);
    }

    public static class ObservationDataScopesV1
    {
        public const string WindowMetadata = "window_metadata";
        public const string Pixels = "pixels";
        public const string Accessibility = "accessibility";
        public const string Focus = "focus";
        public const string Selection = "selection";
        public const string PlayerState = "player_state";
        public const string LorePublic = "lore_public";
        public const string RetentionPersist =
            "retention.persist";
        public const string DataExport = "data.export";

        public static readonly IReadOnlySet<string> All =
            new HashSet<string>(
                new[]
                {
                    WindowMetadata,
                    Pixels,
                    Accessibility,
                    Focus,
                    Selection,
                    PlayerState,
                    LorePublic,
                    RetentionPersist,
                    DataExport
                },
                System.StringComparer.Ordinal);
    }

    public static class TraceExportConsentPurposesV1
    {
        public static readonly IReadOnlySet<string> All =
            new HashSet<string>(
                new[]
                {
                    AgentCapabilitiesV1.Click,
                    AgentCapabilitiesV1.PressKey,
                    AgentCapabilitiesV1.TypeText,
                    AgentCapabilitiesV1.Scroll,
                    AgentCapabilitiesV1.SetValue,
                    AgentCapabilitiesV1.Drag,
                    AgentCapabilitiesV1
                        .PerformSecondaryAction,
                    AgentCapabilitiesV1.ActivateWindow,
                    AgentCapabilitiesV1.SessionShutdown,
                    AgentCapabilitiesV1.LifecycleReveal,
                    AgentCapabilitiesV1.LifecycleCancel,
                    AgentCapabilitiesV1.PanelOpen,
                    AgentCapabilitiesV1
                        .AppearanceHairChange
                },
                System.StringComparer.Ordinal);
    }

    public enum SecurityPrincipalKind
    {
        DeveloperAgent,
        UnattendedTestRunner,
        WingsPersona,
        Human
    }

    public enum ClientKind
    {
        JsonlCli,
        McpStdio,
        WingsInternal,
        TestHarness
    }

    public enum SessionMode
    {
        DeveloperInteractive,
        UnattendedTest,
        PlayerAssist
    }

    public enum RuntimeMode
    {
        FormalRuntime,
        IsolatedCandidate,
        UnqualifiedDev
    }

    public enum RuntimeQualificationState
    {
        Verified,
        Unqualified
    }

    public enum SurfaceKind
    {
        Launcher,
        Flash,
        WebOverlay,
        NativeHud,
        WingsShell,
        BusinessModal
    }

    public static class AgentSurfaceKindsV1
    {
        public const string Launcher = "launcher";
        public const string Flash = "flash";
        public const string WebOverlay = "web_overlay";
        public const string NativeHud = "native_hud";
        public const string WingsShell = "wings_shell";
        public const string BusinessModal = "business_modal";

        public static readonly IReadOnlySet<string> All =
            new HashSet<string>(
                new[]
                {
                    Launcher,
                    Flash,
                    WebOverlay,
                    NativeHud,
                    WingsShell,
                    BusinessModal
                },
                System.StringComparer.Ordinal);

        public static bool TryParse(
            string value,
            out SurfaceKind kind)
        {
            switch (value)
            {
                case Launcher:
                    kind = SurfaceKind.Launcher;
                    return true;
                case Flash:
                    kind = SurfaceKind.Flash;
                    return true;
                case WebOverlay:
                    kind = SurfaceKind.WebOverlay;
                    return true;
                case NativeHud:
                    kind = SurfaceKind.NativeHud;
                    return true;
                case WingsShell:
                    kind = SurfaceKind.WingsShell;
                    return true;
                case BusinessModal:
                    kind = SurfaceKind.BusinessModal;
                    return true;
                default:
                    kind = default;
                    return false;
            }
        }
    }

    public enum ObservationMode
    {
        WindowGraphicsCapture,
        FlashSnapshotKeyframe,
        Uia,
        WebSemantic
    }

    public enum InputMode
    {
        Cdp,
        SendInputGuarded,
        UiaValue,
        UiaInvoke,
        DomainTransaction
    }

    public enum ObservationGrantState
    {
        Active,
        Revoked,
        Expired
    }

    public enum LeasePurpose
    {
        GuiInput,
        DomainTransaction,
        Shutdown
    }

    public enum LeaseState
    {
        Active,
        Revoked,
        Expired,
        Released,
        Consumed
    }

    public enum HumanOverridePolicy
    {
        AlwaysPreempt
    }

    public enum BlockingModalKind
    {
        None,
        BusinessOwned,
        HumanOnlySecurity,
        Foreign,
        Unknown
    }

    public enum SourceLayer
    {
        Launcher,
        Flash,
        WebOverlay,
        NativeHud,
        WingsShell,
        BusinessModal
    }

    public enum PixelFormat
    {
        Bgra8Premultiplied
    }

    public enum ActionOutcome
    {
        Rejected,
        InputDispatched,
        EffectObserved,
        DomainCommitted,
        Unknown
    }

    public enum EvidenceKind
    {
        None,
        BrokerDispatch,
        PostObservation,
        DomainAck,
        ProcessExit,
        ReconciliationRequired
    }

    public enum ReconcileKind
    {
        None,
        DomainAuthoritative,
        VisualAmbiguous,
        ManualRequired
    }
}
