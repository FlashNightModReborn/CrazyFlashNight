using System;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed class WorldShakeGrantSequence
    {
        internal const int Maximum = 1_000_000_000;
        private readonly object _lock = new();
        private int _last;

        internal WorldShakeGrantSequence(int last = 0) => _last = last;

        internal int Allocate()
        {
            lock (_lock)
                return _last < Maximum ? ++_last : 0;
        }
    }

    // The controller serializes this gate with caps writes, native submissions,
    // and native session retirement. Admission is evaluated on a ready tick.
    internal sealed class WorldShakeGrantGate
    {
        internal delegate void SubmitImpulses(int grant, ReadOnlySpan<CombatFxShakeImpulse> impulses,
            float x, float y, float scale);

        private const double RetryIntervalMs = 500;
        private readonly WorldShakeGrantSequence _sequence;
        private readonly Action<int> _setNativeGrant;
        private readonly Func<int, bool> _publishCaps;
        private readonly SubmitImpulses _submit;
        private readonly Func<double> _now;
        private bool _featureEnabled, _ownerFocused;
        private bool _nativeReady, _sharedDamageReady, _sourceRunning = true, _modalClear = true;
        private bool _sceneReady, _connectionReady, _exhausted;
        private bool _retryRevocation;
        private int _pendingGrant;
        private double _nextPublishMs;

        internal int ActiveGrant { get; private set; }
        internal ulong StaleGrantDropped { get; private set; }
        internal bool CapsRetryDue => _pendingGrant == 0 || _now() >= _nextPublishMs;

        internal WorldShakeGrantGate(WorldShakeGrantSequence sequence, Action<int> setNativeGrant,
            Func<int, bool> publishCaps, SubmitImpulses submit, Func<double> now,
            bool ownerFocused, bool featureEnabled = true)
        {
            _sequence = sequence;
            _setNativeGrant = setNativeGrant;
            _publishCaps = publishCaps;
            _submit = submit;
            _now = now;
            _ownerFocused = ownerFocused;
            _featureEnabled = featureEnabled;
        }

        internal void SetFeatureEnabled(bool enabled) => SetAdmissionCondition(ref _featureEnabled, enabled);
        internal void SetNativeReady(bool ready) => SetAdmissionCondition(ref _nativeReady, ready);
        internal void SetSharedDamageReady(bool ready) => SetAdmissionCondition(ref _sharedDamageReady, ready);
        internal void SetOwnerFocused(bool focused) => SetAdmissionCondition(ref _ownerFocused, focused);
        internal void SetSourcePaused(bool paused) => SetAdmissionCondition(ref _sourceRunning, !paused);
        internal void SetModalBlocked(bool blocked) => SetAdmissionCondition(ref _modalClear, !blocked);
        internal void SetSceneReady(bool ready) => SetAdmissionCondition(ref _sceneReady, ready);

        internal void ResetCapture()
        {
            if (!_nativeReady && !_sceneReady) return;
            _nativeReady = _sceneReady = false;
            Revoke();
        }

        internal void SetConnectionReady(bool ready)
        {
            if (_connectionReady == ready) return;
            _connectionReady = ready;
            _sourceRunning = true;
            _sceneReady = false;
            if (!ready) Revoke();
        }

        private void SetAdmissionCondition(ref bool condition, bool allowed)
        {
            if (condition == allowed) return;
            condition = allowed;
            if (!allowed) Revoke();
        }

        private void Revoke()
        {
            ActiveGrant = 0;
            _pendingGrant = 0;
            _setNativeGrant(0);
            _retryRevocation = _connectionReady && !Publish(0);
        }

        private bool Publish(int grant)
        {
            _nextPublishMs = _now() + RetryIntervalMs;
            return _publishCaps(grant);
        }

        internal void RetryRevocation()
        {
            if (_retryRevocation && _now() >= _nextPublishMs)
                _retryRevocation = !Publish(0);
        }

        internal void AdmitIfReady()
        {
            if (!_featureEnabled || !_nativeReady || !_sharedDamageReady || !_ownerFocused
                || !_sourceRunning || !_modalClear || !_sceneReady || !_connectionReady
                || ActiveGrant != 0 || _exhausted) return;

            if (_pendingGrant == 0)
            {
                int grant = _sequence.Allocate();
                if (grant == 0)
                {
                    _exhausted = true;
                    return;
                }
                _setNativeGrant(grant);
                _pendingGrant = grant;
            }
            else if (!CapsRetryDue) return;

            PublishPendingGrant();
        }

        // Changes to the other capability fields share the same message.
        // Keep a pending grant on the wire even if the earlier write was ambiguous.
        internal bool PublishCurrentCaps()
        {
            if (_pendingGrant != 0) return CapsRetryDue && PublishPendingGrant();
            bool sent = _publishCaps(ActiveGrant);
            if (sent) _retryRevocation = false;
            return sent;
        }

        private bool PublishPendingGrant()
        {
            _retryRevocation = false;
            if (!Publish(_pendingGrant)) return false;
            ActiveGrant = _pendingGrant;
            _pendingGrant = 0;
            return true;
        }

        internal void Observe(ReadOnlySpan<CombatFxShakeImpulse> impulses, float x, float y, float scale)
        {
            Span<CombatFxShakeImpulse> accepted = stackalloc CombatFxShakeImpulse[CombatFxShakeImpulse.MaxPerFrame];
            int count = 0;
            foreach (var impulse in impulses)
            {
                if (ActiveGrant > 0 && impulse.Grant == ActiveGrant)
                    accepted[count++] = impulse;
                else
                    StaleGrantDropped++;
            }
            if (count > 0) _submit(ActiveGrant, accepted[..count], x, y, scale);
        }
    }
}
