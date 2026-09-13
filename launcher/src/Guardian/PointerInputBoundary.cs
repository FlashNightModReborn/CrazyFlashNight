namespace CF7Launcher.Guardian
{
    /// <summary>GetMessageTime 与 Environment.TickCount 共用 32 位开机时钟。</summary>
    internal static class PointerInputBoundary
    {
        internal static bool IsCurrent(uint messageTime, uint boundary)
        {
            // 同一毫秒无法证明先后，拒绝歧义；允许跨 uint 环绕，不设慢操作阈值。
            return unchecked((int)(messageTime - boundary)) > 0;
        }
    }
}
