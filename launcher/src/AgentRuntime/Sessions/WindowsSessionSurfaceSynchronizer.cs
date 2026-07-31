using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Sessions
{
    /// <summary>
    /// Host-owned specification for one already-known HWND. It contains no
    /// title, class-name, executable-name, or discovery predicate.
    /// </summary>
    internal sealed class WindowsSessionSurfaceSpec
    {
        private static readonly Regex OpaqueIdPattern = new Regex(
            "^[A-Za-z0-9_-]{22,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        public WindowsSessionSurfaceSpec(
            string targetId,
            SurfaceKind kind,
            AgentTargetSafetyKind safetyKind,
            SessionSurfaceOwnerRelation ownerRelation,
            SessionProcessIdentity ownerProcess,
            long knownWindowHandle,
            string ownerTargetId,
            long ownerWindowHandle,
            IEnumerable<ObservationMode> observationModes,
            IEnumerable<InputMode> inputModes,
            int zIndex)
        {
            RequireOpaque(targetId, nameof(targetId));
            if (!Enum.IsDefined(kind))
                throw new ArgumentOutOfRangeException(nameof(kind));
            if (!Enum.IsDefined(safetyKind))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(safetyKind));
            }
            if (!Enum.IsDefined(ownerRelation))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(ownerRelation));
            }
            if (ownerProcess == null)
                throw new ArgumentNullException(nameof(ownerProcess));
            if (knownWindowHandle <= 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(knownWindowHandle));
            }

            ObservationMode[] frozenObservation =
                FreezeModes(observationModes);
            InputMode[] frozenInput = FreezeModes(inputModes);
            bool owned =
                ownerRelation
                    == SessionSurfaceOwnerRelation.LauncherOwned
                || ownerRelation
                    == SessionSurfaceOwnerRelation.FlashOwned;
            if (owned)
            {
                RequireOpaque(
                    ownerTargetId,
                    nameof(ownerTargetId));
                if (ownerWindowHandle <= 0)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(ownerWindowHandle));
                }
            }
            else if (ownerTargetId != null
                || ownerWindowHandle != 0)
            {
                throw new ArgumentException(
                    "Only explicitly owned surfaces may name an owner.");
            }

            if (safetyKind
                == AgentTargetSafetyKind.HumanOnlySecuritySurface)
            {
                if (ownerRelation
                        != SessionSurfaceOwnerRelation
                            .HumanOnlySecurityReported
                    || frozenObservation.Length != 0
                    || frozenInput.Length != 0)
                {
                    throw new ArgumentException(
                        "Human-only surfaces must have no observation or input modes.");
                }
            }
            else if (ownerRelation
                    == SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported)
            {
                throw new ArgumentException(
                    "Runtime surfaces cannot use the human-only relation.");
            }
            else if (frozenObservation.Length == 0
                && (kind != SurfaceKind.Flash
                    || frozenInput.Length != 0))
            {
                throw new ArgumentException(
                    "Only Flash surfaces may be metadata-only, and they cannot advertise input modes.");
            }

            TargetId = targetId;
            Kind = kind;
            SafetyKind = safetyKind;
            OwnerRelation = ownerRelation;
            OwnerProcess = ownerProcess;
            KnownWindowHandle = knownWindowHandle;
            OwnerTargetId = ownerTargetId;
            OwnerWindowHandle = ownerWindowHandle;
            ObservationModes =
                Array.AsReadOnly(frozenObservation);
            InputModes = Array.AsReadOnly(frozenInput);
            ZIndex = zIndex;
        }

        public string TargetId { get; }
        public SurfaceKind Kind { get; }
        public AgentTargetSafetyKind SafetyKind { get; }
        public SessionSurfaceOwnerRelation OwnerRelation { get; }
        public SessionProcessIdentity OwnerProcess { get; }
        public long KnownWindowHandle { get; }
        public string OwnerTargetId { get; }
        public long OwnerWindowHandle { get; }
        public ReadOnlyCollection<ObservationMode> ObservationModes
        {
            get;
        }
        public ReadOnlyCollection<InputMode> InputModes { get; }
        public int ZIndex { get; }

        public bool IsOwned =>
            OwnerRelation
                == SessionSurfaceOwnerRelation.LauncherOwned
            || OwnerRelation
                == SessionSurfaceOwnerRelation.FlashOwned;

        private static T[] FreezeModes<T>(IEnumerable<T> modes)
            where T : struct, Enum
        {
            T[] supplied = (modes ?? Array.Empty<T>()).ToArray();
            if (supplied.Any(mode => !Enum.IsDefined(mode))
                || supplied.Distinct().Count() != supplied.Length)
            {
                throw new ArgumentException(
                    "Surface modes must be valid and unique.",
                    nameof(modes));
            }
            return supplied.OrderBy(mode => mode).ToArray();
        }

        private static void RequireOpaque(
            string value,
            string parameterName)
        {
            if (!OpaqueIdPattern.IsMatch(value ?? string.Empty))
            {
                throw new ArgumentException(
                    "An opaque surface target ID is required.",
                    parameterName);
            }
        }
    }

    internal sealed class WindowsSessionWindowSnapshot
    {
        public WindowsSessionWindowSnapshot(
            int processId,
            SessionPhysicalRect boundsPhysical,
            SessionPhysicalRect clientRectPhysical,
            SessionPhysicalRect contentRectPhysical,
            int dpi,
            bool visible,
            bool minimized)
        {
            if (processId <= 0)
                throw new ArgumentOutOfRangeException(nameof(processId));
            BoundsPhysical = boundsPhysical
                ?? throw new ArgumentNullException(
                    nameof(boundsPhysical));
            ClientRectPhysical = clientRectPhysical
                ?? throw new ArgumentNullException(
                    nameof(clientRectPhysical));
            ContentRectPhysical = contentRectPhysical
                ?? throw new ArgumentNullException(
                    nameof(contentRectPhysical));
            if (dpi < 48 || dpi > 960)
                throw new ArgumentOutOfRangeException(nameof(dpi));
            ProcessId = processId;
            Dpi = dpi;
            Visible = visible;
            Minimized = minimized;
        }

        public int ProcessId { get; }
        public SessionPhysicalRect BoundsPhysical { get; }
        public SessionPhysicalRect ClientRectPhysical { get; }
        public SessionPhysicalRect ContentRectPhysical { get; }
        public int Dpi { get; }
        public bool Visible { get; }
        public bool Minimized { get; }
    }

    internal sealed class WindowsSessionFocusSnapshot
    {
        public WindowsSessionFocusSnapshot(
            long foregroundWindowHandle,
            long focusWindowHandle)
        {
            if (foregroundWindowHandle <= 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(foregroundWindowHandle));
            }
            if (focusWindowHandle < 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(focusWindowHandle));
            }
            ForegroundWindowHandle = foregroundWindowHandle;
            FocusWindowHandle = focusWindowHandle;
        }

        public long ForegroundWindowHandle { get; }
        public long FocusWindowHandle { get; }
    }

    /// <summary>
    /// Probe contract deliberately has no enumeration or lookup-by-name API.
    /// Every window metrics call receives a host-supplied HWND.
    /// </summary>
    internal interface IWindowsSessionSurfaceProbe
    {
        bool IsInteractiveDesktopAvailable();

        bool TryProbeKnownWindow(
            long knownWindowHandle,
            out WindowsSessionWindowSnapshot snapshot);

        bool TryProbeFocus(
            out WindowsSessionFocusSnapshot snapshot);

        bool IsSameOrChildWindow(
            long knownAncestorWindowHandle,
            long candidateWindowHandle);
    }

    internal sealed class Win32SessionSurfaceProbe
        : IWindowsSessionSurfaceProbe
    {
        private const uint DesktopReadObjects = 0x0001;
        private const uint DesktopSwitchDesktop = 0x0100;
        private const int UoiName = 2;

        public bool IsInteractiveDesktopAvailable()
        {
            IntPtr desktop = OpenInputDesktop(
                0,
                false,
                DesktopReadObjects | DesktopSwitchDesktop);
            if (desktop == IntPtr.Zero)
                return false;
            try
            {
                var name = new StringBuilder(256);
                return GetUserObjectInformation(
                        desktop,
                        UoiName,
                        name,
                        checked(name.Capacity * sizeof(char)),
                        out _)
                    && string.Equals(
                        name.ToString(),
                        "Default",
                        StringComparison.OrdinalIgnoreCase)
                    && GetForegroundWindow() != IntPtr.Zero;
            }
            finally
            {
                CloseDesktop(desktop);
            }
        }

        public bool TryProbeKnownWindow(
            long knownWindowHandle,
            out WindowsSessionWindowSnapshot snapshot)
        {
            snapshot = null;
            if (knownWindowHandle <= 0)
                return false;
            IntPtr hwnd = new IntPtr(knownWindowHandle);
            if (!IsWindow(hwnd))
                return false;
            uint threadId = GetWindowThreadProcessId(
                hwnd,
                out uint rawProcessId);
            if (threadId == 0
                || rawProcessId == 0
                || rawProcessId > int.MaxValue
                || !GetWindowRect(hwnd, out NativeRect windowRect)
                || !GetClientRect(hwnd, out NativeRect localClient))
            {
                return false;
            }

            var clientTopLeft = new NativePoint
            {
                X = localClient.Left,
                Y = localClient.Top
            };
            var clientBottomRight = new NativePoint
            {
                X = localClient.Right,
                Y = localClient.Bottom
            };
            if (!ClientToScreen(hwnd, ref clientTopLeft)
                || !ClientToScreen(hwnd, ref clientBottomRight))
            {
                return false;
            }
            if (!TryRect(
                    windowRect.Left,
                    windowRect.Top,
                    windowRect.Right,
                    windowRect.Bottom,
                    out SessionPhysicalRect bounds)
                || !TryRect(
                    clientTopLeft.X,
                    clientTopLeft.Y,
                    clientBottomRight.X,
                    clientBottomRight.Y,
                    out SessionPhysicalRect client))
            {
                return false;
            }
            uint rawDpi;
            try
            {
                rawDpi = GetDpiForWindow(hwnd);
            }
            catch (EntryPointNotFoundException)
            {
                return false;
            }
            if (rawDpi < 48 || rawDpi > 960)
                return false;

            snapshot = new WindowsSessionWindowSnapshot(
                checked((int)rawProcessId),
                bounds,
                client,
                new SessionPhysicalRect(
                    client.X,
                    client.Y,
                    client.Width,
                    client.Height),
                checked((int)rawDpi),
                IsWindowVisible(hwnd),
                IsIconic(hwnd));
            return true;
        }

        public bool TryProbeFocus(
            out WindowsSessionFocusSnapshot snapshot)
        {
            snapshot = null;
            IntPtr foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero)
                return false;
            uint threadId = GetWindowThreadProcessId(
                foreground,
                out _);
            if (threadId == 0)
                return false;
            var info = new GuiThreadInfo
            {
                Size = checked(
                    (uint)Marshal.SizeOf<GuiThreadInfo>())
            };
            if (!GetGUIThreadInfo(threadId, ref info))
                return false;
            snapshot = new WindowsSessionFocusSnapshot(
                foreground.ToInt64(),
                info.FocusWindow.ToInt64());
            return true;
        }

        public bool IsSameOrChildWindow(
            long knownAncestorWindowHandle,
            long candidateWindowHandle)
        {
            if (knownAncestorWindowHandle <= 0
                || candidateWindowHandle <= 0)
            {
                return false;
            }
            if (knownAncestorWindowHandle
                == candidateWindowHandle)
            {
                return true;
            }
            return IsChild(
                new IntPtr(knownAncestorWindowHandle),
                new IntPtr(candidateWindowHandle));
        }

        private static bool TryRect(
            int left,
            int top,
            int right,
            int bottom,
            out SessionPhysicalRect value)
        {
            value = null;
            long width = (long)right - left;
            long height = (long)bottom - top;
            if (width <= 0
                || width > int.MaxValue
                || height <= 0
                || height > int.MaxValue)
            {
                return false;
            }
            value = new SessionPhysicalRect(
                left,
                top,
                checked((int)width),
                checked((int)height));
            return true;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct NativePoint
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct GuiThreadInfo
        {
            public uint Size;
            public uint Flags;
            public IntPtr ActiveWindow;
            public IntPtr FocusWindow;
            public IntPtr CaptureWindow;
            public IntPtr MenuOwnerWindow;
            public IntPtr MoveSizeWindow;
            public IntPtr CaretWindow;
            public NativeRect CaretRect;
        }

        [DllImport(
            "user32.dll",
            SetLastError = true)]
        private static extern IntPtr OpenInputDesktop(
            uint flags,
            [MarshalAs(UnmanagedType.Bool)] bool inherit,
            uint desiredAccess);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseDesktop(IntPtr desktop);

        [DllImport(
            "user32.dll",
            CharSet = CharSet.Unicode,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetUserObjectInformation(
            IntPtr handle,
            int index,
            StringBuilder information,
            int length,
            out int needed);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr windowHandle);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(
            IntPtr windowHandle,
            out uint processId);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(
            IntPtr windowHandle,
            out NativeRect rect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetClientRect(
            IntPtr windowHandle,
            out NativeRect rect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ClientToScreen(
            IntPtr windowHandle,
            ref NativePoint point);

        [DllImport("user32.dll")]
        private static extern uint GetDpiForWindow(
            IntPtr windowHandle);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(
            IntPtr windowHandle);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(
            IntPtr windowHandle);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetGUIThreadInfo(
            uint threadId,
            ref GuiThreadInfo info);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsChild(
            IntPtr parentWindow,
            IntPtr candidateWindow);
    }

    internal sealed class WindowsSessionSurfaceRefreshResult
    {
        public WindowsSessionSurfaceRefreshResult(
            bool desktopAvailable,
            int synchronizedSurfaceCount,
            int removedSurfaceCount,
            string activeTargetId,
            IEnumerable<string> reasonCodes)
        {
            DesktopAvailable = desktopAvailable;
            SynchronizedSurfaceCount =
                synchronizedSurfaceCount;
            RemovedSurfaceCount = removedSurfaceCount;
            ActiveTargetId = activeTargetId;
            ReasonCodes = Array.AsReadOnly(
                (reasonCodes ?? Array.Empty<string>())
                    .Where(reason =>
                        !string.IsNullOrWhiteSpace(reason))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(reason => reason, StringComparer.Ordinal)
                    .ToArray());
        }

        public bool DesktopAvailable { get; }
        public int SynchronizedSurfaceCount { get; }
        public int RemovedSurfaceCount { get; }
        public string ActiveTargetId { get; }
        public ReadOnlyCollection<string> ReasonCodes { get; }
    }

    /// <summary>
    /// Synchronizes only HWNDs explicitly supplied by the Launcher host. This
    /// type never enumerates windows/processes and never derives identity from
    /// titles, classes, paths, or executable names.
    /// </summary>
    internal sealed class WindowsSessionSurfaceSynchronizer
        : IDisposable
    {
        private readonly object _sync = new object();
        private readonly SessionSurfaceHostController _controller;
        private readonly Func<
            IReadOnlyCollection<WindowsSessionSurfaceSpec>>
                _surfaceSource;
        private readonly IWindowsSessionSurfaceProbe _probe;
        private readonly Action<WindowsSessionSurfaceRefreshResult>
            _refreshCompleted;
        private readonly HashSet<string> _managedTargetIds =
            new HashSet<string>(StringComparer.Ordinal);
        private Timer _timer;
        private bool _disposed;

        public WindowsSessionSurfaceSynchronizer(
            SessionSurfaceHostController controller,
            Func<IReadOnlyCollection<WindowsSessionSurfaceSpec>>
                surfaceSource,
            IWindowsSessionSurfaceProbe probe = null,
            Action<WindowsSessionSurfaceRefreshResult>
                refreshCompleted = null)
        {
            _controller = controller
                ?? throw new ArgumentNullException(
                    nameof(controller));
            _surfaceSource = surfaceSource
                ?? throw new ArgumentNullException(
                    nameof(surfaceSource));
            _probe = probe ?? new Win32SessionSurfaceProbe();
            _refreshCompleted = refreshCompleted;
        }

        public WindowsSessionSurfaceRefreshResult LastResult
        {
            get;
            private set;
        }

        public void Start(TimeSpan interval)
        {
            if (interval < TimeSpan.FromMilliseconds(50)
                || interval > TimeSpan.FromMinutes(1))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(interval));
            }
            lock (_sync)
            {
                ThrowIfDisposed();
                _timer?.Dispose();
                _timer = new Timer(
                    _ => RefreshFromTimer(),
                    null,
                    TimeSpan.Zero,
                    interval);
            }
        }

        public void Stop()
        {
            lock (_sync)
            {
                _timer?.Dispose();
                _timer = null;
            }
        }

        public WindowsSessionSurfaceRefreshResult Refresh()
        {
            WindowsSessionSurfaceRefreshResult result;
            lock (_sync)
            {
                ThrowIfDisposed();
                result = RefreshLocked();
                LastResult = result;
            }
            TryNotifyRefreshCompleted(result);
            return result;
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                _timer?.Dispose();
                _timer = null;
                RemoveAllManagedLocked(null);
                TrySetFocus(null);
            }
        }

        private WindowsSessionSurfaceRefreshResult RefreshLocked()
        {
            var reasons = new List<string>();
            IReadOnlyCollection<WindowsSessionSurfaceSpec> source;
            try
            {
                source = _surfaceSource()
                    ?? Array.Empty<WindowsSessionSurfaceSpec>();
            }
            catch
            {
                int removed = RemoveAllManagedLocked(reasons);
                TrySetFocus(null);
                TrySetDesktopAvailable(false);
                reasons.Add("surface_spec_source_failed");
                return new WindowsSessionSurfaceRefreshResult(
                    false,
                    0,
                    removed,
                    null,
                    reasons);
            }

            WindowsSessionSurfaceSpec[] specs = source.ToArray();
            if (specs.Any(spec => spec == null)
                || specs.Select(spec => spec.TargetId)
                    .Distinct(StringComparer.Ordinal)
                    .Count() != specs.Length
                || specs.Select(spec => spec.KnownWindowHandle)
                    .Distinct()
                    .Count() != specs.Length)
            {
                int removed = RemoveAllManagedLocked(reasons);
                TrySetFocus(null);
                TrySetDesktopAvailable(false);
                reasons.Add("surface_spec_set_invalid");
                return new WindowsSessionSurfaceRefreshResult(
                    false,
                    0,
                    removed,
                    null,
                    reasons);
            }

            bool desktopAvailable;
            try
            {
                desktopAvailable =
                    _probe.IsInteractiveDesktopAvailable();
            }
            catch
            {
                desktopAvailable = false;
            }
            if (!desktopAvailable)
            {
                int removed = RemoveAllManagedLocked(reasons);
                TrySetDesktopAvailable(false);
                reasons.Add("interactive_desktop_unavailable");
                return new WindowsSessionSurfaceRefreshResult(
                    false,
                    0,
                    removed,
                    null,
                    reasons);
            }
            TrySetDesktopAvailable(true);

            var currentIds = specs
                .Select(spec => spec.TargetId)
                .ToHashSet(StringComparer.Ordinal);
            int removedCount = 0;
            foreach (string retired in _managedTargetIds
                .Where(id => !currentIds.Contains(id))
                .ToArray())
            {
                if (TryRemoveSurface(retired))
                    removedCount++;
                _managedTargetIds.Remove(retired);
            }
            foreach (string targetId in currentIds)
                _managedTargetIds.Add(targetId);

            var candidates = new Dictionary<
                string,
                ProbedSurface>(StringComparer.Ordinal);
            foreach (WindowsSessionSurfaceSpec spec in specs)
            {
                WindowsSessionWindowSnapshot snapshot;
                bool probed;
                try
                {
                    probed = _probe.TryProbeKnownWindow(
                        spec.KnownWindowHandle,
                        out snapshot);
                }
                catch
                {
                    probed = false;
                    snapshot = null;
                }
                if (!probed
                    || snapshot == null
                    || snapshot.ProcessId
                        != spec.OwnerProcess.ProcessId)
                {
                    if (TryRemoveSurface(spec.TargetId))
                        removedCount++;
                    reasons.Add(
                        !probed || snapshot == null
                            ? "known_hwnd_unavailable"
                            : "known_hwnd_pid_mismatch");
                    continue;
                }
                candidates.Add(
                    spec.TargetId,
                    new ProbedSurface(spec, snapshot));
            }

            int synchronizedCount = 0;
            var synchronized = new HashSet<string>(
                StringComparer.Ordinal);
            foreach (ProbedSurface candidate
                in candidates.Values
                    .Where(value => !value.Spec.IsOwned)
                    .OrderBy(value => value.Spec.ZIndex)
                    .ThenBy(
                        value => value.Spec.TargetId,
                        StringComparer.Ordinal))
            {
                if (TrySynchronize(
                        candidate,
                        reasons,
                        out bool removedDuringSynchronization))
                {
                    synchronized.Add(candidate.Spec.TargetId);
                    synchronizedCount++;
                }
                else if (removedDuringSynchronization
                    || TryRemoveSurface(
                        candidate.Spec.TargetId))
                {
                    removedCount++;
                }
            }

            var pendingOwned = candidates.Values
                .Where(value => value.Spec.IsOwned)
                .OrderBy(value => value.Spec.ZIndex)
                .ThenBy(
                    value => value.Spec.TargetId,
                    StringComparer.Ordinal)
                .ToList();
            bool progressed;
            do
            {
                progressed = false;
                foreach (ProbedSurface candidate
                    in pendingOwned.ToArray())
                {
                    bool ownerReady = synchronized.Contains(
                            candidate.Spec.OwnerTargetId)
                        || _controller.Snapshot.Surfaces.Any(
                            surface => string.Equals(
                                surface.TargetId,
                                candidate.Spec.OwnerTargetId,
                                StringComparison.Ordinal)
                                && surface.WindowHandle
                                    == candidate.Spec
                                        .OwnerWindowHandle);
                    if (!ownerReady)
                        continue;
                    pendingOwned.Remove(candidate);
                    progressed = true;
                    if (TrySynchronize(
                            candidate,
                            reasons,
                            out bool removedDuringSynchronization))
                    {
                        synchronized.Add(
                            candidate.Spec.TargetId);
                        synchronizedCount++;
                    }
                    else if (removedDuringSynchronization
                        || TryRemoveSurface(
                            candidate.Spec.TargetId))
                    {
                        removedCount++;
                    }
                }
            }
            while (progressed && pendingOwned.Count != 0);

            foreach (ProbedSurface unresolved in pendingOwned)
            {
                if (TryRemoveSurface(unresolved.Spec.TargetId))
                    removedCount++;
                reasons.Add("surface_owner_not_synchronized");
            }

            string activeTarget = ResolveActiveTarget(
                candidates,
                synchronized,
                reasons);
            TrySetFocus(activeTarget);
            return new WindowsSessionSurfaceRefreshResult(
                true,
                synchronizedCount,
                removedCount,
                activeTarget,
                reasons);
        }

        private bool TrySynchronize(
            ProbedSurface candidate,
            ICollection<string> reasons,
            out bool removedDuringSynchronization)
        {
            bool existedBefore = SurfaceExists(
                candidate.Spec.TargetId);
            removedDuringSynchronization = false;
            WindowsSessionSurfaceSpec spec = candidate.Spec;
            WindowsSessionWindowSnapshot snapshot =
                candidate.Snapshot;
            try
            {
                _controller.SynchronizeSurface(
                    new SessionSurfaceHostRegistration
                    {
                        TargetId = spec.TargetId,
                        Kind = spec.Kind,
                        SafetyKind = spec.SafetyKind,
                        OwnerRelation = spec.OwnerRelation,
                        OwnerProcess = spec.OwnerProcess,
                        WindowHandle = spec.KnownWindowHandle,
                        OwnerTargetId = spec.OwnerTargetId,
                        OwnerWindowHandle =
                            spec.OwnerWindowHandle,
                        BoundsPhysical =
                            snapshot.BoundsPhysical,
                        ClientRectPhysical =
                            snapshot.ClientRectPhysical,
                        ContentRectPhysical =
                            snapshot.ContentRectPhysical,
                        Dpi = snapshot.Dpi,
                        ZIndex = spec.ZIndex,
                        Visible = snapshot.Visible,
                        Minimized = snapshot.Minimized,
                        ObservationModes =
                            spec.ObservationModes,
                        InputModes = spec.InputModes
                    });
                return true;
            }
            catch
            {
                removedDuringSynchronization =
                    existedBefore
                    && !SurfaceExists(spec.TargetId);
                reasons.Add("surface_synchronize_rejected");
                return false;
            }
        }

        private bool SurfaceExists(string targetId)
        {
            try
            {
                return _controller.Snapshot.Surfaces.Any(
                    surface => string.Equals(
                        surface.TargetId,
                        targetId,
                        StringComparison.Ordinal));
            }
            catch
            {
                return false;
            }
        }

        private string ResolveActiveTarget(
            IReadOnlyDictionary<string, ProbedSurface> candidates,
            IReadOnlySet<string> synchronized,
            ICollection<string> reasons)
        {
            WindowsSessionFocusSnapshot focus;
            try
            {
                if (!_probe.TryProbeFocus(out focus)
                    || focus == null)
                {
                    reasons.Add("focus_probe_failed");
                    return null;
                }
            }
            catch
            {
                reasons.Add("focus_probe_failed");
                return null;
            }

            ProbedSurface[] focusable = candidates.Values
                .Where(candidate =>
                    synchronized.Contains(
                        candidate.Spec.TargetId)
                    && candidate.Spec.SafetyKind
                        == AgentTargetSafetyKind.RuntimeOwned
                    && candidate.Snapshot.Visible
                    && !candidate.Snapshot.Minimized)
                .ToArray();
            bool foregroundBelongs = focusable.Any(
                candidate =>
                    IsWithinKnownSurface(
                        candidate.Spec.KnownWindowHandle,
                        focus.ForegroundWindowHandle)
                    || IsWithinKnownSurface(
                        focus.ForegroundWindowHandle,
                        candidate.Spec.KnownWindowHandle));
            if (!foregroundBelongs)
            {
                reasons.Add("foreground_outside_known_surfaces");
                return null;
            }

            long focusedHwnd = focus.FocusWindowHandle;
            if (focusedHwnd > 0)
            {
                ProbedSurface exact = focusable.FirstOrDefault(
                    candidate =>
                        candidate.Spec.KnownWindowHandle
                            == focusedHwnd);
                if (exact != null)
                    return exact.Spec.TargetId;

                ProbedSurface containing = focusable
                    .Where(candidate => IsWithinKnownSurface(
                        candidate.Spec.KnownWindowHandle,
                        focusedHwnd))
                    .OrderBy(candidate =>
                        Area(candidate.Snapshot.ClientRectPhysical))
                    .ThenByDescending(
                        candidate => candidate.Spec.ZIndex)
                    .ThenBy(
                        candidate => candidate.Spec.TargetId,
                        StringComparer.Ordinal)
                    .FirstOrDefault();
                if (containing != null)
                    return containing.Spec.TargetId;
                reasons.Add("focus_outside_known_surfaces");
                return null;
            }

            ProbedSurface foreground = focusable.FirstOrDefault(
                candidate =>
                    candidate.Spec.KnownWindowHandle
                        == focus.ForegroundWindowHandle);
            return foreground?.Spec.TargetId;
        }

        private bool IsWithinKnownSurface(
            long knownHwnd,
            long candidateHwnd)
        {
            try
            {
                return _probe.IsSameOrChildWindow(
                    knownHwnd,
                    candidateHwnd);
            }
            catch
            {
                return false;
            }
        }

        private int RemoveAllManagedLocked(
            ICollection<string> reasons)
        {
            int removed = 0;
            foreach (string targetId
                in _managedTargetIds.ToArray())
            {
                if (TryRemoveSurface(targetId))
                    removed++;
            }
            _managedTargetIds.Clear();
            reasons?.Add("managed_surfaces_cleared");
            return removed;
        }

        private bool TryRemoveSurface(string targetId)
        {
            try
            {
                bool existed = _controller.Snapshot.Surfaces.Any(
                    surface => string.Equals(
                        surface.TargetId,
                        targetId,
                        StringComparison.Ordinal));
                _controller.RemoveSurface(targetId);
                return existed;
            }
            catch
            {
                return false;
            }
        }

        private void TrySetFocus(string targetId)
        {
            try
            {
                _controller.SetFocus(targetId);
            }
            catch
            {
                try
                {
                    _controller.SetFocus(null);
                }
                catch
                {
                }
            }
        }

        private void TrySetDesktopAvailable(bool available)
        {
            try
            {
                _controller.SetDesktopAvailable(available);
            }
            catch
            {
            }
        }

        private void RefreshFromTimer()
        {
            try
            {
                Refresh();
            }
            catch (ObjectDisposedException)
            {
            }
            catch
            {
                lock (_sync)
                {
                    if (_disposed)
                        return;
                    int removed = RemoveAllManagedLocked(null);
                    TrySetFocus(null);
                    TrySetDesktopAvailable(false);
                    LastResult =
                        new WindowsSessionSurfaceRefreshResult(
                            false,
                            0,
                            removed,
                            null,
                            new[]
                            {
                                "timer_refresh_failed"
                            });
                }
            }
        }

        private void TryNotifyRefreshCompleted(
            WindowsSessionSurfaceRefreshResult result)
        {
            try
            {
                _refreshCompleted?.Invoke(result);
            }
            catch
            {
                // Surface state is already committed. A dependent bootstrap
                // retry must fail closed without converting the refresh into
                // a false failure or running while the synchronizer lock is
                // held.
            }
        }

        private static long Area(SessionPhysicalRect rect)
        {
            return checked((long)rect.Width * rect.Height);
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
            {
                throw new ObjectDisposedException(
                    nameof(
                        WindowsSessionSurfaceSynchronizer));
            }
        }

        private sealed class ProbedSurface
        {
            public ProbedSurface(
                WindowsSessionSurfaceSpec spec,
                WindowsSessionWindowSnapshot snapshot)
            {
                Spec = spec;
                Snapshot = snapshot;
            }

            public WindowsSessionSurfaceSpec Spec { get; }
            public WindowsSessionWindowSnapshot Snapshot { get; }
        }
    }
}
