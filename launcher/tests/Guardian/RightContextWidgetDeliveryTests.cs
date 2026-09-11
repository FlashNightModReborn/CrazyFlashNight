using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public partial class RightContextWidgetTests
    {
        private static JObject DeliveryState(string scope = "daily.scope.1", string status = "ready", string token = "delivery.1") =>
            new JObject { ["task"] = "task_delivery", ["payload"] = new JObject {
                ["v"] = 1, ["scope"] = scope, ["options"] = ReturnChoices(status, token: token) } };

        [Theory]
        [InlineData(1024, 576)]
        [InlineData(1600, 900)]
        public void DailyDeliveryUsesSharedMenuAndExplicitTaskWithoutOpeningWeb(int width, int height)
        {
            using var owner = new Form { ClientSize = new Size(width, height) };
            var anchor = new Panel { Bounds = new Rectangle(0, 0, width, height) };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            var web = new List<string>(); var commands = new List<JObject>();
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, postToWeb: web.Add);
            using var widget = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Off,
                npcPortraitDirectory: Path.GetFullPath(Path.Combine(FindIconsDir(), "..", "..", "..", "flashswf", "portraits", "profiles")));
            using var task = new TaskTask(() => true, raw => commands.Add(JObject.Parse(raw.TrimEnd('\0'))));
            task.SetDeliveryPresenter(widget);
            widget.ForceGameReady(true); widget.ForceDeliverState(true, "base", true, "0");
            task.HandleDeliveryState(DeliveryState());
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
            Assert.Equal("task.1", widget.SelectedReturnIdForTest);
            ReturnClick(widget, widget.ReturnFieldForTest);
            widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, 0, 0, 0), MouseEventKind.Leave);
            Assert.True(widget.ReturnMenuOpenForTest);
            var menu = widget.ReturnMenuForTest;
            float scale = width / 1024f;
            string preview = Environment.GetEnvironmentVariable("CF7_RETURN_PREVIEW_DIR");
            if (!string.IsNullOrEmpty(preview))
            {
                Directory.CreateDirectory(preview);
                Rectangle bounds = widget.CompositeBounds;
                using var bitmap = new Bitmap(bounds.Width, bounds.Height); using var g = Graphics.FromImage(bitmap);
                g.Clear(Color.FromArgb(42, 42, 42)); widget.Paint(g, 1, bounds.Location);
                bitmap.Save(Path.Combine(preview, "daily-delivery-" + width + ".png"), ImageFormat.Png);
            }
            ReturnClick(widget, new Rectangle(menu.Left, menu.Top + (int)(38 * scale), menu.Width, (int)(38 * scale)));
            Assert.Equal("task.2", widget.SelectedReturnIdForTest);
            Assert.Empty(commands); Assert.Empty(web);
            // 同区域新事实保持手动选择；前往使用最新 token 和选择的任务 ID。
            task.HandleDeliveryState(DeliveryState(token: "delivery.2"));
            ReturnClick(widget, widget.DailyDeliveryActionForTest);
            var command = Assert.Single(commands);
            Assert.Equal("taskDeliveryAction", (string)command["action"]);
            Assert.Equal("navigate", (string)command["intent"]);
            Assert.Equal(1, (int)command["v"]);
            Assert.Equal("delivery.2", (string)command["choicesToken"]);
            Assert.Equal("task.2", (string)command["choiceId"]);
            Assert.Empty(web);
            task.HandleDeliveryState(DeliveryState(scope: "daily.scope.2", token: "delivery.3"));
            Assert.Equal("task.1", widget.SelectedReturnIdForTest);
            if (!string.IsNullOrEmpty(preview))
            {
                // 使用实际绘制器并排核对日常/结算的收起栏，供人工视觉复核。
                Rectangle dailyBounds = widget.CompositeBounds;
                Rectangle dailyField = widget.ReturnFieldForTest;
                using var bitmap = new Bitmap(dailyBounds.Width, dailyBounds.Height * 2 + (int)(16 * scale));
                using var g = Graphics.FromImage(bitmap);
                g.Clear(Color.FromArgb(25, 26, 31)); widget.Paint(g, 1, dailyBounds.Location);
                var longDailyState = DeliveryState(scope: "daily.preview.long");
                longDailyState["payload"]["options"]["choices"][0]["locationName"] = "联合大学周边巡逻任务交付地点";
                task.HandleDeliveryState(longDailyState);
                using (var dailyLongBitmap = new Bitmap(dailyBounds.Width, dailyBounds.Height))
                using (var dailyLongGraphics = Graphics.FromImage(dailyLongBitmap))
                {
                    dailyLongGraphics.Clear(Color.FromArgb(25, 26, 31));
                    widget.Paint(dailyLongGraphics, 1, dailyBounds.Location);
                    dailyLongBitmap.Save(Path.Combine(preview, "daily-long-location-" + width + ".png"), ImageFormat.Png);
                }
                widget.SetReady();
                widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices()));
                NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
                Rectangle stageBounds = widget.CompositeBounds;
                g.TranslateTransform(0, dailyBounds.Height + (int)(16 * scale));
                widget.Paint(g, 1, stageBounds.Location);
                bitmap.Save(Path.Combine(preview, "delivery-and-return-" + width + ".png"), ImageFormat.Png);
                File.WriteAllText(Path.Combine(preview, "selector-layout-" + width + ".txt"),
                    "daily=" + dailyField + Environment.NewLine + "return=" + widget.ReturnFieldForTest);

                var longNames = ReturnChoices();
                longNames["choices"][0]["taskName"] = "联合大学周边的紧急巡逻委托";
                longNames["choices"][0]["locationName"] = "联合大学大门";
                widget.ApplyState(StageState("victory", "alive", "none", revision: 9,
                    canSelectReturn: true, returnOptions: longNames));
                Rectangle longBounds = widget.CompositeBounds;
                using var longBitmap = new Bitmap(longBounds.Width, longBounds.Height);
                using var longGraphics = Graphics.FromImage(longBitmap);
                longGraphics.Clear(Color.FromArgb(25, 26, 31));
                widget.Paint(longGraphics, 1, longBounds.Location);
                longBitmap.Save(Path.Combine(preview, "long-destination-" + width + ".png"), ImageFormat.Png);
            }
        }

        [Theory]
        [InlineData(1024, 576)]
        [InlineData(1600, 900)]
        [InlineData(1600, 1000)]
        public void DeliveryHeightChangeKeepsMapAndMenuHitRegionsAligned(int width, int height)
        {
            using var owner = new Form { ClientSize = new Size(width, height) };
            var anchor = new Panel { Bounds = new Rectangle(0, 0, width, height) };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            _ = owner.Handle; _ = anchor.Handle;
            var web = new List<string>(); var commands = new List<JObject>();
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, postToWeb: web.Add);
            using var host = new PanelHostController(pump => pump(), fire => fire());
            router.SetPanelHost(host);
            using var widget = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Compact);
            using var task = new TaskTask(() => true, raw => commands.Add(JObject.Parse(raw.TrimEnd('\0'))));
            task.SetDeliveryPresenter(widget);
            widget.ForceGameReady(true); widget.ForceDeliverState(true, "base_dorm", true, "1");
            widget.ForceMapHotspot("base_dorm");
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
            Rectangle compactBounds = widget.ScreenBounds;
            task.HandleDeliveryState(DeliveryState());
            Rectangle deliveryBounds = widget.ScreenBounds;
            Assert.True(deliveryBounds.Bottom > compactBounds.Bottom,
                "ordinary=" + compactBounds + " delivery=" + deliveryBounds);
            Assert.Equal(compactBounds.Top, deliveryBounds.Top);
            Assert.Equal(compactBounds.Width, deliveryBounds.Width);
            Assert.False(widget.ReturnFieldForTest.IntersectsWith(widget.DailyDeliveryActionForTest));

            // 选择栏新增的下缘必须仍归选择器；弹层覆盖地图时先命中任务行。
            Rectangle field = widget.ReturnFieldForTest;
            ReturnClick(widget, new Rectangle(field.Left + 2, field.Bottom - 3, field.Width - 4, 2));
            Assert.True(widget.ReturnMenuOpenForTest);
            Rectangle menu = widget.ReturnMenuForTest;
            ReturnClick(widget, new Rectangle(menu.Left + 2, menu.Top + menu.Height / 2, menu.Width - 4, 2));
            Assert.Equal("task.2", widget.SelectedReturnIdForTest);
            Assert.False(widget.ReturnMenuOpenForTest);
            Assert.Empty(commands); Assert.Empty(web);
            Assert.Null(host.ActivePanelName);

            ReturnClick(widget, new Rectangle(deliveryBounds.Left + 4, deliveryBounds.Bottom - 4, deliveryBounds.Width - 8, 2));
            Assert.Equal("map", host.ActivePanelName);
            Assert.True(host.TryClosePanelExact(host.ActivePanelName, host.ActivePanelInstanceId, null));
            task.SetDeliveryPresenter(null);
            widget.ResetDeliveryState();
            Assert.Equal(compactBounds, widget.ScreenBounds);
            Assert.False(widget.TryHitTest(new Point(deliveryBounds.Left + 10, deliveryBounds.Bottom - 2)));
            ReturnClick(widget, new Rectangle(compactBounds.Left + 4, compactBounds.Bottom - 4, compactBounds.Width - 8, 2));
            Assert.Equal("map", host.ActivePanelName);
        }

        [Fact]
        public void DailyDeliveryRefreshAndBusyStateCannotReusePressOrOpenTaskWeb()
        {
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            var anchor = new Panel { Bounds = new Rectangle(0, 0, 1024, 576) };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            var web = new List<string>(); var commands = new List<JObject>();
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, postToWeb: web.Add);
            using var widget = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Off);
            using var task = new TaskTask(() => true, raw => commands.Add(JObject.Parse(raw.TrimEnd('\0'))));
            task.SetDeliveryPresenter(widget);
            widget.ForceGameReady(true); widget.ForceDeliverState(true, "base", true, "0");
            task.HandleDeliveryState(DeliveryState());
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
            ReturnClick(widget, widget.ReturnFieldForTest);
            task.HandleDeliveryState(DeliveryState());
            Assert.True(widget.ReturnMenuOpenForTest);
            var rect = widget.DailyDeliveryActionForTest;
            var args = new MouseEventArgs(MouseButtons.Left, 1, rect.Left + 10, rect.Top + 10, 0);
            widget.OnMouseEvent(args, MouseEventKind.Down);
            task.HandleDeliveryState(DeliveryState(token: "delivery.2"));
            widget.OnMouseEvent(args, MouseEventKind.Up); widget.OnMouseEvent(args, MouseEventKind.Click);
            Assert.Empty(commands);
            task.HandleDeliveryState(DeliveryState(status: "confirming", token: "delivery.2"));
            Assert.False(widget.TryHitTest(new Point(args.X, args.Y)));
            widget.OnMouseEvent(args, MouseEventKind.Down); widget.OnMouseEvent(args, MouseEventKind.Click);
            Assert.Empty(commands); Assert.Empty(web);
        }

        [Fact]
        public void DailyFactsDoNotTakeOwnershipFromVictoryReturnMenu()
        {
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            var anchor = new Panel { Bounds = new Rectangle(0, 0, 1024, 576) };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, s => { });
            using var widget = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Off);
            using var task = new TaskTask(() => true, s => { }); task.SetDeliveryPresenter(widget);
            widget.ForceGameReady(true); widget.SetReady();
            widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices()));
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
            ReturnClick(widget, widget.ReturnFieldForTest);
            var menu = widget.ReturnMenuForTest;
            task.HandleDeliveryState(DeliveryState());
            Assert.True(widget.ReturnMenuOpenForTest); Assert.Equal(menu, widget.ReturnMenuForTest);
            Assert.Equal(new[] { "完成结算", "返回原处" }, widget.StageActionLabelsForTest);
        }

        [Theory]
        [InlineData("extra")]
        [InlineData("version")]
        [InlineData("scope")]
        [InlineData("duplicate")]
        [InlineData("status")]
        [InlineData("envelope")]
        public void DailyMalformedStateClearsSelectionWithoutLegacyHotspotFallback(string malformed)
        {
            using var widget = MakeWidget(out var capture);
            using var task = new TaskTask(() => true, s => { }); task.SetDeliveryPresenter(widget);
            widget.ForceDeliverState(true, "base", true, "0");
            task.HandleDeliveryState(DeliveryState());
            var message = DeliveryState(); var payload = (JObject)message["payload"];
            switch (malformed)
            {
                case "extra": payload["extra"] = true; break;
                case "version": payload["v"] = 2; break;
                case "scope": payload["scope"] = ""; break;
                case "duplicate": payload["options"]["choices"][1]["id"] = "task.1"; break;
                case "status": payload["options"]["status"] = "loading"; break;
                case "envelope": message["task"] = new JObject(); break;
            }
            task.HandleDeliveryState(message);
            Assert.Null(widget.SelectedReturnIdForTest);
            Assert.Equal(RightContextWidget.ClickRoute.TaskUi, widget.ResolveNoticeClickRoute());
        }

        [Fact]
        public void DailyDeliveryProjectionIsSocketOnly()
        {
            string status = CF7Launcher.Bus.TaskRegistry.ToStatusJson(false, 0, 0);
            Assert.Contains("task_delivery", status);
            Assert.False(CF7Launcher.Bus.TaskRegistry.IsHttpCallable("task_delivery"));
        }
    }
}
