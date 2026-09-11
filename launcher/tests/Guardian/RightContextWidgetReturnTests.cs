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
        private static JObject ReturnChoices(string status = "ready", int count = 2, string token = "return.options.1")
        {
            var rows = new JArray();
            for (int i = 0; i < count; i++) rows.Add(new JObject {
                ["id"] = "task." + (i + 1), ["locationName"] = i == 0 ? "联合大学" : "基地1层",
                ["npcName"] = i == 0 ? "Bat" : i == 1 ? "Andy Law" : "Shop Girl",
                ["taskName"] = i == 0 ? "边界冲突" : i == 1 ? "新手试炼" : "军火商Shop Girl"
            });
            return new JObject { ["status"] = status, ["token"] = token, ["choices"] = rows };
        }

        private static void ReturnClick(RightContextWidget widget, Rectangle rect)
        {
            Assert.True(rect.Width > 0 && rect.Height > 0);
            var args = new MouseEventArgs(MouseButtons.Left, 1, rect.Left + rect.Width / 2, rect.Top + rect.Height / 2, 0);
            Assert.True(widget.TryHitTest(new Point(args.X, args.Y)));
            widget.OnMouseEvent(args, MouseEventKind.Down);
            widget.OnMouseEvent(args, MouseEventKind.Up);
            widget.OnMouseEvent(args, MouseEventKind.Click);
        }

        [Fact]
        public void InlineReturnUsesNativeSelectionAndOneBoundConfirmation()
        {
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            var anchor = new Panel { Bounds = new Rectangle(0, 0, 1024, 576) };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            var web = new List<string>();
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, postToWeb: web.Add);
            using var widget = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Off,
                npcPortraitDirectory: Path.GetFullPath(Path.Combine(FindIconsDir(), "..", "..", "..", "flashswf", "portraits", "profiles")));
            var commands = new List<JObject>();
            using var bridge = new StageOutcomeTask(raw => { commands.Add(JObject.Parse(raw.TrimEnd('\0'))); return true; }, widget);
            widget.ForceGameReady(true); widget.SetReady();
            widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices()));
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
            Assert.Equal("task.1", widget.SelectedReturnIdForTest);
            Assert.Equal(new[] { "完成结算", "返回原处" }, widget.StageActionLabelsForTest);
            Assert.True(widget.StageActionLabelFitsForTest(0));
            Assert.True(widget.StageActionLabelFitsForTest(1));
            Assert.Empty(commands);

            ReturnClick(widget, widget.ReturnFieldForTest);
            Rectangle menu = widget.ReturnMenuForTest;
            Assert.True(widget.ReturnMenuOpenForTest);
            Assert.True(widget.ScreenBounds.Contains(menu));
            Assert.True(widget.CompositeBounds.Contains(menu));
            ReturnClick(widget, new Rectangle(menu.Left, menu.Top + 38, menu.Width, 38));
            Assert.Equal("task.2", widget.SelectedReturnIdForTest);
            Assert.False(widget.ReturnMenuOpenForTest);
            Assert.Empty(commands);
            Assert.Empty(web);

            widget.ApplyState(StageState("victory", "alive", "none", revision: 8, canSelectReturn: true, returnOptions: ReturnChoices(token: "return.options.2")));
            Assert.Equal("task.2", widget.SelectedReturnIdForTest);
            ReturnClick(widget, widget.StageActionBoundsForTest(0));
            var command = Assert.Single(commands);
            Assert.Equal(3, (int)command["v"]);
            Assert.Equal("confirm_return", (string)command["intent"]);
            Assert.Equal("task.2", (string)command["choiceId"]);
            Assert.Equal("return.options.2", (string)command["choicesToken"]);
            Assert.Equal(8, (int)command["expectedRevision"]);
            Assert.Equal("run.right-context.1", (string)command["runId"]);
            Assert.Empty(web);
        }

        [Fact]
        public void InlineReturnRefreshOfSameOptionsKeepsOpenPageButInvalidatesOldPress()
        {
            using var owner = new Form { ClientSize = new Size(1024, 576) };
            var anchor = new Panel { Bounds = new Rectangle(0, 0, 1024, 576) };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, s => { });
            using var widget = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Off);
            widget.ForceGameReady(true); widget.SetReady();
            widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices(count: 7)));
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
            ReturnClick(widget, widget.ReturnFieldForTest);
            Rectangle menu = widget.ReturnMenuForTest;
            ReturnClick(widget, new Rectangle(menu.Left + menu.Width * 2 / 3, menu.Bottom - 24, menu.Width / 3, 24));
            menu = widget.ReturnMenuForTest;
            var args = new MouseEventArgs(MouseButtons.Left, 1, menu.Left + 12, menu.Top + 12, 0);
            widget.OnMouseEvent(args, MouseEventKind.Down);
            widget.ApplyState(StageState("victory", "alive", "none", revision: 8, canSelectReturn: true, returnOptions: ReturnChoices(count: 7)));
            Assert.True(widget.ReturnMenuOpenForTest);
            Assert.Equal(menu, widget.ReturnMenuForTest);
            widget.OnMouseEvent(args, MouseEventKind.Click);
            Assert.Equal("task.1", widget.SelectedReturnIdForTest);
            ReturnClick(widget, new Rectangle(menu.Left, menu.Top, menu.Width, 38));
            Assert.Equal("task.6", widget.SelectedReturnIdForTest);
            ReturnClick(widget, widget.ReturnFieldForTest);
            widget.ApplyState(StageState("victory", "alive", "none", revision: 9, canSelectReturn: true, returnOptions: ReturnChoices(count: 2, token: "new.options")));
            Assert.False(widget.ReturnMenuOpenForTest);
            Assert.Equal("task.1", widget.SelectedReturnIdForTest);
        }

        [Fact]
        public void InlineReturnNoTasksKeepsOnlyExistingReturnAndBusyCannotDispatch()
        {
            using var widget = MakeWidget(out var capture);
            widget.SetReady();
            widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices(count: 0)));
            Assert.Equal(new[] { "返回原处" }, widget.StageActionLabelsForTest);
            Assert.Null(widget.SelectedReturnIdForTest);
            Assert.False(widget.ReturnMenuOpenForTest);
            var selected = new List<string>();
            widget.ReturnRequested += (run, rev, token, choice) => selected.Add(choice);
            widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices("confirming")));
            Assert.False(widget.StageActionEnabledForTest(0));
            Assert.False(widget.StageActionEnabledForTest(1));
            widget.ClickStageActionForTest(0);
            Assert.Empty(selected);
            widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices("error", 0)));
            Assert.Equal(new[] { "刷新交付", "返回原处" }, widget.StageActionLabelsForTest);
            Assert.True(widget.StageActionEnabledForTest(1));
        }

        [Theory]
        [InlineData(1024, 576)]
        [InlineData(1600, 900)]
        [InlineData(800, 450)]
        public void InlineReturnMenuPagesAndOldGestureCannotPickNewRows(int width, int height)
        {
            using var owner = new Form { ClientSize = new Size(width, height) };
            var anchor = new Panel { Bounds = new Rectangle(0, 0, width, height) };
            owner.Controls.Add(anchor); owner.CreateControl(); anchor.CreateControl();
            var router = new LauncherCommandRouter(null, k => { }, () => { }, () => { }, () => { }, s => { });
            using var widget = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(BuildPayload()), MapDisplayPreference.Off,
                npcPortraitDirectory: Path.GetFullPath(Path.Combine(FindIconsDir(), "..", "..", "..", "flashswf", "portraits", "profiles")));
            widget.ForceGameReady(true); widget.SetReady();
            widget.ApplyState(StageState("victory", "alive", "none", canSelectReturn: true, returnOptions: ReturnChoices(count: 7)));
            NativeHudOverlay.ResolveAndProjectRightContextSlotOwner(widget, null);
            ReturnClick(widget, widget.ReturnFieldForTest);
            Rectangle menu = widget.ReturnMenuForTest;
            float scale = height / 576f;
            ReturnClick(widget, new Rectangle(menu.Left + menu.Width * 2 / 3, menu.Bottom - (int)(24 * scale), menu.Width / 3, (int)(24 * scale)));
            menu = widget.ReturnMenuForTest;
            var args = new MouseEventArgs(MouseButtons.Left, 1, menu.Left + 10, menu.Top + 10, 0);
            widget.OnMouseEvent(args, MouseEventKind.Down);
            widget.ApplyState(StageState("victory", "alive", "none", revision: 8, canSelectReturn: true, returnOptions: ReturnChoices(count: 3, token: "return.options.new")));
            widget.OnMouseEvent(args, MouseEventKind.Click);
            Assert.Equal("task.1", widget.SelectedReturnIdForTest);
            ReturnClick(widget, widget.ReturnFieldForTest);
            string artifactDir = Environment.GetEnvironmentVariable("CF7_RETURN_PREVIEW_DIR");
            if (!string.IsNullOrEmpty(artifactDir))
            {
                Directory.CreateDirectory(artifactDir);
                Rectangle bounds = widget.CompositeBounds;
                using var bitmap = new Bitmap(bounds.Width, bounds.Height);
                using var graphics = Graphics.FromImage(bitmap);
                graphics.Clear(Color.FromArgb(25, 26, 31));
                widget.Paint(graphics, 1, bounds.Location);
                bitmap.Save(Path.Combine(artifactDir, "return-dropdown-" + width + ".png"), ImageFormat.Png);
            }
            widget.OnMouseEvent(args, MouseEventKind.Cancel);
            Assert.False(widget.ReturnMenuOpenForTest);
        }
    }
}
