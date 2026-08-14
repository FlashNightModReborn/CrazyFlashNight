using System;
using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Single immutable authority object for an exact panel replacement.  Capability commit and
    /// abort are mutually exclusive and exactly-once even when admission and UI dispatch race.
    /// </summary>
    public sealed class PreparedPanelReplace
    {
        private readonly Action _commitCapabilitiesNoFail;
        private readonly Action _abortPrepared;
        private readonly Action _targetCommittedNoFail;
        private int _terminal;
        private int _targetCommitted;

        public string TargetPanel { get; private set; }
        public string TargetInstanceId { get; private set; }
        public string ImmutableInitDataJson { get; private set; }

        public PreparedPanelReplace(
            string targetPanel,
            string targetInstanceId,
            string immutableInitDataJson,
            Action commitCapabilitiesNoFail,
            Action abortPrepared)
            : this(
                targetPanel,
                targetInstanceId,
                immutableInitDataJson,
                commitCapabilitiesNoFail,
                abortPrepared,
                null)
        {
        }

        internal PreparedPanelReplace(
            string targetPanel,
            string targetInstanceId,
            string immutableInitDataJson,
            Action commitCapabilitiesNoFail,
            Action abortPrepared,
            Action targetCommittedNoFail)
        {
            if (string.IsNullOrEmpty(targetPanel))
                throw new ArgumentException("A target panel is required.", "targetPanel");
            if (string.IsNullOrEmpty(targetInstanceId))
                throw new ArgumentException("A target instance is required.", "targetInstanceId");
            if (immutableInitDataJson == null)
                throw new ArgumentNullException("immutableInitDataJson");
            TargetPanel = targetPanel;
            TargetInstanceId = targetInstanceId;
            ImmutableInitDataJson = immutableInitDataJson;
            _commitCapabilitiesNoFail = commitCapabilitiesNoFail ?? delegate { };
            _abortPrepared = abortPrepared ?? delegate { };
            _targetCommittedNoFail = targetCommittedNoFail ?? delegate { };
        }

        public bool CommitCapabilitiesNoFail()
        {
            if (Interlocked.CompareExchange(ref _terminal, 1, 0) != 0) return false;
            _commitCapabilitiesNoFail();
            return true;
        }

        public bool AbortPrepared()
        {
            if (Interlocked.CompareExchange(ref _terminal, 2, 0) != 0) return false;
            _abortPrepared();
            return true;
        }

        internal void NotifyTargetCommittedNoFail()
        {
            if (Volatile.Read(ref _terminal) != 1
                || Interlocked.CompareExchange(ref _targetCommitted, 1, 0) != 0)
            {
                return;
            }
            _targetCommittedNoFail();
        }
    }
}
