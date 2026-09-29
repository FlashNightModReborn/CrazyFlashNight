using System;
using System.Threading;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // The two bullet channels share one connection generation. A failed send on
    // either channel must not prevent attempting the other channel's revocation.
    internal sealed class BulletCapabilityPublisher
    {
        private readonly string _bulletOn, _bulletOff, _chainOn, _chainOff;
        private readonly Func<string, int, bool> _send;
        private readonly object _generationSync = new();
        private int _generation;
        private int _latestGeneration;

        internal BulletCapabilityPublisher(string bulletOn, string bulletOff,
            string chainOn, string chainOff, Func<string, int, bool> send)
        {
            _bulletOn = bulletOn; _bulletOff = bulletOff; _chainOn = chainOn; _chainOff = chainOff;
            _send = send ?? throw new ArgumentNullException(nameof(send));
        }

        internal bool Ready(int generation)
        {
            if (generation < 1) return false;
            lock (_generationSync)
            {
                if (generation < _latestGeneration) return false;
                if (generation == _latestGeneration) return Volatile.Read(ref _generation) == generation;
                _latestGeneration = generation;
                Volatile.Write(ref _generation, generation);
            }
            // Do not re-read a newer generation after leaving the lock: a late
            // ready callback must never send its initial off pair to a new peer.
            return PublishForGeneration(false, generation);
        }

        internal bool Disconnected(int generation) => generation > 0
            && Interlocked.CompareExchange(ref _generation, 0, generation) == generation;

        internal bool Publish(bool available)
        {
            return PublishForGeneration(available, Volatile.Read(ref _generation));
        }

        private bool PublishForGeneration(bool available, int generation)
        {
            if (generation < 1) return false;
            bool bulletSent = _send(available ? _bulletOn : _bulletOff, generation);
            bool chainSent = _send(available ? _chainOn : _chainOff, generation);
            return bulletSent && chainSent;
        }
    }
}
