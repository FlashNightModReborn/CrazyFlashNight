using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Dedicated Host-only correlation for material shop authorization.  It deliberately owns no
    /// timeout: the MaterialShopNavigationCoordinator owns the single transition deadline.
    /// </summary>
    public sealed class MaterialShopAccessTask : IDisposable
    {
        internal enum ResultKind
        {
            Allowed,
            Stale,
            Denied,
            TransportUnavailable,
            MalformedResponse
        }

        internal sealed class Request
        {
            internal string MaterialSnapshotId;
            internal string MaterialName;
            internal string ShopId;
            internal int CatalogIndex;
            internal bool IsProcurement;
            internal string RecipeId;
            internal string Category;
            internal int RecipeIndex;
            internal bool IsKShop;
            internal string EntryId;
            internal string KShopCategory;
        }

        internal sealed class Result
        {
            internal ResultKind Kind;
            internal string Error;
            internal string ItemName;
        }

        private sealed class Pending
        {
            internal Request Request;
            internal Func<bool> Fence;
            internal Action<Result> Completed;
        }

        private readonly Func<bool> _isReady;
        private readonly Func<string, bool> _trySend;
        private readonly object _lock = new object();
        private readonly Dictionary<int, Pending> _pending =
            new Dictionary<int, Pending>();
        private int _fidCursor;
        private bool _disposed;

        public MaterialShopAccessTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); })
        {
        }

        public MaterialShopAccessTask(
            Func<bool> isReady,
            Func<string, bool> trySend)
        {
            _isReady = isReady ?? delegate { return false; };
            _trySend = trySend ?? delegate { return false; };
        }

        internal int PendingCount
        {
            get { lock (_lock) return _pending.Count; }
        }

        internal void SetFidCursorForTests(int value)
        {
            lock (_lock) _fidCursor = value;
        }

        internal bool TryAuthorize(
            Request request,
            Func<bool> fence,
            Action<Result> completed,
            out int fid)
        {
            return TryAuthorize(
                request,
                fence,
                completed,
                null,
                out fid);
        }

        internal bool TryAuthorize(
            Request request,
            Func<bool> fence,
            Action<Result> completed,
            Action<int> fidAllocated,
            out int fid)
        {
            fid = 0;
            if (request == null || fence == null || completed == null)
                return false;
            if (!IsFenceCurrent(fence)) return false;
            bool ready;
            try { ready = _isReady(); }
            catch { ready = false; }
            if (!ready)
            {
                completed(new Result { Kind = ResultKind.TransportUnavailable });
                return true;
            }

            lock (_lock)
            {
                if (_disposed) return false;
                if (!TryAllocateFidLocked(out fid)) return false;
                _pending.Add(
                    fid,
                    new Pending
                    {
                        Request = CloneRequest(request),
                        Fence = fence,
                        Completed = completed
                    });
            }
            if (fidAllocated != null)
            {
                try { fidAllocated(fid); }
                catch
                {
                    Take(fid);
                    return false;
                }
            }
            // The coordinator can expire while transport readiness or allocation is in flight.
            // Recheck after publishing the fid so cancellation can never strand a pending entry.
            if (!IsFenceCurrent(fence))
            {
                Take(fid);
                return true;
            }

            var flash = new JObject
            {
                ["task"] = "cmd",
                ["action"] = request.IsKShop
                    ? "craftingProcurementKShopAuthorize"
                    : request.IsProcurement
                        ? "craftingProcurementShopAuthorize"
                        : "craftingMaterialShopAuthorize",
                ["callId"] = fid,
                ["v"] = 1
            };
            if (!request.IsProcurement)
                flash["materialSnapshotId"] = request.MaterialSnapshotId;
            flash["materialName"] = request.MaterialName;
            if (request.IsKShop)
            {
                flash["catalogIndex"] = request.CatalogIndex;
                flash["entryId"] = request.EntryId;
                flash["kshopCategory"] = request.KShopCategory;
                flash["recipeId"] = request.RecipeId;
                flash["recipeCategory"] = request.Category;
                flash["recipeIndex"] = request.RecipeIndex;
            }
            else
            {
                flash["shopId"] = request.ShopId;
                flash["catalogIndex"] = request.CatalogIndex;
                if (request.IsProcurement)
                {
                    flash["recipeId"] = request.RecipeId;
                    flash["category"] = request.Category;
                    flash["recipeIndex"] = request.RecipeIndex;
                }
            }
            LogManager.Log(
                AuthorityLogFormatter.FormatFlashCommand(
                    "MaterialShopAccessTask",
                    flash));
            bool sent;
            try { sent = _trySend(flash.ToString(Formatting.None) + "\0"); }
            catch (Exception ex)
            {
                sent = false;
                LogManager.Log(
                    "[MaterialShopAccessTask] send threw: "
                    + ex.GetType().Name);
            }
            if (sent) return true;

            Pending failed = Take(fid);
            if (failed != null && IsFenceCurrent(failed.Fence))
                failed.Completed(new Result { Kind = ResultKind.TransportUnavailable });
            return true;
        }

        internal bool Cancel(int fid)
        {
            return Take(fid) != null;
        }

        internal void ClearPending()
        {
            lock (_lock) _pending.Clear();
        }

        public void HandleFlashResponse(JObject message, Action<string> respond)
        {
            int fid;
            if (!TryReadPositiveFid(
                    message != null ? message["callId"] : null,
                    out fid))
            {
                if (respond != null) respond(null);
                return;
            }
            Pending pending = Take(fid);
            if (pending == null || !IsFenceCurrent(pending.Fence))
            {
                if (respond != null) respond(null);
                return;
            }

            Result result;
            if (!TryValidateResponse(message, pending.Request, out result))
                result = new Result { Kind = ResultKind.MalformedResponse };
            try { pending.Completed(result); }
            catch (Exception ex)
            {
                LogManager.Log(
                    "[MaterialShopAccessTask] completion threw: "
                    + ex.GetType().Name);
            }
            if (respond != null) respond(null);
        }

        public void Dispose()
        {
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
                _pending.Clear();
            }
        }

        private bool TryAllocateFidLocked(out int fid)
        {
            fid = 0;
            if (_pending.Count >= int.MaxValue) return false;
            int candidate = _fidCursor;
            do
            {
                candidate = candidate == int.MaxValue ? 1 : candidate + 1;
                if (!_pending.ContainsKey(candidate))
                {
                    _fidCursor = candidate;
                    fid = candidate;
                    return true;
                }
            }
            while (candidate != _fidCursor);
            return false;
        }

        private Pending Take(int fid)
        {
            lock (_lock)
            {
                Pending pending;
                if (!_pending.TryGetValue(fid, out pending)) return null;
                _pending.Remove(fid);
                return pending;
            }
        }

        private static Request CloneRequest(Request request)
        {
            return new Request
            {
                MaterialSnapshotId = request.MaterialSnapshotId,
                MaterialName = request.MaterialName,
                ShopId = request.ShopId,
                CatalogIndex = request.CatalogIndex,
                IsProcurement = request.IsProcurement,
                RecipeId = request.RecipeId,
                Category = request.Category,
                RecipeIndex = request.RecipeIndex,
                IsKShop = request.IsKShop,
                EntryId = request.EntryId,
                KShopCategory = request.KShopCategory
            };
        }

        private static bool IsFenceCurrent(Func<bool> fence)
        {
            try { return fence != null && fence(); }
            catch { return false; }
        }

        private static bool TryValidateResponse(
            JObject message,
            Request request,
            out Result result)
        {
            result = null;
            if (message == null
                || !HasString(message["task"], "material_shop_access_response")
                || !HasInteger(message["v"], 1)
                || message["success"] == null
                || message["success"].Type != JTokenType.Boolean)
            {
                return false;
            }
            bool success = message.Value<bool>("success");
            if (success)
            {
                string[] successKeys = request.IsKShop
                    ? new[] { "task", "callId", "success", "v", "decision", "reason",
                        "materialName", "catalogIndex", "entryId",
                        "category", "itemName", "recipeId", "recipeCategory", "recipeIndex" }
                    : request.IsProcurement
                    ? new[] { "task", "callId", "success", "v", "decision", "reason",
                        "materialName", "shopId", "catalogIndex",
                        "itemName", "recipeId", "category", "recipeIndex" }
                    : new[] { "task", "callId", "success", "v", "decision", "reason",
                        "materialSnapshotId", "materialName", "shopId", "catalogIndex",
                        "itemName" };
                if (!HasExactKeys(message, successKeys)
                    || !HasString(message["decision"], "allow")
                    || !HasString(message["reason"], request.IsKShop
                        ? "procurement_kshop_indexed_live_match"
                        : request.IsProcurement
                            ? "procurement_indexed_live_match"
                            : "indexed_live_match")
                    || !request.IsProcurement
                        && !HasString(message["materialSnapshotId"], request.MaterialSnapshotId)
                    || !HasString(message["materialName"], request.MaterialName)
                    || !HasShopCatalogIndex(
                        message["catalogIndex"],
                        request.CatalogIndex)
                    || !HasString(message["itemName"], request.MaterialName)
                    || request.IsKShop &&
                        (!HasString(message["entryId"], request.EntryId)
                        || !HasString(message["category"], request.KShopCategory)
                        || !HasString(message["recipeId"], request.RecipeId)
                        || !HasString(message["recipeCategory"], request.Category)
                        || !HasShopCatalogIndex(message["recipeIndex"], request.RecipeIndex))
                    || !request.IsKShop && !HasString(message["shopId"], request.ShopId)
                    || !request.IsKShop && request.IsProcurement &&
                        (!HasString(message["recipeId"], request.RecipeId)
                        || !HasString(message["category"], request.Category)
                        || !HasShopCatalogIndex(message["recipeIndex"], request.RecipeIndex)))
                {
                    return false;
                }
                result = new Result
                {
                    Kind = ResultKind.Allowed,
                    ItemName = request.MaterialName
                };
                return true;
            }

            if (!HasExactKeys(
                    message,
                    "task", "callId", "success", "v", "decision", "error"))
                return false;
            string decision = ReadString(message["decision"]);
            string error = ReadString(message["error"]);
            if (decision == "stale"
                && (error == "stale_snapshot"
                    || error == "source_not_current"
                    || error == "catalog_not_current"))
            {
                result = new Result { Kind = ResultKind.Stale, Error = error };
                return true;
            }
            if (decision == "deny"
                && (error == "invalid_payload"
                    || error == "authority_unavailable"
                    || error == "access_denied"))
            {
                result = new Result { Kind = ResultKind.Denied, Error = error };
                return true;
            }
            return false;
        }

        private static bool HasExactKeys(JObject value, params string[] keys)
        {
            if (value == null || value.Count != keys.Length) return false;
            var expected = new HashSet<string>(keys, StringComparer.Ordinal);
            foreach (JProperty property in value.Properties())
                if (!expected.Contains(property.Name)) return false;
            return true;
        }

        private static bool HasString(JToken token, string expected)
        {
            return token != null && token.Type == JTokenType.String
                && string.Equals(token.Value<string>(), expected, StringComparison.Ordinal);
        }

        private static string ReadString(JToken token)
        {
            return token != null && token.Type == JTokenType.String
                ? token.Value<string>()
                : null;
        }

        private static bool HasInteger(JToken token, int expected)
        {
            int value;
            return TryReadInt32(token, out value) && value == expected;
        }

        private static bool HasShopCatalogIndex(JToken token, int expected)
        {
            int value;
            return expected >= 0 && expected <= 10000
                && TryReadInt32(token, out value)
                && value == expected;
        }

        private static bool TryReadPositiveFid(JToken token, out int value)
        {
            return TryReadInt32(token, out value) && value >= 1;
        }

        private static bool TryReadInt32(JToken token, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate;
            try { candidate = token.Value<long>(); }
            catch { return false; }
            if (candidate < int.MinValue || candidate > int.MaxValue) return false;
            value = (int)candidate;
            return true;
        }
    }
}
