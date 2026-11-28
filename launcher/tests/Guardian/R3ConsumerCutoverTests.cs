using System;
using System.Collections.Generic;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.InputOwnership;
using Microsoft.ClearScript.V8;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;
using static CF7Launcher.Tests.Guardian.R1UiAdapterTests;

namespace CF7Launcher.Tests.Guardian;

public sealed class R3ConsumerCutoverTests
{
    [Fact]
    public void WorldPointerCancelKeepsKeyboardAndLocalClaimAndRequiresExactReceipt()
    {
        var authority = StartGameAuthority();
        Assert.True(authority.ObserveKey((int)Keys.D, true));
        long keyboardEpoch = authority.CurrentKeyboardEpoch;
        string held = authority.AdmittedHex;
        const string world = SessionInputAuthority.WorldEndpoint;
        Assert.True(authority.TryBeginPointer(world, 1, 1, Point.Empty, "flash", out var oldWorld));
        Assert.True(authority.TryBeginPointer("modifier.panel", 1, 2, Point.Empty, "tab", out var local));

        authority.ChangeWorldGeometry();
        authority.QueueWorldPointerCancel(25);
        authority.QueueWorldPointerCancel(26);
        Assert.True(authority.TryTakeOutput(out var control, controlOnly: true));
        Assert.EndsWith("|1|25", control.Payload);
        Assert.False(authority.TryTakeOutput(out _, controlOnly: true));
        Assert.False(authority.ValidatePointerCommit(oldWorld, "flash"));
        Assert.False(authority.TryBeginPointer(world, 1, 1, Point.Empty, "flash", out _));
        Assert.True(authority.ValidatePointerCommit(local, "tab"));
        Assert.Equal(held, authority.AdmittedHex);
        Assert.Equal(keyboardEpoch, authority.CurrentKeyboardEpoch);

        string receipt = control.Payload.Replace("|WorldPointerCancel|", "|WorldPointerCancelled|") + "|1";
        Assert.False(authority.Receive(control.Connection + 1, receipt));
        Assert.False(authority.Receive(control.Connection, receipt.Replace("|25|", "|26|")));
        Assert.False(authority.TryBeginPointer(world, 1, 1, Point.Empty, "flash", out _));
        Assert.True(authority.Receive(control.Connection, receipt));
        Assert.True(authority.TryBeginPointer(world, 1, 1, Point.Empty, "flash", out var fresh));
        Assert.False(authority.Receive(control.Connection, receipt));
        Assert.True(authority.ValidatePointerCommit(fresh, "flash"));
        Assert.True(authority.IsGameKeyboardAdmitted);
    }

    [Fact]
    public void WorldPointerCancelReceiptCannotCrossAConnectionReplacement()
    {
        var authority = StartGameAuthority();
        authority.QueueWorldPointerCancel(25);
        Assert.True(authority.TryTakeOutput(out var oldControl, controlOnly: true));
        authority.Disconnect(1);
        authority.Connect(2);
        Assert.True(authority.TryTakeOutput(out var bind, controlOnly: true));
        Assert.True(authority.Receive(2, bind.Payload.Replace("|Bind|", "|Capability|")));
        Assert.True(authority.IsGameKeyboardAdmitted);

        authority.QueueWorldPointerCancel(25);
        Assert.True(authority.TryTakeOutput(out var newControl, controlOnly: true));
        string oldReceipt = oldControl.Payload.Replace("|WorldPointerCancel|", "|WorldPointerCancelled|") + "|1";
        string newReceipt = newControl.Payload.Replace("|WorldPointerCancel|", "|WorldPointerCancelled|") + "|1";
        Assert.False(authority.Receive(2, oldReceipt));
        Assert.False(authority.TryBeginPointer(SessionInputAuthority.WorldEndpoint, 1, 1, Point.Empty, "flash", out _));
        Assert.True(authority.Receive(2, newReceipt));
        Assert.True(authority.TryBeginPointer(SessionInputAuthority.WorldEndpoint, 1, 1, Point.Empty, "flash", out _));
    }

