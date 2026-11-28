using System;
using System.Collections.Generic;
using System.Drawing;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class R1UiAdapterTests
{
    [Theory]
    [InlineData("items", "_itemQuery", "_itemQuantity", "_itemPageInput")]
    [InlineData("items", "_itemQuantity", "_itemPageInput", "_itemQuery")]
    [InlineData("items", "_itemPageInput", "_itemQuery", "_itemQuantity")]
    [InlineData("level", "_taskId", "_taskId", "_taskId")]
    [InlineData("units", "_unitLevel", "_unitCount", "_unitPageInput")]
    [InlineData("units", "_unitCount", "_unitPageInput", "_unitLevel")]
    [InlineData("units", "_unitPageInput", "_unitLevel", "_unitCount")]
    public void ModifierTabAndShiftTabStayWithinTheVisibleEditors(string tab, string field,
        string next, string previous) => Sta(() =>
    {
        using var rig = new ModifierRig();
        rig.SwitchTab(tab);
        var editor = rig.Input(field);
        var first = rig.Focus(field, editor.InputEndpointId);
        Invoke(rig.Surface, "CycleEditor", editor, true);
        var nextBox = rig.Input(next);
        Assert.True(nextBox.Focused);
        Assert.Equal(nextBox.InputEndpointId, rig.Authority.CurrentTextLease?.EndpointId);
        Invoke(rig.Surface, "CycleEditor", nextBox, false);
        Assert.True(editor.Focused);
        Invoke(rig.Surface, "CycleEditor", editor, false);
        Assert.True(rig.Input(previous).Focused);
        Assert.Equal(rig.Input(previous).InputEndpointId, rig.Authority.CurrentTextLease?.EndpointId);

        Application.DoEvents();

        Assert.Empty(rig.Authority.GameRequests);
        Assert.False(rig.Authority.IsGameKeyboardAdmitted);
        if (next == field) Assert.Equal<TextInputLease?>(first, rig.Authority.CurrentTextLease);
        else Assert.Contains(rig.Authority.Releases, receipt =>
            receipt.Lease == first && receipt.Status == TextExitStatus.Stale);
    });

    [Theory]
    [InlineData("items", "_itemQuery", "药剂")]
    [InlineData("items", "_itemQuantity", "21")]
    [InlineData("items", "_itemPageInput", "2")]
    [InlineData("level", "_taskId", "42")]
    [InlineData("units", "_unitLevel", "12")]
    [InlineData("units", "_unitCount", "3")]
    [InlineData("units", "_unitPageInput", "2")]
    public void ModifierEscapeLetsImeCancelFirstAndThenRevertsTheEditorDraft(string tab, string field,
        string draft) => Sta(() =>
    {
        using var rig = new ModifierRig();
        rig.SwitchTab(tab);
        var editor = rig.Input(field);
        string original = editor.Text;
        var claim = rig.Focus(field, editor.InputEndpointId);
        editor.Text = draft;
        rig.Frames.Clear();
        var escape = Message.Create(editor.Handle, 0x0100, (IntPtr)(int)Keys.Escape, IntPtr.Zero);

        SendMessage(editor.Handle, 0x010D, IntPtr.Zero, IntPtr.Zero);
        Assert.False(rig.Surface.PreFilterMessage(ref escape));
        Assert.Equal(draft, editor.Text);
        Assert.Equal<TextInputLease?>(claim, rig.Authority.CurrentTextLease);
        Assert.Empty(rig.Authority.GameRequests);

        SendMessage(editor.Handle, 0x010E, IntPtr.Zero, IntPtr.Zero);
        Assert.True(rig.Surface.PreFilterMessage(ref escape));
        Assert.Equal(original, editor.Text);
        Assert.False(editor.Focused);
        Assert.True(rig.Surface.Active);
        Assert.Null(rig.Authority.CurrentTextLease);
        Assert.Equal(claim, Assert.Single(rig.Authority.GameRequests).Lease);
        Assert.Equal((int)Keys.Escape, Assert.Single(rig.Authority.Exits).TriggerVk);
        Assert.Empty(rig.Frames);
    });

    [Theory]
    [InlineData("items", "_itemQuery", "modifierItems")]
    [InlineData("items", "_itemQuantity", null)]
    [InlineData("items", "_itemPageInput", "modifierItems")]
    [InlineData("level", "_taskId", null)]
    [InlineData("units", "_unitLevel", null)]
    [InlineData("units", "_unitCount", null)]
    [InlineData("units", "_unitPageInput", "modifierUnits")]
    public void ModifierEnterNeverBecomesAGameEdgeEvenIfStillHeldWhenTheEditorExits(
        string tab, string field, string readAction) => Sta(() =>
    {
        using var rig = new ModifierRig();
        rig.SwitchTab(tab);
        SetField(rig.Surface, "_itemLoading", false);
        SetField(rig.Surface, "_unitLoading", false);
        SetField(rig.Surface, "_itemTotal", 256);
        SetField(rig.Surface, "_unitTotal", 64);
        var authority = StartGameAuthority();
        rig.Surface.BindInputAuthority(authority, authority);
        var editor = rig.Input(field);
        Assert.True(editor.Focus());
        SettleGameCancel(authority);
        rig.Frames.Clear();
        var claim = authority.CurrentTextLease;
        editor.Text = field == "_itemQuery" ? "药剂" : "2";

        const int enter = (int)Keys.Enter;
        const int escape = (int)Keys.Escape;
        Assert.False(authority.ObserveKey(enter, true));
        var key = new KeyEventArgs(Keys.Enter);
        Invoke(editor, "OnKeyDown", key);
        Assert.True(key.SuppressKeyPress);
        Assert.Equal(claim, authority.CurrentTextLease);
        Assert.False(authority.IsGameKeyboardAdmitted);
        if (readAction == null) Assert.Empty(rig.Frames);
        else Assert.Equal(readAction, Assert.Single(rig.Frames).Value<string>("action"));

        Assert.False(authority.ObserveKey(escape, true));
        var exit = Message.Create(editor.Handle, 0x0100, (IntPtr)escape, IntPtr.Zero);
        Assert.True(rig.Surface.PreFilterMessage(ref exit));
        Assert.True(authority.IsGameKeyboardAdmitted);
        Assert.True(authority.IsSuppressed(enter));
        Assert.True(authority.IsSuppressed(escape));
        Assert.True(authority.TryTakeOutput(out var neutral));
        Assert.EndsWith("|0|-", neutral.Payload);
        Assert.False(authority.ObserveKey(enter, true)); // old repeat
        Assert.False(authority.ObserveKey(enter, false));
        Assert.False(authority.ObserveKey(escape, false));
        Assert.False(authority.TryTakeOutput(out _));
        Assert.True(authority.ObserveKey(enter, true));
        Assert.True(authority.TryTakeOutput(out var fresh));
        Assert.EndsWith(",13,D", fresh.Payload);
    });

    [Fact]
    public void DelayedModifierLeaveCannotReleaseAnotherField() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var queryLease = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        var quantityLease = rig.Focus("_itemQuantity", "modifier.edit.itemQuantity");
        Assert.Empty(rig.Authority.Releases);
        long keyboardEpoch = rig.Authority.CurrentKeyboardEpoch;

        Application.DoEvents();

        var released = Assert.Single(rig.Authority.Releases);
        Assert.Equal(TextExitStatus.Stale, released.Status);
        Assert.Equal(queryLease, released.Lease);
        Assert.Equal<TextInputLease?>(quantityLease, rig.Authority.CurrentTextLease);
        Assert.Equal(keyboardEpoch, rig.Authority.CurrentKeyboardEpoch);
        Assert.Empty(rig.Authority.GameRequests);
    });

    [Fact]
    public void RefocusOfTheSameBoxSurvivesItsOldQueuedLeave() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var first = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        SetFocus(IntPtr.Zero);
        Assert.False(rig.Input("_itemQuery").Focused);
        var second = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        Assert.Equal(first.InstanceGeneration, second.InstanceGeneration);
        Assert.NotEqual(first.LeaseId, second.LeaseId);
        long keyboardEpoch = rig.Authority.CurrentKeyboardEpoch;

        Application.DoEvents();

        var released = Assert.Single(rig.Authority.Releases);
        Assert.Equal(TextExitStatus.Stale, released.Status);
        Assert.Equal(first, released.Lease);
        Assert.Equal<TextInputLease?>(second, rig.Authority.CurrentTextLease);
        Assert.Equal(keyboardEpoch, rig.Authority.CurrentKeyboardEpoch);
    });

    [Fact]
    public void ModifierUsesSevenEndpointIdentitiesAndRetiresThePanelInstance() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var first = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        rig.Focus("_itemQuantity", "modifier.edit.itemQuantity");
        rig.Focus("_itemPageInput", "modifier.edit.itemPageInput");
        rig.SwitchTab("level");
        rig.Focus("_taskId", "modifier.edit.taskId");
        rig.SwitchTab("units");
        rig.Focus("_unitLevel", "modifier.edit.unitLevel");
        rig.Focus("_unitCount", "modifier.edit.unitCount");
        var last = rig.Focus("_unitPageInput", "modifier.edit.unitPageInput");
        rig.Surface.SuspendPanel();
        Assert.Null(rig.Authority.CurrentTextLease);
        Assert.Contains(rig.Authority.Releases, receipt =>
            receipt.Status == TextExitStatus.Released && receipt.Lease == last);
        Assert.Empty(rig.Authority.GameRequests);

        rig.Open("r1.modifier.reopened");
        var reopened = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        Assert.True(reopened.InstanceGeneration > first.InstanceGeneration);
        Application.DoEvents();
        Assert.Equal<TextInputLease?>(reopened, rig.Authority.CurrentTextLease);
    });

    [Fact]
    public void RecreatedEditorHandleInvalidatesItsOldTextLease() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var first = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        Invoke(rig.Input("_itemQuery"), "RecreateHandle");
        var reopened = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        Assert.True(reopened.InstanceGeneration > first.InstanceGeneration);
        Assert.NotEqual(first.LeaseId, reopened.LeaseId);
        Application.DoEvents();
        Assert.Contains(rig.Authority.Releases, receipt =>
            receipt.Status == TextExitStatus.Released && receipt.Lease == first);
        Assert.Equal<TextInputLease?>(reopened, rig.Authority.CurrentTextLease);
    });

    [Theory]
    [InlineData("items", "_itemQuery", "药剂", "modifierItems", 1)]
    [InlineData("items", "_itemPageInput", "2", "modifierItems", 2)]
    [InlineData("units", "_unitPageInput", "2", "modifierUnits", 2)]
    public void ComposingEnterLeavesNativeImeInCharge(string tab, string editor, string text,
        string command, int page) => Sta(() =>
    {
        using var rig = new ModifierRig();
        rig.SwitchTab(tab);
        SetField(rig.Surface, "_itemLoading", false);
        SetField(rig.Surface, "_unitLoading", false);
        SetField(rig.Surface, "_itemTotal", 256);
        SetField(rig.Surface, "_unitTotal", 64);
        rig.Frames.Clear();
        var input = rig.Input(editor);
        input.Text = text;

        SendMessage(input.Handle, 0x010D, IntPtr.Zero, IntPtr.Zero);
        Assert.True(input.IsImeComposing);
        var composing = new KeyEventArgs(Keys.Enter);
        Invoke(input, "OnKeyDown", composing);
        Assert.False(composing.SuppressKeyPress);
        Assert.Empty(rig.Frames);

        SendMessage(input.Handle, 0x010E, IntPtr.Zero, IntPtr.Zero);
        Assert.False(input.IsImeComposing);
        var completed = new KeyEventArgs(Keys.Enter);
        Invoke(input, "OnKeyDown", completed);
        Assert.True(completed.SuppressKeyPress);
        var wire = Assert.Single(rig.Frames);
        Assert.Equal(command, wire.Value<string>("action"));
        Assert.Equal(page, wire.Value<int>("page"));
        if (editor == "_itemQuery") Assert.Equal(text, wire.Value<string>("query"));
    });

    [Fact]
    public void ComposingEscapeLeavesTheLeaseUntilASeparateEscape() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var claim = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        var input = rig.Input("_itemQuery");
        var escape = Message.Create(input.Handle, 0x0100, (IntPtr)(int)Keys.Escape, IntPtr.Zero);
        SendMessage(input.Handle, 0x010D, IntPtr.Zero, IntPtr.Zero);
        Assert.False(rig.Surface.PreFilterMessage(ref escape));
        Assert.Empty(rig.Authority.Releases);
        Assert.Equal<TextInputLease?>(claim, rig.Authority.CurrentTextLease);

        SendMessage(input.Handle, 0x010E, IntPtr.Zero, IntPtr.Zero);
        Assert.True(rig.Surface.PreFilterMessage(ref escape));
        Assert.False(input.Focused);
        Assert.True(rig.Surface.Active);
        Assert.Equal(claim, Assert.Single(rig.Authority.GameRequests).Lease);
        Assert.Equal((int)Keys.Escape, Assert.Single(rig.Authority.Exits).TriggerVk);
    });

    [Fact]
    public void ItemPlusCommitsOnceWithoutChangingGameKeyboardEpoch() => Sta(() =>
    {
        using var rig = new ModifierRig();
        long epoch = rig.Authority.CurrentKeyboardEpoch;
        SendMessage(rig.Surface.Handle, 0x0201, (IntPtr)1, PackPoint(rig.ItemPlus));
        SendMessage(rig.Surface.Handle, 0x0202, IntPtr.Zero, PackPoint(rig.ItemPlus));
        SendMessage(rig.Surface.Handle, 0x0202, IntPtr.Zero, PackPoint(rig.ItemPlus));

        Assert.Equal("2", rig.Input("_itemQuantity").Text);
        var began = Assert.Single(rig.Authority.Begins);
        Assert.Equal("modifier.surface", began.Ticket.EndpointId);
        Assert.Equal(1, began.Ticket.Button);
        Assert.Equal("modifier.button.item_plus", began.Target);
        var ended = Assert.Single(rig.Authority.Ends);
        Assert.Equal(began.Ticket, ended.Ticket);
        Assert.True(ended.Committed);
        Assert.True(rig.Authority.IsGameKeyboardAdmitted);
        Assert.Equal(epoch, rig.Authority.CurrentKeyboardEpoch);
        Assert.Empty(rig.Authority.GameRequests);
    });

    [Fact]
    public void ModifierButtonsAndWheelDoNotInterruptHeldMovement() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var authority = StartGameAuthority();
        rig.Surface.BindInputAuthority(authority, authority);
        Assert.True(authority.ObserveKey((int)Keys.W, true));
        string held = authority.AdmittedHex;
        long epoch = authority.CurrentKeyboardEpoch;
        SetField(rig.Surface, "_itemTotal", 256);
        SetField(rig.Surface, "_itemLoading", false);
        rig.Frames.Clear();
        rig.Mouse("OnMouseDown", rig.ItemPlus);
        rig.Mouse("OnMouseUp", rig.ItemPlus);
        Invoke(rig.Surface, "OnMouseWheel", new MouseEventArgs(MouseButtons.None, 0, 100, 100, -120));

        Assert.Equal("2", rig.Input("_itemQuantity").Text);
        Assert.Equal(2, Assert.Single(rig.Frames).Value<int>("page"));
        Assert.True(authority.IsGameKeyboardAdmitted);
        Assert.Equal(held, authority.AdmittedHex);
        Assert.Equal(epoch, authority.CurrentKeyboardEpoch);
    });

    [Fact]
    public void ModifierDeniedTitleDragDoesNotInvokeTheSystemMove() => Sta(() =>
    {
        using var rig = new ModifierRig();
        rig.Authority.DenyCommit = true;
        long epoch = rig.Authority.CurrentKeyboardEpoch;
        Invoke(rig.Surface, "StartTitleDrag", new Point(300, 20));
        var begin = Assert.Single(rig.Authority.Begins);
        Assert.Equal("modifier.surface.drag", begin.Target);
        Assert.Equal(begin.Ticket, Assert.Single(rig.Authority.Cancellations));
        Assert.Empty(rig.Authority.Ends);
        Assert.Equal(epoch, rig.Authority.CurrentKeyboardEpoch);
        Assert.Empty(rig.Authority.GameRequests);
    });

    [Theory]
    [InlineData(false, false)]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(true, true)]
    public void ModifierTabAndCloseCommitAcrossWorldOnlyGeometry(bool sendMove, bool worldFirst) => Sta(() =>
    {
        foreach (bool changeWorldGeometry in new[] { worldFirst, !worldFirst })
        {
            using var rig = new ModifierRig();
            var authority = StartGameAuthority();
            rig.Surface.BindInputAuthority(authority, authority);
            Assert.True(authority.ObserveKey((int)Keys.D, true));
            string held = authority.AdmittedHex;
            long keyboardEpoch = authority.CurrentKeyboardEpoch;
            long pointerEpoch = authority.CurrentPointerEpoch;
            int closes = 0;
            rig.Surface.CloseRequested += () => closes++;

            void Click(Rectangle rectangle, string target)
            {
                Point point = rig.SurfacePoint(rectangle);
                Rectangle bounds = rig.Surface.Bounds;
                long worldGeometry = authority.CurrentGeometryVersion;
                SendMessage(rig.Surface.Handle, 0x0201, (IntPtr)1, PackPoint(point));
                var ticket = Assert.IsType<PointerGestureTicket>(Field(rig.Surface, "_pointerTicket").GetValue(rig.Surface));
                if (changeWorldGeometry) authority.ChangeWorldGeometry();
                Assert.Equal(worldGeometry + (changeWorldGeometry ? 1 : 0), authority.CurrentGeometryVersion);
                Assert.Equal(bounds, rig.Surface.Bounds);
                Assert.True(authority.ValidatePointerCommit(ticket, target));
                if (sendMove) SendMessage(rig.Surface.Handle, 0x0200, (IntPtr)1, PackPoint(point));
                SendMessage(rig.Surface.Handle, 0x0202, IntPtr.Zero, PackPoint(point));
                SendMessage(rig.Surface.Handle, 0x0202, IntPtr.Zero, PackPoint(point));
                Assert.False(authority.ValidatePointerCommit(ticket, target));
                Assert.False(rig.Surface.Capture);
            }

            rig.SwitchTab("economy");
            Click(ModifierNativeLayout.ItemsTab, "modifier.button.tab:items");
            Assert.Equal("items", Field(rig.Surface, "_activeTab").GetValue(rig.Surface));
            Click(ModifierNativeLayout.Close, "modifier.button.close");
            Assert.Equal(1, closes);
            Assert.Equal(keyboardEpoch, authority.CurrentKeyboardEpoch);
            Assert.Equal(pointerEpoch, authority.CurrentPointerEpoch);
            Assert.Equal(held, authority.AdmittedHex);
        }
    });

    [Theory]
    [InlineData("drag_out")]
    [InlineData("local_geometry")]
    [InlineData("capture_lost")]
    [InlineData("rejected_commit")]
    public void InvalidatedItemPlusNeverChangesQuantity(string cause) => Sta(() =>
    {
        using var rig = new ModifierRig();
        rig.Mouse("OnMouseDown", rig.ItemPlus);
        switch (cause)
        {
            case "drag_out":
                rig.Mouse("OnMouseMove", new Point(10, 60));
                rig.Mouse("OnMouseMove", rig.ItemPlus);
                break;
            case "local_geometry":
                rig.Surface.Left += 10;
                break;
            case "capture_lost":
                rig.Surface.Capture = false;
                Invoke(rig.Surface, "OnMouseCaptureChanged", EventArgs.Empty);
                break;
            case "rejected_commit":
                rig.Authority.DenyCommit = true;
                break;
        }
        rig.Mouse("OnMouseUp", rig.ItemPlus);

        Assert.Equal("1", rig.Input("_itemQuantity").Text);
        var began = Assert.Single(rig.Authority.Begins);
        Assert.Equal(began.Ticket, Assert.Single(rig.Authority.Cancellations));
        Assert.Empty(rig.Authority.Ends);
        Assert.False(rig.Surface.Capture);

        rig.Authority.DenyCommit = false;
        rig.Mouse("OnMouseDown", rig.ItemPlus);
        rig.Mouse("OnMouseUp", rig.ItemPlus);
        Assert.Equal("2", rig.Input("_itemQuantity").Text);
        Assert.True(Assert.Single(rig.Authority.Ends).Committed);
    });

    [Theory]
    [InlineData("items", "ApplyItems", "_selectedItem")]
    [InlineData("units", "ApplyUnits", "_selectedUnit")]
    public void CatalogueReplacementCancelsTheOldRowEvenAtTheSamePosition(string tab, string apply, string selectionField) => Sta(() =>
    {
        using var rig = new ModifierRig();
        var authority = StartGameAuthority();
        rig.Surface.BindInputAuthority(authority, authority);
        rig.SwitchTab(tab);
        Point point = rig.SurfacePoint(tab == "items" ? ModifierNativeLayout.ItemCell(0) : ModifierNativeLayout.UnitRow(0));
        JObject Page(int id) => new()
        {
            ["success"] = true, ["page"] = 1, ["pageSize"] = 8, ["total"] = 1, ["revision"] = 1,
            [tab] = new JArray(new JObject { ["id"] = id, ["name"] = "test." + id })
        };

        Invoke(rig.Surface, apply, Page(11));
        rig.Mouse("OnMouseDown", point);
        var ticket = Assert.IsType<PointerGestureTicket>(Field(rig.Surface, "_pointerTicket").GetValue(rig.Surface));
        Point unchanged = rig.Surface.PointToScreen(point);
        Invoke(rig.Surface, apply, Page(12));
        Assert.Equal(unchanged, rig.Surface.PointToScreen(point));
        Assert.Null(Field(rig.Surface, "_pointerTicket").GetValue(rig.Surface));

        rig.Mouse("OnMouseUp", point);
        Assert.Equal(-1, Field(rig.Surface, selectionField).GetValue(rig.Surface));
        Assert.False(rig.Surface.Capture);

        rig.Mouse("OnMouseDown", point);
        var fresh = Assert.IsType<PointerGestureTicket>(Field(rig.Surface, "_pointerTicket").GetValue(rig.Surface));
        Assert.NotEqual(ticket, fresh);
        rig.Mouse("OnMouseUp", point);
        Assert.Equal(0, Field(rig.Surface, selectionField).GetValue(rig.Surface));
    });

    [Fact]
    public void RejectedForwardedDownLeavesTheOtherEndpointClaimAndCaptureAlone() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var authority = StartGameAuthority();
        rig.Surface.BindInputAuthority(authority, authority);
        Assert.True(authority.TryBeginPointer("flash.world", 1, 1, Point.Empty, "world_fixture", out var world));
        Point client = rig.Owner.PointToClient(rig.Surface.PointToScreen(rig.ItemPlus));
        var down = Message.Create(rig.Owner.Handle, 0x0201, (IntPtr)1, PackPoint(client));
        var up = Message.Create(rig.Owner.Handle, 0x0202, IntPtr.Zero, PackPoint(client));

        Assert.True(rig.Surface.PreFilterMessage(ref down));
        Assert.False(rig.Surface.Capture);
        Assert.True(authority.ValidatePointerCommit(world, "world_fixture"));
        Assert.True(rig.Surface.PreFilterMessage(ref up));
        Assert.True(authority.ValidatePointerCommit(world, "world_fixture"));
        Assert.Equal("1", rig.Input("_itemQuantity").Text);

        authority.EndPointer(world, true);
        Assert.True(rig.Surface.PreFilterMessage(ref down));
        Assert.True(rig.Surface.PreFilterMessage(ref up));
        Assert.Equal("2", rig.Input("_itemQuantity").Text);
    });

    [Fact]
    public void ModifierPrewarmFailureClosesOnlyThePendingAs2Token() => Sta(() =>
    {
        using var owner = CreateOwner();
        using var task = new ModifierTask(() => true, _ => true);
        var closed = new List<string>();
        using var overlay = new ModifierOverlay(owner, "owned", "owned", task,
            token => { closed.Add(token); return true; }, null);
        var surface = (ModifierNativeSurface)Field(overlay, "_surface").GetValue(overlay);
        SetField(surface, "_disposed", true);
        const string token = "modifier.test.pending";

        Assert.True(overlay.Open(new JObject { ["token"] = token }));
        Assert.False(overlay.IsOpen);
        Assert.Null(Field(overlay, "_pendingOpen").GetValue(overlay));
        Assert.Equal(token, Assert.Single(closed));
    });

    [Theory]
    [InlineData("surface", "user", true, true)]
    [InlineData("editor", "user", true, true)]
    [InlineData("surface", "user", true, false)]
    [InlineData("external", "user", false, true)]
    [InlineData("other_owned", "user", false, true)]
    [InlineData("guardian", "user", false, true)]
    [InlineData("surface", "host", false, true)]
    [InlineData("editor", "command", false, true)]
    public void ModifierUserCloseReturnsOnlyItsOwnForegroundBeforeEitherWindowHides(
        string foregroundSource, string closeSource, bool acceptedScope, bool applyForeground) => Sta(() =>
    {
        using var owner = CreateOwner();
        owner.Show();
        using var external = new Form();
        using var otherOwned = new Form { Owner = owner };
        using var task = new ModifierTask(() => true, _ => true);
        var api = new RootFocusApi { ApplyForegroundWrite = applyForeground };
        var manager = new WindowManager(api, IntPtr.Zero);
        manager.ConfigureSessionRoot(owner);
        var notices = new List<string>();
        using var overlay = new ModifierOverlay(owner, "owned", "owned", task,
            token => { notices.Add(token); return true; }, null, manager);
        var authority = StartGameAuthority();
        overlay.BindInputAuthority(authority, authority);
        const string token = "modifier.foreground.fixture";
        Assert.True(overlay.Open(new JObject { ["token"] = token }));
        var surface = (ModifierNativeSurface)Field(overlay, "_surface").GetValue(overlay);
        var editor = (ModifierInputOverlay)Field(surface, "_inputOverlay").GetValue(surface);
        Invoke(surface, "SetTab", "items");
        Assert.True(surface.Visible);
        Assert.True(editor.Visible);
        api.Foreground = foregroundSource switch
        {
            "surface" => surface.Handle,
            "editor" => editor.Handle,
            "other_owned" => otherOwned.Handle,
            "guardian" => owner.Handle,
            _ => external.Handle
        };
        IntPtr foregroundBefore = api.Foreground;
        bool? bothVisibleAtHandoff = null;
        api.BeforeForegroundWrite = () => bothVisibleAtHandoff = surface.Active && surface.Visible && editor.Visible;

        if (closeSource == "host") overlay.CloseFromHost();
        else if (closeSource == "command")
            Assert.True(surface.TryPost(new JObject
            {
                ["type"] = "panel_cmd", ["panel"] = "modifier", ["cmd"] = "force_close"
            }.ToString()));
        else
        {
            Point point = Center(ModifierNativeLayout.ToClient(ModifierNativeLayout.Close, surface.ClientSize));
            var click = new MouseEventArgs(MouseButtons.Left, 1, point.X, point.Y, 0);
            Invoke(surface, "OnMouseDown", click);
            Invoke(surface, "OnMouseUp", click);
        }

        Assert.False(overlay.IsOpen);
        Assert.False(editor.Visible);
        Assert.Equal(token, Assert.Single(notices));
        if (acceptedScope)
        {
            Assert.Equal(owner.Handle, Assert.Single(api.ForegroundWrites));
            Assert.True(bothVisibleAtHandoff);
            Assert.Equal(applyForeground ? owner.Handle : foregroundBefore, api.Foreground);
        }
        else
        {
            Assert.Empty(api.ForegroundWrites);
            Assert.Null(bothVisibleAtHandoff);
            Assert.Equal(foregroundBefore, api.Foreground);
        }
    });

    [Fact]
    public void QueuedOldHostCloseCannotCloseAReopenedModifier() => Sta(() =>
    {
        using var owner = CreateOwner();
        owner.Show();
        using var task = new ModifierTask(() => true, _ => true);
        var closed = new List<string>();
        var api = new RootFocusApi();
        var manager = new WindowManager(api, IntPtr.Zero);
        manager.ConfigureSessionRoot(owner);
        using var overlay = new ModifierOverlay(owner, "owned", "owned", task,
            token => { closed.Add(token); return true; }, null, manager);
        overlay.Prewarm();
        JObject Data(string token) => ModifierTask.BuildOpenData("nativehud_modifier",
            new JObject { ["token"] = token }.ToString());

        const string oldToken = "modifier.test.old";
        const string newToken = "modifier.test.new";
        Assert.True(overlay.Open(Data(oldToken)));
        Task.Run(overlay.CloseFromHost).GetAwaiter().GetResult();
        overlay.CloseFromHost();
        Assert.True(overlay.Open(Data(newToken)));
        var surface = (ModifierNativeSurface)Field(overlay, "_surface").GetValue(overlay);
        api.Foreground = surface.Handle;
        Application.DoEvents();

        Assert.True(overlay.IsOpen);
        Assert.Empty(api.ForegroundWrites);
        Assert.Equal(oldToken, Assert.Single(closed));
        overlay.CloseFromHost();
        Assert.Equal(new[] { oldToken, newToken }, closed);
    });

    [Fact]
    public void ClickingItemPlusExitsExactEditorAndConsumesBothEdgesOverTheWorld() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var editor = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        rig.Frames.Clear();
        Point client = rig.Owner.PointToClient(rig.Surface.PointToScreen(rig.ItemPlus));
        IntPtr packed = PackPoint(client);
        var down = Message.Create(rig.Owner.Handle, 0x0201, (IntPtr)1, packed);
        var up = Message.Create(rig.Owner.Handle, 0x0202, IntPtr.Zero, packed);

        Assert.True(rig.Surface.PreFilterMessage(ref down));
        Assert.True(rig.Surface.PreFilterMessage(ref up));
        Application.DoEvents();

        var released = Assert.Single(rig.Authority.Releases);
        Assert.Equal(TextExitStatus.Released, released.Status);
        Assert.Equal(editor, released.Lease);
        Assert.Equal(released, Assert.Single(rig.Authority.GameRequests));
        Assert.True(Assert.Single(rig.Authority.Ends).Committed);
        Assert.Null(rig.Authority.CurrentTextLease);
        Assert.False(rig.Input("_itemQuery").Focused);
        Assert.Equal("2", rig.Input("_itemQuantity").Text);
        Assert.Empty(rig.Frames);
    });

    [Theory]
    [InlineData("commit")]
    [InlineData("drag_out")]
    [InlineData("capture_lost")]
    public void SharedNotchExpandUsesItsNativeHitAndKeepsTheKeyboardEpoch(string result) => Sta(() =>
    {
        using var owner = CreateOwner();
        _ = owner.Handle;
        using var notch = new NotchWidget(owner, new FpsRingBuffer(300), "", null, null, null, null);
        using var hud = new NativeHudOverlay(owner, owner);
        hud.AddWidget(notch);
        notch.ForceGameReadyForTest(true);
        notch.BeginExpandForTest();
        notch.Tick(300);
        Rectangle bounds = notch.ScreenBounds;
        using var bitmap = new Bitmap(bounds.Width, bounds.Height);
        using var graphics = Graphics.FromImage(bitmap);
        notch.Paint(graphics, 1, bounds.Location);
        var hit = (Rectangle)Field(notch, "_expandButtonRect").GetValue(notch);
        Assert.True(hit.Width > 0 && hit.Height > 0);
        hit.Offset(bounds.Location);
        var point = Center(hit);
        var authority = new RecordingAuthority();
        hud.BindPointerAuthority(authority);
        var input = new NativeHudOverlay.MainHudInput(hud, owner, () => true);
        var queue = new Queue<Action>();
        var router = new WorldHudPointerRouter(queue.Enqueue);
        router.SetInput(input);
        long epoch = authority.CurrentKeyboardEpoch;
        void Flush()
        {
            while (queue.TryDequeue(out var work)) work();
        }

        Assert.True(router.TryRoute(0x0201, point, 1, false));
        Flush();
        if (result == "drag_out")
        {
            var outside = new Point(bounds.Right + 20, bounds.Bottom + 20);
            Assert.True(router.TryRoute(0x0200, outside, 1, false));
            Flush();
        }
        else if (result == "capture_lost")
        {
            router.Cancel();
            Flush();
        }
        Assert.True(router.TryRoute(0x0202, point, 0, false));
        Flush();

        var began = Assert.Single(authority.Begins);
        Assert.Equal("hud.notch.expand", began.Ticket.EndpointId);
        Assert.Equal("hud.notch.expand", began.Target);
        if (result == "commit")
        {
            Assert.True(Assert.Single(authority.Ends).Committed);
            Assert.Equal("Collapsing", Field(notch, "_state").GetValue(notch).ToString());
        }
        else
        {
            Assert.Equal(began.Ticket, Assert.Single(authority.Cancellations));
            Assert.Empty(authority.Ends);
            Assert.Equal("Expanded", Field(notch, "_state").GetValue(notch).ToString());
        }
        Assert.Equal(epoch, authority.CurrentKeyboardEpoch);
        Assert.True(authority.IsGameKeyboardAdmitted);
    });

    [Fact]
    public void DelayedLeaveDeactivateAndClosedCannotReleaseTheNextNativeEditor() => Sta(() =>
    {
        using var rig = new ModifierRig();
        var query = rig.Focus("_itemQuery", "modifier.edit.itemQuery");
        using var interject = new DialogueInterjectInputOverlay();
        interject.AttachOwner(rig.Owner);
        interject.BindInputAuthority(rig.Authority, rig.Authority);
        interject.SetInputEnabled(true);
        interject.ExpandForTest();
        interject.Show();
        var native = (TextBox)Field(interject, "_textBox").GetValue(interject);
        Assert.True(native.Focus());
        var dialogue = rig.Authority.CurrentTextLease.Value;
        Assert.Equal("dialogue.interject.input", dialogue.EndpointId);
        Assert.True(interject.IsTextInputActive());
        SetFocus(IntPtr.Zero);

        using var config = new DialogueInterjectConfigWindow("unused", "http://127.0.0.1:7077/config?popup=1",
            autoMode: false, developerMode: false);
        config.Owner = rig.Owner;
        config.BindInputAuthority(rig.Authority, rig.Authority);
        _ = config.Handle;
        string instance = (string)Field(config, "_inputInstance").GetValue(config);
        var selectors = (IReadOnlyDictionary<string, string>)typeof(DialogueInterjectConfigWindow)
            .GetField("EditorSelectors", BindingFlags.Static | BindingFlags.NonPublic).GetValue(null);
        var fields = new WebTextFocusBinding(rig.Authority, instance, "dialogue.interject.config.", selectors);
        // Exercise the popup's actual lifecycle callbacks with a synthetic
        // controller focus fact. This fixture never starts the terminal.
        SetField(config, "_textFields", fields);
        ObserveField(fields, rig.Owner.Handle, config.Handle, "dialogue.interject.config.endpoint", 1, "focusin");
        var endpoint = rig.Authority.CurrentTextLease.Value;
        Invoke(config, "QueueWebViewFocusLoss");
        ObserveField(fields, rig.Owner.Handle, config.Handle, "dialogue.interject.config.model", 2, "focusin");
        var model = rig.Authority.CurrentTextLease.Value;
        Assert.Equal("dialogue.interject.config.model", model.EndpointId);
        Invoke(config, "OnDeactivate", EventArgs.Empty);
        ObserveField(fields, rig.Owner.Handle, config.Handle, "dialogue.interject.config.apiKey", 3, "focusin");
        var apiKey = rig.Authority.CurrentTextLease.Value;
        Assert.Equal("dialogue.interject.config.apiKey", apiKey.EndpointId);
        Invoke(config, "OnFormClosing", new FormClosingEventArgs(CloseReason.UserClosing, false));

        rig.SwitchTab("units");
        var level = rig.Focus("_unitLevel", "modifier.edit.unitLevel");
        Invoke(config, "OnFormClosed", new FormClosedEventArgs(CloseReason.UserClosing));
        Assert.Empty(rig.Authority.Releases);
        long epoch = rig.Authority.CurrentKeyboardEpoch;
        Application.DoEvents();

        var releasedLeases = Array.ConvertAll(rig.Authority.Releases.ToArray(), receipt => receipt.Lease);
        foreach (var expectedLease in new[] { query, dialogue, endpoint, model, apiKey })
            Assert.Contains(expectedLease, releasedLeases);
        Assert.All(rig.Authority.Releases, receipt => Assert.Equal(TextExitStatus.Stale, receipt.Status));
        Assert.Equal<TextInputLease?>(level, rig.Authority.CurrentTextLease);
        Assert.Equal(epoch, rig.Authority.CurrentKeyboardEpoch);
        Assert.False(interject.IsTextInputActive());
        Assert.Empty(rig.Authority.GameRequests);
    });

    [Fact]
    public void DialogueGearSurvivesWorldGeometryButLocalMoveCancels() => Sta(() =>
    {
        using var owner = CreateOwner();
        owner.Show();
        var authority = StartGameAuthority();
        using var interject = new DialogueInterjectInputOverlay();
        interject.AttachOwner(owner);
        interject.BindInputAuthority(authority, authority);
        interject.ExpandForTest();
        interject.Show();
        Point point = Center((Rectangle)Field(interject, "_settingsRect").GetValue(interject));
        var click = new MouseEventArgs(MouseButtons.Left, 1, point.X, point.Y, 0);
        int opens = 0;
        interject.ConfigRequested += () => opens++;

        Invoke(interject, "OnMouseDown", click);
        authority.ChangeWorldGeometry();
        Invoke(interject, "OnMouseUp", click);
        Assert.Equal(1, opens);

        Invoke(interject, "OnMouseDown", click);
        interject.Left += 5;
        Invoke(interject, "OnMouseUp", click);
        Assert.Equal(1, opens);
        Assert.False(interject.Capture);

        Invoke(interject, "OnMouseDown", click);
        Invoke(interject, "OnMouseUp", click);
        Assert.Equal(2, opens);
    });

    [Fact]
    public void DialogueSubmitKeepsImeLocalThenReleasesItsExactEditorWithoutLegacyNotification() => Sta(() =>
    {
        using var rig = new ModifierRig();
        using var interject = new DialogueInterjectInputOverlay();
        interject.AttachOwner(rig.Owner);
        interject.BindInputAuthority(rig.Authority, rig.Authority);
        interject.SetInputEnabled(true);
        interject.ExpandForTest();
        interject.Show();
        var editor = (TextBox)Field(interject, "_textBox").GetValue(interject);
        Assert.True(editor.Focus());
        var lease = rig.Authority.CurrentTextLease.Value;
        var sent = new List<string>();
        interject.SendRequested += sent.Add;
        editor.Text = "药剂";

        SendMessage(editor.Handle, 0x010D, IntPtr.Zero, IntPtr.Zero);
        Invoke(editor, "OnKeyDown", new KeyEventArgs(Keys.Enter));
        Invoke(editor, "OnKeyDown", new KeyEventArgs(Keys.Escape));
        Assert.Empty(sent);
        Assert.Equal<TextInputLease?>(lease, rig.Authority.CurrentTextLease);

        SendMessage(editor.Handle, 0x010E, IntPtr.Zero, IntPtr.Zero);
        var enter = new KeyEventArgs(Keys.Enter);
        Invoke(editor, "OnKeyDown", enter);
        Assert.True(enter.SuppressKeyPress);
        Assert.Equal("药剂", Assert.Single(sent));
        Assert.Equal(lease, Assert.Single(rig.Authority.GameRequests).Lease);
        Assert.Equal((int)Keys.Enter, Assert.Single(rig.Authority.Exits).TriggerVk);
        Assert.False(interject.IsTextInputActive());
    });

    [Theory]
    [InlineData("settings", "web.settings.", "keys.search")]
    [InlineData("inventory", "web.inventory.", "field.1")]
    [InlineData("tasks", "web.tasks.", "field.1")]
    [InlineData("archive", "web.archive.", "field.1")]
    [InlineData("help", "composition.help.", "field.1")]
    [InlineData("intelligence", "composition.intelligence.", "field.1")]
    [InlineData("transition", "composition.transition.", "field.1")]
    public void WebFieldMessagesRequireTheExactInstanceDocumentFieldAndTurn(
        string panel, string prefix, string firstField)
    {
        var authority = new RecordingAuthority();
        var fields = new WebTextFocusBinding(authority, panel + ".test", prefix);
        var root = (IntPtr)1;
        var editor = (IntPtr)2;
        string first = prefix + firstField;
        string next = prefix + "field.2";

        ObserveField(fields, root, editor, first, 1, "focusin", token: "previous-document");
        ObserveField(fields, root, editor, first, 1, "focusin", instance: panel + ".old");
        ObserveField(fields, root, IntPtr.Zero, first, 1, "focusin");
        Assert.Null(authority.CurrentTextLease);
        ObserveField(fields, root, editor, first, 1, "focusin");
        var firstLease = authority.CurrentTextLease.Value;

        ObserveField(fields, root, editor, first, 1, "compositionstart");
        Assert.True(fields.ImeComposing);
        ObserveField(fields, root, editor, next, 1, "compositionend");
        Assert.True(fields.ImeComposing);
        ObserveField(fields, root, editor, first, 1, "compositionend");
        Assert.False(fields.ImeComposing);
        Assert.Equal<TextInputLease?>(firstLease, authority.CurrentTextLease);
        var delayed = fields.CaptureExit("test_delayed_blur", requestGame: true);
        ObserveField(fields, root, editor, next, 2, "focusin");
        var newLease = authority.CurrentTextLease.Value;
        ObserveField(fields, root, editor, first, 1, "focusout");
        ObserveField(fields, root, editor, next, 2, "focusout", token: "previous-document");
        delayed();
        Assert.Equal(TextExitStatus.Stale, Assert.Single(authority.Releases).Status);
        Assert.Empty(authority.GameRequests);
        Assert.Equal<TextInputLease?>(newLease, authority.CurrentTextLease);

        ObserveField(fields, root, IntPtr.Zero, next, 2, "focusout");
        ObserveField(fields, root, IntPtr.Zero, next, 2, "focusout");
        Assert.Null(authority.CurrentTextLease);
        Assert.Equal(newLease, Assert.Single(authority.GameRequests).Lease);
        Assert.Equal(2, authority.Releases.Count);
    }

    [Theory]
    [InlineData("help")]
    [InlineData("intelligence")]
    [InlineData("transition")]
    public void CompositionRetirementClearsCaptureAndOnlyTheHostReleasesModalState(string profile) => Sta(() =>
    {
        using var owner = CreateOwner();
        using var surface = new CompositionHelpSurface(owner, "owned", "owned",
            profile: profile == "intelligence" ? CompositionPanelProfile.Intelligence : CompositionPanelProfile.Help,
            transition: profile == "transition");
        var authority = new RecordingAuthority();
        var states = new List<bool>();
        surface.BindInputAuthority(authority, authority, enableUniversalTextFocus: true);
        surface.SurfaceModalStateChanged += states.Add;
        SetField(surface, "_pressedButtons", 1);
        SetField(surface, "_capturedButton", true);
        surface.NotifySurfaceModalState(true);
        surface.NotifySurfaceModalState(true);
        Assert.Equal(0, (int)Field(surface, "_pressedButtons").GetValue(surface));
        Assert.False((bool)Field(surface, "_capturedButton").GetValue(surface));

        SetField(surface, "_pressedButtons", 1);
        Invoke(surface, "OnVisibleChanged", EventArgs.Empty);
        Assert.Equal(0, (int)Field(surface, "_pressedButtons").GetValue(surface));
        Assert.Equal(new[] { true }, states);
        Assert.Empty(authority.GameRequests);

        SetField(surface, "_active", true);
        SetField(surface, "_panelInstance", "fixture.composition");
        var endpoint = surface.CaptureEndpointLease();
        Assert.NotNull(endpoint);
        Assert.True(surface.RetireExact(endpoint));
        Assert.False(surface.RetireExact(endpoint));
        Assert.Equal(new[] { true }, states);
        surface.NotifySurfaceModalState(false);
        surface.NotifySurfaceModalState(false);
        Assert.Equal(new[] { true, false }, states);
    });

    internal static void ObserveField(WebTextFocusBinding fields, IntPtr root, IntPtr editor,
        string endpoint, long turn, string phase, string token = null, string instance = null,
        bool requestGameOnBlur = true)
    {
        fields.Observe(new JObject
        {
            ["type"] = "ui_field_focus",
            ["panelInstanceId"] = instance ?? fields.PanelInstanceId,
            ["documentToken"] = token ?? (string)Field(fields, "_documentToken").GetValue(fields),
            ["endpointId"] = endpoint,
            ["focusTurn"] = turn,
            ["phase"] = phase,
            ["focused"] = phase != "focusout",
            ["composing"] = phase == "compositionstart"
        }, root, editor, requestGameOnBlur);
    }

    internal static SessionInputAuthority StartGameAuthority()
    {
        var authority = new SessionInputAuthority(PassiveFlashInputMode.Disabled);
        authority.Connect(1);
        Assert.True(authority.TryTakeOutput(out var bind));
        authority.SetForeground(true);
        authority.SetBusinessEligible(true, "fixture_ready");
        Assert.True(authority.Receive(1, bind.Payload.Replace("|Bind|", "|Capability|")));
        Assert.True(authority.TryTakeOutput(out _));
        Assert.True(authority.IsGameKeyboardAdmitted);
        return authority;
    }

    internal static void SettleGameCancel(SessionInputAuthority authority)
    {
        Assert.True(authority.TryTakeOutput(out var cancel));
        var fields = cancel.Payload.Split('|');
        Assert.Equal("Cancel", fields[1]);
        Assert.True(authority.Receive(cancel.Connection, "I1|Cancelled|" + string.Join("|", fields, 2, 7) + "|1|1"));
        Assert.False(authority.IsGameKeyboardAdmitted);
    }

    private sealed class ModifierRig : IDisposable
    {
        internal readonly Form Owner = CreateOwner();
        internal readonly RecordingAuthority Authority = new();
        internal readonly List<JObject> Frames = new();
        internal readonly ModifierNativeSurface Surface;
        private readonly ModifierTask _task;

        internal ModifierRig()
        {
            Owner.Show();
            _task = new ModifierTask(() => true,
                frame => { Frames.Add(JObject.Parse(frame.TrimEnd('\0'))); return true; });
            Surface = new ModifierNativeSurface(Owner, "owned", "owned", _task);
            Surface.BindInputAuthority(Authority, Authority);
            Open("r1.modifier.open");
        }

        internal void Open(string instance)
        {
            Assert.True(Surface.ResumePanel(Owner.RectangleToScreen(Owner.ClientRectangle)));
            Assert.True(Surface.TryPost(new JObject
            {
                ["type"] = "panel_cmd",
                ["panel"] = "modifier",
                ["cmd"] = "open",
                ["initData"] = new JObject { ["panelInstanceId"] = instance, ["token"] = "modifier.r1-test" }
            }.ToString()));
            SwitchTab("items");
        }

        internal Point ItemPlus => SurfacePoint(ModifierNativeLayout.ItemPlus);
        internal Point SurfacePoint(Rectangle logicalBounds) => Center(ModifierNativeLayout.ToClient(logicalBounds, Surface.ClientSize));
        internal ModifierTextBox Input(string field) => (ModifierTextBox)Field(Surface, field).GetValue(Surface);
        internal void SwitchTab(string tab) => Invoke(Surface, "SetTab", tab);
        internal TextInputLease Focus(string field, string endpoint)
        {
            Assert.True(Input(field).Focus());
            Assert.True(Authority.CurrentTextLease.HasValue);
            var lease = Authority.CurrentTextLease.Value;
            Assert.Equal(endpoint, lease.EndpointId);
            return lease;
        }
        internal void Mouse(string message, Point point) =>
            Invoke(Surface, message, new MouseEventArgs(MouseButtons.Left, 1, point.X, point.Y, 0));
        public void Dispose()
        {
            Surface.Dispose();
            _task.Dispose();
            Owner.Dispose();
        }
    }

    private sealed class RecordingAuthority : ITextInputAuthority, IUiPointerAuthority
    {
        private readonly Dictionary<string, long> _instances = new();
        private long _generation, _exitSerial, _gestureId;
        private ulong _leaseId;
        private TextExitReceipt? _lastExit;
        private (PointerGestureTicket Ticket, string Target)? _pointer;
        internal readonly List<TextExitObservation> Exits = new();
        internal readonly List<TextExitReceipt> Releases = new();
        internal readonly List<TextExitReceipt> GameRequests = new();
        internal readonly List<(PointerGestureTicket Ticket, string Target)> Begins = new();
        internal readonly List<(PointerGestureTicket Ticket, bool Committed)> Ends = new();
        internal readonly List<PointerGestureTicket> Cancellations = new();
        internal bool DenyCommit;

        public string CurrentSessionId { get; } = "1234567890abcdef1234567890abcdef";
        public long CurrentKeyboardEpoch { get; private set; } = 1;
        public TextInputLease? CurrentTextLease { get; private set; }
        public bool IsGameKeyboardAdmitted { get; private set; } = true;
        public long CurrentPointerEpoch { get; } = 1;
        public long CurrentGeometryVersion { get; set; } = 1;

        public long NextInstanceGeneration(string endpointId) => _instances[endpointId] = ++_generation;
        public TextInputLease? AcquireText(string endpointId, long instanceGeneration, in TextFocusObservation observedFocus)
        {
            Assert.Equal(CurrentSessionId, observedFocus.SessionId);
            Assert.True(observedFocus.LocalFocusConfirmed);
            Assert.NotEqual(IntPtr.Zero, observedFocus.RootHwnd);
            Assert.NotEqual(IntPtr.Zero, observedFocus.EditorHwnd);
            Assert.Equal(_instances[endpointId], instanceGeneration);
            _lastExit = null;
            IsGameKeyboardAdmitted = false;
            return CurrentTextLease = new TextInputLease(endpointId, instanceGeneration, ++_leaseId);
        }
        public TextExitReceipt ReleaseText(in TextInputLease exactLease, in TextExitObservation observedExit)
        {
            Exits.Add(observedExit);
            bool admitted = CurrentTextLease == exactLease && observedExit.SessionId == CurrentSessionId
                && observedExit.EditorFocusCleared;
            var receipt = new TextExitReceipt(admitted ? TextExitStatus.Released : TextExitStatus.Stale,
                CurrentSessionId, exactLease, CurrentKeyboardEpoch, admitted ? ++_exitSerial : _exitSerial);
            if (admitted)
            {
                CurrentTextLease = null;
                _lastExit = receipt;
            }
            Releases.Add(receipt);
            return receipt;
        }
        public bool RequestGameKeyboard(in TextExitReceipt exactRelease)
        {
            GameRequests.Add(exactRelease);
            if (_lastExit != exactRelease || CurrentTextLease.HasValue) return false;
            _lastExit = null;
            IsGameKeyboardAdmitted = true;
            CurrentKeyboardEpoch++;
            return true;
        }
        public bool TryBeginPointer(string endpointId, long instanceGeneration, int button,
            Point screenPoint, string localTargetId, out PointerGestureTicket ticket)
        {
            Assert.Null(_pointer);
            Assert.True(instanceGeneration > 0);
            ticket = new PointerGestureTicket(endpointId, instanceGeneration, CurrentGeometryVersion,
                CurrentPointerEpoch, ++_gestureId, button);
            _pointer = (ticket, localTargetId);
            Begins.Add((ticket, localTargetId));
            return true;
        }
        public bool ValidatePointerCommit(in PointerGestureTicket exactTicket, string localTargetId)
            => !DenyCommit && _pointer is { } active && active.Ticket == exactTicket && active.Target == localTargetId;
        public void EndPointer(in PointerGestureTicket exactTicket, bool committed)
        {
            Assert.Equal(exactTicket, _pointer.Value.Ticket);
            _pointer = null;
            Ends.Add((exactTicket, committed));
        }
        public void CancelPointer(in PointerGestureTicket exactTicket, string reason)
        {
            Assert.Equal(exactTicket, _pointer.Value.Ticket);
            _pointer = null;
            Cancellations.Add(exactTicket);
        }
    }

    internal static Form CreateOwner() => new()
    {
        StartPosition = FormStartPosition.Manual,
        FormBorderStyle = FormBorderStyle.None,
        AutoScaleMode = AutoScaleMode.None,
        Bounds = new Rectangle(-30000, -30000, 1016, 550),
        ShowInTaskbar = false
    };

    private static Point Center(Rectangle bounds) => new(bounds.X + bounds.Width / 2, bounds.Y + bounds.Height / 2);
    private static IntPtr PackPoint(Point point) => (IntPtr)((point.Y << 16) | (point.X & 0xffff));
    private static FieldInfo Field(object target, string name) => target.GetType().GetField(name, BindingFlags.Instance | BindingFlags.NonPublic);
    private static void SetField(object target, string name, object value) => Field(target, name).SetValue(target, value);
    private static void Invoke(object target, string method, params object[] args) =>
        target.GetType().GetMethod(method, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(target, args);

    internal static void Sta(Action action)
    {
        Exception failure = null;
        var thread = new Thread(() =>
        {
            try { action(); }
            catch (Exception error) { failure = error; }
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(20)), "Adapter STA did not settle.");
        if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SetFocus(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);
}
