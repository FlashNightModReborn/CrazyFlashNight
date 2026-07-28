using System;
using System.IO;
using System.Linq;
using System.Text;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Hud.PlayerInfo
{
    public sealed class PlayerInfoSvgProductionTests
    {
        [Fact]
        public void EmbeddedClosure_LoadsExactEightAssetsAndMinimumRasterizes()
        {
            PlayerInfoSvgAssetSet assetSet =
                PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: true);

            Assert.Equal("player-info-hp-mp-b0", assetSet.AssetSetId);
            Assert.Equal(
                "sha256:c8f58cb781f50c5a62eff163a04524e89fd6a2ee37c9b66347743d766ac93871",
                assetSet.Revision);
            Assert.Equal(
                "1006f90e3c1aa5435226c092019f46a3cd6358b0ece2804e42c85052de235630",
                assetSet.ExactManifestSha256);
            Assert.Equal("cf7-player-info-static-svg-v1", assetSet.FeatureSet);
            Assert.Equal(1, assetSet.RasterContractVersion);
            Assert.Equal(8, assetSet.Assets.Count);
            Assert.Equal(99_564, assetSet.Assets.Sum(asset => asset.Bytes.Length));
            Assert.Equal(
                assetSet.Assets.Count,
                assetSet.Assets.Select(asset => asset.Id).Distinct(StringComparer.Ordinal).Count());
        }

        [Fact]
        public void Core_EmbedsOnlyManifestAndEightSvgResources()
        {
            string[] allResources = typeof(PlayerInfoSvgAssetContract).Assembly
                .GetManifestResourceNames();
            string[] resources = allResources
                .Where(name => name.StartsWith(
                    PlayerInfoSvgAssetCatalog.ResourcePrefix + ".",
                    StringComparison.Ordinal))
                .OrderBy(name => name, StringComparer.Ordinal)
                .ToArray();

            Assert.Equal(9, resources.Length);
            Assert.Contains(PlayerInfoSvgAssetCatalog.ManifestResourceName, resources);
            Assert.Equal(8, resources.Count(name => name.EndsWith(".svg", StringComparison.Ordinal)));
            Assert.DoesNotContain(allResources, name =>
                name.Contains("evidence", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("provenance", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("oracle", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("fixture", StringComparison.OrdinalIgnoreCase));
        }

        [Fact]
        public void RepoOnlyFixture_WithDifferentLogicalName_IsRejected()
        {
            const string aliasedFixture =
                "CF7Launcher.Diagnostics.PlayerInfoFixture.hp-mp-feature-derived.svg";

            InvalidDataException error = Assert.Throws<InvalidDataException>(
                () => PlayerInfoSvgAssetCatalog.ValidateNoRepoOnlyResourceNames(
                    new[] { aliasedFixture }));

            Assert.Contains(aliasedFixture, error.Message);
        }

        [Fact]
        public void ProductionStrictFacade_RejectsExternalImageBeforeRendererEntry()
        {
            byte[] bytes = Encoding.UTF8.GetBytes(
                "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\">" +
                "<image href=\"https://example.invalid/pixel.png\" width=\"1\" height=\"1\"/>" +
                "</svg>");

            InvalidDataException error = Assert.Throws<InvalidDataException>(
                () => StrictSvgFacade.Load(bytes));

            Assert.Contains("Element is outside the core subset", error.Message);
        }
    }
}
