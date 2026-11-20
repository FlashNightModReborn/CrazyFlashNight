using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Tooltip
{
    public sealed class NativeTooltipUnicodeTests
    {
        [Theory]
        [InlineData("𠊎", 1)]
        [InlineData("e\u0301", 1)]
        [InlineData("👩‍🚀", 2)]
        [InlineData("🇨🇳", 2)]
        [InlineData("✈️", 1)]
        public void WrapKeepsCrossStyleElementWholeEvenOnNarrowLine(string element, int split)
        {
            var runs = new List<NativeTooltipRun>
            {
                new("A" + element.Substring(0, split), Color.Red, false),
                new(element.Substring(split) + "B", Color.Blue, true)
            };
            var measured = new HashSet<string>();
            int Measure(string text, bool bold)
            {
                measured.Add(text);
                return text.Length;
            }
            var lines = NativeTooltipLayout.WrapRuns(runs, 1, Measure);
            Assert.Equal(new[] { "A", element, "B" },
                lines.Select(line => Assert.Single(line.Slices).Text));
            Assert.Equal(Color.Red, lines[1].Slices[0].Color);
            Assert.False(lines[1].Slices[0].Bold);
            Assert.True(lines[2].Slices[0].Bold);
            Assert.Equal(Color.Blue, lines[2].Slices[0].Color);
            Assert.Contains(element, measured);
            Assert.All(measured, candidate =>
                Assert.Contains(candidate, new[] { "A", "A" + element, element, "B" }));
            Assert.False(lines[0].EndsLogicalLine);
            Assert.False(lines[1].EndsLogicalLine);
            Assert.True(lines[2].EndsLogicalLine);
        }

        [Fact]
        public void CrossStyleHardBreakAndMalformedUnitsKeepNeighborText()
        {
            var runs = new List<NativeTooltipRun>
            {
                new("A\uD840B\r", null, false),
                new("\nC\uDE8ED", null, true)
            };
            var lines = NativeTooltipLayout.WrapRuns(runs, 100, (text, bold) => text.Length);
            Assert.Equal(new[] { "A�B", "C�D" },
                lines.Select(line => Assert.Single(line.Slices).Text));
            Assert.All(lines, line => Assert.True(line.EndsLogicalLine));
        }

        [Fact]
        public void ScoreAndOptionalSpacingCountDisplayedElements()
        {
            var score = NativeTooltipLayout.ScoreText("A e\u0301\r\n𠊎👩‍🚀");
            Assert.Equal(2, score.LineCount);
            Assert.Equal(6.5, score.Total);
            Assert.Equal(4, score.MaxLine);
            var runs = new[] { new NativeTooltipRun("𠊎👩‍🚀", null, false) };
            var line = Assert.Single(NativeTooltipLayout.WrapRuns(runs, 2,
                (text, font) => 0, 12f, 1f));
            Assert.Equal(2f, Assert.Single(line.Slices).WidthF);
        }

        [Theory]
        [InlineData("𠊎")]
        [InlineData("e\u0301")]
        [InlineData("👩‍🚀")]
        public void DisplayFieldsKeepTheirCodeUnitCapsAtElementBoundaries(string element)
        {
            string railPrefix = new string('x', 23);
            string magazinePrefix = new string('x', 63);
            var document = NativeTooltipDocument.FromDocument(new JObject
            {
                ["title"] = "样本",
                ["rail"] = new JArray(railPrefix + element + "B"),
                ["magazine"] = new JObject
                {
                    ["name"] = magazinePrefix + element + "B",
                    ["ammo"] = magazinePrefix + element + "B"
                }
            });
            Assert.Equal(railPrefix, Assert.Single(document.Rail.Texts));
            Assert.Equal(magazinePrefix, document.Magazine.Name);
            Assert.Equal(magazinePrefix, document.Magazine.Ammo);
        }

        [Fact]
        public void GdiRefusalPreservesSourceAndFollowingStyle()
        {
            string cluster = "a" + new string('\u0301', 32767);
            var runs = new[] { new NativeTooltipRun("甲" + cluster + "乙", Color.Blue, false) };
            var lines = NativeTooltipLayout.WrapRuns(runs, 32, (text, bold) =>
                text.Contains(cluster) ? throw new System.Runtime.InteropServices.ExternalException() : text.Length);
            var slices = Assert.Single(NativeTooltipLayout.MergeLogicalLines(lines)).Slices;
            Assert.Equal("甲" + cluster + "乙", string.Concat(slices.Select(s => s.Text)));
            Assert.Equal("甲□乙", string.Concat(slices.Select(s => s.PaintOverride ?? s.Text)));
            Assert.All(slices, s => Assert.Equal(Color.Blue, s.Color));
        }

        [Fact]
        public void ZeroWidthSpacesRetainTheirSourceAndWrapWithoutMeasuringPrefixes()
        {
            string spaces = new string('\u200B', 32768);
            var runs = new[] { new NativeTooltipRun("A" + spaces + "B", null, false) };
            var lines = NativeTooltipLayout.WrapRuns(runs, 1, (text, bold) =>
            {
                Assert.DoesNotContain('\u200B', text);
                return text.Length;
            });
            Assert.Equal(2, lines.Count);
            Assert.Equal("A" + spaces, string.Concat(lines[0].Slices.Select(s => s.Text)));
            Assert.Equal("B", Assert.Single(lines[1].Slices).Text);
        }

        [Fact]
        public void SharedBoundariesPreserveOffsetsAndCompleteLastElement()
        {
            const string valid = "𠊎e\u0301👩‍🚀";
            Assert.Same(valid, NativeTextElements.NormalizeDisplay(valid));
            Assert.Equal(new[] { 0, 2, 4 }, NativeTextElements.Starts(valid));
            Assert.Equal("A�B�C", NativeTextElements.NormalizeDisplay("A\uDE8EB\uD840C"));
            Assert.Equal("𠊎e\u0301", NativeTextElements.Truncate(valid, 4));
            Assert.Equal("", NativeTextElements.Truncate(valid, 1));
            Assert.Equal(valid, NativeTextElements.Truncate(valid, valid.Length));
        }
    }
}
