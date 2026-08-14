using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using Microsoft.Win32.SafeHandles;

namespace CF7Launcher.AgentRuntime.Sessions
{
    internal interface ISessionTopLevelWindowResolver
    {
        IntPtr ResolveTopLevel(IntPtr registeredHwnd);
    }

    internal sealed class WindowsSessionTopLevelWindowResolver
        : ISessionTopLevelWindowResolver
    {
        public IntPtr ResolveTopLevel(IntPtr registeredHwnd)
        {
            if (registeredHwnd == IntPtr.Zero)
                return IntPtr.Zero;
            IntPtr root = GetAncestor(registeredHwnd, 2);
            return root == IntPtr.Zero
                ? registeredHwnd
                : root;
        }

        [DllImport(
            "user32.dll",
            ExactSpelling = true)]
        private static extern IntPtr GetAncestor(
            IntPtr hwnd,
            uint flags);
    }

    internal interface ISessionProcessIdentitySignalFactory
    {
        bool TryCapture(
            SessionProcessIdentity expected,
            out INativeInputProcessIdentitySignal signal);
    }

    /// <summary>
    /// Captures a kernel process handle only after exact PID/start/path
    /// validation. The handle remains bound to that process incarnation even
    /// if Windows later reuses the PID.
    /// </summary>
    internal sealed class SystemSessionProcessIdentitySignalFactory
        : ISessionProcessIdentitySignalFactory
    {
        public bool TryCapture(
            SessionProcessIdentity expected,
            out INativeInputProcessIdentitySignal signal)
        {
            signal = null;
            if (expected == null)
                return false;

            Process process = null;
            try
            {
                process = Process.GetProcessById(
                    expected.ProcessId);
                if (process.HasExited)
                    return false;

                SafeProcessHandle processHandle =
                    process.SafeHandle;
                if (processHandle == null
                    || processHandle.IsInvalid
                    || processHandle.IsClosed)
                {
                    return false;
                }

                DateTimeOffset startTime =
                    new DateTimeOffset(
                        process.StartTime.ToUniversalTime());
                string path = process.MainModule?.FileName;
                if (startTime.UtcDateTime.Ticks
                        != expected.StartTimeUtc.UtcDateTime.Ticks
                    || path == null
                    || !string.Equals(
                        Path.GetFullPath(path),
                        expected.ExecutablePath,
                        StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                signal = new SystemProcessIdentitySignal(
                    process,
                    processHandle);
                process = null;
                if (!signal.IsAliveBounded())
                {
                    signal.Dispose();
                    signal = null;
                    return false;
                }
                return true;
            }
            catch
            {
                return false;
            }
            finally
            {
                process?.Dispose();
            }
        }

        private sealed class SystemProcessIdentitySignal
            : INativeInputProcessIdentitySignal
        {
            private const uint WaitTimeout = 0x00000102;
            private readonly Process _process;
            private readonly SafeProcessHandle _processHandle;
            private int _disposed;

            internal SystemProcessIdentitySignal(
                Process process,
                SafeProcessHandle processHandle)
            {
                _process = process;
                _processHandle = processHandle;
            }

            public bool IsAliveBounded()
            {
                if (Volatile.Read(ref _disposed) != 0
                    || _processHandle.IsInvalid
                    || _processHandle.IsClosed)
                {
                    return false;
                }
                try
                {
                    return WaitForSingleObject(
                            _processHandle,
                            0)
                        == WaitTimeout;
                }
                catch
                {
                    return false;
                }
            }

            public void Dispose()
            {
                if (Interlocked.Exchange(
                        ref _disposed,
                        1) == 0)
                {
                    _process.Dispose();
                }
            }

            [DllImport(
                "kernel32.dll",
                ExactSpelling = true,
                SetLastError = true)]
            private static extern uint WaitForSingleObject(
                SafeProcessHandle handle,
                uint milliseconds);
        }
    }

    /// <summary>
    /// Projects the host-owned session registry into native-input authority.
    /// Caller-thread dispatch resolution performs exact live identity probes;
    /// hook callbacks consume only the captured process handle, HWND ownership,
    /// and in-memory generations.
    /// </summary>
    internal sealed class SessionNativeInputAuthority
        : IAuthoritativeNativeInputTarget
    {
        private readonly SessionSurfaceRegistry _registry;
        private readonly ISessionTopLevelWindowResolver
            _topLevelWindows;
        private readonly ISessionProcessIdentitySignalFactory
            _processIdentitySignals;
        private readonly ISessionWindowProbe _windowProbe;
        private readonly object _invalidatedSync =
            new object();
        private readonly Dictionary<string, InvalidatedGeneration>
            _invalidatedGenerations =
                new Dictionary<string, InvalidatedGeneration>(
                    StringComparer.Ordinal);

        public SessionNativeInputAuthority(
            SessionSurfaceRegistry registry,
            ISessionTopLevelWindowResolver topLevelWindows = null,
            ISessionProcessIdentitySignalFactory
                processIdentitySignals = null,
            ISessionWindowProbe windowProbe = null)
        {
            _registry = registry
                ?? throw new ArgumentNullException(nameof(registry));
            _topLevelWindows = topLevelWindows
                ?? new WindowsSessionTopLevelWindowResolver();
            _processIdentitySignals = processIdentitySignals
                ?? new SystemSessionProcessIdentitySignalFactory();
            _windowProbe = windowProbe
                ?? new WindowsSessionWindowProbe();
        }

        public bool TryResolve(
            string sessionId,
            string targetId,
            out NativeInputTargetSnapshot target,
            out string reasonCode)
        {
            return TryResolveCore(
                sessionId,
                targetId,
                true,
                out target,
                out reasonCode);
        }

        private bool TryResolveBounded(
            string sessionId,
            string targetId,
            out NativeInputTargetSnapshot target,
            out string reasonCode)
        {
            return TryResolveCore(
                sessionId,
                targetId,
                false,
                out target,
                out reasonCode);
        }

        private bool TryResolveCore(
            string sessionId,
            string targetId,
            bool validateLiveSurfaceIdentity,
            out NativeInputTargetSnapshot target,
            out string reasonCode)
        {
            target = null;
            SessionSurfaceRegistrySnapshot registrySnapshot =
                _registry.GetSnapshot();
            SessionSnapshot session =
                registrySnapshot.FindSession(sessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }

            SessionSurfaceSnapshot observed = session.Surfaces
                .FirstOrDefault(surface => string.Equals(
                    surface.TargetId,
                    targetId,
                    StringComparison.Ordinal));
            if (observed == null)
            {
                reasonCode = "target_not_found";
                return false;
            }
            if (observed.SafetyKind
                != AgentTargetSafetyKind.RuntimeOwned)
            {
                reasonCode = "human_only_security_surface";
                return false;
            }
            if (!TryCreateExpectation(
                    session,
                    observed,
                    out SessionTargetGenerationExpectation expectation,
                    out reasonCode))
            {
                return false;
            }
            SessionSurfaceSnapshot validated;
            bool generationValid = validateLiveSurfaceIdentity
                ? _registry.TryValidateTargetGeneration(
                    expectation,
                    InputMode.SendInputGuarded,
                    out validated,
                    out reasonCode)
                : _registry.TryValidateTargetGenerationBounded(
                    expectation,
                    InputMode.SendInputGuarded,
                    out validated,
                    out reasonCode);
            if (!generationValid)
            {
                return false;
            }
            if (validated.WindowHandle == 0
                || validated.OwnerProcess == null)
            {
                reasonCode = "target_not_found";
                return false;
            }
            if (!TryCreateEpochs(
                    session,
                    validated,
                    out InputEpochSnapshot epochs))
            {
                reasonCode = "stale_observation";
                return false;
            }

            IntPtr registeredHwnd =
                new IntPtr(validated.WindowHandle);
            IntPtr topLevelHwnd =
                _topLevelWindows.ResolveTopLevel(
                    registeredHwnd);
            if (topLevelHwnd == IntPtr.Zero)
            {
                reasonCode = "target_not_found";
                return false;
            }
            target = new NativeInputTargetSnapshot(
                session.SessionId,
                validated.TargetId,
                registeredHwnd,
                topLevelHwnd,
                validated.OwnerProcess.ProcessId,
                epochs,
                validated.Visible,
                validated.Minimized,
                IsSecurityModalLatched(session));
            if (IsInvalidated(target, out reasonCode))
            {
                target = null;
                return false;
            }
            reasonCode = null;
            return true;
        }

        public bool TryResolveForDispatch(
            string sessionId,
            string targetId,
            out NativeInputTargetSnapshot target,
            out string reasonCode)
        {
            target = null;
            if (!TryResolveBounded(
                    sessionId,
                    targetId,
                    out NativeInputTargetSnapshot bounded,
                    out reasonCode))
            {
                return false;
            }

            SessionSurfaceRegistrySnapshot registrySnapshot =
                _registry.GetSnapshot();
            SessionSnapshot session =
                registrySnapshot.FindSession(sessionId);
            SessionSurfaceSnapshot observed = session?.Surfaces
                .FirstOrDefault(surface => string.Equals(
                    surface.TargetId,
                    targetId,
                    StringComparison.Ordinal));
            if (session == null
                || observed == null
                || !TryCreateExpectation(
                    session,
                    observed,
                    out SessionTargetGenerationExpectation expectation,
                    out reasonCode))
            {
                Invalidate(bounded, reasonCode);
                return false;
            }

            if (!_registry.TryValidateTargetGeneration(
                    expectation,
                    InputMode.SendInputGuarded,
                    out SessionSurfaceSnapshot validated,
                    out reasonCode))
            {
                Invalidate(bounded, reasonCode);
                return false;
            }
            if (!SnapshotIdentityMatches(
                    bounded,
                    validated))
            {
                reasonCode = "stale_surface";
                Invalidate(bounded, reasonCode);
                return false;
            }
            if (!TryValidateLiveWindowIdentity(
                    session,
                    validated,
                    out long expectedOwnerWindowHandle,
                    out INativeInputProcessIdentitySignal
                        ownerIdentitySignal,
                    out reasonCode))
            {
                Invalidate(bounded, reasonCode);
                return false;
            }
            if (!TryCaptureProcessIdentitySignal(
                    validated.OwnerProcess,
                    out INativeInputProcessIdentitySignal signal))
            {
                ownerIdentitySignal?.Dispose();
                reasonCode = "surface_owner_process_stale";
                Invalidate(bounded, reasonCode);
                return false;
            }
            if (ownerIdentitySignal != null)
            {
                signal = new CompositeProcessIdentitySignal(
                    signal,
                    ownerIdentitySignal);
                ownerIdentitySignal = null;
            }

            try
            {
                // Close the validation/capture race using only in-memory
                // generations and bounded HWND/handle checks.
                if (!IsProcessSignalAliveBounded(signal)
                    || !TryValidateBoundedWindowIdentity(
                        validated.WindowHandle,
                        validated.OwnerProcess.ProcessId,
                        expectedOwnerWindowHandle,
                        out reasonCode)
                    || !_registry.TryValidateTargetGenerationBounded(
                        expectation,
                        InputMode.SendInputGuarded,
                        out SessionSurfaceSnapshot finalSurface,
                        out reasonCode)
                    || !SnapshotIdentityMatches(
                        bounded,
                        finalSurface)
                    || finalSurface.OwnerProcess == null
                    || !validated.OwnerProcess.IsExact(
                        finalSurface.OwnerProcess)
                    || validated.OwnerRelation
                        != finalSurface.OwnerRelation
                    || validated.OwnerWindowHandle
                        != finalSurface.OwnerWindowHandle
                    || !string.Equals(
                        validated.OwnerTargetId,
                        finalSurface.OwnerTargetId,
                        StringComparison.Ordinal))
                {
                    reasonCode ??=
                        "surface_owner_process_stale";
                    Invalidate(bounded, reasonCode);
                    return false;
                }

                target = new NativeInputTargetSnapshot(
                    bounded.SessionId,
                    bounded.TargetId,
                    bounded.TargetHwnd,
                    bounded.TopLevelHwnd,
                    bounded.OwnerProcessId,
                    bounded.Epochs,
                    bounded.Visible,
                    bounded.Minimized,
                    bounded.SecurityModalLatched,
                    expectedOwnerWindowHandle,
                    signal);
                signal = null;
                reasonCode = null;
                return true;
            }
            finally
            {
                signal?.Dispose();
            }
        }

        public bool TryValidateDispatchIdentity(
            NativeInputTargetSnapshot target,
            out string reasonCode)
        {
            if (target == null
                || !target.HasBoundedProcessIdentitySignal)
            {
                reasonCode = "surface_owner_process_stale";
                return false;
            }
            if (IsInvalidated(target, out reasonCode))
            {
                return false;
            }

            bool processAlive;
            try
            {
                processAlive =
                    target.IsProcessIdentityAliveBounded();
            }
            catch
            {
                processAlive = false;
            }
            if (!processAlive)
            {
                reasonCode = "surface_owner_process_stale";
                Invalidate(target, reasonCode);
                return false;
            }
            if (!TryValidateBoundedWindowIdentity(
                    target.TargetHwnd.ToInt64(),
                    target.OwnerProcessId,
                    target.ExpectedOwnerWindowHandle,
                    out reasonCode))
            {
                Invalidate(target, reasonCode);
                return false;
            }

            if (!TryResolveBounded(
                    target.SessionId,
                    target.TargetId,
                    out NativeInputTargetSnapshot current,
                    out reasonCode)
                || current.TargetHwnd != target.TargetHwnd
                || current.TopLevelHwnd != target.TopLevelHwnd
                || current.OwnerProcessId
                    != target.OwnerProcessId
                || !NativeInputEpochComparer.ExactEquals(
                    current.Epochs,
                    target.Epochs))
            {
                reasonCode ??= "stale_observation";
                return false;
            }
            reasonCode = null;
            return true;
        }

        public bool IsRegisteredInputWindow(
            NativeInputTargetSnapshot target,
            IntPtr candidateHwnd)
        {
            if (target == null
                || candidateHwnd == IntPtr.Zero)
            {
                return false;
            }
            bool registeredOrChild;
            try
            {
                registeredOrChild =
                    candidateHwnd == target.TargetHwnd
                    || _topLevelWindows.ResolveTopLevel(
                        candidateHwnd) == target.TargetHwnd;
            }
            catch
            {
                return false;
            }
            if (!registeredOrChild)
                return false;

            if (target.HasBoundedProcessIdentitySignal
                && !TryValidateDispatchIdentity(
                    target,
                    out _))
            {
                return false;
            }
            return TryResolveBounded(
                    target.SessionId,
                    target.TargetId,
                    out NativeInputTargetSnapshot current,
                    out _)
                && current.TargetHwnd == target.TargetHwnd
                && current.TopLevelHwnd
                    == target.TopLevelHwnd
                && NativeInputEpochComparer.ExactEquals(
                    current.Epochs,
                    target.Epochs);
        }

        private bool TryValidateLiveWindowIdentity(
            SessionSnapshot session,
            SessionSurfaceSnapshot surface,
            out long expectedOwnerWindowHandle,
            out INativeInputProcessIdentitySignal
                ownerIdentitySignal,
            out string reasonCode)
        {
            expectedOwnerWindowHandle = 0;
            ownerIdentitySignal = null;
            if (session == null
                || surface?.OwnerProcess == null)
            {
                reasonCode = "surface_owner_unverifiable";
                return false;
            }

            SessionProcessIdentity expectedOwner =
                ExpectedOwnerProcess(
                    session,
                    surface.OwnerRelation);
            if (expectedOwner != null
                && !expectedOwner.IsExact(
                    surface.OwnerProcess))
            {
                reasonCode =
                    "surface_process_relation_mismatch";
                return false;
            }
            if (!TryValidateBoundedWindowIdentity(
                    surface.WindowHandle,
                    surface.OwnerProcess.ProcessId,
                    0,
                    out reasonCode))
            {
                return false;
            }

            if (surface.OwnerRelation
                    != SessionSurfaceOwnerRelation.LauncherOwned
                && surface.OwnerRelation
                    != SessionSurfaceOwnerRelation.FlashOwned)
            {
                reasonCode = null;
                return true;
            }

            SessionSurfaceSnapshot ownerSurface =
                session.Surfaces.FirstOrDefault(candidate =>
                    string.Equals(
                        candidate.TargetId,
                        surface.OwnerTargetId,
                        StringComparison.Ordinal));
            if (ownerSurface == null
                || ownerSurface.SafetyKind
                    != AgentTargetSafetyKind.RuntimeOwned
                || ownerSurface.OwnerProcess == null
                || ownerSurface.WindowHandle
                    != surface.OwnerWindowHandle)
            {
                reasonCode =
                    "surface_window_owner_relation_mismatch";
                return false;
            }

            INativeInputProcessIdentitySignal ownerSignal = null;
            try
            {
                if (!TryCaptureProcessIdentitySignal(
                        ownerSurface.OwnerProcess,
                        out ownerSignal)
                    || !TryValidateBoundedWindowIdentity(
                        ownerSurface.WindowHandle,
                        ownerSurface.OwnerProcess.ProcessId,
                        0,
                        out _))
                {
                    reasonCode =
                        "surface_window_owner_relation_mismatch";
                    return false;
                }

                expectedOwnerWindowHandle =
                    surface.OwnerWindowHandle;
                if (!TryValidateBoundedWindowIdentity(
                        surface.WindowHandle,
                        surface.OwnerProcess.ProcessId,
                        expectedOwnerWindowHandle,
                        out reasonCode))
                {
                    return false;
                }
                ownerIdentitySignal = ownerSignal;
                ownerSignal = null;
                return true;
            }
            finally
            {
                ownerSignal?.Dispose();
            }
        }

        private bool TryValidateBoundedWindowIdentity(
            long windowHandle,
            int expectedProcessId,
            long expectedOwnerWindowHandle,
            out string reasonCode)
        {
            try
            {
                if (!_windowProbe.TryGetOwnerProcessId(
                        windowHandle,
                        out int observedProcessId)
                    || observedProcessId
                        != expectedProcessId)
                {
                    reasonCode =
                        "surface_hwnd_owner_mismatch";
                    return false;
                }
                if (expectedOwnerWindowHandle != 0
                    && _windowProbe.GetOwnerWindow(
                        windowHandle)
                        != expectedOwnerWindowHandle)
                {
                    reasonCode =
                        "surface_window_owner_relation_mismatch";
                    return false;
                }
                reasonCode = null;
                return true;
            }
            catch
            {
                reasonCode = "surface_owner_unverifiable";
                return false;
            }
        }

        private bool TryCaptureProcessIdentitySignal(
            SessionProcessIdentity expected,
            out INativeInputProcessIdentitySignal signal)
        {
            signal = null;
            try
            {
                if (!_processIdentitySignals.TryCapture(
                        expected,
                        out signal)
                    || signal == null
                    || !signal.IsAliveBounded())
                {
                    signal?.Dispose();
                    signal = null;
                    return false;
                }
                return true;
            }
            catch
            {
                signal?.Dispose();
                signal = null;
                return false;
            }
        }

        private static bool IsProcessSignalAliveBounded(
            INativeInputProcessIdentitySignal signal)
        {
            try
            {
                return signal != null
                    && signal.IsAliveBounded();
            }
            catch
            {
                return false;
            }
        }

        private static SessionProcessIdentity ExpectedOwnerProcess(
            SessionSnapshot session,
            SessionSurfaceOwnerRelation relation)
        {
            return relation switch
            {
                SessionSurfaceOwnerRelation.LauncherTopLevel =>
                    session.LauncherProcess,
                SessionSurfaceOwnerRelation.LauncherOwned =>
                    session.LauncherProcess,
                SessionSurfaceOwnerRelation.RuntimeOverlay =>
                    session.LauncherProcess,
                SessionSurfaceOwnerRelation.FlashTopLevel =>
                    session.FlashProcess,
                SessionSurfaceOwnerRelation.FlashOwned =>
                    session.FlashProcess,
                _ => null
            };
        }

        private static bool SnapshotIdentityMatches(
            NativeInputTargetSnapshot target,
            SessionSurfaceSnapshot surface)
        {
            return target != null
                && surface?.OwnerProcess != null
                && target.TargetHwnd.ToInt64()
                    == surface.WindowHandle
                && target.OwnerProcessId
                    == surface.OwnerProcess.ProcessId
                && target.Epochs.SurfaceEpoch
                    == checked((long)surface.SurfaceEpoch)
                && target.Epochs.CoordinateSpaceVersion
                    == checked(
                        (long)surface.CoordinateSpaceVersion);
        }

        private bool IsInvalidated(
            NativeInputTargetSnapshot target,
            out string reasonCode)
        {
            lock (_invalidatedSync)
            {
                string key = GenerationKey(target);
                if (!_invalidatedGenerations.TryGetValue(
                        key,
                        out InvalidatedGeneration invalidated))
                {
                    reasonCode = null;
                    return false;
                }
                if (invalidated.Matches(target))
                {
                    reasonCode = invalidated.ReasonCode;
                    return true;
                }
                _invalidatedGenerations.Remove(key);
                reasonCode = null;
                return false;
            }
        }

        private void Invalidate(
            NativeInputTargetSnapshot target,
            string reasonCode)
        {
            if (target == null)
                return;
            lock (_invalidatedSync)
            {
                _invalidatedGenerations[
                    GenerationKey(target)] =
                        new InvalidatedGeneration(
                            target,
                            string.IsNullOrWhiteSpace(reasonCode)
                                ? "surface_owner_unverifiable"
                                : reasonCode);
            }
        }

        private static string GenerationKey(
            NativeInputTargetSnapshot target)
        {
            return target.SessionId
                + "\n"
                + target.TargetId;
        }

        private sealed class InvalidatedGeneration
        {
            private readonly IntPtr _targetHwnd;
            private readonly int _ownerProcessId;
            private readonly InputEpochSnapshot _epochs;

            internal InvalidatedGeneration(
                NativeInputTargetSnapshot target,
                string reasonCode)
            {
                _targetHwnd = target.TargetHwnd;
                _ownerProcessId = target.OwnerProcessId;
                _epochs = target.Epochs;
                ReasonCode = reasonCode;
            }

            internal string ReasonCode { get; }

            internal bool Matches(
                NativeInputTargetSnapshot target)
            {
                return target.TargetHwnd == _targetHwnd
                    && target.OwnerProcessId
                        == _ownerProcessId
                    && NativeInputEpochComparer.ExactEquals(
                        target.Epochs,
                        _epochs);
            }
        }

        private sealed class CompositeProcessIdentitySignal
            : INativeInputProcessIdentitySignal
        {
            private INativeInputProcessIdentitySignal _first;
            private INativeInputProcessIdentitySignal _second;

            internal CompositeProcessIdentitySignal(
                INativeInputProcessIdentitySignal first,
                INativeInputProcessIdentitySignal second)
            {
                _first = first
                    ?? throw new ArgumentNullException(
                        nameof(first));
                _second = second
                    ?? throw new ArgumentNullException(
                        nameof(second));
            }

            public bool IsAliveBounded()
            {
                INativeInputProcessIdentitySignal first =
                    _first;
                INativeInputProcessIdentitySignal second =
                    _second;
                return first != null
                    && second != null
                    && first.IsAliveBounded()
                    && second.IsAliveBounded();
            }

            public void Dispose()
            {
                Interlocked.Exchange(ref _first, null)
                    ?.Dispose();
                Interlocked.Exchange(ref _second, null)
                    ?.Dispose();
            }
        }

        private static bool TryCreateExpectation(
            SessionSnapshot session,
            SessionSurfaceSnapshot surface,
            out SessionTargetGenerationExpectation expectation,
            out string reasonCode)
        {
            expectation = null;
            if (session.LifecycleGeneration == 0
                || surface.SurfaceEpoch == 0
                || surface.CoordinateSpaceVersion == 0)
            {
                reasonCode = "stale_observation";
                return false;
            }
            expectation = new SessionTargetGenerationExpectation
            {
                SessionId = session.SessionId,
                LifecycleGeneration = session.LifecycleGeneration,
                AttemptId = session.AttemptId,
                AttemptGeneration = session.AttemptGeneration,
                TargetId = surface.TargetId,
                SurfaceEpoch = surface.SurfaceEpoch,
                CoordinateSpaceVersion =
                    surface.CoordinateSpaceVersion,
                FocusEpoch = session.FocusEpoch,
                ModalEpoch = session.ModalEpoch,
                DocumentGeneration = surface.DocumentGeneration,
                PanelInstanceId =
                    session.PanelInstanceIdForTarget(
                        surface.TargetId)
            };
            reasonCode = null;
            return true;
        }

        private static bool TryCreateEpochs(
            SessionSnapshot session,
            SessionSurfaceSnapshot surface,
            out InputEpochSnapshot epochs)
        {
            epochs = null;
            if (session.LifecycleGeneration > long.MaxValue
                || session.AttemptGeneration.GetValueOrDefault()
                    > long.MaxValue
                || surface.SurfaceEpoch > long.MaxValue
                || surface.CoordinateSpaceVersion > long.MaxValue
                || surface.DocumentGeneration.GetValueOrDefault()
                    > long.MaxValue
                || session.FocusEpoch > long.MaxValue
                || session.ModalEpoch > long.MaxValue)
            {
                return false;
            }

            epochs = new InputEpochSnapshot(
                session.SessionId,
                checked((long)session.LifecycleGeneration),
                session.AttemptId,
                checked((long)session.AttemptGeneration
                    .GetValueOrDefault()),
                surface.TargetId,
                checked((long)surface.SurfaceEpoch),
                checked((long)surface.CoordinateSpaceVersion),
                session.PanelInstanceIdForTarget(
                    surface.TargetId),
                checked((long)surface.DocumentGeneration
                    .GetValueOrDefault()),
                checked((long)session.FocusEpoch),
                checked((long)session.ModalEpoch));
            return true;
        }

        private static bool IsSecurityModalLatched(
            SessionSnapshot session)
        {
            return session.HumanReauthorizationRequired
                || session.BlockingModalKind
                    == BlockingModalKind.HumanOnlySecurity
                || session.BlockingModalKind
                    == BlockingModalKind.Foreign
                || session.BlockingModalKind
                    == BlockingModalKind.Unknown;
        }
    }
}
