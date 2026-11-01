using System.Windows.Forms;
using CF7Launcher.Guardian;
using Xunit;

namespace Launcher.Tests.Guardian
{
    public sealed class ModifierSurfaceTests
    {
        [Fact]
        public void ModifierUsesCompactCompositionSurfaceNotANormalPanel()
        {
            using var owner = new Form();
            using var surface = new CompositionHelpSurface(owner, "owned", "owned",
                CompositionPanelProfile.Modifier);
            Assert.Equal("modifier", surface.PanelName);
            Assert.True(CompositionPanelProfile.Modifier.AcceptsPanelRequests);
            Assert.True(CompositionPanelProfile.Modifier.AcceptsPanelResponses);
            Assert.True(CompositionPanelProfile.Modifier.AllowNativeDrag);
            Assert.False(CompositionPanelProfile.Modifier.AllowTutorialPreference);
        }
    }
}
