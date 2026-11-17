using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tooltips
{
    /// <summary>A single, trusted, synchronous content engine. Owned only by the tooltip worker.</summary>
    internal interface ITooltipContentEngine : IDisposable
    {
        string Identity { get; }
        string BuildProjection(string inputJson);
    }

    internal enum TooltipRequestKind { Hover, Inspector, Response }

    /// <summary>Presentation identity is deliberately separate from the read-only content snapshot.</summary>
    internal sealed class TooltipRequestIdentity
    {
        internal readonly string Owner, RequestId, SceneId, Revision, Lease;
        internal readonly TooltipRequestKind Kind;
        internal readonly long Sequence;
        internal string Lane => Kind.ToString() + ":" + Owner;

        internal TooltipRequestIdentity(string owner, string requestId, string sceneId = "",
            string revision = "", string lease = "", TooltipRequestKind kind = TooltipRequestKind.Hover,
            long sequence = 0)
        {
            if (string.IsNullOrEmpty(owner) || owner.Length > 1024)
                throw new ArgumentException("Invalid tooltip owner", nameof(owner));
            if (string.IsNullOrEmpty(requestId) || requestId.Length > 256)
                throw new ArgumentException("Invalid tooltip request identity", nameof(requestId));
            Owner = owner; RequestId = requestId; SceneId = sceneId ?? "";
            Revision = revision ?? ""; Lease = lease ?? ""; Kind = kind; Sequence = sequence;
        }
    }

    /// <summary>Immutable cached bytes: each consumer parses its own JObject before modifying it.</summary>
    internal sealed class TooltipBuildResult
    {
        internal readonly string Json;
        internal TooltipBuildResult(string json) { Json = json; }
        internal JObject ToObject() => JObject.Parse(Json);
    }

    internal sealed class TooltipServiceMetrics
    {
        internal int Queued, ActiveRequests, CacheEntries, MaxQueueDepth;
        internal long CacheBytes, Submitted, Built, CacheHits, Coalesced, Canceled, Rejected;
        internal double InitializationMilliseconds, BuildMilliseconds;
        internal string EngineIdentity;
    }

    /// <summary>
    /// Dedicated, persistent non-realtime worker. No GameInput engine, lock, UI wait or Flash callback.
    /// Unique queued computations and subscribers are bounded; latest request wins within an owner/lane.
    /// Cancellation retires a subscriber, never interrupts a running V8 function. Identical immutable
    /// snapshots share work and a bounded LRU. Catalog/bundle identity is fixed for this service lifetime.
    /// </summary>
    internal sealed class TooltipService : IDisposable
    {
        internal const int MaxInputChars = 262144;
        internal const int MaxInputNodes = 8192;
        internal const int MaxInputDepth = 24;
        private readonly object _gate = new object();
        private readonly Func<ITooltipContentEngine> _engineFactory;
        private readonly Action<string> _log;
        private readonly Thread _worker;
        private readonly int _queueCapacity, _subscriberCapacity, _cacheCapacity;
        private readonly long _cacheByteLimit;
        private readonly LinkedList<Work> _queue = new LinkedList<Work>();
        private readonly Dictionary<string, Work> _computations = new Dictionary<string, Work>(StringComparer.Ordinal);
        private readonly Dictionary<string, Subscriber> _owners = new Dictionary<string, Subscriber>(StringComparer.Ordinal);
        private readonly Dictionary<string, CacheEntry> _cache = new Dictionary<string, CacheEntry>(StringComparer.Ordinal);
        private readonly LinkedList<string> _lru = new LinkedList<string>();
        private readonly Dictionary<string, long> _frontiers = new Dictionary<string, long>(StringComparer.Ordinal);
        private readonly Queue<string> _frontierOwners = new Queue<string>();
        private readonly TaskCompletionSource<bool> _ready = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        private bool _disposed;
        private Exception _initializationError;
        private long _cacheBytes, _submitted, _built, _cacheHits, _coalesced, _canceled, _rejected;
        private int _maxQueueDepth;
        private double _initializationMs, _buildMs;
        private string _engineIdentity;

        private sealed class Work
        {
            internal string Key, Input;
            internal LinkedListNode<Work> Node;
            internal bool Running;
            internal bool DetailsOnly;
            internal readonly List<Subscriber> Subscribers = new List<Subscriber>();
        }
        private sealed class Subscriber
        {
            internal TooltipRequestIdentity Identity;
            internal Work Work;
            internal bool Finished;
            internal CancellationToken Token;
            internal Func<bool> IsCurrent;
            internal CancellationTokenRegistration Registration;
            internal readonly TaskCompletionSource<TooltipBuildResult> Completion =
                new TaskCompletionSource<TooltipBuildResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        }
        private sealed class CacheEntry
        {
            internal TooltipBuildResult Result;
            internal int Bytes;
            internal LinkedListNode<string> Node;
        }

        internal TooltipService(Func<ITooltipContentEngine> engineFactory, Action<string> log = null,
            int queueCapacity = 64, int subscriberCapacity = 128, int cacheCapacity = 256,
            long cacheByteLimit = 16 * 1024 * 1024)
        {
            _engineFactory = engineFactory ?? throw new ArgumentNullException(nameof(engineFactory));
            if (queueCapacity < 1 || subscriberCapacity < queueCapacity || cacheCapacity < 0 || cacheByteLimit < 0)
                throw new ArgumentOutOfRangeException(nameof(queueCapacity));
            _queueCapacity = queueCapacity; _subscriberCapacity = subscriberCapacity;
            _cacheCapacity = cacheCapacity; _cacheByteLimit = cacheByteLimit; _log = log;
            _worker = new Thread(Run) { IsBackground = true, Name = "CF7.Tooltip" };
            _worker.Start();
        }

        internal Task Ready => _ready.Task;

        internal Task<TooltipBuildResult> BuildAsync(JObject input, TooltipRequestIdentity identity,
            CancellationToken cancellationToken = default, Func<bool> isCurrent = null)
        {
            if (identity == null) throw new ArgumentNullException(nameof(identity));
            if (cancellationToken.IsCancellationRequested)
                return Task.FromCanceled<TooltipBuildResult>(cancellationToken);
            if (!FenceIsCurrent(isCurrent)) return Task.FromCanceled<TooltipBuildResult>(new CancellationToken(true));
            string inputJson;
            try { inputJson = ValidateAndSerializeInput(input); }
            catch (Exception ex) { return Task.FromException<TooltipBuildResult>(ex); }
            // Never use the item name as a cache key. Snapshot, revision, lease and scene all participate;
            // engine/catalog SHA is an implicit namespace because caches never escape this service.
            string key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
                JsonConvert.SerializeObject(new[] { identity.SceneId, identity.Revision, identity.Lease, inputJson }))));
            // Serialization/hashing can overlap close/disconnect. Recheck before any ownership
            // or frontier mutation; domain callbacks stay outside the scheduler lock.
            if (!FenceIsCurrent(isCurrent) || cancellationToken.IsCancellationRequested)
                return Task.FromCanceled<TooltipBuildResult>(cancellationToken.IsCancellationRequested
                    ? cancellationToken : new CancellationToken(true));
            Subscriber subscriber = null;
            TooltipBuildResult cachedResult = null;
            lock (_gate)
            {
                _submitted++;
                if (cancellationToken.IsCancellationRequested)
                    return Task.FromCanceled<TooltipBuildResult>(cancellationToken);
                if (_disposed) return Task.FromException<TooltipBuildResult>(new ObjectDisposedException(nameof(TooltipService)));
                if (_initializationError != null) return Task.FromException<TooltipBuildResult>(_initializationError);
                if (identity.Sequence > 0)
                {
                    bool known = _frontiers.TryGetValue(identity.Lane, out long previous);
                    if (known && identity.Sequence < previous)
                    {
                        _canceled++;
                        return Task.FromCanceled<TooltipBuildResult>(new CancellationToken(true));
                    }
                    if (!known)
                    {
                        // Completed owner frontiers prevent an older AS2 reply from superseding a newer
                        // cached/completed hover. Panel identities are bounded; disconnect resets them.
                        while (_frontierOwners.Count >= 1024) _frontiers.Remove(_frontierOwners.Dequeue());
                        _frontierOwners.Enqueue(identity.Lane);
                    }
                    _frontiers[identity.Lane] = identity.Sequence;
                }
                if (_owners.TryGetValue(identity.Lane, out var old)) RetireLocked(old);
                if (_cache.TryGetValue(key, out var cached))
                {
                    _cacheHits++; _lru.Remove(cached.Node); _lru.AddFirst(cached.Node);
                    cachedResult = cached.Result;
                }
                else
                {
                    bool existing = _computations.TryGetValue(key, out var work);
                    if (_owners.Count >= _subscriberCapacity || (!existing && _queue.Count >= _queueCapacity))
                    {
                        _rejected++;
                        return Task.FromException<TooltipBuildResult>(new InvalidOperationException("tooltip_queue_full"));
                    }
                    if (!existing)
                    {
                        work = new Work { Key = key, Input = inputJson,
                            DetailsOnly = input["output"]?.Type == JTokenType.String && input.Value<string>("output") == "details" };
                        work.Node = _queue.AddLast(work); _computations.Add(key, work);
                        _maxQueueDepth = Math.Max(_maxQueueDepth, _queue.Count);
                    }
                    else _coalesced++;
                    subscriber = new Subscriber { Identity = identity, Work = work, Token = cancellationToken, IsCurrent = isCurrent };
                    work.Subscribers.Add(subscriber); _owners[identity.Lane] = subscriber;
                    Monitor.Pulse(_gate);
                }
            }
            if (cachedResult != null)
            {
                // No worker will see this request. Apply the same completion fence explicitly.
                if (!FenceIsCurrent(isCurrent) || cancellationToken.IsCancellationRequested)
                    return Task.FromCanceled<TooltipBuildResult>(cancellationToken.IsCancellationRequested
                        ? cancellationToken : new CancellationToken(true));
                return Task.FromResult(cachedResult);
            }
            if (cancellationToken.CanBeCanceled)
            {
                var registration = cancellationToken.Register(() => { lock (_gate) RetireLocked(subscriber); });
                lock (_gate)
                {
                    subscriber.Registration = registration;
                    if (subscriber.Finished) registration.Unregister();
                }
            }
            return subscriber.Completion.Task;
        }

        /// <summary>Exact cancellation must not retire a newer hover or a separate pinned inspector.</summary>
        internal void Cancel(string owner, TooltipRequestKind kind, string requestId = null, string sceneId = null)
        {
            lock (_gate)
            {
                if (!_owners.TryGetValue(kind.ToString() + ":" + owner, out var subscriber)) return;
                if (requestId != null && !string.Equals(requestId, subscriber.Identity.RequestId, StringComparison.Ordinal)) return;
                if (sceneId != null && !string.Equals(sceneId, subscriber.Identity.SceneId, StringComparison.Ordinal)) return;
                RetireLocked(subscriber);
            }
        }

        internal void ResetRequests()
        {
            lock (_gate)
            {
                foreach (var subscriber in new List<Subscriber>(_owners.Values)) RetireLocked(subscriber);
                _frontiers.Clear(); _frontierOwners.Clear();
            }
        }

        private void RetireLocked(Subscriber subscriber)
        {
            if (subscriber.Finished) return;
            subscriber.Finished = true; _canceled++;
            if (_owners.TryGetValue(subscriber.Identity.Lane, out var current) && ReferenceEquals(current, subscriber))
                _owners.Remove(subscriber.Identity.Lane);
            subscriber.Work.Subscribers.Remove(subscriber);
            if (!subscriber.Work.Running && subscriber.Work.Subscribers.Count == 0)
            {
                if (subscriber.Work.Node != null) _queue.Remove(subscriber.Work.Node);
                subscriber.Work.Node = null; _computations.Remove(subscriber.Work.Key);
            }
            subscriber.Registration.Unregister();
            subscriber.Completion.TrySetCanceled(subscriber.Token.IsCancellationRequested ? subscriber.Token : new CancellationToken(true));
        }

        private void Run()
        {
            ITooltipContentEngine engine = null;
            try
            {
                var init = Stopwatch.StartNew();
                engine = _engineFactory();
                lock (_gate) { _engineIdentity = engine.Identity; _initializationMs = init.Elapsed.TotalMilliseconds; }
                _ready.TrySetResult(true);
                while (true)
                {
                    Work work;
                    lock (_gate)
                    {
                        while (!_disposed && _queue.Count == 0) Monitor.Wait(_gate);
                        if (_disposed) break;
                        work = _queue.First.Value; _queue.RemoveFirst(); work.Node = null; work.Running = true;
                    }
                    RetireExpiredSubscribers(work);
                    lock (_gate)
                    {
                        if (work.Subscribers.Count == 0)
                        {
                            _computations.Remove(work.Key);
                            continue;
                        }
                    }
                    TooltipBuildResult result = null;
                    Exception error = null;
                    var timer = Stopwatch.StartNew();
                    try { result = ValidateProjection(engine.BuildProjection(work.Input), work.DetailsOnly); }
                    catch (Exception ex) { error = ex; }
                    RetireExpiredSubscribers(work);
                    lock (_gate)
                    {
                        _built++; _buildMs += timer.Elapsed.TotalMilliseconds;
                        _computations.Remove(work.Key);
                        if (result != null && !_disposed) CacheLocked(work.Key, result);
                        foreach (var subscriber in work.Subscribers)
                        {
                            if (subscriber.Finished) continue;
                            subscriber.Finished = true;
                            if (_owners.TryGetValue(subscriber.Identity.Lane, out var current) && ReferenceEquals(current, subscriber))
                                _owners.Remove(subscriber.Identity.Lane);
                            subscriber.Registration.Unregister();
                            if (error != null) subscriber.Completion.TrySetException(error);
                            else subscriber.Completion.TrySetResult(result);
                        }
                        work.Subscribers.Clear();
                    }
                    if (error != null) _log?.Invoke("[TooltipService] content failed: " + error.GetType().Name + " " + error.Message);
                }
            }
            catch (Exception ex)
            {
                lock (_gate)
                {
                    _initializationError = ex;
                    foreach (var subscriber in _owners.Values)
                    {
                        subscriber.Finished = true; subscriber.Registration.Unregister();
                        subscriber.Completion.TrySetException(ex);
                    }
                    _owners.Clear(); _queue.Clear(); _computations.Clear();
                }
                _ready.TrySetException(ex);
                _log?.Invoke("[TooltipService] initialization failed: " + ex.GetType().Name + " " + ex.Message);
            }
            finally
            {
                try { engine?.Dispose(); }
                catch (Exception ex) { _log?.Invoke("[TooltipService] engine disposal failed: " + ex.GetType().Name); }
            }
        }

        private static bool FenceIsCurrent(Func<bool> fence)
        {
            try { return fence == null || fence(); }
            catch { return false; }
        }

        private void RetireExpiredSubscribers(Work work)
        {
            Subscriber[] subscribers;
            lock (_gate) subscribers = work.Subscribers.ToArray();
            // Domain fences may take their own locks. Never invoke them under the scheduler lock.
            foreach (var subscriber in subscribers)
                if (!FenceIsCurrent(subscriber.IsCurrent))
                    lock (_gate) RetireLocked(subscriber);
        }

        private void CacheLocked(string key, TooltipBuildResult result)
        {
            if (_cacheCapacity == 0 || _cacheByteLimit == 0) return;
            // Cached strings are UTF-16, not their shorter UTF-8 wire representation. Add bounded
            // key/entry/list bookkeeping; this is a conservative cache estimate, not V8/process RSS.
            int bytes = checked(result.Json.Length * 2 + 512);
            if (bytes > _cacheByteLimit) return;
            while (_cache.Count >= _cacheCapacity || _cacheBytes + bytes > _cacheByteLimit)
            {
                string evicted = _lru.Last.Value;
                _cacheBytes -= _cache[evicted].Bytes; _cache.Remove(evicted); _lru.RemoveLast();
            }
            var entry = new CacheEntry { Result = result, Bytes = bytes, Node = _lru.AddFirst(key) };
            _cache[key] = entry; _cacheBytes += bytes;
        }

        internal TooltipServiceMetrics GetMetrics()
        {
            lock (_gate) return new TooltipServiceMetrics
            {
                Queued = _queue.Count, ActiveRequests = _owners.Count, CacheEntries = _cache.Count,
                MaxQueueDepth = _maxQueueDepth, CacheBytes = _cacheBytes, Submitted = _submitted,
                Built = _built, CacheHits = _cacheHits, Coalesced = _coalesced, Canceled = _canceled,
                Rejected = _rejected, InitializationMilliseconds = _initializationMs,
                BuildMilliseconds = _buildMs, EngineIdentity = _engineIdentity
            };
        }

        internal static string ValidateAndSerializeInput(JObject input)
        {
            if (input == null || input["version"]?.Type != JTokenType.Integer || input.Value<int>("version") != 1)
                throw new ArgumentException("tooltip_input_version");
            string kind = input["kind"]?.Type == JTokenType.String ? input.Value<string>("kind") : null;
            if (kind != "item" && kind != "skill" && kind != "body" && kind != "hud")
                throw new ArgumentException("tooltip_input_kind");
            int nodes = 0;
            ValidateToken(input, 0, ref nodes);
            string json = input.ToString(Formatting.None);
            if (json.Length > MaxInputChars) throw new ArgumentException("tooltip_input_size");
            return json;
        }

        private static void ValidateToken(JToken token, int depth, ref int nodes)
        {
            if (++nodes > MaxInputNodes || depth > MaxInputDepth) throw new ArgumentException("tooltip_input_structure");
            if (token is JObject obj)
            {
                foreach (var property in obj.Properties())
                {
                    if (property.Name == "__proto__" || property.Name == "constructor" || property.Name == "prototype")
                        throw new ArgumentException("tooltip_input_property");
                    ValidateToken(property.Value, depth + 1, ref nodes);
                }
            }
            else if (token is JArray array)
            {
                foreach (var child in array) ValidateToken(child, depth + 1, ref nodes);
            }
            else if (token.Type == JTokenType.String)
            {
                if (token.Value<string>().Length > MaxInputChars) throw new ArgumentException("tooltip_input_string");
            }
            else if (token.Type == JTokenType.Float)
            {
                if (!double.IsFinite(token.Value<double>())) throw new ArgumentException("tooltip_input_number");
            }
            else if (token.Type != JTokenType.Integer && token.Type != JTokenType.Boolean && token.Type != JTokenType.Null)
                throw new ArgumentException("tooltip_input_type");
        }

        private static TooltipBuildResult ValidateProjection(string json, bool detailsOnly)
        {
            if (json == null || json.Length > 2 * 1024 * 1024) throw new InvalidOperationException("tooltip_output_size");
            var projection = JObject.Parse(json);
            if (detailsOnly)
            {
                if (projection["details"]?.Type != JTokenType.String || projection.Value<string>("details").Length > 4096)
                    throw new InvalidOperationException("tooltip_output_details");
                return new TooltipBuildResult(new JObject { ["details"] = projection.Value<string>("details") }.ToString(Formatting.None));
            }
            if (!TooltipDocumentSanitizer.TrySanitize(projection["document"], out var document))
                throw new InvalidOperationException("tooltip_output_document");
            var clean = new JObject { ["document"] = document };
            foreach (string key in new[] { "descHTML", "introHTML", "details" })
            {
                var token = projection[key];
                int limit = key == "details" ? 4096 : 262144;
                if (token?.Type != JTokenType.String || token.Value<string>().Length > limit)
                    throw new InvalidOperationException("tooltip_output_" + key);
                clean[key] = token.DeepClone();
            }
            return new TooltipBuildResult(clean.ToString(Formatting.None));
        }

        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                foreach (var subscriber in new List<Subscriber>(_owners.Values)) RetireLocked(subscriber);
                _cache.Clear(); _lru.Clear(); _cacheBytes = 0;
                _frontiers.Clear(); _frontierOwners.Clear();
                Monitor.PulseAll(_gate);
            }
            // Engine disposal occurs on its owning worker. No UI/thread-pool synchronous wait.
        }
    }
}
