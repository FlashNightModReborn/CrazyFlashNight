#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Concurrent;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

// Diagnostic live wiring only. No ordinary launcher constructs this host.
namespace CF7Launcher.Guardian.UnifiedHost;

internal sealed partial class UnifiedInputHost
{
    private static readonly InputScope MScope = new("M", 1), NScope = new("Native", 1);
    private InputScope WScope = new("Web", 1);
    private sealed record LiveGeometry(long Version, Rectangle Screen, bool Visible, int Dpi);
    private sealed record Effect(string Kind, HandoffRound Round, InputScope? Owner = null,
        ObservationPrefix Prefix = default, InputGesture? Gesture = null, ObservedInputEdge? Edge = null, Point Point = default,
        ContinuousKeyEvent? Continuous = null);
    private readonly Control tooltipAnchor = new() { Visible = false };
    private readonly ConcurrentQueue<Effect> liveControl = new(), liveData = new();
    private InputHandoffCoordinator? coordinator; // observer-thread-owned
    private InputGesture? liveGesture;
    private Effect? deferredEnd;
    private long deferredAt;
    private readonly EndSettlementTracker endSettlement = new(); // observer-thread-owned
    private sealed record ProtocolWait(HandoffRound Round, long StartedAt);
    private ProtocolWait? preparingWait, webGrantWait;
    private InputOpenIntent? liveIntent;
    private HandoffRound liveRound;
    private InputScope? liveOwner;
    private ObservationPrefix livePreparedPrefix;
    private LiveGeometry liveGeometry = new(1, Rectangle.Empty, false, 96);
    private bool liveStarted, liveBusy, pageReady = true, livePageOpen;
    private volatile bool webGrant;
    private volatile bool liveFault;
    private bool liveFaultApplied, liveNativeShown;
    private Point lastWebPoint = new(-1000, -1000);
    private PlayerHudVitals? liveVitals;
    private int liveOpenCount, liveCloseCount;
    private string lastProbe = "";
    private bool delayNextSnapshot, delayNextIntent, dropNextPrepared;
    private JObject? delayedAs2Intent;
    private long delayedAs2IntentAt;
    private JObject? delayedSnapshot;
    private CoreWebView2CompositionController? delayedSnapshotEndpoint;
    private long delayedSnapshotAt;
    private long activationSerial, observedActivationSerial;
    private long duplicatePointerReleases;

