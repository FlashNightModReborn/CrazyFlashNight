using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class FlashWindowMenuPolicyTests
    {
        [Theory]
        [InlineData(0x0112, 0xF100, 0, true)]
        [InlineData(0x0112, 0xF10F, 0, true)] // 系统保留的低四位不改变命令。
        [InlineData(0x0112, 0xF100, 32, false)] // Alt+Space。
        [InlineData(0x0112, 0xF100, 'f', false)] // Alt+字母。
        [InlineData(0x0112, 0xF060, 0, false)] // 关闭。
        [InlineData(0x0112, 0xF060, 1, false)] // Alt+F4 的系统命令。
        [InlineData(0x0112, 0xF040, 0, false)] // 切换窗口。
        [InlineData(0x0112, 0xF090, 0, false)] // 鼠标菜单。
        [InlineData(0x0104, 0x12, 0, false)] // 原始 Alt 按下。
        [InlineData(0x0105, 0x12, 0, false)] // 原始 Alt 松开。
        [InlineData(0x0100, 0xF100, 0, false)]
        public void BareMenuFilterPreservesOtherInput(int message, int command, int character, bool blocked)
        {
            Assert.Equal(blocked, FlashWindowMenuPolicy.SuppressBareMenuActivation(
                message, new IntPtr(command), new IntPtr(character)));
        }

        [Fact]
        public void EmbeddedStyleRemovesMenuAndFrameButPreservesOtherState()
        {
            const int frameAndMenu = 0x00CC0000;
            const int unrelated = 0x10000000 | 0x02000000 | 0x04000000 | 0x00030000;
            int expected = unrelated | 0x40000000;
            Assert.Equal(expected, FlashWindowMenuPolicy.EmbeddedStyle(frameAndMenu | unrelated));
            Assert.Equal(expected, FlashWindowMenuPolicy.EmbeddedStyle(expected));
        }

        [Fact]
        public void ReembeddingNeverQueriesOrDestroysAChildMenuIdentifier()
        {
            var api = new MenuApi();
            Assert.True(FlashWindowMenuPolicy.RemoveMenuBeforeChildStyle(new IntPtr(1), 0x40080000, api));
            Assert.Empty(api.Calls);
        }

        [Fact]
        public void MenuIsDetachedBeforeItIsDestroyed()
        {
            var api = new MenuApi();
            Assert.True(FlashWindowMenuPolicy.RemoveMenuBeforeChildStyle(new IntPtr(1), 0x00CF0000, api));
            Assert.Equal(new[] { "get", "detach", "destroy" }, api.Calls);
        }

        [Fact]
        public void DetachFailurePreservesTheStillOwnedMenu()
        {
            var api = new MenuApi { DetachResult = false };
            Assert.False(FlashWindowMenuPolicy.RemoveMenuBeforeChildStyle(new IntPtr(1), 0x00CF0000, api));
            Assert.Equal(new[] { "get", "detach" }, api.Calls);
        }

        [Fact]
        public void MissingMenuRequiresNoMutation()
        {
            var api = new MenuApi { Menu = IntPtr.Zero };
            Assert.True(FlashWindowMenuPolicy.RemoveMenuBeforeChildStyle(new IntPtr(1), 0x00CF0000, api));
            Assert.Equal(new[] { "get" }, api.Calls);
        }

        [Fact]
        public void DestroyFailureIsReportedAfterSuccessfulDetach()
        {
            var api = new MenuApi { DestroyResult = false };
            Assert.False(FlashWindowMenuPolicy.RemoveMenuBeforeChildStyle(new IntPtr(1), 0x00CF0000, api));
            Assert.Equal(new[] { "get", "detach", "destroy" }, api.Calls);
        }

        [Theory]
        [InlineData("hidden")]
        [InlineData("embed")]
        public void ProductionEmbeddingCleansARealWin32WindowAndIsSafeToRepeat(string phase)
        {
            IntPtr host = IntPtr.Zero, flash = IntPtr.Zero, menu = IntPtr.Zero;
            try
            {
                host = CreateWindowExW(0, "STATIC", "CF7 menu test host", 0x00CF0000,
                    0, 0, 32, 32, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                flash = CreateWindowExW(0, "STATIC", "CF7 menu test child", 0x00CF0000,
                    0, 0, 32, 32, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                Assert.NotEqual(IntPtr.Zero, host);
                Assert.NotEqual(IntPtr.Zero, flash);
                menu = CreateMenu();
                Assert.NotEqual(IntPtr.Zero, menu);
                Assert.True(AppendMenuW(menu, 0, new UIntPtr(1), "测试菜单"));
                Assert.True(SetMenu(flash, menu));

                WindowManager.ApplyFlashChildStyle(flash, phase);
                Assert.False(IsMenu(menu));
                menu = IntPtr.Zero;
                SetParent(flash, host);
                Assert.Equal(host, GetParent(flash));
                Assert.Equal(0, GetWindowLongW(flash, -16) & 0x00CC0000);
                Assert.NotEqual(0, GetWindowLongW(flash, -16) & 0x40000000);

                // 子窗口 ID 与菜单共用 GWL_ID 槽；重嵌入必须保留它且不销毁同值有效菜单。
                menu = CreateMenu();
                Assert.NotEqual(IntPtr.Zero, menu);
                SetWindowLongPtrW(flash, -12, menu);
                WindowManager.ApplyFlashChildStyle(flash, "embed");
                Assert.Equal(menu, GetWindowLongPtrW(flash, -12));
                Assert.True(IsMenu(menu));
            }
            finally
            {
                if (flash != IntPtr.Zero) DestroyWindow(flash);
                if (host != IntPtr.Zero) DestroyWindow(host);
                if (menu != IntPtr.Zero && IsMenu(menu)) DestroyMenu(menu);
            }
        }

        private sealed class MenuApi : IFlashMenuWindowApi
        {
            internal readonly List<string> Calls = new List<string>();
            internal IntPtr Menu = new IntPtr(2);
            internal bool DetachResult = true, DestroyResult = true;
            public IntPtr GetMenu(IntPtr window) { Calls.Add("get"); return Menu; }
            public bool DetachMenu(IntPtr window) { Calls.Add("detach"); return DetachResult; }
            public bool DestroyMenu(IntPtr menu) { Assert.Equal(Menu, menu); Calls.Add("destroy"); return DestroyResult; }
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateWindowExW(int exStyle, string className, string name, int style,
            int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr window);
        [DllImport("user32.dll")] private static extern IntPtr CreateMenu();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool AppendMenuW(IntPtr menu, uint flags, UIntPtr id, string text);
        [DllImport("user32.dll")] private static extern bool SetMenu(IntPtr window, IntPtr menu);
        [DllImport("user32.dll")] private static extern bool IsMenu(IntPtr menu);
        [DllImport("user32.dll")] private static extern bool DestroyMenu(IntPtr menu);
        [DllImport("user32.dll")] private static extern IntPtr SetParent(IntPtr window, IntPtr parent);
        [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr window);
        [DllImport("user32.dll")] private static extern int GetWindowLongW(IntPtr window, int index);
        [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtrW(IntPtr window, int index);
        [DllImport("user32.dll")] private static extern IntPtr SetWindowLongPtrW(IntPtr window, int index, IntPtr value);
    }
}
