using System.Collections.Generic;
using CF7Launcher.Audio;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioSocketPublisherV2Tests
    {
        [Fact]
        public void ReadyProjection_RequiresCompleteMatchingCapability()
        {
            AudioCoordinatorSnapshotV2 ready = Snapshot(
                AudioCoordinatorStatusV2.Ready,
                capabilityDigest: new string('A', 64));
            var accepted = new MusicCatalogProjectionV2(
                "{\"task\":\"catalog\"}",
                new MusicCatalogQualificationSnapshotV2(
                    7,
                    true,
                    new string('A', 64),
                    1,
                    0,
                    0));
            var pending = new MusicCatalogProjectionV2(
                "{\"task\":\"catalog\"}",
                new MusicCatalogQualificationSnapshotV2(
                    8,
                    false,
                    new string('A', 64),
                    0,
                    1,
                    0));
            var wrongCapability = new MusicCatalogProjectionV2(
                "{\"task\":\"catalog\"}",
                new MusicCatalogQualificationSnapshotV2(
                    9,
                    true,
                    new string('B', 64),
                    1,
                    0,
                    0));

            Assert.True(
                AudioSocketPublisherV2.IsQualifiedProjectionForReady(
                    ready,
                    accepted));
            Assert.False(
                AudioSocketPublisherV2.IsQualifiedProjectionForReady(
                    ready,
                    pending));
            Assert.False(
                AudioSocketPublisherV2.IsQualifiedProjectionForReady(
                    ready,
                    wrongCapability));
            Assert.False(
                AudioSocketPublisherV2.IsQualifiedProjectionForReady(
                    Snapshot(AudioCoordinatorStatusV2.Recovering),
                    accepted));
        }

        [Fact]
        public void ReadyFence_BindsSerializedFieldsButIgnoresMeterRefresh()
        {
            AudioCoordinatorSnapshotV2 first = Snapshot(
                AudioCoordinatorStatusV2.Ready,
                peakLeft: 0.1f,
                played: 1UL);
            AudioCoordinatorSnapshotV2 observationRefresh = Snapshot(
                AudioCoordinatorStatusV2.Ready,
                peakLeft: 0.9f,
                played: 2UL);
            AudioCoordinatorSnapshotV2 changedCatalog = Snapshot(
                AudioCoordinatorStatusV2.Ready,
                loaded: 2);

            Assert.True(
                AudioSocketPublisherV2.SameLifecycleTuple(
                    first,
                    observationRefresh));
            Assert.False(
                AudioSocketPublisherV2.SameLifecycleTuple(
                    first,
                    changedCatalog));
        }

        [Fact]
        public void UnavailableFence_RejectsOldStatusOrReason()
        {
            AudioCoordinatorSnapshotV2 recovering = Snapshot(
                AudioCoordinatorStatusV2.Recovering,
                failureCategory: AudioNativeV2.ResultNotReady,
                messageKey: "audio.recovering");
            AudioCoordinatorSnapshotV2 differentReason = Snapshot(
                AudioCoordinatorStatusV2.Recovering,
                failureCategory: AudioNativeV2.ResultNotReady,
                messageKey: "audio.catalog_qualifying");
            AudioCoordinatorSnapshotV2 ready = Snapshot(
                AudioCoordinatorStatusV2.Ready);

            Assert.False(
                AudioSocketPublisherV2.SameLifecycleTuple(
                    recovering,
                    differentReason));
            Assert.False(
                AudioSocketPublisherV2.SameLifecycleTuple(recovering, ready));
        }

        [Fact]
        public void LifecycleGate_CoalescesCounterStormAndEmitsNewEpochOnce()
        {
            var gate = new AudioLifecycleProjectionGateV2();
            var writes = new List<string>();
            const int connectionGeneration = 17;

            ProjectForTest(
                gate,
                connectionGeneration,
                Snapshot(AudioCoordinatorStatusV2.Ready),
                writes);
            Assert.Equal(new[] { "catalog", "audio_ready" }, writes);
            writes.Clear();

            for (int index = 0; index < 1000; index++)
            {
                ProjectForTest(
                    gate,
                    connectionGeneration,
                    Snapshot(
                        AudioCoordinatorStatusV2.Ready,
                        peakLeft: index / 1000f,
                        played: (ulong)(index + 1)),
                    writes);
            }
            Assert.Empty(writes);

            AudioCoordinatorSnapshotV2 nextEpoch = Snapshot(
                AudioCoordinatorStatusV2.Ready,
                audioReadyGeneration: 4UL,
                deviceGeneration: 5UL);
            ProjectForTest(
                gate,
                connectionGeneration,
                nextEpoch,
                writes);
            ProjectForTest(
                gate,
                connectionGeneration,
                Snapshot(
                    AudioCoordinatorStatusV2.Ready,
                    audioReadyGeneration: 4UL,
                    deviceGeneration: 5UL,
                    peakLeft: 0.8f,
                    played: 1001UL),
                writes);

            Assert.Equal(new[] { "catalog", "audio_ready" }, writes);
        }

        [Fact]
        public void LifecycleGate_FailedReservationCanRetryWithoutFlooding()
        {
            var gate = new AudioLifecycleProjectionGateV2();
            AudioCoordinatorSnapshotV2 ready = Snapshot(
                AudioCoordinatorStatusV2.Ready);
            const int connectionGeneration = 23;

            Assert.True(gate.TryReserve(connectionGeneration, ready));
            for (int index = 0; index < 1000; index++)
            {
                Assert.False(gate.TryReserve(
                    connectionGeneration,
                    Snapshot(
                        AudioCoordinatorStatusV2.Ready,
                        peakLeft: index / 1000f,
                        played: (ulong)(index + 1))));
            }

            Assert.True(gate.Release(connectionGeneration, ready));
            Assert.True(gate.TryReserve(connectionGeneration, ready));
            Assert.True(gate.Commit(connectionGeneration, ready));
            Assert.False(gate.TryReserve(connectionGeneration, ready));
        }

        [Fact]
        public void LifecycleGate_ReleasingStaleEpochDoesNotClearCurrentReservation()
        {
            var gate = new AudioLifecycleProjectionGateV2();
            AudioCoordinatorSnapshotV2 stale = Snapshot(
                AudioCoordinatorStatusV2.Recovering,
                audioReadyGeneration: 3UL,
                deviceGeneration: 4UL);
            AudioCoordinatorSnapshotV2 current = Snapshot(
                AudioCoordinatorStatusV2.Ready,
                audioReadyGeneration: 4UL,
                deviceGeneration: 5UL);

            Assert.True(gate.TryReserve(29, stale));
            Assert.True(gate.TryReserve(29, current));
            Assert.True(gate.Release(29, stale));
            Assert.False(gate.TryReserve(29, current));
            Assert.True(gate.Commit(29, current));
            Assert.False(gate.TryReserve(29, current));
        }

        private static void ProjectForTest(
            AudioLifecycleProjectionGateV2 gate,
            int connectionGeneration,
            AudioCoordinatorSnapshotV2 snapshot,
            IList<string> writes)
        {
            if (!gate.TryReserve(connectionGeneration, snapshot)) return;
            if (snapshot.IsReady) writes.Add("catalog");
            writes.Add(snapshot.IsReady ? "audio_ready" : "audio_unavailable");
            Assert.True(gate.Commit(connectionGeneration, snapshot));
        }

        private static AudioCoordinatorSnapshotV2 Snapshot(
            AudioCoordinatorStatusV2 status,
            string capabilityDigest = null,
            int loaded = 1,
            uint failureCategory = AudioNativeV2.ResultOk,
            string messageKey = "audio.ready",
            float peakLeft = 0f,
            ulong played = 0UL,
            ulong audioReadyGeneration = 3UL,
            ulong deviceGeneration = 4UL)
        {
            return new AudioCoordinatorSnapshotV2(
                status,
                "00000000-0000-4000-8000-000000000001",
                audioReadyGeneration,
                deviceGeneration,
                "C:/fixture",
                capabilityDigest ?? new string('A', 64),
                loaded,
                0,
                0,
                failureCategory,
                messageKey,
                peakLeft,
                0f,
                0f,
                0f,
                false,
                "none",
                0UL,
                0UL,
                0UL,
                0UL,
                0UL,
                0UL,
                played,
                new Dictionary<string, int>());
        }
    }
}
