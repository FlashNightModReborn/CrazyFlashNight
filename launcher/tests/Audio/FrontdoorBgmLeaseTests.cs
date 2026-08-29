using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Audio;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class FrontdoorBgmLeaseTests
    {
        [Fact]
        public void DelayedReadyStartsOnceWithFrozenTrackContract()
        {
            string root = CreateProjectRootWithTrack();
            try
            {
                var port = new FakePort(Snapshot(
                    AudioCoordinatorStatusV2.Initializing,
                    null));
                using (var lease = new FrontdoorBgmLease(
                    port,
                    root,
                    "host.frontdoor.lease-ready-test"))
                {
                    lease.EnterFrontdoor("test_start");
                    Assert.Empty(port.Acquires);

                    port.Publish(Snapshot(
                        AudioCoordinatorStatusV2.Ready,
                        null));
                    port.Publish(port.Snapshot);

                    AcquireCall call = Assert.Single(port.Acquires);
                    Assert.Equal(
                        FrontdoorBgmLease.TrackRelativePath,
                        call.Path);
                    Assert.True(call.Loop);
                    Assert.Equal(0.4f, call.Gain);
                    Assert.Equal(1f, call.FadeSeconds);
                }
            }
            finally
            {
                TryDelete(root);
            }
        }

        [Fact]
        public void YieldBeforeReadyPreventsLateReadyResurrection()
        {
            string root = CreateProjectRootWithTrack();
            try
            {
                var port = new FakePort(Snapshot(
                    AudioCoordinatorStatusV2.Recovering,
                    null));
                using (var lease = new FrontdoorBgmLease(
                    port,
                    root,
                    "host.frontdoor.lease-yield-test"))
                {
                    lease.EnterFrontdoor("recovering");
                    lease.YieldToGameplay("accepted_start");
                    port.Publish(Snapshot(
                        AudioCoordinatorStatusV2.Ready,
                        null));

                    Assert.Empty(port.Acquires);
                    Assert.Single(port.Revokes);
                }
            }
            finally
            {
                TryDelete(root);
            }
        }

        [Fact]
        public void ForeignReadySourceBlocksAcquireUntilSourceIsEmpty()
        {
            string root = CreateProjectRootWithTrack();
            try
            {
                var port = new FakePort(Snapshot(
                    AudioCoordinatorStatusV2.Ready,
                    "as2.scene.bgm"));
                using (var lease = new FrontdoorBgmLease(
                    port,
                    root,
                    "host.frontdoor.lease-foreign-source-test"))
                {
                    lease.EnterFrontdoor("foreign_source_active");
                    port.Publish(port.Snapshot);

                    Assert.Empty(port.Acquires);

                    port.Publish(Snapshot(
                        AudioCoordinatorStatusV2.Ready,
                        null));

                    Assert.Single(port.Acquires);
                }
            }
            finally
            {
                TryDelete(root);
            }
        }

        [Fact]
        public void DisposeUnsubscribesAndCannotReacquire()
        {
            string root = CreateProjectRootWithTrack();
            try
            {
                var port = new FakePort(Snapshot(
                    AudioCoordinatorStatusV2.Initializing,
                    null));
                var lease = new FrontdoorBgmLease(
                    port,
                    root,
                    "host.frontdoor.lease-dispose-test");
                lease.EnterFrontdoor("before_dispose");
                lease.Dispose();

                port.Publish(Snapshot(
                    AudioCoordinatorStatusV2.Ready,
                    null));

                Assert.Empty(port.Acquires);
                Assert.Single(port.Revokes);
            }
            finally
            {
                TryDelete(root);
            }
        }

        [Fact]
        public void RepositoryContainsFrozenMainMenuTrack()
        {
            string root = FindRepositoryRoot();
            string path = Path.Combine(
                root,
                FrontdoorBgmLease.TrackRelativePath);

            Assert.True(
                File.Exists(path),
                "Missing fixed launcher frontdoor BGM: " + path);
        }

        private static AudioCoordinatorSnapshotV2 Snapshot(
            AudioCoordinatorStatusV2 status,
            string sourceRequestId)
        {
            var qualification = new AudioCoordinatorQualificationStateV2
            {
                SourceRequestId = sourceRequestId,
            };
            return new AudioCoordinatorSnapshotV2(
                status,
                "00000000-0000-4000-8000-000000000001",
                1UL,
                status == AudioCoordinatorStatusV2.Ready ? 1UL : 0UL,
                @"C:\fixture",
                new string('A', 64),
                0,
                0,
                0,
                status == AudioCoordinatorStatusV2.Ready
                    ? AudioNativeV2.ResultOk
                    : AudioNativeV2.ResultNotReady,
                status == AudioCoordinatorStatusV2.Ready
                    ? "audio.ready"
                    : "audio.not_ready",
                0f,
                0f,
                0f,
                0f,
                sourceRequestId != null,
                "none",
                0UL,
                0UL,
                0UL,
                0UL,
                0UL,
                0UL,
                0UL,
                new Dictionary<string, int>(),
                qualification);
        }

        private static string CreateProjectRootWithTrack()
        {
            string root = Path.Combine(
                Path.GetTempPath(),
                "cf7-frontdoor-bgm-" + Guid.NewGuid().ToString("N"));
            string path = Path.Combine(
                root,
                FrontdoorBgmLease.TrackRelativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllBytes(path, new byte[] { 1 });
            return root;
        }

        private static string FindRepositoryRoot()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                if (File.Exists(Path.Combine(
                        current.FullName,
                        FrontdoorBgmLease.TrackRelativePath)) &&
                    Directory.Exists(Path.Combine(
                        current.FullName,
                        "launcher")))
                {
                    return current.FullName;
                }
                current = current.Parent;
            }
            throw new DirectoryNotFoundException(
                "Unable to locate repository root for frontdoor BGM test.");
        }

        private static void TryDelete(string root)
        {
            try { Directory.Delete(root, true); }
            catch { }
        }

        private sealed class AcquireCall
        {
            internal string RequestId;
            internal string Path;
            internal bool Loop;
            internal float Gain;
            internal float FadeSeconds;
        }

        private sealed class FakePort : IFrontdoorBgmAudioPort
        {
            internal FakePort(AudioCoordinatorSnapshotV2 snapshot)
            {
                Snapshot = snapshot;
            }

            public AudioCoordinatorSnapshotV2 Snapshot { get; private set; }
            public event Action<AudioCoordinatorSnapshotV2> SnapshotChanged;
            internal List<AcquireCall> Acquires { get; } =
                new List<AcquireCall>();
            internal List<string> Revokes { get; } = new List<string>();

            public bool TryAcquire(
                string requestId,
                string path,
                bool loop,
                float gain,
                float fadeSeconds)
            {
                Acquires.Add(new AcquireCall
                {
                    RequestId = requestId,
                    Path = path,
                    Loop = loop,
                    Gain = gain,
                    FadeSeconds = fadeSeconds,
                });
                Publish(FrontdoorBgmLeaseTests.Snapshot(
                    AudioCoordinatorStatusV2.Ready,
                    requestId));
                return true;
            }

            public bool Revoke(string requestId, float fadeSeconds)
            {
                Revokes.Add(requestId);
                if (string.Equals(
                        Snapshot.SourceRequestId,
                        requestId,
                        StringComparison.Ordinal))
                {
                    Publish(FrontdoorBgmLeaseTests.Snapshot(
                        AudioCoordinatorStatusV2.Ready,
                        null));
                }
                return true;
            }

            internal void Publish(AudioCoordinatorSnapshotV2 snapshot)
            {
                Snapshot = snapshot;
                Action<AudioCoordinatorSnapshotV2> handler = SnapshotChanged;
                if (handler != null) handler(snapshot);
            }
        }
    }
}
