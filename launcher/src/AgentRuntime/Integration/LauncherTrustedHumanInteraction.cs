using System;
using System.Threading;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal enum LauncherTrustedHumanInteractionPhase
    {
        WindowActivationConsent = 1,
        HairPreparationConsent = 2,
        HairChooser = 3,
        HairCommitConsent = 4,
        HairRestoreConsent = 5
    }

    /// <summary>
    /// Host-local, reference-identity capability for one exact human
    /// interaction window. The coordinator creates it before presentation;
    /// the trusted presenter binds its HWND before showing/publishing it.
    /// </summary>
    internal sealed class LauncherTrustedHumanInteractionTicket
    {
        private readonly object _sync = new object();
        private Binding _binding;
        private bool _closed;
        private bool _revoked;
        private Action _revocation;

        internal LauncherTrustedHumanInteractionTicket(
            string instanceId,
            LauncherTrustedHumanInteractionPhase phase,
            long ownerWindowHandle)
        {
            WingsProtocolValue.RequireOpaqueId(
                instanceId,
                nameof(instanceId));
            if (!Enum.IsDefined(phase))
                throw new ArgumentOutOfRangeException(nameof(phase));
            if (ownerWindowHandle < 0)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(ownerWindowHandle));
            }
            InstanceId = instanceId;
            Phase = phase;
            OwnerWindowHandle = ownerWindowHandle;
        }

        internal string InstanceId { get; }
        internal LauncherTrustedHumanInteractionPhase Phase { get; }
        internal long OwnerWindowHandle { get; }

        internal bool TryBindSecuritySurface(
            WingsHumanOnlySurfaceDescriptor descriptor,
            out string reasonCode)
        {
            if (descriptor == null)
            {
                reasonCode = "human_intervention_required";
                return false;
            }
            return TryBind(
                descriptor.TargetId,
                descriptor.WindowHandle,
                descriptor.OwnerWindowHandle,
                true,
                out reasonCode);
        }

        internal bool TryBindChooserWindow(
            string chooserId,
            long windowHandle,
            long ownerWindowHandle,
            out string reasonCode)
        {
            if (Phase
                != LauncherTrustedHumanInteractionPhase.HairChooser)
            {
                reasonCode = "human_intervention_required";
                return false;
            }
            return TryBind(
                chooserId,
                windowHandle,
                ownerWindowHandle,
                false,
                out reasonCode);
        }

        internal void MarkClosed(long windowHandle)
        {
            lock (_sync)
            {
                if (_binding != null
                    && _binding.WindowHandle == windowHandle)
                {
                    _closed = true;
                    _revocation = null;
                }
            }
        }

        internal bool TryRegisterRevocation(
            Action revocation)
        {
            if (revocation == null)
                throw new ArgumentNullException(
                    nameof(revocation));
            lock (_sync)
            {
                if (_revoked
                    || _closed
                    || _binding == null
                    || _revocation != null)
                {
                    return false;
                }
                _revocation = revocation;
                return true;
            }
        }

        internal void Revoke()
        {
            Action revocation;
            lock (_sync)
            {
                if (_revoked)
                    return;
                _revoked = true;
                _closed = true;
                revocation = _revocation;
                _revocation = null;
            }
            if (revocation == null)
                return;
            ThreadPool.QueueUserWorkItem(
                _ =>
                {
                    try
                    {
                        revocation();
                    }
                    catch
                    {
                    }
                });
        }

        internal bool TryConfirmPublishedSurface(
            string targetId,
            long windowHandle,
            long ownerWindowHandle,
            ulong surfaceEpoch,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (_revoked
                    || _closed
                    || _binding == null
                    || !_binding.SecuritySurface
                    || _binding.SurfaceEpoch != 0
                    || surfaceEpoch == 0
                    || !string.Equals(
                        _binding.TargetId,
                        targetId,
                        StringComparison.Ordinal)
                    || _binding.WindowHandle != windowHandle
                    || _binding.OwnerWindowHandle
                        != ownerWindowHandle)
                {
                    reasonCode =
                        "human_intervention_required";
                    return false;
                }
                _binding.SurfaceEpoch = surfaceEpoch;
                reasonCode = null;
                return true;
            }
        }

        internal bool TryGetBinding(
            out LauncherTrustedHumanInteractionBinding binding)
        {
            lock (_sync)
            {
                if (_binding == null)
                {
                    binding = null;
                    return false;
                }
                binding =
                    new LauncherTrustedHumanInteractionBinding(
                        InstanceId,
                        Phase,
                        _binding.TargetId,
                        _binding.WindowHandle,
                        _binding.OwnerWindowHandle,
                        _binding.SecuritySurface,
                        _binding.SurfaceEpoch,
                        _closed);
                return true;
            }
        }

        private bool TryBind(
            string targetId,
            long windowHandle,
            long ownerWindowHandle,
            bool securitySurface,
            out string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(targetId)
                || windowHandle == 0
                || ownerWindowHandle < 0
                || (OwnerWindowHandle != 0
                    && ownerWindowHandle != OwnerWindowHandle))
            {
                reasonCode = "human_intervention_required";
                return false;
            }
            lock (_sync)
            {
                if (_revoked || _closed)
                {
                    reasonCode = "credential_revoked";
                    return false;
                }
                if (_binding != null)
                {
                    bool exact = string.Equals(
                            _binding.TargetId,
                            targetId,
                            StringComparison.Ordinal)
                        && _binding.WindowHandle == windowHandle
                        && _binding.OwnerWindowHandle
                            == ownerWindowHandle
                        && _binding.SecuritySurface
                            == securitySurface;
                    reasonCode = exact
                        ? null
                        : "human_intervention_required";
                    return exact;
                }
                _binding = new Binding(
                    targetId,
                    windowHandle,
                    ownerWindowHandle,
                    securitySurface);
                reasonCode = null;
                return true;
            }
        }

        private sealed class Binding
        {
            internal Binding(
                string targetId,
                long windowHandle,
                long ownerWindowHandle,
                bool securitySurface)
            {
                TargetId = targetId;
                WindowHandle = windowHandle;
                OwnerWindowHandle = ownerWindowHandle;
                SecuritySurface = securitySurface;
            }

            internal string TargetId { get; }
            internal long WindowHandle { get; }
            internal long OwnerWindowHandle { get; }
            internal bool SecuritySurface { get; }
            internal ulong SurfaceEpoch { get; set; }
        }
    }

    internal sealed class LauncherTrustedHumanInteractionBinding
    {
        internal LauncherTrustedHumanInteractionBinding(
            string instanceId,
            LauncherTrustedHumanInteractionPhase phase,
            string targetId,
            long windowHandle,
            long ownerWindowHandle,
            bool securitySurface,
            ulong surfaceEpoch,
            bool closed)
        {
            InstanceId = instanceId;
            Phase = phase;
            TargetId = targetId;
            WindowHandle = windowHandle;
            OwnerWindowHandle = ownerWindowHandle;
            SecuritySurface = securitySurface;
            SurfaceEpoch = surfaceEpoch;
            Closed = closed;
        }

        internal string InstanceId { get; }
        internal LauncherTrustedHumanInteractionPhase Phase { get; }
        internal string TargetId { get; }
        internal long WindowHandle { get; }
        internal long OwnerWindowHandle { get; }
        internal bool SecuritySurface { get; }
        internal ulong SurfaceEpoch { get; }
        internal bool Closed { get; }
    }

    /// <summary>
    /// Carries a Host-issued ticket only through the in-process Hair consent
    /// dispatch call. It is never serialized or accepted from wire input.
    /// </summary>
    internal static class LauncherTrustedHumanInteractionContext
    {
        private static readonly AsyncLocal<
            LauncherTrustedHumanInteractionTicket> CurrentTicket =
                new AsyncLocal<
                    LauncherTrustedHumanInteractionTicket>();

        internal static LauncherTrustedHumanInteractionTicket Current =>
            CurrentTicket.Value;

        internal static IDisposable Enter(
            LauncherTrustedHumanInteractionTicket ticket)
        {
            if (ticket == null)
                throw new ArgumentNullException(nameof(ticket));
            LauncherTrustedHumanInteractionTicket prior =
                CurrentTicket.Value;
            CurrentTicket.Value = ticket;
            return new Scope(prior);
        }

        private sealed class Scope : IDisposable
        {
            private LauncherTrustedHumanInteractionTicket _prior;

            internal Scope(
                LauncherTrustedHumanInteractionTicket prior)
            {
                _prior = prior;
            }

            public void Dispose()
            {
                LauncherTrustedHumanInteractionTicket prior =
                    Interlocked.Exchange(ref _prior, null);
                CurrentTicket.Value = prior;
            }
        }
    }
}
