using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Guardian
{
    public sealed class ModifierSurfaceTests
    {
        [Fact]
        public void ModifierUsesNativeSurfaceWithoutWebView()
        {
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, "owned", "owned", task);
            Assert.Equal("modifier", surface.PanelName);
            Assert.False(surface.Active);
            surface.PrepareAsync().GetAwaiter().GetResult();
            Assert.True(surface.Ready);
            Assert.NotNull(typeof(ModifierNativeSurface).GetField(
                "_tooltip", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(surface));
        }

        [Fact]
        public void ItemIconsUseTheSharedAnimatedTimeline()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            using var icons = new LootIconCatalog(Path.Combine(repository.FullName, "launcher", "web", "icons"));
            var description = icons.DescribeForPlayback("金钱", true);
            Assert.NotNull(description);
            Assert.True(description.Animated);
            Assert.NotEqual(description.Sample(0, true), description.Sample(TimeSpan.TicksPerSecond, true));
            byte[] Draw(int content)
            {
                using var bitmap = new Bitmap(64, 64);
                using (var graphics = Graphics.FromImage(bitmap))
                    Assert.True(icons.TryDrawPlayback(graphics, new Rectangle(0, 0, 64, 64), description, content, 1f));
                using var stream = new MemoryStream();
                bitmap.Save(stream, System.Drawing.Imaging.ImageFormat.Png);
                return stream.ToArray();
            }
            Assert.NotEqual(Draw(description.Sample(0, true)),
                Draw(description.Sample(TimeSpan.TicksPerSecond / 2, true)));
        }

        [Fact]
        public void ItemCellsDoNotPaintSyntheticQuantity()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner,
                Path.Combine(repository.FullName, "launcher", "web"), "owned", task);
            surface.ClientSize = new Size(1016, 550);
            Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));
            typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { "items" });
            typeof(ModifierNativeSurface).GetMethod("ApplyItems", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { new JObject
                {
                    ["success"] = true, ["page"] = 1, ["pageSize"] = 64, ["total"] = 1, ["revision"] = 1,
                    ["items"] = new JArray(new JObject
                    {
                        ["id"] = 1, ["name"] = "测试物品", ["displayName"] = "测试物品",
                        ["icon"] = "", ["type"] = "", ["use"] = ""
                    })
                } });
            using var frame = surface.RenderFrame();
            SaveModifierFrame(frame, "modifier-items.png");
            Rectangle cell = ModifierNativeLayout.ToClient(ModifierNativeLayout.ItemCell(0), surface.ClientSize);
            for (int y = Math.Max(0, cell.Bottom - 12); y < Math.Min(frame.Height, cell.Bottom); y++)
                for (int x = Math.Max(0, cell.Right - 12); x < Math.Min(frame.Width, cell.Right); x++)
                {
                    Color pixel = frame.GetPixel(x, y);
                    Assert.False(pixel.A > 0 && pixel.R > 200 && pixel.G > 150 && pixel.B < 80,
                        $"Unexpected yellow quantity at {x},{y}: {pixel}");
                }
        }

        [Fact]
        public void UnitPageDoesNotPaintOverJumpButton()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner,
                Path.Combine(repository.FullName, "launcher", "web"), "owned", task);
            surface.ClientSize = new Size(1016, 550);
            Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));
            typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { "units" });
            typeof(ModifierNativeSurface).GetMethod("ApplyUnits", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { new JObject
                {
                    ["success"] = true, ["page"] = 1, ["pageSize"] = 8, ["total"] = 32, ["revision"] = 1,
                    ["units"] = new JArray(new JObject
                    {
                        ["id"] = 1, ["name"] = "测试兵种", ["spriteName"] = "", ["key"] = "",
                        ["level"] = 1, ["hostile"] = false
                    })
                } });
            using var frame = surface.RenderFrame();
            SaveModifierFrame(frame, "modifier-units.png");
            Rectangle boundary = ModifierNativeLayout.ToClient(new Rectangle(
                ModifierNativeLayout.UnitJump.Left - 8, ModifierNativeLayout.UnitPageTotal.Top,
                8, ModifierNativeLayout.UnitPageTotal.Height), surface.ClientSize);
            for (int y = Math.Max(0, boundary.Top); y < Math.Min(frame.Height, boundary.Bottom); y++)
                for (int x = Math.Max(0, boundary.Left); x < Math.Min(frame.Width, boundary.Right); x++)
                {
                    Color pixel = frame.GetPixel(x, y);
                    Assert.False(pixel.A > 0 && pixel.R > 200 && pixel.G > 150 && pixel.B < 80,
                        $"Unexpected page text over jump button at {x},{y}: {pixel}");
                }
        }

        [Fact]
        public void UnitJumpButtonUsesTheTypedPage()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner,
                Path.Combine(repository.FullName, "launcher", "web"), "owned", task);
            surface.ClientSize = new Size(1016, 550);
            Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));
            typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { "units" });
            typeof(ModifierNativeSurface).GetMethod("ApplyUnits", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { new JObject
                {
                    ["success"] = true, ["page"] = 1, ["pageSize"] = 8, ["total"] = 32, ["revision"] = 1,
                    ["units"] = new JArray()
                } });
            var input = (TextBox)typeof(ModifierNativeSurface).GetField(
                "_unitPageInput", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            input.Text = "2";
            Point center = new Point(ModifierNativeLayout.UnitJump.X + ModifierNativeLayout.UnitJump.Width / 2,
                ModifierNativeLayout.UnitJump.Y + ModifierNativeLayout.UnitJump.Height / 2);
            string hit = (string)typeof(ModifierNativeSurface).GetMethod("HitAction",
                BindingFlags.Instance | BindingFlags.NonPublic).Invoke(surface, new object[] { center });
            Assert.Equal("unit_jump", hit);
            typeof(ModifierNativeSurface).GetMethod("ExecuteAction", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { hit });
            Assert.Equal(2, typeof(ModifierNativeSurface).GetField(
                "_unitPage", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface));
        }

        private static void SaveModifierFrame(Image frame, string name)
        {
            string root = Environment.GetEnvironmentVariable("CF7_EVIDENCE_ROOT");
            if (string.IsNullOrWhiteSpace(root)) return;
            Directory.CreateDirectory(root);
            frame.Save(Path.Combine(root, name), System.Drawing.Imaging.ImageFormat.Png);
        }

        [Fact]
        public void TooltipKeepsModifierScaleAndResolvesNpcPortraits()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner,
                Path.Combine(repository.FullName, "launcher", "web"), "owned", task);
            surface.ClientSize = new Size(1016, 550);
            object tooltip = typeof(ModifierNativeSurface).GetField(
                "_tooltip", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            float scale = (float)tooltip.GetType().GetMethod("CurrentScale",
                BindingFlags.Instance | BindingFlags.NonPublic).Invoke(tooltip, null);
            Assert.InRange(scale, 1.19f, 1.21f);
            object catalog = typeof(ModifierNativeSurface).GetField(
                "_iconCatalog", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            object[] arguments = { "Boy", null };
            bool loaded = (bool)catalog.GetType().GetMethod("TryGetNpc",
                BindingFlags.Instance | BindingFlags.NonPublic).Invoke(catalog, arguments);
            Assert.True(loaded);
            Assert.NotNull(arguments[1]);
        }

        [Fact]
        public void LayeredSurfaceCommitsAlphaAndKeepsTooltipAboveInputs()
        {
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, "owned", "owned", task);
            surface.PrepareAsync().GetAwaiter().GetResult();
            var observer = new CommitObserver();
            surface.SetCommitObserver(observer);
            Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));
            surface.Invalidate();
            Assert.NotNull(observer.Last);
            Assert.True(observer.Last.Succeeded);
            Assert.Equal(1016, observer.Last.Width);
            Assert.Equal(550, observer.Last.Height);

            typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { "items" });
            var inputs = (Form)typeof(ModifierNativeSurface).GetField(
                "_inputOverlay", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            Assert.True(inputs.Visible);
            Assert.Equal(24, ModifierNativeLayout.ItemQuery.Height);
            Assert.Equal(24, ModifierNativeLayout.ItemQuantity.Height);
            Assert.Equal(24, ModifierNativeLayout.TaskId.Height);
            Assert.Equal(22, ModifierNativeLayout.UnitLevel.Height);
            Assert.Equal(22, ModifierNativeLayout.UnitCount.Height);

            var tooltip = (NativeTooltipWidget)typeof(ModifierNativeSurface).GetField(
                "_tooltip", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            Assert.True(tooltip.Show(new JObject
            {
                ["version"] = 1, ["requestId"] = "modifier.layering.test",
                ["document"] = new JObject
                {
                    ["version"] = 1, ["title"] = "层级测试", ["profile"] = "dense",
                    ["sections"] = new JArray()
                }
            }));
            surface.Invalidate();
            Assert.True(tooltip.Visible);
            Assert.False(inputs.Visible);
            tooltip.Reset();
            surface.Invalidate();
            Assert.True(inputs.Visible);
            surface.SuspendPanel();
        }

        [Fact]
        public void OwnerAndInputFocusTransitionsRemainInsideModifier()
        {
            using var owner = new Form();
            using var unrelated = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, "owned", "owned", task);
            var inputs = (Form)typeof(ModifierNativeSurface).GetField(
                "_inputOverlay", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            Assert.True(surface.OwnsFocus(surface.Handle));
            Assert.True(surface.OwnsFocus(inputs.Handle));
            Assert.True(surface.OwnsFocus(owner.Handle));
            Assert.False(surface.OwnsFocus(unrelated.Handle));
        }

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        private static void ExpectForeground(IntPtr handle, bool activate)
        {
            for (int i = 0; i < 20; i++)
            {
                if (activate) SetForegroundWindow(handle);
                Application.DoEvents();
                if (GetForegroundWindow() == handle) return;
                Thread.Sleep(10);
                activate = false;
            }
            Assert.Equal(handle, GetForegroundWindow());
        }

        [Fact]
        public void ModifierMouseWorkflowPreservesGameKeyboardFocus()
        {
            using var owner = new Form { StartPosition = FormStartPosition.Manual };
            owner.Location = new Point(-32000, -32000);
            owner.Show();
            owner.Activate();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, "owned", "owned", task);
            try
            {
                ExpectForeground(owner.Handle, true);
                Assert.True((bool)typeof(ModifierNativeSurface).GetProperty("ShowWithoutActivation",
                    BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface));
                Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));
                ExpectForeground(owner.Handle, false);

                typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic)
                    .Invoke(surface, new object[] { "items" });
                bool? textInputActive = null;
                surface.TextInputFocusChanged += active => textInputActive = active;
                var input = (TextBox)typeof(ModifierNativeSurface).GetField(
                    "_itemQuery", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
                Assert.True(input.Focus());
                Application.DoEvents();
                Assert.True(textInputActive);

                typeof(ModifierNativeSurface).GetMethod("OnMouseDown",
                    BindingFlags.Instance | BindingFlags.NonPublic).Invoke(surface,
                    new object[] { new MouseEventArgs(MouseButtons.Left, 1, 10, 10, 0) });
                Application.DoEvents();
                Assert.False(textInputActive);
                ExpectForeground(owner.Handle, false);
            }
            finally { surface.SuspendPanel(); }
        }

        private sealed class CommitObserver : ILayeredWindowCommitObserver
        {
            internal LayeredWindowCommitResult Last;
            public void OnCommit(LayeredWindowCommitResult result) { Last = result; }
        }

        [Fact]
        public void PortraitManifestResolvesAcceptedUnitPortrait()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            string webRoot = Path.Combine(repository.FullName, "launcher", "web");
            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, webRoot, "owned", task);
            MethodInfo method = typeof(ModifierNativeSurface).GetMethod(
                "TryLoadPortrait", BindingFlags.Instance | BindingFlags.NonPublic);
            object[] arguments = { "敌人-终结者T800", null };
            bool loaded = (bool)method.Invoke(surface, arguments);
            using var image = arguments[1] as Image;
            Assert.True(loaded);
            Assert.NotNull(image);
            Assert.True(image.Width > 0);
            Assert.True(image.Height > 0);
        }
    }
}