    [Theory]
    [InlineData("web.inventory.")]
    [InlineData("web.skills.")]
    [InlineData("web.tasks.")]
    [InlineData("composition.help.")]
    [InlineData("composition.intelligence.")]
    [InlineData("bootstrap.frontdoor.")]
    public void UniversalWebFieldKeepsItsLeaseThroughImeAndDropsHeldExitKeys(string prefix)
    {
        var authority = StartGameAuthority();
        var fields = new WebTextFocusBinding(authority, "panel.1", prefix, selectors: null);
        string endpoint = prefix + "field.1";
        var root = (IntPtr)1;
        var editor = (IntPtr)2;

        ObserveField(fields, root, editor, endpoint, 1, "focusin");
        var lease = Assert.IsType<TextInputLease>(authority.CurrentTextLease);
        Assert.Equal(endpoint, lease.EndpointId);
        Assert.False(fields.ImeComposing);
        SettleGameCancel(authority);

        ObserveField(fields, root, editor, endpoint, 1, "compositionstart");
        Assert.True(fields.ImeComposing);
        Assert.Equal<TextInputLease?>(lease, authority.CurrentTextLease);
        var imeKeys = new[] { (int)Keys.Escape, (int)Keys.Enter, (int)Keys.Space };
        foreach (int vk in imeKeys) Assert.False(authority.ObserveKey(vk, true));
        Assert.False(authority.TryTakeOutput(out _));
        Assert.True(fields.ImeComposing);

        ObserveField(fields, root, editor, endpoint, 1, "compositionend");
        Assert.False(fields.ImeComposing);
        Assert.False(authority.IsGameKeyboardAdmitted);
        Assert.Equal<TextInputLease?>(lease, authority.CurrentTextLease);

        ObserveField(fields, root, IntPtr.Zero, endpoint, 1, "focusout");
        Assert.Null(authority.CurrentTextLease);
        Assert.False(fields.ImeComposing);
        Assert.True(authority.IsGameKeyboardAdmitted);
        Assert.True(authority.TryTakeOutput(out var grant));
        Assert.EndsWith("|0|-", grant.Payload);
        Assert.Equal(new string('0', 64), authority.AdmittedHex);
        foreach (int vk in imeKeys)
        {
            Assert.True(authority.IsSuppressed(vk));
            Assert.False(authority.ObserveKey(vk, false));
            Assert.False(authority.IsSuppressed(vk));
        }
        Assert.False(authority.TryTakeOutput(out _));
    }

    [Theory]
    [InlineData("web.inventory.", "web.inventory.")]
    [InlineData("composition.help.", "composition.intelligence.")]
    [InlineData("bootstrap.frontdoor.", "web.skills.")]
    public void PanelRetirementReleasesOnlyItsOwnLease(string retiringPrefix, string replacementPrefix)
    {
        var authority = new SessionInputAuthority(PassiveFlashInputMode.Disabled);
        var observedAuthority = new TextReleaseObserver(authority);
        var retiring = new WebTextFocusBinding(observedAuthority, "panel.retiring", retiringPrefix);
        var replacement = new WebTextFocusBinding(observedAuthority, "panel.replacement", replacementPrefix);
        var root = (IntPtr)1;
        var retiringEditor = (IntPtr)2;
        var replacementEditor = (IntPtr)3;

        ObserveField(retiring, root, retiringEditor, retiringPrefix + "field.1", 1, "focusin");
        var first = Assert.IsType<TextInputLease>(authority.CurrentTextLease);
        var retireCurrent = retiring.CaptureExit("web_panel_retired", requestGame: false);
        Assert.NotNull(retireCurrent);
        retireCurrent();
        Assert.Equal(first, Assert.IsType<TextExitReceipt>(retiring.TakeExitReceipt()).Lease);
        Assert.Equal(TextExitStatus.Released, observedAuthority.LastRelease.Status);
        Assert.Null(authority.CurrentTextLease);

        ObserveField(retiring, root, retiringEditor, retiringPrefix + "field.2", 2, "focusin");
        var oldLease = Assert.IsType<TextInputLease>(authority.CurrentTextLease);
        var retireLate = retiring.CaptureExit("web_panel_retired", requestGame: true);
        Assert.NotNull(retireLate);
        ObserveField(replacement, root, replacementEditor, replacementPrefix + "field.2", 1, "focusin");
        var newLease = Assert.IsType<TextInputLease>(authority.CurrentTextLease);
        Assert.Equal(replacementPrefix + "field.2", newLease.EndpointId);
        Assert.NotEqual(oldLease.InstanceGeneration, newLease.InstanceGeneration);
        long epoch = authority.CurrentKeyboardEpoch;

        retireLate();
        Assert.Equal(oldLease, observedAuthority.LastRelease.Lease);
        Assert.Equal(TextExitStatus.Stale, observedAuthority.LastRelease.Status);
        Assert.Equal<TextInputLease?>(newLease, authority.CurrentTextLease);
        Assert.Equal(epoch, authority.CurrentKeyboardEpoch);
        Assert.Equal(0, observedAuthority.GameRequests);

        ObserveField(replacement, root, IntPtr.Zero, newLease.EndpointId, 1, "focusout",
            requestGameOnBlur: false);
        Assert.Equal(newLease, observedAuthority.LastRelease.Lease);
        Assert.Equal(TextExitStatus.Released, observedAuthority.LastRelease.Status);
        Assert.Null(authority.CurrentTextLease);
    }

