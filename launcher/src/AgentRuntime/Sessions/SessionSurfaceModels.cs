using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Sessions
{
    internal sealed class SessionProcessIdentity
    {
        public SessionProcessIdentity(
            int processId,
            DateTimeOffset startTimeUtc,
            string executablePath)
        {
            if (processId <= 0)
                throw new ArgumentOutOfRangeException(nameof(processId));
            if (startTimeUtc == default)
                throw new ArgumentException(
                    "A process start time is required.",
                    nameof(startTimeUtc));
            if (string.IsNullOrWhiteSpace(executablePath)
                || !Path.IsPathFullyQualified(executablePath))
            {
                throw new ArgumentException(
                    "An absolute executable path is required.",
                    nameof(executablePath));
            }

            ProcessId = processId;
            StartTimeUtc = startTimeUtc.ToUniversalTime();
            ExecutablePath = Path.GetFullPath(executablePath);
        }

        public int ProcessId { get; }
        public DateTimeOffset StartTimeUtc { get; }
        public string ExecutablePath { get; }

        public bool IsExact(SessionProcessIdentity other)
        {
            return other != null
                && ProcessId == other.ProcessId
                && StartTimeUtc.UtcDateTime.Ticks
                    == other.StartTimeUtc.UtcDateTime.Ticks
                && string.Equals(
                    ExecutablePath,
                    other.ExecutablePath,
                    StringComparison.OrdinalIgnoreCase);
        }
    }

    /// <summary>
    /// An in-process capability held by the Launcher host. Registry mutation
    /// methods require the exact object instance, so a wire request cannot turn
    /// process/window claims into a positive registration.
    /// </summary>
    internal sealed class SessionRegistryHostOwner
    {
        public SessionRegistryHostOwner(SessionProcessIdentity launcherProcess)
        {
            LauncherProcess = launcherProcess
                ?? throw new ArgumentNullException(nameof(launcherProcess));
        }

        public SessionProcessIdentity LauncherProcess { get; }

        public static SessionRegistryHostOwner CaptureCurrentLauncher()
        {
            using Process process = Process.GetCurrentProcess();
            string path = process.MainModule?.FileName
                ?? throw new InvalidOperationException(
                    "The Launcher executable path is unavailable.");
            return new SessionRegistryHostOwner(
                new SessionProcessIdentity(
                    process.Id,
                    new DateTimeOffset(process.StartTime.ToUniversalTime()),
                    path));
        }
    }

    internal sealed class RuntimeQualificationRegistration
    {
        public RuntimeMode RuntimeMode { get; init; }
        public string BuildIdentity { get; init; }
        public string PayloadClosure { get; init; }
        public string ActualProcessPath { get; init; }
        public string UnqualifiedReason { get; init; }
        public bool UnqualifiedDevVisualInputAuthorized { get; init; }
    }

    internal sealed class SessionHostRegistration
    {
        public string SessionId { get; init; }
        public ulong LifecycleGeneration { get; init; }
        public SessionMode SessionMode { get; init; }
        public string Slot { get; init; }
        public long? SaveRevision { get; init; }
        public string AttemptId { get; init; }
        public ulong? AttemptGeneration { get; init; }
        public SessionProcessIdentity LauncherProcess { get; init; }
        public SessionProcessIdentity FlashProcess { get; init; }
        public string CoreSha256 { get; init; }
        public RuntimeQualificationRegistration RuntimeQualification { get; init; }
        public IReadOnlyCollection<string> Capabilities { get; init; }
    }

    internal sealed class SessionAttemptRegistration
    {
        public string AttemptId { get; init; }
        public SessionProcessIdentity FlashProcess { get; init; }
        public string Slot { get; init; }
        public long? SaveRevision { get; init; }
    }

    internal enum SessionSurfaceOwnerRelation
    {
        LauncherTopLevel,
        LauncherOwned,
        FlashTopLevel,
        FlashOwned,
        RuntimeOverlay,
        HumanOnlySecurityReported
    }

    internal sealed class SessionPhysicalRect : IEquatable<SessionPhysicalRect>
    {
        public SessionPhysicalRect(int x, int y, int width, int height)
        {
            if (width <= 0 || height <= 0)
                throw new ArgumentOutOfRangeException(
                    nameof(width),
                    "Surface rectangles must have positive dimensions.");
            X = x;
            Y = y;
            Width = width;
            Height = height;
        }

        public int X { get; }
        public int Y { get; }
        public int Width { get; }
        public int Height { get; }

        public bool Equals(SessionPhysicalRect other)
        {
            return other != null
                && X == other.X
                && Y == other.Y
                && Width == other.Width
                && Height == other.Height;
        }

        public override bool Equals(object obj)
        {
            return Equals(obj as SessionPhysicalRect);
        }

        public override int GetHashCode()
        {
            return HashCode.Combine(X, Y, Width, Height);
        }

        public PhysicalRect ToContract()
        {
            return new PhysicalRect
            {
                X = X,
                Y = Y,
                Width = Width,
                Height = Height
            };
        }
    }

    internal sealed class SessionSurfaceHostRegistration
    {
        public string TargetId { get; init; }
        public SurfaceKind Kind { get; init; }
        public AgentTargetSafetyKind SafetyKind { get; init; }
        public SessionSurfaceOwnerRelation OwnerRelation { get; init; }
        public SessionProcessIdentity OwnerProcess { get; init; }
        public long WindowHandle { get; init; }
        public string OwnerTargetId { get; init; }
        public long OwnerWindowHandle { get; init; }
        public SessionPhysicalRect BoundsPhysical { get; init; }
        public SessionPhysicalRect ClientRectPhysical { get; init; }
        public SessionPhysicalRect ContentRectPhysical { get; init; }
        public int Dpi { get; init; }
        public int ZIndex { get; init; }
        public bool Visible { get; init; } = true;
        public bool Minimized { get; init; }
        public IReadOnlyCollection<ObservationMode> ObservationModes { get; init; }
        public IReadOnlyCollection<InputMode> InputModes { get; init; }
    }

    internal sealed class SessionSurfaceLayoutUpdate
    {
        public SessionPhysicalRect BoundsPhysical { get; init; }
        public SessionPhysicalRect ClientRectPhysical { get; init; }
        public SessionPhysicalRect ContentRectPhysical { get; init; }
        public int Dpi { get; init; }
        public int ZIndex { get; init; }
        public bool Visible { get; init; } = true;
        public bool Minimized { get; init; }
    }

    internal sealed class SessionMutationExpectation
    {
        public string SessionId { get; init; }
        public ulong LifecycleGeneration { get; init; }
        public string AttemptId { get; init; }
        public ulong? AttemptGeneration { get; init; }
    }

    internal sealed class SessionSurfaceMutationExpectation
    {
        public SessionMutationExpectation Session { get; init; }
        public string TargetId { get; init; }
        public ulong SurfaceEpoch { get; init; }
        public long? WindowHandle { get; init; }
    }

    internal sealed class SessionTargetGenerationExpectation
    {
        public string SessionId { get; init; }
        public ulong LifecycleGeneration { get; init; }
        public string AttemptId { get; init; }
        public ulong? AttemptGeneration { get; init; }
        public string TargetId { get; init; }
        public ulong SurfaceEpoch { get; init; }
        public ulong CoordinateSpaceVersion { get; init; }
        public ulong FocusEpoch { get; init; }
        public ulong ModalEpoch { get; init; }
        public ulong? DocumentGeneration { get; init; }
        public string PanelInstanceId { get; init; }
    }

    internal sealed class ActivePanelRegistration
    {
        public string Name { get; init; }
        public string InstanceId { get; init; }
        public string TargetId { get; init; }
    }

    internal enum SessionInvalidationLevel
    {
        None,
        Registration,
        Lifecycle,
        Attempt,
        Surface,
        Focus,
        Modal,
        Document,
        Panel,
        Security
    }

    [Flags]
    internal enum SessionInvalidationFlags
    {
        None = 0,
        ObservationGrants = 1 << 0,
        WriteLeases = 1 << 1,
        Observations = 1 << 2,
        SemanticNodes = 1 << 3,
        PendingActions = 1 << 4,
        PendingCoordinateActions = 1 << 5,
        PendingInput = 1 << 6,
        PendingDomainOperations = 1 << 7,
        ExactInstanceLeases = 1 << 8,
        QueuedActions = 1 << 9,
        RuntimeHeldInput = 1 << 10,
        AttemptScopedAuthorities = 1 << 11
    }

    internal sealed class SessionScopeInvalidation
    {
        public SessionScopeInvalidation(
            SessionInvalidationLevel level,
            string reasonCode,
            string sessionId,
            ulong lifecycleGeneration,
            SessionInvalidationFlags flags,
            IEnumerable<string> targetIds,
            bool affectsAllTargets,
            bool requiresHumanReauthorization)
        {
            Level = level;
            ReasonCode = reasonCode;
            SessionId = sessionId;
            LifecycleGeneration = lifecycleGeneration;
            Flags = flags;
            TargetIds = FreezeStrings(targetIds);
            AffectsAllTargets = affectsAllTargets;
            RequiresHumanReauthorization = requiresHumanReauthorization;
        }

        public SessionInvalidationLevel Level { get; }
        public string ReasonCode { get; }
        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public SessionInvalidationFlags Flags { get; }
        public ReadOnlyCollection<string> TargetIds { get; }
        public bool AffectsAllTargets { get; }
        public bool RequiresHumanReauthorization { get; }

        public bool Has(SessionInvalidationFlags flag)
        {
            return (Flags & flag) == flag;
        }

        private static ReadOnlyCollection<string> FreezeStrings(
            IEnumerable<string> values)
        {
            return Array.AsReadOnly(
                (values ?? Array.Empty<string>())
                    .Where(value => !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
        }
    }

    internal sealed class SessionSurfaceSnapshot
    {
        internal SessionSurfaceSnapshot(
            string targetId,
            SurfaceKind kind,
            AgentTargetSafetyKind safetyKind,
            SessionSurfaceOwnerRelation ownerRelation,
            SessionProcessIdentity ownerProcess,
            long windowHandle,
            string ownerTargetId,
            long ownerWindowHandle,
            ulong surfaceEpoch,
            ulong coordinateSpaceVersion,
            ulong focusEpoch,
            ulong modalEpoch,
            ulong? semanticGeneration,
            ulong? documentGeneration,
            SessionPhysicalRect boundsPhysical,
            SessionPhysicalRect clientRectPhysical,
            SessionPhysicalRect contentRectPhysical,
            int dpi,
            int zIndex,
            bool visible,
            bool minimized,
            bool active,
            IEnumerable<ObservationMode> observationModes,
            IEnumerable<InputMode> inputModes)
        {
            TargetId = targetId;
            Kind = kind;
            SafetyKind = safetyKind;
            OwnerRelation = ownerRelation;
            OwnerProcess = ownerProcess;
            WindowHandle = windowHandle;
            OwnerTargetId = ownerTargetId;
            OwnerWindowHandle = ownerWindowHandle;
            SurfaceEpoch = surfaceEpoch;
            CoordinateSpaceVersion = coordinateSpaceVersion;
            FocusEpoch = focusEpoch;
            ModalEpoch = modalEpoch;
            SemanticGeneration = semanticGeneration;
            DocumentGeneration = documentGeneration;
            BoundsPhysical = boundsPhysical;
            ClientRectPhysical = clientRectPhysical;
            ContentRectPhysical = contentRectPhysical;
            Dpi = dpi;
            ZIndex = zIndex;
            Visible = visible;
            Minimized = minimized;
            Active = active;
            ObservationModes = Freeze(observationModes);
            InputModes = Freeze(inputModes);
        }

        public string TargetId { get; }
        public SurfaceKind Kind { get; }
        public AgentTargetSafetyKind SafetyKind { get; }
        public SessionSurfaceOwnerRelation OwnerRelation { get; }
        public SessionProcessIdentity OwnerProcess { get; }
        public long WindowHandle { get; }
        public string OwnerTargetId { get; }
        public long OwnerWindowHandle { get; }
        public ulong SurfaceEpoch { get; }
        public ulong CoordinateSpaceVersion { get; }
        public ulong FocusEpoch { get; }
        public ulong ModalEpoch { get; }
        public ulong? SemanticGeneration { get; }
        public ulong? DocumentGeneration { get; }
        public SessionPhysicalRect BoundsPhysical { get; }
        public SessionPhysicalRect ClientRectPhysical { get; }
        public SessionPhysicalRect ContentRectPhysical { get; }
        public int Dpi { get; }
        public int ZIndex { get; }
        public bool Visible { get; }
        public bool Minimized { get; }
        public bool Active { get; }
        public ReadOnlyCollection<ObservationMode> ObservationModes { get; }
        public ReadOnlyCollection<InputMode> InputModes { get; }

        public SurfaceDescriptor ToContract()
        {
            return new SurfaceDescriptor
            {
                TargetId = TargetId,
                Kind = Kind,
                SurfaceEpoch = SurfaceEpoch,
                BoundsPhysical = BoundsPhysical.ToContract(),
                Dpi = Dpi,
                ZIndex = ZIndex,
                Visible = Visible,
                CoordinateSpaceVersion = CoordinateSpaceVersion,
                FocusEpoch = FocusEpoch,
                ModalEpoch = ModalEpoch,
                SemanticGeneration = SemanticGeneration,
                DocumentGeneration = DocumentGeneration,
                ObservationModes = ObservationModes.ToList(),
                InputModes = InputModes.ToList()
            };
        }

        private static ReadOnlyCollection<T> Freeze<T>(
            IEnumerable<T> values)
        {
            return Array.AsReadOnly(
                (values ?? Array.Empty<T>())
                    .Distinct()
                    .OrderBy(value => value)
                    .ToArray());
        }
    }

    internal sealed class SessionSnapshot
    {
        internal SessionSnapshot(
            SessionHostRegistration registration,
            IEnumerable<SessionSurfaceSnapshot> discoverableSurfaces,
            string activePanelName,
            string activePanelInstanceId,
            string activePanelTargetId,
            ulong focusEpoch,
            ulong modalEpoch,
            BlockingModalKind blockingModalKind,
            bool humanReauthorizationRequired,
            string activeTargetId,
            bool desktopAvailable)
        {
            SessionId = registration.SessionId;
            LifecycleGeneration = registration.LifecycleGeneration;
            SessionMode = registration.SessionMode;
            Slot = registration.Slot;
            SaveRevision = registration.SaveRevision;
            AttemptId = registration.AttemptId;
            AttemptGeneration = registration.AttemptGeneration;
            LauncherProcess = registration.LauncherProcess;
            FlashProcess = registration.FlashProcess;
            CoreSha256 = registration.CoreSha256;
            RuntimeQualification = registration.RuntimeQualification;
            Capabilities = FreezeStrings(registration.Capabilities);
            Surfaces = Array.AsReadOnly(
                (discoverableSurfaces ?? Array.Empty<SessionSurfaceSnapshot>())
                    .OrderBy(surface => surface.ZIndex)
                    .ThenBy(surface => surface.TargetId, StringComparer.Ordinal)
                    .ToArray());
            ActivePanelName = activePanelName;
            ActivePanelInstanceId = activePanelInstanceId;
            ActivePanelTargetId = activePanelTargetId;
            FocusEpoch = focusEpoch;
            ModalEpoch = modalEpoch;
            BlockingModalKind = blockingModalKind;
            HumanReauthorizationRequired = humanReauthorizationRequired;
            ActiveTargetId = activeTargetId;
            DesktopAvailable = desktopAvailable;
        }

        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public SessionMode SessionMode { get; }
        public string Slot { get; }
        public long? SaveRevision { get; }
        public string AttemptId { get; }
        public ulong? AttemptGeneration { get; }
        public SessionProcessIdentity LauncherProcess { get; }
        public SessionProcessIdentity FlashProcess { get; }
        public string CoreSha256 { get; }
        public RuntimeQualificationRegistration RuntimeQualification { get; }
        public ReadOnlyCollection<string> Capabilities { get; }
        public ReadOnlyCollection<SessionSurfaceSnapshot> Surfaces { get; }
        public string ActivePanelName { get; }
        public string ActivePanelInstanceId { get; }
        public string ActivePanelTargetId { get; }
        public ulong FocusEpoch { get; }
        public ulong ModalEpoch { get; }
        public BlockingModalKind BlockingModalKind { get; }
        public bool HumanReauthorizationRequired { get; }
        public string ActiveTargetId { get; }
        public bool DesktopAvailable { get; }

        public string PanelInstanceIdForTarget(
            string targetId)
        {
            return targetId != null
                && string.Equals(
                    ActivePanelTargetId,
                    targetId,
                    StringComparison.Ordinal)
                ? ActivePanelInstanceId
                : null;
        }

        public SessionDescriptor ToContract()
        {
            return new SessionDescriptor
            {
                SessionId = SessionId,
                LifecycleGeneration = LifecycleGeneration,
                SessionMode = SessionMode,
                RuntimeMode = RuntimeQualification.RuntimeMode,
                AttemptId = AttemptId,
                AttemptGeneration = AttemptGeneration,
                Slot = Slot,
                SaveRevision = SaveRevision,
                LauncherPath = LauncherProcess.ExecutablePath,
                LauncherPid = LauncherProcess.ProcessId,
                LauncherStartTime = LauncherProcess.StartTimeUtc,
                FlashPid = FlashProcess?.ProcessId,
                FlashStartTime = FlashProcess?.StartTimeUtc,
                CoreSha256 = CoreSha256,
                RuntimeQualification = new RuntimeQualification
                {
                    BuildIdentity = RuntimeQualification.BuildIdentity,
                    PayloadClosure = RuntimeQualification.PayloadClosure,
                    UnqualifiedReason = RuntimeQualification.UnqualifiedReason
                },
                Surfaces = Surfaces.Select(surface => surface.ToContract()).ToList(),
                ActivePanel = ActivePanelInstanceId == null
                    ? null
                    : new ActivePanelDescriptor
                    {
                        Name = ActivePanelName,
                        InstanceId = ActivePanelInstanceId,
                        TargetId = ActivePanelTargetId
                    },
                Capabilities = Capabilities.ToList()
            };
        }

        private static ReadOnlyCollection<string> FreezeStrings(
            IEnumerable<string> values)
        {
            return Array.AsReadOnly(
                (values ?? Array.Empty<string>())
                    .Where(value => !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
        }
    }

    internal sealed class SessionSurfaceRegistrySnapshot
    {
        public SessionSurfaceRegistrySnapshot(
            ulong sequence,
            IEnumerable<SessionSnapshot> sessions)
        {
            Sequence = sequence;
            Sessions = Array.AsReadOnly(
                (sessions ?? Array.Empty<SessionSnapshot>())
                    .OrderBy(session => session.SessionId, StringComparer.Ordinal)
                    .ToArray());
        }

        public ulong Sequence { get; }
        public ReadOnlyCollection<SessionSnapshot> Sessions { get; }

        public SessionSnapshot FindSession(string sessionId)
        {
            return Sessions.FirstOrDefault(
                session => string.Equals(
                    session.SessionId,
                    sessionId,
                    StringComparison.Ordinal));
        }
    }

    internal sealed class SessionSurfaceRegistryChangedEventArgs : EventArgs
    {
        public SessionSurfaceRegistryChangedEventArgs(
            SessionSurfaceRegistrySnapshot snapshot,
            SessionScopeInvalidation invalidation)
        {
            Snapshot = snapshot
                ?? throw new ArgumentNullException(nameof(snapshot));
            Invalidation = invalidation
                ?? throw new ArgumentNullException(nameof(invalidation));
        }

        public SessionSurfaceRegistrySnapshot Snapshot { get; }
        public SessionScopeInvalidation Invalidation { get; }
    }

    internal sealed class SessionSurfaceRegistryChange
    {
        public SessionSurfaceRegistryChange(
            SessionSurfaceRegistrySnapshot snapshot,
            SessionScopeInvalidation invalidation,
            bool changed)
        {
            Snapshot = snapshot;
            Invalidation = invalidation;
            Changed = changed;
        }

        public SessionSurfaceRegistrySnapshot Snapshot { get; }
        public SessionScopeInvalidation Invalidation { get; }
        public bool Changed { get; }
    }
}
