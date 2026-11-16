using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tooltips
{
    /// <summary>Read-only view of the domain's existing pending entry; no second pending authority.</summary>
    internal sealed class TooltipResponseOwner
    {
        // No pending entry means the original domain handler must receive the response directly.
        // Null instead means a valid non-hover/batch/write response that still needs enrichment.
        internal static readonly TooltipResponseOwner NoPending = new TooltipResponseOwner { MissingPending = true };
        internal bool MissingPending;
        internal TooltipRequestIdentity Identity;
        internal Func<bool> IsCurrent;
        internal Action RetireSuperseded;

        internal static TooltipResponseOwner Create(string domain, string panel, string instance,
            string requestId, int sequence, JObject request, Func<bool> isCurrent, Action retire,
            TooltipRequestKind kind = TooltipRequestKind.Hover)
        {
            return new TooltipResponseOwner
            {
                Identity = new TooltipRequestIdentity("web:" + domain + ":" + (panel ?? "legacy") + ":" + (instance ?? "legacy"),
                    requestId, revision: request?.ToString(Formatting.None) ?? "", kind: kind, sequence: sequence),
                IsCurrent = isCurrent, RetireSuperseded = retire
            };
        }
    }

    /// <summary>
    /// Enrich only AS2 response domains that already own tooltip projections. The original domain
    /// handler still validates callId, owner, lease/revision and its complete response schema AFTER
    /// async computation. No business acknowledgement is canceled, replayed or rewritten as a result
    /// of a tooltip failure. Nested previews remain one existing RPC, not one RPC per item.
    /// </summary>
    internal sealed class TooltipResponseEnricher : IDisposable
    {
        private static readonly HashSet<string> ResponseTasks = new HashSet<string>(StringComparer.Ordinal)
        {
            "inventory_response", "shop_response", "npcshop_response", "crafting_response",
            "loot_response", "equipment_tuning_response", "loadout_response", "item_use_response",
            "skill_response", "merc_response", "arena_response", "pet_response", "task_response",
            "intelligence_response", "blackmarket_response", "modifier_response", "character_create_response"
        };
        // ChoiceReward's existing domain maximum is 16 offers * 4 options * 16 items = 1024.
        private const int MaxInputs = 1024;
        private const int MaxMessages = 32;
        private const long MaxPendingChars = 16 * 1024 * 1024;
        private readonly TooltipService _service;
        private readonly Func<int> _connectionGeneration;
        private readonly Action<string> _log;
        private readonly object _gate = new object();
        private readonly Dictionary<string, Func<int, TooltipResponseOwner>> _ownerResolvers =
            new Dictionary<string, Func<int, TooltipResponseOwner>>(StringComparer.Ordinal);
        private CancellationTokenSource _lifetime = new CancellationTokenSource();
        private long _epoch, _serial, _pendingChars;
        private int _messages;
        private bool _disposed;

        private sealed class InputSlot
        {
            internal JObject Parent, Input;
            internal string Path, Scene, Revision, Lease;
        }

        internal TooltipResponseEnricher(TooltipService service, Func<int> connectionGeneration = null,
            Action<string> log = null)
        {
            _service = service ?? throw new ArgumentNullException(nameof(service));
            _connectionGeneration = connectionGeneration; _log = log;
        }

        internal void RegisterOwnerResolver(string responseTask, Func<int, TooltipResponseOwner> resolver)
        {
            if (!ResponseTasks.Contains(responseTask)) throw new ArgumentException(nameof(responseTask));
            lock (_gate) _ownerResolvers[responseTask] = resolver;
        }

        /// <returns>True if this response is deferred (or rejected after disconnect), false for the unchanged fast path.</returns>
        internal bool TryEnrich(JObject message, int connectionGeneration, Action<JObject> resume)
        {
            string task = message["task"]?.Type == JTokenType.String ? message.Value<string>("task") : null;
            if (task == null || !ResponseTasks.Contains(task)) return false;
            var found = new List<InputSlot>();
            int nodes = 0;
            try { FindInputs(message, "$", "", "", "", found, 0, ref nodes); }
            catch (ArgumentException ex)
            {
                // Leave malformed shapes to the existing strict domain validator; do not synthesize success.
                _log?.Invoke("[TooltipService] response rejected: " + ex.Message);
                return false;
            }
            if (found.Count == 0) return false;
            TooltipResponseOwner owner = null;
            Func<int, TooltipResponseOwner> resolver = null;
            lock (_gate) _ownerResolvers.TryGetValue(task, out resolver);
            if (resolver != null && message["callId"]?.Type == JTokenType.Integer)
                owner = resolver(message.Value<int>("callId"));
            if (owner?.MissingPending == true) return false;
            string json = message.ToString(Formatting.None);
            long epoch;
            CancellationToken cancellation;
            lock (_gate)
            {
                if (_disposed || (_connectionGeneration != null && _connectionGeneration() != connectionGeneration)) return true;
                if (_messages >= MaxMessages || _pendingChars + json.Length > MaxPendingChars)
                {
                    foreach (var slot in found) ApplyFailure(slot);
                    _log?.Invoke("[TooltipService] response budget exhausted");
                    resume(message);
                    return true;
                }
                _messages++; _pendingChars += json.Length;
                epoch = _epoch; cancellation = _lifetime.Token;
            }
            // Domain response ownership transfers here. No caller mutates it after ProcessMessage returns.
            _ = EnrichAndResume(message, found, task, owner, connectionGeneration, epoch, json.Length, cancellation, resume);
            return true;
        }

        private async Task EnrichAndResume(JObject message, List<InputSlot> slots, string task, TooltipResponseOwner owner,
            int generation, long epoch, int chars, CancellationToken cancellation, Action<JObject> resume)
        {
            string callId = message["callId"]?.ToString(Formatting.None) ?? "uncorrelated";
            string batch = Interlocked.Increment(ref _serial).ToString(System.Globalization.CultureInfo.InvariantCulture);
            try
            {
                // Sequential enqueue keeps a 1024-item snapshot from filling the global worker queue.
                // Other hover/Inspector requests can run between items; results still arrive in one RPC.
                foreach (var slot in slots)
                {
                    cancellation.ThrowIfCancellationRequested();
                    if (owner != null && !owner.IsCurrent()) return;
                    try
                    {
                        var identity = owner == null
                            ? new TooltipRequestIdentity("response:" + task + ":" + batch + ":" + slot.Path,
                                callId.Length <= 256 ? callId : batch, slot.Scene, slot.Revision, slot.Lease, TooltipRequestKind.Response)
                            : new TooltipRequestIdentity(owner.Identity.Owner, owner.Identity.RequestId,
                                JsonConvert.SerializeObject(new[] { owner.Identity.SceneId, slot.Scene }),
                                JsonConvert.SerializeObject(new[] { owner.Identity.Revision, slot.Revision }),
                                JsonConvert.SerializeObject(new[] { owner.Identity.Lease, slot.Lease }),
                                owner.Identity.Kind, owner.Identity.Sequence);
                        var result = await _service.BuildAsync(slot.Input, identity, cancellation, owner?.IsCurrent).ConfigureAwait(false);
                        ApplyProjection(slot, result.ToObject());
                    }
                    catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { throw; }
                    catch (OperationCanceledException) when (owner != null)
                    {
                        owner.RetireSuperseded();
                        return;
                    }
                    catch (Exception ex)
                    {
                        _log?.Invoke("[TooltipService] response content failed task=" + task + " path=" + slot.Path
                            + " reason=" + ex.GetType().Name + " " + ex.Message);
                        ApplyFailure(slot);
                    }
                }
                lock (_gate)
                {
                    if (_disposed || epoch != _epoch || cancellation.IsCancellationRequested
                        || (_connectionGeneration != null && _connectionGeneration() != generation)
                        || (owner != null && !owner.IsCurrent())) return;
                    // The domain validator is the final completion fence (pending callId, closed panel,
                    // revision, exact owner, late response). This lock only serializes disconnect retirement.
                    resume(message);
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception ex) { _log?.Invoke("[TooltipService] response dispatch failed: " + ex.Message); }
            finally { lock (_gate) { _messages--; _pendingChars -= chars; } }
        }

        private static void FindInputs(JToken token, string path, string scene, string revision, string lease,
            List<InputSlot> slots, int depth, ref int nodes)
        {
            if (++nodes > 32768 || depth > 24) throw new ArgumentException("tooltip_response_structure");
            if (token is JObject obj)
            {
                scene = ReadIdentity(obj, "sceneId", scene);
                revision = ReadIdentity(obj, "revision", revision);
                lease = ReadIdentity(obj, "lease", ReadIdentity(obj, "expectedLease", lease));
                if (obj["tooltipInput"] != null)
                {
                    if (slots.Count >= MaxInputs) throw new ArgumentException("tooltip_response_count");
                    slots.Add(new InputSlot { Parent = obj, Input = obj["tooltipInput"] as JObject,
                        Path = path, Scene = scene, Revision = revision, Lease = lease });
                }
                foreach (var property in obj.Properties())
                    if (property.Name != "tooltipInput")
                        FindInputs(property.Value, path + "." + property.Name, scene, revision, lease, slots, depth + 1, ref nodes);
            }
            else if (token is JArray array)
                for (int i = 0; i < array.Count; i++)
                    FindInputs(array[i], path + "[" + i + "]", scene, revision, lease, slots, depth + 1, ref nodes);
        }

        private static string ReadIdentity(JObject value, string key, string fallback)
        {
            JToken token = value[key];
            return token != null && (token.Type == JTokenType.String || token.Type == JTokenType.Integer)
                ? token.ToString(Formatting.None) : fallback;
        }

        private static void ApplyProjection(InputSlot slot, JObject projection)
        {
            string output = slot.Input?["output"]?.Type == JTokenType.String ? slot.Input.Value<string>("output") : null;
            slot.Parent.Remove("tooltipInput");
            if (output == "details") slot.Parent["details"] = projection["details"].DeepClone();
            else
            {
                slot.Parent["document"] = projection["document"].DeepClone();
                slot.Parent["introHTML"] = projection["introHTML"].DeepClone();
                slot.Parent["descHTML"] = projection["descHTML"].DeepClone();
            }
        }

        private static void ApplyFailure(InputSlot slot)
        {
            // Presentation failure only. Never change success/error/operationId or discard a committed
            // transaction acknowledgement. Explicit unavailable content replaces this tooltip alone.
            const string unavailable = "注释暂不可用。";
            ApplyProjection(slot, new JObject
            {
                ["document"] = new JObject { ["version"] = 1, ["title"] = "注释暂不可用",
                    ["sections"] = new JArray(new JObject { ["role"] = "body",
                        ["runs"] = new JArray(new JObject { ["text"] = unavailable }) }) },
                ["introHTML"] = "注释暂不可用", ["descHTML"] = unavailable, ["details"] = unavailable
            });
        }

        internal void Reset()
        {
            CancellationTokenSource old;
            lock (_gate)
            {
                if (_disposed) return;
                _epoch++; old = _lifetime; _lifetime = new CancellationTokenSource();
            }
            old.Cancel(); old.Dispose();
        }

        public void Dispose()
        {
            CancellationTokenSource lifetime;
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true; _epoch++; lifetime = _lifetime;
            }
            lifetime.Cancel(); lifetime.Dispose();
        }
    }
}
