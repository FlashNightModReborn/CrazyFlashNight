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

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

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

        [Fact]
        public void UnitAndItemTabsRenderPageJumpHintBesideStatus()
        {
            Assert.Equal("输入页码数字后按回车键跳转", ModifierNativeSurface.PageJumpHintForTab("units"));
            Assert.Equal("输入页码数字后按回车键跳转", ModifierNativeSurface.PageJumpHintForTab("items"));
            Assert.Null(ModifierNativeSurface.PageJumpHintForTab("economy"));
            Assert.Null(ModifierNativeSurface.PageJumpHintForTab("level"));

            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            string webRoot = Path.Combine(repository.FullName, "launcher", "web");

            using var owner = new Form();
            using var task = new ModifierTask(() => true, _ => true);
            using var surface = new ModifierNativeSurface(owner, webRoot, "owned", task);
            surface.PrepareAsync().GetAwaiter().GetResult();
            surface.ClientSize = new Size(1016, 550);
            Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));

            bool HasSoftGoldPixels(Bitmap bitmap, Rectangle logicalRect)
            {
                Rectangle rect = ModifierNativeLayout.ToClient(logicalRect, surface.ClientSize);
                int left = Math.Max(0, rect.Left);
                int top = Math.Max(0, rect.Top);
                int right = Math.Min(bitmap.Width, rect.Right);
                int bottom = Math.Min(bitmap.Height, rect.Bottom);
                for (int y = top; y < bottom; y++)
                    for (int x = left; x < right; x++)
                    {
                        Color px = bitmap.GetPixel(x, y);
                        if (px.A > 120 && px.R >= 160 && px.G >= 140 && px.B >= 80
                            && px.R > px.G && px.G > px.B && (px.R - px.B) >= 35)
                            return true;
                    }
                return false;
            }

            using (var econ = surface.RenderFrame())
            {
                Assert.False(HasSoftGoldPixels(econ, new Rectangle(296, 403, 356, 20)));
            }

            MethodInfo setTab = typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic);
            MethodInfo setStatus = typeof(ModifierNativeSurface).GetMethod("SetStatus", BindingFlags.Instance | BindingFlags.NonPublic);
            MethodInfo applyUnits = typeof(ModifierNativeSurface).GetMethod("ApplyUnits", BindingFlags.Instance | BindingFlags.NonPublic);
            MethodInfo applyItems = typeof(ModifierNativeSurface).GetMethod("ApplyItems", BindingFlags.Instance | BindingFlags.NonPublic);

            setTab.Invoke(surface, new object[] { "units" });
            setStatus.Invoke(surface, new object[] { "正在读取兵种目录…", "pending" });
            applyUnits.Invoke(surface, new object[] { new JObject
            {
                ["success"] = true, ["page"] = 1, ["pageSize"] = 8, ["total"] = 32, ["revision"] = 1,
                ["units"] = new JArray(new JObject
                {
                    ["id"] = 1, ["name"] = "测试兵种", ["spriteName"] = "", ["key"] = "",
                    ["level"] = 1, ["hostile"] = false
                })
            } });
            using (var unitsFrame = surface.RenderFrame())
            {
                SaveModifierFrame(unitsFrame, "modifier-units-hint.png");
                Assert.True(HasSoftGoldPixels(unitsFrame, new Rectangle(296, 403, 356, 20)));
                Assert.False(HasSoftGoldPixels(unitsFrame, new Rectangle(656, 403, 120, 20)));
            }

            setTab.Invoke(surface, new object[] { "items" });
            setStatus.Invoke(surface, new object[] { "正在读取物品目录…", "pending" });
            applyItems.Invoke(surface, new object[] { new JObject
            {
                ["success"] = true, ["page"] = 1, ["pageSize"] = 64, ["total"] = 64, ["revision"] = 1,
                ["items"] = new JArray(new JObject
                {
                    ["id"] = 1, ["name"] = "测试物品", ["displayName"] = "测试物品",
                    ["icon"] = "", ["type"] = "", ["use"] = ""
                })
            } });
            using (var itemsFrame = surface.RenderFrame())
            {
                SaveModifierFrame(itemsFrame, "modifier-items-hint.png");
                Assert.True(HasSoftGoldPixels(itemsFrame, new Rectangle(296, 403, 356, 20)));
                Assert.False(HasSoftGoldPixels(itemsFrame, new Rectangle(656, 403, 120, 20)));
            }
        }

        [Fact]
        public void SearchInputShowsPlaceholderOnlyWhenEmptyAndNotComposing()
        {
            DirectoryInfo repository = new DirectoryInfo(AppContext.BaseDirectory);
            while (repository != null && !File.Exists(Path.Combine(
                repository.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                repository = repository.Parent;
            Assert.NotNull(repository);
            string webRoot = Path.Combine(repository.FullName, "launcher", "web");

            var sentFrames = new System.Collections.Generic.List<string>();
            using var owner = new Form();
            using var task = new ModifierTask(() => true, text => { sentFrames.Add(text); return true; });
            using var surface = new ModifierNativeSurface(owner, webRoot, "owned", task);
            surface.PrepareAsync().GetAwaiter().GetResult();
            surface.ClientSize = new Size(1016, 550);
            Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));
            Assert.True(surface.TryPost(new JObject
            {
                ["type"] = "panel_cmd",
                ["panel"] = "modifier",
                ["cmd"] = "open",
                ["initData"] = new JObject
                {
                    ["panelInstanceId"] = "mod.panel.placeholder",
                    ["token"] = "modifier.placeholder.1"
                }
            }.ToString()));
            typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, new object[] { "items" });

            var query = (ModifierTextBox)typeof(ModifierNativeSurface).GetField(
                "_itemQuery", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            Assert.Equal("输入物品名", ModifierNativeSurface.SearchPlaceholder);
            Assert.Equal("输入物品名", query.HintText);
            Assert.Equal("", query.Text);
            Assert.True(query.IsShowingHint);

            query.Text = "药剂";
            Assert.False(query.IsShowingHint);
            query.Text = "";
            Assert.True(query.IsShowingHint);

            IntPtr handle = query.Handle;
            Assert.NotEqual(IntPtr.Zero, handle);
            SendMessage(handle, 0x010D, IntPtr.Zero, IntPtr.Zero);
            Assert.Equal("", query.Text);
            Assert.False(query.IsShowingHint);

            SendMessage(handle, 0x010E, IntPtr.Zero, IntPtr.Zero);
            Assert.True(query.IsShowingHint);

            sentFrames.Clear();
            typeof(ModifierNativeSurface).GetField("_itemLoading", BindingFlags.Instance | BindingFlags.NonPublic)
                .SetValue(surface, false);
            typeof(ModifierNativeSurface).GetMethod("SearchItems", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(surface, null);
            Assert.Single(sentFrames);
            JObject payload = JObject.Parse(sentFrames[0].TrimEnd('\0'));
            Assert.Equal("modifierItems", payload.Value<string>("action"));
            Assert.Equal("", payload.Value<string>("query"));
            surface.SuspendPanel();
        }

        [Fact]
        public void AllModifierInputsRenderCrispWhiteOuterBordersWithoutOverlap()
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
            surface.PrepareAsync().GetAwaiter().GetResult();
            surface.ClientSize = new Size(1016, 550);
            Assert.True(surface.ResumePanel(new Rectangle(-32000, -32000, 1016, 550)));

            var overlay = (ModifierInputOverlay)typeof(ModifierNativeSurface).GetField(
                "_inputOverlay", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
            string[] fieldNames = { "_itemQuery", "_itemQuantity", "_itemPageInput", "_taskId", "_unitLevel", "_unitCount", "_unitPageInput" };
            var allInputs = new ModifierTextBox[fieldNames.Length];
            for (int i = 0; i < fieldNames.Length; i++)
            {
                var input = (ModifierTextBox)typeof(ModifierNativeSurface).GetField(
                    fieldNames[i], BindingFlags.Instance | BindingFlags.NonPublic).GetValue(surface);
                allInputs[i] = input;
                Assert.Equal(BorderStyle.None, input.BorderStyle);
                Assert.True(overlay.TryGetInputFrame(input, out Rectangle frame), $"Missing frame for {fieldNames[i]}");
                Assert.True(frame.Width >= 4 && frame.Height >= 4);
                Assert.True(input.Left >= frame.Left + 1 && input.Right <= frame.Right - 1,
                    $"{fieldNames[i]} X outside white border: input={input.Bounds} frame={frame}");
                Assert.True(input.Top >= frame.Top + 1 && input.Bottom <= frame.Bottom - 1,
                    $"{fieldNames[i]} Y outside white border: input={input.Bounds} frame={frame}");
            }

            static void AssertWhiteBorder(Bitmap bitmap, Rectangle frame, string label)
            {
                int midX = frame.X + frame.Width / 2;
                int midY = frame.Y + frame.Height / 2;
                Color top = bitmap.GetPixel(midX, frame.Top);
                Color bottom = bitmap.GetPixel(midX, frame.Bottom - 1);
                Color left = bitmap.GetPixel(frame.Left, midY);
                Color right = bitmap.GetPixel(frame.Right - 1, midY);
                Assert.True(top.A == 255 && top.R == 255 && top.G == 255 && top.B == 255, $"{label} top={top}");
                Assert.True(bottom.A == 255 && bottom.R == 255 && bottom.G == 255 && bottom.B == 255, $"{label} bottom={bottom}");
                Assert.True(left.A == 255 && left.R == 255 && left.G == 255 && left.B == 255, $"{label} left={left}");
                Assert.True(right.A == 255 && right.R == 255 && right.G == 255 && right.B == 255, $"{label} right={right}");
            }

            static Bitmap RenderOverlayBitmap(ModifierInputOverlay target, Size size)
            {
                var bitmap = new Bitmap(size.Width, size.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
                using (var graphics = Graphics.FromImage(bitmap))
                {
                    graphics.Clear(Color.Black);
                    target.PaintInputFrames(graphics);
                }
                return bitmap;
            }

            MethodInfo setTab = typeof(ModifierNativeSurface).GetMethod("SetTab", BindingFlags.Instance | BindingFlags.NonPublic);
            MethodInfo applyItems = typeof(ModifierNativeSurface).GetMethod("ApplyItems", BindingFlags.Instance | BindingFlags.NonPublic);
            MethodInfo applyUnits = typeof(ModifierNativeSurface).GetMethod("ApplyUnits", BindingFlags.Instance | BindingFlags.NonPublic);

            setTab.Invoke(surface, new object[] { "items" });
            applyItems.Invoke(surface, new object[] { new JObject
            {
                ["success"] = true, ["page"] = 1, ["pageSize"] = 64, ["total"] = 1, ["revision"] = 1,
                ["items"] = new JArray(new JObject
                {
                    ["id"] = 1, ["name"] = "普通hp药剂", ["displayName"] = "普通HP药剂",
                    ["icon"] = "", ["type"] = "", ["use"] = ""
                })
            } });
            using (var itemsSurface = surface.RenderFrame())
            using (var itemsOverlay = RenderOverlayBitmap(overlay, surface.ClientSize))
            {
                SaveModifierFrame(itemsSurface, "modifier-items-inputs.png");
                for (int i = 0; i < 3; i++)
                {
                    Assert.True(overlay.TryGetInputFrame(allInputs[i], out Rectangle frame));
                    AssertWhiteBorder(itemsSurface, frame, "surface:" + fieldNames[i]);
                    AssertWhiteBorder(itemsOverlay, frame, "overlay:" + fieldNames[i]);
                }
                Assert.True(overlay.TryGetInputFrame(allInputs[0], out Rectangle queryFrame));
                bool hasHintPixels = false;
                for (int y = queryFrame.Top + 2; y < queryFrame.Bottom - 2 && !hasHintPixels; y++)
                    for (int x = queryFrame.Left + 2; x < queryFrame.Right - 2; x++)
                    {
                        Color px = itemsSurface.GetPixel(x, y);
                        if (px.A > 120 && px.R >= 80 && px.G >= 80 && px.B >= 80) { hasHintPixels = true; break; }
                    }
                Assert.True(hasHintPixels, "Expected placeholder text pixels inside search box");
            }

            setTab.Invoke(surface, new object[] { "level" });
            using (var levelSurface = surface.RenderFrame())
            using (var levelOverlay = RenderOverlayBitmap(overlay, surface.ClientSize))
            {
                SaveModifierFrame(levelSurface, "modifier-level-inputs.png");
                Assert.True(overlay.TryGetInputFrame(allInputs[3], out Rectangle taskFrame));
                AssertWhiteBorder(levelSurface, taskFrame, "surface:_taskId");
                AssertWhiteBorder(levelOverlay, taskFrame, "overlay:_taskId");
            }

            setTab.Invoke(surface, new object[] { "units" });
            applyUnits.Invoke(surface, new object[] { new JObject
            {
                ["success"] = true, ["page"] = 1, ["pageSize"] = 8, ["total"] = 1, ["revision"] = 1,
                ["units"] = new JArray(new JObject
                {
                    ["id"] = 1, ["name"] = "测试兵种", ["spriteName"] = "", ["key"] = "",
                    ["level"] = 1, ["hostile"] = false
                })
            } });
            using (var unitsSurface = surface.RenderFrame())
            using (var unitsOverlay = RenderOverlayBitmap(overlay, surface.ClientSize))
            {
                SaveModifierFrame(unitsSurface, "modifier-units-inputs.png");
                for (int i = 4; i < 7; i++)
                {
                    Assert.True(overlay.TryGetInputFrame(allInputs[i], out Rectangle frame));
                    AssertWhiteBorder(unitsSurface, frame, "surface:" + fieldNames[i]);
                    AssertWhiteBorder(unitsOverlay, frame, "overlay:" + fieldNames[i]);
                }
            }
            surface.SuspendPanel();
        }
    }
}
