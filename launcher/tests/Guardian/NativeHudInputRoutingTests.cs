using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativeHudInputRoutingTests
    {
        private const int WM_NCHITTEST = 0x0084;
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

            public void Paint(Graphics g, float dpr, Point hudOrigin) { }
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
                    right.ForceDeliverState(
                        false, "", false, "0", returnNavigable: true);
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

        private static StageOutcomeState VictoryState(int revision)
        {
            JObject message = new JObject
            {
                ["task"] = "stage_outcome",
                ["payload"] = new JObject
                {
                    ["v"] = 1,
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
                    ["settlement"] = "none",
                    ["remainingRewards"] = 0
                }
            };
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
