using System;
using System.Collections.Generic;
using System.Text.Json;

namespace CF7Launcher.AgentRuntime.Contracts
{
    public sealed class HelloMessage
    {
        public string ProtocolVersion { get; set; } = AgentProtocolV1.Version;
        public string ClientInstanceId { get; set; }
        public ClientKind ClientKind { get; set; }
        public List<string> RequestedCapabilities { get; set; } = new List<string>();
        public string Nonce { get; set; }
        public string ConnectionToken { get; set; }
        public string CredentialProof { get; set; }
    }

    public sealed class WelcomeMessage
    {
        public string ServerInstanceId { get; set; }
        public string ProtocolVersion { get; set; } = AgentProtocolV1.Version;
        public string SecurityPrincipalId { get; set; }
        public MinimalSessionReference MinimalSessionRef { get; set; }
        public List<string> GrantedCapabilities { get; set; } = new List<string>();
        public WelcomeLimits Limits { get; set; }
        public ulong ServerSequence { get; set; }
    }

    public sealed class MinimalSessionReference
    {
        public bool ProjectRunning { get; set; }
        public RuntimeQualificationState QualificationState { get; set; }
        public string LifecycleRef { get; set; }
    }

    public sealed class AppLaunchResultV1
    {
        public string LaunchRequestId { get; set; }
        public string EntryPoint { get; set; }
        public bool Started { get; set; }
        public bool AlreadyRunning { get; set; }
        public RuntimeMode RuntimeMode { get; set; }
        public MinimalSessionReference MinimalSessionRef { get; set; }
    }

    public sealed class AppDescriptorV1
    {
        public string AppId { get; set; }
        public string EntryPoint { get; set; }
        public bool Running { get; set; }
    }

    public sealed class AppListResultV1
    {
        public List<AppDescriptorV1> Apps { get; set; } =
            new List<AppDescriptorV1>();
    }

    public static class AgentAppCatalogV1
    {
        public const string FlashNightAppId = "cf7.flash_night";
        public const string StandardEntryPoint = "standard_entry";

        public static AppListResultV1 CreateList(bool running)
        {
            return new AppListResultV1
            {
                Apps = new List<AppDescriptorV1>
                {
                    new AppDescriptorV1
                    {
                        AppId = FlashNightAppId,
                        EntryPoint = StandardEntryPoint,
                        Running = running
                    }
                }
            };
        }
    }

    public sealed class WelcomeLimits
    {
        public int MaximumJsonFrameBytes { get; set; } = AgentProtocolV1.MaximumJsonFrameBytes;
        public int MaximumBinaryChunkBytes { get; set; } = AgentProtocolV1.MaximumBinaryChunkBytes;
        public int MaximumBinaryObjectBytes { get; set; } = AgentProtocolV1.MaximumBinaryObjectBytes;
        public int MaximumConcurrentRequests { get; set; } = AgentProtocolV1.MaximumConcurrentRequestsPerClient;
        public int MaximumQueueDepth { get; set; } = AgentProtocolV1.MaximumClientQueueDepth;
        public int MaximumRequestsPerMinute { get; set; } = AgentProtocolV1.MaximumRequestsPerMinute;
        public int MaximumActionDeadlineMs { get; set; } = AgentProtocolV1.MaximumActionDeadlineMs;
        public int MaximumContentHandleTtlMs { get; set; } = AgentProtocolV1.MaximumContentHandleTtlMs;
        public int MaximumTargetScopeItems { get; set; } = AgentProtocolV1.MaximumTargetScopeItems;
    }

    public sealed class SessionDescriptor
    {
        public string ProtocolVersion { get; set; } = AgentProtocolV1.Version;
        public string SessionId { get; set; }
        public ulong LifecycleGeneration { get; set; }
        public SessionMode SessionMode { get; set; }
        public RuntimeMode RuntimeMode { get; set; }
        public string AttemptId { get; set; }
        public ulong? AttemptGeneration { get; set; }
        public string Slot { get; set; }
        public long? SaveRevision { get; set; }
        public string LauncherPath { get; set; }
        public int LauncherPid { get; set; }
        public DateTimeOffset LauncherStartTime { get; set; }
        public int? FlashPid { get; set; }
        public DateTimeOffset? FlashStartTime { get; set; }
        public string CoreSha256 { get; set; }
        public RuntimeQualification RuntimeQualification { get; set; }
        public List<SurfaceDescriptor> Surfaces { get; set; } = new List<SurfaceDescriptor>();
        public ActivePanelDescriptor ActivePanel { get; set; }
        public List<string> Capabilities { get; set; } = new List<string>();
    }

