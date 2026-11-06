using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Tests.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// 上层 HUD 生产绘制器的分区合成夹具（ADR D4/D5）：同屏放置 Buff、聚焦目标、刘海+信息行、Combo、
    /// 右侧动作行+状态槽、fallback 消息与事件卡，断言分区互不相交。
    /// 设置 CF7_HUD_ANCHOR_REVIEW_DIR 时输出 PNG（可选 CF7_HUD_ANCHOR_BG 指定底图），仅供布局与绘制复核，
    /// 不代表实机观感验收。
    /// </summary>
    public sealed class HudAnchorCompositeTests : IDisposable
    {
        public HudAnchorCompositeTests() { HudZoneLayout.ResetForTests(); }
        public void Dispose() { HudZoneLayout.ResetForTests(); }

        [Theory]
        [InlineData(1024, 576, 5, 1, false)]
        [InlineData(1024, 576, 23, 4, false)]
        [InlineData(1600, 900, 23, 4, false)]
        [InlineData(1920, 1080, 45, 4, false)]
        [InlineData(1024, 576, 256, 4, true)]
        [InlineData(1600, 900, 23, 4, true)]
        [InlineData(1920, 1080, 45, 4, true)]
        [InlineData(1024, 768, 23, 4, true)]
        [InlineData(1920, 800, 23, 4, true)]
        [InlineData(2560, 1440, 256, 4, true)]
        public void ProductionUpperHudZonesDoNotOverlap(int width, int height, int buffs, int targets, bool expanded) => Sta(() =>
        {
            string root = Root();
            RuntimeFontCatalog.Configure(root);
            using var form = new Form { ClientSize = new Size(width, height), AutoScaleMode = AutoScaleMode.None };
            using var anchor = new Panel { Dock = DockStyle.Fill }; form.Controls.Add(anchor); form.CreateControl(); anchor.CreateControl();
            var origin = anchor.PointToScreen(Point.Empty);

            using var controller = new PlayerHudController(_ => true, () => true, action => action());
            controller.TakeUiData("pi:" + PlayerHudStateTests.Encode(Packet(buffs, targets)));
            using var buffWidget = new PlayerHudBuffWidget(anchor, controller);
            using var focus = new PlayerHudFocusTargetWidget(anchor, controller);

            var router = new LauncherCommandRouter(null, _ => { }, () => { }, () => { }, () => { }, _ => { });
            var right = new RightContextWidget(anchor, router, MapHudDataCatalog.FromPayload(new MapHudPayload { ProtocolVersion = 1, Hotspots = new() }));
            right.ForceGameReady(true);
            right.SetReady();
            right.OnLegacyUiData("announce", new[] { "任务已达成 · 战后交付" });
            right.Tick(50);

            var fps = new FpsRingBuffer(600); fps.Push(24);
            using var notch = new NotchWidget(anchor, fps, root, () => { }, () => { }, () => { }, _ => { }, preparationNavigationV1: true);
            notch.ForceGameReadyForTest(true); notch.ForceCurrenciesForTest(1745260, 1847503);
            notch.SetStatusItem("wave", "波次 1/1 · 歼灭模式", "残敌 13", NativeHudTheme.Cyan);
            if (expanded)
            {
                notch.SetStatusItem("fixture_2", "关卡状态", "长文本边界", Color.White);
                notch.SetStatusItem("fixture_3", "任务状态", "夹具", Color.White);
                notch.SetStatusItem("fixture_4", "系统状态", "夹具", Color.White);
                notch.BeginExpandForTest();
            }
            notch.Tick(500);

            using var combo = new ComboWidget(anchor);
            combo.ForceGameReady(true);
            combo.OnLegacyUiData("combo", new[] { "", "→↓↘", "波动拳:→↓↘A:1" });
            if (expanded) combo.OnNotchNotice("combo", "DFA 波动拳", Color.Gold);

            using var icons = new LootIconCatalog(Path.Combine(root, "launcher", "web", "icons"));
            using var loot = new LootFeedWidget(anchor, icons);
            loot.AddEvent("material", "传动装置", 1, "fixture", "", direction: "gain");
            loot.AddEvent("material", "基因液", 12, "fixture", "", direction: "gain");
            for (int n = 0; n < 4; n++) loot.AddEvent("material", "压力物资" + n, 1, "fixture", "", direction: "gain");
            for (int i = 0; i < 5; i++) { Application.DoEvents(); loot.Tick(200); }

            using var toast = new ToastWidget(anchor);
            toast.SetReady();
            toast.AddMessage("被<font color='#FFCC00'>合金机甲</font>：宇喵关燕");
            toast.AddMessage("通讯终端已连接");
            toast.AddMessage("<font color='#FF6666'>药剂冷却中，无法使用</font>");
            for (int n = 0; n < 5; n++) toast.AddMessage("压力消息 " + n);
            toast.Tick(300); // 越过 200ms 行级淡入

            Rectangle Rel(Rectangle r) { if (r.IsEmpty) return r; r.Offset(-origin.X, -origin.Y); return r; }
            var buffR = Rel(buffWidget.ScreenBounds);
            var focusR = Rel(focus.ScreenBounds);
            var toastR = Rel(toast.ScreenBounds);
            var lootR = Rel(loot.ScreenBounds);
            var notchR = Rel(notch.ScreenBounds);
            var comboR = Rel(combo.ScreenBounds);
            var rightR = Rel(right.ScreenBounds);

            if (buffs > 40) Assert.True(toastR.IsEmpty, "满载状态列与待显示行优先，fallback 无空间时整体隐藏");
            else Assert.False(toastR.IsEmpty, "fallback messages must have room in the event column");
            Assert.False(toastR.IntersectsWith(buffR), $"toast {toastR} vs buff {buffR}");
            Assert.False(toastR.IntersectsWith(focusR), $"toast {toastR} vs focus {focusR}");
            Assert.False(toastR.IntersectsWith(lootR), $"toast {toastR} vs loot {lootR}");
            Assert.False(focusR.IntersectsWith(lootR), $"focus {focusR} vs loot {lootR}");
            Assert.False(comboR.IsEmpty, "combo fixture should be visible");
            Assert.True(comboR.Top >= notchR.Bottom, $"combo {comboR} must sit below notch rows {notchR}");
            Assert.False(comboR.IntersectsWith(rightR), $"combo {comboR} vs right {rightR}");
            Assert.False(comboR.IntersectsWith(focusR) || comboR.IntersectsWith(buffR), $"combo {comboR} vs TL column");

            var output = Environment.GetEnvironmentVariable("CF7_HUD_ANCHOR_REVIEW_DIR");
            if (string.IsNullOrEmpty(output)) return;
            using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(bitmap))
            {
                var bg = Environment.GetEnvironmentVariable("CF7_HUD_ANCHOR_BG");
                if (!string.IsNullOrEmpty(bg) && File.Exists(bg))
                {
                    using var image = Image.FromFile(bg);
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    var viewport = RightHudLayout.ViewportFromPanelSize(width, height);
                    g.Clear(Color.Black);
                    g.DrawImage(image, viewport);
                }
                else
                {
                    using var fill = new LinearGradientBrush(new Rectangle(0, 0, width, height),
                        Color.FromArgb(255, 92, 84, 70), Color.FromArgb(255, 38, 34, 30), LinearGradientMode.Vertical);
                    g.FillRectangle(fill, 0, 0, width, height);
                }
                buffWidget.Paint(g, 1, origin);
                focus.Paint(g, 1, origin);
                right.Paint(g, 1, origin);
                combo.Paint(g, 1, origin);
                loot.Paint(g, 1, origin);
                toast.Paint(g, 1, origin);
                notch.Paint(g, 1, origin); // 与 Program 注册顺序一致：刘海在 Combo 之后。
            }
            Directory.CreateDirectory(output);
            bitmap.Save(Path.Combine(output, $"hud-anchor-{width}x{height}-b{buffs}-t{targets}-{(expanded ? "expanded" : "collapsed")}.png"), ImageFormat.Png);
        });

        private static JObject Packet(int buffs, int targets)
        {
            var packet = PlayerHudStateTests.Full(1, 1);
            string[] names = { "腕刃", "铁布衫", "霸体", "兴奋剂", "蛛网", "状态", "力量", "护盾", "中毒", "疾速" };
            packet["groups"]["buffs"] = new JArray(Enumerable.Range(0, buffs).Select(i =>
            {
                bool timed = i % 3 != 0;
                return new JObject
                {
                    ["id"] = "b" + i.ToString("000"), ["timed"] = timed,
                    ["total"] = timed ? 900 : 0, ["remaining"] = timed ? (i % 4 == 1 ? 60 : 900 - i * 37 % 800) : 0,
                    ["info"] = new JObject
                    {
                        ["name"] = names[i % names.Length], ["description"] = "夹具状态",
                        ["polarity"] = i % 5 == 4 ? "harm" : (i % 7 == 5 ? "neutral" : "benefit"),
                        ["stacks"] = i % 6 == 3 ? 3 : 0
                    }
                };
            }));
            string[] roles = { "protect", "boss", "combat", "combat" };
            var list = new JArray(Enumerable.Range(0, targets).Select(i => new JObject
            {
                ["id"] = 100 + i, ["role"] = targets == 1 ? "boss" : roles[i],
                ["name"] = targets == 1 ? "尸母" : (i == 0 ? "补给车" : i == 1 ? "尸母" : "基因虫"),
                ["hp"] = new JArray(i == 2 ? 3214 : 50589, i == 2 ? 9800 : 51057)
            }));
            packet["groups"]["focusTarget"] = targets == 1 ? list[0] : list;
            return packet;
        }

        private static string Root()
        {
            var current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null && !Directory.Exists(Path.Combine(current.FullName, "data", "items"))) current = current.Parent;
            return current?.FullName ?? throw new DirectoryNotFoundException("Repository root");
        }

        private static void Sta(Action body)
        {
            Exception error = null;
            var thread = new Thread(() => { try { body(); } catch (Exception e) { error = e; } });
            thread.SetApartmentState(ApartmentState.STA); thread.Start(); Assert.True(thread.Join(30000));
            if (error != null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
        }
    }
}
