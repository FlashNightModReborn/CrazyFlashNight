using System;
using System.Drawing;
using System.IO;
using System.Reflection;
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
