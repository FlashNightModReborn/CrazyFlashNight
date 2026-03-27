using System;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 已废弃：低级钩子方案被 RegisterHotKey 替代。
    /// 保留文件避免 csproj 编译错误。
    /// </summary>
    public class KeyboardHook : IDisposable
    {
        public void Dispose() { }
    }
}
