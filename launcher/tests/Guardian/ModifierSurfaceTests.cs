using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
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
        }

        [Fact]
        public void PortraitManifestResolvesAcceptedUnitPortrait()
        {
            string webRoot = Path.Combine(Directory.GetCurrentDirectory(), "launcher", "web");
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
