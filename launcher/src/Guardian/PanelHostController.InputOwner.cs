using System;
using System.Threading;
using CF7Launcher.Guardian.InputOwnership;

namespace CF7Launcher.Guardian
{
    // Business lifecycle of modal panels and scene transitions. Text leases and
    // non-modal pointer tickets are owned by SessionInputAuthority.
    internal enum EffectiveInputOwnerKind { Game, LegacyPanel, CompositionPanel, Settlement, Opening, Transition, Closing, NativeOwned, Unavailable }
    internal sealed class EffectiveInputOwnerSnapshot
    {
        internal readonly EffectiveInputOwnerKind Kind;
        internal readonly string OwnerKey, ClosingId;
        internal readonly long OwnerEpoch;
        internal EffectiveInputOwnerSnapshot(EffectiveInputOwnerKind kind, string key, long epoch, string closing=null)
        { Kind=kind; OwnerKey=key; OwnerEpoch=epoch; ClosingId=closing; }
    }
    public partial class PanelHostController
    {
        private readonly string _hostLifetime = Guid.NewGuid().ToString("N");
        private long _inputAdmissionStamp, _inputOwnerEpoch;
        private EffectiveInputOwnerSnapshot _inputOwner = new EffectiveInputOwnerSnapshot(EffectiveInputOwnerKind.Game,null,0);
        private string _pendingInputOwner;
        private int _transitionInputHeld;
        // Only a blocking native interaction publishes NativeOwned. Non-modal
        // editors and HUD gestures use the authority's independent channels.
        internal Func<bool> NativeInputOwnerPresent;
        internal long InputAdmissionStamp => Interlocked.Read(ref _inputAdmissionStamp);
        internal Action FocusAdmissionChanged;
        private SessionInputAuthority _passiveInput;
        internal void BindPassiveInput(SessionInputAuthority input)
        {
            _passiveInput=input;
            _compositionHelp?.BindInputAuthority(input, input, enableUniversalTextFocus: true);
            _compositionIntelligence?.BindInputAuthority(input, input, enableUniversalTextFocus: true);
        }
        private bool NativeInputBlocksGame()
        {
            if (_ownerForm?.InvokeRequired == true) return true;
            bool modal;
            try { modal = NativeInputOwnerPresent?.Invoke() == true; }
            catch { modal = true; }
            var owner = EffectiveInputOwner;
            if (owner.Kind is EffectiveInputOwnerKind.Game or EffectiveInputOwnerKind.NativeOwned) {
                var kind = modal ? EffectiveInputOwnerKind.NativeOwned : EffectiveInputOwnerKind.Game;
                if (owner.Kind != kind)
                    Volatile.Write(ref _inputOwner, new EffectiveInputOwnerSnapshot(kind, null, ++_inputOwnerEpoch));
            }
            return modal;
        }
        internal bool GameOwnsInput => !_disposed && !NativeInputBlocksGame() && Volatile.Read(ref _pendingInputOwner)==null
            && Volatile.Read(ref _inputOwner).Kind==EffectiveInputOwnerKind.Game && _activePanel==null
            && !AnyCompositionPanelSelected && !_transitionSettlementSelected && !BookshelfReturnLoading
            && Volatile.Read(ref _transitionInputHeld)==0 && !(_sceneSettlement?.OwnsCurtain ?? false);
        internal EffectiveInputOwnerSnapshot EffectiveInputOwner => Volatile.Read(ref _inputOwner);
        private void AdmitInputOwnerIntent(ref PanelCommand command)
        {
            if (command.Kind!=PanelCommandKind.Open && !command.IsExactReplace) return;
            command.InputAdmissionStamp=Interlocked.Increment(ref _inputAdmissionStamp);
            Volatile.Write(ref _pendingInputOwner,command.Name ?? "opening");
            _passiveInput?.SetBusinessEligible(false,"panel_opening");
        }
        private void PublishInputOwner(string panel, string instance)
        {
            if (panel==null && EffectiveInputOwner.Kind==EffectiveInputOwnerKind.Closing) return;
            var kind=panel==null ? EffectiveInputOwnerKind.Game : _transitionSettlementSelected ? EffectiveInputOwnerKind.Settlement : AnyCompositionPanelSelected
                ? EffectiveInputOwnerKind.CompositionPanel : EffectiveInputOwnerKind.LegacyPanel;
            Volatile.Write(ref _inputOwner,new EffectiveInputOwnerSnapshot(kind,instance,++_inputOwnerEpoch));
        }
        private void FinishInputOwnerIntent(PanelCommand command)
        {
            if(command.InputAdmissionStamp==0 || command.InputAdmissionStamp!=Interlocked.Read(ref _inputAdmissionStamp))return;
            lock(_queueLock) {
                if(_deferredRebind?.InputAdmissionStamp==command.InputAdmissionStamp
                    || _deferredBarrierOpen?.InputAdmissionStamp==command.InputAdmissionStamp)return;
            }
            Volatile.Write(ref _pendingInputOwner,null);
            var current=EffectiveInputOwner;
            if(current.Kind is EffectiveInputOwnerKind.Closing or EffectiveInputOwnerKind.Unavailable)return;
            PublishInputOwner(_activePanel,_activePanelInstanceId);
            FocusAdmissionChanged?.Invoke();
        }
        private void ClearConsumedDeferredInputIntentLocked()
        {
            long latest=Interlocked.Read(ref _inputAdmissionStamp);
            foreach(var command in _queue) if(command.InputAdmissionStamp==latest)return;
            if(_deferredRebind?.InputAdmissionStamp==latest || _deferredBarrierOpen?.InputAdmissionStamp==latest)return;
            Volatile.Write(ref _pendingInputOwner,null);
        }
        internal void SetTransitionInputHeld(bool held)
        {
            bool changed=Interlocked.Exchange(ref _transitionInputHeld,held ? 1 : 0)!=(held ? 1 : 0);
            if(_activePanel==null && EffectiveInputOwner.Kind is not (EffectiveInputOwnerKind.Closing or EffectiveInputOwnerKind.Unavailable))
                Volatile.Write(ref _inputOwner,new EffectiveInputOwnerSnapshot(held ? EffectiveInputOwnerKind.Transition :
                    EffectiveInputOwnerKind.Game,null,++_inputOwnerEpoch));
            if(held)_passiveInput?.SetBusinessEligible(false,"transition_hold");
            if(changed) FocusAdmissionChanged?.Invoke();
        }
        internal bool HandoffTransitionToGame(WindowManager manager, IntPtr foreground)
        {
            var owner=EffectiveInputOwner;
            if (owner.Kind is not (EffectiveInputOwnerKind.Game or EffectiveInputOwnerKind.Transition or EffectiveInputOwnerKind.Closing))
                return false;
            if (owner.Kind == EffectiveInputOwnerKind.Closing &&
                ((_executingClose ?? LastCloseOutcome) is not { } close || !ClosingFocusIdentity(close)))
                return false;
            long admission=Interlocked.Read(ref _inputAdmissionStamp);
            var source=CloseSourceWindowIdentity.Capture(foreground);
            return manager != null && !_disposed && _focusLifetime() && _activePanel==null
                && Volatile.Read(ref _pendingInputOwner)==null && admission==Interlocked.Read(ref _inputAdmissionStamp)
                && ReferenceEquals(owner,EffectiveInputOwner) && source?.IsCurrent()==true
                && manager.ReturnPassiveRoot(foreground);
        }
        private bool ExactCloseSource(HostCloseContext context)
        {
            if(context==null || _disposed || _activePanel==null || context.Endpoint.HostLifetime!=_hostLifetime
                || context.Endpoint.Panel!=_activePanel || context.Endpoint.Instance!=_activePanelInstanceId) return false;
            // The captured panel accelerator posts once more to its destination UI.
            // Recheck on delivery; a close already executing keeps its transaction.
            if (context.Cause == NativeCloseCause.Escape && _passiveInput != null
                && context.Authority == AuthorityCommitState.NotStarted && EffectiveInputOwner.ClosingId != context.CloseId
                && (!_passiveInput.ShortcutStamp.HasValue || _closeFocusManager?.PassiveShortcutForeground() != true))
                return false;
            if(context.Plan==ClosePlanKind.CleanupOnly && ReferenceEquals(context.Endpoint,_activeEndpointLease))return true;
            if(context.Endpoint.Surface is CompositionHelpSurface surface) return surface.IsLeaseCurrent(context.Endpoint);
            return context.Endpoint.Surface==null || _web?.IsEndpointCurrent(context.Endpoint)==true;
        }
        private bool ExactSourceAndAdmission(HostCloseContext context) => ExactCloseSource(context)
            && Interlocked.Read(ref _inputAdmissionStamp)==context.AdmissionStamp;
        private bool OwnsClosingCleanup(HostCloseContext context) => !_disposed
            && context.Endpoint.Panel==_activePanel && context.Endpoint.Instance==_activePanelInstanceId
            && EffectiveInputOwner.ClosingId==context.CloseId && (context.SourceRetired || ExactCloseSource(context));
        private bool ClosingFocusEligible(HostCloseContext context) => ClosingFocusIdentity(context)
            && _additionalFocusGate() && !NativeInputBlocksGame();
        private bool ClosingFocusIdentity(HostCloseContext context) => EffectiveInputOwner.ClosingId==context.CloseId
            && !_disposed && _focusLifetime() && !context.CleanupFailed && (context.SourceRetired ? _activePanel==null || OwnsClosingCleanup(context) : ExactCloseSource(context))
            && context.Plan==ClosePlanKind.ReturnGame && context.Authority!=AuthorityCommitState.Unknown
            && Interlocked.Read(ref _inputAdmissionStamp)==context.AdmissionStamp
            && Volatile.Read(ref _pendingInputOwner)==null;
        private bool TryEnterClosing(HostCloseContext context)
        {
            if(!ExactCloseSource(context))return false;
            Volatile.Write(ref _inputOwner,new EffectiveInputOwnerSnapshot(EffectiveInputOwnerKind.Closing,
                context.Endpoint.Instance,++_inputOwnerEpoch,context.CloseId));
            return true;
        }
        private void FinishClosingExact(HostCloseContext context)
        {
            if(EffectiveInputOwner.ClosingId!=context.CloseId)return;
            var kind=context.CleanupFailed ? EffectiveInputOwnerKind.Unavailable
                : Volatile.Read(ref _pendingInputOwner)!=null || Interlocked.Read(ref _inputAdmissionStamp)!=context.AdmissionStamp
                ? EffectiveInputOwnerKind.Opening : _activePanel==null ? EffectiveInputOwnerKind.Game : EffectiveInputOwnerKind.Unavailable;
            Volatile.Write(ref _inputOwner,new EffectiveInputOwnerSnapshot(kind,_activePanelInstanceId,++_inputOwnerEpoch));
            LastCloseOutcome=context;
            FocusAdmissionChanged?.Invoke();
        }
    }
}