    public sealed class RuntimeQualification
    {
        public string BuildIdentity { get; set; }
        public string PayloadClosure { get; set; }
        public string UnqualifiedReason { get; set; }
    }

    public sealed class ActivePanelDescriptor
    {
        public string Name { get; set; }
        public string InstanceId { get; set; }
        public string TargetId { get; set; }
    }

    public sealed class SurfaceDescriptor
    {
        public string TargetId { get; set; }
        public SurfaceKind Kind { get; set; }
        public ulong SurfaceEpoch { get; set; }
        public PhysicalRect BoundsPhysical { get; set; }
        public int Dpi { get; set; }
        public int ZIndex { get; set; }
        public bool Visible { get; set; }
        public ulong CoordinateSpaceVersion { get; set; }
        public ulong FocusEpoch { get; set; }
        public ulong ModalEpoch { get; set; }
        public ulong? SemanticGeneration { get; set; }
        public ulong? DocumentGeneration { get; set; }
        public List<ObservationMode> ObservationModes { get; set; } = new List<ObservationMode>();
        public List<InputMode> InputModes { get; set; } = new List<InputMode>();
    }

    public sealed class PhysicalRect
    {
        public int X { get; set; }
        public int Y { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public sealed class SessionScopeDescriptor
    {
        public string SessionId { get; set; }
        public ulong LifecycleGeneration { get; set; }
        public string AttemptId { get; set; }
        public ulong? AttemptGeneration { get; set; }
        public bool CrossAttempt { get; set; }
    }

    public sealed class ObservationGrantDescriptor
    {
        public string ObservationGrantId { get; set; }
        public string OwnerClientId { get; set; }
        public string SecurityPrincipalId { get; set; }
        public SessionScopeDescriptor SessionScope { get; set; }
        public List<string> TargetScope { get; set; } = new List<string>();
        public List<string> DataScope { get; set; } = new List<string>();
        public ulong IssuedMonotonic { get; set; }
        public ulong ExpiresMonotonic { get; set; }
        public string ConsentReceipt { get; set; }
        public bool AllowEphemeralKeyframes { get; set; }
        public bool AllowPersistence { get; set; }
        public bool AllowExport { get; set; }
        public ObservationGrantState State { get; set; }
        public string RevokeReason { get; set; }
    }

    public sealed class LeaseScopeDescriptor
    {
        public SessionScopeDescriptor Session { get; set; }
        public List<string> TargetScope { get; set; } = new List<string>();
        public List<string> OperationScope { get; set; } = new List<string>();
        public int MaximumActions { get; set; }
        public string ArgumentBoundsHash { get; set; }
    }

    public sealed class LeaseDescriptor
    {
        public string LeaseId { get; set; }
        public string OwnerClientId { get; set; }
        public string SecurityPrincipalId { get; set; }
        public SessionMode SessionMode { get; set; }
        public LeasePurpose Purpose { get; set; }
        public LeaseScopeDescriptor Scope { get; set; }
        public List<string> Capabilities { get; set; } = new List<string>();
        public ulong IssuedMonotonic { get; set; }
        public ulong ExpiresMonotonic { get; set; }
        public ulong? RenewAfter { get; set; }
        public string ConsentReceipt { get; set; }
        public HumanOverridePolicy HumanOverridePolicy { get; set; } = HumanOverridePolicy.AlwaysPreempt;
        public LeaseState State { get; set; }
        public string RevokeReason { get; set; }
    }

    public sealed class ObservationEnvelope
    {
        public string ObservationId { get; set; }
        public string ObservationGrantId { get; set; }
        public string SessionId { get; set; }
        public ulong LifecycleGeneration { get; set; }
        public DateTimeOffset CapturedUtc { get; set; }
        public ulong CapturedAtMonotonic { get; set; }
        public string AttemptId { get; set; }
        public ulong? AttemptGeneration { get; set; }
        public string PanelInstanceId { get; set; }
        public ulong? DocumentGeneration { get; set; }
        public string TargetId { get; set; }
        public ulong SurfaceEpoch { get; set; }
        public ulong CoordinateSpaceVersion { get; set; }
        public ulong FocusEpoch { get; set; }
        public ulong ModalEpoch { get; set; }
        public string SemanticSnapshotId { get; set; }
        public ulong? SemanticGeneration { get; set; }
        public bool Visible { get; set; }
        public bool Minimized { get; set; }
        public bool Active { get; set; }
        public BlockingModalKind BlockingModalKind { get; set; }
        public List<FrameEnvelope> Frames { get; set; } = new List<FrameEnvelope>();
        public JsonElement? Accessibility { get; set; }
        public JsonElement? Focus { get; set; }
        public JsonElement? Selection { get; set; }
    }

    public sealed class FrameEnvelope
    {
        public string FrameId { get; set; }
        public string ObservationId { get; set; }
        public string TargetId { get; set; }
        public ulong SurfaceEpoch { get; set; }
        public SourceLayer SourceLayer { get; set; }
        public int ZIndex { get; set; }
        public ulong CapturedAtMonotonic { get; set; }
        public string CoordinateSpaceId { get; set; }
        public ulong CoordinateSpaceVersion { get; set; }
        public PhysicalRect CaptureRectPhysical { get; set; }
        public PhysicalRect ClientRectPhysical { get; set; }
        public PhysicalRect ContentRectPhysical { get; set; }
        public AffineTransform FrameToTargetContentTransform { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int Dpi { get; set; }
        public PixelFormat PixelFormat { get; set; }
        public string ContentHash { get; set; }
        public string OpaqueContentHandle { get; set; }
    }

    public sealed class AffineTransform
    {
        public double M11 { get; set; }
        public double M12 { get; set; }
        public double M21 { get; set; }
        public double M22 { get; set; }
        public double Dx { get; set; }
        public double Dy { get; set; }
    }

    public sealed class ActionEnvelope
    {
        public string ActionId { get; set; }
        public string IdempotencyKey { get; set; }
        public int DeadlineMs { get; set; }
        public string SessionId { get; set; }
        public string ObservationGrantId { get; set; }
        public string LeaseId { get; set; }
        public string ObservationId { get; set; }
        public ulong ExpectedLifecycleGeneration { get; set; }
        public string TargetId { get; set; }
        public ulong ExpectedSurfaceEpoch { get; set; }
        public string ExpectedAttemptId { get; set; }
        public ulong? ExpectedAttemptGeneration { get; set; }
        public string ExpectedPanelInstanceId { get; set; }
        public ulong? ExpectedSemanticGeneration { get; set; }
        public ulong? ExpectedDocumentGeneration { get; set; }
        public ulong ExpectedCoordinateSpaceVersion { get; set; }
        public ulong ExpectedFocusEpoch { get; set; }
        public ulong ExpectedModalEpoch { get; set; }
        public string FrameId { get; set; }
        public string SemanticSnapshotId { get; set; }
        public string NodeId { get; set; }
        public string Operation { get; set; }
        public JsonElement Arguments { get; set; }
        public string Reason { get; set; }
    }

    public sealed class ActionReceipt
    {
        public string ActionId { get; set; }
        public ulong AuditSequence { get; set; }
        public bool Terminal { get; set; } = true;
        public ActionOutcome Outcome { get; set; }
        public EvidenceKind EvidenceKind { get; set; }
        public string ReasonCode { get; set; }
        public ReconcileKind ReconcileKind { get; set; }
        public bool Retryable { get; set; }
        public string ActualTargetId { get; set; }
        public bool FocusVerified { get; set; }
        public string BeforeObservationId { get; set; }
        public string AfterObservationId { get; set; }
        public LeaseState LeaseState { get; set; }
        public HairDomainActionResult DomainResult { get; set; }
    }

    public sealed class HairDomainActionResult
    {
        public string TransactionId { get; set; }
        public string PreviewHash { get; set; }
        public string RestoreToken { get; set; }
        public DateTimeOffset? RestoreExpiresAtUtc { get; set; }
    }

    public sealed class HairConsentDescriptorV1
    {
        public string ConsentToken { get; init; }
        public string ConsentReceipt { get; init; }
        public string TransactionId { get; init; }
        public string PreviewHash { get; init; }
        public int ExpiresInMs { get; init; }
    }
}