    [Theory]
    [InlineData("Escape")]
    [InlineData("Enter")]
    public void UniversalScriptStopsImeKeyPropagationThroughKeyUp(string key)
    {
        using var engine = new V8ScriptEngine();
        engine.Execute("""
            function eventTarget() {
                const listeners = new Map();
                return {
                    addEventListener(type, listener, capture) {
                        if (!listeners.has(type)) listeners.set(type, []);
                        listeners.get(type).push({ listener, capture: capture === true });
                    },
                    dispatch(event) {
                        for (const capture of [true, false]) {
                            for (const entry of listeners.get(event.type) ?? []) {
                                if (entry.capture !== capture) continue;
                                entry.listener(event);
                                if (event.stopped) return;
                            }
                        }
                    }
                };
            }

            const editor = { tagName: 'TEXTAREA' };
            const document = { ...eventTarget(), activeElement: editor, hasFocus: () => true };
            const messages = [];
            const window = { ...eventTarget(), chrome: { webview: {
                postMessage: (message) => messages.push(message)
            } } };
            window.top = window;
            const location = { href: 'https://bootstrap.local/bootstrap.html' };
            class MutationObserver { observe() {} disconnect() {} }

            function sendKey(type, key) {
                const event = { type, key, isComposing: false, stopped: false, prevented: false,
                    stopImmediatePropagation() { this.stopped = true; },
                    preventDefault() { this.prevented = true; }
                };
                window.dispatch(event);
                return event;
            }
            """);
        engine.Execute(WebTextFocusBinding.InstallScript + """
            ({ source: location.href, instance: 'panel.1', token: 'document.1', serial: '1',
               prefix: 'bootstrap.frontdoor.', selectors: null });
            """);

        var probe = JObject.Parse((string)engine.Evaluate($$"""
            (function (key) {
                const delivered = [];
                for (const type of ['keydown', 'keyup'])
                    window.addEventListener(type, (event) => delivered.push(event.key), true);
                document.dispatch({ type: 'compositionstart', target: editor });
                const composingDown = sendKey('keydown', key);
                sendKey('keydown', 'Tab');
                document.dispatch({ type: 'compositionend', target: editor });
                const composingUp = sendKey('keyup', key);
                const freshDown = sendKey('keydown', key);
                const freshUp = sendKey('keyup', key);
                const events = [composingDown, composingUp, freshDown, freshUp];
                return JSON.stringify({ delivered, stopped: events.map(e => e.stopped),
                    prevented: events.map(e => e.prevented),
                    phases: messages.map(m => m.phase), endpoints: messages.map(m => m.endpointId) });
            })({{JsonConvert.SerializeObject(key)}})
            """));

        Assert.Equal(new[] { "focusin", "compositionstart", "compositionend" }, probe["phases"].Values<string>());
        Assert.All(probe["endpoints"].Values<string>(), endpoint => Assert.Equal("bootstrap.frontdoor.field.1", endpoint));
        Assert.Equal(new[] { true, true, false, false }, probe["stopped"].Values<bool>());
        Assert.Equal(new[] { false, false, false, false }, probe["prevented"].Values<bool>());
        Assert.Equal(new[] { "Tab", key, key }, probe["delivered"].Values<string>());
    }

