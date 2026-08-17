using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Host-owned fixed-route coordinator for crafting &lt;-&gt; exact NPCShop/KShop procurement. It owns the
    /// only transition deadline and the private one-shot return capability.  It is deliberately
    /// not a generic panel history/return stack.
    /// </summary>
    internal sealed class MaterialShopNavigationCoordinator : IDisposable
    {
        internal const int MaterialShopNavigationTimeoutMs = 5000;
        internal const int MaterialShopNavigationDeliveryMarginMs = 1500;
        internal const int MaterialShopNavigationWebWatchdogMs =
            MaterialShopNavigationTimeoutMs + MaterialShopNavigationDeliveryMarginMs;

        internal enum TransitionPhase
        {
            TokenCreated,
            TaskFencesAcquired,
            AuthorityPending,
            TargetReserved,
            Committing,
            TargetCommitted,
            Failed,
            Cancelled
        }

        private enum TransitionKind
        {
            Forward,
            Reverse,
            Close
        }

        private sealed class Transition
        {
            internal TransitionKind Kind;
            internal TransitionPhase Phase;
            internal string Token;
            internal string CallId;
            internal string Signature;
            internal string ResponseCommand;
            internal string SourcePanel;
            internal string SourceInstance;
            internal string TargetPanel;
            internal string TargetInstance;
            internal long DeadlineAtMs;
            internal IDisposable Deadline;
            internal int AuthorityFid;
            internal string MaterialSnapshotId;
            internal string MaterialName;
            internal string ShopId;
            internal int CatalogIndex;
            internal bool IsProcurement;
            internal string RecipeId;
            internal string RecipeCategory;
            internal int RecipeIndex;
            internal bool IsKShop;
            internal string EntryId;
            internal string KShopCategory;
            internal MaterialShopSettlementWitness CraftingWitness;
            internal MaterialShopSettlementWitness NpcShopWitness;
            internal MaterialShopSettlementWitness ShopWitness;
            internal MaterialShopSettlementWitness InventoryWitness;
            internal LauncherCommandRouter.MaterialShopCharacterCapsule CharacterCapsule;
            internal bool KShopPauseOpened;
            internal bool KShopPauseTransferred;
            internal bool LeasesTerminal;
            internal bool ReverseDispatchReturned;
            internal bool ReplacePreparationStarted;
            internal bool ReplaceDispatchReturned;
            internal bool ReplaceQueued;
            internal bool ReplaceCompleted;
            internal Transition WaitForReplaceDrain;
            internal Action CloseCompleted;
            internal Func<bool> DeferredSourceClose;
            internal bool DeferredSourceCloseDispatched;
        }

        private sealed class MaterialReturnRoute
        {
            internal string ShopPanel;
            internal string ShopInstance;
            internal string MaterialName;
            internal string ShopId;
            internal int CatalogIndex;
            internal bool IsProcurement;
            internal string RecipeId;
            internal string RecipeCategory;
            internal int RecipeIndex;
            internal string EntryId;
            internal string KShopCategory;
            internal LauncherCommandRouter.MaterialShopCharacterCapsule CharacterCapsule;
        }

        private static readonly Regex ValidCallId = new Regex(
            "^[A-Za-z0-9._-]{1,96}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex ValidPanelInstanceId = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private readonly object _lock = new object();
        private readonly PanelHostController _panelHost;
        private readonly MaterialShopAccessTask _accessTask;
        private readonly CraftingTask _craftingTask;
        private readonly InventoryTask _inventoryTask;
        private readonly NpcShopTask _npcShopTask;
        private readonly LauncherCommandRouter _commandRouter;
        private readonly Func<string, bool> _tryPostToWeb;
        private readonly Func<long> _nowMs;
        private readonly Func<int, Action, IDisposable> _schedule;
        private readonly Func<string> _nextPanelInstanceId;
        private Transition _active;
        private MaterialReturnRoute _returnRoute;
        private ShopTask _shopTask;
        private Func<bool> _tryOpenKShop;
        private Action _closeKShopNoFail;
        private bool _disposed;

        internal MaterialShopNavigationCoordinator(
            PanelHostController panelHost,
            MaterialShopAccessTask accessTask,
            CraftingTask craftingTask,
            InventoryTask inventoryTask,
            NpcShopTask npcShopTask,
            LauncherCommandRouter commandRouter,
            Func<string, bool> tryPostToWeb)
            : this(
                panelHost,
                accessTask,
                craftingTask,
                inventoryTask,
                npcShopTask,
                commandRouter,
                tryPostToWeb,
                delegate { return Environment.TickCount64; },
                DefaultSchedule,
                delegate { return OpaqueIdGenerator.Create("panel"); })
        {
        }

        internal MaterialShopNavigationCoordinator(
            PanelHostController panelHost,
            MaterialShopAccessTask accessTask,
            CraftingTask craftingTask,
            InventoryTask inventoryTask,
            NpcShopTask npcShopTask,
            LauncherCommandRouter commandRouter,
            Func<string, bool> tryPostToWeb,
            Func<long> nowMs,
            Func<int, Action, IDisposable> schedule,
            Func<string> nextPanelInstanceId)
        {
            _panelHost = panelHost;
            _accessTask = accessTask;
            _craftingTask = craftingTask;
            _inventoryTask = inventoryTask;
            _npcShopTask = npcShopTask;
            _commandRouter = commandRouter;
            _tryPostToWeb = tryPostToWeb ?? delegate { return false; };
            _nowMs = nowMs ?? delegate { return Environment.TickCount64; };
            _schedule = schedule ?? DefaultSchedule;
            _nextPanelInstanceId = nextPanelInstanceId
                ?? delegate { return OpaqueIdGenerator.Create("panel"); };
        }

        internal void ConfigureKShopNavigation(
            ShopTask shopTask,
            Func<bool> tryOpenKShop,
            Action closeKShopNoFail)
        {
            lock (_lock)
            {
                if (_disposed) return;
                _shopTask = shopTask;
                _tryOpenKShop = tryOpenKShop;
                _closeKShopNoFail = closeKShopNoFail;
            }
        }

        internal TransitionPhase? ActivePhaseForTests
        {
            get
            {
                lock (_lock)
                    return _active != null
                        ? (TransitionPhase?)_active.Phase
                        : null;
            }
        }

        internal bool HasMaterialReturnRoute(string npcShopInstance)
        {
            lock (_lock)
            {
                return !_disposed
                    && _returnRoute != null
                    && string.Equals(_returnRoute.ShopPanel, "npcshop",
                        StringComparison.Ordinal)
                    && string.Equals(
                        _returnRoute.ShopInstance,
                        npcShopInstance,
                        StringComparison.Ordinal);
            }
        }

        internal bool HasKShopReturnRoute(string kshopInstance)
        {
            lock (_lock)
            {
                return !_disposed && _returnRoute != null
                    && string.Equals(_returnRoute.ShopPanel, "kshop",
                        StringComparison.Ordinal)
                    && string.Equals(_returnRoute.ShopInstance, kshopInstance,
                        StringComparison.Ordinal);
            }
        }

        internal void HandleForward(JObject request)
        {
            string callId = ReadString(request, "callId");
            string sourceInstance = ReadString(request, "panelInstanceId");
            bool isKShop = IsValidProcurementKShopForwardEnvelope(request);
            bool isProcurement = isKShop || IsValidProcurementForwardEnvelope(request);
            string responseCommand = isKShop
                ? "open_procurement_kshop"
                : isProcurement ? "open_procurement_shop" : "open_npc_shop";
            if (!isProcurement && !IsValidForwardEnvelope(request))
            {
                string requestedCommand = ReadString(request, "cmd");
                RespondMalformedIfOwned(
                    request,
                    "crafting",
                    requestedCommand == "open_procurement_kshop"
                        ? "open_procurement_kshop"
                        : requestedCommand == "open_procurement_shop"
                            ? "open_procurement_shop"
                            : "open_npc_shop");
                return;
            }
            if (!IsExactActive("crafting", sourceInstance))
            {
                LogManager.Log(
                    "event=material_shop_navigation_rejected direction=forward reason=stale_owner");
                return;
            }

            string snapshotId = isProcurement
                ? null
                : request.Value<string>("materialSnapshotId");
            string materialName = request.Value<string>("materialName");
            string shopId = isKShop ? null : request.Value<string>("shopId");
            int catalogIndex = request.Value<int>("catalogIndex");
            string recipeId = isProcurement ? request.Value<string>("recipeId") : null;
            string recipeCategory = isKShop
                ? request.Value<string>("recipeCategory")
                : isProcurement ? request.Value<string>("category") : null;
            int recipeIndex = isProcurement ? request.Value<int>("recipeIndex") : -1;
            string entryId = isKShop ? request.Value<string>("entryId") : null;
            string kshopCategory = isKShop
                ? request.Value<string>("kshopCategory") : null;
            string signature = BuildForwardSignature(
                sourceInstance,
                snapshotId,
                materialName,
                shopId,
                catalogIndex,
                recipeId,
                recipeCategory,
                recipeIndex,
                isKShop,
                entryId,
                kshopCategory);
            Transition transition = BeginTransition(
                TransitionKind.Forward,
                callId,
                signature,
                "crafting",
                sourceInstance,
                responseCommand,
                true);
            if (transition == null) return;
            transition.MaterialSnapshotId = snapshotId;
            transition.MaterialName = materialName;
            transition.ShopId = shopId;
            transition.CatalogIndex = catalogIndex;
            transition.IsProcurement = isProcurement;
            transition.RecipeId = recipeId;
            transition.RecipeCategory = recipeCategory;
            transition.RecipeIndex = recipeIndex;
            transition.IsKShop = isKShop;
            transition.EntryId = entryId;
            transition.KShopCategory = kshopCategory;

            if (_panelHost == null || _accessTask == null
                || _craftingTask == null || _inventoryTask == null
                || !isKShop && (_npcShopTask == null || _commandRouter == null)
                || isKShop && (_shopTask == null || _tryOpenKShop == null
                    || _closeKShopNoFail == null))
            {
                FailTransition(transition, "navigation_unavailable", false);
                return;
            }
            if (!TryAcquireForwardTaskFences(transition)
                || !AreForwardWitnessesCurrent(transition))
            {
                FailTransition(
                    transition,
                    IsDeadlineExpired(transition)
                        ? "timeout"
                        : "source_not_settled",
                    false);
                return;
            }
            if (!AdvancePhase(
                    transition,
                    TransitionPhase.TaskFencesAcquired,
                    TransitionPhase.AuthorityPending))
            {
                FailTransition(transition, "navigation_unavailable", false);
                return;
            }

            int fid;
            bool accepted = _accessTask.TryAuthorize(
                new MaterialShopAccessTask.Request
                {
                    MaterialSnapshotId = snapshotId,
                    MaterialName = materialName,
                    ShopId = shopId,
                    CatalogIndex = catalogIndex,
                    IsProcurement = isProcurement,
                    RecipeId = recipeId,
                    Category = recipeCategory,
                    RecipeIndex = recipeIndex,
                    IsKShop = isKShop,
                    EntryId = entryId,
                    KShopCategory = kshopCategory
                },
                delegate { return IsAuthorityFenceCurrent(transition); },
                delegate(MaterialShopAccessTask.Result result)
                {
                    HandleAuthorityResult(transition, result);
                },
                delegate(int allocatedFid)
                {
                    transition.AuthorityFid = allocatedFid;
                    LogManager.Log(
                        AuthorityLogFormatter
                            .FormatMaterialShopAuthorityFlashCallBound(
                            callId,
                            allocatedFid,
                            sourceInstance,
                            isProcurement,
                            isKShop));
                },
                out fid);
            transition.AuthorityFid = fid;
            if (!accepted)
                FailTransition(transition, "navigation_unavailable", false);
        }

        internal void HandleReverse(JObject request)
        {
            string sourceInstance = ReadString(request, "panelInstanceId");
            bool kshopReturn = IsValidKShopRecipeReverseEnvelope(request);
            bool recipeReturn = kshopReturn || IsValidRecipeReverseEnvelope(request);
            string sourcePanel = kshopReturn ? "kshop" : "npcshop";
            string responseCommand = recipeReturn
                ? "return_crafting_recipe"
                : "return_crafting_materials";
            if (!recipeReturn && !IsValidReverseEnvelope(request))
            {
                string requestedPanel = ReadString(request, "panel");
                RespondMalformedIfOwned(
                    request,
                    requestedPanel == "kshop" ? "kshop" : "npcshop",
                    ReadString(request, "cmd") == "return_crafting_recipe"
                        ? "return_crafting_recipe"
                        : "return_crafting_materials");
                return;
            }
            if (!IsExactActive(sourcePanel, sourceInstance))
            {
                LogManager.Log(
                    "event=material_shop_navigation_rejected direction=reverse reason=stale_owner");
                return;
            }

            string callId = request.Value<string>("callId");
            MaterialReturnRoute route = GetExactRoute(sourcePanel, sourceInstance);
            if (route == null || route.IsProcurement != recipeReturn)
            {
                PostFailure(
                    sourcePanel,
                    responseCommand,
                    callId,
                    sourceInstance,
                    "return_unavailable");
                return;
            }
            Transition transition = BeginTransition(
                TransitionKind.Reverse,
                callId,
                BuildReverseSignature(sourceInstance, responseCommand),
                sourcePanel,
                sourceInstance,
                responseCommand,
                true);
            if (transition == null) return;
            try
            {
                transition.MaterialName = route.MaterialName;
                transition.ShopId = route.ShopId;
                transition.CatalogIndex = route.CatalogIndex;
                transition.IsProcurement = route.IsProcurement;
                transition.RecipeId = route.RecipeId;
                transition.RecipeCategory = route.RecipeCategory;
                transition.RecipeIndex = route.RecipeIndex;
                transition.CharacterCapsule = route.CharacterCapsule;
                transition.IsKShop = string.Equals(route.ShopPanel, "kshop",
                    StringComparison.Ordinal);
                transition.EntryId = route.EntryId;
                transition.KShopCategory = route.KShopCategory;

                if (_panelHost == null || _inventoryTask == null
                    || _craftingTask == null
                    || transition.IsKShop && (_shopTask == null
                        || _closeKShopNoFail == null)
                    || !transition.IsKShop && (_npcShopTask == null
                        || _commandRouter == null))
                {
                    FailTransition(transition, "navigation_unavailable", false);
                    return;
                }
                if (!TryAcquireReverseTaskFences(transition)
                    || !AreReverseWitnessesCurrent(transition))
                {
                    FailTransition(
                        transition,
                        IsDeadlineExpired(transition)
                            ? "timeout"
                            : "source_not_settled",
                        false);
                    return;
                }
                PrepareReverseReplacement(transition);
            }
            finally
            {
                MarkReverseDispatchReturned(transition);
            }
        }

        /// <summary>
        /// Handles only an NPCShop instance carrying the private material-return one-shot. Ordinary
        /// NPCShop instances remain on the existing exact close path.
        /// </summary>
        internal bool TryHandleMaterialRouteOuterClose(
            JObject request,
            Action onClosed)
        {
            string sourceInstance = ReadString(request, "panelInstanceId");
            if (!HasMaterialReturnRoute(sourceInstance)) return false;
            if (!IsValidNpcShopOuterCloseEnvelope(request)
                && !IsValidNpcShopSystemFailureCloseEnvelope(request)
                || !IsExactActive("npcshop", sourceInstance))
            {
                LogManager.Log(
                    "event=material_shop_close_rejected reason=invalid_or_stale_envelope");
                return true;
            }
            MaterialReturnRoute route = GetExactRoute("npcshop", sourceInstance);
            if (route == null) return true;
            Transition supersededReverse =
                CancelPreCommitReverseForOuterClose(
                    sourceInstance,
                    IsValidNpcShopOuterCloseEnvelope(request)
                        ? "outer_close_" + ReadString(request, "reason")
                        : "system_failure_close");
            Transition transition = BeginTransition(
                TransitionKind.Close,
                null,
                "close\u001f" + sourceInstance,
                "npcshop",
                sourceInstance,
                null,
                false);
            if (transition == null) return true;
            transition.MaterialName = route.MaterialName;
            transition.ShopId = route.ShopId;
            transition.CatalogIndex = route.CatalogIndex;
            transition.IsProcurement = route.IsProcurement;
            transition.RecipeId = route.RecipeId;
            transition.RecipeCategory = route.RecipeCategory;
            transition.RecipeIndex = route.RecipeIndex;
            transition.CharacterCapsule = route.CharacterCapsule;
            transition.CloseCompleted = onClosed;
            if (_panelHost == null || _npcShopTask == null
                || _inventoryTask == null)
            {
                FailTransition(transition, null, false);
                return true;
            }
            if (!TryAcquireOuterCloseTaskFences(transition))
            {
                FailTransition(transition, null, false);
                return true;
            }
            if (!TryQueueOuterClose(transition)
                && !TryDeferOuterCloseUntilReplaceDrains(
                    transition,
                    supersededReverse))
            {
                FailTransition(transition, null, false);
            }
            return true;
        }

        internal void OnPanelChanged(string panelName, string panelInstanceId)
        {
            Transition transition;
            MaterialReturnRoute abandoned = null;
            lock (_lock)
            {
                transition = _active;
                if (_returnRoute != null
                    && (!string.Equals(panelName, _returnRoute.ShopPanel,
                            StringComparison.Ordinal)
                        || !string.Equals(
                            panelInstanceId,
                            _returnRoute.ShopInstance,
                            StringComparison.Ordinal)))
                {
                    abandoned = _returnRoute;
                    _returnRoute = null;
                }
            }
            if (transition != null
                && transition.Phase != TransitionPhase.Committing
                && transition.Phase != TransitionPhase.TargetCommitted
                && (!string.Equals(
                        panelName,
                        transition.SourcePanel,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        panelInstanceId,
                        transition.SourceInstance,
                        StringComparison.Ordinal)))
            {
                CancelTransition(transition, "source_changed");
            }
            if (abandoned != null
                && string.Equals(abandoned.ShopPanel, "npcshop",
                    StringComparison.Ordinal)
                && abandoned.CharacterCapsule != null
                && _commandRouter != null)
            {
                _commandRouter.ConsumeMaterialShopCharacterOnNpcShopCloseNoFail(
                    abandoned.CharacterCapsule,
                    abandoned.ShopInstance);
            }
        }

        internal bool CancelPreCommitForSource(
            string panelName,
            string panelInstanceId,
            string reason)
        {
            Transition transition;
            lock (_lock)
            {
                transition = _active;
                if (transition == null
                    || !string.Equals(
                        transition.SourcePanel,
                        panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        transition.SourceInstance,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return false;
                }
            }
            return CancelTransition(transition, reason);
        }

        /// <summary>
        /// Cancels only the exact pre-commit crafting-to-shop transition and arranges the user's
        /// exact source close after any already-reserved replace has drained.  The callback owns
        /// ordinary WebOverlay close effects and returns whether PanelHost admitted the exact close.
        /// </summary>
        internal bool TryHandlePreCommitCraftingSourceClose(
            string panelName,
            string panelInstanceId,
            Func<bool> tryQueueExactClose)
        {
            if (tryQueueExactClose == null) return false;
            Transition transition;
            lock (_lock)
            {
                transition = _active;
                if (transition == null
                    || transition.Kind != TransitionKind.Forward
                    || !string.Equals(
                        transition.SourcePanel,
                        panelName,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        transition.SourceInstance,
                        panelInstanceId,
                        StringComparison.Ordinal))
                {
                    return false;
                }
            }
            if (!CancelTransition(transition, "source_close")) return false;

            bool dispatchNow;
            lock (_lock)
            {
                transition.DeferredSourceClose = tryQueueExactClose;
                dispatchNow = !transition.ReplacePreparationStarted
                    || (transition.ReplaceDispatchReturned
                        && (!transition.ReplaceQueued
                            || transition.ReplaceCompleted));
                if (dispatchNow)
                    transition.DeferredSourceCloseDispatched = true;
            }
            if (dispatchNow) DispatchDeferredSourceClose(transition);
            return true;
        }

        private Transition CancelPreCommitReverseForOuterClose(
            string sourceInstance,
            string reason)
        {
            Transition transition;
            lock (_lock)
            {
                transition = _active;
                if (transition == null
                    || transition.Kind != TransitionKind.Reverse
                    || !string.Equals(
                        transition.SourcePanel,
                        "npcshop",
                        StringComparison.Ordinal)
                    || !string.Equals(
                        transition.SourceInstance,
                        sourceInstance,
                        StringComparison.Ordinal))
                {
                    return null;
                }
            }
            return CancelTransition(transition, reason)
                ? transition
                : null;
        }

        private bool TryQueueOuterClose(Transition transition)
        {
            if (_panelHost == null) return false;
            return _panelHost.TryClosePanelExact(
                "npcshop",
                transition.SourceInstance,
                true,
                delegate { return TryAcquireCloseCommitPermit(transition); },
                delegate { CommitOuterCloseNoFail(transition); },
                delegate(bool closed)
                {
                    if (closed)
                    {
                        Action completed = transition.CloseCompleted;
                        if (completed != null)
                        {
                            try { completed(); }
                            catch { }
                        }
                    }
                    else
                    {
                        FailTransition(transition, null, true);
                    }
                });
        }

        private bool TryDeferOuterCloseUntilReplaceDrains(
            Transition closeTransition,
            Transition supersededReverse)
        {
            if (supersededReverse == null) return false;
            bool retryNow;
            lock (_lock)
            {
                if (!ReferenceEquals(_active, closeTransition)
                    || closeTransition.Kind != TransitionKind.Close
                    || closeTransition.Phase
                        != TransitionPhase.TaskFencesAcquired)
                {
                    return false;
                }
                closeTransition.WaitForReplaceDrain = supersededReverse;
                retryNow = supersededReverse.ReplaceCompleted
                    || (supersededReverse.ReverseDispatchReturned
                        && !supersededReverse.ReplaceQueued);
            }
            if (retryNow)
                RetryDeferredOuterCloseAfter(supersededReverse);
            return true;
        }

        private void MarkReverseDispatchReturned(Transition reverseTransition)
        {
            bool retry;
            lock (_lock)
            {
                reverseTransition.ReverseDispatchReturned = true;
                retry = !reverseTransition.ReplaceQueued
                    && _active != null
                    && _active.Kind == TransitionKind.Close
                    && ReferenceEquals(
                        _active.WaitForReplaceDrain,
                        reverseTransition);
            }
            if (retry) RetryDeferredOuterCloseAfter(reverseTransition);
        }

        private void MarkReplaceDispatchReturned(Transition transition)
        {
            bool dispatch;
            lock (_lock)
            {
                transition.ReplaceDispatchReturned = true;
                dispatch = transition.DeferredSourceClose != null
                    && !transition.DeferredSourceCloseDispatched
                    && (!transition.ReplaceQueued
                        || transition.ReplaceCompleted);
                if (dispatch)
                    transition.DeferredSourceCloseDispatched = true;
            }
            if (dispatch) DispatchDeferredSourceClose(transition);
        }

        private void TryDispatchDeferredSourceCloseAfter(
            Transition drainedForward)
        {
            bool dispatch;
            lock (_lock)
            {
                dispatch = drainedForward.DeferredSourceClose != null
                    && !drainedForward.DeferredSourceCloseDispatched
                    && drainedForward.ReplaceCompleted;
                if (dispatch)
                    drainedForward.DeferredSourceCloseDispatched = true;
            }
            if (dispatch) DispatchDeferredSourceClose(drainedForward);
        }

        private static void DispatchDeferredSourceClose(Transition transition)
        {
            Func<bool> callback = transition.DeferredSourceClose;
            if (callback == null) return;
            try
            {
                if (!callback())
                {
                    LogManager.Log(
                        "event=material_shop_source_close_rejected reason=host_admission_failed");
                }
            }
            catch (Exception ex)
            {
                LogManager.Log(
                    "event=material_shop_source_close_rejected reason=callback_threw type="
                    + ex.GetType().Name);
            }
        }

        private void RetryDeferredOuterCloseAfter(
            Transition drainedReverse)
        {
            Transition closeTransition;
            lock (_lock)
            {
                closeTransition = _active;
                if (closeTransition == null
                    || closeTransition.Kind != TransitionKind.Close
                    || !ReferenceEquals(
                        closeTransition.WaitForReplaceDrain,
                        drainedReverse))
                {
                    return;
                }
                closeTransition.WaitForReplaceDrain = null;
            }
            if (!TryQueueOuterClose(closeTransition))
                FailTransition(closeTransition, null, false);
        }

        internal void CancelAll(string reason)
        {
            Transition transition;
            MaterialReturnRoute route;
            lock (_lock)
            {
                transition = _active;
                bool commitInProgress = transition != null
                    && transition.Phase == TransitionPhase.Committing;
                route = commitInProgress ? null : _returnRoute;
                if (!commitInProgress) _returnRoute = null;
            }
            if (transition != null)
                CancelTransition(transition, reason);
            if (route != null && route.CharacterCapsule != null
                && _commandRouter != null)
            {
                _commandRouter.ConsumeMaterialShopCharacterOnNpcShopCloseNoFail(
                    route.CharacterCapsule,
                    route.ShopInstance);
            }
            if (_accessTask != null) _accessTask.ClearPending();
        }

        public void Dispose()
        {
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
            }
            CancelAll("disposed");
        }

        internal static bool IsValidForwardEnvelope(JObject request)
        {
            return HasExactKeys(
                    request,
                    "type", "panel", "cmd", "callId", "panelInstanceId", "source",
                    "materialSnapshotId", "materialName", "shopId", "catalogIndex")
                && HasString(request["type"], "panel")
                && HasString(request["panel"], "crafting")
                && HasString(request["cmd"], "open_npc_shop")
                && HasString(request["source"], "crafting_materials")
                && IsValidCallId(request["callId"])
                && IsValidPanelInstance(request["panelInstanceId"])
                && IsIdentity(request["materialSnapshotId"], 256)
                && IsIdentity(request["materialName"], 128)
                && IsIdentity(request["shopId"], 80)
                && IsIntegerInRange(request["catalogIndex"], 0, 10000);
        }

        internal static bool IsValidProcurementForwardEnvelope(JObject request)
        {
            return HasExactKeys(
                    request,
                    "type", "panel", "cmd", "callId", "panelInstanceId", "source",
                    "materialName", "shopId", "catalogIndex",
                    "recipeId", "category", "recipeIndex")
                && HasString(request["type"], "panel")
                && HasString(request["panel"], "crafting")
                && HasString(request["cmd"], "open_procurement_shop")
                && HasString(request["source"], "crafting_recipe")
                && IsValidCallId(request["callId"])
                && IsValidPanelInstance(request["panelInstanceId"])
                && IsIdentity(request["materialName"], 128)
                && IsIdentity(request["shopId"], 80)
                && IsIntegerInRange(request["catalogIndex"], 0, 10000)
                && ProcurementProjectionValidator.IsRecipeId(request["recipeId"])
                && IsIdentity(request["category"], 256)
                && IsIntegerInRange(request["recipeIndex"], 0, 999);
        }

        internal static bool IsValidProcurementKShopForwardEnvelope(JObject request)
        {
            return HasExactKeys(
                    request,
                    "type", "panel", "cmd", "callId", "panelInstanceId", "source",
                    "materialName", "catalogIndex", "entryId",
                    "kshopCategory", "recipeId", "recipeCategory", "recipeIndex")
                && HasString(request["type"], "panel")
                && HasString(request["panel"], "crafting")
                && HasString(request["cmd"], "open_procurement_kshop")
                && HasString(request["source"], "crafting_recipe")
                && IsValidCallId(request["callId"])
                && IsValidPanelInstance(request["panelInstanceId"])
                && IsIdentity(request["materialName"], 128)
                && IsIntegerInRange(request["catalogIndex"], 0, 10000)
                && IsIdentity(request["entryId"], 256)
                && IsIdentity(request["kshopCategory"], 512)
                && ProcurementProjectionValidator.IsRecipeId(request["recipeId"])
                && IsIdentity(request["recipeCategory"], 256)
                && IsIntegerInRange(request["recipeIndex"], 0, 999);
        }

        internal static bool IsValidReverseEnvelope(JObject request)
        {
            return HasExactKeys(
                    request,
                    "type", "panel", "cmd", "callId", "panelInstanceId")
                && HasString(request["type"], "panel")
                && HasString(request["panel"], "npcshop")
                && HasString(request["cmd"], "return_crafting_materials")
                && IsValidCallId(request["callId"])
                && IsValidPanelInstance(request["panelInstanceId"]);
        }

        internal static bool IsValidRecipeReverseEnvelope(JObject request)
        {
            return HasExactKeys(
                    request,
                    "type", "panel", "cmd", "callId", "panelInstanceId")
                && HasString(request["type"], "panel")
                && HasString(request["panel"], "npcshop")
                && HasString(request["cmd"], "return_crafting_recipe")
                && IsValidCallId(request["callId"])
                && IsValidPanelInstance(request["panelInstanceId"]);
        }

        internal static bool IsValidKShopRecipeReverseEnvelope(JObject request)
        {
            return HasExactKeys(
                    request,
                    "type", "panel", "cmd", "callId", "panelInstanceId")
                && HasString(request["type"], "panel")
                && HasString(request["panel"], "kshop")
                && HasString(request["cmd"], "return_crafting_recipe")
                && IsValidCallId(request["callId"])
                && IsValidPanelInstance(request["panelInstanceId"]);
        }

        internal static bool IsValidNpcShopOuterCloseEnvelope(JObject request)
        {
            if (!HasExactKeys(
                    request,
                    "type", "panel", "cmd", "panelInstanceId", "reason")
                || !HasString(request["type"], "panel")
                || !HasString(request["panel"], "npcshop")
                || !HasString(request["cmd"], "close")
                || !IsValidPanelInstance(request["panelInstanceId"]))
            {
                return false;
            }
            string reason = ReadString(request, "reason");
            return reason == "button" || reason == "escape"
                || reason == "backdrop" || reason == "toggle";
        }

        internal static bool IsValidNpcShopSystemFailureCloseEnvelope(
            JObject request)
        {
            return HasExactKeys(
                    request,
                    "type", "panel", "cmd", "panelInstanceId")
                && HasString(request["type"], "panel")
                && HasString(request["panel"], "npcshop")
                && HasString(request["cmd"], "close")
                && IsValidPanelInstance(request["panelInstanceId"]);
        }

        internal static bool HasValidFailureCorrelation(JObject request)
        {
            return request != null
                && IsValidCallId(request["callId"])
                && IsValidPanelInstance(request["panelInstanceId"]);
        }

        private void HandleAuthorityResult(
            Transition transition,
            MaterialShopAccessTask.Result result)
        {
            if (!IsAuthorityFenceCurrent(transition)) return;
            if (result == null
                || result.Kind != MaterialShopAccessTask.ResultKind.Allowed)
            {
                string error = MapAuthorityFailure(result);
                FailTransition(transition, error, false);
                return;
            }
            if (!string.Equals(
                    result.ItemName,
                    transition.MaterialName,
                    StringComparison.Ordinal)
                || !AreForwardWitnessesCurrent(transition))
            {
                FailTransition(transition, "stale_source", false);
                return;
            }
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase != TransitionPhase.AuthorityPending)
                {
                    return;
                }
                transition.ReplacePreparationStarted = true;
            }
            try
            {
                PrepareForwardReplacement(transition, result.ItemName);
            }
            finally
            {
                MarkReplaceDispatchReturned(transition);
            }
        }

        private void PrepareForwardReplacement(
            Transition transition,
            string authoritativeItemName)
        {
            string targetInstance;
            try { targetInstance = _nextPanelInstanceId(); }
            catch { targetInstance = null; }
            if (!ValidPanelInstanceId.IsMatch(targetInstance ?? ""))
            {
                FailTransition(transition, "navigation_unavailable", false);
                return;
            }
            LauncherCommandRouter.MaterialShopCharacterCapsule capsule = null;
            if (transition.IsKShop)
            {
                bool opened;
                try { opened = _tryOpenKShop != null && _tryOpenKShop(); }
                catch { opened = false; }
                if (!opened)
                {
                    FailTransition(transition, "admission_failed", false);
                    return;
                }
                transition.KShopPauseOpened = true;
            }
            else if (!_commandRouter.TryPrepareMaterialShopCharacterForward(
                    transition.SourceInstance, targetInstance, out capsule))
            {
                FailTransition(transition, "admission_failed", false);
                return;
            }
            transition.TargetPanel = transition.IsKShop ? "kshop" : "npcshop";
            transition.TargetInstance = targetInstance;
            transition.CharacterCapsule = capsule;
            var init = new JObject
            {
                ["mode"] = "runtime",
                ["source"] = transition.IsKShop ? "crafting_procurement"
                    : transition.IsProcurement ? "crafting_procurement" : "crafting_materials",
                ["debug"] = false,
                ["preferredItemName"] = authoritativeItemName,
                ["preferredCatalogIndex"] = transition.CatalogIndex,
                ["navigationOrigin"] = transition.IsProcurement
                    ? "crafting_recipe"
                    : "crafting_materials",
                ["panelInstanceId"] = targetInstance
            };
            if (transition.IsKShop)
            {
                init["preferredEntryId"] = transition.EntryId;
                init["preferredKShopCategory"] = transition.KShopCategory;
            }
            else init["shopId"] = transition.ShopId;
            if (transition.IsProcurement)
            {
                init["canReturnCraftingRecipe"] = true;
                init["returnRecipeCategory"] = transition.RecipeCategory;
                init["returnRecipeIndex"] = transition.RecipeIndex;
            }
            else init["canReturnCraftingMaterials"] = true;
            if (!AdvancePhase(
                    transition,
                    TransitionPhase.AuthorityPending,
                    TransitionPhase.TargetReserved))
            {
                FailTransition(transition, "navigation_unavailable", false);
                return;
            }
            var plan = new PreparedPanelReplace(
                transition.TargetPanel,
                targetInstance,
                init.ToString(Formatting.None),
                delegate { CommitForwardNoFail(transition); },
                delegate
                {
                    AbortTransitionCapsule(transition);
                    ReleaseLeasesOnce(transition);
                },
                delegate { MarkTargetCommitted(transition); });
            bool queued = _panelHost.TryReplacePanelExact(
                "crafting",
                transition.SourceInstance,
                plan,
                delegate { return TryAcquireReplaceCommitPermit(transition); },
                delegate(PanelHostController.ExactReplaceOutcome outcome)
                {
                    ObserveReplaceOutcome(transition, outcome);
                });
            lock (_lock) transition.ReplaceQueued = queued;
            if (!queued)
                FailTransition(transition, "admission_failed", false);
        }

        private void PrepareReverseReplacement(Transition transition)
        {
            string targetInstance;
            try { targetInstance = _nextPanelInstanceId(); }
            catch { targetInstance = null; }
            if (!ValidPanelInstanceId.IsMatch(targetInstance ?? "")
                || !transition.IsKShop
                    && !_commandRouter.TryPrepareMaterialShopCharacterReverse(
                        transition.CharacterCapsule,
                        transition.SourceInstance,
                        targetInstance))
            {
                FailTransition(transition, "admission_failed", false);
                return;
            }
            transition.TargetPanel = "crafting";
            transition.TargetInstance = targetInstance;
            var init = new JObject
            {
                ["mode"] = "runtime",
                ["source"] = transition.IsKShop ? "kshop_return" : "npcshop_return",
                ["debug"] = false,
                ["panelInstanceId"] = targetInstance
            };
            if (transition.IsProcurement)
            {
                init["view"] = "recipes";
                init["category"] = transition.RecipeCategory;
                init["preferredRecipeIndex"] = transition.RecipeIndex;
                init["preferredCraftCount"] = 1;
            }
            else
            {
                init["view"] = "materials";
                init["preferredMaterialName"] = transition.MaterialName;
            }
            if (!transition.IsProcurement && transition.CharacterCapsule != null)
            {
                init["canReturnCharacterBuild"] = true;
                init["navigationOrigin"] = "character_build";
            }
            if (!AdvancePhase(
                    transition,
                    TransitionPhase.TaskFencesAcquired,
                    TransitionPhase.TargetReserved))
            {
                AbortReverseCapsule(transition);
                FailTransition(transition, "navigation_unavailable", false);
                return;
            }
            var plan = new PreparedPanelReplace(
                "crafting",
                targetInstance,
                init.ToString(Formatting.None),
                delegate { CommitReverseNoFail(transition); },
                delegate
                {
                    AbortTransitionCapsule(transition);
                    ReleaseLeasesOnce(transition);
                },
                delegate { MarkTargetCommitted(transition); });
            bool queued = _panelHost.TryReplacePanelExact(
                transition.SourcePanel,
                transition.SourceInstance,
                plan,
                delegate { return TryAcquireReplaceCommitPermit(transition); },
                delegate(PanelHostController.ExactReplaceOutcome outcome)
                {
                    ObserveReplaceOutcome(transition, outcome);
                });
            lock (_lock) transition.ReplaceQueued = queued;
            if (!queued)
                FailTransition(transition, "admission_failed", false);
        }

        private void ObserveReplaceOutcome(
            Transition transition,
            PanelHostController.ExactReplaceOutcome outcome)
        {
            lock (_lock) transition.ReplaceCompleted = true;
            if (outcome != PanelHostController.ExactReplaceOutcome.TargetCommitted)
            {
                string error;
                switch (outcome)
                {
                    case PanelHostController.ExactReplaceOutcome.SourceMismatch:
                        error = "stale_source";
                        break;
                    case PanelHostController.ExactReplaceOutcome.PreExecutionRejected:
                        error = IsDeadlineExpired(transition)
                            ? "timeout"
                            : "admission_failed";
                        break;
                    case PanelHostController.ExactReplaceOutcome.PostNotDelivered:
                    case PanelHostController.ExactReplaceOutcome.HostUnavailable:
                    default:
                        error = "navigation_unavailable";
                        break;
                }
                FailTransition(transition, error, true);
            }
            RetryDeferredOuterCloseAfter(transition);
            TryDispatchDeferredSourceCloseAfter(transition);
        }

        private Transition BeginTransition(
            TransitionKind kind,
            string callId,
            string signature,
            string sourcePanel,
            string sourceInstance,
            string responseCommand,
            bool respondBusy)
        {
            Transition transition;
            bool busy = false;
            bool unavailable = false;
            IDisposable orphanedDeadline = null;
            lock (_lock)
            {
                if (_disposed) return null;
                if (_active != null)
                {
                    if (!string.IsNullOrEmpty(callId)
                        && string.Equals(
                            callId,
                            _active.CallId,
                            StringComparison.Ordinal))
                    {
                        LogManager.Log(
                            string.Equals(
                                signature,
                                _active.Signature,
                                StringComparison.Ordinal)
                                ? "event=material_shop_navigation_duplicate_coalesced"
                                : "event=material_shop_navigation_duplicate_conflict");
                        return null;
                    }
                    busy = true;
                    transition = null;
                }
                else
                {
                    long now = _nowMs();
                    transition = new Transition
                    {
                        Kind = kind,
                        Phase = TransitionPhase.TokenCreated,
                        Token = OpaqueIdGenerator.Create("materialshop"),
                        CallId = callId,
                        Signature = signature,
                        ResponseCommand = responseCommand,
                        SourcePanel = sourcePanel,
                        SourceInstance = sourceInstance,
                        DeadlineAtMs = now + MaterialShopNavigationTimeoutMs
                    };
                    _active = transition;
                    // The lifecycle token is visible before scheduling any asynchronous callback.
                    try
                    {
                        IDisposable scheduled = _schedule(
                            MaterialShopNavigationTimeoutMs,
                            delegate { OnDeadline(transition); });
                        if (scheduled == null)
                            throw new InvalidOperationException(
                                "Material shop deadline scheduling returned null.");
                        if (ReferenceEquals(_active, transition))
                            transition.Deadline = scheduled;
                        else
                        {
                            orphanedDeadline = scheduled;
                            transition = null;
                        }
                    }
                    catch
                    {
                        if (ReferenceEquals(_active, transition))
                            _active = null;
                        transition = null;
                        unavailable = true;
                    }
                }
            }
            DisposeQuietly(orphanedDeadline);
            if (busy && respondBusy)
            {
                PostFailure(
                    sourcePanel,
                    responseCommand,
                    callId,
                    sourceInstance,
                    "busy");
            }
            else if (unavailable && respondBusy)
            {
                PostFailure(
                    sourcePanel,
                    responseCommand,
                    callId,
                    sourceInstance,
                    "navigation_unavailable");
            }
            return transition;
        }

        private bool AdvancePhase(
            Transition transition,
            TransitionPhase expected,
            TransitionPhase next)
        {
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase != expected
                    || IsDeadlineExpiredLocked(transition)) return false;
                transition.Phase = next;
                return true;
            }
        }

        private bool TryAcquireForwardTaskFences(Transition transition)
        {
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase != TransitionPhase.TokenCreated
                    || IsDeadlineExpiredLocked(transition)) return false;
                bool craftingAcquired = transition.IsProcurement
                    ? _craftingTask.TryAcquireRecipeShopNavigationLease(
                        "crafting",
                        transition.SourceInstance,
                        transition.Token,
                        transition.RecipeCategory,
                        transition.RecipeIndex,
                        transition.MaterialName,
                        transition.ShopId,
                        transition.CatalogIndex,
                        transition.IsKShop,
                        transition.EntryId,
                        transition.KShopCategory,
                        out transition.CraftingWitness)
                    : _craftingTask.TryAcquireMaterialShopNavigationLease(
                        "crafting",
                        transition.SourceInstance,
                        transition.Token,
                        transition.MaterialSnapshotId,
                        transition.MaterialName,
                        out transition.CraftingWitness);
                if (!craftingAcquired) return false;
                if (!_inventoryTask.TryAcquireMaterialShopNavigationLease(
                        "crafting",
                        transition.SourceInstance,
                        transition.Token,
                        out transition.InventoryWitness)) return false;
                if (IsDeadlineExpiredLocked(transition)) return false;
                transition.Phase = TransitionPhase.TaskFencesAcquired;
                return true;
            }
        }

        private bool TryAcquireReverseTaskFences(Transition transition)
        {
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase != TransitionPhase.TokenCreated
                    || IsDeadlineExpiredLocked(transition)) return false;
                if (transition.IsKShop)
                {
                    if (!_shopTask.TryAcquireMaterialShopNavigationLease(
                            "kshop", transition.SourceInstance, transition.Token,
                            out transition.ShopWitness)) return false;
                }
                else if (!_npcShopTask.TryAcquireMaterialShopNavigationLease(
                        "npcshop", transition.SourceInstance, transition.Token,
                        transition.ShopId, out transition.NpcShopWitness)) return false;
                if (!_inventoryTask.TryAcquireMaterialShopNavigationLease(
                        transition.SourcePanel,
                        transition.SourceInstance,
                        transition.Token,
                        out transition.InventoryWitness)) return false;
                if (IsDeadlineExpiredLocked(transition)) return false;
                transition.Phase = TransitionPhase.TaskFencesAcquired;
                return true;
            }
        }

        private bool TryAcquireOuterCloseTaskFences(Transition transition)
        {
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Kind != TransitionKind.Close
                    || transition.Phase != TransitionPhase.TokenCreated
                    || IsDeadlineExpiredLocked(transition)) return false;
                if (!_npcShopTask.TryAcquireMaterialShopCloseLease(
                        "npcshop",
                        transition.SourceInstance,
                        transition.Token,
                        out transition.NpcShopWitness)) return false;
                if (!_inventoryTask.TryAcquireMaterialShopNavigationLease(
                        "npcshop",
                        transition.SourceInstance,
                        transition.Token,
                        out transition.InventoryWitness)) return false;
                if (IsDeadlineExpiredLocked(transition)) return false;
                transition.Phase = TransitionPhase.TaskFencesAcquired;
                return true;
            }
        }

        private bool TryAcquireReplaceCommitPermit(Transition transition)
        {
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase != TransitionPhase.TargetReserved
                    || IsDeadlineExpiredLocked(transition)) return false;
                if (!IsExactActive(
                        transition.SourcePanel,
                        transition.SourceInstance)) return false;
                if (transition.Kind == TransitionKind.Forward)
                {
                    if (!AreForwardWitnessesCurrent(transition)) return false;
                    if (!transition.IsKShop
                        && (!_commandRouter.IsMaterialShopCharacterForwardCurrent(
                                transition.CharacterCapsule,
                                transition.SourceInstance,
                                transition.TargetInstance)
                            || !_commandRouter.TrySealMaterialShopCharacterForwardCommit(
                                transition.CharacterCapsule,
                                transition.SourceInstance,
                                transition.TargetInstance))) return false;
                }
                else
                {
                    if (!AreReverseWitnessesCurrent(transition)
                        || !IsExactRouteCurrent(transition)) return false;
                    if (!transition.IsKShop
                        && (!_commandRouter.IsMaterialShopCharacterReverseCurrent(
                                transition.CharacterCapsule,
                                transition.SourceInstance,
                                transition.TargetInstance)
                            || !_commandRouter.TrySealMaterialShopCharacterReverseCommit(
                                transition.CharacterCapsule,
                                transition.SourceInstance,
                                transition.TargetInstance))) return false;
                }
                transition.Phase = TransitionPhase.Committing;
                return true;
            }
        }

        private bool TryAcquireCloseCommitPermit(Transition transition)
        {
            if (!AreOuterCloseWitnessesCurrent(transition)
                || !IsExactActive("npcshop", transition.SourceInstance)
                || !IsExactRouteCurrent(transition)) return false;
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase
                        != TransitionPhase.TaskFencesAcquired
                    || IsDeadlineExpiredLocked(transition)) return false;
                transition.Phase = TransitionPhase.Committing;
                return true;
            }
        }

        private void CommitForwardNoFail(Transition transition)
        {
            _craftingTask.TransferMaterialShopNavigationLease(
                transition.CraftingWitness);
            _inventoryTask.TransferMaterialShopNavigationLease(
                transition.InventoryWitness);
            if (transition.IsKShop) transition.KShopPauseTransferred = true;
            else _commandRouter.CommitMaterialShopCharacterForwardNoFail(
                    transition.CharacterCapsule);
            lock (_lock)
            {
                _returnRoute = new MaterialReturnRoute
                {
                    ShopPanel = transition.TargetPanel,
                    ShopInstance = transition.TargetInstance,
                    MaterialName = transition.MaterialName,
                    ShopId = transition.ShopId,
                    CatalogIndex = transition.CatalogIndex,
                    IsProcurement = transition.IsProcurement,
                    RecipeId = transition.RecipeId,
                    RecipeCategory = transition.RecipeCategory,
                    RecipeIndex = transition.RecipeIndex,
                    EntryId = transition.EntryId,
                    KShopCategory = transition.KShopCategory,
                    CharacterCapsule = transition.CharacterCapsule
                };
                transition.LeasesTerminal = true;
            }
        }

        private void CommitReverseNoFail(Transition transition)
        {
            if (transition.IsKShop)
                _shopTask.TransferMaterialShopNavigationLease(transition.ShopWitness);
            else _npcShopTask.TransferMaterialShopNavigationLease(
                    transition.NpcShopWitness);
            _inventoryTask.TransferMaterialShopNavigationLease(
                transition.InventoryWitness);
            if (transition.IsKShop)
            {
                try { _closeKShopNoFail(); }
                catch { }
            }
            else _commandRouter.CommitMaterialShopCharacterReverseNoFail(
                    transition.CharacterCapsule, transition.TargetInstance);
            lock (_lock)
            {
                if (_returnRoute != null
                    && string.Equals(
                        _returnRoute.ShopInstance,
                        transition.SourceInstance,
                        StringComparison.Ordinal))
                {
                    _returnRoute = null;
                }
                transition.LeasesTerminal = true;
            }
        }

        private void CommitOuterCloseNoFail(Transition transition)
        {
            _npcShopTask.TransferMaterialShopNavigationLease(
                transition.NpcShopWitness);
            _inventoryTask.TransferMaterialShopNavigationLease(
                transition.InventoryWitness);
            _commandRouter.ConsumeMaterialShopCharacterOnNpcShopCloseNoFail(
                transition.CharacterCapsule,
                transition.SourceInstance);
            IDisposable deadline;
            lock (_lock)
            {
                if (_returnRoute != null
                    && string.Equals(
                        _returnRoute.ShopInstance,
                        transition.SourceInstance,
                        StringComparison.Ordinal))
                {
                    _returnRoute = null;
                }
                transition.LeasesTerminal = true;
                transition.Phase = TransitionPhase.TargetCommitted;
                if (ReferenceEquals(_active, transition)) _active = null;
                deadline = transition.Deadline;
                transition.Deadline = null;
            }
            DisposeQuietly(deadline);
        }

        private void MarkTargetCommitted(Transition transition)
        {
            IDisposable deadline;
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase != TransitionPhase.Committing) return;
                transition.Phase = TransitionPhase.TargetCommitted;
                _active = null;
                deadline = transition.Deadline;
                transition.Deadline = null;
            }
            DisposeQuietly(deadline);
        }

        private void AbortReverseCapsule(Transition transition)
        {
            if (_commandRouter == null) return;
            _commandRouter.AbortMaterialShopCharacterReverseNoFail(
                transition.CharacterCapsule,
                transition.SourceInstance,
                transition.TargetInstance);
        }

        private void AbortTransitionCapsule(Transition transition)
        {
            if (transition == null) return;
            if (transition.IsKShop)
            {
                if (transition.Kind == TransitionKind.Forward
                    && transition.KShopPauseOpened
                    && !transition.KShopPauseTransferred)
                {
                    transition.KShopPauseOpened = false;
                    try { _closeKShopNoFail?.Invoke(); }
                    catch { }
                }
                return;
            }
            if (_commandRouter == null) return;
            if (transition.Kind == TransitionKind.Forward)
            {
                _commandRouter.AbortMaterialShopCharacterForwardNoFail(
                    transition.CharacterCapsule,
                    transition.SourceInstance,
                    transition.TargetInstance);
            }
            else if (transition.Kind == TransitionKind.Reverse)
            {
                AbortReverseCapsule(transition);
            }
        }

        private void OnDeadline(Transition transition)
        {
            FailTransition(transition, "timeout", false);
        }

        private bool CancelTransition(Transition transition, string reason)
        {
            if (TryTerminate(
                    transition,
                    TransitionPhase.Cancelled,
                    false,
                    out IDisposable deadline,
                    out int fid))
            {
                AbortTransitionCapsule(transition);
                if (fid > 0 && _accessTask != null) _accessTask.Cancel(fid);
                DisposeQuietly(deadline);
                ReleaseLeasesOnce(transition);
                LogManager.Log(
                    "event=material_shop_navigation_cancelled reason="
                    + (reason ?? "unknown"));
                return true;
            }
            return false;
        }

        private void FailTransition(
            Transition transition,
            string error,
            bool allowCommitting)
        {
            if (!TryTerminate(
                    transition,
                    TransitionPhase.Failed,
                    allowCommitting,
                    out IDisposable deadline,
                    out int fid)) return;
            AbortTransitionCapsule(transition);
            if (fid > 0 && _accessTask != null) _accessTask.Cancel(fid);
            DisposeQuietly(deadline);
            ReleaseLeasesOnce(transition);
            if (!string.IsNullOrEmpty(error)
                && !string.IsNullOrEmpty(transition.CallId))
            {
                PostFailure(
                    transition.SourcePanel,
                    transition.ResponseCommand,
                    transition.CallId,
                    transition.SourceInstance,
                    error);
            }
        }

        private bool TryTerminate(
            Transition transition,
            TransitionPhase terminal,
            bool allowCommitting,
            out IDisposable deadline,
            out int fid)
        {
            deadline = null;
            fid = 0;
            lock (_lock)
            {
                if (!ReferenceEquals(_active, transition)
                    || transition.Phase == TransitionPhase.TargetCommitted
                    || transition.Phase == TransitionPhase.Failed
                    || transition.Phase == TransitionPhase.Cancelled
                    || (transition.Phase == TransitionPhase.Committing
                        && !allowCommitting)) return false;
                transition.Phase = terminal;
                _active = null;
                deadline = transition.Deadline;
                transition.Deadline = null;
                fid = transition.AuthorityFid;
                return true;
            }
        }

        private void ReleaseLeasesOnce(Transition transition)
        {
            bool release;
            lock (_lock)
            {
                release = !transition.LeasesTerminal;
                transition.LeasesTerminal = true;
            }
            if (!release) return;
            // Reverse acquisition order for both fixed routes.
            if (transition.InventoryWitness != null && _inventoryTask != null)
                _inventoryTask.ReleaseMaterialShopNavigationLease(
                    transition.InventoryWitness);
            if (transition.Kind == TransitionKind.Forward)
            {
                if (transition.CraftingWitness != null && _craftingTask != null)
                    _craftingTask.ReleaseMaterialShopNavigationLease(
                        transition.CraftingWitness);
            }
            else if (transition.IsKShop
                && transition.ShopWitness != null && _shopTask != null)
            {
                _shopTask.ReleaseMaterialShopNavigationLease(
                    transition.ShopWitness);
            }
            else if (transition.NpcShopWitness != null && _npcShopTask != null)
            {
                _npcShopTask.ReleaseMaterialShopNavigationLease(
                    transition.NpcShopWitness);
            }
        }

        private bool AreForwardWitnessesCurrent(Transition transition)
        {
            return _craftingTask != null
                && _inventoryTask != null
                && _craftingTask.IsMaterialShopNavigationLeaseCurrent(
                    transition.CraftingWitness)
                && _inventoryTask.IsMaterialShopNavigationLeaseCurrent(
                    transition.InventoryWitness);
        }

        private bool AreReverseWitnessesCurrent(Transition transition)
        {
            bool shopCurrent = transition.IsKShop
                ? _shopTask != null
                    && _shopTask.IsMaterialShopNavigationLeaseCurrent(
                        transition.ShopWitness)
                : _npcShopTask != null
                    && _npcShopTask.IsMaterialShopNavigationLeaseCurrent(
                        transition.NpcShopWitness);
            return shopCurrent && _inventoryTask != null
                && _inventoryTask.IsMaterialShopNavigationLeaseCurrent(
                    transition.InventoryWitness);
        }

        private bool AreOuterCloseWitnessesCurrent(Transition transition)
        {
            return _npcShopTask != null
                && _inventoryTask != null
                && _npcShopTask.IsMaterialShopCloseLeaseCurrent(
                    transition.NpcShopWitness)
                && _inventoryTask.IsMaterialShopNavigationLeaseCurrent(
                    transition.InventoryWitness);
        }

        private bool IsAuthorityFenceCurrent(Transition transition)
        {
            lock (_lock)
            {
                return ReferenceEquals(_active, transition)
                    && transition.Phase == TransitionPhase.AuthorityPending
                    && !IsDeadlineExpiredLocked(transition);
            }
        }

        private bool IsExactRouteCurrent(Transition transition)
        {
            lock (_lock)
            {
                return _returnRoute != null
                    && string.Equals(_returnRoute.ShopPanel, transition.SourcePanel,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _returnRoute.ShopInstance,
                        transition.SourceInstance,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _returnRoute.MaterialName,
                        transition.MaterialName,
                        StringComparison.Ordinal)
                    && string.Equals(
                        _returnRoute.ShopId,
                        transition.ShopId,
                        StringComparison.Ordinal)
                    && _returnRoute.CatalogIndex == transition.CatalogIndex
                    && _returnRoute.IsProcurement == transition.IsProcurement
                    && string.Equals(_returnRoute.RecipeId, transition.RecipeId,
                        StringComparison.Ordinal)
                    && string.Equals(_returnRoute.RecipeCategory,
                        transition.RecipeCategory, StringComparison.Ordinal)
                    && _returnRoute.RecipeIndex == transition.RecipeIndex
                    && string.Equals(_returnRoute.EntryId, transition.EntryId,
                        StringComparison.Ordinal)
                    && string.Equals(_returnRoute.KShopCategory,
                        transition.KShopCategory, StringComparison.Ordinal)
                    && ReferenceEquals(
                        _returnRoute.CharacterCapsule,
                        transition.CharacterCapsule);
            }
        }

        private MaterialReturnRoute GetExactRoute(
            string shopPanel,
            string shopInstance)
        {
            lock (_lock)
            {
                if (_returnRoute == null
                    || !string.Equals(_returnRoute.ShopPanel, shopPanel,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        _returnRoute.ShopInstance,
                        shopInstance,
                        StringComparison.Ordinal)) return null;
                return _returnRoute;
            }
        }

        private bool IsExactActive(string panel, string panelInstanceId)
        {
            string activePanel = _panelHost != null
                ? _panelHost.ActivePanelName
                : (_commandRouter != null
                    ? _commandRouter.ActiveFallbackPanelName
                    : null);
            string activeInstance = _panelHost != null
                ? _panelHost.ActivePanelInstanceId
                : (_commandRouter != null
                    ? _commandRouter.ActiveFallbackPanelInstanceId
                    : null);
            return string.Equals(activePanel, panel, StringComparison.Ordinal)
                && string.Equals(
                    activeInstance,
                    panelInstanceId,
                    StringComparison.Ordinal);
        }

        private void RespondMalformedIfOwned(
            JObject request,
            string panel,
            string cmd)
        {
            string callId = ReadString(request, "callId");
            string instance = ReadString(request, "panelInstanceId");
            if (ValidCallId.IsMatch(callId ?? "")
                && ValidPanelInstanceId.IsMatch(instance ?? "")
                && IsExactActive(panel, instance))
            {
                PostFailure(panel, cmd, callId, instance, "invalid_payload");
            }
        }

        private void PostFailure(
            string panel,
            string cmd,
            string callId,
            string panelInstanceId,
            string error)
        {
            if (!IsExactActive(panel, panelInstanceId)) return;
            var response = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = panel,
                ["cmd"] = cmd,
                ["callId"] = callId,
                ["panelInstanceId"] = panelInstanceId,
                ["success"] = false,
                ["error"] = error
            };
            try { _tryPostToWeb(response.ToString(Formatting.None)); }
            catch { }
        }

        private static string MapAuthorityFailure(
            MaterialShopAccessTask.Result result)
        {
            if (result == null) return "navigation_unavailable";
            if (result.Kind == MaterialShopAccessTask.ResultKind.Stale)
                return "stale_source";
            if (result.Kind == MaterialShopAccessTask.ResultKind.Denied
                && string.Equals(
                    result.Error,
                    "access_denied",
                    StringComparison.Ordinal)) return "access_denied";
            if (result.Kind == MaterialShopAccessTask.ResultKind.Denied
                && string.Equals(
                    result.Error,
                    "invalid_payload",
                    StringComparison.Ordinal))
            {
                LogManager.Log(
                    "event=material_shop_authority_contract_violation error=invalid_payload");
            }
            return "navigation_unavailable";
        }

        private bool IsDeadlineExpired(Transition transition)
        {
            lock (_lock) return IsDeadlineExpiredLocked(transition);
        }

        private bool IsDeadlineExpiredLocked(Transition transition)
        {
            return _nowMs() >= transition.DeadlineAtMs;
        }

        private static IDisposable DefaultSchedule(int milliseconds, Action callback)
        {
            return new Timer(
                delegate(object state)
                {
                    try { callback(); }
                    catch { }
                },
                null,
                milliseconds,
                Timeout.Infinite);
        }

        private static void DisposeQuietly(IDisposable value)
        {
            if (value == null) return;
            try { value.Dispose(); }
            catch { }
        }

        private static string BuildForwardSignature(
            string instance,
            string snapshot,
            string material,
            string shop,
            int index,
            string recipeId,
            string recipeCategory,
            int recipeIndex,
            bool isKShop,
            string entryId,
            string kshopCategory)
        {
            return "forward\u001f" + instance + "\u001f" + snapshot
                + "\u001f" + material + "\u001f" + shop + "\u001f" + index
                + "\u001f" + (recipeId ?? "") + "\u001f" + (recipeCategory ?? "")
                + "\u001f" + recipeIndex + "\u001f" + isKShop
                + "\u001f" + (entryId ?? "") + "\u001f" + (kshopCategory ?? "");
        }

        private static string BuildReverseSignature(string instance, string command)
        {
            return "reverse\u001f" + instance + "\u001f" + command;
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
                && string.Equals(
                    token.Value<string>(),
                    expected,
                    StringComparison.Ordinal);
        }

        private static string ReadString(JObject value, string key)
        {
            JToken token = value != null ? value[key] : null;
            return token != null && token.Type == JTokenType.String
                ? token.Value<string>()
                : null;
        }

        private static bool IsValidCallId(JToken token)
        {
            string value = token != null && token.Type == JTokenType.String
                ? token.Value<string>()
                : null;
            return value != null && ValidCallId.IsMatch(value);
        }

        private static bool IsValidPanelInstance(JToken token)
        {
            string value = token != null && token.Type == JTokenType.String
                ? token.Value<string>()
                : null;
            return value != null && ValidPanelInstanceId.IsMatch(value);
        }

        private static bool IsIdentity(JToken token, int maxLength)
        {
            if (token == null || token.Type != JTokenType.String) return false;
            string value = token.Value<string>();
            if (string.IsNullOrEmpty(value)
                || value.Length > maxLength
                || string.IsNullOrWhiteSpace(value)
                || string.Equals(
                    value.Trim(),
                    "undefined",
                    StringComparison.OrdinalIgnoreCase)) return false;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool IsIntegerInRange(
            JToken token,
            int minimum,
            int maximum)
        {
            if (token == null || token.Type != JTokenType.Integer) return false;
            long value;
            try { value = token.Value<long>(); }
            catch { return false; }
            return value >= minimum && value <= maximum;
        }
    }
}
