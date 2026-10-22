using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using CF7Launcher.Audio;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class BgmLeaseTests
    {
        [Fact]
        public void RequestIdsRequireExactSessionSequenceSuffixAndOperation()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                string otherSession = "fedcba98-7654-4abc-9def-0123456789ab";
                var invalid = new[]
                {
                    Tuple.Create(Lease(tuple, "1", "acquire"), AudioWireV2.BgmResume),
                    Tuple.Create(Lease(tuple, "1", "release"), AudioWireV2.BgmPause),
                    Tuple.Create("bgm.as2.lease." + otherSession + ".1.acquire", AudioWireV2.BgmPause),
                    Tuple.Create("bgm.as2.lease." + tuple.AudioSessionId + "..acquire", AudioWireV2.BgmPause),
                    Tuple.Create(Lease(tuple, "0", "acquire"), AudioWireV2.BgmPause),
                    Tuple.Create(Lease(tuple, "01", "acquire"), AudioWireV2.BgmPause),
                    Tuple.Create(Lease(tuple, "1.acquire.extra", "acquire"), AudioWireV2.BgmPause),
                    Tuple.Create("bgm.as2.lease-evil." + tuple.AudioSessionId + ".1.acquire", AudioWireV2.BgmPause),
                    Tuple.Create("bgm.as2.lease", AudioWireV2.BgmPause),
                    Tuple.Create(Lease(tuple, "1.release.extra", "release"), AudioWireV2.BgmResume)
                };
                foreach (var item in invalid)
                {
                    AudioBgmResultV2 result = Send(coordinator, Request(tuple, item.Item1, item.Item2));
                    Assert.Equal("failed", result.CompletionState);
                    Assert.Equal("internal_error", result.Category);
                    Assert.Equal("audio.bgm.lease_invalid", result.MessageKey);
                }
                Assert.Equal(0, native.SubmitBgmCount);

                AudioBgmResultV2 stale = Send(coordinator, new AudioBgmRequestV2(
                    Lease(tuple, "2", "acquire"), tuple.AudioSessionId,
                    tuple.AudioReadyGeneration + 1UL, AudioWireV2.BgmPause,
                    null, null, null, null, null));
                Assert.Equal("stale_generation", stale.Category);
                Assert.Equal(0, native.SubmitBgmCount);

                AssertOk(Send(coordinator, Request(tuple, "bgm.as2.ordinary.pause", AudioWireV2.BgmPause)));
                AssertOk(Send(coordinator, Request(tuple, "bgm.as2.ordinary.resume", AudioWireV2.BgmResume)));
                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPause,
                    AudioNativeV2.OperationBgmResume
                }, native.NativeBgmOperations);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void AcquireWithoutPlayIntentOrWithUserPauseHasNoNativeWork(bool userPaused)
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                if (userPaused)
                {
                    Play(coordinator, tuple, "user.mp3");
                    AssertOk(Send(coordinator, Request(tuple, "user.pause", AudioWireV2.BgmPause)));
                }
                int before = native.SubmitBgmCount;
                AssertOk(Send(coordinator, Request(tuple, Lease(tuple, "1", "acquire"), AudioWireV2.BgmPause)));
                Assert.Equal(before, native.SubmitBgmCount);
                AssertOk(Send(coordinator, Request(tuple, Lease(tuple, "1", "release"), AudioWireV2.BgmResume)));
                Assert.Equal(before, native.SubmitBgmCount);
            }
        }

        [Fact]
        public void FailedAcquireDoesNotClaimPauseOrResumeCapability()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                native.SubmitBgmNotReadyRemaining = 1;
                AudioBgmResultV2 acquire = Send(coordinator,
                    Request(tuple, Lease(tuple, "1", "acquire"), AudioWireV2.BgmPause));
                Assert.Equal("failed", acquire.CompletionState);
                Assert.Equal("not_ready", acquire.Category);
                AssertOk(Send(coordinator,
                    Request(tuple, Lease(tuple, "1", "release"), AudioWireV2.BgmResume)));
                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmPause
                }, native.NativeBgmOperations);
            }
        }

        [Fact]
        public void ValidationFailureOfExternalPlayKeepsLeaseResumeDuty()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                AudioBgmResultV2 failed = Send(coordinator,
                    Request(tuple, "jukebox.invalid.play", AudioWireV2.BgmPlay, "../outside.mp3"));
                Assert.Equal("failed", failed.CompletionState);
                Assert.Equal("io_error", failed.Category);
                Release(coordinator, tuple, "1");
                Assert.Equal(AudioNativeV2.OperationBgmResume,
                    native.BgmCommands.Last().Operation);
            }
        }

        [Fact]
        public void NativeFailureOfExternalPlayKeepsLeaseResumeDuty()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                native.SubmitBgmNotReadyRemaining = 1;
                AudioBgmResultV2 failed = Send(coordinator,
                    Request(tuple, "jukebox.failed.play", AudioWireV2.BgmPlay, "sounds/music/next.mp3"));
                Assert.Equal("failed", failed.CompletionState);
                Assert.Equal("not_ready", failed.Category);
                Release(coordinator, tuple, "1");
                Assert.Equal(AudioNativeV2.OperationBgmResume,
                    native.BgmCommands.Last().Operation);
            }
        }

        [Fact]
        public void NullExternalPlayResultUsesTerminalAuthorityWithoutBlindReplay()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                native.SubmitBgmNullResultRemaining = 1;
                AudioBgmResultV2 unknown = Send(coordinator,
                    Request(tuple, "jukebox.unknown.play", AudioWireV2.BgmPlay, "sounds/music/next.mp3"));
                Assert.Equal("failed", unknown.CompletionState);
                Assert.Equal("internal_error", unknown.Category);
                Assert.Equal(AudioCoordinatorStatusV2.Unavailable, coordinator.Snapshot.Status);
                AssertOk(Send(coordinator,
                    Request(coordinator.Snapshot, Lease(tuple, "1", "release"), AudioWireV2.BgmResume)));
                Assert.True(coordinator.RecoverDevice());
                Assert.DoesNotContain(native.BgmCommands,
                    command => command.Operation == AudioNativeV2.OperationBgmResume);
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    native.BgmCommands.Last().Operation);
                Assert.Equal("room.mp3", Path.GetFileName(native.BgmCommands.Last(
                    command => command.Operation == AudioNativeV2.OperationBgmPlay).NormalizedPath));
            }
        }

        [Theory]
        [InlineData(AudioWireV2.BgmPlay)]
        [InlineData(AudioWireV2.BgmStop)]
        [InlineData(AudioWireV2.BgmPause)]
        [InlineData(AudioWireV2.BgmResume)]
        public void SuccessfulExternalCommandSupersedesLateRelease(string operation)
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                AssertOk(Send(coordinator, Request(tuple, "jukebox.external." + operation,
                    operation, "sounds/music/new-room.mp3")));
                int before = native.SubmitBgmCount;
                AssertOk(Send(coordinator,
                    Request(tuple, Lease(tuple, "1", "release"), AudioWireV2.BgmResume)));
                Assert.Equal(before, native.SubmitBgmCount);
                Assert.Equal(3, native.SubmitBgmCount);
            }
        }

        [Fact]
        public void OldReleaseCannotOverrideReplacementAcquire()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                Acquire(coordinator, tuple, "2");
                AssertOk(Send(coordinator,
                    Request(tuple, Lease(tuple, "1", "release"), AudioWireV2.BgmResume)));
                Assert.Equal(2, native.SubmitBgmCount);
                Release(coordinator, tuple, "2");
                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmPause,
                    AudioNativeV2.OperationBgmResume
                }, native.NativeBgmOperations);
            }
        }

        [Fact]
        public void DeviceRecoveryRestoresSameTrackPausedUntilCurrentRelease()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                Assert.True(coordinator.RecoverDevice());
                AudioCoordinatorSnapshotV2 recovered = coordinator.Snapshot;
                Assert.True(recovered.IsReady);
                Assert.Equal(tuple.AudioReadyGeneration + 1UL, recovered.AudioReadyGeneration);
                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmPause,
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmSeek,
                    AudioNativeV2.OperationBgmPause
                }, native.BgmCommands.Select(command => command.Operation).ToArray());
                Release(coordinator, recovered, "1");
                Assert.Equal(AudioNativeV2.OperationBgmResume,
                    native.BgmCommands.Last().Operation);
            }
        }

        [Fact]
        public void ReleaseDuringPendingRecoveryDropsOnlyLeasePause()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var qualificationArrived = new ManualResetEventSlim(false))
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCatalogQualificationRequestV2 qualification = null;
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 value)
                    {
                        qualification = value;
                        qualificationArrived.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(qualificationArrived.Wait(TimeSpan.FromSeconds(2)));
                Assert.True(CompleteQualification(coordinator, qualification));
                AudioCoordinatorSnapshotV2 tuple = coordinator.Snapshot;
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");

                qualificationArrived.Reset();
                Assert.False(coordinator.RecoverDevice());
                Assert.True(qualificationArrived.Wait(TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 recovery = qualification;
                Assert.Equal(AudioCoordinatorStatusV2.Recovering, coordinator.Snapshot.Status);
                AssertOk(Send(coordinator,
                    Request(coordinator.Snapshot, Lease(tuple, "1", "release"), AudioWireV2.BgmResume)));
                Assert.True(CompleteQualification(coordinator, recovery));
                Assert.True(coordinator.Snapshot.IsReady);
                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmPause,
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmSeek
                }, native.BgmCommands.Select(command => command.Operation).ToArray());
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void TerminalUnavailableAndLaterRecoveryPreserveUserPauseOnly(bool userPaused)
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                if (userPaused)
                    AssertOk(Send(coordinator, Request(tuple, "user.pause", AudioWireV2.BgmPause)));
                Acquire(coordinator, tuple, "1");
                int beforeRecovery = native.SubmitBgmCount;
                native.CapabilitySucceeds = false;
                Assert.False(coordinator.RecoverDevice());
                Assert.Equal(AudioCoordinatorStatusV2.Unavailable, coordinator.Snapshot.Status);
                AssertOk(Send(coordinator,
                    Request(coordinator.Snapshot, Lease(tuple, "1", "release"), AudioWireV2.BgmResume)));
                Assert.Equal(beforeRecovery, native.SubmitBgmCount);

                native.CapabilitySucceeds = true;
                Assert.True(coordinator.RecoverDevice());
                Assert.Equal(beforeRecovery + (userPaused ? 3 : 2), native.SubmitBgmCount);
                Assert.Equal(userPaused
                    ? AudioNativeV2.OperationBgmPause
                    : AudioNativeV2.OperationBgmSeek,
                    native.BgmCommands.Last().Operation);
                Assert.DoesNotContain(native.BgmCommands,
                    command => command.Operation == AudioNativeV2.OperationBgmResume);
            }
        }

        [Fact]
        public void ResetRejectsOldReleaseWithoutTouchingNewGeneration()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                Assert.True(coordinator.Initialize(TestRoot()));
                Assert.NotEqual(tuple.AudioSessionId, coordinator.Snapshot.AudioSessionId);
                int before = native.SubmitBgmCount;
                AudioBgmResultV2 late = Send(coordinator,
                    Request(tuple, Lease(tuple, "1", "release"), AudioWireV2.BgmResume));
                Assert.Equal("stale_generation", late.Category);
                Assert.Equal(before, native.SubmitBgmCount);
            }
        }

        [Fact]
        public void ShutdownCannotReplayLateRelease()
        {
            var native = new AudioCoordinatorTests.FakeAudioNativeV2(new List<string>());
            using (var coordinator = AudioCoordinatorTests.Coordinator(native, false))
            {
                AudioCoordinatorSnapshotV2 tuple = Ready(coordinator);
                Play(coordinator, tuple, "room.mp3");
                Acquire(coordinator, tuple, "1");
                int before = native.SubmitBgmCount;
                coordinator.Shutdown();
                AudioBgmResultV2 late = Send(coordinator,
                    Request(coordinator.Snapshot, Lease(tuple, "1", "release"), AudioWireV2.BgmResume));
                Assert.Equal("failed", late.CompletionState);
                Assert.Equal(before, native.SubmitBgmCount);
            }
        }

        private static AudioCoordinatorSnapshotV2 Ready(AudioCoordinator coordinator)
        {
            Assert.True(coordinator.Initialize(TestRoot()));
            Assert.True(coordinator.Snapshot.IsReady);
            return coordinator.Snapshot;
        }

        private static void Play(
            AudioCoordinator coordinator,
            AudioCoordinatorSnapshotV2 tuple,
            string filename)
        {
            AssertOk(Send(coordinator, Request(tuple, "room.play." + filename,
                AudioWireV2.BgmPlay, "sounds/music/" + filename)));
        }

        private static void Acquire(
            AudioCoordinator coordinator,
            AudioCoordinatorSnapshotV2 tuple,
            string sequence)
        {
            AssertOk(Send(coordinator,
                Request(tuple, Lease(tuple, sequence, "acquire"), AudioWireV2.BgmPause)));
        }

        private static void Release(
            AudioCoordinator coordinator,
            AudioCoordinatorSnapshotV2 tuple,
            string sequence)
        {
            AssertOk(Send(coordinator,
                Request(tuple, Lease(tuple, sequence, "release"), AudioWireV2.BgmResume)));
        }

        private static string Lease(
            AudioCoordinatorSnapshotV2 tuple,
            string sequence,
            string suffix)
        {
            return "bgm.as2.lease." + tuple.AudioSessionId + "." + sequence + "." + suffix;
        }

        private static AudioBgmRequestV2 Request(
            AudioCoordinatorSnapshotV2 tuple,
            string requestId,
            string operation,
            string path = null)
        {
            return new AudioBgmRequestV2(
                requestId,
                tuple.AudioSessionId,
                tuple.AudioReadyGeneration,
                operation,
                path,
                operation == AudioWireV2.BgmPlay ? true : (bool?)null,
                operation == AudioWireV2.BgmPlay ? 0.5d : (double?)null,
                operation == AudioWireV2.BgmPlay || operation == AudioWireV2.BgmStop
                    ? 0d
                    : (double?)null,
                null);
        }

        private static AudioBgmResultV2 Send(
            AudioCoordinator coordinator,
            AudioBgmRequestV2 request)
        {
            AudioBgmResultV2 result = null;
            using (var completed = new ManualResetEventSlim(false))
            {
                coordinator.DispatchBgm(request, delegate(AudioBgmResultV2 value)
                {
                    result = value;
                    completed.Set();
                });
                Assert.True(completed.Wait(TimeSpan.FromSeconds(2)));
            }
            Assert.NotNull(result);
            return result;
        }

        private static void AssertOk(AudioBgmResultV2 result)
        {
            Assert.Equal("ok", result.Category);
            Assert.NotEqual("failed", result.CompletionState);
        }

        private static bool CompleteQualification(
            AudioCoordinator coordinator,
            AudioCatalogQualificationRequestV2 request)
        {
            return coordinator.CompleteCatalogQualification(
                request.AudioSessionId,
                request.AudioReadyGeneration,
                request.DeviceGeneration,
                request.CapabilityDigest,
                true);
        }

        private static string TestRoot()
        {
            return Path.GetFullPath(Path.Combine(
                Path.GetTempPath(),
                "cf7-audio-coordinator-tests"));
        }
    }
}
