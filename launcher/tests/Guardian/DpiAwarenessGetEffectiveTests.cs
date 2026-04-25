using System;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// 直接 P/Invoke 探测当前测试进程的 awareness。
    /// 测试只断言"返回值是合法枚举且不抛异常"——具体值依赖测试 host 的 DPI 配置。
    /// 关键不变量：不解析 Initialize 的 Method 字符串。
    /// </summary>
    public class DpiAwarenessGetEffectiveTests
    {
        [Fact]
        public void GetEffectiveAwareness_ReturnsValidEnum()
        {
            EffectiveDpiAwareness a = DpiAwarenessBootstrap.GetEffectiveAwareness();
            // xunit.console 测试 host 默认 unaware；CI 上可能是 SystemAware
            // 任何合法枚举值都接受
            Assert.True(Enum.IsDefined(typeof(EffectiveDpiAwareness), a));
        }

        [Fact]
        public void GetEffectiveAwarenessForWindow_ZeroHandle_ReturnsUnknown()
        {
            EffectiveDpiAwareness a = DpiAwarenessBootstrap.GetEffectiveAwarenessForWindow(IntPtr.Zero);
            Assert.Equal(EffectiveDpiAwareness.Unknown, a);
        }

        [Fact]
        public void GetEffectiveAwarenessForWindow_InvalidHandle_DoesNotThrow()
        {
            // 故意传无效 hwnd —— 内部 try/catch 应吞掉 Win32 异常
            EffectiveDpiAwareness a = DpiAwarenessBootstrap.GetEffectiveAwarenessForWindow(new IntPtr(0xDEADBEEF));
            Assert.True(Enum.IsDefined(typeof(EffectiveDpiAwareness), a));
        }
    }
}
