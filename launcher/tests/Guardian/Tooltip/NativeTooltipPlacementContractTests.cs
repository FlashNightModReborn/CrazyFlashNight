using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Tooltip
{
    /// <summary>
    /// Web→Native 定位回归契约（bounded live contract）。
    ///
    /// 权威侧不是静态快照：launcher/perf/tooltip-parity/placement-oracle.js
    /// 从生产 launcher/web/modules/tooltip.js 源码机械抽取并实际执行
    /// positionFloating 定位管线（clamp/overlapArea/rectAt/anchorRectOf/
    /// placementCandidate/placementFeasible/candidateScore/resetPlacementState），
    /// 输出 CSS px 视口域期望；本测试把同一输入 ×dpi + 物理视口原点换算后
    /// 回放 <see cref="NativeTooltipLayout.SolvePlacement"/>，侧名精确相等、
    /// 物理矩形四边容差 ≤2px（含取整舍入余量，对应 perf 判定 acceptance
    /// posTolWarn=2px）。web 抽取缺失/求解漂移/native 端口改写任一发生，
    /// 本测试即红——这正是它存在的意义。
    ///
    /// 覆盖：DPR 1/1.25/1.5 × 非零物理原点视口 × 四角/四边 × 锁定侧
    /// 可行/不可行 × anchored × 同 show 多步走位（锁保持/解锁/重锁）×
    /// 真实元素锚 rect（候选贴矩形边缘）× pointer≠anchor × 格内指针巡游
    /// 稳定性 × placementHint 可行/被视口否决 × 锁压 hint × 同锚变尺寸
    /// 边缘翻转。anchored 且 pointer=null 时按 web 内建规则回退锚 rect 中心。
    /// 未覆盖（见 job notes.md）：stacked 降级后定位、querySelector 非空分支、
    /// ComputePlan 派生 tipSize 的耦合。
    /// </summary>
    public class NativeTooltipPlacementContractTests
    {
        private const double TolerancePx = 2.0;

        [Fact]
        public void Oracle_ExtractsLiveWebPlacementPipeline()
        {
            JObject suite = RunOracle();
            Assert.Equal("placement-oracle.v1", suite.Value<string>("oracle"));
            Assert.Equal(
                "launcher/web/modules/tooltip.js",
                suite.Value<string>("source"));
            Assert.False(string.IsNullOrWhiteSpace(suite.Value<string>("sourceSha256")));

            var functions = new HashSet<string>(
                suite["extracted"]["functions"].ToObject<string[]>());
            foreach (string name in new[]
            {
                "clamp", "overlapArea", "rectAt", "anchorRectOf",
                "placementCandidate", "placementFeasible", "candidateScore",
                "positionFloating"
            })
            {
                Assert.True(functions.Contains(name),
                    "oracle 未抽取到生产函数 " + name);
            }

            JArray cases = (JArray)suite["cases"];
            Assert.Equal(suite.Value<int>("caseCount"), cases.Count);
            Assert.True(cases.Count >= 63,
                "契约用例数异常收缩：" + cases.Count);
        }

        [Fact]
        public void SolvePlacement_MatchesLiveWebOracle()
        {
            JObject suite = RunOracle();
            JArray cases = (JArray)suite["cases"];
            int compared = 0;

            foreach (JObject c in cases)
            {
                string id = c.Value<string>("id");
                double dpr = c.Value<double>("dpr");
                bool anchored = c.Value<bool>("anchored");
                string hint = c.Value<string>("hint");
                int ox = c["viewportOriginPhys"].Value<int>("x");
                int oy = c["viewportOriginPhys"].Value<int>("y");
                double vw = c["viewportCss"].Value<double>("w");
                double vh = c["viewportCss"].Value<double>("h");

                var viewport = new Rectangle(
                    ox, oy,
                    (int)Math.Round(vw * dpr),
                    (int)Math.Round(vh * dpr));

                JArray steps = (JArray)c["steps"];
                for (int i = 0; i < steps.Count; i++)
                {
                    JObject step = (JObject)steps[i];
                    JObject input = (JObject)step["input"];
                    JObject expected = (JObject)step["expected"];

                    // Web 锁定侧 = 同 show 前轮实际落侧（_lockedPlacement），
                    // 与 widget _lockedSide 回喂语义一致；逐步以 oracle 记录的
                    // lockedBefore 回放，隔离单步漂移不向后传染。
                    JToken lockedTok = input["lockedBefore"];
                    string locked = lockedTok.Type == JTokenType.Null
                        ? null : lockedTok.Value<string>();
                    double tw = input.Value<double>("tipW");
                    double th = input.Value<double>("tipH");
                    var tipSize = new Size(
                        (int)Math.Round(tw * dpr),
                        (int)Math.Round(th * dpr));

                    string side;
                    Rectangle actual;
                    JToken anchorTok = input["anchorRect"];
                    string anchorDesc;
                    if (anchorTok != null && anchorTok.Type != JTokenType.Null)
                    {
                        // 真实元素锚 rect：新重载。候选贴矩形边缘；anchored 时
                        // web pointer=null → 指针回退锚 rect 中心（同口径回放）。
                        double ax = anchorTok.Value<double>("x");
                        double ay = anchorTok.Value<double>("y");
                        double aw = anchorTok.Value<double>("w");
                        double ah = anchorTok.Value<double>("h");
                        var anchorRect = new Rectangle(
                            ox + (int)Math.Round(ax * dpr),
                            oy + (int)Math.Round(ay * dpr),
                            (int)Math.Round(aw * dpr),
                            (int)Math.Round(ah * dpr));
                        JToken pxTok = input["pointerX"];
                        double pxd = pxTok == null || pxTok.Type == JTokenType.Null
                            ? ax + aw / 2.0
                            : pxTok.Value<double>();
                        JToken pyTok = input["pointerY"];
                        double pyd = pyTok == null || pyTok.Type == JTokenType.Null
                            ? ay + ah / 2.0
                            : pyTok.Value<double>();
                        var pointer = new Point(
                            ox + (int)Math.Round(pxd * dpr),
                            oy + (int)Math.Round(pyd * dpr));
                        actual = NativeTooltipLayout.SolvePlacement(
                            anchorRect, pointer, tipSize, viewport,
                            locked, hint, (float)dpr, anchored, out side);
                        anchorDesc = string.Format(
                            "rectCss=({0},{1},{2}x{3}) ptrCss=({4},{5})",
                            ax, ay, aw, ah, pxd, pyd);
                    }
                    else
                    {
                        // 点锚：走旧重载（内部委托零面积 rect + 指针=锚点）。
                        double px = input.Value<double>("pointerX");
                        double py = input.Value<double>("pointerY");
                        var anchorPt = new Point(
                            ox + (int)Math.Round(px * dpr),
                            oy + (int)Math.Round(py * dpr));
                        actual = NativeTooltipLayout.SolvePlacement(
                            anchorPt, tipSize, viewport, locked,
                            1f, (float)dpr, anchored, out side);
                        anchorDesc = string.Format("pointCss=({0},{1})", px, py);
                    }

                    string expSide = expected.Value<string>("side");
                    double ex = ox + expected.Value<double>("x") * dpr;
                    double ey = oy + expected.Value<double>("y") * dpr;
                    double er = ex + expected.Value<double>("w") * dpr;
                    double eb = ey + expected.Value<double>("h") * dpr;

                    string ctx = string.Format(
                        "case={0} step={1} {2} tipCss=({3},{4}) " +
                        "dpr={5} vpCss=({6}x{7}) orgPhys=({8},{9}) locked={10} " +
                        "hint={11} anchored={12}",
                        id, i, anchorDesc, tw, th, dpr, vw, vh, ox, oy,
                        locked ?? "null", hint ?? "null", anchored);

                    Assert.True(
                        string.Equals(expSide, side, StringComparison.Ordinal),
                        string.Format(
                            "{0} | side 期望 {1} 实得 {2} | rect 实得 {3} 期望≈({4},{5},{6},{7})",
                            ctx, expSide, side, actual, ex, ey, er, eb));

                    Assert.True(
                        Math.Abs(actual.X - ex) <= TolerancePx
                            && Math.Abs(actual.Y - ey) <= TolerancePx
                            && Math.Abs(actual.Right - er) <= TolerancePx
                            && Math.Abs(actual.Bottom - eb) <= TolerancePx,
                        string.Format(
                            "{0} | side={1} | rect 实得 (X={2},Y={3},R={4},B={5}) " +
                            "期望≈({6},{7},{8},{9}) 容差≤{10}px",
                            ctx, side, actual.X, actual.Y, actual.Right,
                            actual.Bottom, ex, ey, er, eb, TolerancePx));

                    // 夹取后应整体落在视口内（web insideViewport 同口径，±1 容差）。
                    Assert.True(expected.Value<bool>("insideViewport"),
                        ctx + " | web 报告 insideViewport=false");
                    compared++;
                }
            }

            Assert.True(compared >= 96, "逐步断言数异常：" + compared);
        }

        // ── oracle 进程：单次调用、UTF8、15s 超时、超时即杀 ──

        private static JObject RunOracle()
        {
            string projectRoot = FindProjectRoot();
            string script = Path.Combine(
                projectRoot, "launcher", "perf", "tooltip-parity",
                "placement-oracle.js");
            Assert.True(File.Exists(script), "oracle 缺失：" + script);

            var start = new ProcessStartInfo
            {
                FileName = ResolveNodeExecutable(),
                WorkingDirectory = projectRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            start.ArgumentList.Add(script);

            using (Process process = Process.Start(start)
                ?? throw new InvalidOperationException("无法启动 placement-oracle。"))
            {
                // 异步读双管道防缓冲死锁；15s 对本用例规模（39 case / 51 步）宽裕。
                var stdoutTask = process.StandardOutput.ReadToEndAsync();
                var stderrTask = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(15_000))
                {
                    try { process.Kill(true); } catch { /* 清理尽力而为 */ }
                    Assert.Fail("placement-oracle 超时（>15s），已终止进程树。");
                }
                string stdout = stdoutTask.GetAwaiter().GetResult();
                string stderr = stderrTask.GetAwaiter().GetResult();
                Assert.Equal(0, process.ExitCode);
                Assert.True(string.IsNullOrWhiteSpace(stderr),
                    "placement-oracle stderr：" + stderr);
                return JObject.Parse(stdout);
            }
        }

        private static string ResolveNodeExecutable()
        {
            string configured = Environment.GetEnvironmentVariable("CF7_NODE_EXE");
            return string.IsNullOrWhiteSpace(configured) ? "node.exe" : configured;
        }

        private static string FindProjectRoot()
        {
            foreach (string start in new[]
            {
                Environment.CurrentDirectory,
                AppContext.BaseDirectory
            })
            {
                var directory = new DirectoryInfo(start);
                while (directory != null)
                {
                    if (File.Exists(Path.Combine(
                            directory.FullName, "data", "merc", "pets.xml"))
                        && File.Exists(Path.Combine(
                            directory.FullName,
                            "launcher",
                            "CRAZYFLASHER7MercenaryEmpire.csproj")))
                    {
                        return directory.FullName;
                    }
                    directory = directory.Parent;
                }
            }
            throw new DirectoryNotFoundException(
                "无法定位 CF7 项目根（placement contract 测试）。");
        }
    }
}
