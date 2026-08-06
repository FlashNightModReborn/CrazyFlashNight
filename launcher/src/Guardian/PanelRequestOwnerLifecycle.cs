using System;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Tracks the exact Host document that owns a family of panel requests.  A new
    /// panel instance is a new document even when the panel name is unchanged.
    /// </summary>
    internal sealed class PanelRequestOwnerLifecycle
    {
        private readonly Func<string, bool> _isTrackedOwner;
        private string _panelName;
        private string _panelInstanceId;
        private bool _admissionOpen;

        internal PanelRequestOwnerLifecycle(Func<string, bool> isTrackedOwner)
        {
            _isTrackedOwner = isTrackedOwner
                ?? throw new ArgumentNullException(nameof(isTrackedOwner));
        }

        internal bool Advance(
            string nextPanelName,
            string nextPanelInstanceId,
            out string retiredPanelName,
            out string retiredPanelInstanceId)
        {
            retiredPanelName = null;
            retiredPanelInstanceId = null;

            bool sameOwner = string.Equals(
                    _panelName,
                    nextPanelName,
                    StringComparison.Ordinal)
                && string.Equals(
                    _panelInstanceId,
                    nextPanelInstanceId,
                    StringComparison.Ordinal);
            if (sameOwner) return false;

            if (!string.IsNullOrEmpty(_panelName)
                && !string.IsNullOrEmpty(_panelInstanceId))
            {
                retiredPanelName = _panelName;
                retiredPanelInstanceId = _panelInstanceId;
            }

            if (_isTrackedOwner(nextPanelName)
                && !string.IsNullOrEmpty(nextPanelInstanceId))
            {
                _panelName = nextPanelName;
                _panelInstanceId = nextPanelInstanceId;
                _admissionOpen = true;
            }
            else
            {
                _panelName = null;
                _panelInstanceId = null;
                _admissionOpen = false;
            }
            return retiredPanelName != null;
        }

        internal bool IsAdmittedExact(
            string panelName,
            string panelInstanceId)
        {
            return _admissionOpen
                && string.Equals(
                    _panelName,
                    panelName,
                    StringComparison.Ordinal)
                && string.Equals(
                    _panelInstanceId,
                    panelInstanceId,
                    StringComparison.Ordinal);
        }

        /// <summary>
        /// Seals an accepted exact owner before its asynchronous Host close is
        /// linearized.  Re-observing the same Host tuple must not reopen it; only
        /// an authoritative transition to a different tuple creates a new owner.
        /// </summary>
        internal bool SealExact(
            string panelName,
            string panelInstanceId)
        {
            if (!IsAdmittedExact(panelName, panelInstanceId)) return false;
            _admissionOpen = false;
            return true;
        }
    }
}
