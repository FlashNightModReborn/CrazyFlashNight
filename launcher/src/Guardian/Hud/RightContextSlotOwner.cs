namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 右侧条件槽的封闭 owner 集合。数值顺序不是优先级合同；
    /// 唯一优先级仲裁由 NativeHudOverlay.ResolveAndProjectRightContextSlotOwner 完成。
    /// </summary>
    public enum RightContextSlotOwner
    {
        Hidden = 0,
        ContextHint = 1,
        ActionableNotice = 2,
        TransactionDecision = 3
    }
}
