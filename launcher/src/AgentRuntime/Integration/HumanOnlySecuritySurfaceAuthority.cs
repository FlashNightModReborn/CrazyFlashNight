using System;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Reference-counted production ingress for system/common dialogs whose
    /// HWND is not a Runtime-owned observable surface. Clearing the external
    /// modal never clears the registry's human-reauthorization latch.
    /// </summary>
    internal sealed class HumanOnlySecuritySurfaceAuthority
        : IDisposable
    {
        private readonly object _sync = new object();
        private readonly Action<BlockingModalKind> _setBlockingModal;
        private int _depth;
        private bool _disposed;

        public HumanOnlySecuritySurfaceAuthority(
            Action<BlockingModalKind> setBlockingModal)
        {
            _setBlockingModal = setBlockingModal
                ?? throw new ArgumentNullException(
                    nameof(setBlockingModal));
        }

        public IDisposable Enter()
        {
            lock (_sync)
            {
                if (_disposed)
                {
                    throw new ObjectDisposedException(
                        nameof(
                            HumanOnlySecuritySurfaceAuthority));
                }
                if (_depth == 0)
                {
                    _setBlockingModal(
                        BlockingModalKind
                            .HumanOnlySecurity);
                }
                _depth = checked(_depth + 1);
                return new Scope(this);
            }
        }

        public void Dispose()
        {
            bool clear;
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                clear = _depth != 0;
                _depth = 0;
            }
            if (clear)
                TryClear();
        }

        private void Release()
        {
            bool clear = false;
            lock (_sync)
            {
                if (_disposed || _depth == 0)
                    return;
                _depth--;
                clear = _depth == 0;
            }
            if (clear)
                TryClear();
        }

        private void TryClear()
        {
            try
            {
                _setBlockingModal(
                    BlockingModalKind.None);
            }
            catch
            {
                // The Host may already be tearing down. The registry either
                // remains security-latched or is about to be disposed; never
                // turn a cleanup race into a false reauthorization.
            }
        }

        private sealed class Scope : IDisposable
        {
            private HumanOnlySecuritySurfaceAuthority _owner;

            public Scope(
                HumanOnlySecuritySurfaceAuthority owner)
            {
                _owner = owner;
            }

            public void Dispose()
            {
                HumanOnlySecuritySurfaceAuthority owner =
                    _owner;
                _owner = null;
                owner?.Release();
            }
        }
    }
}
