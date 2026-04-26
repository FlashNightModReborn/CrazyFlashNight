using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Guardian.Hud;
using Newtonsoft.Json;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// MapHudPayload + MapHudDataCatalog parse 回归。
    ///
    /// 关键不变量：
    /// 1. protocolVersion=1 是 supported；missing/不一致只 log warning，不抛
    /// 2. list 字段保持 nullable，区分 "JSON 空数组" vs "字段缺失"
    /// 3. catalog 找不到 hotspot 返回 null（不抛）；空 hotspots → IsAvailable=false
    /// 4. 文件不存在 → IsAvailable=false（不抛）
    /// 5. group 缺失（base 等）→ Meta.Group=null/空，widget 自行 fallback 主题
    ///
    /// fixture 通过 csproj &lt;CopyToOutputDirectory&gt; 拷到 bin/Debug/Fixtures/MapHud；
    /// xunit shadow-copy 下用 AppDomain.CurrentDomain.BaseDirectory 拿原始 bin 路径。
    /// </summary>
    public class MapHudPayloadParseTests
    {
        private static string FixtureDir
        {
            get
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string probe = Path.Combine(baseDir, "Fixtures", "MapHud");
                if (Directory.Exists(probe)) return probe;
                // fallback：从 cwd 走源树
                string dir = Directory.GetCurrentDirectory();
                for (int i = 0; i < 6 && dir != null; i++)
                {
                    probe = Path.Combine(dir, "launcher", "tests", "Fixtures", "MapHud");
                    if (Directory.Exists(probe)) return probe;
                    probe = Path.Combine(dir, "tests", "Fixtures", "MapHud");
                    if (Directory.Exists(probe)) return probe;
                    dir = Path.GetDirectoryName(dir);
                }
                throw new DirectoryNotFoundException("Fixtures/MapHud not found near " + baseDir);
            }
        }

        private static string FixturePath(string name) { return Path.Combine(FixtureDir, name); }

        // ── DTO parse ──

        [Fact]
        public void Parse_Basic_AllFieldsResolved()
        {
            string raw = File.ReadAllText(FixturePath("payload-v1-basic.json"));
            MapHudPayload p = JsonConvert.DeserializeObject<MapHudPayload>(raw);
            Assert.NotNull(p);
            Assert.Equal(1, p.ProtocolVersion);
            Assert.Single(p.Hotspots);
            MapHudHotspotEntry e = p.Hotspots["warlord_base"];
            Assert.Equal("faction", e.Meta.PageId);
            Assert.Equal("warlord", e.Meta.Group);
            Assert.NotNull(e.Outline.ViewportRect);
            Assert.Equal(259.77f, e.Outline.ViewportRect.Value.W);
            Assert.Single(e.Outline.Blocks);
            Assert.Single(e.Outline.Visuals);
            Assert.True(e.Outline.Visuals[0].IsCurrent);
        }

        [Fact]
        public void Parse_FallbackBlocks_VisualsExplicitEmpty()
        {
            // visuals: [] 显式空 → 反序列化得空 list（非 null），区分"字段缺失"
            string raw = File.ReadAllText(FixturePath("payload-v1-fallback-blocks.json"));
            MapHudPayload p = JsonConvert.DeserializeObject<MapHudPayload>(raw);
            MapHudHotspotEntry e = p.Hotspots["base_lobby"];
            Assert.NotNull(e.Outline.Visuals);
            Assert.Empty(e.Outline.Visuals);
            Assert.Equal(2, e.Outline.Blocks.Count);
            Assert.Equal("", e.Meta.Group);
        }

        [Fact]
        public void Parse_MissingMetaGroup_GroupNull()
        {
            string raw = File.ReadAllText(FixturePath("payload-v1-missing-meta-group.json"));
            MapHudPayload p = JsonConvert.DeserializeObject<MapHudPayload>(raw);
            MapHudHotspotEntry e = p.Hotspots["unknown_spot"];
            Assert.Null(e.Meta.Group);  // 字段缺失 → null（不是空串）
            Assert.Null(e.Outline.CurrentRect);  // 显式 null
            Assert.Null(e.Outline.Visuals);  // 字段缺失 → null
            Assert.Single(e.Outline.Blocks);
        }

        [Fact]
        public void Parse_LegacyV0_ProtocolVersionNull()
        {
            string raw = File.ReadAllText(FixturePath("payload-v0-legacy.json"));
            MapHudPayload p = JsonConvert.DeserializeObject<MapHudPayload>(raw);
            Assert.Null(p.ProtocolVersion);  // 旧 schema 没有 protocolVersion
            Assert.Single(p.Hotspots);
            Assert.Equal("schoolInside", p.Hotspots["school_dorm"].Meta.Group);
        }

        // ── catalog ──

        [Fact]
        public void Catalog_LoadBasic_AvailableAndQueryable()
        {
            MapHudDataCatalog cat = MapHudDataCatalog.LoadFromFile(FixturePath("payload-v1-basic.json"));
            Assert.True(cat.IsAvailable);
            Assert.Equal(1, cat.HotspotCount);
            MapHudHotspotEntry e = cat.GetEntry("warlord_base");
            Assert.NotNull(e);
            Assert.Equal("warlord", e.Meta.Group);
        }

        [Fact]
        public void Catalog_UnknownHotspot_Null()
        {
            MapHudDataCatalog cat = MapHudDataCatalog.LoadFromFile(FixturePath("payload-v1-basic.json"));
            Assert.Null(cat.GetEntry("nonexistent"));
            Assert.Null(cat.GetEntry(""));
            Assert.Null(cat.GetEntry(null));
        }

        [Fact]
        public void Catalog_EmptyHotspots_NotAvailable()
        {
            MapHudDataCatalog cat = MapHudDataCatalog.LoadFromFile(FixturePath("payload-v1-empty-hotspots.json"));
            Assert.False(cat.IsAvailable);
            Assert.Equal(0, cat.HotspotCount);
        }

        [Fact]
        public void Catalog_MissingFile_NotAvailableNoThrow()
        {
            MapHudDataCatalog cat = MapHudDataCatalog.LoadFromFile(Path.Combine(FixtureDir, "DOES_NOT_EXIST.json"));
            Assert.False(cat.IsAvailable);
            Assert.Null(cat.GetEntry("anything"));
        }

        [Fact]
        public void Catalog_LegacyV0_StillLoadsWithWarning()
        {
            // protocolVersion 缺失只 log warning，不阻塞加载
            MapHudDataCatalog cat = MapHudDataCatalog.LoadFromFile(FixturePath("payload-v0-legacy.json"));
            Assert.True(cat.IsAvailable);
            Assert.Null(cat.ProtocolVersion);
            Assert.NotNull(cat.GetEntry("school_dorm"));
        }
    }
}
