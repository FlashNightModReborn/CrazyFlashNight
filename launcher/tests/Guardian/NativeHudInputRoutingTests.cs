using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativeHudInputRoutingTests
    {
        private const int WM_NCHITTEST = 0x0084;
        private const int WM_MOUSEMOVE = 0x0200;
        private const int WM_LBUTTONDOWN = 0x0201;
        private const int WM_LBUTTONUP = 0x0202;
        private const int MK_LBUTTON = 0x0001;
        private const int HTCLIENT = 1;
        private const int HTTRANSPARENT = -1;

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessage(
            IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint colorKey, byte alpha, uint flags);

        private sealed class RecordingWidget : INativeHudWidget
        {
            private Rectangle _bounds;

            public RecordingWidget(Rectangle bounds)
            {
                _bounds = bounds;
                Events = new List<MouseEventKind>();
            }

            public List<MouseEventKind> Events { get; private set; }
            public Rectangle ScreenBounds { get { return _bounds; } }
            public bool Visible { get { return true; } }
            public bool WantsAnimationTick { get { return false; } }

            public event EventHandler BoundsOrVisibilityChanged;
            public event EventHandler RepaintRequested;
            public event EventHandler AnimationStateChanged;

            public Color PaintColor = Color.Transparent;
            public void Paint(Graphics g, float dpr, Point hudOrigin)
            {
                Rectangle local = _bounds;
                local.Offset(-hudOrigin.X, -hudOrigin.Y);
                using (var brush = new SolidBrush(PaintColor)) g.FillRectangle(brush, local);
            }
            public bool TryHitTest(Point screenPt) { return _bounds.Contains(screenPt); }
            public void Tick(int deltaMs) { }

            public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
            {
                Events.Add(kind);
            }

            public void MoveTo(Rectangle bounds)
            {
                _bounds = bounds;
                EventHandler handler = BoundsOrVisibilityChanged;
                if (handler != null) handler(this, EventArgs.Empty);
            }
        }

        private sealed class TestNativeHudOverlay : NativeHudOverlay
        {
            public TestNativeHudOverlay(Form owner, Control anchor)
                : base(owner, anchor)
            {
            }

            public bool SessionForegroundForTest;

            protected override bool IsOwnerSessionForeground()
            {
                return SessionForegroundForTest;
            }

            public void SimulateOwnerHidden()
            {
                _ownerVisible = false;
                OnOwnerVisibilityChanged(false);
                HideOverlay();
            }
        }

        [Fact]
        public void RealHwnd_NcHitTestAndDownUpUseScreenCoordinateChain()
        {
            using (Form owner = CreateOwner())
            using (TestNativeHudOverlay hud = CreateHud(
                owner, out RecordingWidget widget))
            {
                Point center = Center(widget.ScreenBounds);
                Assert.Equal(HTCLIENT, SendNcHitTest(hud, center));
                Assert.Equal(HTTRANSPARENT, SendNcHitTest(
                    hud,
                    new Point(widget.ScreenBounds.Left - 2,
                        widget.ScreenBounds.Top - 2)));

                SendMouse(hud, WM_LBUTTONDOWN, center);
                SendMouse(hud, WM_LBUTTONUP, center);

                Assert.Equal(new[]
                {
                    MouseEventKind.Down,
                    MouseEventKind.Up,
                    MouseEventKind.Click
                }, widget.Events);
            }
        }

        [Fact]
        public void DiagnosticRealHwndDirectMessageDoesNotInventPhysicalReceiverProof()
        {
            var trace = new List<string>();
            CF7Launcher.Diagnostic.FocusTrace.Start(trace.Add, false);
            try
            {
                using (Form owner = CreateOwner())
                using (TestNativeHudOverlay hud = CreateHud(owner, out RecordingWidget widget))
                {
                    Point center = Center(widget.ScreenBounds);
                    SendMouse(hud, WM_LBUTTONDOWN, center);
                    SendMouse(hud, WM_LBUTTONUP, center);
                    CF7Launcher.Diagnostic.FocusTrace.Flush();
                    Assert.Equal(new[] { MouseEventKind.Down, MouseEventKind.Up, MouseEventKind.Click }, widget.Events);
                    string evidence = string.Join("\n", trace);
                    Assert.Contains("hud.down", evidence);
                    Assert.Contains("hud.up", evidence);
                    Assert.Contains("\"correlation\":\"unobserved\"", evidence);
                    Assert.DoesNotContain("mouse.down", evidence);
                }
            }
            finally { CF7Launcher.Diagnostic.FocusTrace.Stop(); }
        }

        [Fact]
        public void DiagnosticSeparatesLogicalHitTransparentSurfaceAndNativeMessageReceipt()
        {
            var trace = new List<string>();
            FocusTrace.Start(trace.Add, false);
            try
            {
                using (Form owner = CreateOwner())
                using (TestNativeHudOverlay hud = CreateHud(owner, out RecordingWidget widget))
                {
                    Point center = Center(widget.ScreenBounds);
                    FocusTrace.SetTarget(widget.ScreenBounds);
                    FocusTrace.PhysicalEdge(WM_LBUTTONDOWN, center, 1, 10, 7);
                    Assert.Equal(HTCLIENT, SendNcHitTest(hud, center));
                    JObject surface = JObject.FromObject(FocusTrace.CaptureHudInput(center));
                    Assert.Equal(nameof(RecordingWidget), (string)surface["logicalWidget"]);
                    Assert.Equal(0, (int)surface["submittedSourceAlpha"]);
                    Assert.True((bool)surface["lastCommit"]["Succeeded"]);
                    SendMouse(hud, WM_LBUTTONDOWN, center);
                    SendMouse(hud, WM_LBUTTONUP, center);
                    Assert.Equal(new[] { MouseEventKind.Down, MouseEventKind.Up, MouseEventKind.Click }, widget.Events);

                    widget.PaintColor = Color.FromArgb(120, 50, 100, 150);
                    widget.MoveTo(widget.ScreenBounds);
                    JObject painted = JObject.FromObject(FocusTrace.CaptureHudInput(center));
                    Assert.Equal(120, (int)painted["submittedSourceAlpha"]);
                    Assert.Equal((long)surface["placementGeneration"], (long)painted["placementGeneration"]);
                    Assert.True((long)painted["paintGeneration"] > (long)surface["paintGeneration"]);

                    FocusTrace.Flush();
                    JObject[] rows = ReadFocusRows(trace);
                    JObject enter = rows.First(x => (string)x["event"] == "hud.native_mouse" && (string)x["data"]["phase"] == "enter");
                    JObject down = rows.Single(x => (string)x["event"] == "hud.down");
                    JObject exit = rows.First(x => (string)x["event"] == "hud.native_mouse" && (string)x["data"]["phase"] == "exit");
                    Assert.True((long)enter["seq"] < (long)down["seq"] && (long)down["seq"] < (long)exit["seq"]);
                    Assert.Contains(rows, x => (string)x["event"] == "hud.native_hit_test" && (int)x["data"]["result"] == HTCLIENT);
                }
                Assert.Null(FocusTrace.HudInputSnapshot);
            }
            finally { FocusTrace.Stop(); }
        }

        [Fact]
        public void FailedOriginalLayeredCommitCannotClaimNewPixelsWereSubmitted()
        {
            FocusTrace.Start(_ => { }, false);
            try
            {
                using (Form owner = CreateOwner())
                using (TestNativeHudOverlay hud = CreateHud(owner, out RecordingWidget widget))
                {
                    Point center = Center(widget.ScreenBounds);
                    JObject before = JObject.FromObject(FocusTrace.CaptureHudInput(center));
                    // Win32 明确规定 SLA 之后的 ULW 会失败，直至重置 layered style。
                    Assert.True(SetLayeredWindowAttributes(hud.Handle, 0, 255, 2));
                    widget.PaintColor = Color.Red;
                    widget.MoveTo(widget.ScreenBounds);
                    JObject after = JObject.FromObject(FocusTrace.CaptureHudInput(center));
                    Assert.False((bool)after["lastCommit"]["Succeeded"]);
                    Assert.Equal("update_layered_window_failed", (string)after["lastCommit"]["ErrorValue"]);
                    Assert.Equal((long)before["submittedPaint"], (long)after["submittedPaint"]);
                    Assert.Equal(255, (int)after["paintedAlpha"]);
                    Assert.Equal(JTokenType.Null, after["submittedSourceAlpha"].Type);
                    Assert.Equal(HTCLIENT, SendNcHitTest(hud, center));
                }
            }
            finally { FocusTrace.Stop(); }
        }

        private static JObject[] ReadFocusRows(List<string> trace)
        {
            return trace.SelectMany(x => x.Split(new[] { Environment.NewLine }, StringSplitOptions.RemoveEmptyEntries))
                .Select(x => JObject.Parse(x.Substring("[FocusTrace] ".Length))).ToArray();
        }

        [Fact]
        public void BrokenDiagnosticSinkDoesNotChangeMouseActivationOrDispatch()
        {
            FocusTrace.Start(_ => throw new InvalidOperationException("fixture"), false);
            try
            {
                using (Form owner = CreateOwner())
                using (TestNativeHudOverlay hud = CreateHud(owner, out RecordingWidget widget))
                {
                    Point center = Center(widget.ScreenBounds);
                    Assert.Equal(3, SendMessage(hud.Handle, 0x0021, owner.Handle,
                        new IntPtr((WM_LBUTTONDOWN << 16) | HTCLIENT)).ToInt32());
                    Assert.Equal(HTCLIENT, SendNcHitTest(hud, center));
                    SendMouse(hud, WM_LBUTTONDOWN, center);
                    SendMouse(hud, WM_LBUTTONUP, center);
                    FocusTrace.Flush();
                    Assert.Equal(new[] { MouseEventKind.Down, MouseEventKind.Up, MouseEventKind.Click }, widget.Events);
                }
            }
            finally { FocusTrace.Stop(); }
        }

        [Fact]
        public void ReentrantOlderCommitCannotClaimCurrentSourcePixels()
        {
            FocusTrace.Start(_ => { }, false);
            try
            {
                using (Form owner = CreateOwner())
                using (TestNativeHudOverlay hud = CreateHud(owner, out RecordingWidget widget))
                {
                    long oldPaint = hud.FocusPaintGeneration;
                    long oldPlacement = hud.FocusPlacementGeneration;
                    widget.PaintColor = Color.Red;
                    widget.MoveTo(widget.ScreenBounds);
                    hud.ObserveFocusBitmapCommit(new LayeredWindowCommitResult(
                        true, hud.Left, hud.Top, hud.Width, hud.Height, 255, 0, 0,
                        LayeredWindowCommitError.None, 0, null, null), oldPaint, oldPlacement);
                    JObject evidence = JObject.FromObject(FocusTrace.CaptureHudInput(Center(widget.ScreenBounds)));
                    Assert.Equal(oldPaint, (long)evidence["submittedPaint"]);
                    Assert.True((long)evidence["paintGeneration"] > oldPaint);
                    Assert.Equal(255, (int)evidence["paintedAlpha"]);
                    Assert.Equal(JTokenType.Null, evidence["submittedSourceAlpha"].Type);
                }
            }
            finally { FocusTrace.Stop(); }
        }

        [Fact]
        public void RealHwnd_UpOutsideCancelsOriginalWidgetWithoutClick()
        {
            using (Form owner = CreateOwner())
            using (TestNativeHudOverlay hud = CreateHud(
                owner, out RecordingWidget widget))
            {
                Point center = Center(widget.ScreenBounds);
                Point padding = new Point(
                    widget.ScreenBounds.Right + 2,
                    widget.ScreenBounds.Top + 2);

                SendMouse(hud, WM_LBUTTONDOWN, center);
                SendMouse(hud, WM_LBUTTONUP, padding);

                Assert.Contains(MouseEventKind.Cancel, widget.Events);
                Assert.DoesNotContain(MouseEventKind.Click, widget.Events);
            }
        }

        [Fact]
        public void RealHwnd_ReturnDropdownSurvivesHoveredClickAndCaptureRelease()
        {
            using var owner = CreateOwner();
            owner.Show();
            Control anchor = owner.Controls["anchor"];
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, s => { });
            using var right = new RightContextWidget(anchor, router, catalog: null, mapDisplayPreference: MapDisplayPreference.Off);
            var intents = new List<string>();
            right.ReturnRequested += (run, revision, token, choice) => intents.Add(choice);
            right.ForceGameReady(true);
            right.SetReady();
            right.ApplyState(VictoryState(7, returnOptions: new JObject {
                ["status"] = "ready", ["token"] = "native.return.1", ["choices"] = new JArray {
                    new JObject { ["id"] = "task.1", ["taskName"] = "边界冲突", ["locationName"] = "联合大学", ["npcName"] = "Bat" },
                    new JObject { ["id"] = "task.2", ["taskName"] = "公社外交使节", ["locationName"] = "基地大厅", ["npcName"] = "幸存老兵" }
                }
            }));
            using var hud = new TestNativeHudOverlay(owner, anchor);
            hud.SessionForegroundForTest = true;
            hud.AddWidget(right);
            hud.SetReady();
            Point field = Center(right.ReturnFieldForTest);

            // 真实点击前必有鼠标移入。WinForms 在派发 MouseUp 后才释放 capture。
            SendMouse(hud, WM_MOUSEMOVE, field);
            SendMouse(hud, WM_LBUTTONDOWN, field);
            SendMouse(hud, WM_LBUTTONUP, field);
            Assert.False(hud.Capture);
            Assert.True(right.ReturnMenuOpenForTest, "Native mouse-up/capture release must not dismiss the newly opened dropdown.");
            Assert.Empty(intents);

            Rectangle menu = right.ReturnMenuForTest;
            Point secondRow = new Point(menu.Left + 12, menu.Top + 38 + 12);
            Assert.Equal(HTCLIENT, SendNcHitTest(hud, secondRow));
            SendMouse(hud, WM_MOUSEMOVE, secondRow);
            SendMouse(hud, WM_LBUTTONDOWN, secondRow);
            SendMouse(hud, WM_LBUTTONUP, secondRow);
            Assert.Equal("task.2", right.SelectedReturnIdForTest);
            Assert.False(right.ReturnMenuOpenForTest);
            Assert.Empty(intents);

            Point confirm = Center(right.StageActionBoundsForTest(0));
            SendMouse(hud, WM_MOUSEMOVE, confirm);
            SendMouse(hud, WM_LBUTTONDOWN, confirm);
            SendMouse(hud, WM_LBUTTONUP, confirm);
            Assert.Equal(new[] { "task.2" }, intents);
        }

        [Fact]
        public void RealHwnd_RightContextRevisionAndReorderCannotRetargetClick()
        {
            using (Form owner = CreateOwner())
            {
                owner.Show();
                Control anchor = owner.Controls["anchor"];
                var intents = new List<string>();
                LauncherCommandRouter router = new LauncherCommandRouter(
                    socketServer: null,
                    onSendKey: k => { },
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => { },
                    postToWeb: s => { });
                RightContextWidget right = new RightContextWidget(
                    anchor,
                    router,
                    catalog: null,
                    mapDisplayPreference: MapDisplayPreference.Off);
                right.IntentRequested += delegate(
                    string intent, string runId, int revision)
                {
                    intents.Add(intent + ":" + runId + ":" + revision);
                };
                right.ForceGameReady(true);
                right.SetReady();
                right.ApplyState(VictoryState(7));
                right.ForceDeliverState(
                    true, "base_dorm", false, "0", returnNavigable: true);

                using (TestNativeHudOverlay hud =
                    new TestNativeHudOverlay(owner, anchor))
                {
                    hud.SessionForegroundForTest = true;
                    hud.AddWidget(right);
                    hud.SetReady();

                    Point deliver = Center(right.StageActionBoundsForTest(0));
                    SendMouse(hud, WM_LBUTTONDOWN, deliver);
                    right.ApplyState(VictoryState(8));
                    SendMouse(hud, WM_LBUTTONUP, deliver);
                    Assert.Empty(intents);

                    deliver = Center(right.StageActionBoundsForTest(0));
                    SendMouse(hud, WM_LBUTTONDOWN, deliver);
                    right.ApplyState(VictoryState(8, canSelectReturn: false));
                    Point current = Center(right.StageActionBoundsForTest(0));
                    SendMouse(hud, WM_LBUTTONUP, current);
                    Assert.Empty(intents);

                    SendMouse(hud, WM_LBUTTONDOWN, current);
                    SendMouse(hud, WM_LBUTTONUP, current);
                    Assert.Equal(
                        new[] { "return_base:run.native-hud.input:8" },
                        intents);
                }
            }
        }

        [Fact]
        public void SuspendOwnerHideAndCaptureLossCancelPendingGesture()
        {
            using (Form owner = CreateOwner())
            using (TestNativeHudOverlay hud = CreateHud(
                owner, out RecordingWidget widget))
            {
                Point center = Center(widget.ScreenBounds);

                SendMouse(hud, WM_LBUTTONDOWN, center);
                hud.Suspend();
                Assert.Contains(MouseEventKind.Cancel, widget.Events);

                widget.Events.Clear();
                hud.Resume();
                SendMouse(hud, WM_LBUTTONDOWN, center);
                hud.SimulateOwnerHidden();
                Assert.Contains(MouseEventKind.Cancel, widget.Events);

                widget.Events.Clear();
                hud.SessionForegroundForTest = true;
                hud.Resume();
                SendMouse(hud, WM_LBUTTONDOWN, center);
                hud.Capture = true;
                hud.Capture = false;
                Assert.Contains(MouseEventKind.Cancel, widget.Events);
            }
        }

        [Fact]
        public void BoundsUpdateCannotReshowWhileOwnerAndSessionAreExternal()
        {
            using (Form owner = CreateOwner())
            using (TestNativeHudOverlay hud = CreateHud(
                owner, out RecordingWidget widget))
            {
                hud.SessionForegroundForTest = false;
                hud.SimulateOwnerHidden();
                Assert.False(IsWindowVisible(hud.Handle));

                Rectangle moved = widget.ScreenBounds;
                moved.Offset(12, 0);
                widget.MoveTo(moved);
                Assert.False(IsWindowVisible(hud.Handle));

                hud.SessionForegroundForTest = true;
                moved.Offset(12, 0);
                widget.MoveTo(moved);
                Assert.True(IsWindowVisible(hud.Handle));
            }
        }

        [Fact]
        public void RealHwnd_NotchDragFromOtherButtonToQDoesNotForceExit()
        {
            using (Form owner = CreateOwner())
            {
                owner.Show();
                Control anchor = owner.Controls["anchor"];
                int exits = 0;
                NotchWidget notch = new NotchWidget(
                    anchor,
                    new FpsRingBuffer(300),
                    "",
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => exits++,
                    onSendKey: k => { });
                notch.ForceGameReadyForTest(true);
                notch.BeginExpandForTest();
                notch.Tick(1000);
                notch.OpenOtherMenuForTest(0);
                Rectangle notchBounds = notch.ScreenBounds;
                using (Bitmap bitmap = new Bitmap(
                    Math.Max(1, notchBounds.Width),
                    Math.Max(1, notchBounds.Height)))
                using (Graphics graphics = Graphics.FromImage(bitmap))
                    notch.Paint(graphics, 1f, notchBounds.Location);

                using (TestNativeHudOverlay hud =
                    new TestNativeHudOverlay(owner, anchor))
                {
                    hud.SessionForegroundForTest = true;
                    hud.AddWidget(notch);
                    hud.SetReady();
                    Rectangle qBounds = notch.ButtonScreenBoundsForTest("Q");
                    Assert.False(qBounds.IsEmpty);
                    Point neighborButton = new Point(
                        qBounds.Left + qBounds.Width / 2,
                        qBounds.Bottom + 1 + qBounds.Height / 2);
                    Assert.Equal(HTCLIENT, SendNcHitTest(hud, neighborButton));

                    SendMouse(hud, WM_LBUTTONDOWN, neighborButton);
                    SendMouse(hud, WM_LBUTTONUP, Center(qBounds));
                    Assert.Equal(0, exits);

                    SendMouse(hud, WM_LBUTTONDOWN, Center(qBounds));
                    SendMouse(hud, WM_LBUTTONUP, Center(qBounds));
                    Assert.Equal(1, exits);
                }
            }
        }

        [Fact]
        public void RealHwnd_MapCardAndCloseButtonCannotRetargetEachOther()
        {
            using (Form owner = CreateOwner())
            using (PanelHostController host = new PanelHostController(
                pump => pump(), fire => fire()))
            {
                owner.Show();
                Control anchor = owner.Controls["anchor"];
                LauncherCommandRouter router = new LauncherCommandRouter(
                    socketServer: null,
                    onSendKey: k => { },
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => { },
                    postToWeb: s => { });
                router.SetPanelHost(host);
                MapHudWidget map = new MapHudWidget(
                    anchor, router, MapCatalog());
                map.ForceGameReady(true);
                map.ForceMode("1");
                map.ForceHotspot("warlord_base");

                using (TestNativeHudOverlay hud =
                    new TestNativeHudOverlay(owner, anchor))
                {
                    hud.SessionForegroundForTest = true;
                    hud.AddWidget(map);
                    hud.SetReady();
                    Rectangle card = map.ScreenBounds;
                    Rectangle close = map.CloseButtonScreenBoundsForTest;
                    Assert.False(card.IsEmpty);
                    Assert.False(close.IsEmpty);
                    Point body = new Point(card.Left + 10, card.Bottom - 10);

                    SendMouse(hud, WM_LBUTTONDOWN, body);
                    SendMouse(hud, WM_LBUTTONUP, Center(close));
                    Assert.False(map.IsCollapsed);
                    Assert.False(host.IsPanelOpen);

                    SendMouse(hud, WM_LBUTTONDOWN, Center(close));
                    SendMouse(hud, WM_LBUTTONUP, body);
                    Assert.False(map.IsCollapsed);
                    Assert.False(host.IsPanelOpen);
                }
            }
        }

        private static Form CreateOwner()
        {
            Form owner = new Form();
            owner.StartPosition = FormStartPosition.Manual;
            owner.Bounds = new Rectangle(100, 80, 1024, 576);
            Panel anchor = new Panel();
            anchor.Name = "anchor";
            anchor.Bounds = new Rectangle(0, 0, 1024, 576);
            owner.Controls.Add(anchor);
            owner.CreateControl();
            anchor.CreateControl();
            return owner;
        }

        private static TestNativeHudOverlay CreateHud(
            Form owner,
            out RecordingWidget widget)
        {
            Control anchor = owner.Controls["anchor"];
            widget = new RecordingWidget(new Rectangle(300, 220, 80, 40));
            TestNativeHudOverlay hud = new TestNativeHudOverlay(owner, anchor);
            hud.SessionForegroundForTest = true;
            hud.AddWidget(widget);
            hud.SetReady();
            return hud;
        }

        private static Point Center(Rectangle bounds)
        {
            return new Point(
                bounds.Left + bounds.Width / 2,
                bounds.Top + bounds.Height / 2);
        }

        private static StageOutcomeState VictoryState(int revision, bool canSelectReturn = true, JObject returnOptions = null)
        {
            JObject message = new JObject
            {
                ["task"] = "stage_outcome",
                ["payload"] = new JObject
                {
                    ["v"] = returnOptions == null ? 3 : 4,
                    ["runId"] = "run.native-hud.input",
                    ["revision"] = revision,
                    ["stageName"] = "测试关卡",
                    ["difficulty"] = "普通",
                    ["outcome"] = "victory",
                    ["life"] = "alive",
                    ["activeFrames"] = 30,
                    ["reviveCoins"] = 0,
                    ["reviveAllowed"] = false,
                    ["reviveBlockedReason"] = "",
                    ["canReturnBase"] = true,
                    ["canSelectReturn"] = canSelectReturn,
                    ["returnFailure"] = "",
                    ["settlement"] = "none",
                    ["remainingRewards"] = 0
                }
            };
            if (returnOptions != null) message["payload"]["returnOptions"] = returnOptions;
            StageOutcomeState state;
            string error;
            Assert.True(StageOutcomeState.TryParseMessage(
                message, out state, out error), error);
            return state;
        }

        private static MapHudDataCatalog MapCatalog()
        {
            MapHudPayload payload = new MapHudPayload
            {
                ProtocolVersion = 1,
                Hotspots = new Dictionary<string, MapHudHotspotEntry>()
            };
            payload.Hotspots["warlord_base"] = new MapHudHotspotEntry
            {
                Meta = new MapHudMeta
                {
                    PageId = "faction",
                    PageLabel = "A兵团",
                    HotspotId = "warlord_base",
                    Label = "军阀基地",
                    Group = "warlord"
                },
                Outline = new MapHudOutline
                {
                    ViewportRect = new RectF { X = 0, Y = 0, W = 200, H = 100 },
                    CurrentRect = new RectF { X = 20, Y = 20, W = 40, H = 30 },
                    Blocks = new List<MapHudBlock>
                    {
                        new MapHudBlock
                        {
                            HotspotId = "warlord_base",
                            Label = "军阀基地",
                            SourceRect = new RectF
                                { X = 20, Y = 20, W = 40, H = 30 }
                        }
                    }
                }
            };
            return MapHudDataCatalog.FromPayload(payload);
        }

        private static int SendNcHitTest(
            TestNativeHudOverlay hud,
            Point screenPoint)
        {
            return SendMessage(
                hud.Handle,
                WM_NCHITTEST,
                IntPtr.Zero,
                PackPoint(screenPoint.X, screenPoint.Y)).ToInt32();
        }

        private static void SendMouse(
            TestNativeHudOverlay hud,
            int message,
            Point screenPoint)
        {
            Point client = hud.PointToClient(screenPoint);
            SendMessage(
                hud.Handle,
                message,
                message == WM_LBUTTONDOWN
                    ? new IntPtr(MK_LBUTTON) : IntPtr.Zero,
                PackPoint(client.X, client.Y));
        }

        private static IntPtr PackPoint(int x, int y)
        {
            long packed = (ushort)(short)x
                | ((long)(ushort)(short)y << 16);
            return new IntPtr(packed);
        }
    }
}
