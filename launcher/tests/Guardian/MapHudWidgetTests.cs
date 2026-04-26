using System.Collections.Generic;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// MapHudWidget UiData 状态机回归。
    ///
    /// 关键不变量：
    /// 1. Visible 门控：gameReady && mode in {1,2} && hotspotId 非空 && catalog 命中
    /// 2. mode 0/3 → 不渲染（与 web map-hud.js applyState 同步）
    /// 3. mh 切到 catalog 内不存在的 hotspot → entry=null → Visible=false（不抛）
    /// 4. SanitizeMode：仅 0/1/2/3 合法，其它 → "0"
    /// 5. ResolveTheme：未知 group → base 主题（不抛）
    /// 6. WantsAnimationTick 永远 false（HUD 静态，无动画）
    /// 7. click → router.Dispatch("TASK_MAP")
    /// </summary>
    public class MapHudWidgetTests
    {
        private static MapHudPayload BuildPayload()
        {
            MapHudPayload p = new MapHudPayload();
            p.ProtocolVersion = 1;
            p.Hotspots = new Dictionary<string, MapHudHotspotEntry>();

            MapHudHotspotEntry e1 = new MapHudHotspotEntry();
            e1.Meta = new MapHudMeta
            {
                PageId = "faction", PageLabel = "A兵团",
                HotspotId = "warlord_base", Label = "军阀基地",
                Group = "warlord"
            };
            e1.Outline = new MapHudOutline
            {
                ViewportRect = new RectF { X = 35, Y = 25, W = 260, H = 300 },
                CurrentRect  = new RectF { X = 46, Y = 85, W = 240, H = 125 },
                Blocks = new List<MapHudBlock>
                {
                    new MapHudBlock
                    {
                        HotspotId = "warlord_base", Label = "军阀基地",
                        SourceRect = new RectF { X = 46, Y = 85, W = 240, H = 125 }
                    }
                }
            };
            p.Hotspots["warlord_base"] = e1;
            return p;
        }

        private static MapHudWidget MakeWidget(out RouterStub router, out MapHudDataCatalog cat)
        {
            cat = MapHudDataCatalog.FromPayload(BuildPayload());
            router = new RouterStub();
            Control anchor = new Control();
            MapHudWidget w = new MapHudWidget(anchor, router.Router, cat);
            return w;
        }

        // ── default state ──

        [Fact]
        public void Default_NotReady_NotVisible()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            Assert.False(w.VisibleForTest);
        }

        [Fact]
        public void Ready_NoHotspot_NotVisible()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.ForceGameReady(true);
            w.ForceMode("1");
            Assert.False(w.VisibleForTest);
        }

        [Fact]
        public void Ready_ModeZero_NotVisible()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.ForceGameReady(true);
            w.ForceMode("0");
            w.ForceHotspot("warlord_base");
            Assert.False(w.VisibleForTest);
        }

        [Fact]
        public void Ready_ModeOne_KnownHotspot_Visible()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.ForceGameReady(true);
            w.ForceMode("1");
            w.ForceHotspot("warlord_base");
            Assert.True(w.VisibleForTest);
            Assert.NotNull(w.EntryForTest);
            Assert.Equal("warlord", w.EntryForTest.Meta.Group);
        }

        [Fact]
        public void Ready_ModeTwo_KnownHotspot_Visible()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.ForceGameReady(true);
            w.ForceMode("2");
            w.ForceHotspot("warlord_base");
            Assert.True(w.VisibleForTest);
        }

        [Fact]
        public void Ready_ModeThree_NotVisible()
        {
            // mode 3 在 web map-hud.js 视为不渲染（仅 1/2 显示）
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.ForceGameReady(true);
            w.ForceMode("3");
            w.ForceHotspot("warlord_base");
            Assert.False(w.VisibleForTest);
        }

        [Fact]
        public void Hotspot_NotInCatalog_NotVisibleNoThrow()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.ForceGameReady(true);
            w.ForceMode("1");
            w.ForceHotspot("nonexistent_hotspot");
            Assert.False(w.VisibleForTest);
            Assert.Null(w.EntryForTest);
        }

        // ── UiData 通道 ──

        [Fact]
        public void UiData_FullChain_Visible()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.OnUiDataChanged(Snapshot("s:1", "mm:1", "mh:warlord_base"),
                              new HashSet<string> { "s", "mm", "mh" });
            Assert.True(w.VisibleForTest);
        }

        [Fact]
        public void UiData_EmptyHotspot_HidesAndClearsEntry()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.OnUiDataChanged(Snapshot("s:1", "mm:1", "mh:warlord_base"),
                              new HashSet<string> { "s", "mm", "mh" });
            Assert.True(w.VisibleForTest);
            // 切到空 hotspot
            w.OnUiDataChanged(Snapshot("s:1", "mm:1", "mh:"),
                              new HashSet<string> { "mh" });
            Assert.False(w.VisibleForTest);
            Assert.Null(w.EntryForTest);
        }

        [Fact]
        public void UiData_ModeFlipsToZero_Hides()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.OnUiDataChanged(Snapshot("s:1", "mm:1", "mh:warlord_base"),
                              new HashSet<string> { "s", "mm", "mh" });
            Assert.True(w.VisibleForTest);
            w.OnUiDataChanged(Snapshot("s:1", "mm:0", "mh:warlord_base"),
                              new HashSet<string> { "mm" });
            Assert.False(w.VisibleForTest);
        }

        // ── click ──

        [Fact]
        public void Click_DispatchesTaskMap()
        {
            // Flag OFF（_panelHost==null）：TASK_MAP → OpenMapPanel → PostToWeb panel_cmd open(map)
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            w.SimulateClick();
            Assert.Single(r.Posts);
            Assert.Contains("\"panel\":\"map\"", r.Posts[0]);
            Assert.Contains("\"cmd\":\"open\"", r.Posts[0]);
        }

        // ── animation ──

        [Fact]
        public void WantsAnimationTick_AlwaysFalse()
        {
            RouterStub r; MapHudDataCatalog cat;
            MapHudWidget w = MakeWidget(out r, out cat);
            Assert.False(w.WantsAnimationTick);
            w.ForceGameReady(true);
            w.ForceMode("1");
            w.ForceHotspot("warlord_base");
            Assert.False(w.WantsAnimationTick);  // 即使 visible 也无动画
        }

        // ── helpers ──

        [Theory]
        [InlineData("0", "0")]
        [InlineData("1", "1")]
        [InlineData("2", "2")]
        [InlineData("3", "3")]
        [InlineData("4", "0")]
        [InlineData("", "0")]
        [InlineData(null, "0")]
        [InlineData("abc", "0")]
        public void SanitizeMode_Cases(string input, string expected)
        {
            Assert.Equal(expected, MapHudWidget.SanitizeMode(input));
        }

        [Theory]
        [InlineData("mh:warlord_base", "mh", "warlord_base")]
        [InlineData("mh:", "mh", "")]
        [InlineData("warlord_base", "mh", "warlord_base")]
        [InlineData("", "mh", "")]
        [InlineData(null, "mh", "")]
        public void StripPrefix_Cases(string input, string key, string expected)
        {
            Assert.Equal(expected, MapHudWidget.StripPrefix(input, key));
        }

        // ── helpers ──

        private static IReadOnlyDictionary<string, string> Snapshot(params string[] kvPieces)
        {
            Dictionary<string, string> dict = new Dictionary<string, string>();
            foreach (string p in kvPieces)
            {
                int colon = p.IndexOf(':');
                string k = colon > 0 ? p.Substring(0, colon) : p;
                dict[k] = p;
            }
            return dict;
        }

        private class RouterStub
        {
            public List<string> Posts = new List<string>();
            public LauncherCommandRouter Router;
            public RouterStub()
            {
                List<string> postsLocal = Posts;
                Router = new LauncherCommandRouter(
                    socketServer: null,
                    onSendKey: k => { },
                    onToggleFullscreen: () => { },
                    onToggleLog: () => { },
                    onForceExit: () => { },
                    postToWeb: s => postsLocal.Add(s),
                    onPanelStateChanged: b => { },
                    setActivePanel: name => { });
            }
        }
    }
}
