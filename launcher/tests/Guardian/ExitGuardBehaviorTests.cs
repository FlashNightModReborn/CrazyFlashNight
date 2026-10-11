using System;
using System.Diagnostics;
using System.IO;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// phase1-owner-matrix 最后一行的行为级覆盖：
    /// ExitGuard 后台线程在 OnShutdownEarly 注入 10s 阻塞时仍 8s Environment.Exit(1)。
    /// 现存 GuardianRunsCancellableFenceBeforeShutdownLifecycleAndExitGuard 只做源码顺序断言，
    /// 本测试以子进程运行真实构建产物，验证真实进程退出语义（exit code + 时序）。
    /// 探针经 CF7_EXITGUARD_PROBE 环境变量显式激活（Program.Main 最早门控）。
    /// </summary>
    public sealed class ExitGuardBehaviorTests
    {
        // 探针进程启动 + GuardianForm 构造 + 8s 守卫触发：充裕上限。
        private const int ProbeTimeoutMs = 30000;
        private const int ExitGuardDelayMs = 8000;

        [Fact]
        public void ExitGuardKillsProcessWhileOnShutdownEarlyBlocksTenSeconds()
        {
            var sw = new Stopwatch();
            int exitCode;
            using (Process probe = StartProbe(10000))
            {
                sw.Start();
                Assert.True(
                    probe.WaitForExit(ProbeTimeoutMs),
                    "ExitGuard 探针 30s 未退出 — 保底线程未触发 Environment.Exit(1)。");
                sw.Stop();
                exitCode = probe.ExitCode;
            }

            // 只有 ExitGuard 的 Environment.Exit(1) 能产生 exit code 1；
            // OnShutdownEarly 10s 睡眠走完后正常通道返回 0。
            Assert.Equal(1, exitCode);
            // 守卫线程在 DoExit 中先于 OnShutdownEarly 启动：
            // 进程应在 ~8s 被杀，早于 10s 睡眠醒来后的正常退出。
            Assert.True(
                sw.ElapsedMilliseconds < 11500,
                "探针耗时 " + sw.ElapsedMilliseconds + "ms — 进程在 OnShutdownEarly 阻塞"
                + " 10s 结束前就应被 8s ExitGuard 终结。");
            // 反向约束：守卫确实等了 ~8s，不是启动即死（探针启动开销计入下限）。
            Assert.True(
                sw.ElapsedMilliseconds >= ExitGuardDelayMs - 2500,
                "探针仅耗时 " + sw.ElapsedMilliseconds + "ms — 退出过早，不像 8s 守卫触发。");
        }

        [Fact]
        public void ExitGuardDoesNotMisfireWhenCleanupCompletesWithinDeadline()
        {
            int exitCode;
            var sw = new Stopwatch();
            using (Process probe = StartProbe(500))
            {
                sw.Start();
                Assert.True(
                    probe.WaitForExit(ProbeTimeoutMs),
                    "ExitGuard 探针正常退出通道 30s 未结束。");
                sw.Stop();
                exitCode = probe.ExitCode;
            }

            // OnShutdownEarly 仅阻塞 500ms：清理在 8s 前完成，后台守卫线程随进程退出，
            // 正常通道返回 0 — 守卫不得误杀正常退出。
            Assert.Equal(0, exitCode);
            Assert.True(
                sw.ElapsedMilliseconds < ExitGuardDelayMs + 3000,
                "正常退出通道耗时 " + sw.ElapsedMilliseconds + "ms 超过守卫 deadline — "
                + "疑似被 ExitGuard 强杀而非正常退出。");
        }

        private static Process StartProbe(int onShutdownEarlySleepMs)
        {
            string launcherExe = ResolveLauncherExe();
            var start = new ProcessStartInfo
            {
                FileName = launcherExe,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = false,
                RedirectStandardError = false
            };
            start.EnvironmentVariables["CF7_EXITGUARD_PROBE"] =
                onShutdownEarlySleepMs.ToString();
            Process process = Process.Start(start);
            if (process == null)
            {
                throw new InvalidOperationException(
                    "无法启动 ExitGuard 探针进程: " + launcherExe);
            }
            return process;
        }

        // 测试工程通过 ProjectReference 引用主工程，构建产物被复制到测试输出目录。
        // 托管程序集实际命名为 .Core.exe（CRAZYFLASHER7MercenaryEmpire.exe 是部署 bootstrap）。
        private static string ResolveLauncherExe()
        {
            string candidate = Path.Combine(
                AppContext.BaseDirectory,
                "CRAZYFLASHER7MercenaryEmpire.Core.exe");
            if (File.Exists(candidate)) return candidate;
            throw new FileNotFoundException(
                "测试输出目录缺少 CRAZYFLASHER7MercenaryEmpire.Core.exe — "
                + "请先构建 launcher/CRAZYFLASHER7MercenaryEmpire.csproj。",
                candidate);
        }
    }
}
