#nullable enable

using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml.Linq;
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
                "sha256:d67ab427748f5256bd18ea5669c9f1d045a6adaac30dce96f9660ea20c892ba1",
                assetSet.Revision);
            Assert.Equal(
                "6f0aaa452343319f861eba8ed678ade24e8b2b87ccd7cd01795d3d6b45fef826",
                assetSet.ExactManifestSha256);
            Assert.Equal("cf7-player-info-static-svg-v1", assetSet.FeatureSet);
            Assert.Equal(1, assetSet.RasterContractVersion);
            Assert.Equal(8, assetSet.Assets.Count);
            Assert.Equal(99_576, assetSet.Assets.Sum(asset => asset.Bytes.Length));
            Assert.Equal(
                assetSet.Assets.Count,
                assetSet.Assets.Select(asset => asset.Id).Distinct(StringComparer.Ordinal).Count());
        }

        [Fact]
        public void HpRim_KeepsExactHiddenHorizontalLineSource()
        {
            PlayerInfoSvgAssetSet assetSet =
                PlayerInfoSvgAssetContract.LoadProductionEmbedded(minimumRaster: false);
            PlayerInfoSvgAsset rim = assetSet.Assets.Single(asset =>
                string.Equals(asset.Id, "hp.rim", StringComparison.Ordinal));
            XDocument document = XDocument.Parse(
                new UTF8Encoding(false, true).GetString(rim.Bytes.Span),
                LoadOptions.None);
            XNamespace svg = "http://www.w3.org/2000/svg";

            XElement layer = Assert.Single(
                document.Descendants(svg + "g"),
                element =>
                    string.Equals(
                        (string?)element.Attribute("id"),
                        "hp-rim-layer-0025",
                        StringComparison.Ordinal));
            Assert.Equal("0", (string?)layer.Attribute("opacity"));

            XElement instance = Assert.Single(
                layer.Elements(svg + "g"),
                element =>
                    string.Equals(
                        (string?)element.Attribute("id"),
                        "hp-rim-instance-0026",
                        StringComparison.Ordinal));
            Assert.Equal(
                "matrix(1 0 0 1 -22.6 7.55)",
                (string?)instance.Attribute("transform"));

            XElement shape = Assert.Single(
                instance.Elements(svg + "g"),
                element =>
                    string.Equals(
                        (string?)element.Attribute("id"),
                        "hp-rim-shape-0027",
                        StringComparison.Ordinal));
            XElement path = Assert.Single(
                shape.Elements(svg + "path"),
                element =>
                    string.Equals(
                        (string?)element.Attribute("id"),
                        "hp-rim-path-0028",
                        StringComparison.Ordinal));
            Assert.Equal("#FFFFFF", (string?)path.Attribute("fill"));
            Assert.Equal("evenodd", (string?)path.Attribute("fill-rule"));
            Assert.False(string.IsNullOrWhiteSpace((string?)path.Attribute("d")));
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
