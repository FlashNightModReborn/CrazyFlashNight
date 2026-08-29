using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Audio;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioCoordinatorTests
    {
        [Fact]
        public void Rebuild_UsesFrozenOrderAndPublishesOneReadyEpoch()
        {
            var events = new List<string>();
            var native = new FakeAudioNativeV2(events);
            AudioCoordinator coordinator = null;
            coordinator = new AudioCoordinator(
                native,
                delegate(string root, CancellationToken token)
                {
                    events.Add("preload");
                    AudioCoordinatorSnapshotV2 during = coordinator.Snapshot;
                    Assert.Equal(
                        AudioCoordinatorStatusV2.Initializing,
                        during.Status);
                    Assert.Equal(1UL, during.AudioReadyGeneration);
                    return Catalog(root, "shot.wav");
                },
                delegate(
                    string session,
                    ulong ready,
                    ulong device,
                    AudioPreloadResultV2 catalog,
                    CancellationToken token)
                {
                    events.Add("catalog_hook");
                    Assert.Equal(1UL, ready);
                    Assert.Equal(1UL, device);
                    Assert.Equal(
                        AudioCoordinatorStatusV2.Initializing,
                        coordinator.Snapshot.Status);
                });

            try
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                Assert.Equal(
                    new[]
                    {
                        "capability", "initialize", "preload",
                        "native_catalog", "catalog_hook"
                    },
                    events.Take(5).ToArray());
                AudioCoordinatorSnapshotV2 ready = coordinator.Snapshot;
                Assert.Equal(AudioCoordinatorStatusV2.Ready, ready.Status);
                Assert.Equal(1UL, ready.AudioReadyGeneration);
                Assert.Equal(1UL, ready.DeviceGeneration);
                Assert.Equal(1, ready.Loaded);
                Assert.True(ready.IsSfxPreloadComplete);
                Assert.Equal(
                    coordinator.ResolveSfxHandle("shot.wav"),
                    ready.SfxHandles["shot.wav"]);
            }
            finally
            {
                coordinator.Shutdown();
            }
        }

        [Fact]
        public void BeginInitialize_QueuesWorkAndAppliesConfiguredInitialGain()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.MutationDelayMilliseconds = 20;
            using (var coordinator = Coordinator(native))
            using (var ready = new ManualResetEventSlim(false))
            {
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    if (snapshot.IsReady) ready.Set();
                };
                Assert.True(coordinator.ConfigureInitialMasterGain(0.5f));
                Assert.True(coordinator.BeginInitialize(TestRoot()));
                Assert.True(ready.Wait(TimeSpan.FromSeconds(3)));
                Assert.True(coordinator.Snapshot.IsReady);
                Assert.Equal(1, native.SetGainCount);
                Assert.False(coordinator.ConfigureInitialMasterGain(0.25f));
            }
        }

        [Fact]
        public void Initialize_RetriesTransientDeviceStartWithinOneReadyEpoch()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.InitializeFailuresRemaining = 2;
            using (var coordinator = Coordinator(native, false))
            {
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.Equal(AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);
                Assert.Equal(1UL,
                    coordinator.Snapshot.AudioReadyGeneration);
                Assert.Equal(1, native.InitializeCount);

                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(2, native.InitializeCount);
                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(2, native.InitializeCount);
                Assert.True(coordinator.PollNativeRuntimeOnce());

                Assert.True(coordinator.Snapshot.IsReady);
                Assert.Equal(1UL,
                    coordinator.Snapshot.AudioReadyGeneration);
                Assert.Equal(3, native.InitializeCount);
                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(3, native.InitializeCount);
            }
        }

        [Fact]
        public void Initialize_ExhaustsFiveDeviceStartAttemptsOnce()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.InitializeSucceeds = false;
            using (var coordinator = Coordinator(native, false))
            {
                Assert.False(coordinator.Initialize(TestRoot()));
                for (int tick = 0; tick < 15; tick++)
                    coordinator.PollNativeRuntimeOnce();

                Assert.Equal(AudioCoordinatorStatusV2.Unavailable,
                    coordinator.Snapshot.Status);
                Assert.Equal(AudioNativeV2.ResultDeviceUnavailable,
                    coordinator.Snapshot.FailureCategory);
                Assert.Equal(1UL,
                    coordinator.Snapshot.AudioReadyGeneration);
                Assert.Equal(5, native.InitializeCount);
                for (int tick = 0; tick < 20; tick++)
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(5, native.InitializeCount);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void CatalogQualification_InitializeVariantsStayPendingWithExactRequest(
            bool beginInitialize)
        {
            var native = new FakeAudioNativeV2(new List<string>());
            AudioCatalogQualificationRequestV2 request = null;
            int readySnapshots = 0;
            using (var hookCalled = new ManualResetEventSlim(false))
            using (var coordinator = Coordinator(native))
            {
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    if (snapshot.IsReady)
                        Interlocked.Increment(ref readySnapshots);
                };
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 value)
                    {
                        request = value;
                        hookCalled.Set();
                    }));

                if (beginInitialize)
                    Assert.True(coordinator.BeginInitialize(TestRoot()));
                else
                    Assert.False(coordinator.Initialize(TestRoot()));

                Assert.True(hookCalled.Wait(TimeSpan.FromSeconds(2)));
                Assert.NotNull(request);
                AudioCoordinatorSnapshotV2 pending = coordinator.Snapshot;
                Assert.Equal(
                    AudioCoordinatorStatusV2.Initializing,
                    pending.Status);
                Assert.False(pending.IsReady);
                Assert.Equal("audio.catalog_qualifying", pending.MessageKey);
                Assert.Equal(0, Volatile.Read(ref readySnapshots));
                Assert.Equal(pending.AudioSessionId, request.AudioSessionId);
                Assert.Equal(
                    pending.AudioReadyGeneration,
                    request.AudioReadyGeneration);
                Assert.Equal(
                    pending.DeviceGeneration,
                    request.DeviceGeneration);
                Assert.Equal(pending.CapabilityDigest, request.CapabilityDigest);
                Assert.Equal(new string('A', 64), request.CapabilityDigest);
                Assert.Equal(1UL, request.AudioReadyGeneration);
                Assert.Equal(1UL, request.DeviceGeneration);
                Assert.False(request.CancellationToken.IsCancellationRequested);
                Assert.Equal(1, native.InitializeCount);
            }
        }

        [Fact]
        public void CatalogQualification_PendingAllowsRuntimeProbeThroughNative()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                AudioCatalogQualificationRequestV2 request =
                    StartPendingQualification(coordinator);
                AudioCoordinatorSnapshotV2 pending = coordinator.Snapshot;

                AudioRuntimeProbeResultV2 result =
                    coordinator.ProbeRuntimeCompatibility(
                        Path.Combine(TestRoot(), "sounds", "probe.ogg"),
                        4096UL,
                        1234L,
                        new string('B', 64),
                        request.CapabilityDigest);

                Assert.True(result.Valid);
                Assert.Equal(
                    AudioNativeV2.ProbeCompatibleSignalPresent,
                    result.Outcome);
                Assert.Equal(1, native.ProbeRuntimeCount);
                Assert.Equal(request.AudioSessionId,
                    result.Result.AudioSessionId);
                Assert.Equal(request.AudioReadyGeneration,
                    result.Result.AudioReadyGeneration);
                Assert.Equal(request.DeviceGeneration,
                    result.Result.DeviceGeneration);
                Assert.Same(pending, coordinator.Snapshot);
                Assert.False(coordinator.Snapshot.IsReady);
            }
        }

        [Fact]
        public void CatalogQualification_PendingRejectsPlaybackBeforeSuccess()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            using (var bgmResponded = new ManualResetEventSlim(false))
            {
                StartPendingQualification(coordinator);
                AudioCoordinatorSnapshotV2 pending = coordinator.Snapshot;
                AudioBgmResultV2 bgmResult = null;

                coordinator.DispatchBgm(Request(
                    pending,
                    "qualification.pending.bgm",
                    "sounds/music/pending.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        bgmResult = result;
                        bgmResponded.Set();
                    });
                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    pending.AudioSessionId,
                    pending.AudioReadyGeneration,
                    1UL,
                    new[] { "shot.wav", "shell.wav", "voice.wav" }));

                Assert.True(bgmResponded.Wait(TimeSpan.FromSeconds(2)));
                coordinator.RefreshObservation();
                Assert.NotNull(bgmResult);
                Assert.Equal("failed", bgmResult.CompletionState);
                Assert.Equal("not_ready", bgmResult.Category);
                Assert.Equal(
                    "audio.catalog_qualifying",
                    bgmResult.MessageKey);
                Assert.Equal(0, native.SubmitBgmCount);
                Assert.Equal(0, native.SubmitSfxCount);
                Assert.Equal(3UL, coordinator.Snapshot.PreReadyDrops);
                Assert.False(coordinator.Snapshot.IsReady);
            }
        }

        [Fact]
        public void CatalogQualification_OnlyExactCompletionPublishesReady()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            int readySnapshots = 0;
            using (var coordinator = Coordinator(native))
            {
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    if (snapshot.IsReady)
                        Interlocked.Increment(ref readySnapshots);
                };
                AudioCatalogQualificationRequestV2 request =
                    StartPendingQualification(coordinator);
                AudioCoordinatorSnapshotV2 pending = coordinator.Snapshot;
                int shutdownsBefore = native.ShutdownCount;

                Assert.False(coordinator.CompleteCatalogQualification(
                    Guid.NewGuid().ToString("D"),
                    request.AudioReadyGeneration,
                    request.DeviceGeneration,
                    request.CapabilityDigest,
                    true));
                Assert.Same(pending, coordinator.Snapshot);
                Assert.False(coordinator.CompleteCatalogQualification(
                    request.AudioSessionId,
                    request.AudioReadyGeneration + 1UL,
                    request.DeviceGeneration,
                    request.CapabilityDigest,
                    true));
                Assert.Same(pending, coordinator.Snapshot);
                Assert.False(coordinator.CompleteCatalogQualification(
                    request.AudioSessionId,
                    request.AudioReadyGeneration,
                    request.DeviceGeneration + 1UL,
                    request.CapabilityDigest,
                    true));
                Assert.Same(pending, coordinator.Snapshot);
                Assert.False(coordinator.CompleteCatalogQualification(
                    request.AudioSessionId,
                    request.AudioReadyGeneration,
                    request.DeviceGeneration,
                    new string('B', 64),
                    true));
                Assert.Same(pending, coordinator.Snapshot);
                Assert.Equal(0, Volatile.Read(ref readySnapshots));
                Assert.Equal(shutdownsBefore, native.ShutdownCount);

                Assert.True(CompleteQualification(
                    coordinator, request, true));
                AudioCoordinatorSnapshotV2 ready = coordinator.Snapshot;
                Assert.Equal(AudioCoordinatorStatusV2.Ready, ready.Status);
                Assert.Equal(request.AudioSessionId, ready.AudioSessionId);
                Assert.Equal(request.AudioReadyGeneration,
                    ready.AudioReadyGeneration);
                Assert.Equal(request.DeviceGeneration,
                    ready.DeviceGeneration);
                Assert.Equal(1, Volatile.Read(ref readySnapshots));
                Assert.Equal(shutdownsBefore, native.ShutdownCount);

                Assert.False(CompleteQualification(
                    coordinator, request, true));
                Assert.Same(ready, coordinator.Snapshot);
                Assert.Equal(1, Volatile.Read(ref readySnapshots));
            }
        }

        [Fact]
        public void HotCatalogQualification_RebuildsNativeAndAdmitsOnlyExactNewEpoch()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var requests = new List<AudioCatalogQualificationRequestV2>();
            using (var coordinator = Coordinator(native))
            using (var bgmResponded = new ManualResetEventSlim(false))
            using (var newBgmResponded = new ManualResetEventSlim(false))
            using (var qualificationArrived = new AutoResetEvent(false))
            {
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 request)
                    {
                        lock (requests) requests.Add(request);
                        qualificationArrived.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 initial;
                lock (requests) initial = Assert.Single(requests);
                Assert.True(CompleteQualification(
                    coordinator, initial, true));
                AudioCoordinatorSnapshotV2 oldReady = coordinator.Snapshot;
                Assert.True(oldReady.IsReady);
                coordinator.DispatchBgm(
                    Request(
                        oldReady,
                        "hot.catalog.prior.bgm",
                        "sounds/music/prior.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        if (result.CompletionState == "started")
                            newBgmResponded.Set();
                    });
                Assert.True(newBgmResponded.Wait(TimeSpan.FromSeconds(2)));
                newBgmResponded.Reset();

                Assert.True(coordinator.BeginCatalogRefreshRebuild(
                    oldReady.CapabilityDigest));
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 replacement = null;
                lock (requests)
                {
                    Assert.Collection(
                        requests,
                        delegate(AudioCatalogQualificationRequestV2 actual)
                        {
                            Assert.Same(initial, actual);
                        },
                        delegate(AudioCatalogQualificationRequestV2 actual)
                        {
                            replacement = actual;
                        });
                }
                Assert.NotNull(replacement);
                AudioCoordinatorSnapshotV2 pending = coordinator.Snapshot;
                Assert.Equal(AudioCoordinatorStatusV2.Recovering, pending.Status);
                Assert.Equal("audio.catalog_qualifying", pending.MessageKey);
                Assert.Equal(
                    oldReady.AudioReadyGeneration + 1UL,
                    pending.AudioReadyGeneration);
                Assert.Equal(
                    oldReady.DeviceGeneration + 1UL,
                    pending.DeviceGeneration);
                Assert.Equal(2, native.InitializeCount);
                Assert.Equal(pending.AudioSessionId,
                    replacement.AudioSessionId);
                Assert.Equal(pending.AudioReadyGeneration,
                    replacement.AudioReadyGeneration);
                Assert.Equal(pending.DeviceGeneration,
                    replacement.DeviceGeneration);

                AudioBgmResultV2 staleBgm = null;
                coordinator.DispatchBgm(
                    Request(
                        oldReady,
                        "hot.catalog.old.bgm",
                        "sounds/music/old.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        staleBgm = result;
                        bgmResponded.Set();
                    });
                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    oldReady.AudioSessionId,
                    oldReady.AudioReadyGeneration,
                    1UL,
                    new[] { "shot.wav", "shell.wav", "voice.wav" }));
                Assert.True(bgmResponded.Wait(TimeSpan.FromSeconds(2)));
                coordinator.RefreshObservation();

                Assert.NotNull(staleBgm);
                Assert.Equal("failed", staleBgm.CompletionState);
                Assert.Equal("stale_generation", staleBgm.Category);
                Assert.Equal(pending.AudioReadyGeneration,
                    staleBgm.AudioReadyGeneration);
                Assert.Equal(1, native.SubmitBgmCount);
                Assert.Equal(0, native.SubmitSfxCount);
                Assert.Equal(3UL, coordinator.Snapshot.StaleGenerationDrops);

                Assert.False(CompleteQualification(
                    coordinator, initial, true));
                Assert.False(coordinator.Snapshot.IsReady);

                Assert.True(CompleteQualification(
                    coordinator, replacement, true));
                AudioCoordinatorSnapshotV2 newReady = coordinator.Snapshot;
                Assert.True(newReady.IsReady);
                Assert.Equal(replacement.AudioSessionId,
                    newReady.AudioSessionId);
                Assert.Equal(replacement.AudioReadyGeneration,
                    newReady.AudioReadyGeneration);
                Assert.Equal(replacement.DeviceGeneration,
                    newReady.DeviceGeneration);
                Assert.Equal(1, newReady.Loaded);
                Assert.Equal(3, native.SubmitBgmCount);

                coordinator.DispatchBgm(
                    Request(
                        newReady,
                        "hot.catalog.new.bgm",
                        "sounds/music/new.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        if (result.CompletionState == "started")
                            newBgmResponded.Set();
                    });
                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    newReady.AudioSessionId,
                    newReady.AudioReadyGeneration,
                    1UL,
                    new[] { "shot.wav" }));
                Assert.True(newBgmResponded.Wait(TimeSpan.FromSeconds(2)));
                Assert.True(native.SfxSubmitted.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal(4, native.SubmitBgmCount);
                Assert.Equal(1, native.SubmitSfxCount);
            }
        }

        [Fact]
        public void CatalogQualification_FailedCompletionPublishesUnavailable()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            int readySnapshots = 0;
            using (var coordinator = Coordinator(native))
            {
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    if (snapshot.IsReady)
                        Interlocked.Increment(ref readySnapshots);
                };
                AudioCatalogQualificationRequestV2 request =
                    StartPendingQualification(coordinator);

                Assert.False(CompleteQualification(
                    coordinator, request, false));
                AudioCoordinatorSnapshotV2 unavailable = coordinator.Snapshot;
                Assert.Equal(
                    AudioCoordinatorStatusV2.Unavailable,
                    unavailable.Status);
                Assert.False(unavailable.IsReady);
                Assert.Equal(
                    AudioNativeV2.ResultInternalError,
                    unavailable.FailureCategory);
                Assert.Equal(
                    "audio.catalog_qualification_failed",
                    unavailable.MessageKey);
                Assert.Equal(request.AudioSessionId,
                    unavailable.AudioSessionId);
                Assert.Equal(request.AudioReadyGeneration,
                    unavailable.AudioReadyGeneration);
                Assert.Equal(request.DeviceGeneration,
                    unavailable.DeviceGeneration);
                Assert.Equal(0, Volatile.Read(ref readySnapshots));
                Assert.Equal(1, native.ShutdownCount);

                Assert.False(CompleteQualification(
                    coordinator, request, true));
                Assert.Same(unavailable, coordinator.Snapshot);
                Assert.Equal(1, native.ShutdownCount);
            }
        }

        [Fact]
        public void CatalogQualification_RecoveryReplaysBgmOnlyAfterCompletion()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var requests = new List<AudioCatalogQualificationRequestV2>();
            using (var coordinator = Coordinator(native))
            using (var bgmStarted = new ManualResetEventSlim(false))
            using (var qualificationArrived = new AutoResetEvent(false))
            {
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 request)
                    {
                        lock (requests) requests.Add(request);
                        qualificationArrived.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 initial;
                lock (requests) initial = Assert.Single(requests);
                Assert.True(CompleteQualification(
                    coordinator, initial, true));
                AudioCoordinatorSnapshotV2 firstReady = coordinator.Snapshot;

                coordinator.DispatchBgm(Request(
                    firstReady,
                    "qualification.recovery.bgm",
                    "sounds/music/qualified.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        if (result.CompletionState == "started")
                            bgmStarted.Set();
                    });
                Assert.True(bgmStarted.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal(1, native.SubmitBgmCount);

                Assert.False(coordinator.RecoverDevice());
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 recovery = null;
                lock (requests)
                {
                    Assert.Collection(
                        requests,
                        delegate(AudioCatalogQualificationRequestV2 actual)
                        {
                            Assert.Same(initial, actual);
                        },
                        delegate(AudioCatalogQualificationRequestV2 actual)
                        {
                            recovery = actual;
                        });
                }
                Assert.NotNull(recovery);
                AudioCoordinatorSnapshotV2 pending = coordinator.Snapshot;
                Assert.Equal(
                    AudioCoordinatorStatusV2.Recovering,
                    pending.Status);
                Assert.Equal("audio.catalog_qualifying", pending.MessageKey);
                Assert.Equal(firstReady.AudioSessionId,
                    recovery.AudioSessionId);
                Assert.Equal(firstReady.AudioReadyGeneration + 1UL,
                    recovery.AudioReadyGeneration);
                Assert.Equal(firstReady.DeviceGeneration + 1UL,
                    recovery.DeviceGeneration);
                Assert.Equal(1, native.SubmitBgmCount);

                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    recovery.AudioSessionId,
                    recovery.AudioReadyGeneration,
                    1UL,
                    new[] { "shot.wav", "shell.wav", "voice.wav" }));
                coordinator.RefreshObservation();
                Assert.Equal(0, native.SubmitSfxCount);
                Assert.Equal(3UL, coordinator.Snapshot.RecoveryDrops);
                AudioCoordinatorSnapshotV2 pendingAfterDrop =
                    coordinator.Snapshot;

                Assert.False(CompleteQualification(
                    coordinator, initial, true));
                Assert.Same(pendingAfterDrop, coordinator.Snapshot);
                Assert.Equal(1, native.SubmitBgmCount);

                Assert.True(CompleteQualification(
                    coordinator, recovery, true));
                AudioCoordinatorSnapshotV2 recovered = coordinator.Snapshot;
                Assert.Equal(AudioCoordinatorStatusV2.Ready, recovered.Status);
                Assert.Equal(recovery.AudioReadyGeneration,
                    recovered.AudioReadyGeneration);
                Assert.Equal(recovery.DeviceGeneration,
                    recovered.DeviceGeneration);
                Assert.Equal(3, native.SubmitBgmCount);
                AudioNativeBgmCommandV2 replay =
                    native.BgmCommands[native.BgmCommands.Length - 2];
                AudioNativeBgmCommandV2 replaySeek =
                    native.BgmCommands.Last();
                Assert.Equal(AudioNativeV2.OperationBgmPlay,
                    replay.Operation);
                Assert.Equal(0f, replay.Volume);
                Assert.Equal("qualified.mp3",
                    Path.GetFileName(replay.NormalizedPath));
                Assert.Equal(recovery.AudioSessionId, replay.AudioSessionId);
                Assert.Equal(recovery.AudioReadyGeneration,
                    replay.AudioReadyGeneration);
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    replaySeek.Operation);
                Assert.Equal(3.5f, replaySeek.SeekSeconds);
                Assert.Equal(0.5f, native.SetGainValues.Last());
            }
        }

        [Fact]
        public void Rebuild_NoRealOutputFailsClosedWithoutProcessException()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.InitializeSucceeds = false;
            using (var coordinator = Coordinator(native))
            {
                Exception error = Record.Exception(
                    delegate { coordinator.Initialize(TestRoot()); });
                Assert.Null(error);
                Assert.False(coordinator.Initialize(TestRoot()));
                for (int tick = 0; tick < 15; tick++)
                    coordinator.PollNativeRuntimeOnce();
                AudioCoordinatorSnapshotV2 snapshot = coordinator.Snapshot;
                Assert.Equal(
                    AudioCoordinatorStatusV2.Unavailable,
                    snapshot.Status);
                Assert.Equal(1UL, snapshot.AudioReadyGeneration);
                Assert.Equal(
                    AudioNativeV2.ResultDeviceUnavailable,
                    snapshot.FailureCategory);
                Assert.Equal(5, native.InitializeCount);
                Assert.False(snapshot.IsReady);
            }
        }

        [Fact]
        public void Rebuild_AbiCapabilityFailureStopsBeforeDeviceAndPreload()
        {
            var events = new List<string>();
            var native = new FakeAudioNativeV2(events);
            native.CapabilitySucceeds = false;
            bool preloadCalled = false;
            using (var coordinator = new AudioCoordinator(
                native,
                delegate(string root, CancellationToken token)
                {
                    preloadCalled = true;
                    return Catalog(root, "shot.wav");
                },
                NoopCatalogHook))
            {
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.Equal(new[] { "capability" }, events.ToArray());
                Assert.False(preloadCalled);
                Assert.Equal(0, native.InitializeCount);
                Assert.Equal(
                    AudioNativeV2.ResultAbiMismatch,
                    coordinator.Snapshot.FailureCategory);
                Assert.Equal(1UL,
                    coordinator.Snapshot.AudioReadyGeneration);
            }
        }

        [Fact]
        public void StaleTuple_PerformsZeroNativePlaybackSideEffects()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 current = coordinator.Snapshot;
                var responseReady = new ManualResetEventSlim(false);
                AudioBgmResultV2 response = null;
                var stale = new AudioBgmRequestV2(
                    "stale.request",
                    current.AudioSessionId,
                    current.AudioReadyGeneration + 1UL,
                    AudioWireV2.BgmPlay,
                    "sounds/music/test.mp3",
                    true,
                    0.5d,
                    0d,
                    null);

                int beforeBgm = native.SubmitBgmCount;
                int beforeSfx = native.SubmitSfxCount;
                coordinator.DispatchBgm(stale, delegate(AudioBgmResultV2 value)
                {
                    response = value;
                    responseReady.Set();
                });
                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    Guid.NewGuid().ToString("D"),
                    current.AudioReadyGeneration,
                    1UL,
                    new[] { "shot.wav", "shell.wav", "voice.wav" }));

                Assert.True(responseReady.Wait(TimeSpan.FromSeconds(2)));
                coordinator.RefreshObservation();
                Assert.NotNull(response);
                Assert.Equal("stale_generation", response.Category);
                Assert.Equal(current.AudioSessionId, response.AudioSessionId);
                Assert.Equal(
                    current.AudioReadyGeneration,
                    response.AudioReadyGeneration);
                Assert.Equal(beforeBgm, native.SubmitBgmCount);
                Assert.Equal(beforeSfx, native.SubmitSfxCount);
                Assert.Equal(3UL, coordinator.Snapshot.StaleGenerationDrops);
            }
        }

        [Fact]
        public void SfxMixedNativeOutcomes_AggregatePerItemFromCounterDeltas()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 tuple = coordinator.Snapshot;

                native.QueueSfxOutcome(0uL, 0uL, 0uL, 1uL, 1uL, 1uL, 1uL);
                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    tuple.AudioSessionId,
                    tuple.AudioReadyGeneration,
                    1uL,
                    new[] { "played", "throttled", "unknown", "failed" }));
                coordinator.RefreshObservation();

                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                Assert.Equal(1, native.SubmitSfxCount);
                Assert.Equal(1uL, first.PlayedCount);
                Assert.Equal(1uL, first.ThrottledCount);
                Assert.Equal(1uL, first.UnknownIdCount);
                Assert.Equal(1uL, first.StartFailureCount);

                native.QueueSfxOutcome(0uL, 0uL, 0uL, 0uL, 1uL, 0uL, 2uL);
                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    tuple.AudioSessionId,
                    tuple.AudioReadyGeneration,
                    2uL,
                    new[] { "played-2", "played-3", "throttled-2" }));
                coordinator.RefreshObservation();

                AudioCoordinatorSnapshotV2 second = coordinator.Snapshot;
                Assert.Equal(2, native.SubmitSfxCount);
                Assert.Equal(3uL, second.PlayedCount);
                Assert.Equal(2uL, second.ThrottledCount);
                Assert.Equal(1uL, second.UnknownIdCount);
                Assert.Equal(1uL, second.StartFailureCount);
                Assert.Equal(0uL, second.PreReadyDrops);
                Assert.Equal(0uL, second.RecoveryDrops);
                Assert.Equal(0uL, second.StaleGenerationDrops);
            }
        }

        [Fact]
        public void CounterOverflow_RotatesSessionAndFailsClosedBeforePlayback()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 before = coordinator.Snapshot;
                typeof(AudioCoordinator).GetField(
                    "_unknownIdCount",
                    BindingFlags.Instance | BindingFlags.NonPublic)
                    .SetValue(coordinator, ulong.MaxValue);

                Assert.Equal(-1, coordinator.LegacySfxPlay(-1, 1f));
                AudioCoordinatorSnapshotV2 after = coordinator.Snapshot;
                Assert.NotEqual(before.AudioSessionId, after.AudioSessionId);
                Assert.Equal(0UL, after.AudioReadyGeneration);
                Assert.Equal(0UL, after.DeviceGeneration);
                Assert.Equal(
                    AudioCoordinatorStatusV2.Unavailable,
                    after.Status);
                Assert.Equal(0UL, after.UnknownIdCount);
                Assert.Equal(0, native.SubmitSfxCount);
                Assert.Equal(1, native.ShutdownCount);
            }
        }

        [Fact]
        public async Task OwnerQueue_SerializesConcurrentNativeMutations()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.MutationDelayMilliseconds = 4;
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                Task[] workers = Enumerable.Range(0, 24)
                    .Select(delegate(int index)
                    {
                        return Task.Run(delegate
                        {
                            coordinator.LegacySetGain(
                                AudioNativeV2.OperationSetMasterGain,
                                0.5f);
                        });
                    })
                    .ToArray();
                await Task.WhenAll(workers).WaitAsync(TimeSpan.FromSeconds(10));
                Assert.Equal(1, native.MaxConcurrentMutations);
                Assert.Single(native.MutationThreadIds);
                Assert.Equal(24, native.SetGainCount);
            }
        }

        [Fact]
        public async Task Shutdown_CancelsInflightHookJoinsAndIsIdempotent()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var entered = new ManualResetEventSlim(false);
            var coordinator = new AudioCoordinator(
                native,
                delegate(string root, CancellationToken token)
                {
                    entered.Set();
                    token.WaitHandle.WaitOne();
                    token.ThrowIfCancellationRequested();
                    return Catalog(root, "never.wav");
                },
                NoopCatalogHook);
            try
            {
                Task<bool> initializing = Task.Run(
                    delegate { return coordinator.Initialize(TestRoot()); });
                Assert.True(entered.Wait(TimeSpan.FromSeconds(2)));
                coordinator.Shutdown();
                Assert.False(await initializing.WaitAsync(
                    TimeSpan.FromSeconds(2)));
                coordinator.Shutdown();
                Assert.Equal(1, native.ShutdownCount);
                Assert.Equal(
                    AudioCoordinatorStatusV2.Shutdown,
                    coordinator.Snapshot.Status);
                Assert.False(coordinator.Initialize(TestRoot()));
            }
            finally
            {
                coordinator.Shutdown();
            }
        }

        [Fact]
        public async Task Shutdown_UsesConcurrentNativeCancellationFenceForBlockedCall()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var coordinator = Coordinator(native, false);
            try
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 tuple = coordinator.Snapshot;
                native.BlockSubmitBgmUntilShutdown = true;
                coordinator.DispatchBgm(Request(
                    tuple,
                    "shutdown.blocked",
                    "sounds/music/blocked.mp3"),
                    delegate { });
                Assert.True(native.BgmSubmitted.Wait(TimeSpan.FromSeconds(2)));

                Task shutdown = Task.Run(delegate { coordinator.Shutdown(); });
                await shutdown.WaitAsync(TimeSpan.FromSeconds(2));

                Assert.Equal(1, native.ShutdownCount);
                Assert.Equal(
                    AudioCoordinatorStatusV2.Shutdown,
                    coordinator.Snapshot.Status);
                coordinator.Shutdown();
                Assert.Equal(1, native.ShutdownCount);
            }
            finally
            {
                coordinator.Shutdown();
            }
        }

        [Fact]
        public void Recovery_ReplaysLatestBgmOnlyAndNeverReplaysSfx()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                var recoverySnapshots =
                    new List<AudioCoordinatorSnapshotV2>();
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    if (snapshot.AudioReadyGeneration >
                        first.AudioReadyGeneration)
                    {
                        recoverySnapshots.Add(snapshot);
                    }
                };
                var bgmDone = new ManualResetEventSlim(false);
                coordinator.DispatchBgm(new AudioBgmRequestV2(
                    "recovery.bgm",
                    first.AudioSessionId,
                    first.AudioReadyGeneration,
                    AudioWireV2.BgmPlay,
                    "sounds/music/latest.mp3",
                    true,
                    0.75d,
                    0d,
                    null),
                    delegate(AudioBgmResultV2 result) { bgmDone.Set(); });
                Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));

                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    first.AudioSessionId,
                    first.AudioReadyGeneration,
                    9UL,
                    new[] { "shot.wav" }));
                Assert.True(native.SfxSubmitted.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal(1, native.SubmitBgmCount);
                Assert.Equal(1, native.SubmitSfxCount);

                Assert.True(coordinator.RecoverDevice());
                AudioCoordinatorSnapshotV2 recovered = coordinator.Snapshot;
                Assert.Equal(AudioCoordinatorStatusV2.Ready, recovered.Status);
                Assert.Equal(first.AudioSessionId, recovered.AudioSessionId);
                Assert.Equal(
                    first.AudioReadyGeneration + 1UL,
                    recovered.AudioReadyGeneration);
                Assert.Equal(first.DeviceGeneration + 1UL,
                    recovered.DeviceGeneration);
                AudioCoordinatorSnapshotV2 recovering =
                    recoverySnapshots.First(snapshot =>
                        snapshot.Status ==
                            AudioCoordinatorStatusV2.Recovering);
                Assert.Equal(first.AudioReadyGeneration + 1UL,
                    recovering.AudioReadyGeneration);
                Assert.Equal(first.DeviceGeneration,
                    recovering.DeviceGeneration);
                Assert.Contains(recoverySnapshots, snapshot =>
                    snapshot.Status == AudioCoordinatorStatusV2.Ready &&
                    snapshot.AudioReadyGeneration ==
                        first.AudioReadyGeneration + 1UL &&
                    snapshot.DeviceGeneration ==
                        first.DeviceGeneration + 1UL);
                Assert.Equal(3, native.SubmitBgmCount);
                Assert.Equal(1, native.SubmitSfxCount);
                AudioNativeBgmCommandV2 replayPlay =
                    native.BgmCommands[native.BgmCommands.Length - 2];
                AudioNativeBgmCommandV2 replaySeek =
                    native.BgmCommands.Last();
                Assert.Equal(AudioNativeV2.OperationBgmPlay,
                    replayPlay.Operation);
                Assert.Equal(0f, replayPlay.Volume);
                Assert.Equal(
                    "latest.mp3",
                    Path.GetFileName(replayPlay.NormalizedPath));
                Assert.Equal(
                    recovered.AudioReadyGeneration,
                    replayPlay.AudioReadyGeneration);
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    replaySeek.Operation);
                Assert.Equal(3.5f, replaySeek.SeekSeconds);
                Assert.Equal(0.75f, native.SetGainValues.Last());
                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmSeek,
                    AudioNativeV2.OperationBgmSetGain
                }, native.NativeBgmOperations.Skip(1).ToArray());
            }
        }

        [Fact]
        public async Task RuntimePoll_RecoversNativeNotificationAndReplaysCursorOnce()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.RecoveryCursorSeconds = 3.5f;
            using (var coordinator = Coordinator(native, false))
            using (var bgmDone = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                var lifecycle = new List<AudioCoordinatorStatusV2>();
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    lock (lifecycle) lifecycle.Add(snapshot.Status);
                };
                coordinator.DispatchBgm(Request(
                    first,
                    "runtime.recovery",
                    "sounds/music/recover.mp3"),
                    delegate { bgmDone.Set(); });
                Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal(1, native.SubmitBgmCount);

                for (int index = 0; index < 16; index++)
                    native.RequestDeviceRecovery();
                Task<bool>[] polls = Enumerable.Range(0, 16)
                    .Select(delegate(int index)
                    {
                        return Task.Run(
                            delegate
                            {
                                return coordinator.PollNativeRuntimeOnce();
                            });
                    })
                    .ToArray();
                bool[] results = await Task.WhenAll(polls).WaitAsync(
                    TimeSpan.FromSeconds(10));
                Assert.Equal(1, results.Count(rebuilt => rebuilt));

                AudioCoordinatorSnapshotV2 recovered = coordinator.Snapshot;
                Assert.Equal(AudioCoordinatorStatusV2.Ready, recovered.Status);
                Assert.Equal(first.AudioSessionId, recovered.AudioSessionId);
                Assert.Equal(
                    first.AudioReadyGeneration + 1uL,
                    recovered.AudioReadyGeneration);
                Assert.Equal(
                    first.DeviceGeneration + 1uL,
                    recovered.DeviceGeneration);
                Assert.Equal(2, native.InitializeCount);
                Assert.Equal(3, native.SubmitBgmCount);
                AudioNativeBgmCommandV2 replay =
                    native.BgmCommands[native.BgmCommands.Length - 2];
                AudioNativeBgmCommandV2 replaySeek =
                    native.BgmCommands.Last();
                Assert.Equal(AudioNativeV2.OperationBgmPlay,
                    replay.Operation);
                Assert.Equal(0f, replay.Volume);
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    replaySeek.Operation);
                Assert.Equal(3.5f, replaySeek.SeekSeconds);
                Assert.Equal(
                    recovered.AudioReadyGeneration,
                    replay.AudioReadyGeneration);
                Assert.Equal(0.5f, native.SetGainValues.Last());
                lock (lifecycle)
                {
                    Assert.Contains(
                        AudioCoordinatorStatusV2.Recovering,
                        lifecycle);
                    Assert.Equal(
                        AudioCoordinatorStatusV2.Ready,
                        lifecycle.Last());
                }

                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(2, native.InitializeCount);
                Assert.Equal(3, native.SubmitBgmCount);
                Assert.Same(recovered, coordinator.Snapshot);
            }
        }

        [Fact]
        public void Recovery_RetriesTransientDeviceStartAndReplaysBgmOnce()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.RecoveryCursorSeconds = 6.25f;
            using (var coordinator = Coordinator(native, false))
            using (var bgmDone = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                coordinator.DispatchBgm(Request(
                    first,
                    "recovery.retry.bgm",
                    "sounds/music/retry.mp3"),
                    delegate { bgmDone.Set(); });
                Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));
                coordinator.DispatchSfx(new AudioSfxBatchV2(
                    first.AudioSessionId,
                    first.AudioReadyGeneration,
                    1UL,
                    new[] { "shot.wav" }));
                Assert.True(native.SfxSubmitted.Wait(TimeSpan.FromSeconds(2)));

                native.InitializeFailuresRemaining = 2;
                Assert.False(coordinator.RecoverDevice());
                Assert.Equal(AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);
                Assert.Equal("audio.device_unavailable",
                    coordinator.Snapshot.MessageKey);
                Assert.Equal(2, native.InitializeCount);

                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(3, native.InitializeCount);
                Assert.Equal(AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);
                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(3, native.InitializeCount);
                Assert.True(coordinator.PollNativeRuntimeOnce());

                AudioCoordinatorSnapshotV2 ready = coordinator.Snapshot;
                Assert.True(ready.IsReady);
                Assert.Equal(first.AudioReadyGeneration + 1UL,
                    ready.AudioReadyGeneration);
                Assert.Equal(4, native.InitializeCount);
                Assert.Equal(3, native.SubmitBgmCount);
                Assert.Equal(1, native.SubmitSfxCount);
                Assert.Equal(AudioNativeV2.OperationBgmPlay,
                    native.BgmCommands[native.BgmCommands.Length - 2].Operation);
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    native.BgmCommands.Last().Operation);
                Assert.Equal(6.25f, native.BgmCommands.Last().SeekSeconds);
                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(4, native.InitializeCount);
                Assert.Equal(3, native.SubmitBgmCount);
            }
        }

        [Fact]
        public void BgmDeviceLost_EntersBoundedRecoveryAndReplaysPriorIntent()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.RecoveryCursorSeconds = 2.75f;
            using (var coordinator = Coordinator(native, false))
            using (var firstDone = new ManualResetEventSlim(false))
            using (var failedDone = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                coordinator.DispatchBgm(Request(
                    first,
                    "bgm.device_lost.prior",
                    "sounds/music/prior.mp3"),
                    delegate { firstDone.Set(); });
                Assert.True(firstDone.Wait(TimeSpan.FromSeconds(2)));

                native.SubmitBgmDeviceLostRemaining = 1;
                AudioBgmResultV2 failedResult = null;
                coordinator.DispatchBgm(Request(
                    first,
                    "bgm.device_lost.new",
                    "sounds/music/new.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        failedResult = result;
                        failedDone.Set();
                    });
                Assert.True(failedDone.Wait(TimeSpan.FromSeconds(2)));

                Assert.NotNull(failedResult);
                Assert.Equal("device_lost", failedResult.Category);
                AudioCoordinatorSnapshotV2 recovered = coordinator.Snapshot;
                Assert.True(recovered.IsReady);
                Assert.Equal(first.AudioReadyGeneration + 1UL,
                    recovered.AudioReadyGeneration);
                Assert.Equal(2, native.InitializeCount);
                Assert.Equal(4, native.SubmitBgmCount);
                AudioNativeBgmCommandV2 replay =
                    native.BgmCommands[native.BgmCommands.Length - 2];
                Assert.Equal(AudioNativeV2.OperationBgmPlay,
                    replay.Operation);
                Assert.Equal("prior.mp3",
                    Path.GetFileName(replay.NormalizedPath));
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    native.BgmCommands.Last().Operation);
                Assert.Equal(2.75f,
                    native.BgmCommands.Last().SeekSeconds);
                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(2, native.InitializeCount);
            }
        }

        [Fact]
        public void Recovery_DeviceLostDuringReplayKeepsConsumedAttemptBudget()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var lifecycle = new List<AudioCoordinatorStatusV2>();
            using (var coordinator = Coordinator(native, false))
            using (var bgmDone = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                coordinator.DispatchBgm(Request(
                    first,
                    "recovery.replay.device_lost",
                    "sounds/music/replay-device-lost.mp3"),
                    delegate { bgmDone.Set(); });
                Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    lock (lifecycle) lifecycle.Add(snapshot.Status);
                };

                native.SubmitBgmDeviceLostRemaining = 5;
                Assert.False(coordinator.RecoverDevice());
                Assert.Equal(AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);
                Assert.Equal(2, native.InitializeCount);

                for (int tick = 0; tick < 15; tick++)
                {
                    native.RequestDeviceRecovery();
                    Assert.False(coordinator.RecoverDevice());
                    coordinator.PollNativeRuntimeOnce();
                }

                Assert.Equal(AudioCoordinatorStatusV2.Unavailable,
                    coordinator.Snapshot.Status);
                Assert.Equal(AudioNativeV2.ResultDeviceLost,
                    coordinator.Snapshot.FailureCategory);
                Assert.Equal(6, native.InitializeCount);
                Assert.Equal(6, native.SubmitBgmCount);
                lock (lifecycle)
                    Assert.DoesNotContain(
                        AudioCoordinatorStatusV2.Ready,
                        lifecycle);
                for (int tick = 0; tick < 20; tick++)
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(6, native.InitializeCount);
            }
        }

        [Fact]
        public void Recovery_NotReadyDuringReplayKeepsConsumedAttemptBudget()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var lifecycle = new List<AudioCoordinatorStatusV2>();
            using (var coordinator = Coordinator(native, false))
            using (var bgmDone = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                coordinator.DispatchBgm(Request(
                    first,
                    "recovery.replay.not_ready",
                    "sounds/music/replay-not-ready.mp3"),
                    delegate { bgmDone.Set(); });
                Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));
                coordinator.SnapshotChanged += delegate(
                    AudioCoordinatorSnapshotV2 snapshot)
                {
                    lock (lifecycle) lifecycle.Add(snapshot.Status);
                };

                native.SubmitBgmNotReadyRemaining = 5;
                Assert.False(coordinator.RecoverDevice());
                Assert.Equal(AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);
                for (int tick = 0; tick < 15; tick++)
                    coordinator.PollNativeRuntimeOnce();

                Assert.Equal(AudioCoordinatorStatusV2.Unavailable,
                    coordinator.Snapshot.Status);
                Assert.Equal(AudioNativeV2.ResultDeviceLost,
                    coordinator.Snapshot.FailureCategory);
                Assert.Equal(6, native.InitializeCount);
                Assert.Equal(6, native.SubmitBgmCount);
                lock (lifecycle)
                    Assert.DoesNotContain(
                        AudioCoordinatorStatusV2.Ready,
                        lifecycle);
                for (int tick = 0; tick < 20; tick++)
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(6, native.InitializeCount);
            }
        }

        [Fact]
        public void Recovery_ShutdownDuringBackoffCancelsRetry()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var coordinator = Coordinator(native, false);
            try
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                native.InitializeSucceeds = false;
                Assert.False(coordinator.RecoverDevice());
                Assert.Equal(AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);
                Assert.Equal(2, native.InitializeCount);

                coordinator.Shutdown();
                int initializeCount = native.InitializeCount;
                int shutdownCount = native.ShutdownCount;
                native.RequestDeviceRecovery();
                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.False(coordinator.RecoverDevice());
                Assert.Equal(initializeCount, native.InitializeCount);
                Assert.Equal(shutdownCount, native.ShutdownCount);
                Assert.Equal(AudioCoordinatorStatusV2.Shutdown,
                    coordinator.Snapshot.Status);
            }
            finally
            {
                coordinator.Shutdown();
            }
        }

        [Fact]
        public void Recovery_QualificationPendingSuppressesRetriesAndReplaysOnce()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var requests = new List<AudioCatalogQualificationRequestV2>();
            using (var coordinator = Coordinator(native, false))
            using (var qualificationArrived = new AutoResetEvent(false))
            using (var bgmDone = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 request)
                    {
                        lock (requests) requests.Add(request);
                        qualificationArrived.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 initial;
                lock (requests) initial = Assert.Single(requests);
                Assert.True(CompleteQualification(
                    coordinator, initial, true));
                AudioCoordinatorSnapshotV2 ready = coordinator.Snapshot;
                coordinator.DispatchBgm(Request(
                    ready,
                    "qualification.retry.bgm",
                    "sounds/music/qualification-retry.mp3"),
                    delegate { bgmDone.Set(); });
                Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));

                Assert.False(coordinator.RecoverDevice());
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 recovery;
                lock (requests) recovery = requests.Last();
                Assert.Equal("audio.catalog_qualifying",
                    coordinator.Snapshot.MessageKey);
                int initializeCount = native.InitializeCount;
                for (int tick = 0; tick < 20; tick++)
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(initializeCount, native.InitializeCount);
                Assert.Equal(1, native.SubmitBgmCount);

                Assert.True(CompleteQualification(
                    coordinator, recovery, true));
                Assert.True(coordinator.Snapshot.IsReady);
                Assert.Equal(3, native.SubmitBgmCount);
                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(initializeCount, native.InitializeCount);
                Assert.Equal(3, native.SubmitBgmCount);
            }
        }

        [Fact]
        public void Recovery_QualificationCompletionDefersReadyAfterNewNotification()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var requests = new List<AudioCatalogQualificationRequestV2>();
            using (var coordinator = Coordinator(native, false))
            using (var qualificationArrived = new AutoResetEvent(false))
            using (var bgmDone = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 request)
                    {
                        lock (requests) requests.Add(request);
                        qualificationArrived.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 initial;
                lock (requests) initial = Assert.Single(requests);
                Assert.True(CompleteQualification(
                    coordinator, initial, true));
                AudioCoordinatorSnapshotV2 ready = coordinator.Snapshot;
                coordinator.DispatchBgm(Request(
                    ready,
                    "qualification.notification.bgm",
                    "sounds/music/qualification-notification.mp3"),
                    delegate { bgmDone.Set(); });
                Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));

                Assert.False(coordinator.RecoverDevice());
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 recovery;
                lock (requests) recovery = requests.Last();
                native.RequestDeviceRecovery();

                Assert.False(CompleteQualification(
                    coordinator, recovery, true));
                Assert.Equal(AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);
                Assert.Equal("audio.device_lost",
                    coordinator.Snapshot.MessageKey);
                Assert.Equal(1, native.SubmitBgmCount);

                Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 retried;
                lock (requests) retried = requests.Last();
                Assert.NotEqual(recovery.DeviceGeneration,
                    retried.DeviceGeneration);
                Assert.True(CompleteQualification(
                    coordinator, retried, true));
                Assert.True(coordinator.Snapshot.IsReady);
                Assert.Equal(3, native.SubmitBgmCount);
                Assert.Equal(3, native.InitializeCount);
            }
        }

        [Theory]
        [InlineData(
            "throw",
            AudioNativeV2.ResultDeviceUnavailable,
            "audio.runtime_query_failed")]
        [InlineData(
            "invalid",
            AudioNativeV2.ResultAbiMismatch,
            "audio.runtime_snapshot_invalid")]
        [InlineData(
            "tuple",
            AudioNativeV2.ResultStaleGeneration,
            "audio.runtime_tuple_drift")]
        public void Recovery_QualificationRuntimeDefectIsTerminal(
            string failureMode,
            uint expectedCategory,
            string expectedMessageKey)
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var requests = new List<AudioCatalogQualificationRequestV2>();
            using (var coordinator = Coordinator(native, false))
            using (var qualificationArrived = new AutoResetEvent(false))
            {
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 request)
                    {
                        lock (requests) requests.Add(request);
                        qualificationArrived.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 initial;
                lock (requests) initial = Assert.Single(requests);
                Assert.True(CompleteQualification(
                    coordinator, initial, true));

                Assert.False(coordinator.RecoverDevice());
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 recovery;
                lock (requests) recovery = requests.Last();
                int initializeCount = native.InitializeCount;
                native.QueryRuntimeFailureMode = failureMode;

                Assert.False(CompleteQualification(
                    coordinator, recovery, true));
                Assert.Equal(AudioCoordinatorStatusV2.Unavailable,
                    coordinator.Snapshot.Status);
                Assert.Equal(expectedCategory,
                    coordinator.Snapshot.FailureCategory);
                Assert.Equal(expectedMessageKey,
                    coordinator.Snapshot.MessageKey);
                Assert.Equal(initializeCount, native.InitializeCount);
                for (int tick = 0; tick < 20; tick++)
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(initializeCount, native.InitializeCount);
            }
        }

        [Fact]
        public void Recovery_AbiFailureIsTerminalWithoutRetry()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native, false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                native.CapabilitySucceeds = false;
                Assert.False(coordinator.RecoverDevice());
                Assert.Equal(AudioCoordinatorStatusV2.Unavailable,
                    coordinator.Snapshot.Status);
                Assert.Equal(AudioNativeV2.ResultAbiMismatch,
                    coordinator.Snapshot.FailureCategory);
                Assert.Equal(1, native.InitializeCount);
                for (int tick = 0; tick < 20; tick++)
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(1, native.InitializeCount);
            }
        }

        [Fact]
        public void Shutdown_LateRecoverySignalCannotReopenOrReplay()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var coordinator = Coordinator(native, false);
            using (var bgmDone = new ManualResetEventSlim(false))
            {
                try
                {
                    Assert.True(coordinator.Initialize(TestRoot()));
                    AudioCoordinatorSnapshotV2 ready = coordinator.Snapshot;
                    coordinator.DispatchBgm(Request(
                        ready,
                        "shutdown.late_recovery",
                        "sounds/music/shutdown.mp3"),
                        delegate { bgmDone.Set(); });
                    Assert.True(bgmDone.Wait(TimeSpan.FromSeconds(2)));
                    Assert.Equal(1, native.SubmitBgmCount);

                    coordinator.Shutdown();
                    AudioCoordinatorSnapshotV2 shutdown = coordinator.Snapshot;
                    int initializeCount = native.InitializeCount;
                    int submitBgmCount = native.SubmitBgmCount;
                    int shutdownCount = native.ShutdownCount;

                    native.RequestDeviceRecovery();
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                    Assert.False(coordinator.RecoverDevice());

                    Assert.Equal(initializeCount, native.InitializeCount);
                    Assert.Equal(submitBgmCount, native.SubmitBgmCount);
                    Assert.Equal(shutdownCount, native.ShutdownCount);
                    Assert.Equal(1, initializeCount);
                    Assert.Equal(1, submitBgmCount);
                    Assert.Equal(1, shutdownCount);
                    Assert.Same(shutdown, coordinator.Snapshot);
                    Assert.Equal(
                        AudioCoordinatorStatusV2.Shutdown,
                        coordinator.Snapshot.Status);
                }
                finally
                {
                    coordinator.Shutdown();
                }
            }
        }

        [Fact]
        public void Recovery_PausedBgmIsPositionedAndPausedBeforeGainRestore()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            native.RecoveryCursorSeconds = 4.25f;
            using (var coordinator = Coordinator(native, false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                using (var completed = new ManualResetEventSlim(false))
                {
                    coordinator.DispatchBgm(new AudioBgmRequestV2(
                        "paused.recovery.play",
                        first.AudioSessionId,
                        first.AudioReadyGeneration,
                        AudioWireV2.BgmPlay,
                        "sounds/music/paused.mp3",
                        true,
                        0.65d,
                        0d,
                        null),
                        delegate { completed.Set(); });
                    Assert.True(completed.Wait(TimeSpan.FromSeconds(2)));
                }
                using (var completed = new ManualResetEventSlim(false))
                {
                    coordinator.DispatchBgm(new AudioBgmRequestV2(
                        "paused.recovery.pause",
                        first.AudioSessionId,
                        first.AudioReadyGeneration,
                        AudioWireV2.BgmPause,
                        null,
                        null,
                        null,
                        null,
                        null),
                        delegate { completed.Set(); });
                    Assert.True(completed.Wait(TimeSpan.FromSeconds(2)));
                }

                Assert.True(coordinator.RecoverDevice());
                AudioCoordinatorSnapshotV2 recovered = coordinator.Snapshot;
                Assert.True(recovered.IsReady);
                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmPause,
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmSeek,
                    AudioNativeV2.OperationBgmPause,
                    AudioNativeV2.OperationBgmSetGain
                }, native.NativeBgmOperations);
                Assert.Equal(5, native.SubmitBgmCount);
                AudioNativeBgmCommandV2 replayPlay = native.BgmCommands[2];
                Assert.Equal(AudioNativeV2.OperationBgmPlay,
                    replayPlay.Operation);
                Assert.Equal(0f, replayPlay.Volume);
                Assert.Equal("paused.mp3",
                    Path.GetFileName(replayPlay.NormalizedPath));
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    native.BgmCommands[3].Operation);
                Assert.Equal(4.25f, native.BgmCommands[3].SeekSeconds);
                Assert.Equal(AudioNativeV2.OperationBgmPause,
                    native.BgmCommands[4].Operation);
                Assert.Equal(0.65f, native.SetGainValues.Single());
            }
        }

        [Fact]
        public void PositionedPlay_IsMutedUntilSeekAndUsesSetGainExport()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native, false))
            using (var completed = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 tuple = coordinator.Snapshot;
                coordinator.DispatchBgm(new AudioBgmRequestV2(
                    "positioned.play",
                    tuple.AudioSessionId,
                    tuple.AudioReadyGeneration,
                    AudioWireV2.BgmPlay,
                    "sounds/music/positioned.mp3",
                    false,
                    0.6d,
                    0d,
                    2.25d),
                    delegate { completed.Set(); });
                Assert.True(completed.Wait(TimeSpan.FromSeconds(2)));

                Assert.Equal(new[]
                {
                    AudioNativeV2.OperationBgmPlay,
                    AudioNativeV2.OperationBgmSeek,
                    AudioNativeV2.OperationBgmSetGain
                }, native.NativeBgmOperations);
                Assert.Equal(0f, native.BgmCommands[0].Volume);
                Assert.Equal(AudioNativeV2.OperationBgmSeek,
                    native.BgmCommands[1].Operation);
                Assert.Equal(2.25f, native.BgmCommands[1].SeekSeconds);
                Assert.Equal(0.6f, native.SetGainValues.Single());

                completed.Reset();
                coordinator.DispatchBgm(new AudioBgmRequestV2(
                    "positioned.gain",
                    tuple.AudioSessionId,
                    tuple.AudioReadyGeneration,
                    AudioWireV2.BgmSetGain,
                    null,
                    null,
                    0.4d,
                    null,
                    null),
                    delegate { completed.Set(); });
                Assert.True(completed.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal(2, native.SubmitBgmCount);
                Assert.Equal(2, native.SetGainCount);
                Assert.Equal(0.4f, native.SetGainValues.Last());
            }
        }

        [Fact]
        public void RuntimePoll_FailedRecoveryPublishesUnavailable()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native, false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                native.InitializeSucceeds = false;
                native.FailedInitializeAdvancesDeviceGeneration = true;
                native.RequestDeviceRecovery();

                Assert.True(coordinator.PollNativeRuntimeOnce());
                for (int tick = 0; tick < 15; tick++)
                    coordinator.PollNativeRuntimeOnce();

                AudioCoordinatorSnapshotV2 failed = coordinator.Snapshot;
                Assert.Equal(
                    AudioCoordinatorStatusV2.Unavailable,
                    failed.Status);
                Assert.Equal(first.AudioSessionId, failed.AudioSessionId);
                Assert.Equal(
                    first.AudioReadyGeneration + 1uL,
                    failed.AudioReadyGeneration);
                Assert.Equal(
                    first.DeviceGeneration + 5uL,
                    failed.DeviceGeneration);
                Assert.Equal(5, native.ShutdownCount);
                Assert.Equal(6, native.InitializeCount);
                for (int tick = 0; tick < 20; tick++)
                    Assert.False(coordinator.PollNativeRuntimeOnce());
                Assert.Equal(6, native.InitializeCount);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void Recovery_FailureAdoptsOnlyNativeReturnedDeviceEpoch(
            bool failedAttemptAdvancesDeviceGeneration)
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 first = coordinator.Snapshot;
                native.InitializeSucceeds = false;
                native.FailedInitializeAdvancesDeviceGeneration =
                    failedAttemptAdvancesDeviceGeneration;

                Assert.False(coordinator.RecoverDevice());

                for (int tick = 0; tick < 15; tick++)
                    coordinator.PollNativeRuntimeOnce();

                AudioCoordinatorSnapshotV2 failed = coordinator.Snapshot;
                Assert.Equal(AudioCoordinatorStatusV2.Unavailable,
                    failed.Status);
                Assert.Equal(first.AudioSessionId, failed.AudioSessionId);
                Assert.Equal(first.AudioReadyGeneration + 1UL,
                    failed.AudioReadyGeneration);
                Assert.Equal(
                    first.DeviceGeneration +
                        (failedAttemptAdvancesDeviceGeneration ? 5UL : 0UL),
                    failed.DeviceGeneration);
                Assert.Equal(AudioNativeV2.ResultDeviceUnavailable,
                    failed.FailureCategory);
            }
        }

        [Fact]
        public void BootstrapGate_IsLatestWinsBeforeNativeStart()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                AudioCoordinatorSnapshotV2 tuple = coordinator.Snapshot;
                var firstStates = new List<string>();
                var secondStates = new List<string>();
                var started = new ManualResetEventSlim(false);
                coordinator.ArmBootstrapBgmGate();
                coordinator.DispatchBgm(Request(
                    tuple,
                    "bootstrap.first",
                    "sounds/music/first.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        lock (firstStates) firstStates.Add(result.CompletionState);
                    });
                coordinator.DispatchBgm(Request(
                    tuple,
                    "bootstrap.second",
                    "sounds/music/second.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        lock (secondStates)
                        {
                            secondStates.Add(result.CompletionState);
                            if (result.CompletionState == "started") started.Set();
                        }
                    });
                coordinator.ReleaseBootstrapBgmGate();

                Assert.True(started.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal(
                    new[] { "accepted_deferred", "superseded" },
                    firstStates.ToArray());
                Assert.Equal(
                    new[] { "accepted_deferred", "started" },
                    secondStates.ToArray());
                Assert.Single(native.BgmCommands);
                Assert.Equal(
                    "second.mp3",
                    Path.GetFileName(
                        native.BgmCommands[0].NormalizedPath));
            }
        }

        [Fact]
        public void FrontdoorBgm_DuplicateExactAcquireInOneEpochDoesNotReplay()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                const string requestId = "host.frontdoor.duplicate-test";

                Assert.True(coordinator.TryAcquireFrontdoorBgm(
                    requestId,
                    @"sounds\PTXOA馆长\主菜单.mp3",
                    true,
                    0.4f,
                    1f));
                Assert.True(coordinator.TryAcquireFrontdoorBgm(
                    requestId,
                    @"sounds\PTXOA馆长\主菜单.mp3",
                    true,
                    0.4f,
                    1f));

                AudioNativeBgmCommandV2 command =
                    Assert.Single(native.BgmCommands);
                Assert.Equal(requestId, command.RequestId);
                Assert.Equal(0.4f, command.Volume);
                Assert.True(command.Loop);
                Assert.Equal("主菜单.mp3",
                    Path.GetFileName(command.NormalizedPath));
                Assert.Equal(requestId, coordinator.Snapshot.SourceRequestId);
            }
        }

        [Fact]
        public void FrontdoorBgm_RevokeWithDifferentLeaseNeverStopsOwner()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                const string owner = "host.frontdoor.owner-test";
                Assert.True(coordinator.TryAcquireFrontdoorBgm(
                    owner,
                    FrontdoorBgmLease.TrackRelativePath,
                    true,
                    FrontdoorBgmLease.TrackGain,
                    FrontdoorBgmLease.FadeSeconds));

                Assert.True(coordinator.RevokeFrontdoorBgm(
                    "host.frontdoor.other-test",
                    FrontdoorBgmLease.FadeSeconds));

                Assert.Single(native.BgmCommands);
                Assert.Equal(owner, coordinator.Snapshot.SourceRequestId);
            }
        }

        [Fact]
        public void FrontdoorBgm_As2SupersedeMakesLateRevokeANoop()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            using (var coordinator = Coordinator(native))
            using (var as2Started = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.Initialize(TestRoot()));
                const string frontdoor = "host.frontdoor.as2-fence-test";
                Assert.True(coordinator.TryAcquireFrontdoorBgm(
                    frontdoor,
                    FrontdoorBgmLease.TrackRelativePath,
                    true,
                    FrontdoorBgmLease.TrackGain,
                    FrontdoorBgmLease.FadeSeconds));

                AudioCoordinatorSnapshotV2 tuple = coordinator.Snapshot;
                coordinator.DispatchBgm(
                    Request(
                        tuple,
                        "bgm.as2.frontdoor-supersede",
                        "sounds/music/gameplay.mp3"),
                    delegate(AudioBgmResultV2 result)
                    {
                        if (result.CompletionState == "started")
                            as2Started.Set();
                    });
                Assert.True(as2Started.Wait(TimeSpan.FromSeconds(2)));
                Assert.Equal(2, native.BgmCommands.Length);
                Assert.Equal(
                    "bgm.as2.frontdoor-supersede",
                    coordinator.Snapshot.SourceRequestId);

                Assert.True(coordinator.RevokeFrontdoorBgm(
                    frontdoor,
                    FrontdoorBgmLease.FadeSeconds));

                Assert.Equal(2, native.BgmCommands.Length);
                Assert.Equal(
                    "bgm.as2.frontdoor-supersede",
                    coordinator.Snapshot.SourceRequestId);
            }
        }

        [Fact]
        public void FrontdoorBgm_RevokeDuringQualificationClearsRecoveryReplay()
        {
            var native = new FakeAudioNativeV2(new List<string>());
            var requests = new List<AudioCatalogQualificationRequestV2>();
            using (var coordinator = Coordinator(native, false))
            using (var qualificationArrived = new AutoResetEvent(false))
            {
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 request)
                    {
                        lock (requests) requests.Add(request);
                        qualificationArrived.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 initial;
                lock (requests) initial = Assert.Single(requests);
                Assert.True(CompleteQualification(
                    coordinator,
                    initial,
                    true));

                const string requestId =
                    "host.frontdoor.recovery-revoke-test";
                Assert.True(coordinator.TryAcquireFrontdoorBgm(
                    requestId,
                    FrontdoorBgmLease.TrackRelativePath,
                    true,
                    FrontdoorBgmLease.TrackGain,
                    FrontdoorBgmLease.FadeSeconds));
                Assert.Single(native.BgmCommands);

                Assert.False(coordinator.RecoverDevice());
                Assert.True(qualificationArrived.WaitOne(
                    TimeSpan.FromSeconds(2)));
                AudioCatalogQualificationRequestV2 recovery;
                lock (requests) recovery = requests.Last();
                Assert.Equal(
                    AudioCoordinatorStatusV2.Recovering,
                    coordinator.Snapshot.Status);

                Assert.True(coordinator.RevokeFrontdoorBgm(
                    requestId,
                    FrontdoorBgmLease.FadeSeconds));
                Assert.Single(native.BgmCommands);

                Assert.True(CompleteQualification(
                    coordinator,
                    recovery,
                    true));
                Assert.True(coordinator.Snapshot.IsReady);
                Assert.Null(coordinator.Snapshot.SourceRequestId);
                Assert.Single(native.BgmCommands);
            }
        }

        [Fact]
        public void AudioEngine_LegacySurfaceContainsNoRawDllImports()
        {
            MethodInfo[] methods = typeof(AudioEngine).GetMethods(
                BindingFlags.Public |
                BindingFlags.NonPublic |
                BindingFlags.Static);
            Assert.DoesNotContain(methods, delegate(MethodInfo method)
            {
                return method.GetCustomAttribute<DllImportAttribute>() != null;
            });
            Assert.NotNull(typeof(AudioEngine).GetMethod(
                "ma_bridge_bgm_play",
                BindingFlags.Public | BindingFlags.Static));
            Assert.NotNull(typeof(AudioEngine).GetMethod(
                "ma_bridge_sfx_play",
                BindingFlags.Public | BindingFlags.Static));
            Assert.NotNull(typeof(AudioEngine).GetProperty(
                "CommandFacadeV2",
                BindingFlags.NonPublic | BindingFlags.Static));
        }

        [Fact]
        public void NativeInputBuffers_UseLengthButNeverOutputRequiredFields()
        {
            using (var arena = new AudioNativeV2Adapter.NativeBufferArena())
            {
                AudioNativeV2.Utf8Buffer utf8 =
                    arena.CreateInputUtf8("audio-v2");
                Assert.Equal(AudioNativeV2.BufferReadOnly, utf8.flags);
                Assert.Equal(8u, utf8.lengthBytes);
                Assert.Equal(0u, utf8.requiredBytes);

                AudioNativeV2.Utf16Buffer utf16 =
                    arena.CreateInputUtf16("音频-v2");
                Assert.Equal(AudioNativeV2.BufferReadOnly, utf16.flags);
                Assert.Equal(5u, utf16.lengthCodeUnits);
                Assert.Equal(0u, utf16.requiredCodeUnits);
            }
        }

        private static AudioCoordinator Coordinator(
            FakeAudioNativeV2 native,
            bool enableRuntimePolling = true)
        {
            return new AudioCoordinator(
                native,
                delegate(string root, CancellationToken token)
                {
                    return Catalog(root, "shot.wav");
                },
                NoopCatalogHook,
                enableRuntimePolling);
        }

        private static AudioCatalogQualificationRequestV2
            StartPendingQualification(AudioCoordinator coordinator)
        {
            AudioCatalogQualificationRequestV2 request = null;
            using (var hookCalled = new ManualResetEventSlim(false))
            {
                Assert.True(coordinator.ConfigureCatalogQualificationHook(
                    delegate(AudioCatalogQualificationRequestV2 value)
                    {
                        request = value;
                        hookCalled.Set();
                    }));
                Assert.False(coordinator.Initialize(TestRoot()));
                Assert.True(hookCalled.Wait(TimeSpan.FromSeconds(2)));
            }
            AudioCoordinatorSnapshotV2 pending = coordinator.Snapshot;
            Assert.NotNull(request);
            Assert.Equal(
                AudioCoordinatorStatusV2.Initializing,
                pending.Status);
            Assert.Equal("audio.catalog_qualifying", pending.MessageKey);
            Assert.False(pending.IsReady);
            return request;
        }

        private static bool CompleteQualification(
            AudioCoordinator coordinator,
            AudioCatalogQualificationRequestV2 request,
            bool succeeded)
        {
            return coordinator.CompleteCatalogQualification(
                request.AudioSessionId,
                request.AudioReadyGeneration,
                request.DeviceGeneration,
                request.CapabilityDigest,
                succeeded);
        }

        private static void NoopCatalogHook(
            string session,
            ulong ready,
            ulong device,
            AudioPreloadResultV2 catalog,
            CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
        }

        private static AudioPreloadResultV2 Catalog(
            string root,
            string linkageId)
        {
            return new AudioPreloadResultV2(
                new[]
                {
                    new AudioCatalogItemV2(
                        linkageId,
                        Path.Combine(root, "sounds", linkageId))
                },
                0,
                0);
        }

        private static AudioBgmRequestV2 Request(
            AudioCoordinatorSnapshotV2 tuple,
            string requestId,
            string path)
        {
            return new AudioBgmRequestV2(
                requestId,
                tuple.AudioSessionId,
                tuple.AudioReadyGeneration,
                AudioWireV2.BgmPlay,
                path,
                true,
                0.5d,
                0d,
                null);
        }

        private static string TestRoot()
        {
            return Path.GetFullPath(Path.Combine(
                Path.GetTempPath(),
                "cf7-audio-coordinator-tests"));
        }

        private sealed class FakeAudioNativeV2 : IAudioNativeV2
        {
            private readonly IList<string> _events;
            private readonly object _lock = new object();
            private readonly HashSet<int> _mutationThreadIds =
                new HashSet<int>();
            private readonly List<AudioNativeBgmCommandV2> _bgmCommands =
                new List<AudioNativeBgmCommandV2>();
            private readonly List<uint> _nativeBgmOperations =
                new List<uint>();
            private readonly List<float> _setGainValues =
                new List<float>();
            private int _activeMutations;
            private int _maxConcurrentMutations;
            private int _initializeCount;
            private int _submitBgmCount;
            private int _submitSfxCount;
            private int _probeRuntimeCount;
            private int _setGainCount;
            private int _shutdownCount;
            private readonly Queue<ulong[]> _sfxOutcomeDeltas =
                new Queue<ulong[]>();
            private ulong _nativePreReadyDrops;
            private ulong _nativeRecoveryDrops;
            private ulong _nativeStaleGenerationDrops;
            private ulong _nativeUnknownIdCount;
            private ulong _nativeThrottledCount;
            private ulong _nativeStartFailureCount;
            private ulong _nativePlayedCount;
            private string _runtimeSessionId;
            private ulong _runtimeReadyGeneration;
            private ulong _runtimeDeviceGeneration;
            private uint _runtimeStatus = AudioNativeV2.AudioShutdown;

            internal FakeAudioNativeV2(IList<string> events)
            {
                _events = events;
            }

            internal bool InitializeSucceeds { get; set; } = true;
            internal int InitializeFailuresRemaining { get; set; }
            internal int SubmitBgmDeviceLostRemaining { get; set; }
            internal int SubmitBgmNotReadyRemaining { get; set; }
            internal string QueryRuntimeFailureMode { get; set; }
            internal bool FailedInitializeAdvancesDeviceGeneration
                { get; set; }
            internal bool CapabilitySucceeds { get; set; } = true;
            internal int MutationDelayMilliseconds { get; set; }
            internal bool BlockSubmitBgmUntilShutdown { get; set; }
            internal float RecoveryCursorSeconds { get; set; } = 3.5f;
            internal ManualResetEventSlim SfxSubmitted { get; } =
                new ManualResetEventSlim(false);
            internal ManualResetEventSlim BgmSubmitted { get; } =
                new ManualResetEventSlim(false);
            private ManualResetEventSlim BgmShutdownRelease { get; } =
                new ManualResetEventSlim(false);

            internal void RequestDeviceRecovery()
            {
                lock (_lock)
                {
                    _runtimeStatus = AudioNativeV2.AudioRecovering;
                }
            }

            internal void QueueSfxOutcome(
                ulong preReadyDrops,
                ulong recoveryDrops,
                ulong staleGenerationDrops,
                ulong unknownIdCount,
                ulong throttledCount,
                ulong startFailureCount,
                ulong playedCount)
            {
                lock (_lock)
                {
                    _sfxOutcomeDeltas.Enqueue(new[]
                    {
                        preReadyDrops,
                        recoveryDrops,
                        staleGenerationDrops,
                        unknownIdCount,
                        throttledCount,
                        startFailureCount,
                        playedCount
                    });
                }
            }

            internal int MaxConcurrentMutations
            {
                get { return Volatile.Read(ref _maxConcurrentMutations); }
            }

            internal int SubmitBgmCount
            {
                get { return Volatile.Read(ref _submitBgmCount); }
            }

            internal int InitializeCount
            {
                get { return Volatile.Read(ref _initializeCount); }
            }

            internal int SubmitSfxCount
            {
                get { return Volatile.Read(ref _submitSfxCount); }
            }

            internal int ProbeRuntimeCount
            {
                get { return Volatile.Read(ref _probeRuntimeCount); }
            }

            internal int SetGainCount
            {
                get { return Volatile.Read(ref _setGainCount); }
            }

            internal int ShutdownCount
            {
                get { return Volatile.Read(ref _shutdownCount); }
            }

            internal int[] MutationThreadIds
            {
                get
                {
                    lock (_lock) return _mutationThreadIds.ToArray();
                }
            }

            internal AudioNativeBgmCommandV2[] BgmCommands
            {
                get
                {
                    lock (_lock) return _bgmCommands.ToArray();
                }
            }

            internal uint[] NativeBgmOperations
            {
                get
                {
                    lock (_lock) return _nativeBgmOperations.ToArray();
                }
            }

            internal float[] SetGainValues
            {
                get
                {
                    lock (_lock) return _setGainValues.ToArray();
                }
            }

            public AudioNativeCapabilityResultV2 QueryCapability()
            {
                return Mutate(delegate
                {
                    AddEvent("capability");
                    AudioNativeCallResultV2 result = CapabilitySucceeds
                        ? Ok(
                            AudioNativeV2.OperationQueryCapability,
                            null,
                            0UL,
                            0UL,
                            AudioNativeV2.CompletionNone)
                        : AudioNativeCallResultV2.Failure(
                            AudioNativeV2.ResultAbiMismatch,
                            AudioNativeV2.OperationQueryCapability,
                            AudioNativeV2.StageValidateAbi,
                            null,
                            0UL,
                            0UL,
                            "audio.abi_mismatch");
                    return new AudioNativeCapabilityResultV2(
                        CapabilitySucceeds,
                        CapabilitySucceeds ? new string('A', 64) : null,
                        result);
                });
            }

            public AudioNativeInitializeResultV2 Initialize(
                string normalizedBasePath,
                string audioSessionId,
                ulong audioReadyGeneration)
            {
                return Mutate(delegate
                {
                    AddEvent("initialize");
                    int count = Interlocked.Increment(ref _initializeCount);
                    ResetNativeSfxCounters();
                    bool initializeSucceeds = InitializeSucceeds;
                    lock (_lock)
                    {
                        if (InitializeFailuresRemaining > 0)
                        {
                            InitializeFailuresRemaining--;
                            initializeSucceeds = false;
                        }
                    }
                    if (!initializeSucceeds)
                    {
                        ulong failedDeviceGeneration =
                            FailedInitializeAdvancesDeviceGeneration
                                ? (ulong)count
                                : 0UL;
                        AudioNativeCallResultV2 failure =
                            AudioNativeCallResultV2.Failure(
                                AudioNativeV2.ResultDeviceUnavailable,
                                AudioNativeV2.OperationInitialize,
                                AudioNativeV2.StageDeviceStart,
                                audioSessionId,
                                audioReadyGeneration,
                                failedDeviceGeneration,
                                "audio.device_unavailable");
                        lock (_lock)
                        {
                            _runtimeSessionId = audioSessionId;
                            _runtimeReadyGeneration = audioReadyGeneration;
                            _runtimeDeviceGeneration = failedDeviceGeneration;
                            _runtimeStatus = AudioNativeV2.AudioFailedNoOutput;
                        }
                        return new AudioNativeInitializeResultV2(
                            false, true, failedDeviceGeneration,
                            AudioNativeV2.BackendNone,
                            0u, 0u, AudioNativeV2.SampleFormatUnknown,
                            failure);
                    }
                    AudioNativeCallResultV2 result = Ok(
                        AudioNativeV2.OperationInitialize,
                        audioSessionId,
                        audioReadyGeneration,
                        (ulong)count,
                        AudioNativeV2.CompletionStarted);
                    lock (_lock)
                    {
                        _runtimeSessionId = audioSessionId;
                        _runtimeReadyGeneration = audioReadyGeneration;
                        _runtimeDeviceGeneration = (ulong)count;
                        _runtimeStatus = AudioNativeV2.AudioReady;
                    }
                    return new AudioNativeInitializeResultV2(
                        true,
                        true,
                        (ulong)count,
                        AudioNativeV2.BackendWasapi,
                        48000u,
                        2u,
                        AudioNativeV2.SampleFormatF32,
                        result);
                });
            }

            public AudioNativeRuntimeStateV2 QueryRuntime()
            {
                if (string.Equals(
                        QueryRuntimeFailureMode,
                        "throw",
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "scripted runtime query failure");
                }
                lock (_lock)
                {
                    bool valid = !string.Equals(
                        QueryRuntimeFailureMode,
                        "invalid",
                        StringComparison.Ordinal);
                    bool tupleDrift = string.Equals(
                        QueryRuntimeFailureMode,
                        "tuple",
                        StringComparison.Ordinal);
                    AudioNativeCallResultV2 result = Ok(
                        AudioNativeV2.OperationQueryRuntime,
                        _runtimeSessionId,
                        _runtimeReadyGeneration,
                        _runtimeDeviceGeneration,
                        AudioNativeV2.CompletionNone);
                    return new AudioNativeRuntimeStateV2(
                        valid,
                        _runtimeStatus,
                        tupleDrift
                            ? "00000000-0000-0000-0000-000000000001"
                            : _runtimeSessionId,
                        _runtimeReadyGeneration,
                        _runtimeDeviceGeneration,
                        result);
                }
            }

            public AudioNativeCallResultV2 RebuildSfxCatalog(
                string audioSessionId,
                ulong audioReadyGeneration,
                IList<AudioCatalogItemV2> items)
            {
                return Mutate(delegate
                {
                    AddEvent("native_catalog");
                    return Ok(
                        AudioNativeV2.OperationSfxRebuildCatalog,
                        audioSessionId,
                        audioReadyGeneration,
                        (ulong)_initializeCount,
                        AudioNativeV2.CompletionStarted);
                });
            }

            public AudioNativeCallResultV2 SubmitBgm(
                AudioNativeBgmCommandV2 command)
            {
                return Mutate(delegate
                {
                    Interlocked.Increment(ref _submitBgmCount);
                    lock (_lock)
                    {
                        _bgmCommands.Add(command);
                        _nativeBgmOperations.Add(command.Operation);
                    }
                    BgmSubmitted.Set();
                    if (BlockSubmitBgmUntilShutdown)
                    {
                        BgmShutdownRelease.Wait(TimeSpan.FromSeconds(5));
                    }
                    lock (_lock)
                    {
                        if (SubmitBgmNotReadyRemaining > 0)
                        {
                            SubmitBgmNotReadyRemaining--;
                            _runtimeStatus = AudioNativeV2.AudioRecovering;
                            return AudioNativeCallResultV2.Failure(
                                AudioNativeV2.ResultNotReady,
                                command.Operation,
                                AudioNativeV2.StageAdmission,
                                command.AudioSessionId,
                                command.AudioReadyGeneration,
                                (ulong)_initializeCount,
                                "audio.bgm.not_ready");
                        }
                        if (SubmitBgmDeviceLostRemaining > 0)
                        {
                            SubmitBgmDeviceLostRemaining--;
                            _runtimeStatus = AudioNativeV2.AudioRecovering;
                            return AudioNativeCallResultV2.Failure(
                                AudioNativeV2.ResultDeviceLost,
                                command.Operation,
                                AudioNativeV2.StageNativeStart,
                                command.AudioSessionId,
                                command.AudioReadyGeneration,
                                (ulong)_initializeCount,
                                "audio.device_lost");
                        }
                    }
                    return Ok(
                        command.Operation,
                        command.AudioSessionId,
                        command.AudioReadyGeneration,
                        (ulong)_initializeCount,
                        command.Operation == AudioNativeV2.OperationBgmStop
                            ? AudioNativeV2.CompletionStopped
                            : AudioNativeV2.CompletionStarted);
                });
            }

            public AudioNativeCallResultV2 SubmitSfxBatch(
                string audioSessionId,
                ulong audioReadyGeneration,
                ulong batchSequence,
                IList<string> linkageIds,
                float volume)
            {
                return Mutate(delegate
                {
                    Interlocked.Increment(ref _submitSfxCount);
                    SfxSubmitted.Set();
                    ulong[] delta;
                    AudioNativeSfxCountersV2 counters;
                    lock (_lock)
                    {
                        delta = _sfxOutcomeDeltas.Count == 0
                            ? new[]
                            {
                                0uL, 0uL, 0uL, 0uL, 0uL, 0uL,
                                (ulong)linkageIds.Count
                            }
                            : _sfxOutcomeDeltas.Dequeue();
                        _nativePreReadyDrops += delta[0];
                        _nativeRecoveryDrops += delta[1];
                        _nativeStaleGenerationDrops += delta[2];
                        _nativeUnknownIdCount += delta[3];
                        _nativeThrottledCount += delta[4];
                        _nativeStartFailureCount += delta[5];
                        _nativePlayedCount += delta[6];
                        counters = new AudioNativeSfxCountersV2(
                            audioSessionId,
                            audioReadyGeneration,
                            _nativePreReadyDrops,
                            _nativeRecoveryDrops,
                            _nativeStaleGenerationDrops,
                            _nativeUnknownIdCount,
                            _nativeThrottledCount,
                            _nativeStartFailureCount,
                            _nativePlayedCount);
                    }
                    return Ok(
                        AudioNativeV2.OperationSfxPlayBatch,
                        audioSessionId,
                        audioReadyGeneration,
                        (ulong)_initializeCount,
                        AudioNativeV2.CompletionStarted)
                        .WithSfxCounters(counters);
                });
            }

            public AudioNativeCallResultV2 SetGain(
                string audioSessionId,
                ulong audioReadyGeneration,
                uint operation,
                float gain)
            {
                return Mutate(delegate
                {
                    Interlocked.Increment(ref _setGainCount);
                    lock (_lock)
                    {
                        _nativeBgmOperations.Add(operation);
                        _setGainValues.Add(gain);
                    }
                    return Ok(
                        operation,
                        audioSessionId,
                        audioReadyGeneration,
                        (ulong)_initializeCount,
                        AudioNativeV2.CompletionStarted);
                });
            }

            public AudioNativeObservationV2 QueryBgmObservation(
                string audioSessionId,
                ulong audioReadyGeneration,
                ulong deviceGeneration)
            {
                return Mutate(delegate
                {
                    return new AudioNativeObservationV2(
                        true, 0.25f, 0.5f, 1f, 10f, true, "builtin");
                });
            }

            public AudioNativeObservationV2 QueryBgmRecoveryObservation(
                string audioSessionId,
                ulong audioReadyGeneration,
                ulong deviceGeneration)
            {
                return Mutate(delegate
                {
                    return new AudioNativeObservationV2(
                        true,
                        0f,
                        0f,
                        RecoveryCursorSeconds,
                        10f,
                        false,
                        "builtin");
                });
            }

            public AudioRuntimeProbeResultV2 ProbeRuntimeCompatibility(
                string normalizedPath,
                ulong fileSizeBytes,
                long modifiedTimeUnixMilliseconds,
                string first64kSha256,
                string capabilityDigestSha256,
                string audioSessionId,
                ulong audioReadyGeneration)
            {
                return Mutate(delegate
                {
                    Interlocked.Increment(ref _probeRuntimeCount);
                    return new AudioRuntimeProbeResultV2(
                        true,
                        AudioNativeV2.ProbeCompatibleSignalPresent,
                        1024uL,
                        1024d / 48000d,
                        0.5d,
                        0.25d,
                        1u,
                        Math.Min(
                            fileSizeBytes,
                            AudioNativeV2.RuntimeProbeMaxInputBytes),
                        Ok(
                            AudioNativeV2.OperationRuntimeProbe,
                            audioSessionId,
                            audioReadyGeneration,
                            (ulong)_initializeCount,
                            AudioNativeV2.CompletionStarted));
                });
            }

            public AudioNativeCallResultV2 Shutdown(
                string audioSessionId,
                ulong audioReadyGeneration)
            {
                return Mutate(delegate
                {
                    Interlocked.Increment(ref _shutdownCount);
                    lock (_lock)
                    {
                        _runtimeStatus = AudioNativeV2.AudioShutdown;
                    }
                    BgmShutdownRelease.Set();
                    return Ok(
                        AudioNativeV2.OperationShutdown,
                        audioSessionId,
                        audioReadyGeneration,
                        (ulong)_initializeCount,
                        AudioNativeV2.CompletionStopped);
                });
            }

            private T Mutate<T>(Func<T> action)
            {
                int active = Interlocked.Increment(ref _activeMutations);
                UpdateMaximum(active);
                lock (_lock)
                {
                    _mutationThreadIds.Add(
                        Thread.CurrentThread.ManagedThreadId);
                }
                try
                {
                    if (MutationDelayMilliseconds > 0)
                        Thread.Sleep(MutationDelayMilliseconds);
                    return action();
                }
                finally
                {
                    Interlocked.Decrement(ref _activeMutations);
                }
            }

            private void UpdateMaximum(int candidate)
            {
                int observed;
                do
                {
                    observed = Volatile.Read(ref _maxConcurrentMutations);
                    if (candidate <= observed) return;
                }
                while (Interlocked.CompareExchange(
                    ref _maxConcurrentMutations,
                    candidate,
                    observed) != observed);
            }

            private void ResetNativeSfxCounters()
            {
                lock (_lock)
                {
                    _nativePreReadyDrops = 0uL;
                    _nativeRecoveryDrops = 0uL;
                    _nativeStaleGenerationDrops = 0uL;
                    _nativeUnknownIdCount = 0uL;
                    _nativeThrottledCount = 0uL;
                    _nativeStartFailureCount = 0uL;
                    _nativePlayedCount = 0uL;
                }
            }

            private void AddEvent(string value)
            {
                lock (_events) _events.Add(value);
            }

            private static AudioNativeCallResultV2 Ok(
                uint operation,
                string session,
                ulong ready,
                ulong device,
                uint completion)
            {
                return new AudioNativeCallResultV2(
                    AudioNativeV2.ResultOk,
                    operation,
                    AudioNativeV2.StageNativeStart,
                    0,
                    0,
                    completion,
                    session,
                    ready,
                    device,
                    "audio.ok",
                    "builtin");
            }
        }
    }
}
