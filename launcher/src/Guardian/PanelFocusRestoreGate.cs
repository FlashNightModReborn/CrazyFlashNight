using System;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Web panel focus requests can outlive the message-loop turn that scheduled them.  This
    /// state-only gate keeps those callbacks bound to the panel generation that created them and
    /// suppresses the activation echo caused by SetForegroundWindow.  It deliberately contains
    /// no HWND/WebView2 code so the race policy can be covered by ordinary unit tests.
    /// </summary>
    internal sealed class PanelFocusRestoreGate
    {
        internal const long DebounceMilliseconds = 200;

        private readonly object _sync = new object();
        private int _generation;
        private int _queuedGeneration;
        private int _lastAttemptGeneration;
        private long _lastAttemptTick = long.MinValue;

        internal int BeginPanel()
        {
            lock (_sync)
            {
                _generation = _generation == int.MaxValue ? 1 : _generation + 1;
                _queuedGeneration = 0;
                return _generation;
            }
        }

        internal void EndPanel()
        {
            lock (_sync)
            {
                _queuedGeneration = 0;
            }
        }

        internal bool TryQueue(bool takeForeground, bool panelMode, bool disposed,
            long nowTick, out int generation)
        {
            lock (_sync)
            {
                generation = _generation;
                if (!takeForeground || !panelMode || disposed || generation <= 0)
                    return false;
                if (_queuedGeneration == generation
                    || IsDebouncedLocked(generation, nowTick))
                    return false;
                _queuedGeneration = generation;
                return true;
            }
        }

        internal bool TryBeginExecution(int scheduledGeneration, bool takeForeground,
            bool panelMode, bool disposed, bool foregroundEligible, long nowTick)
        {
            lock (_sync)
            {
                if (!takeForeground || !panelMode || disposed || !foregroundEligible
                    || scheduledGeneration <= 0 || scheduledGeneration != _generation
                    || scheduledGeneration != _queuedGeneration
                    || IsDebouncedLocked(scheduledGeneration, nowTick))
                    return false;
                return true;
            }
        }

        internal bool TryCommitExecution(int scheduledGeneration, bool takeForeground,
            bool panelMode, bool disposed, long nowTick)
        {
            lock (_sync)
            {
                if (!takeForeground || !panelMode || disposed)
                    return false;
                if (scheduledGeneration <= 0
                    || scheduledGeneration != _generation
                    || scheduledGeneration != _queuedGeneration
                    || IsDebouncedLocked(scheduledGeneration, nowTick))
                    return false;

                _lastAttemptGeneration = scheduledGeneration;
                _lastAttemptTick = nowTick;
                return true;
            }
        }

        internal bool IsCurrentExecution(int scheduledGeneration, bool takeForeground,
            bool panelMode, bool disposed)
        {
            lock (_sync)
            {
                return takeForeground && panelMode && !disposed
                    && scheduledGeneration > 0
                    && scheduledGeneration == _generation
                    && scheduledGeneration == _queuedGeneration;
            }
        }

        internal void Complete(int scheduledGeneration)
        {
            lock (_sync)
            {
                if (_queuedGeneration == scheduledGeneration)
                    _queuedGeneration = 0;
            }
        }

        private bool IsDebouncedLocked(int generation, long nowTick)
        {
            if (_lastAttemptGeneration != generation || _lastAttemptTick == long.MinValue)
                return false;
            long elapsed = nowTick - _lastAttemptTick;
            return elapsed >= 0 && elapsed < DebounceMilliseconds;
        }
    }
}
