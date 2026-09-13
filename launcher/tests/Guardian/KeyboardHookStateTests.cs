using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class KeyboardHookStateTests
    {
        [Fact]
        public void IndependentGuardRequiresMatchingParentExecutableAndCoreModule()
        {
            string mvid = typeof(KeyboardHook).Assembly.ManifestModule.ModuleVersionId.ToString("D");
            Assert.True(HotkeyGuard.IsMatchingParent("C:\\candidate\\Core.exe", "c:\\candidate\\core.exe", mvid));
            Assert.False(HotkeyGuard.IsMatchingParent("C:\\old\\Core.exe", "C:\\candidate\\Core.exe", mvid));
            Assert.False(HotkeyGuard.IsMatchingParent("C:\\candidate\\Core.exe", "C:\\candidate\\Core.exe", Guid.NewGuid().ToString("D")));
            Assert.Equal(1, HotkeyGuard.Run(new string[0]));
            Assert.Equal(1, HotkeyGuard.Run(new[] { "0", mvid, "unexpected" }));
        }

        private static bool Edge(KeyboardHook hook, uint vk, bool down)
        {
            IntPtr data = Marshal.AllocHGlobal(24);
            try
            {
                for (int offset = 0; offset < 24; offset += 4) Marshal.WriteInt32(data, offset, 0);
                Marshal.WriteInt32(data, unchecked((int)vk));
                return hook.ProcessKeyEdge(down ? 0x100 : 0x101, data) != IntPtr.Zero;
            }
            finally { Marshal.FreeHGlobal(data); }
        }

        [Fact]
        public void TwoControlKeysAndLostReleaseDoNotBlockOrdinaryW()
        {
            var physical = new HashSet<int>();
            using (var hook = new KeyboardHook())
            {
                hook.ReadAsyncKeyState = vk => physical.Contains(vk) ? unchecked((short)0x8000) : (short)0;
                hook.LiveForegroundProbeForTests = () => true;
                hook.SetActivationProbe(() => true);
                Edge(hook, 0xA2, true); physical.Add(0xA2);
                Edge(hook, 0xA3, true); physical.Add(0xA3);
                Edge(hook, 0xA2, false); physical.Remove(0xA2);
                Assert.True(Edge(hook, 0x57, true));
                Assert.True(Edge(hook, 0x57, false));
                // 在外部应用丢掉右 Ctrl up 回调；下一普通键以前一边沿物理状态修正。
                physical.Remove(0xA3);
                Assert.False(Edge(hook, 0x57, true));
                Assert.False(Edge(hook, 0x57, false));
                Assert.False(Edge(hook, 0x52, true));
            }
        }

        [Fact]
        public void ConsumedDialogueDownDoesNotNeedOsKeyStateAndPairsWithUp()
        {
            int advances = 0;
            using (var hook = new KeyboardHook())
            {
                // 被 hook 消费的 down 在 OS 中仍可能是 up；不能因此解除长按去重。
                hook.ReadAsyncKeyState = _ => 0;
                hook.LiveForegroundProbeForTests = () => true;
                hook.SetDialogueKeyProbe(vk => vk == 0x20 ? () => Interlocked.Increment(ref advances) : null);
                Assert.True(Edge(hook, 0x20, true));
                Assert.True(SpinWait.SpinUntil(() => Volatile.Read(ref advances) == 1, 2000));
                for (int i = 0; i < 10; i++) Assert.True(Edge(hook, 0x20, true));
                Assert.Equal(1, Volatile.Read(ref advances));
                Assert.True(Edge(hook, 0x20, false));
                Assert.True(Edge(hook, 0x20, true));
                Assert.True(SpinWait.SpinUntil(() => Volatile.Read(ref advances) == 2, 2000));
                hook.SetDialogueKeyProbe(null);
                Assert.True(Edge(hook, 0x20, false));
                Assert.False(Edge(hook, 0x20, true));
            }
        }
    }
}
