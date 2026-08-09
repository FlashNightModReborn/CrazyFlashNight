using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Coalesces immutable lifecycle semantics before they enter the projection
    /// queue. Meter and aggregate-counter refreshes deliberately do not participate.
    /// </summary>
    internal sealed class AudioLifecycleProjectionGateV2
    {
        private readonly object _sync = new object();
        private readonly List<Reservation> _reservations =
            new List<Reservation>();
        private int _publishedConnectionGeneration;
        private AudioCoordinatorSnapshotV2 _publishedSnapshot;

        internal bool TryReserve(
            int connectionGeneration,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            if (snapshot == null) return false;
            lock (_sync)
            {
                if (_publishedSnapshot != null &&
                    _publishedConnectionGeneration == connectionGeneration &&
                    AudioSocketPublisherV2.SameLifecycleTuple(
                        _publishedSnapshot,
                        snapshot))
                {
                    return false;
                }
                for (int index = 0; index < _reservations.Count; index++)
                {
                    Reservation reservation = _reservations[index];
                    if (reservation.ConnectionGeneration ==
                            connectionGeneration &&
                        AudioSocketPublisherV2.SameLifecycleTuple(
                            reservation.Snapshot,
                            snapshot))
                    {
                        return false;
                    }
                }

                _reservations.Add(new Reservation(
                    connectionGeneration,
                    snapshot));
                return true;
            }
        }

        internal bool Commit(
            int connectionGeneration,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            lock (_sync)
            {
                int index = FindReservation(connectionGeneration, snapshot);
                if (index < 0) return false;
                _reservations.RemoveAt(index);
                _publishedConnectionGeneration = connectionGeneration;
                _publishedSnapshot = snapshot;
                return true;
            }
        }

        internal bool Release(
            int connectionGeneration,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            lock (_sync)
            {
                int index = FindReservation(connectionGeneration, snapshot);
                if (index < 0) return false;
                _reservations.RemoveAt(index);
                return true;
            }
        }

        private int FindReservation(
            int connectionGeneration,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            for (int index = 0; index < _reservations.Count; index++)
            {
                Reservation reservation = _reservations[index];
                if (reservation.ConnectionGeneration == connectionGeneration &&
                    AudioSocketPublisherV2.SameLifecycleTuple(
                        reservation.Snapshot,
                        snapshot))
                {
                    return index;
                }
            }
            return -1;
        }

        private sealed class Reservation
        {
            internal Reservation(
                int connectionGeneration,
                AudioCoordinatorSnapshotV2 snapshot)
            {
                ConnectionGeneration = connectionGeneration;
                Snapshot = snapshot;
            }

            internal int ConnectionGeneration { get; private set; }
            internal AudioCoordinatorSnapshotV2 Snapshot { get; private set; }
        }
    }

    /// <summary>
    /// Serializes lifecycle/catalog projection independently from the native owner.
    /// Every write is fenced by the XMLSocket connection generation; a ready envelope
    /// is written only after the same connection received a full catalog.
    /// </summary>
    internal sealed class AudioSocketPublisherV2 : IDisposable
    {
        private readonly XmlSocketServer _socket;
        private readonly MusicCatalog _catalog;
        private readonly BlockingCollection<ProjectionWork> _queue;
        private readonly AudioLifecycleProjectionGateV2 _lifecycleGate;
        private readonly Thread _thread;
        private int _disposed;

        internal AudioSocketPublisherV2(
            XmlSocketServer socket,
            MusicCatalog catalog)
        {
            _socket = socket ?? throw new ArgumentNullException("socket");
            _catalog = catalog ?? throw new ArgumentNullException("catalog");
            _lifecycleGate = new AudioLifecycleProjectionGateV2();
            _queue = new BlockingCollection<ProjectionWork>(
                new ConcurrentQueue<ProjectionWork>());
            _thread = new Thread(WorkerLoop);
            _thread.IsBackground = true;
            _thread.Name = "CF7 Audio v2 socket projection";

            _socket.OnClientReadyForGeneration += OnClientReady;
            _catalog.CatalogChanged += OnCatalogChanged;
            _catalog.QualificationChangedV2 += OnQualificationChanged;
            AudioEngine.SnapshotChanged += OnSnapshotChanged;
            _thread.Start();

            // The socket can become ready before Program finishes composing the
            // audio projector. Replay that already-current transport generation;
            // otherwise the first connection would never receive catalog/lifecycle.
            int currentConnectionGeneration;
            if (_socket.TryGetReadyGeneration(out currentConnectionGeneration))
                OnClientReady(currentConnectionGeneration);
        }

        private void OnClientReady(int connectionGeneration)
        {
            TryEnqueueLifecycle(
                connectionGeneration,
                AudioEngine.SnapshotV2);
        }

        private void OnSnapshotChanged(AudioCoordinatorSnapshotV2 snapshot)
        {
            int connectionGeneration;
            if (!_socket.TryGetReadyGeneration(out connectionGeneration))
                return;
            TryEnqueueLifecycle(connectionGeneration, snapshot);
        }

        private void OnCatalogChanged(string updateJson)
        {
            int connectionGeneration;
            if (string.IsNullOrEmpty(updateJson) ||
                !_socket.TryGetReadyGeneration(out connectionGeneration))
                return;
            Enqueue(ProjectionWork.CatalogUpdate(
                connectionGeneration,
                updateJson));
        }

        private void OnQualificationChanged(
            MusicCatalogQualificationSnapshotV2 qualification)
        {
            if (qualification == null) return;
            AudioCoordinatorSnapshotV2 snapshot = AudioEngine.SnapshotV2;
            if (!snapshot.IsReady ||
                !qualification.IsCompleteForCapability(
                    snapshot.CapabilityDigest))
            {
                return;
            }

            int connectionGeneration;
            if (!_socket.TryGetReadyGeneration(out connectionGeneration))
                return;
            TryEnqueueLifecycle(connectionGeneration, snapshot);
        }

        private void TryEnqueueLifecycle(
            int connectionGeneration,
            AudioCoordinatorSnapshotV2 snapshot)
        {
            if (snapshot == null) return;

            // Do not consume a ready semantic key before its exact catalog is
            // qualified. QualificationChangedV2 will retry the same key later.
            if (snapshot.IsReady && !IsQualifiedProjectionForReady(
                snapshot,
                _catalog.GetProjectionV2()))
            {
                return;
            }

            if (_lifecycleGate.TryReserve(connectionGeneration, snapshot) &&
                !Enqueue(ProjectionWork.Lifecycle(
                    connectionGeneration,
                    snapshot)))
            {
                _lifecycleGate.Release(connectionGeneration, snapshot);
            }
        }

        private bool Enqueue(ProjectionWork work)
        {
            if (work == null || Volatile.Read(ref _disposed) != 0) return false;
            try
            {
                _queue.Add(work);
                return true;
            }
            catch (InvalidOperationException)
            {
                return false;
            }
        }

        private void WorkerLoop()
        {
            foreach (ProjectionWork work in _queue.GetConsumingEnumerable())
            {
                try
                {
                    if (work.UpdateJson != null)
                    {
                        if (AudioEngine.SnapshotV2.IsReady)
                        {
                            _socket.TrySendIfGen(
                                work.UpdateJson + "\0",
                                work.ConnectionGeneration);
                        }
                        continue;
                    }
                    ProcessLifecycleWork(work);
                }
                catch (Exception ex)
                {
                    LogManager.Log(
                        "[AudioV2] socket projection failed: " +
                        ex.GetType().Name);
                }
            }
        }

        private void ProcessLifecycleWork(ProjectionWork work)
        {
            AudioCoordinatorSnapshotV2 snapshot = work.Snapshot;
            if (snapshot == null) return;
            bool committed = false;
            bool retryCurrent = false;
            try
            {
                AudioCoordinatorSnapshotV2 current =
                    AudioEngine.SnapshotV2;
                if (!SameLifecycleTuple(snapshot, current))
                {
                    retryCurrent = true;
                    return;
                }
                if (snapshot.IsReady)
                {
                    MusicCatalogProjectionV2 projection =
                        _catalog.GetProjectionV2();
                    if (!IsQualifiedProjectionForReady(
                            snapshot,
                            projection))
                    {
                        retryCurrent = true;
                        return;
                    }

                    if (!_socket.TrySendIfGen(
                            projection.CatalogJson + "\0",
                            work.ConnectionGeneration))
                        return;

                    // A rebuild may have started while the catalog was serialized.
                    // A hot refresh may also have advanced the catalog revision.
                    // Never publish ready for either stale projection.
                    current = AudioEngine.SnapshotV2;
                    if (!SameLifecycleTuple(snapshot, current))
                    {
                        retryCurrent = true;
                        return;
                    }
                    MusicCatalogProjectionV2 latestProjection =
                        _catalog.GetProjectionV2();
                    if (!IsQualifiedProjectionForReady(
                            snapshot,
                            latestProjection) ||
                        latestProjection.Qualification.Revision !=
                            projection.Qualification.Revision)
                    {
                        retryCurrent = true;
                        return;
                    }
                }

                string lifecycleJson;
                string error;
                if (!AudioLifecycleWireV2.TrySerialize(
                        snapshot,
                        out lifecycleJson,
                        out error))
                {
                    LogManager.Log(
                        "[AudioV2] lifecycle projection rejected: " +
                        error);
                    return;
                }
                if (!_socket.TrySendIfGen(
                        lifecycleJson + "\0",
                        work.ConnectionGeneration))
                {
                    return;
                }
                committed = _lifecycleGate.Commit(
                    work.ConnectionGeneration,
                    snapshot);
            }
            finally
            {
                if (!committed)
                {
                    _lifecycleGate.Release(
                        work.ConnectionGeneration,
                        snapshot);
                }
                if (retryCurrent)
                {
                    RetryCurrentLifecycle(work.ConnectionGeneration);
                }
            }
        }

        private void RetryCurrentLifecycle(int expectedConnectionGeneration)
        {
            int currentConnectionGeneration;
            if (!_socket.TryGetReadyGeneration(
                    out currentConnectionGeneration) ||
                currentConnectionGeneration != expectedConnectionGeneration)
            {
                return;
            }
            TryEnqueueLifecycle(
                currentConnectionGeneration,
                AudioEngine.SnapshotV2);
        }

        internal static bool IsQualifiedProjectionForReady(
            AudioCoordinatorSnapshotV2 snapshot,
            MusicCatalogProjectionV2 projection)
        {
            return snapshot != null && snapshot.IsReady &&
                projection != null &&
                !string.IsNullOrEmpty(projection.CatalogJson) &&
                projection.Qualification != null &&
                projection.Qualification.IsCompleteForCapability(
                    snapshot.CapabilityDigest);
        }

        internal static bool SameLifecycleTuple(
            AudioCoordinatorSnapshotV2 left,
            AudioCoordinatorSnapshotV2 right)
        {
            if (left == null || right == null ||
                left.Status != right.Status ||
                !string.Equals(
                    left.AudioSessionId,
                    right.AudioSessionId,
                    StringComparison.Ordinal) ||
                left.AudioReadyGeneration != right.AudioReadyGeneration ||
                left.DeviceGeneration != right.DeviceGeneration ||
                !string.Equals(
                    left.CapabilityDigest,
                    right.CapabilityDigest,
                    StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            if (left.IsReady)
            {
                return left.Loaded == right.Loaded &&
                    left.Failed == right.Failed &&
                    left.Overrides == right.Overrides;
            }
            return left.FailureCategory == right.FailureCategory &&
                string.Equals(
                    left.MessageKey,
                    right.MessageKey,
                    StringComparison.Ordinal);
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            _socket.OnClientReadyForGeneration -= OnClientReady;
            _catalog.CatalogChanged -= OnCatalogChanged;
            _catalog.QualificationChangedV2 -= OnQualificationChanged;
            AudioEngine.SnapshotChanged -= OnSnapshotChanged;
            _queue.CompleteAdding();
            if (!ReferenceEquals(Thread.CurrentThread, _thread))
                _thread.Join(TimeSpan.FromSeconds(5));
            _queue.Dispose();
        }

        private sealed class ProjectionWork
        {
            private ProjectionWork(
                int connectionGeneration,
                AudioCoordinatorSnapshotV2 snapshot,
                string updateJson)
            {
                ConnectionGeneration = connectionGeneration;
                Snapshot = snapshot;
                UpdateJson = updateJson;
            }

            internal int ConnectionGeneration { get; private set; }
            internal AudioCoordinatorSnapshotV2 Snapshot { get; private set; }
            internal string UpdateJson { get; private set; }

            internal static ProjectionWork Lifecycle(
                int connectionGeneration,
                AudioCoordinatorSnapshotV2 snapshot)
            {
                return new ProjectionWork(
                    connectionGeneration,
                    snapshot,
                    null);
            }

            internal static ProjectionWork CatalogUpdate(
                int connectionGeneration,
                string updateJson)
            {
                return new ProjectionWork(
                    connectionGeneration,
                    null,
                    updateJson);
            }
        }
    }
}
