using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>crafting domain 的严格 WebView↔Flash callId 桥与提交对账门。</summary>
    public sealed class CraftingTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public string OwnerPanel;
            public string OwnerPanelInstanceId;
            public JObject NormalizedPayload;
            public bool IsWrite;
            public bool IsReconcileProbe;
            public int ReconcileEpoch;
            public int PreviewEpoch;
            public int MaterialsRequestEpoch;
            public PreviewAuthority ExpectedPreview;
        }

        private sealed class MaterialsSession
        {
            public string OwnerPanelInstanceId;
            public int Version;
            public string SnapshotId;
            public Dictionary<string, CatalogMaterialProof> Materials;
            public Dictionary<string, RegistryEntryProof> RecipePurposes;
            public Dictionary<string, RegistryEntryProof> DirectPurposes;
            public Dictionary<string, int> RecipePurposeOrder;
            public Dictionary<string, int> DirectPurposeOrder;
        }

        private sealed class CatalogMaterialProof
        {
            public string Name;
            public string DisplayName;
            public string Icon;
            public long Owned;
            public long SourceCount;
            public long DropVariantCount;
            public long UseCount;
            public long StructuredPurposeCount;
            public bool HasSourceSummary;
            public string[] RecipePurposeIds;
            public string[] DirectPurposeIds;
        }

        private sealed class RegistryEntryProof
        {
            public string Id;
            public string Label;
            public long Order;
        }

        private sealed class SourceOrderProof
        {
            public int KindOrder;
            public int CategoryOrder;
            public string PrimaryText;
            public int RewardSetOrder;
            public long NumericOrder;
        }

        private sealed class PreviewAuthority
        {
            public string OwnerPanelInstanceId;
            public string Token;
            public string Category;
            public int RecipeIndex;
            public int CraftCount;
            public JObject Output;
            public JObject AcceptedPlan;
        }

        private sealed class RecipeNavigationAuthority
        {
            public string OwnerPanelInstanceId;
            public string Category;
            public int RecipeIndex;
            public JArray Materials;
        }

        private const int DefaultTimeoutMs = 10000;
        private const long MaxSafeInteger = 9007199254740991L;
        private const int MaxMaterials = 4096;
        private const int MaxSources = 512;
        private const int MaxVariants = 128;
        private const int MaxUses = 1024;
        private const int MaxRecipeIngredients = 64;
        private const int MaxCraftingSources = 32;
        // Per catalog material/detail references. The taxonomy registry itself is
        // bounded by MaxTaxonomyEntries so future controlled entries remain data-driven.
        private const int MaxDirectPurposes = 128;
        private const int MaxTaxonomyEntries = 1024;
        private const int MaxInfrastructureProjects = 256;
        private const int MaxInfrastructureLevels = 128;
        private const string InfrastructurePurposeId = "system:infrastructure_upgrade";
        private static readonly Regex ValidCallId = new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidPanelInstanceId = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidToken = new Regex("^[A-Za-z0-9._-]{1,160}$", RegexOptions.Compiled);
        private static readonly HashSet<string> Categories = new HashSet<string>(StringComparer.Ordinal)
        {
            "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
            "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备"
        };
        private static readonly string[] CategoryOrder =
        {
            "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
            "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备"
        };
        private static readonly HashSet<string> AvailabilityCodes = new HashSet<string>(StringComparer.Ordinal)
        {
            "ready", "level_locked", "material_missing", "insufficient_money",
            "insufficient_kpoint", "inventory_full", "output_projection_failed"
        };
        private static readonly HashSet<string> StorageKinds = new HashSet<string>(StringComparer.Ordinal)
        {
            "bag", "drug", "bag_and_drug", "material_collection",
            "information_collection", "unavailable"
        };

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private string _writeState = "idle";
        private int _reconcileEpoch;
        private int _previewEpoch;
        private int _materialsRequestEpoch;
        private PreviewAuthority _previewAuthority;
        private RecipeNavigationAuthority _recipeNavigationAuthority;
        private MaterialsSession _materialsSession;
        private string _navigationOwnerPanel;
        private string _navigationOwnerPanelInstanceId;
        private string _navigationLeaseToken;
        private bool _navigationLeaseTransferred;
        private long _navigationGeneration;
        private bool _disposed;
        public CraftingTask(XmlSocketServer socket)
            : this(delegate { return socket != null && socket.IsClientReady; },
                   delegate(string payload) { return socket != null && socket.TrySend(payload); }, DefaultTimeoutMs) { }

        public CraftingTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs = DefaultTimeoutMs)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                timeoutMs,
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        internal string WriteState { get { lock (_lock) return _writeState; } }
        public void Dispose()
        {
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
                _navigationGeneration++;
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationOwnerPanel = null;
                _navigationOwnerPanelInstanceId = null;
                _recipeNavigationAuthority = null;
                _pendingCalls.Dispose();
            }
        }

        internal void BindMaterialShopNavigationOwner(
            string panelName,
            string panelInstanceId)
        {
            lock (_lock)
            {
                if (_disposed) return;
                if (string.Equals(_navigationOwnerPanel, panelName, StringComparison.Ordinal)
                    && string.Equals(
                        _navigationOwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationOwnerPanel = panelName;
                _navigationOwnerPanelInstanceId = panelInstanceId;
                _recipeNavigationAuthority = null;
                _navigationGeneration++;
            }
        }

        internal bool TryAcquireMaterialShopNavigationLease(
            string panelName,
            string panelInstanceId,
            string leaseToken,
            string materialSnapshotId,
            string materialName,
            out MaterialShopSettlementWitness witness)
        {
            witness = null;
            lock (_lock)
            {
                CatalogMaterialProof proof;
                if (_disposed
                    || string.IsNullOrEmpty(leaseToken)
                    || _navigationLeaseToken != null
                    || !string.Equals(panelName, "crafting", StringComparison.Ordinal)
                    || !string.Equals(_navigationOwnerPanel, panelName, StringComparison.Ordinal)
                    || !string.Equals(
                        _navigationOwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _pendingCalls.PendingCount != 0
                    || !string.Equals(_writeState, "idle", StringComparison.Ordinal)
                    || _materialsSession == null
                    || _materialsSession.Version != 2
                    || !string.Equals(
                        _materialsSession.OwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _materialsSession.SnapshotId,
                        materialSnapshotId,
                        StringComparison.Ordinal)
                    || _materialsSession.Materials == null
                    || !_materialsSession.Materials.TryGetValue(materialName, out proof))
                {
                    return false;
                }
                _navigationLeaseToken = leaseToken;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                witness = new MaterialShopSettlementWitness
                {
                    TaskName = "crafting",
                    LeaseToken = leaseToken,
                    OwnerPanel = panelName,
                    OwnerPanelInstanceId = panelInstanceId,
                    Generation = _navigationGeneration,
                    MaterialSnapshotId = materialSnapshotId,
                    MaterialName = materialName
                };
                return true;
            }
        }

        internal bool TryAcquireRecipeShopNavigationLease(
            string panelName,
            string panelInstanceId,
            string leaseToken,
            string category,
            int recipeIndex,
            string materialName,
            string shopId,
            int catalogIndex,
            bool isKShop,
            string entryId,
            string kshopCategory,
            out MaterialShopSettlementWitness witness)
        {
            witness = null;
            lock (_lock)
            {
                if (_disposed
                    || string.IsNullOrEmpty(leaseToken)
                    || _navigationLeaseToken != null
                    || !string.Equals(panelName, "crafting", StringComparison.Ordinal)
                    || !string.Equals(_navigationOwnerPanel, panelName, StringComparison.Ordinal)
                    || !string.Equals(
                        _navigationOwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || _pendingCalls.PendingCount != 0
                    || !string.Equals(_writeState, "idle", StringComparison.Ordinal)
                    || _recipeNavigationAuthority == null
                    || !string.Equals(
                        _recipeNavigationAuthority.OwnerPanelInstanceId,
                        panelInstanceId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _recipeNavigationAuthority.Category,
                        category,
                        StringComparison.Ordinal)
                    || _recipeNavigationAuthority.RecipeIndex != recipeIndex
                    || !HasRecipeNavigationSource(
                        _recipeNavigationAuthority.Materials,
                        materialName,
                        shopId,
                        catalogIndex,
                        isKShop,
                        entryId,
                        kshopCategory))
                {
                    return false;
                }
                _navigationLeaseToken = leaseToken;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                witness = new MaterialShopSettlementWitness
                {
                    TaskName = "crafting",
                    LeaseToken = leaseToken,
                    OwnerPanel = panelName,
                    OwnerPanelInstanceId = panelInstanceId,
                    Generation = _navigationGeneration,
                    MaterialName = materialName,
                    ShopId = shopId,
                    IsRecipeProcurement = true,
                    RecipeCategory = category,
                    RecipeIndex = recipeIndex,
                    CatalogIndex = catalogIndex,
                    IsKShop = isKShop,
                    EntryId = entryId,
                    KShopCategory = kshopCategory
                };
                return true;
            }
        }

        internal bool IsMaterialShopNavigationLeaseCurrent(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                bool common = witness != null
                    && !_disposed
                    && !_navigationLeaseTransferred
                    && string.Equals(witness.TaskName, "crafting", StringComparison.Ordinal)
                    && string.Equals(
                        witness.LeaseToken,
                        _navigationLeaseToken,
                        StringComparison.Ordinal)
                    && witness.Generation == _navigationGeneration
                    && string.Equals(
                        witness.OwnerPanel,
                        _navigationOwnerPanel,
                        StringComparison.Ordinal)
                    && string.Equals(
                        witness.OwnerPanelInstanceId,
                        _navigationOwnerPanelInstanceId,
                        StringComparison.Ordinal)
                    && _pendingCalls.PendingCount == 0
                    && string.Equals(_writeState, "idle", StringComparison.Ordinal);
                if (!common) return false;
                if (witness.IsRecipeProcurement)
                {
                    return _recipeNavigationAuthority != null
                        && string.Equals(
                            witness.OwnerPanelInstanceId,
                            _recipeNavigationAuthority.OwnerPanelInstanceId,
                            StringComparison.Ordinal)
                        && string.Equals(
                            witness.RecipeCategory,
                            _recipeNavigationAuthority.Category,
                            StringComparison.Ordinal)
                        && witness.RecipeIndex == _recipeNavigationAuthority.RecipeIndex
                        && HasRecipeNavigationSource(
                            _recipeNavigationAuthority.Materials,
                            witness.MaterialName,
                            witness.ShopId,
                            witness.CatalogIndex,
                            witness.IsKShop,
                            witness.EntryId,
                            witness.KShopCategory);
                }
                return _materialsSession != null
                    && _materialsSession.Version == 2
                    && string.Equals(
                        witness.MaterialSnapshotId,
                        _materialsSession.SnapshotId,
                        StringComparison.Ordinal)
                    && _materialsSession.Materials != null
                    && _materialsSession.Materials.ContainsKey(witness.MaterialName);
            }
        }

        internal bool ReleaseMaterialShopNavigationLease(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                if (!MatchesMaterialShopNavigationLeaseLocked(witness)) return false;
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationGeneration++;
                return true;
            }
        }

        internal bool TransferMaterialShopNavigationLease(
            MaterialShopSettlementWitness witness)
        {
            lock (_lock)
            {
                if (!MatchesMaterialShopNavigationLeaseLocked(witness)
                    || _navigationLeaseTransferred) return false;
                _navigationLeaseTransferred = true;
                return true;
            }
        }

        private bool MatchesMaterialShopNavigationLeaseLocked(
            MaterialShopSettlementWitness witness)
        {
            return witness != null
                && string.Equals(witness.TaskName, "crafting", StringComparison.Ordinal)
                && string.Equals(
                    witness.LeaseToken,
                    _navigationLeaseToken,
                    StringComparison.Ordinal)
                && witness.Generation == _navigationGeneration;
        }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            string callId = parsed != null ? ReadExactString(parsed["callId"]) : null;
            string ownerPanel = parsed != null ? ReadExactString(parsed["panel"]) : null;
            string ownerPanelInstanceId = parsed != null
                ? ReadExactString(parsed["panelInstanceId"]) : null;
            if (!string.Equals(ownerPanel, "crafting", StringComparison.Ordinal)
                || string.IsNullOrEmpty(ownerPanelInstanceId)
                || !ValidPanelInstanceId.IsMatch(ownerPanelInstanceId)) return;
            if (string.IsNullOrEmpty(callId)) return;
            if (!ValidCallId.IsMatch(callId))
            {
                RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_call_id");
                return;
            }
            if (!string.Equals(ReadExactString(parsed["domain"]), "crafting", StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_domain");
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_cmd");
                return;
            }
            JObject payload = parsed["payload"] as JObject;
            JObject normalized;
            if (payload == null || !TryNormalizePayload(cmd, payload, out normalized))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_payload");
                return;
            }
            if (!_pendingCalls.IsReady())
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                if (_navigationLeaseToken != null)
                {
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "busy");
                    return;
                }
                string materialsSessionError;
                if (!IsMaterialsSessionRequestAllowedLocked(
                        cmd, ownerPanelInstanceId, normalized, out materialsSessionError))
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId,
                        materialsSessionError);
                    return;
                }
                if (isWrite && _writeState != "idle")
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId,
                        _writeState == "needs_reconcile" ? "reconcile_required" : "busy");
                    return;
                }
                PreviewAuthority expectedPreview = null;
                if (cmd == "commit")
                {
                    if (!TryConsumePreviewAuthorityLocked(
                            ownerPanelInstanceId, normalized, out expectedPreview))
                    {
                        if (!_pendingCalls.TryRememberRejected(callId)) return;
                        RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "stale_state");
                        return;
                    }
                    _recipeNavigationAuthority = null;
                }
                else if (cmd == "preview" || cmd == "snapshot")
                {
                    _previewEpoch++;
                    _previewAuthority = null;
                    _recipeNavigationAuthority = null;
                }
                else if (cmd == "setPlan") _recipeNavigationAuthority = null;
                int materialsRequestEpoch = 0;
                if (cmd == "materials")
                {
                    _materialsRequestEpoch++;
                    materialsRequestEpoch = _materialsRequestEpoch;
                }
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        OwnerPanel = ownerPanel,
                        OwnerPanelInstanceId = ownerPanelInstanceId,
                        NormalizedPayload = (JObject)normalized.DeepClone(),
                        IsWrite = isWrite,
                        IsReconcileProbe = cmd == "preview"
                            && _writeState == "needs_reconcile",
                        ReconcileEpoch = _reconcileEpoch,
                        PreviewEpoch = _previewEpoch,
                        MaterialsRequestEpoch = materialsRequestEpoch,
                        ExpectedPreview = expectedPreview
                    },
                    out fid)) return;
                _navigationGeneration++;
                if (isWrite) _writeState = "write_pending";
            }

            JObject flash = PanelBridge.BuildFlashCommand(action, fid, normalized);
            string json = flash.ToString(Formatting.None);
            LogManager.Log(AuthorityLogFormatter.FormatAuthorityFlashCallBound(
                "CraftingTask", callId, fid, ownerPanel, ownerPanelInstanceId,
                cmd, action));
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand(
                "CraftingTask", flash));
            _pendingCalls.Send(fid, json + "\0");
        }

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            int fid;
            if (msg == null || !TryReadInteger(msg["callId"], 1, int.MaxValue, out fid))
            {
                if (respond != null) respond(null);
                return;
            }
            PendingRequest entry;
            PanelPendingCall<PendingRequest> pendingCall;
            bool valid;
            bool definitiveWrite;
            JObject authority;
            MaterialsSession selectedMaterialsSession;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out pendingCall))
                {
                    if (respond != null) respond(null);
                    return;
                }
                _navigationGeneration++;
                entry = pendingCall.Context;
                valid = TrySanitizeResponse(
                    msg, entry, _materialsSession, out authority, out selectedMaterialsSession);
                if (valid && selectedMaterialsSession != null
                    && entry.MaterialsRequestEpoch == _materialsRequestEpoch)
                    _materialsSession = selectedMaterialsSession;
                if (entry.WebCmd == "preview" && entry.PreviewEpoch == _previewEpoch)
                {
                    UpdateRecipeNavigationAuthorityLocked(msg, entry, valid);
                    UpdatePreviewAuthorityLocked(msg, entry, valid);
                }
                definitiveWrite = entry.IsWrite && valid && IsDefinitiveWriteResponse(msg);
                if (entry.IsWrite)
                {
                    if (definitiveWrite) _writeState = "idle";
                    else EnterNeedsReconcileLocked();
                }
                else if (entry.IsReconcileProbe
                    && entry.ReconcileEpoch == _reconcileEpoch
                    && entry.WebCmd == "preview" && valid && msg.Value<bool?>("success") == true
                    && _writeState == "needs_reconcile") _writeState = "idle";
            }
            JObject web = valid
                ? authority
                : new JObject { ["success"] = false, ["error"] = "malformed_response" };
            web["type"] = "panel_resp";
            web["domain"] = "crafting";
            web["panel"] = entry.OwnerPanel;
            web["panelInstanceId"] = entry.OwnerPanelInstanceId;
            web["cmd"] = entry.WebCmd;
            web["callId"] = pendingCall.WebCallId;
            if (entry.IsWrite && !definitiveWrite) web["requiresReconcile"] = true;
            PostToWeb(web.ToString(Formatting.None));
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                _navigationGeneration++;
                _navigationLeaseToken = null;
                _navigationLeaseTransferred = false;
                _navigationOwnerPanel = null;
                _navigationOwnerPanelInstanceId = null;
                _previewEpoch++;
                _previewAuthority = null;
                _recipeNavigationAuthority = null;
                _materialsRequestEpoch++;
                _materialsSession = null;
                _pendingCalls.Clear();
            }
        }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "craftingSnapshot"; return true;
                case "materials": action = "craftingMaterials"; return true;
                case "materialDetail": action = "craftingMaterialDetail"; return true;
                case "preview": action = "craftingPreview"; return true;
                case "tooltip": action = "craftingTooltip"; return true;
                case "setPlan": action = "craftingPlanSet"; isWrite = true; return true;
                case "commit": action = "craftingCommit"; isWrite = true; return true;
                default: action = null; return false;
            }
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = null;
            int version;
            if (!TryReadProtocolVersion(payload != null ? payload["v"] : null, out version))
                return false;
            normalized = new JObject { ["v"] = version };
            if (cmd == "materials")
                return (version == 1 || version == 2) && HasExactKeys(payload, "v");
            if (cmd == "materialDetail")
            {
                bool exact = version == 1
                    ? HasExactKeys(payload, "v", "itemName")
                    : version == 2 && HasExactKeys(payload, "v", "itemName", "snapshotId");
                if (!exact) return false;
                string itemName = ReadExactString(payload["itemName"]);
                if (!IsIdentityText(itemName, 128)) return false;
                normalized["itemName"] = itemName;
                if (version == 2)
                {
                    string snapshotId = ReadExactString(payload["snapshotId"]);
                    if (!IsIdentityText(snapshotId, 256)) return false;
                    normalized["snapshotId"] = snapshotId;
                }
                return true;
            }
            if (version != 1) return false;
            if (cmd == "tooltip")
            {
                if (!HasExactKeys(payload, "v", "itemName")) return false;
                string itemName = ReadExactString(payload["itemName"]);
                if (!IsIdentityText(itemName, 128)) return false;
                normalized["itemName"] = itemName;
                return true;
            }
            if (cmd == "setPlan")
            {
                if (version != 1 || !HasExactKeys(payload, "v", "recipeId",
                        "plannedCrafts", "expectedRevision")) return false;
                string recipeId = ReadExactString(payload["recipeId"]);
                int plannedCrafts;
                long expectedRevision;
                if (!ProcurementProjectionValidator.IsRecipeId(payload["recipeId"])
                    || !TryReadInteger(payload["plannedCrafts"], 0, 99, out plannedCrafts)
                    || !TryReadLongInteger(payload["expectedRevision"], 0,
                        9007199254740990L, out expectedRevision)) return false;
                normalized["recipeId"] = recipeId;
                normalized["plannedCrafts"] = plannedCrafts;
                normalized["expectedRevision"] = expectedRevision;
                return true;
            }
            bool materialNavigationSnapshot = cmd == "snapshot"
                && HasExactKeys(payload, "v", "category", "materialSnapshotId");
            if (cmd == "snapshot"
                && !materialNavigationSnapshot
                && !HasExactKeys(payload, "v", "category")) return false;
            if (cmd == "preview" && !HasExactKeys(
                    payload, "v", "category", "recipeIndex", "craftCount")) return false;
            if (cmd == "commit" && !HasExactKeys(
                    payload, "v", "category", "expectedCraftToken")) return false;
            string category = ReadExactString(payload["category"]);
            if (!Categories.Contains(category)) return false;
            normalized["category"] = category;
            if (cmd == "snapshot")
            {
                if (materialNavigationSnapshot)
                {
                    string materialSnapshotId = ReadExactString(payload["materialSnapshotId"]);
                    if (!IsIdentityText(materialSnapshotId, 256)) return false;
                    normalized["materialSnapshotId"] = materialSnapshotId;
                }
                return true;
            }
            if (cmd == "preview")
            {
                int recipeIndex;
                int craftCount;
                if (!TryReadInteger(payload["recipeIndex"], 0, 999, out recipeIndex)) return false;
                if (!TryReadInteger(payload["craftCount"], 1, 99, out craftCount)) return false;
                normalized["recipeIndex"] = recipeIndex;
                normalized["craftCount"] = craftCount;
                return true;
            }
            if (cmd == "commit")
            {
                string token = ReadExactString(payload["expectedCraftToken"]);
                if (string.IsNullOrEmpty(token) || !ValidToken.IsMatch(token)) return false;
                normalized["expectedCraftToken"] = token;
                return true;
            }
            return false;
        }

        private static bool TryReadInteger(JToken token, int min, int max, out int value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate = token.Value<long>();
            if (candidate < min || candidate > max) return false;
            value = (int)candidate;
            return true;
        }

        private static bool IsSafeText(string value, int max)
        {
            if (string.IsNullOrWhiteSpace(value) || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool TryReadLongInteger(
            JToken token, long min, long max, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.ToObject<long>(); }
            catch { return false; }
            return value >= min && value <= max;
        }

        private static bool IsIdentityText(string value, int max)
        {
            return IsSafeText(value, max)
                && !string.Equals(value.Trim(), "undefined", StringComparison.OrdinalIgnoreCase);
        }

        private bool IsMaterialsSessionRequestAllowedLocked(
            string cmd,
            string ownerPanelInstanceId,
            JObject normalized,
            out string error)
        {
            error = "invalid_payload";
            bool materialNavigationSnapshot = cmd == "snapshot"
                && normalized != null
                && normalized["materialSnapshotId"] != null;
            if (cmd != "materials" && cmd != "materialDetail"
                && !materialNavigationSnapshot) return true;
            int version;
            if (!TryReadProtocolVersion(normalized != null ? normalized["v"] : null, out version))
                return false;
            if (_materialsSession != null
                && !string.Equals(_materialsSession.OwnerPanelInstanceId,
                    ownerPanelInstanceId, StringComparison.Ordinal))
                _materialsSession = null;
            if (cmd == "materials")
                return _materialsSession == null || _materialsSession.Version == version;

            if (materialNavigationSnapshot)
            {
                if (_materialsSession == null || _materialsSession.Version != 2
                    || !string.Equals(
                        ReadExactString(normalized["materialSnapshotId"]),
                        _materialsSession.SnapshotId,
                        StringComparison.Ordinal))
                {
                    error = "stale_snapshot";
                    return false;
                }
                return true;
            }

            // The pre-v2 Web did not expose an explicit catalog-session token. Keep
            // an unbound v1 detail request legal for that exact legacy wire only.
            if (version == 1 && _materialsSession == null) return true;
            if (_materialsSession == null)
            {
                error = "stale_snapshot";
                return false;
            }
            if (_materialsSession.Version != version) return false;
            if (version == 2
                && !string.Equals(ReadExactString(normalized["snapshotId"]),
                    _materialsSession.SnapshotId, StringComparison.Ordinal))
            {
                error = "stale_snapshot";
                return false;
            }
            return true;
        }

        private static bool IsV2MaterialDetail(PendingRequest entry)
        {
            int version;
            return entry != null
                && entry.WebCmd == "materialDetail"
                && TryReadProtocolVersion(
                    entry.NormalizedPayload != null ? entry.NormalizedPayload["v"] : null,
                    out version)
                && version == 2;
        }

        private static bool IsMaterialNavigationSnapshot(PendingRequest entry)
        {
            return entry != null
                && string.Equals(entry.WebCmd, "snapshot", StringComparison.Ordinal)
                && entry.NormalizedPayload != null
                && IsIdentityText(
                    ReadExactString(entry.NormalizedPayload["materialSnapshotId"]), 256);
        }

        private bool TryConsumePreviewAuthorityLocked(
            string ownerPanelInstanceId, JObject normalized, out PreviewAuthority authority)
        {
            authority = _previewAuthority;
            if (authority == null || normalized == null
                || !string.Equals(authority.OwnerPanelInstanceId, ownerPanelInstanceId, StringComparison.Ordinal)
                || !string.Equals(authority.Category,
                    ReadExactString(normalized["category"]), StringComparison.Ordinal)
                || !string.Equals(authority.Token,
                    ReadExactString(normalized["expectedCraftToken"]), StringComparison.Ordinal))
            {
                authority = null;
                return false;
            }
            _previewAuthority = null;
            return true;
        }

        private void UpdatePreviewAuthorityLocked(JObject msg, PendingRequest entry, bool valid)
        {
            _previewAuthority = null;
            if (!valid || msg.Value<bool?>("success") != true
                || msg.Value<bool?>("canCommit") != true) return;
            int recipeIndex;
            int craftCount;
            if (!TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)) return;
            _previewAuthority = new PreviewAuthority
            {
                OwnerPanelInstanceId = entry.OwnerPanelInstanceId,
                Token = ReadExactString(msg["craftToken"]),
                Category = ReadExactString(msg["category"]),
                RecipeIndex = recipeIndex,
                CraftCount = craftCount,
                Output = (JObject)msg["output"].DeepClone(),
                AcceptedPlan = (JObject)msg["acceptedPlan"].DeepClone()
            };
        }

        private void UpdateRecipeNavigationAuthorityLocked(
            JObject msg, PendingRequest entry, bool valid)
        {
            _recipeNavigationAuthority = null;
            if (!valid || msg.Value<bool?>("success") != true || entry == null) return;
            int recipeIndex;
            JArray materials = msg["materials"] as JArray;
            if (!TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || materials == null) return;
            _recipeNavigationAuthority = new RecipeNavigationAuthority
            {
                OwnerPanelInstanceId = entry.OwnerPanelInstanceId,
                Category = ReadExactString(msg["category"]),
                RecipeIndex = recipeIndex,
                Materials = (JArray)materials.DeepClone()
            };
        }

        private static bool HasRecipeNavigationSource(
            JArray materials,
            string materialName,
            string shopId,
            int catalogIndex,
            bool isKShop,
            string entryId,
            string kshopCategory)
        {
            if (materials == null || string.IsNullOrEmpty(materialName)) return false;
            int matches = 0;
            foreach (JToken materialToken in materials)
            {
                JObject material = materialToken as JObject;
                JObject demand = material != null ? material["procurement"] as JObject : null;
                JArray sources = demand != null ? demand["sources"] as JArray : null;
                if (!string.Equals(
                        ReadExactString(material != null ? material["name"] : null),
                        materialName,
                        StringComparison.Ordinal)
                    || demand == null
                    || demand.Value<long?>("obtainMissing") <= 0
                    || sources == null) continue;
                foreach (JToken sourceToken in sources)
                {
                    JObject source = sourceToken as JObject;
                    if (source == null
                        || source.Value<int?>("catalogIndex") != catalogIndex) continue;
                    bool exact = isKShop
                        ? string.Equals(ReadExactString(source["kind"]), "kshop",
                                StringComparison.Ordinal)
                            && string.Equals(ReadExactString(source["entryId"]), entryId,
                                StringComparison.Ordinal)
                            && string.Equals(ReadExactString(source["category"]), kshopCategory,
                                StringComparison.Ordinal)
                        : string.Equals(ReadExactString(source["kind"]), "npcshop",
                                StringComparison.Ordinal)
                            && string.Equals(ReadExactString(source["shopId"]), shopId,
                                StringComparison.Ordinal);
                    if (exact) matches++;
                }
            }
            return matches == 1;
        }

        private static bool TrySanitizeResponse(
            JObject msg,
            PendingRequest entry,
            MaterialsSession materialsSession,
            out JObject sanitized,
            out MaterialsSession selectedMaterialsSession)
        {
            sanitized = null;
            selectedMaterialsSession = null;
            if (msg == null
                || !string.Equals(ReadExactString(msg["task"]), "crafting_response", StringComparison.Ordinal)
                || msg["callId"] == null || msg["callId"].Type != JTokenType.Integer
                || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            if (!msg.Value<bool>("success"))
            {
                string error = ReadExactString(msg["error"]);
                if (!HasExactKeys(msg, "task", "callId", "success", "error")
                    || !IsSafeText(error, 128)
                    || (string.Equals(error, "stale_snapshot", StringComparison.Ordinal)
                        && !IsV2MaterialDetail(entry)
                        && !IsMaterialNavigationSnapshot(entry))) return false;
                sanitized = new JObject { ["success"] = false, ["error"] = error };
                return true;
            }

            bool authoritative;
            switch (entry.WebCmd)
            {
                case "snapshot": authoritative = IsAuthoritativeSnapshot(msg, entry); break;
                case "materials":
                    authoritative = IsAuthoritativeMaterials(
                        msg, entry, materialsSession, out selectedMaterialsSession);
                    break;
                case "materialDetail":
                    authoritative = IsAuthoritativeMaterialDetail(msg, entry, materialsSession);
                    break;
                case "preview": authoritative = IsAuthoritativePreview(msg, entry); break;
                case "tooltip": authoritative = IsAuthoritativeTooltip(msg, entry); break;
                case "setPlan": authoritative = IsAuthoritativeSetPlan(msg, entry); break;
                case "commit": authoritative = IsAuthoritativeCommit(msg, entry); break;
                default: authoritative = false; break;
            }
            if (!authoritative) return false;

            sanitized = (JObject)msg.DeepClone();
            sanitized.Remove("task");
            sanitized.Remove("callId");
            if (entry.WebCmd == "tooltip")
            {
                // AS2 的 tooltip profile 仍使用历史 displayname；只在这一条 Host
                // 边界翻译，Web 不再猜测多种展示字段。
                sanitized["displayName"] = sanitized["displayname"];
                sanitized.Remove("displayname");
            }
            return true;
        }

        private static bool IsAuthoritativeSnapshot(JObject msg, PendingRequest entry)
        {
            var recipes = msg["recipes"] as JArray;
            string gender = ReadExactString(msg["gender"]);
            if (!HasExactResponseKeys(msg, "v", "category", "gender", "recipes",
                    "balance", "skills", "procurement", "note")
                || !HasProtocolVersion(msg)
                || !MatchesSelector(msg, entry, "category")
                || recipes == null || !IsBalance(msg["balance"] as JObject)
                || !IsSkills(msg["skills"] as JObject)
                || !ProcurementProjectionValidator.IsPlanSummary(msg["procurement"] as JObject)
                || !IsSafeOptionalText(ReadExactString(msg["note"]), 2000)
                || (gender != "男" && gender != "女")) return false;
            var seenIndexes = new HashSet<int>();
            var seenRecipeIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in recipes)
            {
                var recipe = token as JObject;
                var output = recipe != null ? recipe["output"] as JObject : null;
                var baseCost = recipe != null ? recipe["baseCost"] as JObject : null;
                int recipeIndex;
                int materialCount;
                if (recipe == null
                    || !HasExactKeys(recipe, "recipeId", "recipeIndex", "title", "output",
                        "owned", "plannedCrafts", "baseCost", "materialCount",
                        "batchEligible", "canCraftOne", "availability")
                    || !ProcurementProjectionValidator.IsRecipeId(recipe["recipeId"])
                    || !seenRecipeIds.Add(ReadExactString(recipe["recipeId"]))
                    || !TryReadInteger(recipe["recipeIndex"], 0, 999, out recipeIndex)
                    || !seenIndexes.Add(recipeIndex)
                    || !TryReadInteger(recipe["materialCount"], 0, 999, out materialCount)
                    || recipe["batchEligible"] == null || recipe["batchEligible"].Type != JTokenType.Boolean
                    || recipe["canCraftOne"] == null || recipe["canCraftOne"].Type != JTokenType.Boolean
                    || !IsIdentityText(ReadExactString(recipe["title"]), 256)
                    || !IsProjectedItem(output, false)
                    || !ProcurementProjectionValidator.IsOwnedSummary(recipe["owned"] as JObject)
                    || !TryReadInteger(recipe["plannedCrafts"], 0, 99, out materialCount)
                    || !IsCost(baseCost)) return false;
                string availability = ReadExactString(recipe["availability"]);
                bool canCraftOne = recipe.Value<bool>("canCraftOne");
                if (!AvailabilityCodes.Contains(availability)
                    || canCraftOne != string.Equals(availability, "ready", StringComparison.Ordinal)) return false;
            }
            return true;
        }

        private static bool IsAuthoritativeMaterials(
            JObject msg,
            PendingRequest entry,
            MaterialsSession currentSession,
            out MaterialsSession selectedSession)
        {
            selectedSession = null;
            int requestVersion;
            int responseVersion;
            if (entry == null
                || !TryReadProtocolVersion(entry.NormalizedPayload["v"], out requestVersion)
                || !TryReadProtocolVersion(msg != null ? msg["v"] : null, out responseVersion))
                return false;
            if (currentSession != null)
            {
                if (!string.Equals(currentSession.OwnerPanelInstanceId,
                        entry.OwnerPanelInstanceId, StringComparison.Ordinal)
                    || requestVersion != currentSession.Version
                    || responseVersion != currentSession.Version) return false;
            }
            else if (responseVersion != requestVersion
                && !(requestVersion == 2 && responseVersion == 1)) return false;

            if (responseVersion == 1)
            {
                if (!IsAuthoritativeMaterialsV1(msg)) return false;
                selectedSession = new MaterialsSession
                {
                    OwnerPanelInstanceId = entry.OwnerPanelInstanceId,
                    Version = 1
                };
                return true;
            }
            return TryBuildMaterialsSessionV2(msg, entry.OwnerPanelInstanceId, out selectedSession);
        }

        private static bool IsAuthoritativeMaterialsV1(JObject msg)
        {
            var materials = msg["materials"] as JArray;
            if (!HasExactResponseKeys(msg, "v", "view", "materials")
                || !HasProtocolVersion(msg)
                || !string.Equals(ReadExactString(msg["view"]), "materials", StringComparison.Ordinal)
                || materials == null) return false;
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in materials)
            {
                var material = token as JObject;
                int sourceCount;
                int useCount;
                string name = material != null ? ReadExactString(material["name"]) : null;
                if (material == null
                    || !HasExactKeys(material, "name", "displayName", "icon", "owned",
                        "sourceCount", "useCount", "hasSourceSummary")
                    || !IsIdentityTriple(material) || !names.Add(name)
                    || !IsNonNegativeNumber(material["owned"])
                    || !TryReadInteger(material["sourceCount"], 0, 100000, out sourceCount)
                    || !TryReadInteger(material["useCount"], 0, 100000, out useCount)
                    || material["hasSourceSummary"] == null
                    || material["hasSourceSummary"].Type != JTokenType.Boolean) return false;
            }
            return true;
        }

        private static bool IsAuthoritativeMaterialDetail(
            JObject msg, PendingRequest entry, MaterialsSession session)
        {
            int requestVersion;
            int responseVersion;
            if (entry == null
                || !TryReadProtocolVersion(entry.NormalizedPayload["v"], out requestVersion)
                || !TryReadProtocolVersion(msg != null ? msg["v"] : null, out responseVersion)
                || requestVersion != responseVersion) return false;
            if (session != null
                && (!string.Equals(session.OwnerPanelInstanceId,
                        entry.OwnerPanelInstanceId, StringComparison.Ordinal)
                    || session.Version != responseVersion)) return false;
            if (responseVersion == 1) return IsAuthoritativeMaterialDetailV1(msg, entry);
            return session != null && IsAuthoritativeMaterialDetailV2(msg, entry, session);
        }

        private static bool IsAuthoritativeMaterialDetailV1(JObject msg, PendingRequest entry)
        {
            var material = msg["material"] as JObject;
            var sources = msg["sources"] as JArray;
            var uses = msg["uses"] as JArray;
            if (!HasExactResponseKeys(msg, "v", "view", "material", "sources", "uses")
                || !HasProtocolVersion(msg)
                || !string.Equals(ReadExactString(msg["view"]), "materials", StringComparison.Ordinal)
                || material == null || sources == null || uses == null
                || !HasExactKeys(material, "name", "displayName", "icon", "description",
                    "owned", "sourceSummary")
                || !IsIdentityTriple(material)
                || !string.Equals(ReadExactString(material["name"]),
                    ReadExactString(entry.NormalizedPayload["itemName"]), StringComparison.Ordinal)
                || !IsSafeMultilineText(ReadExactString(material["description"]), 12000)
                || !IsSafeMultilineText(ReadExactString(material["sourceSummary"]), 20000)
                || !IsNonNegativeNumber(material["owned"])) return false;
            foreach (JToken token in sources)
            {
                if (!IsMaterialSource(token as JObject)) return false;
            }
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in uses)
            {
                var use = token as JObject;
                string name = use != null ? ReadExactString(use["name"]) : null;
                if (use == null
                    || !HasExactKeys(use, "name", "displayName", "icon", "itemKind", "category", "required")
                    || !IsIdentityTriple(use) || !names.Add(name)
                    || !IsItemKind(ReadExactString(use["itemKind"]))
                    || !IsSafeOptionalText(ReadExactString(use["category"]), 128)
                    || !IsNonNegativeNumber(use["required"])) return false;
            }
            return true;
        }

        private static bool TryBuildMaterialsSessionV2(
            JObject msg,
            string ownerPanelInstanceId,
            out MaterialsSession session)
        {
            session = null;
            var taxonomy = msg != null ? msg["taxonomy"] as JObject : null;
            var navigationAccess = msg != null ? msg["navigationAccess"] as JObject : null;
            var materials = msg != null ? msg["materials"] as JArray : null;
            string snapshotId = msg != null ? ReadExactString(msg["snapshotId"]) : null;
            Dictionary<string, RegistryEntryProof> recipePurposes;
            Dictionary<string, RegistryEntryProof> directPurposes;
            Dictionary<string, int> recipePurposeOrder;
            Dictionary<string, int> directPurposeOrder;
            if (!HasExactResponseKeys(msg, "v", "view", "snapshotId",
                    "navigationAccess", "taxonomy", "materials")
                || !HasProtocolVersion(msg, 2)
                || !string.Equals(ReadExactString(msg["view"]), "materials", StringComparison.Ordinal)
                || !IsIdentityText(snapshotId, 256)
                || navigationAccess == null
                || !HasExactKeys(navigationAccess, "shop", "crafting")
                || navigationAccess["shop"] == null
                || navigationAccess["shop"].Type != JTokenType.Boolean
                || navigationAccess["crafting"] == null
                || navigationAccess["crafting"].Type != JTokenType.Boolean
                || materials == null || materials.Count > MaxMaterials
                || !TryValidateTaxonomy(taxonomy,
                    out recipePurposes, out directPurposes,
                    out recipePurposeOrder, out directPurposeOrder)) return false;

            var materialProofs = new Dictionary<string, CatalogMaterialProof>(StringComparer.Ordinal);
            for (int index = 0; index < materials.Count; index++)
            {
                var material = materials[index] as JObject;
                string typeId = material != null ? ReadExactString(material["typeId"]) : null;
                bool equipmentMod = string.Equals(typeId, "equipment_mod", StringComparison.Ordinal);
                string[] expectedKeys = equipmentMod
                    ? new[] { "name", "displayName", "icon", "owned", "archiveOrder", "typeId",
                        "modFacetIds", "recipePurposeIds", "directPurposeIds",
                        "structuredPurposeCount", "sourceCount", "dropVariantCount", "useCount",
                        "hasSourceSummary" }
                    : new[] { "name", "displayName", "icon", "owned", "archiveOrder", "typeId",
                        "recipePurposeIds", "directPurposeIds", "structuredPurposeCount",
                        "sourceCount", "dropVariantCount", "useCount", "hasSourceSummary" };
                long owned;
                long archiveOrder;
                long structuredPurposeCount;
                long sourceCount;
                long dropVariantCount;
                long useCount;
                string[] recipePurposeIds;
                string[] directPurposeIds;
                string name = material != null ? ReadExactString(material["name"]) : null;
                if (material == null || !HasExactKeys(material, expectedKeys)
                    || !IsIdentityTriple(material) || materialProofs.ContainsKey(name)
                    || (typeId != "equipment_mod" && typeId != "food" && typeId != "general")
                    || !TryReadNni(material["owned"], out owned)
                    || !TryReadNni(material["archiveOrder"], out archiveOrder)
                    || archiveOrder != index
                    || !TryReadNni(material["structuredPurposeCount"], out structuredPurposeCount)
                    || !TryReadNni(material["sourceCount"], out sourceCount)
                    || !TryReadNni(material["dropVariantCount"], out dropVariantCount)
                    || !TryReadNni(material["useCount"], out useCount)
                    || material["hasSourceSummary"] == null
                    || material["hasSourceSummary"].Type != JTokenType.Boolean
                    || !TryValidatePurposeIds(material["recipePurposeIds"],
                        recipePurposes, recipePurposeOrder, MaxTaxonomyEntries, out recipePurposeIds)
                    || !TryValidatePurposeIds(material["directPurposeIds"],
                        directPurposes, directPurposeOrder, MaxDirectPurposes, out directPurposeIds)
                    || structuredPurposeCount != useCount + directPurposeIds.Length
                    || (equipmentMod && !IsCanonicalModFacetIds(material["modFacetIds"] as JObject)))
                    return false;
                materialProofs.Add(name, new CatalogMaterialProof
                {
                    Name = name,
                    DisplayName = ReadExactString(material["displayName"]),
                    Icon = ReadExactString(material["icon"]),
                    Owned = owned,
                    SourceCount = sourceCount,
                    DropVariantCount = dropVariantCount,
                    UseCount = useCount,
                    StructuredPurposeCount = structuredPurposeCount,
                    HasSourceSummary = material.Value<bool>("hasSourceSummary"),
                    RecipePurposeIds = recipePurposeIds,
                    DirectPurposeIds = directPurposeIds
                });
            }
            session = new MaterialsSession
            {
                OwnerPanelInstanceId = ownerPanelInstanceId,
                Version = 2,
                SnapshotId = snapshotId,
                Materials = materialProofs,
                RecipePurposes = recipePurposes,
                DirectPurposes = directPurposes,
                RecipePurposeOrder = recipePurposeOrder,
                DirectPurposeOrder = directPurposeOrder
            };
            return true;
        }

        private static bool TryValidateTaxonomy(
            JObject taxonomy,
            out Dictionary<string, RegistryEntryProof> recipePurposes,
            out Dictionary<string, RegistryEntryProof> directPurposes,
            out Dictionary<string, int> recipePurposeOrder,
            out Dictionary<string, int> directPurposeOrder)
        {
            recipePurposes = null;
            directPurposes = null;
            recipePurposeOrder = null;
            directPurposeOrder = null;
            if (taxonomy == null
                || !HasExactKeys(taxonomy, "version", "roots", "types", "modAxes",
                    "recipePurposes", "directPurposes", "fallback")
                || !IsExactInteger(taxonomy["version"], 1)) return false;
            var roots = taxonomy["roots"] as JArray;
            var types = taxonomy["types"] as JArray;
            var axes = taxonomy["modAxes"] as JArray;
            var recipes = taxonomy["recipePurposes"] as JArray;
            var directs = taxonomy["directPurposes"] as JArray;
            var fallback = taxonomy["fallback"] as JObject;
            if (!IsExactRegistry(roots, new[]
                {
                    new[] { "type", "类型" }, new[] { "purpose", "用途" }
                })
                || !IsExactRegistry(types, new[]
                {
                    new[] { "equipment_mod", "改装材料" },
                    new[] { "food", "食材" }, new[] { "general", "通用材料" }
                })
                || !IsCanonicalModAxes(axes)
                || recipes == null || recipes.Count != CategoryOrder.Length
                || directs == null || directs.Count == 0
                || fallback == null
                || !HasExactKeys(fallback, "id", "label", "order")
                || ReadExactString(fallback["id"]) != "unstructured"
                || ReadExactString(fallback["label"]) != "尚未结构化用途"
                || !IsExactInteger(fallback["order"], 2147483647)) return false;

            recipePurposes = new Dictionary<string, RegistryEntryProof>(StringComparer.Ordinal);
            recipePurposeOrder = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int index = 0; index < recipes.Count; index++)
            {
                var entry = recipes[index] as JObject;
                string id = "recipe:" + CategoryOrder[index];
                if (!IsExactRegistryEntry(entry, id, CategoryOrder[index], index)) return false;
                recipePurposes.Add(id, ToRegistryProof(entry));
                recipePurposeOrder.Add(id, index);
            }
            directPurposes = new Dictionary<string, RegistryEntryProof>(StringComparer.Ordinal);
            directPurposeOrder = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int index = 0; index < directs.Count; index++)
            {
                var direct = directs[index] as JObject;
                string id = direct != null ? ReadExactString(direct["id"]) : null;
                string label = direct != null ? ReadExactString(direct["label"]) : null;
                if (direct == null || !HasExactKeys(direct, "id", "label", "order")
                    || !IsIdentityText(id, 256) || !IsIdentityText(label, 512)
                    || !IsExactInteger(direct["order"], index)
                    || directPurposes.ContainsKey(id)) return false;
                if (index == 0 && (id != "system:equipment_tuning" || label != "装备改装"))
                    return false;
                directPurposes.Add(id, ToRegistryProof(direct));
                directPurposeOrder.Add(id, index);
            }
            int taxonomyEntryCount = roots.Count + types.Count + axes.Count
                + recipes.Count + directs.Count + 1;
            foreach (JToken axisToken in axes)
                taxonomyEntryCount += ((JArray)axisToken["values"]).Count;
            return taxonomyEntryCount <= MaxTaxonomyEntries;
        }

        private static bool IsCanonicalModAxes(JArray axes)
        {
            if (axes == null || axes.Count != 3) return false;
            var grade = axes[0] as JObject;
            var scope = axes[1] as JObject;
            var role = axes[2] as JObject;
            return IsCanonicalAxisHeader(grade, "grade", "档级", 0)
                && IsExactGradeValues(grade["values"] as JArray)
                && IsCanonicalAxisHeader(scope, "scope", "适用范围", 1)
                && IsExactRegistry(scope["values"] as JArray, new[]
                {
                    new[] { "armor", "防具" }, new[] { "firearm", "枪械" },
                    new[] { "blade", "刀具" }, new[] { "fist", "拳套" },
                    new[] { "universal", "通用" }, new[] { "underbarrel", "下挂武器" }
                })
                && IsCanonicalAxisHeader(role, "role", "定位", 2)
                && IsExactRoleValues(role["values"] as JArray);
        }

        private static bool IsCanonicalAxisHeader(
            JObject axis, string id, string label, int order)
        {
            return axis != null && HasExactKeys(axis, "id", "label", "order", "values")
                && ReadExactString(axis["id"]) == id
                && ReadExactString(axis["label"]) == label
                && IsExactInteger(axis["order"], order)
                && axis["values"] is JArray;
        }

        private static bool IsExactGradeValues(JArray values)
        {
            string[][] expected =
            {
                new[] { "low", "低级", "#006600" },
                new[] { "medium", "中等", "#996600" },
                new[] { "high", "高等", "#0099FF" },
                new[] { "special", "特殊", "#FFFF00" }
            };
            if (values == null || values.Count != expected.Length) return false;
            for (int index = 0; index < expected.Length; index++)
            {
                var value = values[index] as JObject;
                if (value == null || !HasExactKeys(value, "id", "label", "order", "color")
                    || ReadExactString(value["id"]) != expected[index][0]
                    || ReadExactString(value["label"]) != expected[index][1]
                    || !IsExactInteger(value["order"], index)
                    || ReadExactString(value["color"]) != expected[index][2]) return false;
            }
            return true;
        }

        private static bool IsExactRoleValues(JArray values)
        {
            string[][] expected =
            {
                new[] { "firepower", "火力", "triangle-solid" },
                new[] { "precision", "精准与操控", "triangle-outline" },
                new[] { "stability", "稳定与防护", "square-outline" },
                new[] { "sustain", "续航", "circle-outline" },
                new[] { "utility", "结构与功能", "diamond-outline" },
                new[] { "mechanism", "特殊机制", "star-solid" }
            };
            if (values == null || values.Count != expected.Length) return false;
            for (int index = 0; index < expected.Length; index++)
            {
                var value = values[index] as JObject;
                if (value == null || !HasExactKeys(value, "id", "label", "order", "symbol")
                    || ReadExactString(value["id"]) != expected[index][0]
                    || ReadExactString(value["label"]) != expected[index][1]
                    || !IsExactInteger(value["order"], index)
                    || ReadExactString(value["symbol"]) != expected[index][2]) return false;
            }
            return true;
        }

        private static bool IsExactRegistry(JArray entries, string[][] expected)
        {
            if (entries == null || entries.Count != expected.Length || entries.Count == 0)
                return false;
            for (int index = 0; index < expected.Length; index++)
                if (!IsExactRegistryEntry(
                        entries[index] as JObject, expected[index][0], expected[index][1], index))
                    return false;
            return true;
        }

        private static bool IsExactRegistryEntry(
            JObject entry, string id, string label, int order)
        {
            return entry != null && HasExactKeys(entry, "id", "label", "order")
                && IsIdentityText(ReadExactString(entry["id"]), 256)
                && IsIdentityText(ReadExactString(entry["label"]), 512)
                && ReadExactString(entry["id"]) == id
                && ReadExactString(entry["label"]) == label
                && IsExactInteger(entry["order"], order);
        }

        private static RegistryEntryProof ToRegistryProof(JObject entry)
        {
            return new RegistryEntryProof
            {
                Id = ReadExactString(entry["id"]),
                Label = ReadExactString(entry["label"]),
                Order = entry.Value<long>("order")
            };
        }

        private static bool IsCanonicalModFacetIds(JObject facets)
        {
            if (facets == null || !HasExactKeys(facets, "grade", "scope", "role"))
                return false;
            string grade = ReadExactString(facets["grade"]);
            string scope = ReadExactString(facets["scope"]);
            string role = ReadExactString(facets["role"]);
            return (grade == "low" || grade == "medium" || grade == "high" || grade == "special")
                && (scope == "armor" || scope == "firearm" || scope == "blade"
                    || scope == "fist" || scope == "universal" || scope == "underbarrel")
                && (role == "firepower" || role == "precision" || role == "stability"
                    || role == "sustain" || role == "utility" || role == "mechanism");
        }

        private static bool TryValidatePurposeIds(
            JToken token,
            Dictionary<string, RegistryEntryProof> registry,
            Dictionary<string, int> registryOrder,
            int maximum,
            out string[] ids)
        {
            ids = null;
            var values = token as JArray;
            if (values == null || values.Count > maximum) return false;
            ids = new string[values.Count];
            var seen = new HashSet<string>(StringComparer.Ordinal);
            int previousOrder = -1;
            for (int index = 0; index < values.Count; index++)
            {
                string id = ReadExactString(values[index]);
                int order;
                if (!IsIdentityText(id, 256) || !seen.Add(id)
                    || registry == null || !registry.ContainsKey(id)
                    || registryOrder == null || !registryOrder.TryGetValue(id, out order)
                    || order <= previousOrder) return false;
                previousOrder = order;
                ids[index] = id;
            }
            return true;
        }

        private static bool IsAuthoritativeMaterialDetailV2(
            JObject msg, PendingRequest entry, MaterialsSession session)
        {
            if (msg == null || entry == null || entry.NormalizedPayload == null
                || session == null || session.Materials == null) return false;
            var material = msg != null ? msg["material"] as JObject : null;
            var sources = msg != null ? msg["sources"] as JArray : null;
            var directPurposes = msg != null ? msg["directPurposes"] as JArray : null;
            var uses = msg != null ? msg["uses"] as JArray : null;
            long sourceCount;
            long dropVariantCount;
            long useCount;
            long structuredPurposeCount;
            string requestItemName = ReadExactString(entry.NormalizedPayload["itemName"]);
            string requestSnapshotId = ReadExactString(entry.NormalizedPayload["snapshotId"]);
            CatalogMaterialProof catalog;
            if (!session.Materials.TryGetValue(requestItemName, out catalog)) return false;
            bool expectsInfrastructureUses = Array.IndexOf(
                catalog.DirectPurposeIds, InfrastructurePurposeId) >= 0;
            string[] responseKeys = expectsInfrastructureUses
                ? new[] { "v", "view", "snapshotId", "material", "sourceCount",
                    "dropVariantCount", "useCount", "structuredPurposeCount", "sources",
                    "directPurposes", "uses", "infrastructureUses" }
                : new[] { "v", "view", "snapshotId", "material", "sourceCount",
                    "dropVariantCount", "useCount", "structuredPurposeCount", "sources",
                    "directPurposes", "uses" };
            var infrastructureUses = expectsInfrastructureUses
                ? msg["infrastructureUses"] as JArray : null;
            if (!HasExactResponseKeys(msg, responseKeys)
                || !HasProtocolVersion(msg, 2)
                || ReadExactString(msg["view"]) != "materials"
                || !string.Equals(ReadExactString(msg["snapshotId"]),
                    requestSnapshotId, StringComparison.Ordinal)
                || !string.Equals(requestSnapshotId, session.SnapshotId, StringComparison.Ordinal)
                || material == null || sources == null || sources.Count > MaxSources
                || directPurposes == null || directPurposes.Count > MaxDirectPurposes
                || uses == null || uses.Count > MaxUses
                || !TryReadNni(msg["sourceCount"], out sourceCount)
                || !TryReadNni(msg["dropVariantCount"], out dropVariantCount)
                || !TryReadNni(msg["useCount"], out useCount)
                || !TryReadNni(msg["structuredPurposeCount"], out structuredPurposeCount)
                || expectsInfrastructureUses && infrastructureUses == null
                || !HasExactKeys(material, "name", "displayName", "icon", "description",
                    "owned", "sourceSummary")
                || !IsIdentityTriple(material)
                || !string.Equals(ReadExactString(material["name"]), requestItemName,
                    StringComparison.Ordinal)
                || !string.Equals(ReadExactString(material["displayName"]), catalog.DisplayName,
                    StringComparison.Ordinal)
                || !string.Equals(ReadExactString(material["icon"]), catalog.Icon,
                    StringComparison.Ordinal)
                || !IsSafeMultilineText(ReadExactString(material["description"]), 12000)
                || !IsSafeMultilineText(ReadExactString(material["sourceSummary"]), 20000))
                return false;
            long owned;
            if (!TryReadNni(material["owned"], out owned)
                || owned != catalog.Owned
                || sourceCount != catalog.SourceCount
                || dropVariantCount != catalog.DropVariantCount
                || useCount != catalog.UseCount
                || structuredPurposeCount != catalog.StructuredPurposeCount
                || catalog.HasSourceSummary
                    != (ReadExactString(material["sourceSummary"]).Length > 0)
                || sourceCount != sources.Count
                || useCount != uses.Count
                || structuredPurposeCount != useCount + directPurposes.Count
                || expectsInfrastructureUses
                    && !TryValidateInfrastructureUses(infrastructureUses, catalog.Owned)) return false;

            var sourceKeys = new HashSet<string>(StringComparer.Ordinal);
            SourceOrderProof previousSource = null;
            long countedDropVariants = 0;
            for (int index = 0; index < sources.Count; index++)
            {
                var source = sources[index] as JObject;
                long sourceOrder;
                int variants;
                SourceOrderProof orderProof;
                string sourceKey = source != null ? ReadExactString(source["sourceKey"]) : null;
                if (source == null || !TryReadNni(source["sourceOrder"], out sourceOrder)
                    || sourceOrder != index || !IsIdentityText(sourceKey, 768)
                    || !sourceKeys.Add(sourceKey)
                    || !TryValidateMaterialSourceV2(
                        source, requestItemName, out variants, out orderProof)
                    || (previousSource != null && CompareSourceOrder(previousSource, orderProof) >= 0))
                    return false;
                previousSource = orderProof;
                countedDropVariants += variants;
            }
            if (countedDropVariants != dropVariantCount) return false;

            string[] detailDirectIds;
            if (!TryValidateDirectPurposes(
                    directPurposes, session, out detailDirectIds)
                || !StringArraysEqual(detailDirectIds, catalog.DirectPurposeIds)) return false;
            string[] detailRecipePurposeIds;
            if (!TryValidateRecipeUses(
                    uses, session, requestItemName, out detailRecipePurposeIds)
                || !StringArraysEqual(detailRecipePurposeIds, catalog.RecipePurposeIds)) return false;
            return true;
        }

        private static bool TryValidateDirectPurposes(
            JArray values, MaterialsSession session, out string[] ids)
        {
            ids = null;
            if (values == null || session == null || values.Count > MaxDirectPurposes)
                return false;
            ids = new string[values.Count];
            var seen = new HashSet<string>(StringComparer.Ordinal);
            long previousOrder = -1;
            for (int index = 0; index < values.Count; index++)
            {
                var value = values[index] as JObject;
                string id = value != null ? ReadExactString(value["id"]) : null;
                RegistryEntryProof expected;
                long order;
                if (value == null || !HasExactKeys(value, "id", "label", "order")
                    || !IsIdentityText(id, 256) || !seen.Add(id)
                    || !session.DirectPurposes.TryGetValue(id, out expected)
                    || ReadExactString(value["label"]) != expected.Label
                    || !TryReadNni(value["order"], out order)
                    || order != expected.Order || order <= previousOrder) return false;
                previousOrder = order;
                ids[index] = id;
            }
            return true;
        }

        private static bool TryValidateInfrastructureUses(JArray projects, long catalogOwned)
        {
            if (projects == null || projects.Count > MaxInfrastructureProjects) return false;
            var names = new HashSet<string>(StringComparer.Ordinal);
            int previousProjectOrder = -1;
            foreach (JToken token in projects)
            {
                var project = token as JObject;
                var levels = project != null ? project["levels"] as JArray : null;
                string infrastructureName = project != null
                    ? ReadExactString(project["infrastructureName"]) : null;
                int projectOrder;
                int currentLevel;
                int maximumLevel;
                if (project == null
                    || !HasExactKeys(project, "infrastructureName", "projectOrder",
                        "currentLevel", "maximumLevel", "levels")
                    || !IsIdentityText(infrastructureName, 128) || !names.Add(infrastructureName)
                    || !TryReadInteger(project["projectOrder"], 0,
                        MaxInfrastructureProjects - 1, out projectOrder)
                    || projectOrder <= previousProjectOrder
                    || !TryReadInteger(project["maximumLevel"], 1,
                        MaxInfrastructureLevels, out maximumLevel)
                    || !TryReadInteger(project["currentLevel"], 0,
                        maximumLevel, out currentLevel)
                    || levels == null || levels.Count < 1
                    || levels.Count > MaxInfrastructureLevels) return false;

                previousProjectOrder = projectOrder;
                int previousLevelIndex = -1;
                foreach (JToken levelToken in levels)
                {
                    var level = levelToken as JObject;
                    int levelIndex;
                    int targetLevel;
                    long required;
                    long owned;
                    long missing;
                    string status = level != null ? ReadExactString(level["status"]) : null;
                    if (level == null
                        || !HasExactKeys(level, "levelIndex", "targetLevel", "required",
                            "owned", "missing", "status")
                        || !TryReadInteger(level["levelIndex"], 0,
                            maximumLevel - 1, out levelIndex)
                        || levelIndex <= previousLevelIndex
                        || !TryReadInteger(level["targetLevel"], 1,
                            maximumLevel, out targetLevel)
                        || targetLevel != levelIndex + 1
                        || !TryReadPi(level["required"], out required)
                        || !TryReadNni(level["owned"], out owned) || owned != catalogOwned
                        || !TryReadNni(level["missing"], out missing)) return false;

                    string expectedStatus = currentLevel > levelIndex
                        ? "completed" : currentLevel == levelIndex ? "current" : "future";
                    long expectedMissing = expectedStatus == "completed"
                        ? 0 : required > owned ? required - owned : 0;
                    if (!string.Equals(status, expectedStatus, StringComparison.Ordinal)
                        || missing != expectedMissing) return false;
                    previousLevelIndex = levelIndex;
                }
            }
            return true;
        }

        private static bool TryValidateRecipeUses(
            JArray uses, MaterialsSession session, string materialName,
            out string[] recipePurposeIds)
        {
            recipePurposeIds = null;
            if (uses == null || session == null || uses.Count > MaxUses) return false;
            var seenUses = new HashSet<string>(StringComparer.Ordinal);
            var seenPurposeIds = new HashSet<string>(StringComparer.Ordinal);
            var orderedPurposes = new List<string>();
            for (int index = 0; index < uses.Count; index++)
            {
                var use = uses[index] as JObject;
                var ingredients = use != null ? use["ingredients"] as JArray : null;
                string category = use != null ? ReadExactString(use["category"]) : null;
                int recipeIndex;
                long required;
                string purposeId = "recipe:" + category;
                string identity;
                bool legacyUseShape = use != null && HasExactKeys(use,
                    "category", "recipeIndex", "productName", "displayName",
                    "icon", "itemKind", "required");
                bool ingredientUseShape = use != null && HasExactKeys(use,
                    "category", "recipeIndex", "productName", "displayName",
                    "icon", "itemKind", "required", "ingredients");
                if (use == null || (!legacyUseShape && !ingredientUseShape)
                    || !IsIdentityText(category, 256)
                    || !session.RecipePurposes.ContainsKey(purposeId)
                    || !TryReadInteger(use["recipeIndex"], 0, 999, out recipeIndex)
                    || !IsIdentityText(ReadExactString(use["productName"]), 128)
                    || !IsIdentityText(ReadExactString(use["displayName"]), 256)
                    || !IsIdentityText(ReadExactString(use["icon"]), 256)
                    || !IsItemKind(ReadExactString(use["itemKind"]))
                    || !TryReadPi(use["required"], out required)
                    || ingredientUseShape
                        && !TryValidateRecipeIngredients(
                            ingredients, materialName, required)) return false;
                identity = category + "\u0000" + recipeIndex.ToString(CultureInfo.InvariantCulture);
                if (!seenUses.Add(identity)) return false;
                if (seenPurposeIds.Add(purposeId)) orderedPurposes.Add(purposeId);
            }
            orderedPurposes.Sort(delegate(string left, string right)
            {
                return session.RecipePurposeOrder[left].CompareTo(
                    session.RecipePurposeOrder[right]);
            });
            recipePurposeIds = orderedPurposes.ToArray();
            return true;
        }

        private static bool TryValidateRecipeIngredients(
            JArray ingredients, string materialName, long expectedRequired)
        {
            if (ingredients == null || ingredients.Count < 1
                || ingredients.Count > MaxRecipeIngredients) return false;
            long selectedRequired = 0;
            foreach (JToken token in ingredients)
            {
                var ingredient = token as JObject;
                long required;
                if (ingredient == null
                    || !HasExactKeys(ingredient,
                        "name", "displayName", "icon", "required", "isQuantity")
                    || !IsIdentityText(ReadExactString(ingredient["name"]), 128)
                    || !IsIdentityText(ReadExactString(ingredient["displayName"]), 256)
                    || !IsIdentityText(ReadExactString(ingredient["icon"]), 256)
                    || !TryReadPi(ingredient["required"], out required)
                    || ingredient["isQuantity"] == null
                    || ingredient["isQuantity"].Type != JTokenType.Boolean) return false;
                if (string.Equals(ReadExactString(ingredient["name"]),
                        materialName, StringComparison.Ordinal))
                {
                    if (selectedRequired > MaxSafeInteger - required) return false;
                    selectedRequired += required;
                }
            }
            return selectedRequired == expectedRequired;
        }

        private static bool TryValidateMaterialSourceV2(
            JObject source,
            string materialName,
            out int variantCount,
            out SourceOrderProof orderProof)
        {
            variantCount = 0;
            orderProof = null;
            string kind = ReadExactString(source != null ? source["kind"] : null);
            string sourceKey = ReadExactString(source != null ? source["sourceKey"] : null);
            if (source == null || string.IsNullOrEmpty(kind)) return false;
            long numeric;
            string expectedKey;
            switch (kind)
            {
                case "craft":
                {
                    string category = ReadExactString(source["category"]);
                    int recipeIndex;
                    int categoryIndex = IndexOfCategory(category);
                    if (!HasExactKeys(source, "kind", "sourceKey", "sourceOrder", "category",
                            "recipeIndex", "productName", "price", "kpoints")
                        || categoryIndex < 0
                        || !TryReadInteger(source["recipeIndex"], 0, 999, out recipeIndex)
                        || !string.Equals(ReadExactString(source["productName"]),
                            materialName, StringComparison.Ordinal)
                        || !IsNonNegativeNumber(source["price"])
                        || !IsNonNegativeNumber(source["kpoints"])) return false;
                    expectedKey = BuildSourceKey(kind, category,
                        recipeIndex.ToString(CultureInfo.InvariantCulture));
                    orderProof = new SourceOrderProof
                    {
                        KindOrder = 0, CategoryOrder = categoryIndex,
                        PrimaryText = string.Empty, NumericOrder = recipeIndex
                    };
                    break;
                }
                case "shop":
                {
                    string shopId = ReadExactString(source["shopId"]);
                    if (!HasExactKeys(source, "kind", "sourceKey", "sourceOrder", "shopId",
                            "itemName", "catalogIndex", "basePrice", "unitPriceAtSnapshot",
                            "requiredInfo", "locked", "shopAccessMode", "shopAccessReason")
                        || !IsIdentityText(shopId, 80)
                        || ReadExactString(source["itemName"]) != materialName
                        || !TryReadLongInteger(source["catalogIndex"], 0, 10000, out numeric)
                        || !IsNonNegativeNumber(source["basePrice"])
                        || !IsNonNegativeNumber(source["unitPriceAtSnapshot"])
                        || !IsSafeOptionalText(ReadExactString(source["requiredInfo"]), 512)
                        || source["locked"] == null || source["locked"].Type != JTokenType.Boolean
                        || !IsValidShopAccessPair(
                            ReadExactString(source["shopAccessMode"]),
                            ReadExactString(source["shopAccessReason"]))) return false;
                    expectedKey = BuildSourceKey(kind, shopId,
                        numeric.ToString(CultureInfo.InvariantCulture));
                    orderProof = new SourceOrderProof
                    {
                        KindOrder = 1, PrimaryText = shopId, NumericOrder = numeric
                    };
                    break;
                }
                case "kshop":
                {
                    if (!HasExactKeys(source, "kind", "sourceKey", "sourceOrder", "catalogIndex",
                            "entryId", "category", "priceK")
                        || !TryReadNni(source["catalogIndex"], out numeric)
                        || !IsIdentityText(ReadExactString(source["entryId"]), 256)
                        || !IsSafeOptionalText(ReadExactString(source["category"]), 512)
                        || !IsNonNegativeNumber(source["priceK"])) return false;
                    expectedKey = BuildSourceKey(kind,
                        numeric.ToString(CultureInfo.InvariantCulture));
                    orderProof = new SourceOrderProof { KindOrder = 2, NumericOrder = numeric };
                    break;
                }
                case "quest":
                {
                    string questId = ReadExactString(source["questId"]);
                    string rewardSet = ReadExactString(source["rewardSet"]);
                    long quantity;
                    if (!HasExactKeys(source, "kind", "sourceKey", "sourceOrder", "questId",
                            "rewardSet", "authoredIndex", "title", "quantity")
                        || !IsIdentityText(questId, 256)
                        || (rewardSet != "base" && rewardSet != "challenge")
                        || !TryReadNni(source["authoredIndex"], out numeric)
                        || !IsIdentityText(ReadExactString(source["title"]), 512)
                        || !TryReadPi(source["quantity"], out quantity)) return false;
                    expectedKey = BuildSourceKey(kind, questId, rewardSet,
                        numeric.ToString(CultureInfo.InvariantCulture));
                    orderProof = new SourceOrderProof
                    {
                        KindOrder = 3, PrimaryText = questId,
                        RewardSetOrder = rewardSet == "base" ? 0 : 1,
                        NumericOrder = numeric
                    };
                    break;
                }
                case "stage":
                {
                    string stageName = ReadExactString(source["stageName"]);
                    var variants = source["variants"] as JArray;
                    if (!HasExactKeys(source, "kind", "sourceKey", "sourceOrder", "stageName",
                            "chanceModel", "legacyConditionId", "variants")
                        || !IsIdentityText(stageName, 256)
                        || ReadExactString(source["chanceModel"])
                            != "stage_roll_divisor_with_legacy_domain_branch"
                        || ReadExactString(source["legacyConditionId"]) != "andylaw_domain_bonus"
                        || !TryValidateStageVariants(variants)) return false;
                    variantCount = variants.Count;
                    expectedKey = BuildSourceKey(kind, stageName);
                    orderProof = new SourceOrderProof { KindOrder = 4, PrimaryText = stageName };
                    break;
                }
                case "enemy":
                {
                    string enemyType = ReadExactString(source["enemyType"]);
                    var variants = source["variants"] as JArray;
                    if (!HasExactKeys(source, "kind", "sourceKey", "sourceOrder", "enemyType",
                            "displayName", "chanceModel", "variants")
                        || !IsIdentityText(enemyType, 256)
                        || !enemyType.StartsWith("敌人-", StringComparison.Ordinal)
                        || !IsIdentityText(ReadExactString(source["displayName"]), 512)
                        || ReadExactString(source["chanceModel"]) != "enemy_prd_with_reverse_bonus"
                        || !TryValidateEnemyVariants(variants)) return false;
                    variantCount = variants.Count;
                    expectedKey = BuildSourceKey(kind, enemyType);
                    orderProof = new SourceOrderProof { KindOrder = 5, PrimaryText = enemyType };
                    break;
                }
                default:
                    return false;
            }
            return string.Equals(sourceKey, expectedKey, StringComparison.Ordinal);
        }

        private static bool TryValidateEnemyVariants(JArray variants)
        {
            if (variants == null || variants.Count == 0 || variants.Count > MaxVariants) return false;
            for (int index = 0; index < variants.Count; index++)
            {
                var variant = variants[index] as JObject;
                string state = variant != null ? ReadExactString(variant["chanceInputState"]) : null;
                long occurrenceIndex;
                long quantityMin;
                long quantityMax;
                bool minNull = variant != null && variant["minReverseLevel"] != null
                    && variant["minReverseLevel"].Type == JTokenType.Null;
                bool maxNull = variant != null && variant["maxReverseLevel"] != null
                    && variant["maxReverseLevel"].Type == JTokenType.Null;
                long minLevel = 0;
                long maxLevel = 0;
                if (variant == null
                    || !HasExactKeys(variant, "occurrenceIndex", "chanceRaw", "chanceInputState",
                        "nominalChancePercent", "minReverseLevel", "maxReverseLevel",
                        "quantityMin", "quantityMax")
                    || !TryReadNni(variant["occurrenceIndex"], out occurrenceIndex)
                    || occurrenceIndex != index
                    || (!minNull && !TryReadNni(variant["minReverseLevel"], out minLevel))
                    || (!maxNull && !TryReadNni(variant["maxReverseLevel"], out maxLevel))
                    || (!minNull && !maxNull && minLevel > maxLevel)
                    || !TryReadPi(variant["quantityMin"], out quantityMin)
                    || !TryReadPi(variant["quantityMax"], out quantityMax)
                    || quantityMin > quantityMax
                    || !IsFiniteNumberInRange(variant["nominalChancePercent"], 0, 100)) return false;
                double nominal = variant["nominalChancePercent"].Value<double>();
                if (state == "explicit")
                {
                    if (!IsFiniteNumberInRange(variant["chanceRaw"], 0, 100)
                        || variant["chanceRaw"].Value<double>() != nominal) return false;
                }
                else if (state == "absent_defaulted" || state == "invalid_defaulted")
                {
                    if (variant["chanceRaw"] == null
                        || variant["chanceRaw"].Type != JTokenType.Null || nominal != 100) return false;
                }
                else return false;
            }
            return true;
        }

        private static bool TryValidateStageVariants(JArray variants)
        {
            if (variants == null || variants.Count == 0 || variants.Count > MaxVariants) return false;
            for (int index = 0; index < variants.Count; index++)
            {
                var variant = variants[index] as JObject;
                long occurrenceIndex;
                long divisor;
                long quantityMin;
                long quantityMax;
                if (variant == null
                    || !HasExactKeys(variant, "occurrenceIndex", "rollDivisor",
                        "defaultBranchChancePercent", "quantityMin", "quantityMax")
                    || !TryReadNni(variant["occurrenceIndex"], out occurrenceIndex)
                    || occurrenceIndex != index
                    || !TryReadPi(variant["rollDivisor"], out divisor)
                    || !IsFiniteNumberInRange(variant["defaultBranchChancePercent"], 0, 100)
                    || !TryReadPi(variant["quantityMin"], out quantityMin)
                    || !TryReadPi(variant["quantityMax"], out quantityMax)
                    || quantityMin > quantityMax) return false;
                double expected = Math.Round(
                    (100.0 / divisor) * 1000000.0, MidpointRounding.AwayFromZero) / 1000000.0;
                double actual = variant["defaultBranchChancePercent"].Value<double>();
                if (Math.Abs(expected - actual) > 0.0000005) return false;
            }
            return true;
        }

        private static int CompareSourceOrder(SourceOrderProof left, SourceOrderProof right)
        {
            int result = left.KindOrder.CompareTo(right.KindOrder);
            if (result != 0) return result;
            if (left.KindOrder == 0)
            {
                result = left.CategoryOrder.CompareTo(right.CategoryOrder);
                return result != 0 ? result : left.NumericOrder.CompareTo(right.NumericOrder);
            }
            if (left.KindOrder == 1)
            {
                result = StringComparer.Ordinal.Compare(left.PrimaryText, right.PrimaryText);
                return result != 0 ? result : left.NumericOrder.CompareTo(right.NumericOrder);
            }
            if (left.KindOrder == 2) return left.NumericOrder.CompareTo(right.NumericOrder);
            if (left.KindOrder == 3)
            {
                result = StringComparer.Ordinal.Compare(left.PrimaryText, right.PrimaryText);
                if (result != 0) return result;
                result = left.RewardSetOrder.CompareTo(right.RewardSetOrder);
                return result != 0 ? result : left.NumericOrder.CompareTo(right.NumericOrder);
            }
            return StringComparer.Ordinal.Compare(left.PrimaryText, right.PrimaryText);
        }

        private static string BuildSourceKey(params string[] segments)
        {
            string value = "lp1";
            for (int index = 0; index < segments.Length; index++)
            {
                string segment = segments[index] ?? string.Empty;
                value += "|" + segment.Length.ToString(CultureInfo.InvariantCulture)
                    + ":" + segment;
            }
            return value;
        }

        private static int IndexOfCategory(string category)
        {
            for (int index = 0; index < CategoryOrder.Length; index++)
                if (string.Equals(CategoryOrder[index], category, StringComparison.Ordinal)) return index;
            return -1;
        }

        private static bool StringArraysEqual(string[] left, string[] right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            for (int index = 0; index < left.Length; index++)
                if (!string.Equals(left[index], right[index], StringComparison.Ordinal)) return false;
            return true;
        }

        private static bool IsMaterialSource(JObject source)
        {
            string kind = source != null ? ReadExactString(source["kind"]) : null;
            if (source == null || string.IsNullOrEmpty(kind)) return false;
            switch (kind)
            {
                case "craft":
                    return HasExactKeys(source, "kind", "category", "price", "kpoints")
                        && IsSafeOptionalText(ReadExactString(source["category"]), 512)
                        && IsNonNegativeNumber(source["price"]) && IsNonNegativeNumber(source["kpoints"]);
                case "shop":
                    return HasExactKeys(source, "kind", "npc", "requirement")
                        && IsSafeOptionalText(ReadExactString(source["npc"]), 512)
                        && IsSafeOptionalText(ReadExactString(source["requirement"]), 512);
                case "kshop":
                    return HasExactKeys(source, "kind", "category", "priceK")
                        && IsSafeOptionalText(ReadExactString(source["category"]), 512)
                        && IsNonNegativeNumber(source["priceK"]);
                case "quest":
                    return HasExactKeys(source, "kind", "questId", "title", "quantity")
                        && IsSafeOptionalText(ReadExactString(source["questId"]), 512)
                        && IsIdentityText(ReadExactString(source["title"]), 512)
                        && IsNonNegativeNumber(source["quantity"]);
                case "stage":
                    return HasExactKeys(source, "kind", "stageName", "probability", "quantityMax")
                        && IsSafeOptionalText(ReadExactString(source["stageName"]), 512)
                        && IsNonNegativeNumber(source["probability"])
                        && IsNonNegativeNumber(source["quantityMax"]);
                case "enemy":
                    return HasExactKeys(source, "kind", "enemyType", "displayName", "probability",
                            "minLevel", "maxLevel")
                        && IsSafeOptionalText(ReadExactString(source["enemyType"]), 512)
                        && IsIdentityText(ReadExactString(source["displayName"]), 512)
                        && IsNonNegativeNumber(source["probability"])
                        && IsNonNegativeNumber(source["minLevel"])
                        && IsNonNegativeNumber(source["maxLevel"]);
                default:
                    return false;
            }
        }

        private static bool IsSafeOptionalText(string value, int max)
        {
            if (value == null || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++) if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool IsSafeMultilineText(string value, int max)
        {
            if (value == null || value.Length > max) return false;
            for (int i = 0; i < value.Length; i++)
            {
                char current = value[i];
                if (char.IsControl(current)
                    && current != '\r' && current != '\n' && current != '\t') return false;
            }
            return true;
        }

        private static bool IsNonNegativeNumber(JToken value)
        {
            return IsNumber(value) && value.Value<double>() >= 0;
        }

        private static bool IsAuthoritativePreview(JObject msg, PendingRequest entry)
        {
            int recipeIndex;
            int craftCount;
            int maxCraftCount;
            bool canCommit = msg.Value<bool?>("canCommit") == true;
            string[] responseKeys = canCommit
                ? new[] { "v", "category", "recipeIndex", "craftCount", "batchEligible",
                    "maxCraftCount", "output", "materials", "cost", "balance", "skills",
                    "levelAllowed", "enoughMaterials", "enoughMoney", "enoughKpoints",
                    "enoughSpace", "canCommit", "blockingError", "outputDelivery",
                    "craftToken", "acceptedPlan" }
                : new[] { "v", "category", "recipeIndex", "craftCount", "batchEligible",
                    "maxCraftCount", "output", "materials", "cost", "balance", "skills",
                    "levelAllowed", "enoughMaterials", "enoughMoney", "enoughKpoints",
                    "enoughSpace", "canCommit", "blockingError", "outputDelivery" };
            if (!HasExactResponseKeys(msg, responseKeys)
                || !HasProtocolVersion(msg)
                || !MatchesSelector(msg, entry, "category", "recipeIndex", "craftCount")
                || !TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                || !TryReadInteger(msg["maxCraftCount"], 0, 99, out maxCraftCount)
                || !IsProjectedItem(msg["output"] as JObject, true)
                || !(msg["materials"] is JArray) || !IsCost(msg["cost"] as JObject)
                || !IsOutputDelivery(msg["outputDelivery"] as JObject, msg["output"] as JObject)
                || !IsBalance(msg["balance"] as JObject) || !IsSkills(msg["skills"] as JObject)
                || msg["batchEligible"] == null || msg["batchEligible"].Type != JTokenType.Boolean
                || msg["canCommit"] == null || msg["canCommit"].Type != JTokenType.Boolean
                || !HasExactBooleanFields(msg, "levelAllowed", "enoughMaterials", "enoughMoney",
                    "enoughKpoints", "enoughSpace")) return false;
            if (((JObject)msg["outputDelivery"]).Value<bool>("available")
                != msg.Value<bool>("enoughSpace")) return false;
            foreach (JToken materialToken in (JArray)msg["materials"])
            {
                if (!IsRequirement(materialToken as JObject)) return false;
                if (canCommit && string.Equals(ReadExactString(materialToken["storageKind"]),
                    "unavailable", StringComparison.Ordinal)) return false;
            }
            bool batchEligible = msg.Value<bool>("batchEligible");
            if (!batchEligible && (craftCount != 1 || maxCraftCount > 1)) return false;
            bool allConditions = msg.Value<bool>("levelAllowed")
                && msg.Value<bool>("enoughMaterials")
                && msg.Value<bool>("enoughMoney")
                && msg.Value<bool>("enoughKpoints")
                && msg.Value<bool>("enoughSpace");
            if (canCommit != allConditions) return false;
            if (canCommit)
            {
                if (maxCraftCount < craftCount) return false;
                if (!string.IsNullOrEmpty(ReadExactString(msg["blockingError"]))) return false;
                string token = ReadExactString(msg["craftToken"]);
                if (string.IsNullOrEmpty(token) || !ValidToken.IsMatch(token)
                    || !IsAcceptedPlan(msg["acceptedPlan"] as JObject, msg)) return false;
            }
            else if (!AvailabilityCodes.Contains(ReadExactString(msg["blockingError"]))) return false;
            return true;
        }

        private static bool IsAuthoritativeTooltip(JObject msg, PendingRequest entry)
        {
            return HasExactResponseKeys(msg, "v", "itemName", "displayname", "descHTML", "introHTML")
                && HasProtocolVersion(msg)
                && string.Equals(ReadExactString(msg["itemName"]),
                    ReadExactString(entry.NormalizedPayload["itemName"]), StringComparison.Ordinal)
                && IsIdentityText(ReadExactString(msg["displayname"]), 256)
                && IsSafeMultilineText(ReadExactString(msg["descHTML"]), 20000)
                && IsSafeMultilineText(ReadExactString(msg["introHTML"]), 20000);
        }

        private static bool IsAuthoritativeSetPlan(JObject msg, PendingRequest entry)
        {
            if (!HasExactResponseKeys(msg, "v", "revision", "recipeId", "plannedCrafts"))
                return false;
            JObject payload = (JObject)msg.DeepClone();
            payload.Remove("task");
            payload.Remove("callId");
            return ProcurementProjectionValidator.IsPlanMutation(payload)
                && string.Equals(ReadExactString(msg["recipeId"]),
                    ReadExactString(entry.NormalizedPayload["recipeId"]),
                    StringComparison.Ordinal)
                && JToken.DeepEquals(msg["plannedCrafts"],
                    entry.NormalizedPayload["plannedCrafts"])
                && msg.Value<long>("revision")
                    == entry.NormalizedPayload.Value<long>("expectedRevision") + 1;
        }

        private static bool IsAuthoritativeCommit(JObject msg, PendingRequest entry)
        {
            int recipeIndex;
            int craftCount;
            var crafted = msg["crafted"] as JObject;
            if (!HasExactResponseKeys(msg, "v", "operation", "category", "recipeIndex",
                    "craftCount", "crafted", "acceptedPlan", "outputReceipt", "balance",
                    "procurement")
                || !HasProtocolVersion(msg)
                || !string.Equals(ReadExactString(msg["operation"]), "commit", StringComparison.Ordinal)
                || !MatchesSelector(msg, entry, "category")
                || entry.ExpectedPreview == null) return false;
            if (!TryReadInteger(msg["recipeIndex"], 0, 999, out recipeIndex)
                || !TryReadInteger(msg["craftCount"], 1, 99, out craftCount)
                || !IsProjectedItem(crafted, true)
                || !IsBalance(msg["balance"] as JObject)
                || !ProcurementProjectionValidator.IsCommitState(msg["procurement"] as JObject)
                || recipeIndex != entry.ExpectedPreview.RecipeIndex
                || craftCount != entry.ExpectedPreview.CraftCount
                || !string.Equals(ReadExactString(msg["category"]),
                    entry.ExpectedPreview.Category, StringComparison.Ordinal)
                || !JToken.DeepEquals(crafted, entry.ExpectedPreview.Output)
                || !JToken.DeepEquals(msg["acceptedPlan"], entry.ExpectedPreview.AcceptedPlan)
                || !IsOutputReceipt(msg["outputReceipt"],
                    msg["acceptedPlan"] as JObject, crafted)) return false;
            string itemKind = ReadExactString(crafted["itemKind"]);
            double value = crafted["value"].Value<double>();
            double quantity = crafted["quantity"].Value<double>();
            double enhancementLevel = crafted["enhancementLevel"].Value<double>();
            return itemKind == "equipment"
                ? craftCount == 1 && quantity == 1 && enhancementLevel == value
                : enhancementLevel == 0 && quantity == value && quantity >= craftCount;
        }

        private static bool IsProjectedItem(JObject item, bool withRequiredLevel)
        {
            if (item == null) return false;
            string[] keys = withRequiredLevel
                ? new[] { "name", "displayName", "icon", "itemKind", "value", "quantity",
                    "enhancementLevel", "majorType", "use", "actionType", "weaponType",
                    "setId", "setName", "setOrder", "requiredLevel" }
                : new[] { "name", "displayName", "icon", "itemKind", "value", "quantity",
                    "enhancementLevel", "majorType", "use", "actionType", "weaponType",
                    "setId", "setName", "setOrder" };
            int setOrder;
            if (!HasExactKeys(item, keys) || !IsIdentityTriple(item)
                || !IsItemKind(ReadExactString(item["itemKind"]))
                || !IsNonNegativeNumber(item["value"]) || !IsNonNegativeNumber(item["quantity"])
                || !IsNonNegativeNumber(item["enhancementLevel"])
                || !IsSafeOptionalText(ReadExactString(item["majorType"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["use"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["actionType"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["weaponType"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["setId"]), 128)
                || !IsSafeOptionalText(ReadExactString(item["setName"]), 256)
                || !TryReadInteger(item["setOrder"], 0, 100000, out setOrder)
                || (withRequiredLevel && !IsNonNegativeNumber(item["requiredLevel"]))) return false;
            string kind = ReadExactString(item["itemKind"]);
            double value = item["value"].Value<double>();
            double quantity = item["quantity"].Value<double>();
            double enhancement = item["enhancementLevel"].Value<double>();
            if (value <= 0 || quantity <= 0
                || Math.Truncate(value) != value
                || Math.Truncate(quantity) != quantity
                || Math.Truncate(enhancement) != enhancement) return false;
            return kind == "equipment"
                ? quantity == 1 && enhancement == value
                : enhancement == 0 && quantity == value;
        }

        private static bool IsRequirement(JObject requirement)
        {
            return requirement != null
                && HasExactKeys(requirement, "name", "displayName", "icon", "itemKind", "required",
                    "owned", "maxEnhancement", "isQuantity", "tier", "consumed", "enough",
                    "storageKind", "craftingSources", "procurement")
                && IsIdentityTriple(requirement)
                && IsItemKind(ReadExactString(requirement["itemKind"]))
                && IsNonNegativeNumber(requirement["required"])
                && IsNonNegativeNumber(requirement["owned"])
                && IsNonNegativeNumber(requirement["maxEnhancement"])
                && IsSafeOptionalText(ReadExactString(requirement["tier"]), 128)
                && StorageKinds.Contains(ReadExactString(requirement["storageKind"]))
                && IsCraftingSources(requirement["craftingSources"] as JArray)
                && ProcurementProjectionValidator.IsDemand(
                    requirement["procurement"] as JObject,
                    ReadExactString(requirement["name"]))
                && HasExactBooleanFields(requirement, "isQuantity", "consumed", "enough");
        }

        private static bool IsCraftingSources(JArray sources)
        {
            if (sources == null || sources.Count > MaxCraftingSources) return false;
            var recipeIds = new HashSet<string>(StringComparer.Ordinal);
            var occurrences = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in sources)
            {
                JObject source = token as JObject;
                int index;
                string category = source != null
                    ? ReadExactString(source["category"]) : null;
                string recipeId = source != null
                    ? ReadExactString(source["recipeId"]) : null;
                if (source == null
                    || !HasExactKeys(source, "category", "recipeIndex", "recipeId", "title")
                    || !Categories.Contains(category)
                    || !TryReadInteger(source["recipeIndex"], 0, 999, out index)
                    || !ProcurementProjectionValidator.IsRecipeId(source["recipeId"])
                    || !IsIdentityText(ReadExactString(source["title"]), 256)
                    || !recipeIds.Add(recipeId)
                    || !occurrences.Add(category + "\0" + index.ToString(CultureInfo.InvariantCulture)))
                    return false;
            }
            return true;
        }

        private static bool IsOutputDelivery(JObject delivery, JObject output)
        {
            int physicalSlot;
            if (delivery == null || output == null
                || !HasExactKeys(delivery, "available", "storageKind", "mode", "physicalSlot", "quantity")
                || delivery["available"] == null || delivery["available"].Type != JTokenType.Boolean
                || !StorageKinds.Contains(ReadExactString(delivery["storageKind"]))
                || !TryReadInteger(delivery["physicalSlot"], -1, 999, out physicalSlot)
                || !IsNonNegativeNumber(delivery["quantity"])
                || !JToken.DeepEquals(delivery["quantity"], output["quantity"])) return false;
            bool available = delivery.Value<bool>("available");
            string storageKind = ReadExactString(delivery["storageKind"]);
            string mode = ReadExactString(delivery["mode"]);
            string itemKind = ReadExactString(output["itemKind"]);
            if (!available) return storageKind == "unavailable" && mode == "none" && physicalSlot == -1;
            if (storageKind == "bag") return (mode == "insert"
                    || mode == "merge" && itemKind == "stack")
                && physicalSlot >= 0 && physicalSlot < 50;
            if (storageKind == "drug") return itemKind == "stack"
                && mode == "merge" && physicalSlot >= 0;
            if (storageKind == "material_collection" || storageKind == "information_collection")
                return itemKind == "stack" && mode == "increment" && physicalSlot == -1;
            return false;
        }

        private static bool IsAcceptedPlan(JObject plan, JObject preview)
        {
            int recipeIndex;
            int craftCount;
            return plan != null
                && HasExactKeys(plan, "category", "recipeIndex", "craftCount", "output",
                    "materials", "outputDelivery", "outputPrototype", "cost")
                && TryReadInteger(plan["recipeIndex"], 0, 999, out recipeIndex)
                && TryReadInteger(plan["craftCount"], 1, 99, out craftCount)
                && string.Equals(ReadExactString(plan["category"]),
                    ReadExactString(preview["category"]), StringComparison.Ordinal)
                && recipeIndex == preview.Value<int>("recipeIndex")
                && craftCount == preview.Value<int>("craftCount")
                && JToken.DeepEquals(plan["output"], preview["output"])
                && JToken.DeepEquals(plan["materials"], preview["materials"])
                && JToken.DeepEquals(plan["outputDelivery"], preview["outputDelivery"])
                && JToken.DeepEquals(plan["cost"], preview["cost"])
                && IsOutputPrototype(plan["outputPrototype"],
                    plan["output"] as JObject, plan["outputDelivery"] as JObject);
        }

        private static bool IsOutputPrototype(
            JToken token,
            JObject output,
            JObject delivery)
        {
            if (output == null || delivery == null) return false;
            string storageKind = ReadExactString(delivery["storageKind"]);
            bool physical = storageKind == "bag" || storageKind == "drug";
            if (!physical) return token != null && token.Type == JTokenType.Null
                && (storageKind == "material_collection"
                    || storageKind == "information_collection");
            var prototype = token as JObject;
            if (prototype == null || !HasExactKeys(prototype, "item", "confirmProjection")) return false;
            JObject item;
            JObject confirm;
            if (!InventoryTask.TrySanitizeItem(prototype["item"] as JObject, out item)
                || !InventoryTask.TrySanitizeStableConfirm(
                    prototype["confirmProjection"] as JObject, item, out confirm)
                || !JToken.DeepEquals(item, prototype["item"])
                || !JToken.DeepEquals(confirm, prototype["confirmProjection"])) return false;
            return string.Equals(ReadExactString(item["name"]),
                    ReadExactString(output["name"]), StringComparison.Ordinal)
                && string.Equals(ReadExactString(item["displayName"]),
                    ReadExactString(output["displayName"]), StringComparison.Ordinal)
                && string.Equals(ReadExactString(item["icon"]),
                    ReadExactString(output["icon"]), StringComparison.Ordinal)
                && string.Equals(ReadExactString(item["itemKind"]),
                    ReadExactString(output["itemKind"]), StringComparison.Ordinal)
                && JToken.DeepEquals(item["quantity"], output["quantity"])
                && JToken.DeepEquals(item["enhancementLevel"], output["enhancementLevel"])
                && JToken.DeepEquals(item["quantity"], delivery["quantity"]);
        }

        private static bool IsOutputReceipt(
            JToken token,
            JObject acceptedPlan,
            JObject crafted)
        {
            if (acceptedPlan == null || crafted == null) return false;
            var delivery = acceptedPlan["outputDelivery"] as JObject;
            string storageKind = delivery != null
                ? ReadExactString(delivery["storageKind"]) : null;
            bool physical = storageKind == "bag" || storageKind == "drug";
            if (!physical) return token != null && token.Type == JTokenType.Null
                && (storageKind == "material_collection"
                    || storageKind == "information_collection");
            var receipt = token as JObject;
            var prototype = acceptedPlan["outputPrototype"] as JObject;
            if (receipt == null || prototype == null
                || !HasExactKeys(receipt, "item", "confirmProjection")) return false;
            JObject item;
            JObject confirm;
            if (!InventoryTask.TrySanitizeItem(receipt["item"] as JObject, out item)
                || !InventoryTask.TrySanitizeConfirm(
                    receipt["confirmProjection"] as JObject, item, out confirm)
                || !JToken.DeepEquals(item, receipt["item"])
                || !JToken.DeepEquals(confirm, receipt["confirmProjection"])) return false;
            var prototypeItem = prototype["item"] as JObject;
            var prototypeConfirm = prototype["confirmProjection"] as JObject;
            if (prototypeItem == null || prototypeConfirm == null) return false;
            long outputQuantity;
            long receiptQuantity;
            if (!TryReadLongInteger(crafted["quantity"], 1, 9007199254740991L,
                    out outputQuantity)
                || !TryReadLongInteger(item["quantity"], 1, 9007199254740991L,
                    out receiptQuantity)
                || (ReadExactString(delivery["mode"]) == "insert"
                    ? receiptQuantity != outputQuantity
                    : receiptQuantity < outputQuantity)) return false;

            JObject normalizedItem = (JObject)item.DeepClone();
            normalizedItem["quantity"] = prototypeItem["quantity"].DeepClone();
            JObject normalizedConfirm = (JObject)confirm.DeepClone();
            normalizedConfirm.Remove("lastUpdate");
            normalizedConfirm["quantity"] = prototypeConfirm["quantity"].DeepClone();
            return JToken.DeepEquals(normalizedItem, prototypeItem)
                && JToken.DeepEquals(normalizedConfirm, prototypeConfirm);
        }

        private static bool IsIdentityTriple(JObject value)
        {
            return value != null
                && IsIdentityText(ReadExactString(value["name"]), 128)
                && IsIdentityText(ReadExactString(value["displayName"]), 256)
                && IsIdentityText(ReadExactString(value["icon"]), 256);
        }

        private static bool IsItemKind(string value)
        {
            return value == "equipment" || value == "stack";
        }

        private static bool IsBalance(JObject balance)
        {
            return balance != null && HasExactKeys(balance, "money", "kpoints")
                && IsNonNegativeNumber(balance["money"]) && IsNonNegativeNumber(balance["kpoints"]);
        }

        private static bool IsSkills(JObject skills)
        {
            return skills != null && HasExactKeys(skills, "reverseLevel", "smithEnabled", "smithLevel")
                && IsNonNegativeNumber(skills["reverseLevel"])
                && skills["smithEnabled"] != null && skills["smithEnabled"].Type == JTokenType.Boolean
                && IsNonNegativeNumber(skills["smithLevel"]);
        }

        private static bool IsCost(JObject cost)
        {
            return cost != null && HasExactKeys(cost, "money", "kpoints")
                && IsNonNegativeNumber(cost["money"]) && IsNonNegativeNumber(cost["kpoints"]);
        }

        private static bool HasExactBooleanFields(JObject value, params string[] fields)
        {
            foreach (string field in fields)
            {
                if (value[field] == null || value[field].Type != JTokenType.Boolean) return false;
            }
            return true;
        }

        private static bool MatchesSelector(JObject msg, PendingRequest entry, params string[] fields)
        {
            if (entry == null || entry.NormalizedPayload == null) return false;
            foreach (string field in fields)
            {
                if (!JToken.DeepEquals(msg[field], entry.NormalizedPayload[field])) return false;
            }
            return true;
        }

        private static bool HasExactResponseKeys(JObject value, params string[] bodyKeys)
        {
            var expected = new string[bodyKeys.Length + 3];
            expected[0] = "task";
            expected[1] = "callId";
            expected[2] = "success";
            Array.Copy(bodyKeys, 0, expected, 3, bodyKeys.Length);
            return HasExactKeys(value, expected);
        }

        private static bool HasExactKeys(JObject value, params string[] expected)
        {
            if (value == null || value.Count != expected.Length) return false;
            var names = new HashSet<string>(expected, StringComparer.Ordinal);
            if (names.Count != expected.Length) return false;
            foreach (JProperty property in value.Properties())
            {
                if (!names.Contains(property.Name)) return false;
            }
            return true;
        }

        private static string ReadExactString(JToken token)
        {
            return token != null && token.Type == JTokenType.String ? token.Value<string>() : null;
        }

        private static bool HasProtocolVersion(JObject value)
        {
            return HasProtocolVersion(value, 1);
        }

        private static bool IsValidShopAccessPair(string mode, string reason)
        {
            return (mode == "full" && reason == "indexed_live_match")
                || (mode == "unavailable"
                    && reason == "no_authoritative_remote_access_capability");
        }

        private static bool HasProtocolVersion(JObject value, int expected)
        {
            int actual;
            return value != null && TryReadProtocolVersion(value["v"], out actual)
                && actual == expected;
        }

        private static bool TryReadProtocolVersion(JToken token, out int version)
        {
            version = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            long candidate;
            try { candidate = token.Value<long>(); }
            catch { return false; }
            if (candidate != 1 && candidate != 2) return false;
            version = (int)candidate;
            return true;
        }

        private static bool TryReadNni(JToken token, out long value)
        {
            return TryReadLongInteger(token, 0, MaxSafeInteger, out value);
        }

        private static bool TryReadPi(JToken token, out long value)
        {
            return TryReadLongInteger(token, 1, MaxSafeInteger, out value);
        }

        private static bool IsExactInteger(JToken token, long expected)
        {
            long value;
            return TryReadLongInteger(token, expected, expected, out value);
        }

        private static bool IsFiniteNumberInRange(JToken token, double minimum, double maximum)
        {
            return IsNumber(token) && token.Value<double>() >= minimum
                && token.Value<double>() <= maximum;
        }

        private static bool IsNumber(JToken value)
        {
            if (value == null || (value.Type != JTokenType.Integer && value.Type != JTokenType.Float)) return false;
            double candidate = value.Value<double>();
            return !double.IsNaN(candidate) && !double.IsInfinity(candidate);
        }

        private static bool IsDefinitiveWriteResponse(JObject msg)
        {
            if (msg == null || msg["success"] == null || msg["success"].Type != JTokenType.Boolean) return false;
            // Caller invokes this only after TrySanitizeResponse accepted the
            // command-specific success shape and postcondition.
            if (msg.Value<bool>("success")) return true;
            switch (msg.Value<string>("error"))
            {
                case "invalid_payload": case "category_not_found": case "recipe_not_found":
                case "batch_not_supported":
                case "stale_state": case "material_missing": case "insufficient_money":
                case "insufficient_kpoint": case "inventory_full": case "level_locked": case "busy": return true;
                default: return false;
            }
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pendingCall,
            PanelPendingCallEndReason reason)
        {
            PendingRequest entry = pendingCall.Context;
            lock (_lock)
            {
                _navigationGeneration++;
                if (entry.IsWrite) EnterNeedsReconcileLocked();
            }
            if (reason == PanelPendingCallEndReason.Cleared) return;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                entry.OwnerPanel,
                entry.OwnerPanelInstanceId,
                reason == PanelPendingCallEndReason.Timeout ? "timeout" : "disconnected",
                entry.IsWrite);
        }

        private void EnterNeedsReconcileLocked()
        {
            _writeState = "needs_reconcile";
            _reconcileEpoch++;
        }

        private void RejectAndRemember(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId, string error)
        {
            string responseError = error;
            lock (_lock)
            {
                if (_navigationLeaseToken != null)
                    responseError = "busy";
                else if (!_pendingCalls.TryRememberRejected(callId))
                    return;
            }
            RespondError(
                callId,
                cmd,
                ownerPanel,
                ownerPanelInstanceId,
                responseError,
                false);
        }

        private void RespondError(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId,
            string error, bool requiresReconcile = false)
        {
            var response = new JObject
            {
                ["type"] = "panel_resp", ["domain"] = "crafting", ["cmd"] = cmd ?? "",
                ["panel"] = ownerPanel, ["panelInstanceId"] = ownerPanelInstanceId,
                ["callId"] = callId ?? "", ["success"] = false, ["error"] = error
            };
            if (requiresReconcile) response["requiresReconcile"] = true;
            PostToWeb(response.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null) _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }
    }
}
