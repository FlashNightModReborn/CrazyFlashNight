using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class BootstrapRevealCurtainTests
    {
        [Fact]
        public void CurtainColor_MatchesWebHandoffObsidian()
        {
            Assert.Equal(Color.FromArgb(6, 9, 12), BootstrapRevealCurtain.CurtainColor);
        }

        [Fact]
        public void ComputeFadeAlpha_HoldsOpaqueThenEasesOutMonotonicallyToZero()
        {
            const int holdMs = BootstrapRevealCurtain.DefaultHoldMs;
            const int fadeMs = BootstrapRevealCurtain.DefaultFadeMs;

            Assert.Equal((byte)255, BootstrapRevealCurtain.ComputeFadeAlpha(-10, holdMs, fadeMs));
            Assert.Equal((byte)255, BootstrapRevealCurtain.ComputeFadeAlpha(0, holdMs, fadeMs));
            Assert.Equal((byte)255, BootstrapRevealCurtain.ComputeFadeAlpha(holdMs, holdMs, fadeMs));

            byte prev = 255;
            for (int ms = holdMs + 10; ms < holdMs + fadeMs; ms += 15)
            {
                byte cur = BootstrapRevealCurtain.ComputeFadeAlpha(ms, holdMs, fadeMs);
                Assert.True(cur <= prev, $"Alpha must decrease monotonically: {cur} > {prev} at {ms}ms");
                prev = cur;
            }

            // Quadratic ease-out at midpoint: (1 - 0.5)^2 = 0.25 -> ~64
            byte mid = BootstrapRevealCurtain.ComputeFadeAlpha(holdMs + fadeMs * 0.5, holdMs, fadeMs);
            Assert.InRange(mid, (byte)60, (byte)68);

            Assert.Equal((byte)0, BootstrapRevealCurtain.ComputeFadeAlpha(holdMs + fadeMs, holdMs, fadeMs));
            Assert.Equal((byte)0, BootstrapRevealCurtain.ComputeFadeAlpha(holdMs + fadeMs + 500, holdMs, fadeMs));
            Assert.Equal((byte)0, BootstrapRevealCurtain.ComputeFadeAlpha(10, 0, 0));
            Assert.Equal((byte)255, BootstrapRevealCurtain.ComputeFadeAlpha(0, -20, 100));
        }

        [Fact]
        public void TryCover_FailsClosedForNullHiddenOrUncreatedControls()
        {
            Assert.Null(BootstrapRevealCurtain.TryCover(null, null));

            using var owner = new Form();
            using var anchor = new Panel();
            owner.Controls.Add(anchor);

            Assert.Null(BootstrapRevealCurtain.TryCover(owner, null));
            Assert.Null(BootstrapRevealCurtain.TryCover(null, anchor));

            // Uncreated handles and hidden owner must no-op without spawning a window.
            Assert.Null(BootstrapRevealCurtain.TryCover(owner, anchor));

            owner.Dispose();
            Assert.Null(BootstrapRevealCurtain.TryCover(owner, anchor));
        }
    }
}
