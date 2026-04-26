using System.IO;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// MapHudWidget.TryResolveAssetPath 路径安全回归（计划硬约束 #18）。
    ///
    /// 拒绝：
    /// - 绝对路径
    /// - URL（含 ://）
    /// - query / fragment（? / #）
    /// - 通过 .. 逃出 webDir
    /// - 前缀绕过（webDir="C:\x\web" 不能通过 "C:\x\web2" 命中）
    ///
    /// 接受：webDir 之内的相对路径（即使文件不存在——存在性由调用方校验）
    /// </summary>
    public class MapHudAssetPathSecurityTests
    {
        private string _tmpRoot;
        private string _webDir;
        private string _siblingDir;

        public MapHudAssetPathSecurityTests()
        {
            _tmpRoot = Path.Combine(Path.GetTempPath(), "MapHudAssetPathTests_" + System.Guid.NewGuid().ToString("N"));
            _webDir = Path.Combine(_tmpRoot, "web");
            _siblingDir = Path.Combine(_tmpRoot, "web2");
            Directory.CreateDirectory(_webDir);
            Directory.CreateDirectory(_siblingDir);
        }

        [Fact]
        public void Accept_RelativeAssetPath()
        {
            string resolved;
            Assert.True(MapHudWidget.TryResolveAssetPath(_webDir, "assets/map/foo.png", out resolved));
            Assert.NotNull(resolved);
            Assert.StartsWith(_webDir, resolved, System.StringComparison.OrdinalIgnoreCase);
        }

        [Fact]
        public void Reject_AbsolutePath()
        {
            string resolved;
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, _webDir + "/foo.png", out resolved));
            Assert.Null(resolved);
        }

        [Fact]
        public void Reject_Url()
        {
            string resolved;
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "https://example.com/foo.png", out resolved));
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "file://etc/passwd", out resolved));
        }

        [Fact]
        public void Reject_QueryOrFragment()
        {
            string resolved;
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "assets/foo.png?x=1", out resolved));
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "assets/foo.png#frag", out resolved));
        }

        [Fact]
        public void Reject_DotDotEscape()
        {
            string resolved;
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "../web2/foo.png", out resolved));
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "../../etc/passwd", out resolved));
        }

        [Fact]
        public void Reject_PrefixBypass_WebVsWeb2()
        {
            // 关键：webDir="...\web"，"\web2\foo" 在字符串 StartsWith("...\web") 下会误中。
            // 加分隔符后比较防止此类绕过。
            string resolved;
            string assetUrl = "../web2/foo.png";
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, assetUrl, out resolved));
            Assert.Null(resolved);
        }

        [Fact]
        public void Reject_NullOrEmpty()
        {
            string resolved;
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, null, out resolved));
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "", out resolved));
            Assert.False(MapHudWidget.TryResolveAssetPath(null, "foo.png", out resolved));
            Assert.False(MapHudWidget.TryResolveAssetPath("", "foo.png", out resolved));
        }

        [Fact]
        public void Reject_NestedDotDot()
        {
            string resolved;
            Assert.False(MapHudWidget.TryResolveAssetPath(_webDir, "assets/../../web2/foo.png", out resolved));
        }
    }
}