    [Fact]
    public void BoundBootstrapReleasesItsOwnLeaseOnHideAndDispose() => Sta(() =>
    {
        using var owner = CreateOwner();
        using var panel = new BootstrapHandleFixture();
        var authority = new SessionInputAuthority(PassiveFlashInputMode.Disabled);
        panel.BindInputAuthority(authority, authority);
        owner.Controls.Add(panel);
        owner.Show();

        Assert.Same(owner, panel.FindForm());
        Assert.True(panel.IsHandleCreated);
        Assert.True(panel.Visible);
        Assert.Null(panel.InternalCoreWebView2);
        var documentFields = typeof(BootstrapPanel).GetField("_documentFields",
            BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.NotNull(documentFields);

        // Seed the document binding at the WebView2-ready boundary and exercise real panel teardown.
        WebTextFocusBinding FocusFrontDoor(string field)
        {
            Assert.Null(documentFields.GetValue(panel));
            const string prefix = "bootstrap.frontdoor.";
            var binding = new WebTextFocusBinding(authority, "bootstrap.fixture", prefix);
            documentFields.SetValue(panel, binding);
            ObserveField(binding, owner.Handle, panel.Handle, prefix + field, 1, "focusin");
            Assert.Equal(prefix + field, authority.CurrentTextLease?.EndpointId);
            return binding;
        }

        var hiddenFields = FocusFrontDoor("field.1");
        var hiddenLease = Assert.IsType<TextInputLease>(authority.CurrentTextLease);
        panel.Hide();
        Assert.False(panel.Visible);
        Assert.Null(authority.CurrentTextLease);
        var hideReceipt = Assert.IsType<TextExitReceipt>(hiddenFields.TakeExitReceipt());
        Assert.Equal(TextExitStatus.Released, hideReceipt.Status);
        Assert.Equal(hiddenLease, hideReceipt.Lease);

        panel.Show();
        Assert.True(panel.Visible);
        var disposedFields = FocusFrontDoor("field.2");
        var disposedLease = Assert.IsType<TextInputLease>(authority.CurrentTextLease);
        panel.Dispose();
        Assert.True(panel.IsDisposed);
        Assert.False(panel.IsHandleCreated);
        Assert.Null(authority.CurrentTextLease);
        Assert.Null(documentFields.GetValue(panel));
        var disposeReceipt = Assert.IsType<TextExitReceipt>(disposedFields.TakeExitReceipt());
        Assert.Equal(TextExitStatus.Released, disposeReceipt.Status);
        Assert.Equal(disposedLease, disposeReceipt.Lease);
        Assert.False(authority.IsGameKeyboardAdmitted);
    });

    [Fact]
    public void BoundShortcutHookYieldsToTextAndRevokesImmediatelyOnForegroundLoss()
    {
        var authority = StartGameAuthority();
        bool exactForeground = true;
        bool ctrlHeld = false;
        int panelEscapes = 0;
        int shortcuts = 0;
        var posted = new Queue<Action>();
        using var hook = new KeyboardHook
        {
            LiveForegroundProbeForTests = () => exactForeground,
            ReadAsyncKeyState = vk => vk == (int)Keys.LControlKey && ctrlHeld ? unchecked((short)0x8000) : (short)0,
            CapturePanelEscapeAction = () => { panelEscapes++; return null; },
        };
        hook.SetPanelEscapeEnabled(true);
        hook.BindPassiveInput(authority, () => exactForeground, postShortcut: posted.Enqueue);
        hook.RegisterAction((uint)Keys.W, () => shortcuts++);
        IntPtr edge = Marshal.AllocHGlobal(24);
        try
        {
            for (int offset = 0; offset < 24; offset += 4) Marshal.WriteInt32(edge, offset, 0);
            bool Intercept(Keys key, bool down)
            {
                Marshal.WriteInt32(edge, (int)key);
                return hook.ProcessKeyEdge(down ? 0x100 : 0x101, edge) != IntPtr.Zero;
            }

            Assert.False(Intercept(Keys.LControlKey, down: true));
            ctrlHeld = true;
            Assert.True(Intercept(Keys.W, down: true));
            Assert.True(Intercept(Keys.W, down: false));
            var queuedShortcut = Assert.Single(posted);
            posted.Clear();
            Assert.True(authority.TryTakeOutput(out var ctrlBatch));
            Assert.DoesNotContain($",{(int)Keys.W},", ctrlBatch.Payload);
            Assert.False(authority.TryTakeOutput(out _));

            var fields = new WebTextFocusBinding(authority, "skills.1", "web.skills.");
            const string endpoint = "web.skills.field.1";
            ObserveField(fields, (IntPtr)1, (IntPtr)2, endpoint, 1, "focusin");
            SettleGameCancel(authority);
            Assert.True(hook.TextInputActive);
            Assert.False(Intercept(Keys.W, down: true));
            Assert.False(Intercept(Keys.W, down: false));
            Assert.False(Intercept(Keys.Escape, down: true));
            Assert.False(Intercept(Keys.Escape, down: false));
            Assert.False(Intercept(Keys.LControlKey, down: false));
            ctrlHeld = false;
            Assert.Equal(0, panelEscapes);
            Assert.False(authority.TryTakeOutput(out _));
            ObserveField(fields, (IntPtr)1, IntPtr.Zero, endpoint, 1, "focusout");
            Assert.True(authority.TryTakeOutput(out _));
            Assert.True(authority.IsGameKeyboardAdmitted);
            queuedShortcut();
            Assert.Equal(0, shortcuts);
            Assert.Empty(posted);

            Assert.False(Intercept(Keys.D, down: true));
            Assert.True(authority.IsPhysicallyDown((int)Keys.D));
            exactForeground = false;
            Assert.False(Intercept(Keys.LControlKey, down: true));
            ctrlHeld = true;
            Assert.False(Intercept(Keys.W, down: true));
            Assert.False(Intercept(Keys.Escape, down: true));
            Assert.False(authority.IsGameKeyboardAdmitted);
            Assert.False(authority.ForegroundEligible);
            Assert.False(authority.IsPhysicallyDown((int)Keys.W));
            Assert.True(authority.IsSuppressed((int)Keys.D));
            Assert.Equal(0, panelEscapes);
            Assert.Empty(posted);
            SettleGameCancel(authority);
            Assert.False(Intercept(Keys.D, down: false));
            Assert.False(Intercept(Keys.LControlKey, down: false));
            ctrlHeld = false;
            Assert.False(authority.IsPhysicallyDown((int)Keys.D));
            Assert.False(authority.IsSuppressed((int)Keys.D));
            Assert.False(authority.TryTakeOutput(out _));

            exactForeground = true;
            authority.SetForeground(true, held: _ => false);
            Assert.True(authority.IsGameKeyboardAdmitted);
            Assert.True(authority.TryTakeOutput(out var grant));
            Assert.EndsWith("|0|-", grant.Payload);
        }
        finally
        {
            Marshal.FreeHGlobal(edge);
        }
    }

    [Theory]
    [InlineData("hud.main", "hud.notch.expand", "hud_backend_changed")]
    [InlineData("hud.main", "hud.dialogue.advance", "hud_backend_changed")]
    [InlineData("hud.main", "hud.npc.item", "capture_lost")]
    [InlineData("hud.main", "hud.potion.slot", "drag_out")]
    [InlineData("hud.player.bottom", "hud.player.bottom.potion", "hud_backend_changed")]
    [InlineData("hud.player.buffs", "hud.player.buffs.icon", "hud_backend_changed")]
    [InlineData("modifier.surface", "modifier.surface.drag", "capture_lost")]
    public void SharedButtonHasOneConsumerWhileMovementStaysAdmitted(string endpoint, string target, string reason)
    {
        var authority = StartGameAuthority();
        IUiPointerAuthority pointer = authority;
        const int w = (int)Keys.W;
        const int d = (int)Keys.D;
        Assert.True(authority.ObserveKey(w, true));
        Assert.True(authority.ObserveKey(d, true));
        string held = authority.AdmittedHex;
        uint movementWord = Convert.ToUInt32(held.Substring(w / 32 * 8, 8), 16);
        Assert.Equal((1u << (w % 32)) | (1u << (d % 32)), movementWord);
        long epoch = authority.CurrentKeyboardEpoch;
        const int button = 1;
        var point = new Point(120, 80);
        var commits = new List<long>();

        void AssertHeldMovement()
        {
            Assert.True(authority.IsGameKeyboardAdmitted);
            Assert.Equal(epoch, authority.CurrentKeyboardEpoch);
            Assert.Equal(held, authority.AdmittedHex);
        }

        bool Commit(PointerGestureTicket ticket)
        {
            if (!pointer.ValidatePointerCommit(ticket, target)) return false;
            commits.Add(ticket.GestureId);
            pointer.EndPointer(ticket, committed: true);
            return true;
        }

        Assert.True(pointer.TryBeginPointer(endpoint, 1, button, point, target, out var inFlight));
        AssertHeldMovement();
        Assert.False(pointer.TryBeginPointer(endpoint, 1, button, point, target, out _));
        Assert.False(pointer.TryBeginPointer(SessionInputAuthority.WorldEndpoint, 1, button, point, "world", out _));
        Assert.False(pointer.ValidatePointerCommit(inFlight, "other_target"));
        Assert.True(pointer.ValidatePointerCommit(inFlight, target));
        AssertHeldMovement();

        pointer.CancelPointer(inFlight, reason);
        Assert.False(pointer.ValidatePointerCommit(inFlight, target));
        AssertHeldMovement();

        long generation = reason == "hud_backend_changed" ? 2 : 1;
        Assert.True(pointer.TryBeginPointer(endpoint, generation, button, point, target, out var fresh));
        Assert.NotEqual(inFlight.GestureId, fresh.GestureId);
        Assert.False(Commit(inFlight));
        pointer.EndPointer(inFlight, committed: false);
        AssertHeldMovement();
        Assert.True(Commit(fresh));
        Assert.False(Commit(fresh));
        Assert.Equal(fresh.GestureId, Assert.Single(commits));
        AssertHeldMovement();
    }

    private sealed class BootstrapHandleFixture : BootstrapPanel
    {
        internal BootstrapHandleFixture() : base("fixture-web") { }

        // Keep the WinForms lifecycle while isolating the browser/profile initialization.
        protected override void OnLoad(EventArgs e) { }
    }

    private sealed class TextReleaseObserver(SessionInputAuthority authority) : ITextInputAuthority
    {
        internal TextExitReceipt LastRelease { get; private set; }
        internal int GameRequests { get; private set; }
        public string CurrentSessionId => authority.CurrentSessionId;
        public long CurrentKeyboardEpoch => authority.CurrentKeyboardEpoch;
        public TextInputLease? CurrentTextLease => authority.CurrentTextLease;
        public bool IsGameKeyboardAdmitted => authority.IsGameKeyboardAdmitted;

        public long NextInstanceGeneration(string endpointId) => authority.NextInstanceGeneration(endpointId);

        public TextInputLease? AcquireText(string endpointId, long instanceGeneration, in TextFocusObservation focus) =>
            authority.AcquireText(endpointId, instanceGeneration, focus);

        public TextExitReceipt ReleaseText(in TextInputLease lease, in TextExitObservation exit) =>
            LastRelease = authority.ReleaseText(lease, exit);

        public bool RequestGameKeyboard(in TextExitReceipt receipt)
        {
            GameRequests++;
            return authority.RequestGameKeyboard(receipt);
        }
    }
}