    private static JObject JsonRound(HandoffRound value) => new() {
        ["session"] = value.Session, ["coverage"] = value.Coverage, ["epoch"] = value.Epoch,
        ["ticket"] = value.Ticket, ["geometry"] = value.Geometry };
    private static HandoffRound ReadRound(JToken value) => new(value.Value<string>("session") ?? "", value.Value<string>("coverage") ?? "",
        value.Value<long>("epoch"), value.Value<long>("ticket"), value.Value<long>("geometry"));
    private void LiveSend(string op, HandoffRound round, JObject? fields = null)
    {
        var message = JsonRound(round); message["op"] = op;
        if (fields != null) message.Merge(fields);
        var bytes = System.Text.Encoding.UTF8.GetBytes(message.ToString(Newtonsoft.Json.Formatting.None) + "\0");
        stream!.Write(bytes);
    }
    private void LiveWeb(string op, HandoffRound round, JObject? fields = null)
    {
        var message = new JObject { ["type"] = "c1_control", ["op"] = op, ["instance"] = pageInstance,
            ["generation"] = pageGeneration, ["round"] = JsonRound(round) };
        if (fields != null) message.Merge(fields);
        web!.CoreWebView2.PostWebMessageAsJson(message.ToString(Newtonsoft.Json.Formatting.None));
    }
    private async Task StartLive()
    {
        Text = "CF7 C1 live wiring - NOT ACCEPTED";
        liveStarted = true;
        liveGeometry = new(1, RectangleToScreen(ClientRectangle), Visible && WindowState != FormWindowState.Minimized, DeviceDpi);
        await inputProbe!.OnObserver((ledger, _) => {
            var movement = sceneProfile.MovementKeys.Count == 0 ? default
                : ContinuousInputPolicy.Declare(MScope, sceneProfile.MovementKeys.ToArray());
            coordinator = new(ledger, session, closure, new[] { MScope, WScope, NScope }, movement);
            coordinator.CancelRequired += (round, scopes) => {
                while (liveData.TryDequeue(out var discarded)) { }
                liveGesture = null; deferredEnd = null; endSettlement.Cancel();
                if (liveControl.Count >= 64) { liveFault = true; return; }
                liveControl.Enqueue(new("cancel", round));
            };
            inputProbe.BatchObserved += ObserveLive;
            coordinator.SetEnvironment(GetForegroundWindow() == Handle, liveGeometry.Version);
            coordinator.Start(MScope); return true;
        });
        Log("live_started", new { policy = "activation_only", noPaidWrites = true, C1Acceptance = false });
    }
    private void ObserveLive(PhysicalInputLedger ledger, RawSourceBatch batch)
    {
        if (coordinator == null || liveFault) return;
        CheckActivationBoundary();
        var geometry = Volatile.Read(ref liveGeometry);
        coordinator.SetEnvironment(geometry.Visible && GeometryMatches(geometry) && GetForegroundWindow() == Handle, geometry.Version);
        foreach (var edge in batch.Edges) {
            coordinator.ObservationChanged(edge);
            if (edge.Key == 1 && edge.Duplicate && !edge.Down) Interlocked.Increment(ref duplicatePointerReleases);
            var owner = coordinator.Owner;
            var continuous = coordinator.AcceptContinuousEdge(edge, geometry.Version);
            if (continuous.HasValue) {
                QueueData(new(continuous.Value.Down ? "key_down" : "key_up", coordinator.Round, owner, Continuous: continuous));
                continue;
            }
            if (edge.Duplicate || (edge.Key != 1 && !(owner == WScope && edge.Key is 13 or 27 or 32))) continue;
            if (owner != MScope && owner != WScope) continue;
            var point = new Point(batch.ScreenX - geometry.Screen.X, batch.ScreenY - geometry.Screen.Y);
            bool onSurface = GetAncestor(WindowFromPoint(new Point(batch.ScreenX, batch.ScreenY)), 2) == Handle;
            if (edge.Key == 1 && !edge.Down && !onSurface && coordinator.Phase == InputHandoffPhase.Held) {
                coordinator.Revoke("pointer_target_occluded"); continue;
            }
            if (edge.Down) {
                if (edge.Key == 1 && (!new Rectangle(Point.Empty, geometry.Screen.Size).Contains(point) || !onSurface)) continue;
                liveGesture = coordinator.Begin(owner.Value, edge, geometry.Version);
                if (liveGesture.HasValue) QueueData(new("down", coordinator.Round, owner, Gesture: liveGesture, Edge: edge, Point: point));
            } else if (liveGesture.HasValue && coordinator.Complete(liveGesture.Value, edge, geometry.Version)) {
                if (owner == MScope) endSettlement.Track(liveGesture.Value);
                QueueData(new("up", coordinator.Round, owner, Gesture: liveGesture, Edge: edge, Point: point));
            } else if (!edge.Down && liveGesture.HasValue && coordinator.DeferCompletion(liveGesture.Value, edge, geometry.Version)) {
                deferredEnd = new("up", coordinator.Round, owner, Gesture: liveGesture, Edge: edge, Point: point);
                deferredAt = Environment.TickCount64;
            }
        }
    }
    private void QueueData(Effect effect)
    {
        if (liveData.Count >= 128) { coordinator!.Fail("live_data_overflow"); return; }
        liveData.Enqueue(effect);
    }
    private async void PumpLive()
    {
        if (liveBusy || closing || inputProbe == null) return;
        liveBusy = true;
        try {
            var rectangle = RectangleToScreen(ClientRectangle);
            bool visible = Visible && WindowState != FormWindowState.Minimized &&
                ProbeGetOutputSize(capture, out int outputWidth, out int outputHeight) == 1 && outputWidth == ClientSize.Width && outputHeight == ClientSize.Height;
            var previous = liveGeometry;
            if (rectangle != previous.Screen || visible != previous.Visible || DeviceDpi != previous.Dpi) {
                Volatile.Write(ref liveGeometry, new(previous.Version + 1, rectangle, visible, DeviceDpi));
                // Keep the old Web viewport intact until cancellation captures
                // it. Resizing the browser first can bake a transient stretched
                // browser frame into the retained image.
                if (web != null) web.NotifyParentWindowPositionChanged(); tooltipAnchor.Bounds = ClientRectangle;
                if (pipeline != null && ClientSize.Width > 0 && ClientSize.Height > 0) {
                    pipeline.Request(PlayerInfoRasterPlanner.Create(PlayerInfoSvgAssetContract.LoadProductionEmbedded(false), Rectangle.Round(WorldViewport(ClientSize)), DeviceDpi / 96f));
                    await pipeline.WaitForIdleAsync(); PaintLiveHud();
                }
            }
            // A booted replacement can restore its retained draft while its
            // display/input readiness is still closed. A cancellation arriving
            // between replacement and restore must not strand that cold page.
            bool ready = (pageReady || (restoreAfterRetirement != null && pageBoot)) && pendingWebReplacement == null;
            var pointer = PointToClient(Cursor.Position);
            var viewport = WorldViewport(ClientSize);
            bool nativeHover = !livePageOpen && GetAncestor(WindowFromPoint(Cursor.Position), 2) == Handle && pointer.X >= viewport.X && pointer.X < viewport.X + viewport.Width * 280 / 1024
                && pointer.Y >= viewport.Y + viewport.Height * 512 / 576 && pointer.Y < viewport.Bottom;
            string? protocolFault = null;
            var state = await inputProbe.OnObserver((ledger, drained) => {
                CheckActivationBoundary();
                coordinator!.SetEnvironment(visible && GetForegroundWindow() == Handle, liveGeometry.Version);
                coordinator.ObservationChanged();
                if (deferredEnd != null && coordinator.TryCompleteDeferred(out var deferredGesture, out _)) {
                    if (deferredEnd.Owner == MScope) endSettlement.Track(deferredGesture);
                    QueueData(deferredEnd); deferredEnd = null;
                } else if (deferredEnd != null && Environment.TickCount64 - deferredAt > 2000) {
                    coordinator.Revoke("end_reconciliation_timeout"); deferredEnd = null;
                }
                var prepared = Volatile.Read(ref preparingWait);
                var granted = Volatile.Read(ref webGrantWait);
                if (prepared != null && (coordinator.Phase != InputHandoffPhase.Preparing || prepared.Round != coordinator.Round))
                    Volatile.Write(ref preparingWait, null);
                else if (prepared != null && Environment.TickCount64 - prepared.StartedAt > 5000)
                    protocolFault = "prepare_ack_timeout";
                if (granted != null && (coordinator.Owner != WScope || webGrant || granted.Round != coordinator.Round))
                    Volatile.Write(ref webGrantWait, null);
                else if (granted != null && Environment.TickCount64 - granted.StartedAt > 5000)
                    protocolFault = "grant_ack_timeout";
                if (endSettlement.Expire(Environment.TickCount64, 2000)) protocolFault = "end_settlement_timeout";
                if (protocolFault != null) {
                    liveFault = true; liveFaultApplied = true;
                    coordinator.Fail(protocolFault); // unknown reply is a fault, not a synthetic settlement/grant
                }
                if (!endSettlement.Pending && !coordinator.HasContinuousHolds
                    && coordinator.Owner is { } hoverOwner && (hoverOwner == MScope || hoverOwner == NScope))
                    coordinator.SelectReadOnlyHover(nativeHover ? NScope : MScope);
                if (liveFault && !liveFaultApplied) { liveFaultApplied = true; coordinator.Fail("live_endpoint_fault"); }
                if (restoreAfterRetirement != null && ready && coordinator.Phase == InputHandoffPhase.WaitNeutral && !coordinator.HasPendingIntent) {
                    liveControl.Enqueue(new("restore", coordinator.Round));
                } else if (liveIntent.HasValue && ready && coordinator.ConsumeIntentForRetainedPreparation(liveIntent.Value)) {
                    liveControl.Enqueue(new(liveIntent.Value.Destination == "surgery" ? "open" : "close", coordinator.Round));
                    liveIntent = null;
                } else if (ready && !coordinator.HasPendingIntent && coordinator.TryPrepare(out var prefix)) {
                    livePreparedPrefix = prefix; liveControl.Enqueue(new("prepare", coordinator.Round, coordinator.PreparingOwner, Prefix: prefix));
                } else if (ready && coordinator.TryGrant(drained)) {
                    liveControl.Enqueue(new("grant", coordinator.Round, coordinator.Owner, livePreparedPrefix));
                }
                return (coordinator.Round, coordinator.Owner, coordinator.Phase);
            });
            liveRound = state.Round; liveOwner = state.Owner;
            if (protocolFault != null) Log("live_protocol_fault", new { protocolFault, state.Round });
            if (pendingWebReplacement != null && state.Phase is InputHandoffPhase.WaitNeutral or InputHandoffPhase.Blocked) {
                await ReplaceWebEndpoint(); return;
            }
            // A callback can advance the observer after this UI snapshot. Keep
            // future control/data queued; dropping them here loses cancellation.
            for (int i = 0; i < 32 && liveControl.TryPeek(out var control); i++) {
                if (LaterRound(control.Round, liveRound)) break;
                if (liveControl.TryDequeue(out control) && control.Round == liveRound) await ApplyControl(control);
            }
            if (web != null && web.Bounds != ClientRectangle) web.Bounds = ClientRectangle;
            if (delayedAs2Intent != null && Environment.TickCount64 >= delayedAs2IntentAt) {
                var request = delayedAs2Intent; delayedAs2Intent = null; ReceiveLive(request);
            }
            if (delayedSnapshot != null && Environment.TickCount64 >= delayedSnapshotAt) {
                var request = delayedSnapshot; delayedSnapshot = null;
                if (ReferenceEquals(delayedSnapshotEndpoint, web)) ReceiveLiveWeb(request);
                delayedSnapshotEndpoint = null;
            }
            for (int i = 0; i < 32 && liveData.TryPeek(out var data); i++) {
                if (LaterRound(data.Round, liveRound)) break;
                if (liveData.TryDequeue(out data) && data.Round == liveRound && data.Owner == liveOwner && GetForegroundWindow() == Handle) await ApplyData(data);
            }
            Text = "CF7 C1 live · 只读验收 · " + (liveFault ? "恢复失败，请关闭候选后重启" : state.Phase == InputHandoffPhase.Ready && (state.Owner != WScope || webGrant) ? "可操作" : "正在恢复输入");
            if (liveOwner == WScope && webGrant && GetForegroundWindow() == Handle) {
                var point = PointToClient(Cursor.Position);
                if (point != lastWebPoint) {
                    lastWebPoint = point;
                    bool overSurface = GetAncestor(WindowFromPoint(Cursor.Position), 2) == Handle;
                    web!.SendMouseInput(overSurface ? CoreWebView2MouseEventKind.Move : CoreWebView2MouseEventKind.Leave,
                        overSurface && Control.MouseButtons.HasFlag(MouseButtons.Left) ? CoreWebView2MouseEventVirtualKeys.LeftButton : CoreWebView2MouseEventVirtualKeys.None, 0, overSurface ? point : Point.Empty);
                }
            }
            if (liveNativeShown) { tooltip!.QueuePointerMove(Cursor.Position.X, Cursor.Position.Y); tooltip.FlushPointerMove(); PaintLiveHud(); }
            await RunLiveProbe();
            if (File.Exists(Path.Combine(evidence, "stop.request"))) Finish(true);
        } catch (Exception error) {
            if (closing) return;
            Log("live_fault", error.ToString()); liveFault = true;
            // A transport exception never falls through to a world grant.
            if (inputProbe != null) await inputProbe.OnObserver((_, _) => { coordinator?.Fail("endpoint_exception"); return true; });
        } finally { liveBusy = false; }
    }
    private async Task ApplyControl(Effect effect)
    {
        Log("live_control", effect);
        if (effect.Kind == "cancel") {
            webGrant = false;
            LiveSend("CANCEL", effect.Round);
            await FreezePresentation(effect.Round);
            if (web != null) LiveWeb("cancel", effect.Round, new() { ["retire"] = webExposed || !livePageOpen });
            else if (pendingWebReplacement != null) await AckCancel(WScope, effect.Round);
            tooltip!.Reset(); liveNativeShown = false; PaintLiveHud();
            await AckCancel(NScope, effect.Round);
        } else if (effect.Kind == "open") {
            livePageOpen = true; pageReady = false; liveOpenCount++;
            presentationSerial++; PresentModal(true, false, "open_intent");
            pageGeneration++; pageInstance = "c1.surgery." + Guid.NewGuid().ToString("N");
            LiveWeb("prepare", effect.Round); // real production opener was validated before this effect
        } else if (effect.Kind == "restore") {
            pageReady = false; var draft = restoreAfterRetirement; restoreAfterRetirement = null;
            LiveWeb("prepare", effect.Round, new() { ["restoreDraft"] = draft });
        } else if (effect.Kind == "close") {
            livePageOpen = false; pageReady = false; liveCloseCount++;
            presentationSerial++; PresentModal(false, false, "close_intent");
            LiveWeb("cancel", effect.Round, new() { ["retire"] = true });
        } else if (effect.Kind == "prepare") {
            if (effect.Owner == WScope && GetForegroundWindow() == Handle) {
                webExposed = true; web!.MoveFocus(CoreWebView2MoveFocusReason.Programmatic);
                if (retiredFocusWindows.Contains(FocusedWebWindow())) throw new InvalidOperationException("Retired keyboard HWND reused; no input grant");
            }
            var prefix = new JObject { ["generation"] = effect.Prefix.Generation, ["sequence"] = effect.Prefix.Sequence };
            LiveSend("PREPARE", effect.Round, new() { ["prefix"] = prefix });
            LiveWeb("arm", effect.Round, new() { ["prefix"] = prefix });
            Volatile.Write(ref preparingWait, new ProtocolWait(effect.Round, Environment.TickCount64));
            await inputProbe!.OnObserver((_, _) => coordinator!.AcceptPrepared(new(effect.Round, NScope, effect.Prefix)));
        } else if (effect.Kind == "grant") {
            var prefix = effect.Prefix;
            if (effect.Owner == MScope) LiveSend("GRANT", effect.Round, new() { ["sourceGeneration"] = prefix.Generation, ["sequence"] = prefix.Sequence });
            if (effect.Owner == WScope) { LiveWeb("grant", effect.Round); Volatile.Write(ref webGrantWait, new ProtocolWait(effect.Round, Environment.TickCount64)); }
            if (effect.Owner == NScope && liveVitals != null) {
                var target = new PlayerHudTarget("resources", 0, "", 1, 1, 0, new RectangleF(0, 512, 280, 64));
                liveNativeShown = tooltip!.Show(PlayerHudResourceTooltip.Build(liveVitals, 1, 1, target, "c1.resources." + effect.Round.Epoch));
                tooltip.QueuePointerMove(Cursor.Position.X, Cursor.Position.Y); tooltip.FlushPointerMove();
                PaintLiveHud(); Log("live_native_hover", new { visible = liveNativeShown, effect.Round });
            }
            Log("live_granted", new { effect.Round, effect.Owner, liveOpenCount, liveCloseCount });
        }
    }
    private async Task ApplyData(Effect effect)
    {
        if (effect.Kind.StartsWith("rejected:", StringComparison.Ordinal)) { Log("live_rejected_end", effect); return; }
        if (effect.Continuous is { } continuous) {
            if (effect.Owner != MScope || continuous.Round != effect.Round || continuous.Scope != MScope)
                throw new InvalidDataException("Continuous input escaped its declared world scope.");
            LiveSend(continuous.Down ? "KEYHOLD" : "KEYRELEASE", effect.Round, new() {
                ["scope"] = MScope.Id, ["incarnation"] = MScope.Incarnation,
                ["key"] = continuous.Key, ["sequence"] = continuous.Sequence });
            Log("live_continuous_forwarded", continuous); // forwarding, not Flash business acceptance
            return;
        }
        var gesture = effect.Gesture!.Value; var edge = effect.Edge!.Value;
        if (effect.Owner == MScope) {
            var viewport = WorldViewport(liveGeometry.Screen.Size);
            LiveSend(effect.Kind == "down" ? "BEGIN" : "END", effect.Round, new() {
                ["gesture"] = gesture.Id, ["sequence"] = edge.Prefix.Sequence, ["begin"] = gesture.BeginSequence,
                ["button"] = 1, ["x"] = (effect.Point.X - viewport.X) * sceneProfile.Width / viewport.Width,
                ["y"] = (effect.Point.Y - viewport.Y) * sceneProfile.Height / viewport.Height });
            if (effect.Kind == "up") await inputProbe!.OnObserver((_, _) =>
                { endSettlement.MarkDispatched(gesture.Id, gesture.Round, Environment.TickCount64); return true; });
        } else if (effect.Owner == WScope && webGrant) {
            // Stamp the exact gesture before the browser sees its pointer event.
            if (edge.Key != 1) {
                if (!edge.Down) await web!.CoreWebView2.ExecuteScriptAsync("C1IslandGate.activateKey(" + edge.Key + "," + gesture.Id + "," + JsonRound(effect.Round).ToString(Newtonsoft.Json.Formatting.None) + ");");
                Log("live_key_activation", new { edge.Key, edge.Down, gesture.Id }); return;
            }
            await web!.CoreWebView2.ExecuteScriptAsync("C1IslandGate.pointerGesture=" + gesture.Id + ";");
            if (effect.Round != liveRound || GetForegroundWindow() != Handle) return;
            web.SendMouseInput(effect.Kind == "down" ? CoreWebView2MouseEventKind.LeftButtonDown : CoreWebView2MouseEventKind.LeftButtonUp,
                effect.Kind == "down" ? CoreWebView2MouseEventVirtualKeys.LeftButton : CoreWebView2MouseEventVirtualKeys.None, 0, effect.Point);
        }
        Log("live_pointer", effect);
    }
    private Task<bool> AckCancel(InputScope scope, HandoffRound round) => inputProbe!.OnObserver((_, _) =>
        coordinator!.AcceptCancelled(new(round, scope, true, true)));
    private bool ReceiveLive(JObject message)
    {
        string kind = message.Value<string>("kind") ?? message.Value<string>("task") ?? "";
        if (kind == "CANCELLED" && message.Value<int>("pending") == 0 && message.Value<bool>("gateClosed")) {
            _ = AckCancel(MScope, ReadRound(message)); return true;
        }
        if (kind == "PREPARED" && message.Value<bool>("gateClosed")) {
            var round = ReadRound(message); var prefix = message["prefix"]!;
            _ = inputProbe!.OnObserver((_, _) => coordinator!.AcceptPrepared(new(round, MScope,
                new(prefix.Value<long>("generation"), prefix.Value<long>("sequence"))))); return true;
        }
        if (kind == "panel_request") {
            if (message.Value<string>("panel") == "surgery" && message.Value<string>("source") == "world_plastic_surgery"
                && message["inputIntent"] is JObject intent) _ = AcceptLiveIntent(MScope, intent.Value<long>("gesture"), ReadRound(intent), WScope, "surgery");
            return true;
        }
        if (kind is "end_miss" or "end_no_intent") {
            if (message.Value<string>("op") == "END")
                _ = SettleLiveEnd(kind, message.Value<long>("gesture"), ReadRound(message));
            return true;
        }
        return kind is "BEGIN" or "GRANTED" or "closed_rejected" or "stale_rejected" or "raw_rejected" or "opener_rejected";
    }
    private async Task AcceptLiveIntent(InputScope scope, long id, HandoffRound round, InputScope target, string destination)
    {
        bool accepted = await inputProbe!.OnObserver((_, _) => {
            if (!liveGesture.HasValue || liveGesture.Value.Id != id || liveGesture.Value.Scope != scope || liveGesture.Value.Round != round) return false;
            liveIntent = coordinator!.HandoffCompleted(liveGesture.Value, target, destination);
            endSettlement.Settle("END", id, round); // hover release and intent mint stay in one observer turn
            return liveIntent.HasValue;
        });
        Log("live_intent", new { scope, id, round, destination, accepted });
    }
    private async Task SettleLiveEnd(string kind, long gesture, HandoffRound round)
    {
        bool settled = await inputProbe!.OnObserver((_, _) => endSettlement.Settle("END", gesture, round));
        Log("live_end_settlement", new { kind, gesture, round, settled });
    }
    private void ReceiveLiveWeb(JObject message)
    {
        if (message.Value<string>("instance") != pageInstance && message.Value<string>("panelInstanceId") != pageInstance) return;
        var roundToken = message["round"] ?? message["inputRound"];
        if (roundToken == null) return;
        var round = ReadRound(roundToken);
        // Read-only page initialization belongs to the exact page lifetime,
        // not a physical gesture or a particular window geometry. Resizing may
        // revoke input between Panels.open and its asynchronous snapshot.
        // Never extend this exception to close, writes, ACKs or input grants.
        if (message.Value<string>("type") == "panel" && message.Value<string>("cmd") is "snapshot" or "query") {
            bool accepted = livePageOpen && message.Value<string>("panel") == "surgery"
                && message.Value<string>("panelInstanceId") == pageInstance && message.Value<long>("inputGeneration") == pageGeneration
                && round.Session == liveRound.Session && round.Coverage == liveRound.Coverage
                && round.Epoch > 0 && round.Epoch <= liveRound.Epoch && round.Ticket > 0 && round.Ticket <= liveRound.Ticket
                && round.Geometry > 0 && round.Geometry <= liveRound.Geometry;
            Log("live_readonly_request", new { accepted, round, current = liveRound, pageInstance, pageGeneration });
            if (accepted) surgery!.HandleWebRequest(message.Value<string>("cmd"), message);
            return;
        }
        if (round != liveRound) return;
        if (message.Value<string>("type") == "c1_scope" && message.Value<long>("generation") == pageGeneration) {
            string kind = message.Value<string>("kind") ?? "";
            if (kind is "suspended" or "cancelled" && message.Value<bool>("gateClosed")) {
                if (webExposed && kind == "cancelled") _ = RetireWebEndpoint(round, message["draft"] as JObject);
                else { _ = AckCancel(WScope, round); if (kind == "cancelled") pageReady = true; }
            }
            if (kind == "page_ready") _ = RevealPresentation(round);
            if (kind == "prepare_failed") { Log("live_page_prepare_failed", message); liveFault = true; }
            if (kind == "prepared" && message.Value<bool>("gateClosed")) {
                var prefix = message["prefix"]!;
                _ = inputProbe!.OnObserver((_, _) => coordinator!.AcceptPrepared(new(round, WScope,
                    new(prefix.Value<long>("generation"), prefix.Value<long>("sequence")))));
            }
            if (kind == "granted") webGrant = true;
        } else if (message.Value<string>("type") == "panel" && message.Value<long>("inputGeneration") == pageGeneration) {
            var cmd = message.Value<string>("cmd");
            if (cmd == "close") _ = AcceptLiveIntent(WScope, message.Value<long>("inputGesture"), round, MScope, "world");
            else if (webGrant && liveOwner == WScope) surgery!.HandleWebRequest(cmd, message);
            else Log("live_unqualified_business", new { cmd, webGrant, liveOwner });
        }
    }
    private async Task RunLiveProbe()
    {
        if (!diagnosticCommands) return;
        string path = Path.Combine(evidence, "probe.json");
        if (!File.Exists(path) || web == null) return;
        string text;
        try {
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(file); text = reader.ReadToEnd();
        } catch (IOException) { return; }
        if (text == lastProbe) return;
        lastProbe = text;
        var request = JObject.Parse(text);
        string op = request.Value<string>("op") ?? "";
        JObject? visual = null;
        if (op != "state" && !diagnosticCommands) throw new InvalidDataException("Unsupported diagnostic operation");
        if (op == "disconnect") { stream!.Dispose(); return; }
        if (op == "visual_state") { LiveSend("VISUAL", liveRound); visual = await Receive("VISUAL"); }
        else if (op == "delay_next_intent") delayNextIntent = true;
        else if (op == "drop_next_prepared") dropNextPrepared = true;
        else if (op == "delay_next_snapshot") delayNextSnapshot = true;
        else if (op == "source_fault") inputProbe!.RequestFaultControl();
        else if (op == "data_fault") await inputProbe!.OnObserver((_, _) => { coordinator!.Fail("declared_data_queue_failure"); return true; });
        else if (op == "transport_recovered") await inputProbe!.OnObserver((_, _) => { coordinator!.TransportRecovered(); return true; });
        else if (op == "composition_begin" && liveOwner == WScope && webGrant) {
            await web!.CoreWebView2.ExecuteScriptAsync("(()=>{let e=document.getElementById('surgery-character-name');e.focus();e.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true,cancelable:true,data:''}));e.value='未提交';e.dispatchEvent(new InputEvent('input',{bubbles:true,isComposing:true,inputType:'insertCompositionText',data:'未提交'}));})()");
        }
        else if (op != "state") throw new InvalidDataException("Unsupported diagnostic operation");
        var endpoint = web;
        var state = await inputProbe!.OnObserver((_, _) => new { coordinator!.Round, coordinator.Owner, coordinator.Phase, coordinator.BlockReason });
        string page = "\"{}\"";
        try {
            if (endpoint != null && ReferenceEquals(endpoint, web)) page = await endpoint.CoreWebView2.ExecuteScriptAsync("JSON.stringify({gate:C1IslandGate, panel:PlasticSurgeryPanel.debugState(), active:document.activeElement && document.activeElement.id, targets:['surgery-character-name','surgery-cancel'].map(id=>{var e=document.getElementById(id);if(!e)return null;var r=e.getBoundingClientRect();return {id:id,x:(r.x+r.width/2)*devicePixelRatio,y:(r.y+r.height/2)*devicePixelRatio};})})");
        } catch (Exception) when (!ReferenceEquals(endpoint, web) || closing) { page = "\"{}\""; }
        var observedRound = await inputProbe!.OnObserver((_, _) => coordinator!.Round);
        if (!ReferenceEquals(endpoint, web) || observedRound != state.Round) page = "\"{}\"";
        Log("live_probe", new { id = request.Value<string>("id"), op, state, page, visual, liveOpenCount, liveCloseCount, duplicatePointerReleases = Interlocked.Read(ref duplicatePointerReleases), nativeVisible = tooltip!.ActiveDocument != null, modalPresentation, frozenPresentation });
    }
    private void PaintLiveHud()
    {
        if (pipeline == null || playerInfo == null || ClientSize.Width < 1 || ClientSize.Height < 1) return;
        using var image = new Bitmap(ClientSize.Width, ClientSize.Height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(image)) {
            pipeline.TryUseCurrent((batch, plan) => {
                var bounds = plan.TightPhysicalBounds;
                using var part = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppPArgb);
                playerInfo.Paint(part, batch, plan); graphics.DrawImageUnscaled(part, bounds.Location);
            });
            tooltip?.Paint(graphics, DeviceDpi / 96f, PointToScreen(Point.Empty));
        }
        var bits = image.LockBits(new Rectangle(Point.Empty, image.Size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try { compositionScene!.UploadHud(bits.Scan0, image.Width, image.Height, bits.Stride, 0, 0); }
        finally { image.UnlockBits(bits); }
    }
    private static bool LaterRound(HandoffRound value, HandoffRound current) => value.Epoch > current.Epoch || (value.Epoch == current.Epoch && value.Ticket > current.Ticket);
    private RectangleF WorldViewport(Size size)
    {
        float scale = Math.Min(size.Width / (float)sceneProfile.Width, size.Height / (float)sceneProfile.Height);
        return new((size.Width - sceneProfile.Width * scale) / 2, (size.Height - sceneProfile.Height * scale) / 2, sceneProfile.Width * scale, sceneProfile.Height * scale);
    }
    private bool GeometryMatches(LiveGeometry geometry)
    {
        var origin = Point.Empty;
        return GetDpiForWindow(Handle) == geometry.Dpi && GetClientRect(Handle, out var rectangle) && ClientToScreen(Handle, ref origin)
            && new Rectangle(origin.X, origin.Y, rectangle.Right, rectangle.Bottom) == geometry.Screen;
    }
    [StructLayout(LayoutKind.Sequential)] private struct ClientRect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out ClientRect rectangle);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref Point point);
    [DllImport("FlashCompositorNative.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int ProbeGetOutputSize(IntPtr capture, out int width, out int height);
    private void CheckActivationBoundary()
    {
        long serial = Interlocked.Read(ref activationSerial);
        if (coordinator == null || serial == observedActivationSerial) return;
        observedActivationSerial = serial;
        if (coordinator.Phase != InputHandoffPhase.BootClosed) coordinator.Revoke("window_activation_boundary");
    }
    protected override void WndProc(ref Message message)
    {
        // Agreed C1 policy: an inactive-window click activates only. The
        // unmatched Up still reaches the global ledger, never a new gesture.
        if (interactive && ((message.Msg == 0x6 && (message.WParam.ToInt64() & 0xffff) == 0)
            || (message.Msg == 0x1c && message.WParam == IntPtr.Zero))) Interlocked.Increment(ref activationSerial);
        if (interactive && message.Msg == 0x21 && GetForegroundWindow() != Handle) {
            Interlocked.Increment(ref activationSerial);
            message.Result = new IntPtr(2); return;
        }
        base.WndProc(ref message);
    }
}
