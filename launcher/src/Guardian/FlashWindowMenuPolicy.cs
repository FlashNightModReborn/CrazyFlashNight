using System;

namespace CF7Launcher.Guardian
{
    internal interface IFlashMenuWindowApi
    {
        IntPtr GetMenu(IntPtr window);
        bool DetachMenu(IntPtr window);
        bool DestroyMenu(IntPtr menu);
    }

    internal static class FlashWindowMenuPolicy
    {
        private const int WmSysCommand = 0x0112;
        private const long ScKeyMenu = 0xF100;
        private const int WsChild = 0x40000000;
        private const int WsCaption = 0x00C00000;
        private const int WsThickFrame = 0x00040000;
        private const int WsSysMenu = 0x00080000;

        internal static bool SuppressBareMenuActivation(int message, IntPtr command, IntPtr character)
        {
            // 裸 Alt / F10 没有菜单字符；保留 Alt+Space、菜单助记符和 SC_CLOSE 等其他命令。
            return message == WmSysCommand
                && (command.ToInt64() & 0xFFF0) == ScKeyMenu
                && character == IntPtr.Zero;
        }

        internal static int EmbeddedStyle(int style)
        {
            // WS_CAPTION 已包含 WS_BORDER；隐藏标题栏也必须清除独立的系统菜单位。
            return (style & ~(WsCaption | WsThickFrame | WsSysMenu)) | WsChild;
        }

        internal static bool RemoveMenuBeforeChildStyle(
            IntPtr window, int originalStyle, IFlashMenuWindowApi api)
        {
            // GetMenu 对子窗口返回值未定义。重新嵌入时不能把 child ID 当菜单句柄销毁。
            if ((originalStyle & WsChild) != 0)
                return true;

            IntPtr menu = api.GetMenu(window);
            if (menu == IntPtr.Zero)
                return true;

            // 只有窗口已放弃菜单所有权，才可销毁它；失败时由调用者记录 Win32 错误。
            if (!api.DetachMenu(window))
                return false;

            return api.DestroyMenu(menu);
        }
    }
}
