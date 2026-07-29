#nullable enable

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo;

public sealed class PlayerInfoRasterPipelineTests
{
    private static readonly PlayerInfoSvgAssetSet AssetSet =
        PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);

    [Fact]
    public async Task LatestWins_OneActiveOneLatestPending_NoStalePublish()
    {
        var rasterizer = new BlockingFirstRasterizer(ignoreFirstCancellation: true);
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        var plans = Enumerable.Range(0, 100)
            .Select(index => CreatePlan(576 + (index * 4)))
            .ToArray();

        Assert.Equal(
            PlayerInfoRasterRequestResult.Queued,
            pipeline.Request(plans[0]));
        Assert.True(rasterizer.FirstStarted.Wait(TimeSpan.FromSeconds(5)));
        for (var index = 1; index < plans.Length; index++)
        {
            Assert.Equal(
                PlayerInfoRasterRequestResult.Queued,
                pipeline.Request(plans[index]));
        }
        rasterizer.ReleaseFirst.Set();
        await WaitForIdle(pipeline);

        PlayerInfoRasterPipelineSnapshot snapshot = pipeline.Snapshot;
        Assert.Equal(100, snapshot.RequestCount);
        Assert.Equal(1, snapshot.PublishCount);
        Assert.Equal(2, rasterizer.CallCount);
        Assert.Equal(1, rasterizer.MaxConcurrent);
        Assert.Equal(1, snapshot.MaxConcurrentWorkers);
        Assert.Equal(1, snapshot.StaleDiscardCount);
        Assert.True(snapshot.PendingReplacementCount >= 99);
        Assert.Equal(16, snapshot.ParseCount);
        Assert.Equal(16, snapshot.RasterCount);
        Assert.Equal(plans[^1].BatchKey, snapshot.CurrentBatchKey);
    }

    [Fact]
    public async Task Cancellation_StopsOldBakeAndPublishesOnlyDesiredKey()
    {
        var rasterizer = new BlockingFirstRasterizer(ignoreFirstCancellation: false);
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        PlayerInfoRasterPlan first = CreatePlan(576);
        PlayerInfoRasterPlan second = CreatePlan(720);

        pipeline.Request(first);
        Assert.True(rasterizer.FirstStarted.Wait(TimeSpan.FromSeconds(5)));
        pipeline.Request(second);
        await WaitForIdle(pipeline);

        PlayerInfoRasterPipelineSnapshot snapshot = pipeline.Snapshot;
        Assert.Equal(1, snapshot.CancelCount);
        Assert.Equal(1, snapshot.PublishCount);
        Assert.Equal(second.BatchKey, snapshot.CurrentBatchKey);
        Assert.Equal(1, snapshot.MaxConcurrentWorkers);
        Assert.Equal(8, snapshot.ParseCount);
        Assert.Equal(8, snapshot.RasterCount);
    }

    [Fact]
    public async Task Fault_RetainsLastGoodAndReportsPartialLayerProgress()
    {
        var rasterizer = new FaultOnSecondRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        PlayerInfoRasterPlan first = CreatePlan(576);
        PlayerInfoRasterPlan second = CreatePlan(720);

        pipeline.Request(first);
        await WaitForIdle(pipeline);
        pipeline.Request(second);
        await WaitForIdle(pipeline);

        PlayerInfoRasterPipelineSnapshot snapshot = pipeline.Snapshot;
        Assert.Equal(1, snapshot.PublishCount);
        Assert.Equal(1, snapshot.FaultCount);
        Assert.Equal(first.BatchKey, snapshot.CurrentBatchKey);
        Assert.Equal(11, snapshot.ParseCount);
        Assert.Equal(10, snapshot.RasterCount);
        Assert.Contains("synthetic fault", snapshot.LastFault);
    }

    [Fact]
    public async Task SameSizeMovedViewport_ReusesBitmapButPublishesCurrentPlacementPlan()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        PlayerInfoRasterPlan original = CreatePlan(576, 0, 0);
        PlayerInfoRasterPlan moved = CreatePlan(576, 311, 227);

        pipeline.Request(original);
        await WaitForIdle(pipeline);
        Assert.Equal(
            PlayerInfoRasterRequestResult.CurrentHit,
            pipeline.Request(moved));

        Rectangle actualStage = Rectangle.Empty;
        Assert.True(pipeline.TryUseCurrent((batch, currentPlan) =>
        {
            Assert.Equal(original.BatchKey, batch.BatchKey);
            actualStage = currentPlan.StagePhysicalBounds;
        }));

        Assert.Equal(moved.StagePhysicalBounds, actualStage);
        Assert.Equal(original.BatchKey, moved.BatchKey);
        Assert.Equal(1, rasterizer.CallCount);
        Assert.Equal(8, pipeline.Snapshot.ParseCount);
        Assert.Equal(8, pipeline.Snapshot.RasterCount);
    }

    [Fact]
    public async Task CacheHit_SwapsWholeBatchWithoutRasterizingAgain()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        PlayerInfoRasterPlan first = CreatePlan(576, 0, 0);
        PlayerInfoRasterPlan second = CreatePlan(720, 0, 0);
        PlayerInfoRasterPlan movedFirst = CreatePlan(576, 41, 73);

        pipeline.Request(first);
        await WaitForIdle(pipeline);
        pipeline.Request(second);
        await WaitForIdle(pipeline);
        Assert.Equal(
            PlayerInfoRasterRequestResult.CacheHit,
            pipeline.Request(movedFirst));

        Assert.Equal(2, rasterizer.CallCount);
        Assert.Equal(1, pipeline.Snapshot.CacheHitCount);
        Assert.Equal(8, pipeline.Snapshot.CacheLayerHitCount);
        Assert.Equal(3, pipeline.Snapshot.PublishCount);
        Assert.Equal(movedFirst.BatchKey, pipeline.Snapshot.CurrentBatchKey);
        Assert.True(pipeline.Snapshot.CacheBytes <= pipeline.MaxCacheBytes);
        Assert.True(pipeline.TryUseCurrent((_, currentPlan) =>
            Assert.Equal(movedFirst.StagePhysicalBounds, currentPlan.StagePhysicalBounds)));
    }

    [Fact]
    public async Task DefaultBudget_EvictsWholeInactiveBatchesAndNeverExceeds16MiB()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);

        for (var index = 0; index < 20; index++)
        {
            pipeline.Request(CreatePlan(576 + (index * 72)));
            await WaitForIdle(pipeline);
            Assert.True(pipeline.Snapshot.CacheBytes <= 16L * 1024 * 1024);
        }

        Assert.Equal(20, pipeline.Snapshot.PublishCount);
        Assert.True(pipeline.Snapshot.CacheCount < 20);
        Assert.Contains(rasterizer.Batches, batch => batch.IsDisposed);
        Assert.DoesNotContain(
            rasterizer.Batches.Where(batch => !batch.IsDisposed),
            batch => batch.Layers.Count != 8);
    }

    [Fact]
    public async Task OversizeBatch_IsDisposedAndNeverReplacesLastGood()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(
            rasterizer,
            maxCacheBytes: 1);

        pipeline.Request(CreatePlan(576));
        await WaitForIdle(pipeline);

        Assert.Equal(1, pipeline.Snapshot.FaultCount);
        Assert.Equal(0, pipeline.Snapshot.PublishCount);
        Assert.Null(pipeline.Snapshot.CurrentBatchKey);
        Assert.NotNull(rasterizer.LastBatch);
        Assert.True(rasterizer.LastBatch!.IsDisposed);
        Assert.Equal(1, pipeline.Snapshot.DisposedBatchCount);
        Assert.Equal(8, pipeline.Snapshot.DisposedLayerCount);
    }

    [Fact]
    public async Task Dispose_DiscardsAndDisposesLatePrivateBatch()
    {
        var rasterizer = new BlockingFirstRasterizer(ignoreFirstCancellation: true);
        var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        pipeline.Request(CreatePlan(576));
        Assert.True(rasterizer.FirstStarted.Wait(TimeSpan.FromSeconds(5)));

        pipeline.Dispose();
        rasterizer.ReleaseFirst.Set();
        await WaitForIdle(pipeline);

        Assert.NotNull(rasterizer.LastBatch);
        Assert.True(rasterizer.LastBatch!.IsDisposed);
        Assert.Equal(0, pipeline.Snapshot.PublishCount);
        Assert.Equal(1, pipeline.Snapshot.StaleDiscardCount);
        Assert.Equal(2, pipeline.Snapshot.Generation);
        Assert.Equal(1, pipeline.Snapshot.DisposedBatchCount);
        Assert.Equal(8, pipeline.Snapshot.DisposedLayerCount);
        Assert.Throws<ObjectDisposedException>(
            () => pipeline.Request(CreatePlan(720)));
    }

    [Fact]
    public async Task Steady3000Requests_DoNotParseRasterOrRepublish()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        PlayerInfoRasterPlan plan = CreatePlan(1080);
        pipeline.Request(plan);
        await WaitForIdle(pipeline);
        PlayerInfoRasterPipelineSnapshot before = pipeline.Snapshot;

        for (var tick = 0; tick < 3000; tick++)
        {
            Assert.Equal(
                PlayerInfoRasterRequestResult.CurrentHit,
                pipeline.Request(plan));
        }
        PlayerInfoRasterPipelineSnapshot after = pipeline.Snapshot;

        Assert.Equal(3000, after.RequestCount - before.RequestCount);
        Assert.Equal(before.ParseCount, after.ParseCount);
        Assert.Equal(before.RasterCount, after.RasterCount);
        Assert.Equal(before.PublishCount, after.PublishCount);
        Assert.Equal(
            3000 * PlayerInfoSvgAssetCatalog.ExpectedAssetCount,
            after.CurrentLayerHitCount - before.CurrentLayerHitCount);
        Assert.Equal(1, after.MaxConcurrentWorkers);
    }

    [Fact]
    public async Task Dispose_ReleasesCurrentAndInactiveBatchesExactlyOnce()
    {
        var rasterizer = new ImmediateRasterizer();
        var pipeline = new PlayerInfoRasterPipeline(rasterizer);

        pipeline.Request(CreatePlan(576));
        await WaitForIdle(pipeline);
        pipeline.Request(CreatePlan(720));
        await WaitForIdle(pipeline);
        PlayerInfoRasterPipelineSnapshot before = pipeline.Snapshot;

        Assert.Equal(2, before.CacheCount);
        Assert.Equal(0, before.DisposedBatchCount);
        pipeline.Dispose();
        pipeline.Dispose();
        PlayerInfoRasterPipelineSnapshot after = pipeline.Snapshot;

        Assert.Equal(before.Generation + 1, after.Generation);
        Assert.Equal(2, after.DisposedBatchCount);
        Assert.Equal(16, after.DisposedLayerCount);
        Assert.Equal(0, after.CacheCount);
        Assert.Equal(0, after.CacheBytes);
        Assert.All(rasterizer.Batches, batch => Assert.True(batch.IsDisposed));
    }

    [Fact]
    public async Task TryUseCurrent_ReentrantMutationFailsBeforeBorrowedBatchCanBeDisposed()
    {
        var rasterizer = new ImmediateRasterizer();
        var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        PlayerInfoRasterPlan plan = CreatePlan(576);
        pipeline.Request(plan);
        await WaitForIdle(pipeline);

        PlayerInfoRasterBatch? borrowed = null;
        Assert.True(pipeline.TryUseCurrent((batch, _) =>
        {
            borrowed = batch;
            Assert.False(batch.IsDisposed);
            Assert.Throws<InvalidOperationException>(() =>
                pipeline.Request(CreatePlan(720)));
            Assert.Throws<InvalidOperationException>(() =>
                pipeline.Dispose());
            Assert.Equal(plan.BatchKey, pipeline.Snapshot.CurrentBatchKey);
            Assert.False(batch.IsDisposed);
        }));

        Assert.NotNull(borrowed);
        Assert.False(borrowed!.IsDisposed);
        pipeline.Dispose();
        Assert.True(borrowed.IsDisposed);
    }

    [Fact]
    public async Task BlockingObserver_DoesNotBlockPipelineStateOrIdle()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        using var observerStarted = new ManualResetEventSlim(false);
        using var releaseObserver = new ManualResetEventSlim(false);
        using var observerExited = new ManualResetEventSlim(false);
        PlayerInfoRasterPlan plan = CreatePlan(576);

        pipeline.BatchPublished += (_, _) =>
        {
            observerStarted.Set();
            try
            {
                if (!releaseObserver.Wait(TimeSpan.FromSeconds(5)))
                {
                    throw new TimeoutException("blocking observer was not released");
                }
            }
            finally
            {
                observerExited.Set();
            }
        };

        Assert.Equal(
            PlayerInfoRasterRequestResult.Queued,
            pipeline.Request(plan));
        Assert.True(observerStarted.Wait(TimeSpan.FromSeconds(5)));

        Task<PlayerInfoRasterPipelineSnapshot> snapshotTask =
            Task.Run(() => pipeline.Snapshot);
        Task<PlayerInfoRasterRequestResult> requestTask =
            Task.Run(() => pipeline.Request(plan));
        Task idleTask = Task.Run(() => pipeline.WaitForIdleAsync());
        try
        {
            await Task.WhenAll(snapshotTask, requestTask, idleTask)
                .WaitAsync(TimeSpan.FromSeconds(3));
            PlayerInfoRasterPipelineSnapshot snapshot = await snapshotTask;
            PlayerInfoRasterRequestResult requestResult = await requestTask;
            Assert.Equal(plan.BatchKey, snapshot.CurrentBatchKey);
            Assert.Equal(0, snapshot.ActiveWorkers);
            Assert.Equal(
                PlayerInfoRasterRequestResult.CurrentHit,
                requestResult);
        }
        finally
        {
            releaseObserver.Set();
        }

        Assert.True(observerExited.Wait(TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public async Task Dispose_WaitsForActiveObserverAndDropsQueuedNotification()
    {
        var rasterizer = new ImmediateRasterizer();
        var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        using var firstObserverStarted = new ManualResetEventSlim(false);
        using var releaseFirstObserver = new ManualResetEventSlim(false);
        var observerCalls = 0;
        pipeline.BatchPublished += (_, _) =>
        {
            int call = Interlocked.Increment(ref observerCalls);
            if (call != 1)
            {
                return;
            }
            firstObserverStarted.Set();
            Assert.True(releaseFirstObserver.Wait(TimeSpan.FromSeconds(5)));
        };

        pipeline.Request(CreatePlan(576));
        Assert.True(firstObserverStarted.Wait(TimeSpan.FromSeconds(5)));
        pipeline.Request(CreatePlan(720));
        await WaitForIdle(pipeline);

        using var disposeStarted = new ManualResetEventSlim(false);
        Task disposeTask = Task.Run(() =>
        {
            disposeStarted.Set();
            pipeline.Dispose();
        });
        Assert.True(disposeStarted.Wait(TimeSpan.FromSeconds(5)));
        Assert.True(
            SpinWait.SpinUntil(
                () => pipeline.Snapshot.DesiredBatchKey is null,
                TimeSpan.FromSeconds(5)),
            "Dispose did not enter its active-observer drain state.");
        Assert.False(disposeTask.IsCompleted);
        releaseFirstObserver.Set();
        await disposeTask.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal(1, Volatile.Read(ref observerCalls));
        Assert.Throws<ObjectDisposedException>(() =>
            pipeline.Request(CreatePlan(1080)));
    }

    [Fact]
    public async Task Observer_CanDisposeWithoutDeadlockAndStopsLaterHandlers()
    {
        var rasterizer = new ImmediateRasterizer();
        var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        var laterHandlerCalls = 0;
        pipeline.BatchPublished += (_, _) => pipeline.Dispose();
        pipeline.BatchPublished += (_, _) =>
            Interlocked.Increment(ref laterHandlerCalls);

        pipeline.Request(CreatePlan(576));
        await WaitForIdle(pipeline);

        Assert.Equal(0, Volatile.Read(ref laterHandlerCalls));
        Assert.Throws<ObjectDisposedException>(() =>
            pipeline.Request(CreatePlan(720)));
    }

    [Fact]
    public async Task Observer_CanReenterSnapshotAndCacheRequestWithoutRecursiveDelivery()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        PlayerInfoRasterPlan first = CreatePlan(576);
        PlayerInfoRasterPlan second = CreatePlan(720);

        pipeline.Request(first);
        await WaitForIdle(pipeline);
        pipeline.Request(second);
        await WaitForIdle(pipeline);

        var observed = new ConcurrentQueue<
            (PlayerInfoRasterBatchPublishedEventArgs Args, string? CurrentKey)>();
        var depth = 0;
        var maxDepth = 0;
        PlayerInfoRasterRequestResult reentrantResult = default;
        pipeline.BatchPublished += (_, args) =>
        {
            int currentDepth = Interlocked.Increment(ref depth);
            UpdateMaximum(ref maxDepth, currentDepth);
            try
            {
                observed.Enqueue((args, pipeline.Snapshot.CurrentBatchKey));
                if (args.Generation == 3)
                {
                    reentrantResult = pipeline.Request(second);
                }
            }
            finally
            {
                Interlocked.Decrement(ref depth);
            }
        };

        PlayerInfoRasterRequestResult outerResult = await Task.Run(
                () => pipeline.Request(first))
            .WaitAsync(TimeSpan.FromSeconds(5));

        var events = observed.ToArray();
        Assert.Equal(PlayerInfoRasterRequestResult.CacheHit, outerResult);
        Assert.Equal(PlayerInfoRasterRequestResult.CacheHit, reentrantResult);
        Assert.Equal(1, maxDepth);
        Assert.Equal(2, events.Length);
        Assert.Equal(first.BatchKey, events[0].Args.BatchKey);
        Assert.Equal(3, events[0].Args.Generation);
        Assert.True(events[0].Args.FromCache);
        Assert.Equal(first.BatchKey, events[0].CurrentKey);
        Assert.Equal(second.BatchKey, events[1].Args.BatchKey);
        Assert.Equal(4, events[1].Args.Generation);
        Assert.True(events[1].Args.FromCache);
        Assert.Equal(second.BatchKey, events[1].CurrentKey);
    }

    [Fact]
    public async Task ThrowingObserver_DoesNotBreakOrderedGenerationAndCacheMetadata()
    {
        var rasterizer = new ImmediateRasterizer();
        using var pipeline = new PlayerInfoRasterPipeline(rasterizer);
        using var observedSignal = new SemaphoreSlim(0);
        var observed = new ConcurrentQueue<PlayerInfoRasterBatchPublishedEventArgs>();
        var throwingObserverCalls = 0;
        pipeline.BatchPublished += (_, _) =>
        {
            Interlocked.Increment(ref throwingObserverCalls);
            throw new InvalidOperationException("synthetic observer fault");
        };
        pipeline.BatchPublished += (_, args) =>
        {
            observed.Enqueue(args);
            observedSignal.Release();
        };
        PlayerInfoRasterPlan first = CreatePlan(576);
        PlayerInfoRasterPlan second = CreatePlan(720);

        pipeline.Request(first);
        await WaitForIdle(pipeline);
        Assert.True(await observedSignal.WaitAsync(TimeSpan.FromSeconds(5)));
        pipeline.Request(second);
        await WaitForIdle(pipeline);
        Assert.True(await observedSignal.WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.Equal(
            PlayerInfoRasterRequestResult.CacheHit,
            pipeline.Request(first));
        Assert.True(await observedSignal.WaitAsync(TimeSpan.FromSeconds(5)));

        PlayerInfoRasterBatchPublishedEventArgs[] events = observed.ToArray();
        Assert.Equal(3, throwingObserverCalls);
        Assert.Equal(3, events.Length);
        Assert.Equal(
            new[] { first.BatchKey, second.BatchKey, first.BatchKey },
            events.Select(args => args.BatchKey));
        Assert.Equal(new long[] { 1, 2, 3 }, events.Select(args => args.Generation));
        Assert.Equal(
            new[] { false, false, true },
            events.Select(args => args.FromCache));
        Assert.Equal(3, pipeline.Snapshot.PublishCount);
        Assert.Equal(0, pipeline.Snapshot.FaultCount);
        Assert.Equal(
            PlayerInfoRasterRequestResult.CurrentHit,
            pipeline.Request(first));
    }

    private static PlayerInfoRasterPlan CreatePlan(
        int viewportHeight,
        int left = 0,
        int top = 0)
    {
        int viewportWidth = checked((int)Math.Round(
            viewportHeight * (1024d / 576d)));
        return PlayerInfoRasterPlanner.Create(
            AssetSet,
            new Rectangle(left, top, viewportWidth, viewportHeight),
            monitorDpiScale: 1.75f);
    }

    private static async Task WaitForIdle(PlayerInfoRasterPipeline pipeline)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        await pipeline.WaitForIdleAsync(timeout.Token);
    }

    private static PlayerInfoRasterBatch CreateBatch(
        PlayerInfoRasterPlan plan)
    {
        var layers = new List<PlayerInfoRasterLayer>(plan.Layers.Count);
        try
        {
            foreach (PlayerInfoRasterLayerPlan layerPlan in plan.Layers)
            {
                layers.Add(new PlayerInfoRasterLayer(
                    layerPlan.Key,
                    new Bitmap(
                        layerPlan.PixelWidth,
                        layerPlan.PixelHeight,
                        PixelFormat.Format32bppPArgb)));
            }
            var batch = new PlayerInfoRasterBatch(plan.BatchKey, layers);
            layers.Clear();
            return batch;
        }
        catch
        {
            foreach (PlayerInfoRasterLayer layer in layers)
            {
                layer.Dispose();
            }
            throw;
        }
    }

    private static void RecordCompleteProgress(
        PlayerInfoRasterPlan plan,
        PlayerInfoRasterProgress progress)
    {
        foreach (PlayerInfoRasterLayerPlan _ in plan.Layers)
        {
            progress.RecordParse();
            progress.RecordRaster();
        }
    }

    private sealed class ImmediateRasterizer : IPlayerInfoRasterizer
    {
        private int _callCount;

        internal int CallCount => Volatile.Read(ref _callCount);
        internal ConcurrentBag<PlayerInfoRasterBatch> Batches { get; } = [];
        internal PlayerInfoRasterBatch? LastBatch { get; private set; }

        public PlayerInfoRasterBatch Bake(
            PlayerInfoRasterPlan plan,
            CancellationToken cancellationToken,
            PlayerInfoRasterProgress progress)
        {
            Interlocked.Increment(ref _callCount);
            cancellationToken.ThrowIfCancellationRequested();
            RecordCompleteProgress(plan, progress);
            PlayerInfoRasterBatch batch = CreateBatch(plan);
            LastBatch = batch;
            Batches.Add(batch);
            return batch;
        }
    }

    private sealed class BlockingFirstRasterizer(
        bool ignoreFirstCancellation) : IPlayerInfoRasterizer
    {
        private int _callCount;
        private int _active;
        private int _maxConcurrent;

        internal ManualResetEventSlim FirstStarted { get; } = new(false);
        internal ManualResetEventSlim ReleaseFirst { get; } = new(false);
        internal int CallCount => Volatile.Read(ref _callCount);
        internal int MaxConcurrent => Volatile.Read(ref _maxConcurrent);
        internal PlayerInfoRasterBatch? LastBatch { get; private set; }

        public PlayerInfoRasterBatch Bake(
            PlayerInfoRasterPlan plan,
            CancellationToken cancellationToken,
            PlayerInfoRasterProgress progress)
        {
            int active = Interlocked.Increment(ref _active);
            UpdateMaximum(ref _maxConcurrent, active);
            int call = Interlocked.Increment(ref _callCount);
            try
            {
                if (call == 1)
                {
                    FirstStarted.Set();
                    if (ignoreFirstCancellation)
                    {
                        if (!ReleaseFirst.Wait(TimeSpan.FromSeconds(5)))
                        {
                            throw new TimeoutException("first bake was not released");
                        }
                    }
                    else
                    {
                        cancellationToken.WaitHandle.WaitOne(TimeSpan.FromSeconds(5));
                        cancellationToken.ThrowIfCancellationRequested();
                    }
                }
                if (!(call == 1 && ignoreFirstCancellation))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                }
                RecordCompleteProgress(plan, progress);
                PlayerInfoRasterBatch batch = CreateBatch(plan);
                LastBatch = batch;
                return batch;
            }
            finally
            {
                Interlocked.Decrement(ref _active);
            }
        }
    }

    private sealed class FaultOnSecondRasterizer : IPlayerInfoRasterizer
    {
        private int _calls;

        public PlayerInfoRasterBatch Bake(
            PlayerInfoRasterPlan plan,
            CancellationToken cancellationToken,
            PlayerInfoRasterProgress progress)
        {
            int call = Interlocked.Increment(ref _calls);
            if (call == 2)
            {
                for (var index = 0; index < 3; index++)
                {
                    progress.RecordParse();
                    if (index < 2)
                    {
                        progress.RecordRaster();
                    }
                }
                throw new InvalidOperationException("synthetic fault");
            }
            RecordCompleteProgress(plan, progress);
            return CreateBatch(plan);
        }
    }

    private static void UpdateMaximum(ref int target, int value)
    {
        while (true)
        {
            int current = Volatile.Read(ref target);
            if (value <= current ||
                Interlocked.CompareExchange(ref target, value, current) == current)
            {
                return;
            }
        }
    }
}
