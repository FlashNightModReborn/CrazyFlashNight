using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using CF7Launcher.Guardian.InputOwnership;
using System.Threading;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class KeyboardHookStateTests
    {
        internal static bool Edge(KeyboardHook hook, uint vk, bool down)
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
        public void RefusedNativeInstallBlocksOrdinaryStartupWithoutGlobalHotkeys() => OnSta(() =>
        {
            int attempted = 0;
            using var form = new GuardianForm(null, false, "", false, true, false, false,
                new SessionInputAuthority(), () => new KeyboardHook(() =>
                {
                    Interlocked.Increment(ref attempted);
                    return (IntPtr.Zero, 5);
                }, null, 2000));
            Assert.Equal(1, Volatile.Read(ref attempted));
            Assert.Equal("native_install_failed win32=5", form.KeyboardStartupFailure);
            Assert.False(form.Visible);
            Assert.Null(form.GetPanelEscapeSource());
            Assert.Null(typeof(GuardianForm).GetMethod("RegisterHotKey", BindingFlags.NonPublic | BindingFlags.Static));
            Assert.Null(typeof(GuardianForm).GetMethod("UnregisterHotKey", BindingFlags.NonPublic | BindingFlags.Static));
        });

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void NonPlayerStartupDoesNotNeedKeyboardHook(bool worker) => OnSta(() =>
        {
            using var form = new GuardianForm(null, false, "", false, true, worker, false, null,
                () => throw new InvalidOperationException("A non-player route must not install the gameplay hook."));
            Assert.Null(form.KeyboardStartupFailure);
        });

        [Theory]
        [InlineData(true, true, "1", true)]
        [InlineData(false, true, "1", false)]
        [InlineData(true, false, "1", false)]
        [InlineData(true, true, "true", false)]
        [InlineData(true, true, null, false)]
        public void OnlyExplicitIsolatedLegacyProbeCanStartWithoutPhysicalKeyboard(bool isolated, bool legacy, string noWgc, bool expected)
            => Assert.Equal(expected, global::Program.IsKeyboardlessPassiveProbe(isolated, legacy, noWgc));

        [Fact]
        public void InstallTimeoutReleasesLateNativeHandleWithoutPublishingIt()
        {
            using var entered = new ManualResetEventSlim();
            using var finishNativeCall = new ManualResetEventSlim();
            using var released = new ManualResetEventSlim();
            var expected = new IntPtr(24);
            IntPtr actual = IntPtr.Zero;
            int owner = 0, disposer = 0;
            using var hook = new KeyboardHook(() =>
            {
                owner = Environment.CurrentManagedThreadId;
                entered.Set();
                if (!finishNativeCall.Wait(5000)) return (IntPtr.Zero, 5);
                return (expected, 0);
            }, handle =>
            {
                actual = handle;
                disposer = Environment.CurrentManagedThreadId;
                released.Set();
            }, 450);
            Task<bool> result = Task.Run(hook.Install);
            try
            {
                Assert.True(entered.Wait(2500));
                Assert.True(result.Wait(2500));
                Assert.False(result.Result);
                Assert.Equal("install_timeout", hook.InstallFailure);
                Assert.False(hook.IsInstalled);
            }
            finally { finishNativeCall.Set(); }
            Assert.True(released.Wait(2500));
            Assert.Equal(expected, actual);
            Assert.Equal(owner, disposer);
            Assert.False(hook.IsInstalled);
        }

        [Fact]
        public void HealthyHookLivesUntilItsOwningThreadStops()
        {
            int installedBy = 0, releasedBy = 0;
            var handle = new IntPtr(31);
            IntPtr released = IntPtr.Zero;
            using var hook = new KeyboardHook(() =>
            {
                installedBy = Environment.CurrentManagedThreadId;
                return (handle, 0);
            }, native =>
            {
                releasedBy = Environment.CurrentManagedThreadId;
                released = native;
            }, 2000);
            Assert.True(hook.Install());
            Assert.True(hook.IsInstalled);
            Assert.Null(hook.InstallFailure);
            hook.Dispose();
            Assert.False(hook.IsInstalled);
            Assert.Equal(handle, released);
            Assert.Equal(installedBy, releasedBy);
        }

        [Theory]
        [InlineData(0x46u)]
        [InlineData(0x51u)]
        public void LosingExactForegroundPassesThroughShortcutsAndDropsQueuedAction(uint vk)
        {
            var authority = new SessionInputAuthority();
            authority.SetForeground(true);
            bool exactForeground = true;
            bool ctrlHeld = false;
            Action pending = null;
            int actions = 0;
            using var hook = new KeyboardHook();
            hook.BindPassiveInput(authority, () => exactForeground, action => pending = action);
            hook.ReadAsyncKeyState = key => key == 0xA2 && ctrlHeld ? unchecked((short)0x8000) : (short)0;
            hook.RegisterAction(vk, () => ++actions);
            Assert.False(Edge(hook, 0xA2, true));
            ctrlHeld = true;
            Assert.True(Edge(hook, vk, true));
            Assert.NotNull(pending);
            exactForeground = false;
            Assert.False(Edge(hook, vk, false));
            pending();
            Assert.False(Edge(hook, vk, true));
            Assert.False(Edge(hook, vk, false));
            Assert.Equal(0, actions);
            Assert.False(authority.ForegroundEligible);
        }

        private static void OnSta(Action body)
        {
            Exception failure = null;
            var thread = new Thread(() =>
            {
                try { body(); }
                catch (Exception error) { failure = error; }
            }) { IsBackground = true };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(5000));
            if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
        }

        [Fact]
        public void TwoControlKeysAndLostReleaseDoNotBlockOrdinaryW()
        {
            var physical = new HashSet<int>();
            using (var hook = new KeyboardHook())
            {
                hook.ReadAsyncKeyState = vk => physical.Contains(vk) ? unchecked((short)0x8000) : (short)0;
                hook.LiveForegroundProbeForTests = () => true;
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
