using System.Collections.Generic;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class MapHudPrewarmTests
    {
        [Fact]
        public void ProcessPrewarmWorkset_StopsAfterGenerationChanges()
        {
            LatestWorkGeneration gate = new LatestWorkGeneration();
            int generation = gate.Advance();
            List<string> processed = new List<string>();

            int count = gate.Process(
                new[] { "old-a.webp", "old-b.webp", "old-c.webp" },
                generation,
                delegate(string assetUrl)
                {
                    processed.Add(assetUrl);
                    gate.Advance();
                });

            Assert.Equal(1, count);
            Assert.Equal(new[] { "old-a.webp" }, processed);
        }

        [Fact]
        public void ProcessPrewarmWorkset_DoesNotStartAlreadyStaleGeneration()
        {
            LatestWorkGeneration gate = new LatestWorkGeneration();
            int staleGeneration = gate.Advance();
            gate.Advance();

            int count = gate.Process(
                new[] { "stale.webp" },
                staleGeneration,
                delegate(string assetUrl) { Assert.Fail("stale workset must not run"); });

            Assert.Equal(0, count);
        }
    }
}
